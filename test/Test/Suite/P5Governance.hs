{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.P5Governance
  ( p5GovernanceTests
  ) where

import qualified Data.Text as T
import Test.HUnit

import QxFx0.Runtime.Session
  ( governanceSummaryLines
  , governanceAuthorityStatus
  )
import QxFx0.Types.Observability (TruthContractStatus(..))
import QxFx0.Self.Conatus
  ( ConatusComponents(..)
  , ConatusEnergy(..)
  )
import QxFx0.Self.Field
  ( defaultFieldHeuristics
  , FieldHeuristics(..)
  , emptyField
  )
import QxFx0.Self.Perspective
  ( applyPerspectiveDecision
  , applyPerspectiveOperator
  , buildActivePerspectiveProjections
  , buildPerspectiveProjection
  , opinionCore
  )
import QxFx0.Governance.Replay
  ( rebuildGovernanceProjection
  , governanceReplayProof
  , rebuildGovernedPerspectiveState
  , rebuildGovernedSystemState
  , verifyPerspectiveRegistryRebuild
  )
import QxFx0.Types.State.Governance
  ( CarryPayload(..)
  , CapabilityEvidence(..)
  , CapabilityPayload(..)
  , ClaimStancePayload(..)
  , FreezePayload(..)
  , FreezeScope(..)
  , GovernanceActor(..)
  , GovernanceArchiveContract(..)
  , GovernanceDataClass(..)
  , GovernanceDecision(..)
  , GovernanceEvent(..)
  , GovernanceEventEnvelope(..)
  , GovernanceEventId(..)
  , GovernanceLifecycleStatus(..)
  , GovernancePayload(..)
  , GovernancePermission(..)
  , GovernedProjectionRef(..)
  , GovernanceProvenanceLink(..)
  , GovernanceReplayOrderingContract(..)
  , GovernanceReason(..)
  , GovernanceRef(..)
  , GovernanceSchemaEvolutionContract(..)
  , GovernedSubject(..)
  , NormativeRevisionPayload(..)
  , buildPerspectiveGovernanceEvent
  , appendGovernanceEventToHistory
  , normalizeGovernanceEventChecked
  , currentGovernancePayloadVersion
  , currentGovernanceSchemaVersion
  , currentEvaluatorVersion
  , currentProjectionVersion
  , currentReducerVersion
  , defaultGovernanceArchiveContract
  , defaultGovernanceReplayOrderingContract
  , defaultGovernanceSchemaEvolutionContract
  , governanceDeterminismBoundary
  , governancePermission
  , governanceProjectionChecksum
  , gpActivePerspectiveProjections
  , gpGovernedRefs
  , gpMeta
  , gpPerspectiveRegistry
  , gpProjectionChecksum
  , validateGovernanceEventContract
  )
import QxFx0.Types.State.Perspective
  ( ClaimStanceRef(..)
  , ConatusSlice(..)
  , CounterargumentRef(..)
  , EvidenceRef(..)
  , IdentitySlice(..)
  , NormativeProfile
  , PerspectiveAdmissibility(..)
  , PerspectiveCandidate(..)
  , PerspectiveId(..)
  , PerspectiveInputBundle(..)
  , PerspectivePromotionDecision(..)
  , PerspectiveRegistry
  , PerspectiveRevisionRecord
  , PerspectiveScope(..)
  , defaultNormativeProfile
  , defaultPerspectiveRegistry
  )
import QxFx0.Types.State
  ( emptySystemState
    , ssAdaptiveMutationLog
    , ssGovernanceHistory
    , ssGovernanceProjection
    , ssGovernanceRuntimeFault
  , ssTruthContractStatus
  , ssSelfState
  )
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Types.State.Governance (EpistemicStatus(..))
import QxFx0.Core.TurnPipeline
  ( PrepareEffectPlan(..)
  , PrepareStatic(..)
  , buildPrepareEffectPlan
  )
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime(..))

p5GovernanceTests :: [Test]
p5GovernanceTests =
  [ TestLabel "P5 event envelope preserves explicit intent/outcome split" testIntentOutcomeSplit
  , TestLabel "P5 append is idempotent for identical event id and rejects semantic conflict" testAppendIdempotenceAndConflict
  , TestLabel "P5 append fails closed on broken hash chain or ordering" testAppendFailsClosedOnBrokenChain
  , TestLabel "P5 perspective operator keeps derived state unchanged when canonical append fails" testPerspectiveOperatorAtomicOnAppendFailure
  , TestLabel "P5 deterministic rebuild reproduces governed perspective registry" testDeterministicPerspectiveRebuild
  , TestLabel "P5 rebuild verification rejects derived registry mismatches" testRebuildVerificationGuard
  , TestLabel "P5 replay is independent of input order but ordered by sequence/partition/id" testCanonicalOrdering
  , TestLabel "P5 system-state rebuild derives registry from canonical history" testSystemStateRebuildsDerivedRegistry
  , TestLabel "P5 system-state rebuild fails closed under non-authoritative truth" testSystemStateReplayFailsClosedWhenTruthNonAuthoritative
  , TestLabel "P5 governance authority status fails closed on non-authoritative truth" testGovernanceAuthorityStatusFailsClosedOnNonAuthoritativeTruth
  , TestLabel "P5 lifecycle-sensitive ref validation follows deny/promote/rollback contracts" testLifecycleSensitiveRefValidation
  , TestLabel "P5 denied perspective event is replay-visible without endorsing state" testDeniedPathReplay
  , TestLabel "P5 rollback path is replay-visible and restores prior projection" testRollbackPathReplay
  , TestLabel "P5 typed non-perspective paths remain replay-visible in projection refs" testTypedNonPerspectiveReplayPreservesProjection
  , TestLabel "P5 perspective replay rejects envelope payload decision mismatch" testPerspectiveReplayRejectsDecisionMismatch
  , TestLabel "P5 governance summary exposes operator-visible evidence" testGovernanceSummaryVisibility
  , TestLabel "P5 governance fingerprint canonicalizes history" testGovernanceFingerprintCanonicalizesHistory
  , TestLabel "P5 replay proof exposes canonical provenance trail" testReplayProofExposesCanonicalProvenance
  , TestLabel "P5 prepare path keeps field heuristics non-governing" testPreparePathUsesDefaultFieldHeuristics
  , TestLabel "P5 deny-first permissions protect privileged actions" testDenyFirstPermissions
  , TestLabel "P5 contracts expose schema, ordering, determinism boundary, and archive rules" testGovernanceContracts
  ]

testIntentOutcomeSplit :: Test
testIntentOutcomeSplit = TestCase $ do
  let bundle = mkPerspectiveBundle 1 [] [] [] defaultNormativeProfile []
      candidate = opinionCore bundle
      eventWithIntent = buildPerspectiveGovernanceEvent
        ActorRuntime
        1
        "session-p5"
        Nothing
        defaultPerspectiveRegistry
        defaultPerspectiveRegistry
        bundle
        candidate
        (PerspectiveInadmissible "insufficient_evidence")
        (Just PpdPromoteEndorsed)
        PpdObserveOnly
        Nothing
      eventWithoutIntent = buildPerspectiveGovernanceEvent
        ActorRuntime
        2
        "session-p5"
        (Just eventWithIntent)
        defaultPerspectiveRegistry
        defaultPerspectiveRegistry
        bundle
        candidate
        (PerspectiveInadmissible "insufficient_evidence")
        Nothing
        PpdObserveOnly
        Nothing
      envelope = geEnvelope eventWithIntent
      absentEnvelope = geEnvelope eventWithoutIntent
  assertEqual "requested decision records the considered intent"
    (Just GovPromote)
    (geeRequestedDecision envelope)
  assertEqual "resolved decision records canonical denial outcome"
    (Just GovDeny)
    (geeResolvedDecision envelope)
  assertEqual "canonical decision follows resolved outcome"
    GovDeny
    (geeDecision envelope)
  assertEqual "denied lifecycle is explicit"
    GlsDenied
    (geeLifecycleStatus envelope)
  assertEqual "requested decision can remain absent when intent was absent"
    Nothing
    (geeRequestedDecision absentEnvelope)
  assertBool "before_ref is mandatory" (geeBeforeRef envelope /= Nothing)
  assertBool "after_ref is mandatory" (geeAfterRef envelope /= Nothing)
  assertBool "effect_ref is mandatory" (geeEffectRef envelope /= Nothing)
  assertEqual "typed contract validates" (Right ()) (validateGovernanceEventContract eventWithIntent)
  assertEqual "absent intent still validates" (Right ()) (validateGovernanceEventContract eventWithoutIntent)

testAppendIdempotenceAndConflict :: Test
testAppendIdempotenceAndConflict = TestCase $ do
  let (event, _) = promotionEvent 1 Nothing
  case appendGovernanceEventToHistory event [] of
    Left err -> assertFailure ("initial append failed: " <> T.unpack err)
    Right history1 -> do
      assertEqual "initial append stores one event" 1 (length history1)
      assertEqual "duplicate append is idempotent" (Right history1) (appendGovernanceEventToHistory event history1)
      let conflicting = event
            { geEnvelope = (geEnvelope event)
                { geeReason = GovernanceReason "conflicting_duplicate" ["same id, changed reason"]
                , geeEventHash = Nothing
                , geePayloadHash = Nothing
                }
            }
      case appendGovernanceEventToHistory conflicting history1 of
        Left _ -> pure ()
        Right _ -> assertFailure "conflicting duplicate unexpectedly accepted"

testAppendFailsClosedOnBrokenChain :: Test
testAppendFailsClosedOnBrokenChain = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
      (event2, _) = revisionEvent 2 (Just event1) registry1
      firstWithPrevHash = event1
        { geEnvelope = (geEnvelope event1)
            { geePrevHash = Just "fnv1a64:unexpected"
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
      event2WrongPrev = event2
        { geEnvelope = (geEnvelope event2)
            { geePrevHash = Just "fnv1a64:wrong"
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
      event2NonMonotonic = event2
        { geEnvelope = (geEnvelope event2)
            { geeSequenceNo = 1
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
  assertLeft "first canonical event cannot carry prev_hash" (appendGovernanceEventToHistory firstWithPrevHash [])
  history1 <- assertRight (appendGovernanceEventToHistory event1 [])
  assertLeft "append rejects wrong prev_hash" (appendGovernanceEventToHistory event2WrongPrev history1)
  assertLeft "append rejects non-monotonic sequence" (appendGovernanceEventToHistory event2NonMonotonic history1)

testPerspectiveOperatorAtomicOnAppendFailure :: Test
testPerspectiveOperatorAtomicOnAppendFailure = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
      (event2, _) = revisionEvent 2 (Just event1) registry1
      brokenHistory =
        [ event1
        , event2
            { geEnvelope = (geEnvelope event2)
                { geePrevHash = Just "fnv1a64:wrong"
                , geeEventHash = Nothing
                , geePayloadHash = Nothing
                }
            }
        ]
      before = emptySystemState
        { ssGovernanceHistory = brokenHistory
        , ssSelfState = (ssSelfState emptySystemState)
            { selfPerspectiveRegistry = registry1 }
        }
      after = applyPerspectiveOperator before positiveConatus False emptyField
  assertEqual "append failure leaves canonical history unchanged"
    (ssGovernanceHistory before)
    (ssGovernanceHistory after)
  assertEqual "append failure leaves derived registry unchanged"
    (selfPerspectiveRegistry (ssSelfState before))
    (selfPerspectiveRegistry (ssSelfState after))
  assertEqual "append failure leaves adaptive mutation log unchanged"
    (ssAdaptiveMutationLog before)
    (ssAdaptiveMutationLog after)
  assertBool "append failure surfaces governance runtime fault"
    (ssGovernanceRuntimeFault after /= Nothing)

testDeterministicPerspectiveRebuild :: Test
testDeterministicPerspectiveRebuild = TestCase $ do
  let (event, expectedRegistry) = promotionEvent 1 Nothing
  projection1 <- assertRight (rebuildGovernanceProjection [event])
  projection2 <- assertRight (rebuildGovernanceProjection [event])
  assertEqual "rebuilt registry must match direct P4 application"
    expectedRegistry
    (gpPerspectiveRegistry projection1)
  assertEqual "same history + versions must produce same projection"
    projection1
    projection2
  assertEqual "projection checksum is deterministic equality criterion"
    (gpProjectionChecksum projection1)
    (governanceProjectionChecksum (gpMeta projection1) (gpPerspectiveRegistry projection1) (gpActivePerspectiveProjections projection1) (gpGovernedRefs projection1))

testRebuildVerificationGuard :: Test
testRebuildVerificationGuard = TestCase $ do
  let (event, expectedRegistry) = promotionEvent 1 Nothing
  rebuilt <- assertRight (verifyPerspectiveRegistryRebuild [event] expectedRegistry)
  assertEqual "verified rebuild returns canonical registry" expectedRegistry rebuilt
  assertLeft "mismatched live registry fails closed"
    (verifyPerspectiveRegistryRebuild [event] defaultPerspectiveRegistry)

testCanonicalOrdering :: Test
testCanonicalOrdering = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
      (event2, expectedRegistry) = revisionEvent 2 (Just event1) registry1
  rebuiltForward <- assertRight (rebuildGovernedPerspectiveState [event1, event2])
  rebuiltShuffled <- assertRight (rebuildGovernedPerspectiveState [event2, event1])
  assertEqual "forward replay matches expected registry" expectedRegistry rebuiltForward
  assertEqual "shuffled import canonicalizes before replay" expectedRegistry rebuiltShuffled

testSystemStateRebuildsDerivedRegistry :: Test
testSystemStateRebuildsDerivedRegistry = TestCase $ do
  let (event, expectedRegistry) = promotionEvent 1 Nothing
      staleState = emptySystemState
        { ssSelfState = (ssSelfState emptySystemState)
            { selfPerspectiveRegistry = defaultPerspectiveRegistry }
        , ssGovernanceHistory = [event]
        , ssTruthContractStatus = CanonicalSurfacePreserved
        }
  assertBool "fixture has stale derived registry" (selfPerspectiveRegistry (ssSelfState staleState) /= expectedRegistry)
  rebuilt <- assertRight (rebuildGovernedSystemState staleState)
  assertEqual "canonical history is preserved" [event] (ssGovernanceHistory rebuilt)
  assertEqual "derived registry is rebuilt from canonical history" expectedRegistry (selfPerspectiveRegistry (ssSelfState rebuilt))

testSystemStateReplayFailsClosedWhenTruthNonAuthoritative :: Test
testSystemStateReplayFailsClosedWhenTruthNonAuthoritative = TestCase $ do
  case rebuildGovernedSystemState emptySystemState { ssTruthContractStatus = LegacyIncompleteSurface } of
    Left err -> assertBool "non-authoritative truth should fail closed" ("non_authoritative" `T.isInfixOf` err)
    Right _ -> assertFailure "rebuild should fail closed for non-authoritative truth"

testGovernanceAuthorityStatusFailsClosedOnNonAuthoritativeTruth :: Test
testGovernanceAuthorityStatusFailsClosedOnNonAuthoritativeTruth = TestCase $ do
  let status = governanceAuthorityStatus (emptySystemState { ssTruthContractStatus = LegacyIncompleteSurface }) "ok"
  assertEqual "non-authoritative truth must fail closed in operator summary" EpstNonAuthoritative status

testLifecycleSensitiveRefValidation :: Test
testLifecycleSensitiveRefValidation = TestCase $ do
  let (promote, _) = promotionEvent 1 Nothing
      deny = promote
        { geEnvelope = (geEnvelope promote)
            { geeId = GovernanceEventId "gov:session-p5:turn1:seq1:deny:sparse"
            , geeDecision = GovDeny
            , geeResolvedDecision = Just GovDeny
            , geeLifecycleStatus = GlsDenied
            , geeAfterRef = Nothing
            , geeEffectRef = Nothing
            , geeRollbackLink = Nothing
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
      promoteMissingAfter = promote
        { geEnvelope = (geEnvelope promote)
            { geeId = GovernanceEventId "gov:session-p5:turn1:seq1:promote:missing-after"
            , geeAfterRef = Nothing
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
      promoteMissingEffect = promote
        { geEnvelope = (geEnvelope promote)
            { geeId = GovernanceEventId "gov:session-p5:turn1:seq1:promote:missing-effect"
            , geeEffectRef = Nothing
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
      promoteMissingResolved = promote
        { geEnvelope = (geEnvelope promote)
            { geeId = GovernanceEventId "gov:session-p5:turn1:seq1:promote:missing-resolved"
            , geeResolvedDecision = Nothing
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
      rollbackMissingLink = promote
        { geEnvelope = (geEnvelope promote)
            { geeId = GovernanceEventId "gov:session-p5:turn1:seq1:rollback:missing-link"
            , geeDecision = GovRollback
            , geeResolvedDecision = Just GovRollback
            , geeLifecycleStatus = GlsRolledBack
            , geeRollbackLink = Nothing
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
      rollbackWithLink = rollbackMissingLink
        { geEnvelope = (geEnvelope rollbackMissingLink)
            { geeId = GovernanceEventId "gov:session-p5:turn1:seq1:rollback:with-link"
            , geeRollbackLink = Just (geeId (geEnvelope promote))
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
  assertEqual "deny can omit impossible after/effect refs while preserving resolved decision"
    (Right ())
    (validateGovernanceEventContract deny)
  assertLeft "promote requires after_ref" (validateGovernanceEventContract promoteMissingAfter)
  assertLeft "promote requires effect_ref" (validateGovernanceEventContract promoteMissingEffect)
  assertLeft "event requires resolved decision" (validateGovernanceEventContract promoteMissingResolved)
  assertLeft "rollback requires rollback_link" (validateGovernanceEventContract rollbackMissingLink)
  assertEqual "rollback validates when rollback_link is present"
    (Right ())
    (validateGovernanceEventContract rollbackWithLink)

testDeniedPathReplay :: Test
testDeniedPathReplay = TestCase $ do
  let bundle = mkPerspectiveBundle 1 [] [] [] defaultNormativeProfile []
      candidate = opinionCore bundle
      event = buildPerspectiveGovernanceEvent
        ActorRuntime
        1
        "session-p5"
        Nothing
        defaultPerspectiveRegistry
        defaultPerspectiveRegistry
        bundle
        candidate
        (PerspectiveInadmissible "insufficient_evidence")
        (Just PpdPromoteEndorsed)
        PpdObserveOnly
        Nothing
  registry <- assertRight (rebuildGovernedPerspectiveState [event])
  assertEqual "denied path advances no endorsed projections" [] (buildActivePerspectiveProjections registry)

testRollbackPathReplay :: Test
testRollbackPathReplay = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
      (event2, registry2) = revisionEvent 2 (Just event1) registry1
      bundle = mkPerspectiveBundleWithThesis 3 "rollback pressure"
      candidate = (opinionCore bundle) { pcCounterargumentPressure = 0.50 }
      registry3 = applyPerspectiveDecision 3 registry2 bundle candidate PpdRollbackPrior
      event3 = buildPerspectiveGovernanceEvent
        ActorRuntime
        3
        "session-p5"
        (Just event2)
        registry2
        registry3
        bundle
        candidate
        PerspectiveAdmissibleQuarantined
        (Just PpdRollbackPrior)
        PpdRollbackPrior
        (buildPerspectiveProjection registry3 (pibScope bundle))
      envelope = geEnvelope event3
  assertBool "rollback event carries rollback_link" (geeRollbackLink envelope /= Nothing)
  rebuilt <- assertRight (rebuildGovernedPerspectiveState [event1, event2, event3])
  assertEqual "rollback replay matches direct registry" registry3 rebuilt

testTypedNonPerspectiveReplayPreservesProjection :: Test
testTypedNonPerspectiveReplayPreservesProjection = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
  freeze <- assertRight (normalizeGovernanceEventChecked (linkEvent event1 freezeEventTemplate))
  carry <- assertRight (normalizeGovernanceEventChecked (linkEvent freeze carryEventTemplate))
  claim <- assertRight (normalizeGovernanceEventChecked (linkEvent carry claimStanceEventTemplate))
  capability <- assertRight (normalizeGovernanceEventChecked (linkEvent claim capabilityEventTemplate))
  normative <- assertRight (normalizeGovernanceEventChecked (linkEvent capability normativeRevisionEventTemplate))
  projection <- assertRight (rebuildGovernanceProjection [event1, freeze, carry, claim, capability, normative])
  assertEqual "all governed events remain replay-visible in projection refs"
    [ SubjectPerspective (PerspectiveId "perspective-1")
    , SubjectFreeze FreezeGlobal
    , SubjectCrossSessionCarry "carry:handoff"
    , SubjectClaimStance "claim:freedom"
    , SubjectCapability "capability:gf-map"
    , SubjectNormativeProfile "default"
    ]
    (map gprSubject (gpGovernedRefs projection))
  assertEqual "perspective registry should stay unchanged by foreign payloads"
    registry1
    (gpPerspectiveRegistry projection)
  mapM_
    (\(label, event) -> assertEqual label (Right ()) (validateGovernanceEventContract event))
    [ ("freeze event validates as typed payload", freeze)
    , ("carry event validates as typed payload", carry)
    , ("claim-stance event validates as typed payload", claim)
    , ("capability event validates as typed payload", capability)
    , ("normative revision event validates as typed payload", normative)
    ]

testPerspectiveReplayRejectsDecisionMismatch :: Test
testPerspectiveReplayRejectsDecisionMismatch = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
      bundle = mkPerspectiveBundleWithThesis 2 "mismatch"
      candidate = opinionCore bundle
      registry2 = applyPerspectiveDecision 2 registry1 bundle candidate PpdPromoteEndorsed
      event2 = buildPerspectiveGovernanceEvent
        ActorRuntime
        2
        "session-p5"
        (Just event1)
        registry1
        registry2
        bundle
        candidate
        PerspectiveAdmissibleAccepted
        (Just PpdPromoteEndorsed)
        PpdPromoteEndorsed
        (buildPerspectiveProjection registry2 (pibScope bundle))
      mismatched = event2
        { geEnvelope = (geEnvelope event2)
            { geeDecision = GovSuspend
            , geeResolvedDecision = Just GovSuspend
            , geeEventHash = Nothing
            , geePayloadHash = Nothing
            }
        }
  assertLeft "perspective replay must reject envelope/payload decision mismatch"
    (rebuildGovernedPerspectiveState [event1, mismatched])

testGovernanceSummaryVisibility :: Test
testGovernanceSummaryVisibility = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
  freeze <- assertRight (normalizeGovernanceEventChecked (linkEvent event1 freezeEventTemplate))
  projection <- assertRight (rebuildGovernanceProjection [event1, freeze])
  let ss = emptySystemState
        { ssGovernanceHistory = [event1, freeze]
        , ssSelfState = (ssSelfState emptySystemState)
            { selfPerspectiveRegistry = registry1 }
        , ssGovernanceProjection = projection
        , ssTruthContractStatus = CanonicalSurfacePreserved
        }
      summary = governanceSummaryLines ss
  assertLinePresent "summary exposes event count" "governance_events_count: 2" summary
  assertBool "summary exposes governance fingerprint"
    (any ("governance_fingerprint: " `T.isPrefixOf`) summary)
  assertLinePresent "summary exposes rebuild status" "governance_rebuild_status: ok" summary
  assertLinePresent "summary exposes active perspective count" "active_perspectives_count: 1" summary
  assertLinePresent "summary exposes denied count" "governance_denied_count: 0" summary
  assertLinePresent "summary exposes rollback count" "governance_rollback_count: 0" summary
  assertLinePresent "summary exposes stale count" "governance_stale_count: 0" summary
  assertLinePresent "summary exposes freeze status" "governance_freeze_status: frozen" summary
  assertLinePresent "summary exposes governance authority status" "governance_authority_status: authoritative" summary
  assertLinePresent "summary exposes governance runtime fault status" "governance_runtime_fault: none" summary
  assertLinePresent "summary exposes latest governed subject" "latest_governed_subject: SubjectFreeze FreezeGlobal" summary
  assertLinePresent "summary exposes latest governance reason tag" "latest_governance_reason_tag: freeze:entry" summary
  assertLinePresent "summary exposes salience/field contract status" "salience_field_contract_status: persisted_governing_default" summary
  assertLinePresent "summary exposes plan narrative tone contract status" "plan_narrative_tone_contract_status: bounded_causal_contour_policy" summary
  assertLinePresent "summary exposes bayesian contract status" "bayesian_contract_status: bounded_causal_contour_runtime_authoritative" summary

testReplayProofExposesCanonicalProvenance :: Test
testReplayProofExposesCanonicalProvenance = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
  freeze <- assertRight (normalizeGovernanceEventChecked (linkEvent event1 freezeEventTemplate))
  proof <- assertRight (governanceReplayProof [event1, freeze] registry1)
  assertEqual "replay proof preserves canonical event order"
    [geeId (geEnvelope event1), geeId (geEnvelope freeze)]
    (map gplEventId proof)
  assertEqual "replay proof exposes subject ancestry via parent refs"
    [ [], [geeId (geEnvelope event1)] ]
    (map gplParentRefs proof)
  assertEqual "replay proof exposes governance reason tags"
    ["perspective:GovPromote", "freeze:entry"]
    (map gplReasonTag proof)

testGovernanceFingerprintCanonicalizesHistory :: Test
testGovernanceFingerprintCanonicalizesHistory = TestCase $ do
  let (event1, registry1) = promotionEvent 1 Nothing
      (event2, _) = revisionEvent 2 (Just event1) registry1
      projection1 = case rebuildGovernanceProjection [event1, event2] of
        Right value -> value
        Left err -> error (T.unpack err)
      projection2 = case rebuildGovernanceProjection [event2, event1] of
        Right value -> value
        Left err -> error (T.unpack err)
      summaryForward = governanceSummaryLines emptySystemState
        { ssGovernanceHistory = [event1, event2]
        , ssSelfState = (ssSelfState emptySystemState)
            { selfPerspectiveRegistry = registry1 }
        , ssGovernanceProjection = projection1
        }
      summaryShuffled = governanceSummaryLines emptySystemState
        { ssGovernanceHistory = [event2, event1]
        , ssSelfState = (ssSelfState emptySystemState)
            { selfPerspectiveRegistry = registry1 }
        , ssGovernanceProjection = projection2
        }
      fingerprint lines' = case [ value | line <- lines', Just value <- [T.stripPrefix "governance_fingerprint: " line] ] of
        value:_ -> value
        [] -> ""
  assertEqual "canonical fingerprint must ignore raw list ordering"
    (fingerprint summaryForward)
    (fingerprint summaryShuffled)

testPreparePathUsesDefaultFieldHeuristics :: Test
testPreparePathUsesDefaultFieldHeuristics = TestCase $ do
  let customHeuristics = defaultFieldHeuristics { fhDefaultNarrativeRate = 0.99 }
      ss = emptySystemState
        { ssSelfState = (ssSelfState emptySystemState) { selfFieldHeuristics = customHeuristics }
        }
      plan = buildPrepareEffectPlan ss "что такое свобода" (UTCTime (fromGregorian 2026 1 1) 0)
  assertEqual "prepare path should thread persisted field heuristics"
    (selfFieldHeuristics (ssSelfState ss))
    (psFieldHeuristics (pepStatic plan))

testDenyFirstPermissions :: Test
testDenyFirstPermissions = TestCase $ do
  assertEqual "runtime cannot revise normative profile"
    (GovernanceDenied "runtime cannot revise normative profile")
    (governancePermission ActorRuntime (SubjectNormativeProfile "default") GovPromote)
  assertEqual "runtime cannot promote cross-session carry"
    (GovernanceDenied "runtime cannot promote cross-session carry")
    (governancePermission ActorRuntime (SubjectCrossSessionCarry "carry:key") GovPromote)
  assertEqual "runtime cannot promote capability updates"
    (GovernanceDenied "runtime cannot promote capability updates")
    (governancePermission ActorRuntime (SubjectCapability "capability:gf") GovPromote)
  assertEqual "operator can commit normative revision path"
    GovernanceAllowed
    (governancePermission ActorOperator (SubjectNormativeProfile "default") GovPromote)
  assertEqual "operator is still deny-first for unsupported actions"
    (GovernanceDenied "privileged action not explicitly allowed")
    (governancePermission ActorOperator (SubjectPerspective (PerspectiveId "p1")) GovFreeze)
  assertEqual "replay actor is read-only"
    (GovernanceDenied "replay actor is read-only")
    (governancePermission ActorReplayRebuild (SubjectPerspective (PerspectiveId "p1")) GovObserveOnly)

testGovernanceContracts :: Test
testGovernanceContracts = TestCase $ do
  assertEqual "current schema version is explicit" 1 currentGovernanceSchemaVersion
  assertEqual "current payload version is explicit" 1 currentGovernancePayloadVersion
  assertBool "schema contract exposes unsupported-version handling"
    (not (T.null (gsecUnsupportedVersionHandling defaultGovernanceSchemaEvolutionContract)))
  assertBool "ordering contract has total-order tie-break rule"
    ("sequence_no" `T.isInfixOf` grocTotalOrderTieBreakRule defaultGovernanceReplayOrderingContract)
  assertEqual "canonical history compaction is forbidden"
    False
    (gacCanonicalHistoryCompactionAllowed defaultGovernanceArchiveContract)
  assertEqual "determinism boundary classifies canonical history"
    (Just GdcCanonical)
    (lookup "canonical_history" governanceDeterminismBoundary)

promotionEvent :: Int -> Maybe GovernanceEvent -> (GovernanceEvent, PerspectiveRegistry)
promotionEvent sequenceNo previousEvent =
  let bundle = mkPerspectiveBundleWithThesis sequenceNo "initial promoted thesis"
      candidate = opinionCore bundle
      registry = applyPerspectiveDecision sequenceNo defaultPerspectiveRegistry bundle candidate PpdPromoteEndorsed
      event = buildPerspectiveGovernanceEvent
        ActorRuntime
        sequenceNo
        "session-p5"
        previousEvent
        defaultPerspectiveRegistry
        registry
        bundle
        candidate
        PerspectiveAdmissibleAccepted
        (Just PpdPromoteEndorsed)
        PpdPromoteEndorsed
        (buildPerspectiveProjection registry (pibScope bundle))
  in (event, registry)

revisionEvent :: Int -> Maybe GovernanceEvent -> PerspectiveRegistry -> (GovernanceEvent, PerspectiveRegistry)
revisionEvent sequenceNo previousEvent beforeRegistry =
  let bundle = mkPerspectiveBundleWithThesis sequenceNo "revised promoted thesis"
      candidate = opinionCore bundle
      registry = applyPerspectiveDecision sequenceNo beforeRegistry bundle candidate PpdReviseActive
      event = buildPerspectiveGovernanceEvent
        ActorRuntime
        sequenceNo
        "session-p5"
        previousEvent
        beforeRegistry
        registry
        bundle
        candidate
        PerspectiveAdmissibleAccepted
        (Just PpdReviseActive)
        PpdReviseActive
        (buildPerspectiveProjection registry (pibScope bundle))
  in (event, registry)

mkPerspectiveBundleWithThesis :: Int -> T.Text -> PerspectiveInputBundle
mkPerspectiveBundleWithThesis turn thesis =
  let evidence =
        [ EvidenceRef ("knowledge:" <> thesis)
        , EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"
        ]
      stance = [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
  in mkPerspectiveBundle turn evidence stance [] defaultNormativeProfile []

mkPerspectiveBundle
  :: Int
  -> [EvidenceRef]
  -> [ClaimStanceRef]
  -> [CounterargumentRef]
  -> NormativeProfile
  -> [PerspectiveRevisionRecord]
  -> PerspectiveInputBundle
mkPerspectiveBundle turn evidence stance counterarguments profile lineage = PerspectiveInputBundle
  { pibScope = ScopeTopic "freedom"
  , pibEvidence = evidence
  , pibStanceSlice = stance
  , pibIdentitySlice = IdentitySlice
      { isSessionId = "session-p5"
      , isIdentityClaims = []
      , isIdentityClaimCount = 0
      , isTurnCount = turn
      }
  , pibConatusSlice = ConatusSlice
      { csEnergy = 10.0
      , csGateFired = False
      , csFieldConfidence = 1.0
      , csStability = 1.0
      }
  , pibNormativeProfile = profile
  , pibCounterarguments = counterarguments
  , pibRevisionLineage = lineage
  }

linkEvent :: GovernanceEvent -> GovernanceEvent -> GovernanceEvent
linkEvent previous event =
  let previousEnvelope = geEnvelope previous
  in event
    { geEnvelope = (geEnvelope event)
        { geePrevHash = geeEventHash previousEnvelope
        , geeParentRefs = [geeId previousEnvelope]
        }
    }

freezeEventTemplate :: GovernanceEvent
freezeEventTemplate = GovernanceEvent
  { geEnvelope = baseEnvelope
      { geeId = GovernanceEventId "gov:session-p5:turn1:seq10:freeze:global"
      , geeActor = ActorOperator
      , geeSubject = SubjectFreeze FreezeGlobal
      , geeDecision = GovFreeze
      , geeRequestedDecision = Just GovFreeze
      , geeResolvedDecision = Just GovFreeze
      , geeLifecycleStatus = GlsCommitted
      , geeSequenceNo = 10
      , geePartitionId = "freeze"
      , geeReason = GovernanceReason "freeze:entry" ["budget exceeded"]
      , geeBeforeRef = Just (GovRefSnapshot "freeze:before")
      , geeAfterRef = Just (GovRefSnapshot "freeze:after")
      , geeEffectRef = Just (GovRefSnapshot "freeze:global")
      }
  , gePayload = GpFreeze FreezePayload
      { fpScope = FreezeGlobal
      , fpEntryReason = GovernanceReason "freeze:entry" ["budget exceeded"]
      , fpReleaseConditions = ["operator review", "cooldown elapsed"]
      , fpCooldownTurns = 3
      }
  }

carryEventTemplate :: GovernanceEvent
carryEventTemplate = GovernanceEvent
  { geEnvelope = baseEnvelope
      { geeId = GovernanceEventId "gov:session-p5:turn1:seq11:carry:handoff"
      , geeActor = ActorOperator
      , geeSubject = SubjectCrossSessionCarry "carry:handoff"
      , geeDecision = GovPromote
      , geeRequestedDecision = Just GovPromote
      , geeResolvedDecision = Just GovPromote
      , geeLifecycleStatus = GlsCommitted
      , geeSequenceNo = 11
      , geePartitionId = "carry"
      , geeReason = GovernanceReason "carry:handoff" ["operator approved"]
      , geeBeforeRef = Just (GovRefSnapshot "carry:before")
      , geeAfterRef = Just (GovRefSnapshot "carry:after")
      , geeEffectRef = Just (GovRefSnapshot "carry:handoff")
      }
  , gePayload = GpCarry CarryPayload
      { cpCarryKey = "carry:handoff"
      , cpSourceSession = Just "session-p5"
      , cpTargetSession = Just "session-p5-next"
      , cpEligibilityReason = GovernanceReason "carry:handoff" ["bounded handoff"]
      }
  }

claimStanceEventTemplate :: GovernanceEvent
claimStanceEventTemplate = GovernanceEvent
  { geEnvelope = baseEnvelope
      { geeId = GovernanceEventId "gov:session-p5:turn1:seq12:claim:stance"
      , geeActor = ActorOperator
      , geeSubject = SubjectClaimStance "claim:freedom"
      , geeDecision = GovPromote
      , geeRequestedDecision = Just GovPromote
      , geeResolvedDecision = Just GovPromote
      , geeLifecycleStatus = GlsCommitted
      , geeSequenceNo = 12
      , geePartitionId = "claim-stance"
      , geeReason = GovernanceReason "claim-stance:revision" ["strong evidence accepted"]
      , geeBeforeRef = Just (GovRefClaim "claim:freedom:before")
      , geeAfterRef = Just (GovRefClaim "claim:freedom:after")
      , geeEffectRef = Just (GovRefClaim "claim:freedom")
      }
  , gePayload = GpClaimStance ClaimStancePayload
      { cspClaimRef = "claim:freedom"
      , cspBefore = Just "contested"
      , cspAfter = Just "affirmed"
      , cspReason = GovernanceReason "claim-stance:revision" ["strong evidence accepted"]
      }
  }

capabilityEventTemplate :: GovernanceEvent
capabilityEventTemplate = GovernanceEvent
  { geEnvelope = baseEnvelope
      { geeId = GovernanceEventId "gov:session-p5:turn1:seq13:capability:gf-map"
      , geeActor = ActorOperator
      , geeSubject = SubjectCapability "capability:gf-map"
      , geeDecision = GovSuspend
      , geeRequestedDecision = Just GovSuspend
      , geeResolvedDecision = Just GovSuspend
      , geeLifecycleStatus = GlsCommitted
      , geeSequenceNo = 13
      , geePartitionId = "capability"
      , geeReason = GovernanceReason "capability:degrade" ["sandbox failures exceeded budget"]
      , geeBeforeRef = Just (GovRefCapability "capability:gf-map:normal")
      , geeAfterRef = Just (GovRefCapability "capability:gf-map:degraded")
      , geeEffectRef = Just (GovRefCapability "capability:gf-map")
      }
  , gePayload = GpCapability CapabilityPayload
      { cpCapabilityRef = "capability:gf-map"
      , cpScope = "render"
      , cpOperation = "linearize"
      , cpMode = "degraded"
      , cpBeforeConfidence = Just 0.82
      , cpAfterConfidence = 0.43
      , cpEvidence = CapabilityEvidence
          { ceObservedFailures = 3
          , ceSandboxFailures = 2
          , ceFreezeCount = 1
          , ceRollbackCount = 0
          , ceDegradedCount = 1
          }
      }
  }

normativeRevisionEventTemplate :: GovernanceEvent
normativeRevisionEventTemplate = GovernanceEvent
  { geEnvelope = baseEnvelope
      { geeId = GovernanceEventId "gov:session-p5:turn1:seq14:normative:default"
      , geeActor = ActorOperator
      , geeSubject = SubjectNormativeProfile "default"
      , geeDecision = GovPromote
      , geeRequestedDecision = Just GovPromote
      , geeResolvedDecision = Just GovPromote
      , geeLifecycleStatus = GlsCommitted
      , geeSequenceNo = 14
      , geePartitionId = "normative"
      , geeReason = GovernanceReason "normative:revision" ["offline governance approved"]
      , geeBeforeRef = Just (GovRefSnapshot "normative:default:v1")
      , geeAfterRef = Just (GovRefSnapshot "normative:default:v2")
      , geeEffectRef = Just (GovRefSnapshot "normative:default")
      }
  , gePayload = GpNormativeRevision NormativeRevisionPayload
      { nrpProfileId = "default"
      , nrpVersionId = 2
      , nrpRevisionPolicy = "operator-reviewed"
      , nrpAuditReason = GovernanceReason "normative:revision" ["offline governance approved"]
      }
  }

baseEnvelope :: GovernanceEventEnvelope
baseEnvelope = GovernanceEventEnvelope
  { geeId = GovernanceEventId "gov:base"
  , geeSchemaVersion = currentGovernanceSchemaVersion
  , geePayloadVersion = currentGovernancePayloadVersion
  , geeLifecycleStatus = GlsCommitted
  , geeSubject = SubjectClaimStance "base"
  , geeActor = ActorOperator
  , geeTurnId = Just 1
  , geeSessionId = Just "session-p5"
  , geeStreamId = "governance:session-p5"
  , geePartitionId = "base"
  , geeSequenceNo = 1
  , geeParentRefs = []
  , geeDecision = GovObserveOnly
  , geeRequestedDecision = Just GovObserveOnly
  , geeResolvedDecision = Just GovObserveOnly
  , geeReason = GovernanceReason "base" []
  , geeNormativeProfileVersion = Just 1
  , geeProjectionVersion = currentProjectionVersion
  , geeReducerVersion = currentReducerVersion
  , geeNormativeEvaluatorVersion = currentEvaluatorVersion
  , geeConfidenceAlgebraVersion = currentEvaluatorVersion
  , geeCapabilityEvaluatorVersion = currentEvaluatorVersion
  , geeSandboxVersion = currentEvaluatorVersion
  , geeRollbackLink = Nothing
  , geeBeforeRef = Just (GovRefSnapshot "base:before")
  , geeAfterRef = Just (GovRefSnapshot "base:after")
  , geeEffectRef = Just (GovRefSnapshot "base:effect")
  , geeEventHash = Nothing
  , geePrevHash = Nothing
  , geePayloadHash = Nothing
  }

assertRight :: Show e => Either e a -> IO a
assertRight result =
  case result of
    Left err -> assertFailure (show err)
    Right value -> pure value

assertLeft :: String -> Either e a -> IO ()
assertLeft label result =
  case result of
    Left _ -> pure ()
    Right _ -> assertFailure label

assertLinePresent :: String -> T.Text -> [T.Text] -> IO ()
assertLinePresent label expected lines' =
  assertBool label (expected `elem` lines')

positiveConatus :: ConatusEnergy
positiveConatus = ConatusEnergy
  { ceScalar = 10.0
  , ceComponents = ConatusComponents
      { ccMorphology = 0.0
      , ccIdentity = 0.0
      , ccTurns = 10.0
      , ccPenalty = 0.0
      }
  }
