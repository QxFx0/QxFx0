{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.TraceAnalysis (traceAnalysisTests) where

import Test.HUnit
import Data.Aeson (decode, encode)

import QxFx0.Observability.TraceAnalysis
import QxFx0.Types.TurnProjection (TurnReplayTrace(..))
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
import QxFx0.Types.Observability (TruthContractStatus(..), ReplayProvenanceStatus(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind(..), ShadowDivergenceSeverity(..), ShadowSnapshotId(..))
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase(..))
import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision(..))
import QxFx0.Types.CognitiveSignals (emptyCognitiveSignals)

traceAnalysisTests :: [Test]
traceAnalysisTests =
  [ TestLabel "Recovery enums JSON round-trip (cause/strategy)" testRecoveryEnumsRoundTrip
  , TestLabel "TraceAnalysis: Recovery no trigger" testRecoveryNoTrigger
  , TestLabel "TraceAnalysis: Recovery with cause" testRecoveryWithCause
  , TestLabel "TraceAnalysis: Conatus healthy" testConatusHealthy
  , TestLabel "TraceAnalysis: Conatus degraded" testConatusDegraded
  , TestLabel "TraceAnalysis: Field balanced" testFieldBalanced
  , TestLabel "TraceAnalysis: Essence witnessing" testEssenceWitnessing
  , TestLabel "TraceAnalysis: Full analysis" testFullAnalysis
  , TestLabel "TraceAnalysis: Anomaly detection" testAnomalyDetection
  ]

-- | Audit C: LocalRecoveryCause/Strategy serialize via rendered snake_case but
-- previously derived a generic FromJSON expecting the constructor name, so
-- decode (encode x) failed. This locks the round-trip for EVERY constructor.
testRecoveryEnumsRoundTrip :: Test
testRecoveryEnumsRoundTrip = TestCase $ do
  let causeRoundTrips c = decode (encode c) == Just c
      stratRoundTrips s = decode (encode s) == Just s
  mapM_ (\c -> assertBool ("cause round-trip: " <> show c) (causeRoundTrips c))
        [minBound .. maxBound :: LocalRecoveryCause]
  mapM_ (\s -> assertBool ("strategy round-trip: " <> show s) (stratRoundTrips s))
        [minBound .. maxBound :: LocalRecoveryStrategy]

-- | Helper to create minimal trace
minimalTrace :: TurnReplayTrace
minimalTrace = TurnReplayTrace
  { trcRequestId = "test-request"
  , trcSessionId = "test-session"
  , trcRuntimeMode = "production"
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
  , trcShadowSnapshotId = ShadowSnapshotId "test-snapshot-0"
  , trcShadowStatus = ShadowUnavailable
  , trcShadowDivergenceKind = ShadowNoDivergence
  , trcShadowDivergenceSeverity = ShadowSeverityClean
  , trcShadowResolvedFamily = CMGround
  , trcFinalFamily = CMGround
  , trcFinalForce = IFAssert
  , trcDecisionDisposition = DispositionPermit
  , trcLegitimacyReason = ReasonOk
  , trcParserConfidence = 0.9
  , trcParserBackend = "test"
  , trcParserStatus = "ok"
  , trcParserDegradationReason = Nothing
  , trcParserLatencyMs = 10
  , trcEmbeddingQuality = "high"
  , trcClaimAst = Nothing
  , trcPreSafetyRenderedRaw = "test"
  , trcRenderedAfterRebind = "test"
  , trcLinearizationLang = Just "en"
  , trcLinearizationOk = True
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
  , trcDialogueFocus = "general"
  , trcDialogueFocusBefore = "general"
  , trcDialogueFocusAfter = "general"
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
  , trcConatusEnergy = ConatusEnergy 1.0 (ConatusComponents 0.4 0.3 0.3 0.0)
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
  , trcRegimeVersion = 1
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
  , trcEffectSnapshot = Nothing
  }

testRecoveryNoTrigger :: Test
testRecoveryNoTrigger = TestCase $ do
  let trace = minimalTrace
  let analysis = analyzeRecoveryPattern trace
  assertEqual "Recovery not triggered" False (raTriggered analysis)
  assertEqual "No anomaly" Nothing (raAnomaly analysis)

testRecoveryWithCause :: Test
testRecoveryWithCause = TestCase $ do
  let trace = minimalTrace
        { trcRecoveryCause = Just RecoveryLowLegitimacy
        , trcRecoveryStrategy = Just StrategyAskClarification
        , trcRecoveryEvidence = ["low_confidence"]
        }
  let analysis = analyzeRecoveryPattern trace
  assertEqual "Recovery triggered" True (raTriggered analysis)
  assertEqual "Evidence count" 1 (raEvidenceCount analysis)

testConatusHealthy :: Test
testConatusHealthy = TestCase $ do
  let trace = minimalTrace
  let analysis = analyzeConatusDynamics trace
  assertEqual "Healthy energy" "healthy" (caEnergyTrend analysis)
  assertEqual "No anomaly" Nothing (caAnomaly analysis)

testConatusDegraded :: Test
testConatusDegraded = TestCase $ do
  let trace = minimalTrace
        { trcConatusEnergy = ConatusEnergy 0.2 (ConatusComponents 0.1 0.05 0.05 0.0)
        }
  let analysis = analyzeConatusDynamics trace
  assertEqual "Degraded energy" "degraded" (caEnergyTrend analysis)

testFieldBalanced :: Test
testFieldBalanced = TestCase $ do
  let trace = minimalTrace
  let analysis = analyzeFieldState trace
  assertEqual "Balanced field" "balanced" (faBalance analysis)
  assertEqual "No anomaly" Nothing (faAnomaly analysis)

testEssenceWitnessing :: Test
testEssenceWitnessing = TestCase $ do
  let trace = minimalTrace
  let analysis = analyzeEssenceCommitment trace
  assertEqual "Witnessing mode" (Just "witnessing") (eaMode analysis)
  assertEqual "Not committed" (Just False) (eaCommitted analysis)

testFullAnalysis :: Test
testFullAnalysis = TestCase $ do
  let trace = minimalTrace
  let summary = analyzeTrace trace
  assertEqual "Recovery policy" "enabled" (raPolicy $ tasRecovery summary)
  assertEqual "Conatus scalar" 1.0 (caScalar $ tasConatus summary)
  assertEqual "Field resonance" 0.5 (faResonance $ tasField summary)
  assertEqual "Salience driver" "formal_priority" (saDriver $ tasSalience summary)

testAnomalyDetection :: Test
testAnomalyDetection = TestCase $ do
  let trace = minimalTrace
        { trcRecoveryCause = Just RecoveryLowLegitimacy
        , trcRecoveryStrategy = Nothing  -- This should trigger anomaly
        }
  let summary = analyzeTrace trace
  assertEqual "Has anomaly" True (hasAnyAnomaly summary)
  assertEqual "Anomaly count" 1 (tasAnomalyCount summary)

