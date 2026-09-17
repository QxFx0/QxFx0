{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.M6FeltGate
Description : Anti-rot tests for the M6-FELT mechanical evidence gate.

Pins the fail-closed semantics of 'QxFx0.Core.M6FeltGate':

  * an empty session is 'M6FeltNotProven' naming all six gates;
  * a single ungoverned turn fails the governed-evidence precondition
    (SLICE-012) regardless of content;
  * Gate 5 rejects fallback turns (authority class, fallback reason,
    linearization, content source);
  * Gates 1-4 fire on the mechanical criteria from the trace fields;
  * a 10-turn governed session that passes every criterion yields
    'M6FeltProven' with the structural summary;
  * the conjunction is strict: one bad turn fails the whole gate.
-}
module Test.Suite.M6FeltGate
  ( m6FeltGateTests
  ) where

import qualified Data.Sequence as Seq
import Test.HUnit (Test(..), assertBool, assertEqual, assertFailure)

import QxFx0.Core.M6FeltGate
import QxFx0.Runtime (RuntimeMode(..))
import QxFx0.Types.TurnProjection (ParserStatus(..), TurnReplayTrace(..))
import QxFx0.Types.Recovery (LocalRecoveryCause(..), LocalRecoveryStrategy(..))
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Types.State.SemanticCommitment (MatchKind(..))
import QxFx0.Self.Field
  ( Field(..)
  , Resonance(..)
  , Atmosphere(..)
  , FieldConfidence(..)
  , Consolidation(..)
  , Counterfactual(..)
  )
import QxFx0.Types.Domain (CanonicalMoveFamily(..), IllocutionaryForce(..))
import QxFx0.Types.Decision (ShadowStatus(..), LegitimacyReason(..), DecisionDisposition(..))
import QxFx0.Types.Observability (AuthorityClass(..), TruthContractStatus(..), ReplayProvenanceStatus(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind(..), ShadowDivergenceSeverity(..), ShadowSnapshotId(..))
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase(..))
import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision(..))
import QxFx0.Types.CognitiveSignals (emptyCognitiveSignals)
import QxFx0.Types.Evidence (EvidenceAdmissibility(..))

-- ---------------------------------------------------------------------------
-- Test group
-- ---------------------------------------------------------------------------

m6FeltGateTests :: [Test]
m6FeltGateTests =
  [ TestLabel "M6-FELT: empty session is NotProven naming all gates"
      testEmptySession
  , TestLabel "M6-FELT: ungoverned turn fails governed-evidence precondition"
      testUngovernedFailsPrecondition
  , TestLabel "M6-FELT: Gate 5 rejects fallback authority"
      testGate5RejectsFallback
  , TestLabel "M6-FELT: Gate 5 rejects fallback reason"
      testGate5RejectsFallbackReason
  , TestLabel "M6-FELT: Gate 5 rejects non-semantic content source"
      testGate5RejectsTemplateSource
  , TestLabel "M6-FELT: Gate 1 needs two substantive turns"
      testGate1NeedsTwoSubstantive
  , TestLabel "M6-FELT: Gate 2 needs two distinct semantic focuses"
      testGate2NeedsTwoDistinctFocuses
  , TestLabel "M6-FELT: Gate 3 fires on challenge repair"
      testGate3RepairFires
  , TestLabel "M6-FELT: Gate 3 absent without engagement"
      testGate3AbsentWithoutEngagement
  , TestLabel "M6-FELT: Gate 4 needs 10 turns and final count >= 1"
      testGate4SessionFloor
  , TestLabel "M6-FELT: Gate 4 rejects silent count drop"
      testGate4RejectsSilentDrop
  , TestLabel "M6-FELT: 10-turn governed session passes (conjunction)"
      testPassingSession
  , TestLabel "M6-FELT: one bad turn fails the whole gate"
      testOneBadTurnFailsAll
  ]

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

testEmptySession :: Test
testEmptySession = TestCase $ do
  let verdict = evaluateM6FeltGate []
  assertEqual "empty session must name all six gates"
    (M6FeltNotProven [ FeltGateGovernedEvidence, FeltGate5NonFallback
                     , FeltGate1Definition, FeltGate2Distinction
                     , FeltGate3Repair, FeltGate4Commitment ])
    verdict

testUngovernedFailsPrecondition :: Test
testUngovernedFailsPrecondition = TestCase $ do
  let trace = passingTrace { trcEvidenceAdmissibility = EvidenceDegradedGuardUnavailable }
      verdict = evaluateM6FeltGate [trace]
  assertBool "ungoverned trace must fail the governed-evidence precondition"
    (FeltGateGovernedEvidence `elem` failedGates verdict)

testGate5RejectsFallback :: Test
testGate5RejectsFallback = TestCase $ do
  let trace = passingTrace { trcAuthorityClass = Just AuthorityFallback }
      verdict = evaluateM6FeltGate (mkSession 10 trace)
  assertBool "fallback authority must fail Gate 5"
    (FeltGate5NonFallback `elem` failedGates verdict)

testGate5RejectsFallbackReason :: Test
testGate5RejectsFallbackReason = TestCase $ do
  let trace = passingTrace { trcFallbackReason = Just "uncovered topic" }
      verdict = evaluateM6FeltGate (mkSession 10 trace)
  assertBool "recorded fallback reason must fail Gate 5"
    (FeltGate5NonFallback `elem` failedGates verdict)

testGate5RejectsTemplateSource :: Test
testGate5RejectsTemplateSource = TestCase $ do
  let trace = passingTrace { trcContentSource = Nothing }
      verdict = evaluateM6FeltGate (mkSession 10 trace)
  assertBool "template content source must fail Gate 5"
    (FeltGate5NonFallback `elem` failedGates verdict)

testGate1NeedsTwoSubstantive :: Test
testGate1NeedsTwoSubstantive = TestCase $ do
  let trace = passingTrace { trcEmittedPredicates = [] }
      verdict = evaluateM6FeltGate (mkSession 10 trace)
  assertBool "empty predications must fail Gate 1"
    (FeltGate1Definition `elem` failedGates verdict)

testGate2NeedsTwoDistinctFocuses :: Test
testGate2NeedsTwoDistinctFocuses = TestCase $ do
  let trace = passingTrace { trcDialogueFocus = "freedom" }
      verdict = evaluateM6FeltGate (replicate 10 trace)
  assertBool "single dialogue focus must fail Gate 2"
    (FeltGate2Distinction `elem` failedGates verdict)

testGate3RepairFires :: Test
testGate3RepairFires = TestCase $ do
  let repair = passingTrace
        { trcCommitmentEngaged = 1
        , trcCommitmentContradicted = True
        }
      traces = mkSession 10 passingTrace <> [repair]
      verdict = evaluateM6FeltGate traces
  assertBool "challenge repair must pass Gate 3"
    (FeltGate3Repair `notElem` failedGates verdict)

testGate3AbsentWithoutEngagement :: Test
testGate3AbsentWithoutEngagement = TestCase $ do
  let trace = passingTrace { trcCommitmentEngaged = 0, trcCommitmentContradicted = False }
      verdict = evaluateM6FeltGate (mkSession 10 trace)
  assertBool "no commitment engagement must fail Gate 3"
    (FeltGate3Repair `elem` failedGates verdict)

testGate4SessionFloor :: Test
testGate4SessionFloor = TestCase $ do
  let trace = passingTrace { trcSemanticCommitmentCount = 0 }
      verdict = evaluateM6FeltGate (replicate 10 trace)
  assertBool "final count 0 must fail Gate 4"
    (FeltGate4Commitment `elem` failedGates verdict)

testGate4RejectsSilentDrop :: Test
testGate4RejectsSilentDrop = TestCase $ do
  let low = passingTrace { trcSemanticCommitmentCount = 5, trcCommitmentStoreDecision = CsaAdmitCanonical }
      high = passingTrace { trcSemanticCommitmentCount = 8, trcCommitmentStoreDecision = CsaAdmitCanonical }
      traces = high : replicate 8 passingTrace <> [low]
      verdict = evaluateM6FeltGate traces
  assertBool "silent count drop must fail Gate 4"
    (FeltGate4Commitment `elem` failedGates verdict)

testPassingSession :: Test
testPassingSession = TestCase $ do
  let repair = passingTrace
        { trcCommitmentEngaged = 1
        , trcCommitmentContradicted = True
        }
      traces = repair : mkSession 9 passingTrace
  case evaluateM6FeltGate traces of
    M6FeltProven evidence -> do
      assertEqual "turn count" 10 (feTurnCount evidence)
      assertBool "final commitment count must be >= 1"
        (feFinalCommitmentCount evidence >= 1)
      assertBool "distinct focuses must be >= 2"
        (feDistinctFocuses evidence >= 2)
      assertBool "repair turns must be recorded"
        (feRepairTurns evidence >= 1)
    M6FeltNotProven gs ->
      assertFailure ("10-turn governed session must pass; failed: " <> show gs)

testOneBadTurnFailsAll :: Test
testOneBadTurnFailsAll = TestCase $ do
  let bad = passingTrace
        { trcEvidenceAdmissibility = EvidenceInadmissible
        , trcAuthorityClass = Just AuthorityFallback
        , trcFallbackReason = Just "guard unavailable"
        }
      traces = bad : mkSession 9 passingTrace
      verdict = evaluateM6FeltGate traces
  assertBool "one inadmissible fallback turn must fail the whole gate"
    (case verdict of M6FeltNotProven _ -> True; M6FeltProven _ -> False)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | A single turn that passes every gate criterion on its own.
passingTrace :: TurnReplayTrace
passingTrace = TurnReplayTrace
  { trcRequestId = "m6-felt-request"
  , trcSessionId = "m6-felt-session"
  , trcRuntimeMode = StrictRuntime
  , trcShadowPolicy = "enabled"
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
  , trcShadowSnapshotId = ShadowSnapshotId "m6-felt-snapshot-0"
  , trcShadowStatus = ShadowUnavailable
  , trcShadowDivergenceKind = ShadowNoDivergence
  , trcShadowDivergenceSeverity = ShadowSeverityClean
  , trcShadowResolvedFamily = CMGround
  , trcFinalFamily = CMGround
  , trcFinalForce = IFAssert
  , trcDecisionDisposition = DispositionPermit
  , trcLegitimacyReason = ReasonOk
  , trcParserConfidence = 0.9
  , trcParserBackend = "gf"
  , trcParserStatus = PsOk
  , trcParserDegradationReason = Nothing
  , trcParserLatencyMs = 10
  , trcEmbeddingQuality = "high"
  , trcClaimAst = Nothing
  , trcPreSafetyRenderedRaw = "Свобода предполагает выбор."
  , trcRenderedAfterRebind = "Свобода предполагает выбор и ограничена ответственностью."
  , trcLinearizationLang = Just "ru"
  , trcLinearizationOk = True
  , trcFallbackReason = Nothing
  , trcContractProvenance = Nothing
  , trcSurfaceProvenance = Nothing
  , trcAuthorityClass = Just AuthorityCanonical
  , trcTruthContractStatus = CanonicalSurfacePreserved
  , trcResponseSurfaceKind = Nothing
  , trcAssemblyPath = Nothing
  , trcArtifactManifest = Nothing
  , trcReplayProvenanceStatus = ReplayProvenanceComplete
  , trcDerivationTags = []
  , trcSalienceDriver = "formal_priority"
  , trcSalienceHolisticBias = 0.5
  , trcSalienceConfidence = 0.8
  , trcDeliberationRule = Nothing
  , trcDeliberationAgreement = Nothing
  , trcDeliberationDivergence = Nothing
  , trcDeliberationNarrativeTone = Nothing
  , trcEssenceMode = Just "witnessing"
  , trcEssenceCommitted = Just False
  , trcEssenceAngstLevel = Just 0.1
  , trcEssenceTrigger = Nothing
  , trcEssenceResetEvent = Nothing
  , trcLearningQueryType = Nothing
  , trcExternalTool = Nothing
  , trcLearningValidationStatus = Nothing
  , trcLearningSandboxResult = Nothing
  , trcLearningGraftTurn = Nothing
  , trcLearningRejectReason = Nothing
  , trcExternalActionReason = Nothing
  , trcExternalActionNeed = Nothing
  , trcPreActorFailureEvent = Nothing
  , trcSenseAnchor = "neutral"
  , trcSenseOperator = Nothing
  , trcSensePreservedAxes = []
  , trcDialogueFocus = "freedom"
  , trcDialogueFocusBefore = "general"
  , trcDialogueFocusAfter = "freedom"
  , trcDialoguePhase = Exploring
  , trcDialoguePhaseBefore = Exploring
  , trcDialoguePhaseAfter = Exploring
  , trcDialogueCommitmentCount = 1
  , trcDialogueCommitmentCountBefore = 0
  , trcDialogueCommitmentCountAfter = 1
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
  , trcConatusEnergy = ConatusEnergy 14.0 (ConatusComponents 5.6 4.2 4.2 0.0 0.0)
  , trcSelfDivergenceTotal = Nothing
  , trcSelfDivergencePenalty = 0.0
  , trcSelfDivergenceWindowMean = Nothing
  , trcSelfDivergencePredictionActive = False
  , trcConatusGateFired = False
  , trcField = Field
      { fieldResonance = Resonance 0.5
      , fieldAtmosphere = Atmosphere 0.0 0.5
      , fieldConfidence = FieldConfidence 0.8
      , fieldConsolidation = Consolidation 0.6
      , fieldCounterfactual = Counterfactual 0.3
      }
  , trcIdentityClaims = []
  , trcEpisodicEncoding = []
  , trcEpisodicRetrieval = Nothing
  , trcEpisodicForgetting = (0, Nothing)
  , trcRegimeVersion = 2
  , trcMorphologyVersion = 1
  , trcFamilyDivergenceActive = True
  , trcSemanticCommitmentCount = 1
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
  , trcEffectSnapshot = Nothing
  , trcEvidenceAdmissibility = EvidenceGoverned
  , trcIntentType = Just "IntentDefine"
  , trcFrameType = Just "definition"
  , trcContentSource = Just "covered_exact"
  , trcAnalogicalSource = Nothing
  , trcSubstrateActivated = []
  , trcSubstrateEdgesUsed = 0
  , trcActivationSteps = Seq.empty
  , trcSubstrateHops = 0
  , trcActivatedConcepts = ["свобода"]
  , trcMissingPredicates = []
  , trcEmittedPredicates = ["свобода предполагает выбор", "свобода ограничена ответственностью"]
  , trcCuratedOverlayVersion = Nothing
  , trcOverlayPredicateIds = []
  , trcOverlayContentUsed = False
  , trcSelectorDiagnostics = []
  , trcAssemblyCandidates = []
  , trcResponsePlan = Nothing
  , trcUserRegime = Nothing
  }

-- | A session of @n@ identical passing turns, with the dialogue focus
-- alternating so Gate 2 (distinction) holds.
mkSession :: Int -> TurnReplayTrace -> [TurnReplayTrace]
mkSession n t =
  [ t { trcDialogueFocus = if even i then "freedom" else "truth"
      , trcSemanticCommitmentCount = i + 1
      }
  | i <- [0 .. n - 1] ]

failedGates :: M6FeltVerdict -> [FeltGate]
failedGates = \case
  M6FeltNotProven gs -> gs
  M6FeltProven _     -> []
