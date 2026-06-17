{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.ReplayDeterminism
Description : Step 0 — discriminating test for apiHealthy replay determinism.

Without 'QxFx0.Core.PipelineIO.Replay.mkReplayPipelineIO' and the
'trcEffectSnapshot' field in 'TurnReplayTrace', this test does not
compile (design-time RED).  With both, it compiles and asserts that
replay reads the snapshot, not the live world — proving the
legitimacy-score path is deterministic under replay.
-}
module Test.Suite.ReplayDeterminism
  ( replayDeterminismTests
  ) where

import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision(..))
import Test.HUnit (Test (..), assertBool, assertEqual)

import Data.Aeson (encode, eitherDecode, withObject, (.:?))
import Data.Aeson.Types (parseEither)

import QxFx0.Core.Legitimacy (legitimacyScore)
import QxFx0.Core.PipelineIO
  ( defaultTestPipelineConfig
  , mkTestPipelineIO
  , mkReplayPipelineIO
  , checkPipelineApiHealth
  )
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Self.Field (emptyField)
import QxFx0.Types.CognitiveSignals (emptyCognitiveSignals)
import QxFx0.Types.Decision (DecisionDisposition(..), LegitimacyReason(..), ShadowStatus(..))
import QxFx0.Types.Domain (CanonicalMoveFamily(..), IllocutionaryForce(..))
import QxFx0.Types.Observability (ReplayProvenanceStatus(..), TruthContractStatus(..))
import QxFx0.Types.Evidence (EvidenceAdmissibility(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergence(..), ShadowDivergenceKind(..), ShadowDivergenceSeverity(..), ShadowSnapshotId(..))
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase(..))
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Types.TurnProjection (TurnReplayTrace(..), EffectSnapshot(..), TurnProjection(..))
import QxFx0.Types.State.SemanticCommitment (MatchKind(..), emptyCommitmentEngagement)

import QxFx0.Core.TurnPipeline.Finalize.Projection (buildTurnProjection)
import QxFx0.Core.TurnPipeline (TurnSignals(..))
import Test.Support.TurnPipelineFixtures (buildRenderedFixture)

-- | A minimal 'TurnReplayTrace' with only 'trcEffectSnapshot' set.
-- All other fields use safe defaults so the record's strict fields
-- do not force evaluation of 'undefined'.
minimalReplayTrace :: Bool -> TurnReplayTrace
minimalReplayTrace apiHealthy =
  TurnReplayTrace
    { trcRequestId = "test"
    , trcSessionId = "test"
    , trcRuntimeMode = "test"
    , trcShadowPolicy = "observe"
    , trcLocalRecoveryPolicy = "enabled"
    , trcRecoveryCause = Nothing
    , trcRecoveryStrategy = Nothing
    , trcRecoveryEvidence = []
    , trcSemanticIntrospectionEnabled = False
    , trcWarnMorphologyFallbackEnabled = False
    , trcRequestedFamily = CMGround
    , trcStrategyFamily = Nothing
    , trcNarrativeHint = Nothing
    , trcIntuitionHint = Nothing
    , trcPreShadowFamily = CMGround
    , trcShadowSnapshotId = ShadowSnapshotId "test"
    , trcShadowStatus = ShadowUnavailable
    , trcShadowDivergenceKind = ShadowNoDivergence
    , trcShadowDivergenceSeverity = ShadowSeverityClean
    , trcShadowResolvedFamily = CMGround
    , trcFinalFamily = CMGround
    , trcFinalForce = IFAssert
    , trcDecisionDisposition = DispositionPermit
    , trcLegitimacyReason = ReasonOk
    , trcParserConfidence = 0.0
    , trcParserBackend = "test"
    , trcParserStatus = "ok"
    , trcParserDegradationReason = Nothing
    , trcParserLatencyMs = 0
    , trcEmbeddingQuality = "heuristic"
    , trcClaimAst = Nothing
    , trcPreSafetyRenderedRaw = "test"
    , trcRenderedAfterRebind = "test"
    , trcLinearizationLang = Nothing
    , trcLinearizationOk = False
    , trcFallbackReason = Nothing
    , trcContractProvenance = Nothing
    , trcSurfaceProvenance = Nothing
    , trcAuthorityClass = Nothing
    , trcTruthContractStatus = CanonicalSurfacePreserved
    , trcResponseSurfaceKind = Nothing
    , trcAssemblyPath = Nothing
    , trcArtifactManifest = Nothing
    , trcReplayProvenanceStatus = ReplayProvenanceComplete
    , trcDerivationTags = []
    , trcSalienceDriver = "default"
    , trcSalienceHolisticBias = 0.5
    , trcSalienceConfidence = 1.0
    , trcDeliberationRule = Nothing
    , trcDeliberationAgreement = Nothing
    , trcDeliberationDivergence = Nothing
    , trcDeliberationNarrativeTone = Nothing
    , trcEssenceMode = Nothing
    , trcEssenceCommitted = Nothing
    , trcEssenceAngstLevel = Nothing
    , trcEssenceTrigger = Nothing
    , trcLearningQueryType = Nothing
    , trcExternalTool = Nothing
    , trcLearningValidationStatus = Nothing
    , trcLearningSandboxResult = Nothing
    , trcLearningGraftTurn = Nothing
    , trcLearningRejectReason = Nothing
    , trcExternalActionReason = Nothing
    , trcExternalActionNeed = Nothing
    , trcPreActorFailureEvent = Nothing
    , trcSenseAnchor = "test"
    , trcSenseOperator = Nothing
    , trcSensePreservedAxes = []
    , trcDialogueFocus = "test"
    , trcDialogueFocusBefore = "test"
    , trcDialogueFocusAfter = "test"
    , trcDialoguePhase = Exploring
    , trcDialoguePhaseBefore = Exploring
    , trcDialoguePhaseAfter = Exploring
    , trcDialogueCommitmentCount = 0
    , trcDialogueCommitmentCountBefore = 0
    , trcDialogueCommitmentCountAfter = 0
    , trcMicroPlanMoves = []
    , trcMicroPlanExplicitness = 0.5
    , trcDreamPressureDatalogClass = Nothing
    , trcDreamPressureIntuitionClass = Nothing
    , trcDreamPressureAgreement = Nothing
    , trcDreamPressureStrength = Nothing
    , trcDreamPressureCandidateThresholdFired = Nothing
    , trcDreamPressureCandidateKinds = []
    , trcDreamPressureBiasApplied = Nothing
    , trcDreamCandidateLifecycleStatuses = []
    , trcDreamCandidateDecisionReasons = []
    , trcDreamCandidateApplied = Nothing
    , trcPerspectiveProjection = Nothing
    , trcPerspectiveProjections = []
    , trcConatusEnergy = ConatusEnergy 0.0 (ConatusComponents 0.0 0.0 0.0 0.0)
    , trcConatusGateFired = False
    , trcField = emptyField
    , trcIdentityClaims = []
    , trcEpisodicEncoding = []
    , trcEpisodicRetrieval = Nothing
    , trcEpisodicForgetting = (0, Nothing)
    , trcRegimeVersion = 0
    , trcMorphologyVersion = 0
    , trcFamilyDivergenceActive = False
  , trcSemanticCommitmentCount = 0
  , trcQuarantinedCommitmentCount = 0
  , trcPromotedFromQuarantineCount = 0
   , trcCommitmentStoreDecision = CsaAdmitCanonical
    , trcCommitmentEngaged = 0
    , trcCommitmentContradicted = False
    , trcCommitmentMatchKind = NoMatch
    , trcCommitmentFamilyHint = Nothing
   , trcCognitiveSignals = emptyCognitiveSignals
    , trcDoubtScore = Nothing
    , trcEpisodicRetrievalCount = Nothing
    , trcContentSaliencyDominantCluster = Nothing
    , trcMoodValence = Nothing
    , trcMoodArousal = Nothing
    , trcAffectDecoupled = False
    , trcMood = 0.0
    , trcUserModelTopIntent = Nothing
    , trcUserModelConfidence = Nothing
    , trcDerivedInferenceCount = Nothing
    , trcFamilyDivergenceOccurred = Nothing
    , trcFmarDetectorFamily = Nothing
    , trcFmarFamily = Nothing
    , trcFmarFamiliesMatch = Nothing
    , trcFmarFieldDistance = Nothing
    , trcFmarMode = Nothing
    , trcFamilyDerivationChain = []
    , trcGenerationTrace = []
    , trcEffectSnapshot = Just EffectSnapshot { esApiHealthy = apiHealthy }
    , trcEvidenceAdmissibility = EvidenceGoverned
    }

-- | Baseline 'ShadowDivergence' with no mismatch, for scoring.
cleanDivergence :: ShadowDivergence
cleanDivergence = ShadowDivergence
  { sdKind = ShadowNoDivergence
  , sdFamilyMismatch = False
  , sdForceMismatch = False
  , sdClauseMismatch = False
  , sdLayerMismatch = False
  , sdWarrantedMismatch = False
  }

-- | Shared legitimacy-score arguments for equal-comparison fairness.
parserConfidence :: Double
parserConfidence = 0.85

emaLoad :: Double
emaLoad = 0.3

-- | P1 test: replay PipelineIO reads apiHealthy from trace,
-- NOT from the default test interpreter (which returns False).
testReplayReadsTraceNotWorld :: Test
testReplayReadsTraceNotWorld =
  TestLabel "P1: replay PipelineIO reads apiHealthy from trace, not world" $
  TestCase $ do
    let trace = minimalReplayTrace True  -- apiHealthy = True in trace
        replayPio = mkReplayPipelineIO trace
        testPio = mkTestPipelineIO defaultTestPipelineConfig
    replayHealthy <- checkPipelineApiHealth replayPio
    testHealthy  <- checkPipelineApiHealth testPio
    assertBool "replay: must return True from trace" replayHealthy
    assertBool "test: default must return False" (not testHealthy)

-- | P2 test: legitimacyScore under replay matches the original (True) run,
-- NOT the degraded (False) run that the live world would produce.
testLegitimacyMatchesTraceNotWorld :: Test
testLegitimacyMatchesTraceNotWorld =
  TestLabel "P2: legitimacyScore reproduces trace value, not live world" $
  TestCase $ do
    let trace = minimalReplayTrace True
        replayPio = mkReplayPipelineIO trace
        testPio = mkTestPipelineIO defaultTestPipelineConfig
    replayHealthy <- checkPipelineApiHealth replayPio
    testHealthy  <- checkPipelineApiHealth testPio
    let scoreFromTrace    = legitimacyScore parserConfidence cleanDivergence emaLoad replayHealthy
        scoreFromWorld    = legitimacyScore parserConfidence cleanDivergence emaLoad testHealthy
        scoreIfLiveHealth = legitimacyScore parserConfidence cleanDivergence emaLoad True
    assertEqual "replay must reproduce original (True) score"
               scoreIfLiveHealth scoreFromTrace
    assertBool "replay and live must differ when world returns False"
               (scoreFromTrace /= scoreFromWorld)
    assertBool "replay penalty must be absent (api penalty only on unhealthy)"
               (scoreFromTrace > scoreFromWorld)

-- | P3 test: the recorded==consumed lock, exercised end-to-end through the
-- real 'buildTurnProjection'.  We run a rendered-turn fixture, then build the
-- projection twice with 'tsApiHealthy' forced True / False.  'esApiHealthy' in
-- 'trcEffectSnapshot' must track the consumed 'tsApiHealthy' — proving the
-- projection copies the threaded value rather than substituting a constant or
-- re-sampling the live world — and 'mkReplayPipelineIO' must read each recorded
-- value straight back.  A regression that hardcoded or re-sampled apiHealthy
-- would fail the False case.
testRecordedEqualsConsumed :: Test
testRecordedEqualsConsumed =
  TestLabel "P3: buildTurnProjection records consumed tsApiHealthy; replay round-trips it" $
  TestCase $ do
    (ss, ti, ts, tp, ta) <- buildRenderedFixture "привет"
    let projOf h = buildTurnProjection "test" "observe" "enabled" False False FmarOff
                     ss ti (ts { tsApiHealthy = h }) tp ta CsaAdmitCanonical 0 emptyCommitmentEngagement EvidenceGoverned
        recorded proj = esApiHealthy <$> trcEffectSnapshot (tqpReplayTrace proj)
    assertEqual "projection records True when consumed value is True"
               (Just True) (recorded (projOf True))
    assertEqual "projection records False when consumed value is False"
               (Just False) (recorded (projOf False))
    replayTrue  <- checkPipelineApiHealth (mkReplayPipelineIO (tqpReplayTrace (projOf True)))
    replayFalse <- checkPipelineApiHealth (mkReplayPipelineIO (tqpReplayTrace (projOf False)))
    assertBool "replay reproduces recorded True"        replayTrue
    assertBool "replay reproduces recorded False" (not replayFalse)

-- | P4 test: the recorded snapshot survives the EXACT serialization the DB
-- column uses.  'persistTurnQuality' stores @Aeson.encode replayTrace@ as the
-- @replay_trace_json@ TEXT column (Bridge/StatePersistence.hs:255), so an
-- encode -> decode round-trip is the serialization half of the production DB
-- round-trip.  We pull 'trcEffectSnapshot' back out of the encoded blob via a
-- 'Value' parser (no full-trace 'FromJSON' required) and confirm it equals the
-- recorded value for both polarities.
testSnapshotSurvivesSerialization :: Test
testSnapshotSurvivesSerialization =
  TestLabel "P4: trcEffectSnapshot survives Aeson encode/decode (DB column round-trip)" $
  TestCase $ do
    (ss, ti, ts, tp, ta) <- buildRenderedFixture "привет"
    let projOf h = buildTurnProjection "test" "observe" "enabled" False False FmarOff
                     ss ti (ts { tsApiHealthy = h }) tp ta CsaAdmitCanonical 0 emptyCommitmentEngagement EvidenceGoverned
        decodeSnapshot proj =
          (eitherDecode (encode (tqpReplayTrace proj))
             >>= parseEither (withObject "trace" (\o -> o .:? "trcEffectSnapshot")))
            :: Either String (Maybe EffectSnapshot)
    assertEqual "snapshot survives DB-column round-trip (recorded True)"
               (Right (Just (EffectSnapshot True)))  (decodeSnapshot (projOf True))
    assertEqual "snapshot survives DB-column round-trip (recorded False)"
               (Right (Just (EffectSnapshot False))) (decodeSnapshot (projOf False))

-- | P5 (audit D): the FULL TurnReplayTrace round-trips through the exact
-- serialization the DB column uses. 'persistTurnQuality' stores
-- @Aeson.encode (tqpReplayTrace p)@; with 'FromJSON TurnReplayTrace' now in
-- place (and FromJSON for all ~32 nested types + the 2 previously ToJSON-only
-- PreActor types), @decode . encode@ is total. This is the serialization half
-- of the production replay-from-DB path (item #1); the remaining half is the
-- on-disk SQLite blob load, deferred to an integration suite.
testFullTraceRoundTrips :: Test
testFullTraceRoundTrips =
  TestLabel "P5: full TurnReplayTrace survives Aeson encode/decode (DB-column round-trip)" $
  TestCase $ do
    (ss, ti, ts, tp, ta) <- buildRenderedFixture "это помогло"
    let trace = tqpReplayTrace
                  (buildTurnProjection "test" "observe" "enabled" False False FmarOff ss ti ts tp ta CsaAdmitCanonical 0 emptyCommitmentEngagement EvidenceGoverned)
    assertEqual "decode (encode trace) must reproduce the trace exactly"
      (Right trace)
      (eitherDecode (encode trace) :: Either String TurnReplayTrace)

replayDeterminismTests :: [Test]
replayDeterminismTests =
  [ testReplayReadsTraceNotWorld
  , testFullTraceRoundTrips
  , testLegitimacyMatchesTraceNotWorld
  , testRecordedEqualsConsumed
  , testSnapshotSurvivesSerialization
  ]
