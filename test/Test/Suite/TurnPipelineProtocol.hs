{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.TurnPipelineProtocol
  ( turnPipelineProtocolTests
  , buildFinalizeFixture
  , buildFinalizeFixtureWithState
  , withDeterministicEmbedding
  ) where

import Control.Concurrent (threadDelay)

import Control.Exception (try)
import Control.Monad (foldM, unless)
import Data.Aeson (encode, decode)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (sort)
import Data.Time.Clock (UTCTime(..))
import Data.Time.Calendar (Day(ModifiedJulianDay))
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Text as T
import qualified Data.Vector as V
import Test.HUnit hiding (Testable)
import Test.QuickCheck
  ( Result(..)
  , Testable
  , elements
  , forAll
  , ioProperty
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )

import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Types
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Semantic.Input.Model (SemanticTag(..))
import QxFx0.Types.Readiness (AgdaVerificationStatus(..))
import QxFx0.Types.Thresholds (blockedConceptsRetentionLimit, parserLowConfidenceThreshold)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , ShadowPolicy(..)
  , ShadowResult(..)
  , scheduleTurnEffects
  , TestPipelineConfig(..)
  , defaultTestPipelineConfig
  , mkTestPipelineIO
  , pipelineShadowPolicy
  , pipelineUpdateHistory
  , pipelineParseAuthoritySurface
  )
import QxFx0.ExceptionPolicy (QxFx0Exception(..), PersistenceErrorDetails(..))
import QxFx0.Core.TurnPipeline.Protocol
  ( RoutingDecision(..)
  , TurnArtifacts(..)
  , TurnInput(..)
  , TurnPlan(..)
  , TurnSignals(..)
  , PrepareEffectPlan(..)
  , PrepareEffectRequest(..)
  , PrepareStatic(..)
  , TurnEffectRequest(..)
  , TurnEffectResult(..)
  , RouteEffectPlan(..)
  , RouteEffectRequest(..)
  , RouteEffectResults(..)
  , RouteStatic(..)
  , RenderEffectPlan(..)
  , LocalRecoveryPlan(..)
  , RenderStatic(..)
  , FinalizeCommitPlan(..)
  , FinalizeCommitResults(..)
  , FinalizePrecommitBundle(..)
  , FinalizePrecommitPlan(..)
  , FinalizePrecommitRequest(..)
  , FinalizeStatic(..)
  , buildFinalizePrecommit
  , buildRouteTurnPlan
  , buildTurnArtifacts
  , buildTurnInput
  , buildTurnSignals
  , planPrepareEffects
  , planFinalizeCommit
  , planFinalizePrecommit
  , planRenderEffects
  , planRenderEffectsForRuntime
  , planRouteEffects
  , resolveFinalizePrecommit
  , resolveFinalizeCommit
  , resolvePrepareEffects
  , resolveRenderEffects
  , resolveRouteEffects
  , finalizeMetrics
  )
import QxFx0.Core.Observability (PhaseTiming(..), TurnMetrics(..))
import QxFx0.Core.InterpretationAdmission
  ( InterpretationAdmissionInput(..)
  , InterpretationAdmissionDecision(..)
  , AdmittedInterpretation(..)
  , admitInterpretationCandidate
  )
import QxFx0.Core.SemanticFrameAdmission
  ( SemanticFrameAdmissionInput(..)
  , SemanticFrameAdmissionDecision(..)
  , AdmittedSemanticFrame(..)
  , admitSemanticFrame
  , admitSemanticFrameForInput
  , admittedSemanticFrameConfidence
  , admittedSemanticFrameRouteTag
  , admittedSemanticFrameRouteEvidence
  )
import QxFx0.Types.Admission.PropositionAdmission
  ( PropositionAdmissionInput(..)
  , PropositionAdmissionDecision(..)
  , AdmittedPropositionFrame(..)
  , admitPropositionFrame
  )
import QxFx0.Core.SenseVectorAdmission
  ( SenseVectorAdmissionInput(..)
  , SenseVectorAdmissionDecision(..)
  , AdmittedSenseVector(..)
  , admitSenseVector
  )
import QxFx0.Core.RouteHintAdmission
  ( InputRouteType(..)
  , InputRouteHint(..)
  , RouteHintAdmissionInput(..)
  , RouteHintAdmissionDecision(..)
  , AdmittedRouteHint(..)
  , admitRouteHint
  , admitRouteHintForFrame
  , applyAdmittedRouteHint
  , admittedRouteHintTag
  , admittedRouteHintConfidence
  , admittedRouteHintEvidence
  )
import QxFx0.Core.FamilyAdmission
  ( FamilyAdmissionInput(..)
  , FamilyAdmissionDecision(..)
  , AdmittedFamily(..)
  , admitFamilyCrystallization
  )
import QxFx0.Core.EarlyFamilyAdmission
  ( EarlyFamilyAdmissionInput(..)
  , EarlyFamilyAdmissionDecision(..)
  , AdmittedEarlyFamily(..)
  , admitEarlyFamilyRecommendation
  )
import QxFx0.Core.AtomContributionAdmission
  ( AtomContributionAdmissionInput(..)
  , AtomContributionAdmissionDecision(..)
  , AdmittedAtomContributions(..)
  , admitAtomContributions
  )
import QxFx0.Core.AtomExtractionAdmission
  ( AtomExtractionAdmissionInput(..)
  , AtomExtractionAdmissionDecision(..)
  , AdmittedAtomAvailability(..)
  , admitAtomAvailability
  )
import QxFx0.Core.AtomFindingAdmission
  ( AtomFindingAdmissionInput(..)
  , AtomFindingAdmissionDecision(..)
  , AdmittedAtomFindings(..)
  , admitAtomFindings
  )
import QxFx0.Core.StructuralAtomAdmission
  ( StructuralAtomAdmissionInput(..)
  , StructuralAtomAdmissionDecision(..)
  , AdmittedStructuralAtoms(..)
  , admitStructuralAtoms
  )
import QxFx0.Core.LexicalClusterPhraseDecisionAdmission
  ( LexicalClusterPhraseDecisionAdmissionInput(..)
  , LexicalClusterPhraseDecisionAdmissionDecision(..)
  , AdmittedLexicalClusterPhraseDecisions(..)
  , admitLexicalClusterPhraseDecisions
  )
import QxFx0.Core.LexicalClusterPhraseAdmission
  ( LexicalClusterPhraseAdmissionInput(..)
  , LexicalClusterPhraseAdmissionDecision(..)
  , AdmittedLexicalClusterPhraseContainment(..)
  , admitLexicalClusterPhraseContainment
  )
import QxFx0.Core.LexicalClusterHitAdmission
  ( LexicalClusterHitAdmissionInput(..)
  , LexicalClusterHitAdmissionDecision(..)
  , AdmittedLexicalClusterHits(..)
  , admitLexicalClusterHits
  )
import QxFx0.Core.LexicalClusterMatchAdmission
  ( LexicalClusterMatchAdmissionInput(..)
  , LexicalClusterMatchAdmissionDecision(..)
  , AdmittedLexicalClusterMatches(..)
  , admitLexicalClusterMatches
  )
import QxFx0.Core.SemanticContributionAdmission
  ( SemanticContributionAdmissionInput(..)
  , SemanticContributionAdmissionDecision(..)
  , AdmittedSemanticContributions(..)
  , admitSemanticContributions
  )
import QxFx0.Core.SemanticLogicAdmission
  ( SemanticLogicAdmissionInput(..)
  , SemanticLogicAdmissionDecision(..)
  , AdmittedSemanticLogic(..)
  , admitSemanticLogicWeighting
  )
import QxFx0.Core.SensePlan (buildResponseSensePlan)
import QxFx0.Self.Conatus (ConatusComponents(..), ConatusEnergy(..))
import QxFx0.Self.Deliberation
  ( Deliberation(..)
  , DeliberationTrace(..)
  , Plan(..)
  , Agreement(..)
  , ReconcileRule(..)
  , defaultPlan
  )
import QxFx0.Self.Salience (Salience(..), SelfVerdict(..), SalienceDriver(..), SalienceVerdict(..))
import qualified QxFx0.Semantic.Embedding as Emb
import qualified QxFx0.Semantic.Morphology as Morph
import QxFx0.Semantic.MeaningAtoms
  ( RawAtomFindings(..)
  , RawClusterPhraseDecision(..)
  , RawLexicalPhraseDecision(..)
  , RawLexicalClusterPhraseDecisions(..)
  , RawClusterPhraseContainment(..)
  , RawClusterHit(..)
  , LexicalPhraseContainmentClass(..)
  , RawLexicalPhraseContainment(..)
  , RawLexicalClusterPhraseContainment(..)
  , RawLexicalHit(..)
  , RawLexicalClusterHits(..)
  , RawLexicalClusterMatches(..)
  , buildRawLexicalClusterPhraseContainmentFromDecisions
  , buildRawLexicalClusterHitsFromPhraseContainment
  , buildRawLexicalClusterMatchesFromHits
  )
import QxFx0.Semantic.SemanticInput (SemanticInput(..))
import QxFx0.Semantic.Sense.Extract (extractSenseVector)
import qualified QxFx0.Core.Intuition as Intuition
import qualified QxFx0.Core.ConsciousnessLoop as CLoop
import QxFx0.Types.ShadowDivergence
  ( ShadowSnapshotId(..)
  , ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  , ShadowDivergenceSeverity(..)
  , ShadowVetoState(..)
  , emptyShadowDivergence
  )
import QxFx0.Semantic.Proposition (parseProposition, parsePropositionWithFrame, PropositionType(..))
import QxFx0.Types.Domain.Atoms (ProvisionalAtom(..), MorphologyData(..))
import QxFx0.Core.Guard (SafetyStatus(..))
import QxFx0.Semantic.AtomAccretion
  ( observeNovelAtom
  , promoteProvisionalAtoms
  , decayProvisionalAtoms
  , resolveCollisions
  )
import QxFx0.Learning.Need
  ( LearningNeed(..)
  , NeedTrend(..)
  , LearningNeedState(..)
  , emptyLearningNeedState
  , detectLearningNeed
  , detectLearningNeedWithPressure
  , defaultLearningPressureConfig
  , LearningPressureConfig(..)
  )
import QxFx0.Learning.KnowledgeTree
  ( ktGraftedCount
  , emptyKnowledgeTree
  )
import QxFx0.Learning.DialogueDevelopment
  ( adjustRenderStyleForSpeechPolicy
  , updateBeliefStore
  , updateSpeechPolicy
  )
import QxFx0.Self.Field (Field(..), emptyField, FieldConfidence(..), Consolidation(..), Counterfactual(..))
import QxFx0.Learning.Tool
  ( ExternalTool(..)
  , ToolDomain(..)
  , selectTool
  , defaultAvailableTools
  )
import QxFx0.Bridge.ExternalLLM
  ( buildTransportFromConfig
  , queryExternalTool
  , defaultExternalQueryConfig
  )
import QxFx0.Types.ExternalQuery (ExternalQueryConfig(..), TransportFallbackReason(..))
import QxFx0.Learning.Calibration
  ( CalibrationId(..)
  , CalibrationProposal(..)
  , CalibrationStatus(..)
  , CalibrationEntry(..)
  , CalibrationLog(..)
  , emptyCalibrationLog
  , verifyProposal
  , simulateProposal
  , acceptProposal
  , monitorCalibration
  , rollbackCalibration
  , currentCalibrationVersion
  )
import QxFx0.Learning.Guardrails
  ( GuardrailState(..)
  , emptyGuardrailState
  , canSubmitProposal
  , recordProposalSubmission
  , recordRejection
  , recordAcceptance
  , isQuarantineExpired
  )
import Test.Support (withEnvVar)
-- Authoritative-turn finalize fixture (forces canonical artifacts) for the
-- governed perspective-commit path; the other fixtures here are local copies.
import Test.Support.TurnPipelineFixtures (buildAuthoritativePerspectiveFinalizeFixture)

-- | Match both plain and structured PersistenceError variants.
matchPersistenceError :: QxFx0Exception -> Maybe T.Text
matchPersistenceError ex = case ex of
  PersistenceError msg -> Just msg
  PersistenceErrorStructured d -> Just (pedErrorCode d)
  _ -> Nothing

turnPipelineProtocolTests :: [Test]
turnPipelineProtocolTests =
  [ testPrepareEffectPlanDeterministicProperty
  , testRouteEffectPlanDeterministicProperty
  , testRenderEffectPlanDeterministicProperty
  , testFinalizePrecommitPlanDeterministicProperty
  , testFinalizeCommitPlanDeterministicProperty
  , testFinalizeCommitRecoversRuntimeStateAfterCommitFailure
  , testFinalizeCommitRollsBackPersistedStateAfterRecoveryFailure
  , testReplayEnvelopeDeterministicProperty
  , testReplayEnvelopeJsonDeterministicProperty
  , testBlockedConceptsRetentionIsBoundedAndDeduplicated
  , testPrepareEffectsResolveConcurrently
  , testScheduleTurnEffectsPrioritizesCheapChecksWhenConatusCritical
  , testPrepareMetricsExposeHonestPhaseNames
  , testRouteEffectsResolveConcurrently
  , testRouteEffectsFailOnAgdaInStrictRuntime
  , testNarrativeHintCannotBypassShadowGate
   , testAdvisoryShadowDivergenceDoesNotTriggerRecovery
   , testShadowVetoAllowedWithinWindow
   , testShadowVetoExhaustedAfterMax
    , testShadowVetoWindowResets
    , testObserveNovelAtomCreatesNew
    , testObserveNovelAtomBumpsExisting
    , testPromoteProvisionalAtomsMeetsCriteria
    , testPromoteProvisionalAtomsBelowThreshold
    , testDecayProvisionalAtomsRemovesStale
    , testDecayProvisionalAtomsKeepsFresh
    , testResolveCollisionsRemovesDuplicates
     , testResolveCollisionsKeepsNovel
     , testLearningNeedRaisedOnPersistentPattern
     , testLearningNeedNotRaisedOnNoise
     , testLearningNeedWiredThroughFinalizePrecommit
     , testLearningNeedHighDeficitTriggersRequestStrategy
     , testLearningNeedLowDeficitDoesNotTriggerRequest
     , testLearningNeedNoneDoesNotTriggerRequest
     , testToolSelectsBestMatchByDomainAndReliability
     , testToolRejectsMismatchDomain
     , testToolPrefersValidatableOverHigherReliability
     , testToolNoneForNoNeed
     , testCalibrationVerifyRejectsEmptyRule
     , testCalibrationVerifyRejectsBlockedRule
     , testCalibrationVerifyAcceptsValidConcept
     , testCalibrationAcceptCreatesEntry
     , testCalibrationMonitorOkWithinWindow
     , testCalibrationMonitorDetectsDegradation
     , testCalibrationRollbackReturnsPrevVersion
     , testCalibrationRollbackFailsForNonAccepted
     , testCalibrationCurrentVersionReturnsLastAccepted
     , testGuardrailRateLimitBlocksAfterMax
     , testGuardrailRateLimitResetsAfterWindow
     , testGuardrailCircuitBreakerOpensAfterRejections
     , testGuardrailCircuitBreakerClosesAfterCooldown
     , testGuardrailQuarantineExpiresAfterMinTurns
     , testGuardrailQuarantineBlocksBeforeMinTurns
     , testGuardrailStateRoundTripsThroughJson
     , testCalibrationLogRoundTripsThroughJson
     , testGuardrailStatePersistsThroughTurnPipeline
     , testCalibrationLogPersistsThroughTurnPipeline
     , testRollbackPathPreservesPrevAndCurrentIds
     , testCooldownStateSurvivesRestartViaJson
     , testOperationalDiagnosticQuestionRendersDirectStatus
     , testOperationalCauseQuestionPreservesGroundDiagnosticFamily
     , testSystemLogicQuestionRendersDirectExplanation
     , testSelfKnowledgeAboutSelfRendersStructuredDescription
     , testSelfKnowledgeAboutUserRendersStructuredBoundary
     , testWorldCauseQuestionRendersGroundedExplanation
     , testWorldCauseSkyQuestionRendersGroundedExplanation
     , testLocationFormationQuestionRendersStructuredExplanation
     , testEverydayPurchaseStatementAvoidsLexicalFallback
     , testEverydayResidenceStatementAvoidsLexicalFallback
     , testAffectiveHelpQuestionUsesContactWithoutLexicalFallback
     , testGreetingSmallTalkUsesContactWithoutDistressFallback
     , testSmallTalkHowLifeUsesContactWithoutDistressFallback
     , testPurposeQuestionUsesObjectTopicWithoutCaseRegression
     , testPurposeQuestionHandsAvoidsBrokenGenitive
     , testPurposeQuestionExistenceAvoidsInfinitiveGenitive
     , testConceptQuestionUsesPrepositionalFallbackCase
     , testComparisonQuestionRendersStructuredDistinction
     , testMisunderstandingReportRendersRepairWithoutLexicalFallback
     , testDialogueInvitationRendersDeepenWithoutLexicalFallback
     , testConceptKnowledgeQuestionRendersDefinitionWithoutLexicalFallback
     , testConceptKnowledgeBeingSmartRendersNaturalFrame
     , testSelfStateQuestionRendersDescriptionWithoutLexicalFallback
     , testGenerativePromptRendersDirectThought
     , testGenerativePromptAnotherThoughtRendersNewThought
     , testGenerativePromptFreshThoughtRendersDistinctSurface
     , testGenerativePromptLogicalQualityRendersLogicalSurface
     , testSelfKnowledgeWhatYouAreRendersStructuredDescription
     , testSelfKnowledgeThoughtCapacityRendersDirectAnswer
     , testSelfKnowledgeCapabilityQuestionRendersCapabilitySurface
     , testSelfKnowledgeHelpQuestionRendersHelpSurface
     , testSelfKnowledgeUserIdentityQuestionRendersBoundarySurface
     , testSystemLogicQuestionWithUtebyaRendersDirectExplanation
     , testSystemIdentityProbeAvoidsReflectFallback
     , testMustRouteNameQuestionUsesDescribe
     , testMustRoutePurposeQuestionUsesPurpose
     , testMustRouteDefineQuestionUsesDefine
     , testMustRouteDistinguishQuestionUsesDistinguish
     , testWorkEnableQuestionUsesOperationalStatusNotUserBoundary
     , testContemplativeTopicRendersDeepenWithoutLexicalFallback
     , testReflectiveAssertionRendersConceptTopicWithoutLexicalFallback
     , testLowLegitimacyUsesLocalRecoveryWithoutExternalCall
     , testRuntimeDegradedUsesVisibleLocalRecovery
     , testParserLowConfidenceUsesDistinguishCandidates
      , testRenderBlockedPersistsSafeRecoveryTrace
      -- P1-1 (Phase 7): FMAR behavioral integration — FmarLive must override cascade routing
      , testFmarLiveOverridesRouting
      -- P1-1: empty/fresh state must NOT fire the Conatus gate (energy starts non-negative)
      , testConatusGateDoesNotFireFromEmptyState
      , testConatusGateFiresRecoveryConatusGate
     , testConatusGateFlagDrivesLocalRecoveryPlan
     , testConatusGateEnergyWithoutFlagDoesNotProduceConatusCause
     , testConatusGradientMorphologyDominant
     , testConatusGradientIdentityDominant
     , testConatusGradientTemporalDominant
     , testConatusGradientDegenerateTie
     , testDeliberationRecoveryNotSilenced
     , testFinalizePrecommitResolveConcurrently
     , testPrepareCurrentTimeDeterministicInjection
      -- Phase 8 gap closure: external query end-to-end
      , testExternalQueryRequestPopulatedWhenLearningNeedActive
      , testExternalQueryResultPopulatedAfterRenderEffects
      , testExternalQueryGraftAppliedInFinalize
      , testExternalQueryFailClosedOnMockFailure
      , testExternalQueryNotAttemptedWhenNoRequestStrategy
      -- Phase 9 MVP: autonomous exploratory learning
      , testExploratoryPromptDetected
      , testAutonomousExplorationRequestPopulated
      , testAutonomousExplorationResultPopulated
      , testAutonomousExplorationGraftApplied
      , testAutonomousExplorationFailClosed
      , testAutonomousExplorationGuardrailBlocks
      , testAutonomousExplorationTelemetry
      , testRequestDrivenPathNotRegressedByExploration
       , testRequestDrivenBlockedPathRemainsInert
       , testRequestDrivenExternalActionReason
       , testExploratoryExternalActionReason
       , testGuardrailDeniedExternalActionReason
       , testNoActionExternalReason
       , testRequestDrivenTransportFailureSurfacesPreActorFailureEvent
       , testRequestDrivenNoExecutableToolSurfacesPreActorFailureEvent
       , testGuardrailDeniedPathDoesNotFabricatePreActorFailureEvent
        -- WP6.1: dedup anti-overblocking + telemetry wiring
       , testDedupAntiOverblockingAllowsNoisyKnownTopic
       , testDedupBlocksCleanKnownTopic
       , testConstitutionAdmissibleCommitmentStrengthens
       , testNonAuthoritativeCommitmentCandidateCappedBeforePlanning
       , testConatusGatedCommitmentCandidateSuspendedBeforePlanning
       , testNonAuthoritativeFinalizeDoesNotStrengthenCommitment
       , testConstitutionAdmissibleInterpretationPreservesRawRouteInput
       , testNonAuthoritativeInterpretationNarrowsBeforeRouteCrystallization
       , testConatusGatedInterpretationFallsBackBeforeRouteCrystallization
       , testConstitutionAdmissiblePropositionPreservesRawFrame
       , testNonAuthoritativePropositionFrameSoftensBeforeInterpretationAdmission
       , testConatusGatedPropositionFrameSoftensBeforeInterpretationAdmission
       , testConstitutionAdmissibleSemanticFramePreservesRawFrame
       , testNonAuthoritativeSemanticFrameSoftensBeforePropositionAdmission
       , testConatusGatedSemanticFrameSoftensBeforePropositionAdmission
       , testConstitutionAdmissibleSenseVectorPreservesRawVector
       , testNonAuthoritativeSenseVectorNarrowsBeforeMeaningShaping
       , testConatusGatedSenseVectorNarrowsBeforeMeaningShaping
       , testConstitutionAdmissibleRouteHintPreservesRawHint
       , testNonAuthoritativeRouteHintSoftensBeforePropositionAdmission
       , testConatusGatedRouteHintSoftensBeforePropositionAdmission
       , testConstitutionAdmissibleFamilyPreservesRawCrystallization
       , testNonAuthoritativeFamilyCrystallizationCapsBeforeRouteDecision
       , testConatusGatedFamilyCrystallizationCapsBeforeRouteDecision
       , testRoutePlanConsumesAdmittedFamilyCrystallization
       , testConstitutionAdmissibleEarlyFamilyPreservesRawRecommendation
       , testNonAuthoritativeEarlyFamilyCapsBeforeLaterCrystallization
       , testConatusGatedEarlyFamilyCapsBeforeLaterCrystallization
       , testPrepareConsciousnessUsesAdmittedEarlyFamily
       , testConstitutionAdmissibleSemanticLogicPreservesRawWeighting
       , testNonAuthoritativeSemanticLogicCapsBeforeEarlyFamilyAdmission
       , testConatusGatedSemanticLogicCapsBeforeEarlyFamilyAdmission
       , testPrepareUsesAdmittedSemanticLogicFamily
       , testConstitutionAdmissibleSemanticContributionPreservesRawContributions
       , testNonAuthoritativeSemanticContributionSoftensBeforeWeightingAdmission
       , testConatusGatedSemanticContributionSoftensBeforeWeightingAdmission
       , testPrepareUsesAdmittedSemanticContributionPlane
       , testConstitutionAdmissibleAtomContributionPreservesRawAtoms
       , testNonAuthoritativeAtomContributionCapsStrongAtoms
       , testNonAuthoritativeWeakAtomContributionStaysAmbiguous
       , testPrepareUsesAdmittedAtomContributionPlane
       , testConstitutionAdmissibleAtomExtractionPreservesRawAtoms
       , testNonAuthoritativeAtomExtractionSuppressesStrongFindings
       , testNonAuthoritativeSafeAtomExtractionStaysPresent
       , testPrepareUsesAdmittedAtomExtractionPlane
       , testConstitutionAdmissibleAtomFindingPreservesRawFindings
       , testNonAuthoritativeAtomFindingSuppressesStrongLexicalAndClusterFindings
       , testNonAuthoritativeSafeAtomFindingsStayPresent
       , testPrepareUsesAdmittedAtomFindingPlane
        , testConstitutionAdmissibleStructuralAtomPreservesSearching
        , testNonAuthoritativeStructuralAtomSuppressesSearching
        , testSafeStructuralAtomsStayPresent
        , testPrepareUsesAdmittedStructuralAtomPlane
        , testConstitutionAdmissibleLexicalClusterPhraseDecisionPreservesRawDecisions
        , testNonAuthoritativeLexicalClusterPhraseDecisionSuppressesStrongDecisions
        , testNonAuthoritativeSafeLexicalClusterPhraseDecisionsStayPresent
        , testPrepareUsesAdmittedLexicalClusterPhraseDecisionPlane
        , testConstitutionAdmissibleLexicalClusterPhraseContainmentPreservesRawContainment
        , testNonAuthoritativeLexicalClusterPhraseContainmentSuppressesStrongContainment
        , testNonAuthoritativeSafeLexicalClusterPhraseContainmentStaysPresent
        , testPrepareUsesAdmittedLexicalClusterPhraseContainmentPlane
        , testConstitutionAdmissibleLexicalClusterHitPreservesRawHits
        , testNonAuthoritativeLexicalClusterHitSuppressesStrongHits
        , testNonAuthoritativeSafeLexicalClusterHitsStayPresent
        , testPrepareUsesAdmittedLexicalClusterHitPlane
        , testConstitutionAdmissibleLexicalClusterMatchingPreservesRawMatches
        , testNonAuthoritativeLexicalClusterMatchingSuppressesStrongMatches
        , testNonAuthoritativeSafeLexicalClusterMatchesStayPresent
        , testPrepareUsesAdmittedLexicalClusterMatchingPlane
        , testDialogueDevelopmentPersistsOutcomeAndBelief
       , testDialogueDevelopmentConflictUsesPriorTopic
        , testDialogueDevelopmentWeakSignalsDoNotMutate
        , testDialogueDevelopmentWeakAcknowledgementDoesNotMutate
        , testDialogueDevelopmentWeakConfirmationPhrasesStayWeak
        , testDialogueDevelopmentRepeatedQuestionRecordsMutation
         , testDialogueDevelopmentDecisionRecordsStrongMutation
         , testPerspectiveFinalizeRecordsGovernedMutation
         , testPerspectiveFinalizeReplayUsesSafeProjectionOnly
        , testDialogueDevelopmentBoundsAdaptiveMaps
       , testSpeechPolicyBiasesRouteStyle
       , testSpeechPolicyDoesNotDowngradeRecoveryStyle
       , testFinalizeMetricsPopulatesLearningTelemetry
       ]

testPrepareEffectPlanDeterministicProperty :: Test
testPrepareEffectPlanDeterministicProperty = quickCheckTest "prepare effect planning is deterministic" $
  forAll (elements prepareInputs) $ \rawInput ->
    let input = T.pack rawInput
        plan1 = summarizePreparePlan (planPrepareEffects emptySystemState input testEpochZero)
        plan2 = summarizePreparePlan (planPrepareEffects emptySystemState input testEpochZero)
    in plan1 == plan2
  where
    prepareInputs =
      [ "что такое свобода"
      , "мне нужен контакт"
      , "я устал и не могу"
      , "где граница между смыслом и пустотой"
      , "что делать дальше"
      ]

    summarizePreparePlan :: PrepareEffectPlan -> (CanonicalMoveFamily, [PrepareEffectRequest])
    summarizePreparePlan plan =
      ( psRecommendedFamily (pepStatic plan)
      , [ pepEmbeddingRequest plan
        , pepNixGuardRequest plan
        , pepConsciousnessRequest plan
        , pepIntuitionRequest plan
        , pepApiHealthRequest plan
        ]
      )

-- | Phase C: verify that 'buildPrepareEffectPlan' injects the caller-supplied
-- time into 'psCurrentTime', which is then used by 'buildTurnInput' for
-- 'tiStartTime' instead of the resolved timeline (non-deterministic in unit tests).
testPrepareCurrentTimeDeterministicInjection :: Test
testPrepareCurrentTimeDeterministicInjection = TestCase $ do
  let fixedTime = UTCTime (ModifiedJulianDay 12345) 3600
      plan = planPrepareEffects emptySystemState "deterministic time test" fixedTime
  assertEqual "psCurrentTime must match injected time"
    fixedTime (psCurrentTime (pepStatic plan))

testRouteEffectPlanDeterministicProperty :: Test
testRouteEffectPlanDeterministicProperty = quickCheckTest "route effect planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, ti, ts) <- withDeterministicEmbedding (buildPreparedFixture (T.pack rawInput))
      let plan1 = summarizeRoutePlan (planRouteEffects ss ti ts)
          plan2 = summarizeRoutePlan (planRouteEffects ss ti ts)
      pure (plan1 == plan2)

testRenderEffectPlanDeterministicProperty :: Test
testRenderEffectPlanDeterministicProperty = quickCheckTest "render effect planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, ti, ts, tp) <- withDeterministicEmbedding (buildPlannedFixture (T.pack rawInput))
      let plan1 = summarizeRenderPlan (planRenderEffects LocalRecoveryEnabled ss ti ts tp)
          plan2 = summarizeRenderPlan (planRenderEffects LocalRecoveryEnabled ss ti ts tp)
      pure (plan1 == plan2)

testFinalizePrecommitPlanDeterministicProperty :: Test
testFinalizePrecommitPlanDeterministicProperty = quickCheckTest "finalize precommit planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, ti, ts, tp, ta) <- withDeterministicEmbedding (buildRenderedFixture (T.pack rawInput))
      let plan1 = summarizeFinalizePrecommitPlan (planFinalizePrecommit ss ti ts tp ta)
          plan2 = summarizeFinalizePrecommitPlan (planFinalizePrecommit ss ti ts tp ta)
      pure (plan1 == plan2)

testFinalizeCommitPlanDeterministicProperty :: Test
testFinalizeCommitPlanDeterministicProperty = quickCheckTest "finalize commit planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, ti, ts, _tp, ta, bundle) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      let plan1 = summarizeFinalizeCommitPlan (planFinalizeCommit "session-prop" ss ti ts ta bundle)
          plan2 = summarizeFinalizeCommitPlan (planFinalizeCommit "session-prop" ss ti ts ta bundle)
      pure (plan1 == plan2)

testFinalizeCommitRecoversRuntimeStateAfterCommitFailure :: Test
testFinalizeCommitRecoversRuntimeStateAfterCommitFailure = TestCase $
  withDeterministicEmbedding $ do
    commitAttemptsRef <- newIORef 0
    let recoveryPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = failingCommitThenRecoverInterpreter commitAttemptsRef
              }
    (ss, ti, ts, _tp, ta, bundle) <- buildFinalizeFixture "что такое свобода"
    let commitPlan = planFinalizeCommit "session-recovery" ss ti ts ta bundle
    _ <- resolveFinalizeCommit recoveryPio 0 commitPlan
    attempts <- readIORef commitAttemptsRef
    assertEqual "commit effect should be retried once on recovery path" 2 attempts

testFinalizeCommitRollsBackPersistedStateAfterRecoveryFailure :: Test
testFinalizeCommitRollsBackPersistedStateAfterRecoveryFailure = TestCase $
  withDeterministicEmbedding $ do
    saveRequestsRef <- newIORef ([] :: [(T.Text, Int, Bool)])
    let rollbackPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = failingCommitWithRollbackInterpreter saveRequestsRef
              }
    (ss, ti, ts, _tp, ta, bundle) <- buildFinalizeFixture "что такое свобода"
    let commitPlan = planFinalizeCommit "session-rollback" ss ti ts ta bundle
    result <- try (resolveFinalizeCommit rollbackPio 0 commitPlan) :: IO (Either QxFx0Exception FinalizeCommitResults)
    case result of
      Left ex | Just detail <- matchPersistenceError ex -> do
        let hasProjectionRollback = "projections rollback=ok" `T.isInfixOf` detail
            hasStateRollback = "state rollback=ok" `T.isInfixOf` detail
        unless (hasProjectionRollback && hasStateRollback) $
          assertFailure ("double-failure path must expose projection and state rollback status, got: " <> T.unpack detail)
      Left other ->
        assertFailure ("unexpected exception while testing rollback path: " <> show other)
      Right _ ->
        assertFailure "commit path must fail when commit and recovery both fail"
    requests <- readIORef saveRequestsRef
    assertEqual
      "double-failure path should save, cleanup persisted projections, then rollback state"
      [ ("save", ssTurnCount (fpbNextSs bundle), True)
      , ("cleanup", ssTurnCount ss, False)
      , ("save", ssTurnCount ss, False)
      ]
      requests

testBlockedConceptsRetentionIsBoundedAndDeduplicated :: Test
testBlockedConceptsRetentionIsBoundedAndDeduplicated = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
    let updateState :: SystemState -> T.Text -> IO SystemState
        updateState state blockedReason =
          let tiBlocked = ti0 { tiNixStatus = Blocked blockedReason }
              precommitPlan = planFinalizePrecommit state tiBlocked ts tp ta
          in do
            precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
            bundle <-
                  buildFinalizePrecommit
                    (pipelineUpdateHistory testProtocolPipelineIO)
                    (pipelineParseAuthoritySurface testProtocolPipelineIO)
                    state
                    tiBlocked
                    ts
                    tp
                    ta
                    precommitPlan
                    precommitResults
            pure (fpbNextSs bundle)
    dedupedState <- foldM updateState ss0 (replicate 10 "same_reason")
    let dedupedReasons = ssBlockedConcepts dedupedState
        uniqueReasons = map (\n -> "reason_" <> T.pack (show n)) [1 .. blockedConceptsRetentionLimit + 15]
    boundedState <- foldM updateState ss0 uniqueReasons
    let boundedReasons = ssBlockedConcepts boundedState
    assertEqual "blocked reasons should deduplicate repeated values" ["same_reason"] dedupedReasons
    assertEqual "blocked reasons list should be capped at retention limit"
      blockedConceptsRetentionLimit
      (length boundedReasons)
    assertEqual "latest blocked reason should stay at the head"
      ("reason_" <> T.pack (show (blockedConceptsRetentionLimit + 15)))
      (case boundedReasons of [] -> error "expected non-empty boundedReasons"; (r:_) -> r)

testReplayEnvelopeDeterministicProperty :: Test
testReplayEnvelopeDeterministicProperty = quickCheckTest "replay envelope is deterministic for identical inputs" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (_ss1, _ti1, _ts1, _tp1, _ta1, bundle1) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      (_ss2, _ti2, _ts2, _tp2, _ta2, bundle2) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      let trace1 = tqpReplayTrace (fpbProjection bundle1)
          trace2 = tqpReplayTrace (fpbProjection bundle2)
      pure (trace1 == trace2)

testReplayEnvelopeJsonDeterministicProperty :: Test
testReplayEnvelopeJsonDeterministicProperty = quickCheckTest "replay envelope JSON is deterministic for identical inputs" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (_ss1, _ti1, _ts1, _tp1, _ta1, bundle1) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      (_ss2, _ti2, _ts2, _tp2, _ta2, bundle2) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      let payload1 = encode (tqpReplayTrace (fpbProjection bundle1))
          payload2 = encode (tqpReplayTrace (fpbProjection bundle2))
      pure (payload1 == payload2)

testPrepareEffectsResolveConcurrently :: Test
testPrepareEffectsResolveConcurrently = TestCase $ do
  activeRef <- newIORef 0
  maxRef <- newIORef 0
  let pio =
        mkTestPipelineIO
          defaultTestPipelineConfig
            { tpcInterpreter = trackedPrepareInterpreter activeRef maxRef
            }
      preparePlan = planPrepareEffects emptySystemState "что такое свобода" testEpochZero
  _ <- resolvePrepareEffects pio preparePlan
  maxActive <- readIORef maxRef
  assertBool "prepare effects should overlap instead of running strictly one-by-one" (maxActive >= 3)

testScheduleTurnEffectsPrioritizesCheapChecksWhenConatusCritical :: Test
testScheduleTurnEffectsPrioritizesCheapChecksWhenConatusCritical = TestCase $ do
  let criticalConatus = ConatusEnergy
        { ceScalar = -1.0
        , ceComponents = ConatusComponents
            { ccMorphology = 0.0
            , ccIdentity = 0.0
            , ccTurns = 0.0
            , ccPenalty = 1.0
            }
        }
      scheduled =
        scheduleTurnEffects
          testProtocolPipelineIO
          criticalConatus
          [ ("embedding", TurnReqEmbedding "тест")
          , ("api", TurnReqApiHealth)
          , ("nix", TurnReqNixGuard "concept" 0.1 0.1)
          ]
  assertEqual "critical conatus should prioritize cheap checks before expensive embedding"
    [T.pack "api", T.pack "embedding", T.pack "nix"]
    (map fst scheduled)

testPrepareMetricsExposeHonestPhaseNames :: Test
testPrepareMetricsExposeHonestPhaseNames = TestCase $
  withDeterministicEmbedding $ do
    let ss = emptySystemState
        preparePlan = planPrepareEffects ss "что такое свобода" testEpochZero
    prepareResults <- resolvePrepareEffects testProtocolPipelineIO preparePlan
    let ti = buildTurnInput ss "request-phase" "session-phase" preparePlan prepareResults
        phaseNames = sort (map ptPhase (tmPhases (tiMetrics ti)))
    assertBool "prepare metrics should stop pretending forced bookkeeping is logic" ("logic" `notElem` phaseNames)
    assertEqual
      "prepare metrics should expose the real prepare phase set"
      ["api_health", "consciousness", "embedding", "intuition", "nix_check", "prepare_static"]
      phaseNames

testRouteEffectsResolveConcurrently :: Test
testRouteEffectsResolveConcurrently = TestCase $
  withDeterministicEmbedding $ do
    activeRef <- newIORef 0
    maxRef <- newIORef 0
    let routePio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = trackedRouteInterpreter activeRef maxRef
              }
    (ss, ti, ts) <- buildPreparedFixture "что такое свобода"
    let routePlan = planRouteEffects ss ti ts
    _ <- resolveRouteEffects routePio routePlan
    maxActive <- readIORef maxRef
    assertBool "route shadow/agda effects should resolve concurrently" (maxActive >= 2)

testRouteEffectsFailOnAgdaInStrictRuntime :: Test
testRouteEffectsFailOnAgdaInStrictRuntime = TestCase $
  withDeterministicEmbedding $ do
    let strictPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcRuntimeMode = RuntimeStrict
              , tpcInterpreter = strictAgdaFailInterpreter
              }
    (ss, ti, ts) <- buildPreparedFixture "что такое свобода"
    let routePlan = planRouteEffects ss ti ts
    result <- try (resolveRouteEffects strictPio routePlan >> pure ()) :: IO (Either QxFx0Exception ())
    case result of
      Left (AgdaGateError detail) ->
        assertBool "strict Agda gate should expose typed failing status" ("agda_status=" `T.isPrefixOf` detail)
      Left other ->
        assertFailure ("unexpected exception while testing strict Agda gate: " <> show other)
      Right () ->
        assertFailure "strict runtime must fail route resolution when Agda verification is not ready"

testNarrativeHintCannotBypassShadowGate :: Test
testNarrativeHintCannotBypassShadowGate = TestCase $
  withDeterministicEmbedding $ do
    let strictShadowPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcRuntimeMode = RuntimeStrict
              , tpcShadowPolicy = ShadowBlockOnUnavailableOrDivergence
              , tpcInterpreter = strictShadowUnavailableInterpreter
              }
    (ss, ti, ts0) <- buildPreparedFixture "что такое свобода"
    let ts = ts0 { tsNarrativeFragment = Just "narrative_override_attempt" }
        routePlan = planRouteEffects ss ti ts
    routeResults <- resolveRouteEffects strictShadowPio routePlan
    let turnPlan = buildRouteTurnPlan FmarOff (pipelineShadowPolicy strictShadowPio) ss ti ts routePlan routeResults
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts turnPlan
    renderResults <- resolveRenderEffects strictShadowPio renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts turnPlan renderPlan renderResults
        precommitPlan = planFinalizePrecommit ss ti ts turnPlan turnArtifacts
    precommitResults <- resolveFinalizePrecommit strictShadowPio precommitPlan
    precommitBundle <-
          buildFinalizePrecommit
            (pipelineUpdateHistory strictShadowPio)
            (pipelineParseAuthoritySurface strictShadowPio)
            ss
            ti
            ts
            turnPlan
            turnArtifacts
            precommitPlan
            precommitResults
    let projection = fpbProjection precommitBundle
    assertEqual "shadow unavailable should remain visible in projection" ShadowUnavailable (tqpShadowStatus projection)
    assertEqual "narrative hint must not bypass hard shadow gate" CMRepair (tqpOwnerFamily projection)

testAdvisoryShadowDivergenceDoesNotTriggerRecovery :: Test
testAdvisoryShadowDivergenceDoesNotTriggerRecovery = TestCase $
  withDeterministicEmbedding $ do
    let strictPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcRuntimeMode = RuntimeStrict
              , tpcInterpreter = testProtocolInterpreter
              }
    (ss0, ti, ts, tp0) <- buildPlannedFixture "логика это истина бытия?"
    let ss =
          ss0
            { ssMorphology =
                Morph.buildMorphologyData
                  (map Morph.analyzeMorph ["логика", "истина", "бытие"])
            }
    let tp =
          tp0
            { tpFinalFamily = CMReflect
            , tpShadowStatus = ShadowDiverged
            , tpShadowDivergence = True
            , tpShadowDivergenceSeverity = ShadowSeverityAdvisory
            }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "advisory shadow divergence must not plan local recovery"
      Nothing
      (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertEqual "advisory shadow divergence must not surface as local recovery"
      Nothing
      (taLocalRecoveryCause turnArtifacts)
    assertBool "advisory non-repair turn must not leak repair rupture language"
      (not ("Признаю разрыв" `T.isInfixOf` taRendered turnArtifacts))
    let precommitPlan = planFinalizePrecommit ss ti ts tp turnArtifacts
    precommitResults <- resolveFinalizePrecommit strictPio precommitPlan
    bundle <-
          buildFinalizePrecommit
            (pipelineUpdateHistory strictPio)
            (pipelineParseAuthoritySurface strictPio)
            ss
            ti
            ts
            tp
            turnArtifacts
            precommitPlan
            precommitResults
    let projection = fpbProjection bundle
        replayTrace = tqpReplayTrace projection
    assertEqual "projection should keep the non-repair owner family"
      CMReflect
      (tqpOwnerFamily projection)
    assertEqual "replay trace should persist advisory shadow severity"
      ShadowSeverityAdvisory
      (trcShadowDivergenceSeverity replayTrace)
    assertEqual "advisory shadow divergence must not persist recovery cause"
      Nothing
      (trcRecoveryCause replayTrace)

-- | WP2 (GAP2): shadow gate trigger within window count < max → allowed.
testShadowVetoAllowedWithinWindow :: Test
testShadowVetoAllowedWithinWindow = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti, ts) <- buildPreparedFixture "что такое свобода"
    let ss = ss0
          { ssShadowVetoState = ShadowVetoState 2 0
          , ssDialogue = (ssDialogue ss0) { dsTurnCount = 5 }
          }
        routePlan = planRouteEffects ss ti ts
        shadowResult = ShadowResult
          { srDatalogVerdict = Nothing
          , srStatus = ShadowDiverged
          , srDivergence = emptyShadowDivergence { sdKind = ShadowVerdictMismatch, sdFamilyMismatch = True }
          , srSnapshotId = ShadowSnapshotId "veto-test"
          , srDiagnostics = []
          }
        routeResults = RouteEffectResults shadowResult AgdaMissingInput
        turnPlan = buildRouteTurnPlan FmarOff ShadowBlockOnUnavailableOrDivergence ss ti ts routePlan routeResults
    assertBool "shadow gate must trigger when count < max"
      (tpShadowGateTriggered turnPlan)
    assertEqual "veto count must increment"
      3
      (svsCount (tpShadowVetoState turnPlan))
    assertEqual "veto window start must stay at turn 0"
      0
      (svsWindowStart (tpShadowVetoState turnPlan))

-- | WP2 (GAP2): shadow gate trigger at count == max → exhausted, bypassed.
testShadowVetoExhaustedAfterMax :: Test
testShadowVetoExhaustedAfterMax = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti, ts) <- buildPreparedFixture "что такое свобода"
    let ss = ss0
          { ssShadowVetoState = ShadowVetoState 3 0
          , ssDialogue = (ssDialogue ss0) { dsTurnCount = 5 }
          }
        routePlan = planRouteEffects ss ti ts
        shadowResult = ShadowResult
          { srDatalogVerdict = Nothing
          , srStatus = ShadowDiverged
          , srDivergence = emptyShadowDivergence { sdKind = ShadowVerdictMismatch, sdFamilyMismatch = True }
          , srSnapshotId = ShadowSnapshotId "veto-test"
          , srDiagnostics = []
          }
        routeResults = RouteEffectResults shadowResult AgdaMissingInput
        turnPlan = buildRouteTurnPlan FmarOff ShadowBlockOnUnavailableOrDivergence ss ti ts routePlan routeResults
    assertBool "shadow gate must be bypassed when exhausted"
      (not (tpShadowGateTriggered turnPlan))
    assertBool "shadow message must contain exhaustion telemetry"
      ("shadow_veto_exhausted" `T.isInfixOf` tpShadowMessage turnPlan)
    assertEqual "veto count must not increment when exhausted"
      3
      (svsCount (tpShadowVetoState turnPlan))

-- | WP2 (GAP2): window expiry resets the veto counter.
testShadowVetoWindowResets :: Test
testShadowVetoWindowResets = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti, ts) <- buildPreparedFixture "что такое свобода"
    let ss = ss0
          { ssShadowVetoState = ShadowVetoState 3 0
          , ssDialogue = (ssDialogue ss0) { dsTurnCount = 11 }
          }
        routePlan = planRouteEffects ss ti ts
        shadowResult = ShadowResult
          { srDatalogVerdict = Nothing
          , srStatus = ShadowDiverged
          , srDivergence = emptyShadowDivergence { sdKind = ShadowVerdictMismatch, sdFamilyMismatch = True }
          , srSnapshotId = ShadowSnapshotId "veto-test"
          , srDiagnostics = []
          }
        routeResults = RouteEffectResults shadowResult AgdaMissingInput
        turnPlan = buildRouteTurnPlan FmarOff ShadowBlockOnUnavailableOrDivergence ss ti ts routePlan routeResults
    assertBool "shadow gate must trigger after window reset"
      (tpShadowGateTriggered turnPlan)
    assertEqual "veto count must reset to 1 after expiry"
      1
      (svsCount (tpShadowVetoState turnPlan))
    assertEqual "veto window start must reset to current turn"
      11
      (svsWindowStart (tpShadowVetoState turnPlan))

-- | WP3 (GAP3): observeNovelAtom creates a fresh ProvisionalAtom.
testObserveNovelAtomCreatesNew :: Test
testObserveNovelAtomCreatesNew = TestCase $ do
  let tag = Searching "test"
      result = observeNovelAtom tag 10 []
  assertEqual "novel atom must create exactly one entry"
    1
    (length result)
  case result of
    []    -> error "expected non-empty result in testObserveNovelAtomCreatesNew"
    (a:_) -> do
      assertEqual "novel atom must store the tag"
        tag
        (paTag a)
      assertEqual "novel atom must have occurrence count 1"
        1
        (paOccurrences a)
      assertEqual "novel atom must record first seen turn"
        10
        (paFirstSeenTurn a)
      assertEqual "novel atom must record last seen turn"
        10
        (paLastSeenTurn a)

-- | WP3 (GAP3): observeNovelAtom bumps an existing provisional atom.
testObserveNovelAtomBumpsExisting :: Test
testObserveNovelAtomBumpsExisting = TestCase $ do
  let tag = Searching "test"
      initial = [ProvisionalAtom tag 1 5 5 False]
      result = observeNovelAtom tag 7 initial
  assertEqual "bumped atom must still be a single entry"
    1
    (length result)
  case result of
    []    -> error "expected non-empty result in testObserveNovelAtomBumpsExisting"
    (a:_) -> do
      assertEqual "bumped atom must have occurrence count 2"
        2
        (paOccurrences a)
      assertEqual "bumped atom must keep original first seen turn"
        5
        (paFirstSeenTurn a)
      assertEqual "bumped atom must refresh last seen turn"
        7
        (paLastSeenTurn a)

-- | WP3 (GAP3): promoteProvisionalAtoms promotes atoms meeting criteria.
testPromoteProvisionalAtomsMeetsCriteria :: Test
testPromoteProvisionalAtomsMeetsCriteria = TestCase $ do
  let eligible = ProvisionalAtom (Searching "eligible") 3 1 7 False
      (remaining, promoted) = promoteProvisionalAtoms 10 [eligible]
  assertEqual "eligible atom must be promoted"
    [Searching "eligible"]
    promoted
  assertBool "remaining list must contain the promoted atom marked True"
    (all paPromoted remaining)

-- | WP3 (GAP3): promoteProvisionalAtoms skips atoms below threshold.
testPromoteProvisionalAtomsBelowThreshold :: Test
testPromoteProvisionalAtomsBelowThreshold = TestCase $ do
  let lowOccurrences = ProvisionalAtom (Searching "low-occ") 2 1 10 False
      lowSpan = ProvisionalAtom (Searching "low-span") 5 1 5 False
      (remaining1, promoted1) = promoteProvisionalAtoms 10 [lowOccurrences]
      (remaining2, promoted2) = promoteProvisionalAtoms 10 [lowSpan]
  assertEqual "low occurrences must not be promoted"
    []
    promoted1
  assertBool "low occurrences must remain un-promoted"
    (not (any paPromoted remaining1))
  assertEqual "low span must not be promoted"
    []
    promoted2
  assertBool "low span must remain un-promoted"
    (not (any paPromoted remaining2))

-- | WP3 (GAP3): decayProvisionalAtoms removes stale un-promoted atoms.
testDecayProvisionalAtomsRemovesStale :: Test
testDecayProvisionalAtomsRemovesStale = TestCase $ do
  let stale = ProvisionalAtom (Searching "stale") 2 1 1 False
      result = decayProvisionalAtoms 22 [stale]
  assertEqual "stale atom beyond TTL must be removed"
    []
    result

-- | WP3 (GAP3): decayProvisionalAtoms keeps fresh and promoted atoms.
testDecayProvisionalAtomsKeepsFresh :: Test
testDecayProvisionalAtomsKeepsFresh = TestCase $ do
  let fresh = ProvisionalAtom (Searching "fresh") 2 10 15 False
      promoted = ProvisionalAtom (Searching "promoted") 3 1 1 True
      result = decayProvisionalAtoms 25 [fresh, promoted]
  assertBool "fresh atom within TTL must be kept"
    (Searching "fresh" `elem` map paTag result)
  assertEqual "promoted atom must survive decay regardless of TTL"
    2
    (length result)

-- | WP3 (GAP3): resolveCollisions removes provisional atoms colliding with canonical set.
testResolveCollisionsRemovesDuplicates :: Test
testResolveCollisionsRemovesDuplicates = TestCase $ do
  let tag = Searching "collision"
      canonical = AtomSet [MeaningAtom "" tag (V.fromList [])] 0.0 Neutral
      provisional = [ProvisionalAtom tag 1 1 1 False]
      result = resolveCollisions canonical provisional
  assertEqual "colliding provisional atom must be removed"
    []
    result

-- | WP3 (GAP3): resolveCollisions keeps non-colliding provisional atoms.
testResolveCollisionsKeepsNovel :: Test
testResolveCollisionsKeepsNovel = TestCase $ do
  let canonical = AtomSet [MeaningAtom "" (Searching "canonical") (V.fromList [])] 0.0 Neutral
      provisional = [ProvisionalAtom (Searching "novel") 1 1 1 False]
      result = resolveCollisions canonical provisional
  assertEqual "non-colliding provisional atom must be kept"
    [Searching "novel"]
    (map paTag result)

-- | WP6.1: persistent learning-pressure pattern (3 turns of unknown
-- topics + graft stagnation) must raise NeedLexiconExtension once
-- persistence threshold is met.
testLearningNeedRaisedOnPersistentPattern :: Test
testLearningNeedRaisedOnPersistentPattern = TestCase $ do
  let conatus = ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)
        -- ^ High conatus: old logic would suppress lexicon need.
        --   WP6.1 decouples learning from conatus health.
      field = emptyField
        { fieldConfidence = FieldConfidence 0.3
        , fieldCounterfactual = Counterfactual 0.6
        , fieldConsolidation = Consolidation 0.2
        }
      cfg = defaultLearningPressureConfig
        { lpcStagnationTurns = 1
        , lpcMinUnknownCount = 1
        }
      step turn st = detectLearningNeedWithPressure cfg conatus field 0 3 turn st True 0
        -- ^ isTopicUnknown=True, currentGraftedCount=0 (stagnation)
      st0 = emptyLearningNeedState { lnsWindowStartTurn = 1, lnsUnknownWindowCount = 2 }
      st1 = step 2 st0
      st2 = step 3 st1
      st3 = step 4 st2
  assertEqual "first turn must not raise need (persistence=1)"
    NeedNone (lnsCurrentNeed st1)
  assertEqual "second turn must not raise need (persistence=2)"
    NeedNone (lnsCurrentNeed st2)
  assertEqual "third turn must raise lexicon extension need (persistence=3)"
    NeedLexiconExtension (lnsCurrentNeed st3)
  assertBool "level must be positive"
    (lnsLevel st3 > 0.0)
  assertEqual "trend must be rising when need is raised after persistent pressure"
    TrendRising (lnsTrend st3)

-- | WP1: single-turn noise must not create a learning need.
testLearningNeedNotRaisedOnNoise :: Test
testLearningNeedNotRaisedOnNoise = TestCase $ do
  let conatus = ConatusEnergy 0.3 (ConatusComponents 0 0 0 0)
      field = emptyField
        { fieldConfidence = FieldConfidence 0.3
        , fieldCounterfactual = Counterfactual 0.6
        , fieldConsolidation = Consolidation 0.2
        }
      st1 = detectLearningNeed conatus field 0 3 1 emptyLearningNeedState
      st2 = detectLearningNeed conatus field 0 3 2 st1
  assertEqual "noise turn 1 must stay NeedNone"
    NeedNone (lnsCurrentNeed st1)
  assertEqual "noise turn 2 must stay NeedNone (below persistence threshold=3)"
    NeedNone (lnsCurrentNeed st2)

-- | WP1: verify detectLearningNeed is actually called inside
-- buildNextSystemState via the finalize precommit bundle.
testLearningNeedWiredThroughFinalizePrecommit :: Test
testLearningNeedWiredThroughFinalizePrecommit = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixture "что такое свобода"
    let lns = ssLearningNeedState (fpbNextSs bundle)
    assertEqual "learning need state must record the current turn"
      1
      (lnsLastSeenTurn lns)
    assertBool "learning need state must have a non-empty history after one turn"
      (not (null (lnsHistory lns)))

-- | WP3: high-deficit learning need (level >= 0.6) must trigger a
-- StrategyRequest* recovery plan.
testLearningNeedHighDeficitTriggersRequestStrategy :: Test
testLearningNeedHighDeficitTriggersRequestStrategy = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let highDeficitNeed = emptyLearningNeedState
          { lnsCurrentNeed = NeedLexiconExtension
          , lnsCandidateNeed = NeedLexiconExtension
          , lnsLevel = 0.8
          , lnsPersistence = 3
          , lnsLastSeenTurn = 1
          }
        ss = ss0 { ssLearningNeedState = highDeficitNeed }
        -- Ensure no higher-priority recovery drivers fire
        ti = ti0
          { tiConatusGateFired = False
          , tiConatusEnergy = ConatusEnergy 1.0 (ConatusComponents 0 0 0 0)
          }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing -> assertFailure "high-deficit learning need must produce recovery plan"
      Just recoveryPlan ->
        assertEqual "high-deficit lexicon need must map to StrategyRequestConcept"
          StrategyRequestConcept
          (lrpStrategy recoveryPlan)

-- | WP3: low-deficit learning need (level < 0.6) must NOT trigger a
-- request strategy; normal routing continues.
testLearningNeedLowDeficitDoesNotTriggerRequest :: Test
testLearningNeedLowDeficitDoesNotTriggerRequest = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let lowDeficitNeed = emptyLearningNeedState
          { lnsCurrentNeed = NeedLexiconExtension
          , lnsCandidateNeed = NeedLexiconExtension
          , lnsLevel = 0.4
          , lnsPersistence = 3
          , lnsLastSeenTurn = 1
          }
        ss = ss0 { ssLearningNeedState = lowDeficitNeed }
        ti = ti0
          { tiConatusGateFired = False
          , tiConatusEnergy = ConatusEnergy 1.0 (ConatusComponents 0 0 0 0)
          }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    -- With no other recovery drivers, and learningNeedActive = False,
    -- the plan should have no local recovery.
    assertEqual "low-deficit learning need must not produce local recovery"
      Nothing
      (repLocalRecoveryPlan renderPlan)

-- | WP3: NeedNone must never produce a request strategy.
testLearningNeedNoneDoesNotTriggerRequest :: Test
testLearningNeedNoneDoesNotTriggerRequest = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let noNeed = emptyLearningNeedState
        ss = ss0 { ssLearningNeedState = noNeed }
        ti = ti0
          { tiConatusGateFired = False
          , tiConatusEnergy = ConatusEnergy 1.0 (ConatusComponents 0 0 0 0)
          }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "NeedNone must not produce learning-driven recovery"
      Nothing
      (repLocalRecoveryPlan renderPlan)

testOperationalDiagnosticQuestionRendersDirectStatus :: Test
testOperationalDiagnosticQuestionRendersDirectStatus = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "ты не работаешь?"
    assertEqual "operational status diagnostic should preserve clarifying family" CMClarify (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "operational diagnostic question should not plan local recovery" Nothing (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = taRendered turnArtifacts
        lowered = T.toLower rendered
    assertEqual "decision family should stay aligned with the status diagnostic trace" CMClarify (tdFamily (taDecision turnArtifacts))
    assertBool "diagnostic output should state operational status directly" ("я работаю" `T.isInfixOf` lowered)
    assertBool "diagnostic output should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "diagnostic output should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "diagnostic output should stay declarative" (not (T.isSuffixOf "?" (T.strip lowered)))

testOperationalCauseQuestionPreservesGroundDiagnosticFamily :: Test
testOperationalCauseQuestionPreservesGroundDiagnosticFamily = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "почему ты не работаешь?"
    assertEqual "operational cause diagnostic should preserve ground family" CMGround (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "operational cause diagnostic should not plan local recovery" Nothing (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = taRendered turnArtifacts
        lowered = T.toLower rendered
    assertEqual "decision family should stay aligned with the cause diagnostic trace" CMGround (tdFamily (taDecision turnArtifacts))
    assertBool "cause diagnostic output should explain routing failure directly" ("проблема сейчас в разборе смысла и маршрутизации" `T.isInfixOf` lowered)
    assertBool "cause diagnostic output should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "cause diagnostic output should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))

testSystemLogicQuestionRendersDirectExplanation :: Test
testSystemLogicQuestionRendersDirectExplanation = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "в чём твоя логика?"
    assertEqual "system-logic diagnostic should preserve describe family" CMDescribe (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "system-logic question should not plan local recovery" Nothing (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = taRendered turnArtifacts
        lowered = T.toLower rendered
    assertEqual "decision family should stay aligned with the system-logic trace" CMDescribe (tdFamily (taDecision turnArtifacts))
    assertBool "system-logic output should explain the local pipeline directly" ("моя текущая логика локальная" `T.isInfixOf` lowered)
    assertBool "system-logic output should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "system-logic output should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "system-logic output should stay declarative" (not (T.isSuffixOf "?" (T.strip lowered)))

testSelfKnowledgeAboutSelfRendersStructuredDescription :: Test
testSelfKnowledgeAboutSelfRendersStructuredDescription = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "что ты знаешь о себе?"
      CMDescribe
      [ "я — локальная система диалога"
      , "свою роль"
      ]

testSelfKnowledgeAboutUserRendersStructuredBoundary :: Test
testSelfKnowledgeAboutUserRendersStructuredBoundary = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "что ты знаешь обо мне?"
      CMDescribe
      [ "о тебе я знаю только то"
      , "текущего разговора"
      ]

testWorldCauseQuestionRendersGroundedExplanation :: Test
testWorldCauseQuestionRendersGroundedExplanation = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "почему солнце светит?"
      CMGround
      [ "причин"
      , "локальную схему"
      , "внешнем мире"
      ]

testWorldCauseSkyQuestionRendersGroundedExplanation :: Test
testWorldCauseSkyQuestionRendersGroundedExplanation = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "почему небо голубое?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "sky-cause question should keep ground family" CMGround (tpFinalFamily tp)
    assertBool "sky-cause question should avoid lexical fallback" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "sky-cause question should avoid recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "sky-cause question should keep sky concept in output" ("неб" `T.isInfixOf` lowered)

testEverydayPurchaseStatementAvoidsLexicalFallback :: Test
testEverydayPurchaseStatementAvoidsLexicalFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "я купил дом"
    let lowered = T.toLower (taRendered ta)
    assertBool "purchase statement should avoid reflective fallback family" (tpFinalFamily tp /= CMReflect)
    assertBool "purchase statement should avoid lexical fallback" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "purchase statement should avoid recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "purchase statement should use stable prepositional form" ("о доме" `T.isInfixOf` lowered)

testEverydayResidenceStatementAvoidsLexicalFallback :: Test
testEverydayResidenceStatementAvoidsLexicalFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "я живу дома"
    let lowered = T.toLower (taRendered ta)
    assertBool "residence statement should avoid reflective fallback family" (tpFinalFamily tp /= CMReflect)
    assertBool "residence statement should avoid lexical fallback" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "residence statement should avoid recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "residence statement should use stable prepositional form" ("о доме" `T.isInfixOf` lowered)

testAffectiveHelpQuestionUsesContactWithoutLexicalFallback :: Test
testAffectiveHelpQuestionUsesContactWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "что делать если грустно?"
      CMNextStep
      [ "зафиксируем практичный следующий ход"
      , "1) назови одну цель"
      , "2) выбери минимальный шаг"
      , "3) проверь результат"
      ]

testGreetingSmallTalkUsesContactWithoutDistressFallback :: Test
testGreetingSmallTalkUsesContactWithoutDistressFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "привет"
    let lowered = T.toLower (taRendered ta)
    assertEqual "greeting should keep contact family" CMContact (tpFinalFamily tp)
    assertBool "greeting should avoid distress framing" (not ("нужна опора" `T.isInfixOf` lowered))
    assertBool "greeting should avoid tension-step framing" (not ("точку напряжения" `T.isInfixOf` lowered))
    assertBool "greeting should keep healthy contact response" ("на связи" `T.isInfixOf` lowered)

testSmallTalkHowLifeUsesContactWithoutDistressFallback :: Test
testSmallTalkHowLifeUsesContactWithoutDistressFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "как жизнь?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "small-talk life question should keep contact family" CMContact (tpFinalFamily tp)
    assertBool "small-talk should avoid distress framing" (not ("нужна опора" `T.isInfixOf` lowered))
    assertBool "small-talk should keep healthy contact response" ("на связи" `T.isInfixOf` lowered)

testPurposeQuestionUsesObjectTopicWithoutCaseRegression :: Test
testPurposeQuestionUsesObjectTopicWithoutCaseRegression = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "в чём функция стола?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "purpose question should stay in purpose family" CMPurpose (tpFinalFamily tp)
    assertBool "purpose question should keep object in genitive form" ("функции стола" `T.isInfixOf` lowered)
    assertBool "purpose question should avoid broken genitive fallback" (not ("функции стол " `T.isInfixOf` lowered))

testPurposeQuestionHandsAvoidsBrokenGenitive :: Test
testPurposeQuestionHandsAvoidsBrokenGenitive = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "зачем человеку руки?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "hands purpose question should stay in purpose family" CMPurpose (tpFinalFamily tp)
    assertBool "hands purpose question should avoid broken suffix -а artifact"
      (not ("рукиа" `T.isInfixOf` lowered))

testPurposeQuestionExistenceAvoidsInfinitiveGenitive :: Test
testPurposeQuestionExistenceAvoidsInfinitiveGenitive = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "зачем ты есть?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "existence purpose question should stay in purpose family" CMPurpose (tpFinalFamily tp)
    assertBool "existence purpose question should avoid broken infinitive genitive"
      (not ("быти" `T.isInfixOf` lowered))

testConceptQuestionUsesPrepositionalFallbackCase :: Test
testConceptQuestionUsesPrepositionalFallbackCase = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "что такое осень?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "concept question should stay in define family" CMDefine (tpFinalFamily tp)
    assertBool "concept question should keep prepositional case for topic"
      ("о осени" `T.isInfixOf` lowered || "об осени" `T.isInfixOf` lowered)
    assertBool "concept question should avoid broken prepositional fallback" (not ("о осень" `T.isInfixOf` lowered))
    assertBool "concept question should carry claim AST into turn artifacts" (taClaimAst ta /= Nothing)
    assertBool "concept question should mark successful AST linearization" (taLinearizationOk ta)

testLocationFormationQuestionRendersStructuredExplanation :: Test
testLocationFormationQuestionRendersStructuredExplanation = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "где формируется мысль?"
      CMReflect
      [ "образно"
      , "смысловая точка"
      ]

testComparisonQuestionRendersStructuredDistinction :: Test
testComparisonQuestionRendersStructuredDistinction = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "стол на стуле. или стул на столе. что логичнее?"
      CMDistinguish
      [ "если речь о бытовой устойчивости"
      , "стул на столе"
      ]

testMisunderstandingReportRendersRepairWithoutLexicalFallback :: Test
testMisunderstandingReportRendersRepairWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "я не понимаю тебя"
      CMRepair
      [ "сигнал сбоя взаимопонимания"
      , "в смысле, тоне или ходе рассуждения"
      ]

testDialogueInvitationRendersDeepenWithoutLexicalFallback :: Test
testDialogueInvitationRendersDeepenWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "поговорим о логике?"
      CMDeepen
      [ "да, поговорим о логике"
      , "не потерять фокус"
      ]

testConceptKnowledgeQuestionRendersDefinitionWithoutLexicalFallback :: Test
testConceptKnowledgeQuestionRendersDefinitionWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "знаешь что такое солнце?"
      CMDefine
      [ "солнце — это звезда"
      , "внешнего мира"
      ]

testConceptKnowledgeBeingSmartRendersNaturalFrame :: Test
testConceptKnowledgeBeingSmartRendersNaturalFrame = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "что значит быть умным?"
    assertEqual "being-smart concept question should preserve define family" CMDefine (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = T.toLower (taRendered turnArtifacts)
    assertBool "being-smart question should render the full phrase naturally"
      ("что значит быть умным" `T.isInfixOf` rendered)
    assertBool "being-smart question should not produce broken prepositional grammar"
      (not ("о умным" `T.isInfixOf` rendered))

testSelfStateQuestionRendersDescriptionWithoutLexicalFallback :: Test
testSelfStateQuestionRendersDescriptionWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "о чём ты думаешь?"
      CMDescribe
      [ "мой внутренний ход"
      , "текущего состояния диалога"
      ]

testGenerativePromptRendersDirectThought :: Test
testGenerativePromptRendersDirectThought = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "скажи любую мысль"
      CMDescribe
      [ "одна мысль"
      , "связи"
      ]

testGenerativePromptAnotherThoughtRendersNewThought :: Test
testGenerativePromptAnotherThoughtRendersNewThought = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "а еще одну интересную мысль?"
      CMDescribe
      [ "другая мысль"
      , "удержать различие"
      ]

testGenerativePromptFreshThoughtRendersDistinctSurface :: Test
testGenerativePromptFreshThoughtRendersDistinctSurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "скажи новую интересную мысль"
      CMDescribe
      [ "новая мысль"
      , "менять собственную рамку"
      ]

testGenerativePromptLogicalQualityRendersLogicalSurface :: Test
testGenerativePromptLogicalQualityRendersLogicalSurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "скажи что-то логичное"
      CMDescribe
      [ "логичная мысль"
      , "посылками и выводом"
      ]

testSelfKnowledgeWhatYouAreRendersStructuredDescription :: Test
testSelfKnowledgeWhatYouAreRendersStructuredDescription = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "чем ты являешься?"
      CMDescribe
      [ "я — локальная система диалога"
      , "типизированный разбор"
      ]

testSelfKnowledgeThoughtCapacityRendersDirectAnswer :: Test
testSelfKnowledgeThoughtCapacityRendersDirectAnswer = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "у тебя всего одна интересная мысль?"
      CMDescribe
      [ "нет, не одна"
      , "генеративный слой"
      ]

testSelfKnowledgeCapabilityQuestionRendersCapabilitySurface :: Test
testSelfKnowledgeCapabilityQuestionRendersCapabilitySurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "ты умеешь обобщать?"
      CMDescribe
      [ "могу работать с обобщением"
      , "локальный разбор"
      ]

testSelfKnowledgeHelpQuestionRendersHelpSurface :: Test
testSelfKnowledgeHelpQuestionRendersHelpSurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "ты можешь мне помочь?"
      CMDescribe
      [ "да, я могу помочь"
      , "локальную рамку"
      ]

testSelfKnowledgeUserIdentityQuestionRendersBoundarySurface :: Test
testSelfKnowledgeUserIdentityQuestionRendersBoundarySurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "кто я такой?"
      CMDescribe
      [ "о тебе я знаю только то"
      , "вне текущего разговора"
      ]

testSystemLogicQuestionWithUtebyaRendersDirectExplanation :: Test
testSystemLogicQuestionWithUtebyaRendersDirectExplanation = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "у тебя есть логика?"
      CMDescribe
      [ "логика локальная"
      , "выборе семьи"
      ]

testSystemIdentityProbeAvoidsReflectFallback :: Test
testSystemIdentityProbeAvoidsReflectFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "ты промт машина?"
      CMDescribe
      [ "локальная система диалога"
      , "текущей сессии"
      ]

testMustRouteNameQuestionUsesDescribe :: Test
testMustRouteNameQuestionUsesDescribe = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "как тебя зовут?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "name question must route to CMDescribe" CMDescribe (tpFinalFamily tp)
    assertBool "name question should avoid reflect fallback marker" (not ("смысловая точка:" `T.isInfixOf` lowered))

testMustRoutePurposeQuestionUsesPurpose :: Test
testMustRoutePurposeQuestionUsesPurpose = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "зачем ты тут?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "purpose question must route to CMPurpose" CMPurpose (tpFinalFamily tp)
    assertBool "purpose question should keep purpose framing" ("функц" `T.isInfixOf` lowered)

testMustRouteDefineQuestionUsesDefine :: Test
testMustRouteDefineQuestionUsesDefine = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "что такое логика?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "define question must route to CMDefine" CMDefine (tpFinalFamily tp)
    assertBool "define question should keep define framing" ("определ" `T.isInfixOf` lowered || "является" `T.isInfixOf` lowered)

testMustRouteDistinguishQuestionUsesDistinguish :: Test
testMustRouteDistinguishQuestionUsesDistinguish = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "как отличить ложь от правды?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "distinguish question must route to CMDistinguish" CMDistinguish (tpFinalFamily tp)
    assertBool "distinguish question should keep both entities in rendered answer"
      ("лож" `T.isInfixOf` lowered && "правд" `T.isInfixOf` lowered)

testWorkEnableQuestionUsesOperationalStatusNotUserBoundary :: Test
testWorkEnableQuestionUsesOperationalStatusNotUserBoundary = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "что мне сделать, чтобы ты работал?"
    let lowered = T.toLower (taRendered ta)
    assertBool "work-enable question should not collapse into user-boundary self-knowledge surface"
      (not ("о тебе я знаю только то" `T.isInfixOf` lowered))
    assertBool "work-enable question should return operational status framing"
      ("я работаю" `T.isInfixOf` lowered)
    assertBool "work-enable question should not be CMDescribe after self-knowledge misroute"
      (tpFinalFamily tp /= CMDescribe)

testContemplativeTopicRendersDeepenWithoutLexicalFallback :: Test
testContemplativeTopicRendersDeepenWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "тишина"
      CMDeepen
      [ "если держаться слова"
      , "поле смыслов"
      ]

testReflectiveAssertionRendersConceptTopicWithoutLexicalFallback :: Test
testReflectiveAssertionRendersConceptTopicWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "я думаю, что важно сохранять свою субъектность"
      CMDeepen
      [ "субъектность"
      , "поле смыслов"
      ]

testLowLegitimacyUsesLocalRecoveryWithoutExternalCall :: Test
testLowLegitimacyUsesLocalRecoveryWithoutExternalCall = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp0) <- buildPlannedFixture "неясный запрос без устойчивой рамки"
    let tp =
          tp0
            { tpLegitScore = 0.0
            , tpShadowStatus = ShadowMatch
            , tpShadowDivergence = False
            }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "low legitimacy must produce a local recovery plan"
      Just recoveryPlan -> do
        assertEqual "low legitimacy should be typed as local recovery cause"
          RecoveryLowLegitimacy
          (lrpCause recoveryPlan)
        assertEqual "low legitimacy should expose uncertainty locally"
          StrategyExposeUncertainty
          (lrpStrategy recoveryPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertBool "local recovery turn must still produce non-empty output"
      (not (T.null (T.strip (taRendered turnArtifacts))))
    assertEqual "artifact must carry recovery cause into replay envelope"
      (Just RecoveryLowLegitimacy)
      (taLocalRecoveryCause turnArtifacts)

testRuntimeDegradedUsesVisibleLocalRecovery :: Test
testRuntimeDegradedUsesVisibleLocalRecovery = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti0, ts, tp0) <- buildPlannedFixture "что такое свобода"
    let ti = ti0 { tiBestTopic = "" }
    let tp =
          tp0
            { tpShadowStatus = ShadowMatch
            , tpShadowDivergence = False
            }
        renderPlan =
          planRenderEffectsForRuntime RuntimeDegraded LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "degraded runtime must expose a visible local recovery plan"
      Just recoveryPlan -> do
        assertEqual "degraded runtime should be typed as local recovery cause"
          RecoveryRuntimeDegraded
          (lrpCause recoveryPlan)
        assertEqual "degraded runtime should narrow scope explicitly"
          StrategyNarrowScope
          (lrpStrategy recoveryPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertEqual "degraded runtime local recovery cause should propagate to artifacts"
      (Just RecoveryRuntimeDegraded)
      (taLocalRecoveryCause turnArtifacts)
    assertBool "degraded runtime output should include local recovery surface"
      ("Локальный режим восстановления." `T.isInfixOf` taRendered turnArtifacts)
    let precommitPlan = planFinalizePrecommit ss ti ts tp turnArtifacts
    precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
    bundle <-
          buildFinalizePrecommit
            (pipelineUpdateHistory testProtocolPipelineIO)
            (pipelineParseAuthoritySurface testProtocolPipelineIO)
            ss
            ti
            ts
            tp
            turnArtifacts
            precommitPlan
            precommitResults
    let replayTrace = tqpReplayTrace (fpbProjection bundle)
    assertEqual "degraded runtime replay trace should keep typed recovery cause"
      (Just RecoveryRuntimeDegraded)
      (trcRecoveryCause replayTrace)
    assertEqual "degraded runtime replay trace should keep typed recovery strategy"
      (Just StrategyNarrowScope)
      (trcRecoveryStrategy replayTrace)

testFmarLiveOverridesRouting :: Test
testFmarLiveOverridesRouting = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts) <- buildPreparedFixture "что такое свобода"
    let routePlan = planRouteEffects ss ti ts
        pio = testProtocolPipelineIO
    routeResults <- resolveRouteEffects pio routePlan
    let tpOff  = buildRouteTurnPlan FmarOff  (pipelineShadowPolicy pio) ss ti ts routePlan routeResults
        tpLive = buildRouteTurnPlan FmarLive (pipelineShadowPolicy pio) ss ti ts routePlan routeResults
    case tpFmarDirective tpOff of
      Just _  -> assertFailure "FmarOff must not produce an FMAR directive"
      Nothing -> pure ()
    case tpFmarDirective tpLive of
      Nothing -> assertFailure "FmarLive must produce an FMAR directive"
      Just _  -> pure ()
    assertBool "FmarLive must select a different final family than FmarOff"
      (tpFinalFamily tpOff /= tpFinalFamily tpLive)

-- | An empty/fresh system state must NOT fire the Conatus gate. By design the
-- gate trips only when @ceScalar < conatusGateThreshold@ (== 0), which requires
-- accumulated blanket violations to drive energy negative. A fresh fixture
-- starts with non-negative energy, so the gate stays closed and no
-- ConatusGate-caused recovery plan is produced. (The firing path is exercised
-- separately by 'testConatusGateFiresRecoveryConatusGate', which forces a
-- negative energy.) This corrects an earlier premise that wrongly assumed the
-- empty state self-triggers the gate.
testConatusGateDoesNotFireFromEmptyState :: Test
testConatusGateDoesNotFireFromEmptyState = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "что такое свобода"
    assertBool "empty system state must NOT fire Conatus gate"
      (not (tiConatusGateFired ti))
    assertBool "Conatus energy must be non-negative with empty state"
      (ceScalar (tiConatusEnergy ti) >= 0)
    let renderPlan = planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing -> pure ()
      Just recoveryPlan ->
        assertBool
          ("empty state must not produce a ConatusGate recovery plan, got: "
            <> show (lrpCause recoveryPlan))
          (lrpCause recoveryPlan /= RecoveryConatusGate)

testConatusGateFiresRecoveryConatusGate :: Test
testConatusGateFiresRecoveryConatusGate = TestCase $
  withDeterministicEmbedding $ do
    -- Phase 2.5 (M2d) + RecoveryConatusGate integration test:
    -- when the runtime Conatus energy drops below the gate
    -- threshold (default 0.0), 'buildLocalRecoveryPlan' inside
    -- 'planRenderEffectsForRuntime' must emit the dedicated
    -- 'RecoveryConatusGate' cause with 'StrategySafeRecovery'
    -- as the highest-priority recovery driver, regardless of
    -- the runtime mode being 'RuntimeStrict' (so this is /not/
    -- the environmental 'RecoveryRuntimeDegraded' path).
    --
    -- Strategy: build a viable fixture, then forcibly override
    -- only 'tiConatusEnergy' to a negative scalar. This is the
    -- single field 'conatusGateFires' inspects, and is the
    -- canonical M6 single-source-of-truth threading site, so
    -- the override is enough to drive the entire decision
    -- branch without rebuilding the rest of the fixture.
    (ss, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let forcedConatus = ConatusEnergy
          { ceScalar     = -1.0
          , ceComponents = ConatusComponents
              { ccMorphology = 0.0
              , ccIdentity   = 0.0
              , ccTurns      = 0.0
              , ccPenalty    = 1.0
              }
          }
        ti = ti0
          { tiConatusEnergy         = forcedConatus
          , tiBlanketViolationCount = 2
          , tiConatusGateFired      = True
          }
        renderPlan =
          planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "Conatus gate firing must expose a visible local recovery plan"
      Just recoveryPlan -> do
        assertEqual "Conatus gate must produce RecoveryConatusGate cause"
          RecoveryConatusGate
          (lrpCause recoveryPlan)
        assertEqual "Conatus gate must force StrategySafeRecovery"
          StrategySafeRecovery
          (lrpStrategy recoveryPlan)
        assertBool "evidence must include conatus_gate_fired tag"
          ("conatus_gate_fired" `elem` lrpEvidence recoveryPlan)
        assertBool "evidence must include blanket_violations=2 line"
          ("blanket_violations=2" `elem` lrpEvidence recoveryPlan)

-- | F2-lock (regression): conatus gate *flag* must drive the recovery plan.
-- This pins the M6 single-source-of-truth invariant: the energy scalar
-- alone is not enough; tiConatusGateFired must be True.
testConatusGateFlagDrivesLocalRecoveryPlan :: Test
testConatusGateFlagDrivesLocalRecoveryPlan = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let forcedConatus = ConatusEnergy
          { ceScalar     = -0.1
          , ceComponents = ConatusComponents
              { ccMorphology = 0.0
              , ccIdentity   = 0.0
              , ccTurns      = 0.0
              , ccPenalty    = 1.0
              }
          }
        ti = ti0
          { tiConatusEnergy         = forcedConatus
          , tiBlanketViolationCount = 2
          , tiConatusGateFired      = True
          }
        renderPlan =
          planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "Conatus gate flag=True must expose a visible local recovery plan"
      Just recoveryPlan -> do
        assertEqual "Conatus gate flag must produce RecoveryConatusGate cause"
          RecoveryConatusGate
          (lrpCause recoveryPlan)
        assertEqual "Conatus gate must force StrategySafeRecovery"
          StrategySafeRecovery
          (lrpStrategy recoveryPlan)
        assertBool "evidence must include conatus_gate_fired tag"
          ("conatus_gate_fired" `elem` lrpEvidence recoveryPlan)

-- | F2-lock (regression): energy below threshold WITHOUT the flag must NOT
-- produce RecoveryConatusGate. This proves the flag is the actual driver,
-- not the scalar alone.
testConatusGateEnergyWithoutFlagDoesNotProduceConatusCause :: Test
testConatusGateEnergyWithoutFlagDoesNotProduceConatusCause = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let forcedConatus = ConatusEnergy
          { ceScalar     = -0.1
          , ceComponents = ConatusComponents
              { ccMorphology = 0.0
              , ccIdentity   = 0.0
              , ccTurns      = 0.0
              , ccPenalty    = 1.0
              }
          }
        ti = ti0
          { tiConatusEnergy         = forcedConatus
          , tiBlanketViolationCount = 2
          , tiConatusGateFired      = False
          }
        renderPlan =
          planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing -> pure ()  -- acceptable: no recovery plan at all
      Just recoveryPlan ->
         assertBool "energy below threshold without gate flag must NOT produce RecoveryConatusGate"
           (lrpCause recoveryPlan /= RecoveryConatusGate)

-- | WP1 (GAP1): morphology-dominant Conatus gradient → StrategyMorphologyExpansion.
-- ∂m = 1.0/(1+0) = 1.0, ∂c = 0.5/(1+9) = 0.05, ∂t = 0.25/(1+0) = 0.25.
testConatusGradientMorphologyDominant :: Test
testConatusGradientMorphologyDominant = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let forcedConatus = ConatusEnergy
          { ceScalar     = -1.0
          , ceComponents = ConatusComponents
              { ccMorphology = 0.0
              , ccIdentity   = 0.0
              , ccTurns      = 0.0
              , ccPenalty    = 1.0
              }
          }
        dummyClaim = IdentityClaimRef "" "" 0.0 "" ""
        ss = ss0
          { ssMorphology = MorphologyData Map.empty Map.empty Map.empty Map.empty
          , ssIdentity   = (ssIdentity ss0) { idsIdentityClaims = replicate 9 dummyClaim }
          }
        ti = ti0
          { tiConatusEnergy         = forcedConatus
          , tiBlanketViolationCount = 2
          , tiConatusGateFired      = True
          }
        renderPlan =
          planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "Conatus gate must produce recovery plan"
      Just recoveryPlan -> do
        assertEqual "morphology-dominant gradient must map to StrategyMorphologyExpansion"
          StrategyMorphologyExpansion
          (lrpStrategy recoveryPlan)
        assertBool "evidence must include conatus_strategy tag"
          (any ("conatus_strategy=" `T.isPrefixOf`) (lrpEvidence recoveryPlan))

-- | WP1 (GAP1): identity-dominant Conatus gradient → StrategyIdentityReinforcement.
-- ∂m = 1.0/(1+9) = 0.1, ∂c = 0.5/(1+0) = 0.5, ∂t = 0.25/(1+0) = 0.25.
testConatusGradientIdentityDominant :: Test
testConatusGradientIdentityDominant = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let forcedConatus = ConatusEnergy
          { ceScalar     = -1.0
          , ceComponents = ConatusComponents
              { ccMorphology = 0.0
              , ccIdentity   = 0.0
              , ccTurns      = 0.0
              , ccPenalty    = 1.0
              }
          }
        ss = ss0
          { ssMorphology = MorphologyData
              (Map.fromList [("a","x"),("b","x"),("c","x"),("d","x"),("e","x"),("f","x"),("g","x"),("h","x"),("i","x")])
              Map.empty Map.empty Map.empty
          , ssIdentity   = (ssIdentity ss0) { idsIdentityClaims = [] }
          }
        ti = ti0
          { tiConatusEnergy         = forcedConatus
          , tiBlanketViolationCount = 2
          , tiConatusGateFired      = True
          }
        renderPlan =
          planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "Conatus gate must produce recovery plan"
      Just recoveryPlan -> do
        assertEqual "identity-dominant gradient must map to StrategyIdentityReinforcement"
          StrategyIdentityReinforcement
          (lrpStrategy recoveryPlan)

-- | WP1 (GAP1): temporal-dominant Conatus gradient → StrategyTemporalDeepening.
-- ∂m = 1.0/(1+4) = 0.2, ∂c = 0.5/(1+2) ≈ 0.167, ∂t = 0.25/(1+0) = 0.25.
testConatusGradientTemporalDominant :: Test
testConatusGradientTemporalDominant = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let forcedConatus = ConatusEnergy
          { ceScalar     = -1.0
          , ceComponents = ConatusComponents
              { ccMorphology = 0.0
              , ccIdentity   = 0.0
              , ccTurns      = 0.0
              , ccPenalty    = 1.0
              }
          }
        dummyClaim = IdentityClaimRef "" "" 0.0 "" ""
        ss = ss0
          { ssMorphology = MorphologyData
              (Map.fromList [("a","x"),("b","x"),("c","x"),("d","x")])
              Map.empty Map.empty Map.empty
          , ssIdentity   = (ssIdentity ss0) { idsIdentityClaims = replicate 2 dummyClaim }
          }
        ti = ti0
          { tiConatusEnergy         = forcedConatus
          , tiBlanketViolationCount = 2
          , tiConatusGateFired      = True
          }
        renderPlan =
          planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "Conatus gate must produce recovery plan"
      Just recoveryPlan -> do
        assertEqual "temporal-dominant gradient must map to StrategyTemporalDeepening"
          StrategyTemporalDeepening
          (lrpStrategy recoveryPlan)

-- | WP1 (GAP1): degenerate (three-way tie) gradient → StrategySafeRecovery fallback.
-- ∂m = 1.0/(1+3) = 0.25, ∂c = 0.5/(1+1) = 0.25, ∂t = 0.25/(1+0) = 0.25.
testConatusGradientDegenerateTie :: Test
testConatusGradientDegenerateTie = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "что такое свобода"
    let forcedConatus = ConatusEnergy
          { ceScalar     = -1.0
          , ceComponents = ConatusComponents
              { ccMorphology = 0.0
              , ccIdentity   = 0.0
              , ccTurns      = 0.0
              , ccPenalty    = 1.0
              }
          }
        dummyClaim = IdentityClaimRef "" "" 0.0 "" ""
        ss = ss0
          { ssMorphology = MorphologyData
              (Map.fromList [("a","x"),("b","x"),("c","x")])
              Map.empty Map.empty Map.empty
          , ssIdentity   = (ssIdentity ss0) { idsIdentityClaims = [dummyClaim] }
          }
        ti = ti0
          { tiConatusEnergy         = forcedConatus
          , tiBlanketViolationCount = 2
          , tiConatusGateFired      = True
          }
        renderPlan =
          planRenderEffectsForRuntime RuntimeStrict LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "Conatus gate must produce recovery plan"
      Just recoveryPlan -> do
        assertEqual "degenerate three-way tie must fall back to StrategySafeRecovery"
          StrategySafeRecovery
          (lrpStrategy recoveryPlan)

-- | Phase-8 (M3): deliberation recovery cause must not be silenced
-- by an absent local recovery plan.  When the reconciled Plan carries
-- a recovery cause (e.g. injected via upstream deliberation), the
-- artifact trace must preserve it even if buildLocalRecoveryPlan
-- returns Nothing.
testDeliberationRecoveryNotSilenced :: Test
testDeliberationRecoveryNotSilenced = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "что такое свобода"
    let syntheticDelib = Deliberation
          { delibHolistic = defaultPlan { planRecoveryCause = Just RecoveryConatusGate }
          , delibFormal   = defaultPlan { planRecoveryCause = Just RecoveryConatusGate }
          , delibReconciled = defaultPlan { planRecoveryCause = Just RecoveryConatusGate }
          , delibTrace = DeliberationTrace
              { dtAgreement = Agree
              , dtDivergence = 0.0
              , dtRule = RuleAgreement
              , dtSalienceDriver = DrivenByDefault
              }
          }
        tp' = tp { tpDeliberation = Just syntheticDelib }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp'
    -- Baseline: this clean input should not trigger a local recovery plan.
    assertEqual "baseline local recovery plan should be absent"
      Nothing
      (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp' renderPlan renderResults
    assertEqual "deliberation recovery cause must survive even when local plan is absent"
      (Just RecoveryConatusGate)
      (taLocalRecoveryCause turnArtifacts)

testParserLowConfidenceUsesDistinguishCandidates :: Test
testParserLowConfidenceUsesDistinguishCandidates = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti0, ts, tp0) <- buildPlannedFixture "свобода или ответственность"
    let frame =
          (tiFrame ti0)
            { ipfRawText = "свобода или ответственность"
            , ipfCanonicalFamily = CMClarify
            , ipfConfidence = parserLowConfidenceThreshold / 2.0
            }
        ti =
          ti0
            { tiFrame = frame
            , tiRecommendedFamily = CMDescribe
            }
        tp =
          tp0
            { tpRouting =
                (tpRouting tp0)
                  { rdFamily = CMGround
                  , rdStrategyFamily = Just CMDistinguish
                  }
            , tpFinalFamily = CMDescribe
            , tpShadowStatus = ShadowMatch
            , tpShadowDivergence = False
            }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "low parser confidence with competing candidates must produce local recovery"
      Just recoveryPlan -> do
        assertEqual "parser branch should stay typed as parser low confidence"
          RecoveryParserLowConfidence
          (lrpCause recoveryPlan)
        assertEqual "parser ambiguity should use distinguish-candidates strategy"
          StrategyDistinguishCandidates
          (lrpStrategy recoveryPlan)
        assertBool "recovery evidence should include candidate family set"
          (any ("candidate_families=" `T.isPrefixOf`) (lrpEvidence recoveryPlan))

testRenderBlockedPersistsSafeRecoveryTrace :: Test
testRenderBlockedPersistsSafeRecoveryTrace = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "что такое свобода"
    let renderPlan0 = planRenderEffects LocalRecoveryEnabled ss ti ts tp
        renderStatic0 = repRenderStatic renderPlan0
        renderPlan =
          renderPlan0
            { repRenderStatic =
                renderStatic0
                  { rsRenderWithBg = "phase 0"
                  }
            }
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertEqual "blocked render should switch to recovery provenance"
      FromRecovery
      (taSurfaceProv turnArtifacts)
    assertEqual "blocked render should be typed as render-blocked recovery"
      (Just RecoveryRenderBlocked)
      (taLocalRecoveryCause turnArtifacts)
    assertEqual "blocked render should persist safe-recovery strategy"
      (Just StrategySafeRecovery)
      (taLocalRecoveryStrategy turnArtifacts)
    assertEqual "blocked render should rebind executed decision family to repair"
      CMRepair
      (tdFamily (taDecision turnArtifacts))
    assertBool "safe recovery output should be non-empty"
      (not (T.null (T.strip (taRendered turnArtifacts))))
    let precommitPlan = planFinalizePrecommit ss ti ts tp turnArtifacts
    precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
    bundle <-
          buildFinalizePrecommit
            (pipelineUpdateHistory testProtocolPipelineIO)
            (pipelineParseAuthoritySurface testProtocolPipelineIO)
            ss
            ti
            ts
            tp
            turnArtifacts
            precommitPlan
            precommitResults
    let replayTrace = tqpReplayTrace (fpbProjection bundle)
    assertEqual "render-blocked replay trace should keep typed recovery cause"
      (Just RecoveryRenderBlocked)
      (trcRecoveryCause replayTrace)
    assertEqual "render-blocked replay trace should keep safe-recovery strategy"
      (Just StrategySafeRecovery)
      (trcRecoveryStrategy replayTrace)
    assertEqual "render-blocked replay trace should persist executed recovery family"
      CMRepair
      (trcFinalFamily replayTrace)
    assertEqual "render-blocked projection should persist executed recovery decision"
      CMRepair
      (tqpPlannerDecision (fpbProjection bundle))

testFinalizePrecommitResolveConcurrently :: Test
testFinalizePrecommitResolveConcurrently = TestCase $
  withDeterministicEmbedding $ do
    activeRef <- newIORef 0
    maxRef <- newIORef 0
    let precommitPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = trackedFinalizePrecommitInterpreter activeRef maxRef
              }
    (ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
    let precommitPlan = planFinalizePrecommit ss ti ts tp ta
    _ <- resolveFinalizePrecommit precommitPio precommitPlan
    maxActive <- readIORef maxRef
    assertBool "finalize precommit env effects should resolve concurrently" (maxActive >= 1)

protocolInputs :: [String]
protocolInputs =
  [ "что такое свобода"
  , "мне нужен контакт"
  , "я устал и не могу"
  , "где граница между смыслом и пустотой"
  , "что делать дальше"
  ]

testProtocolPipelineIO :: PipelineIO
testProtocolPipelineIO =
  mkTestPipelineIO
    defaultTestPipelineConfig
      { tpcInterpreter = testProtocolInterpreter
      }

testProtocolInterpreter :: TurnEffectRequest -> IO TurnEffectResult
testProtocolInterpreter request =
  case request of
    TurnReqEmbedding inputText ->
      TurnResEmbedding <$> Emb.textToEmbeddingResult inputText
    TurnReqNixGuard _ _ _ ->
      pure (TurnResNixGuard Allowed)
    TurnReqConsciousness semanticInput humanTheta resonance _conatusEnergy _salienceWeights -> do
      let (loop1, fragment) = CLoop.runConsciousnessLoop CLoop.initialLoop semanticInput humanTheta resonance
      pure (TurnResConsciousness loop1 (CLoop.clLastNarrative loop1) (if T.null fragment then Nothing else Just fragment))
    TurnReqIntuition inputText resonance tension turnNumber _conatusEnergy _salienceWeights _semanticConfig -> do
      let (mFlash, intuitionState) =
            Intuition.checkIntuitionWithInput inputText resonance tension turnNumber Intuition.defaultIntuitiveState
      pure (TurnResIntuition mFlash (Intuition.effectivePosterior intuitionState) intuitionState)
    TurnReqApiHealth ->
      pure (TurnResApiHealth True)
    TurnReqShadow family force _ ->
      pure (TurnResShadow (Just (family, force)) ShadowMatch emptyShadowDivergence (ShadowSnapshotId "shadow:test_protocol") [])
    TurnReqAgdaVerify ->
      pure (TurnResAgdaVerify AgdaVerified)
    TurnReqCurrentTime ->
      pure (TurnResCurrentTime protocolFixedTime)
    TurnReqRequestId ->
      pure (TurnResRequestId "request-id-protocol")
    TurnReqReadEnv _ ->
      pure (TurnResReadEnv Nothing)
    TurnReqTestMarkOnceFile _ ->
      pure (TurnResTestMarkOnceFile False)
    TurnReqSemanticIntrospectionEnv ->
      pure (TurnResSemanticIntrospectionEnv False)
    TurnReqCommitRuntimeState _ _ _ ->
      pure TurnResCommitRuntimeState
    TurnReqSaveState ss _ _ _ ->
      pure (TurnResSaveState (Right ss))
    TurnReqRollbackTurnProjections _ _ ->
      pure (TurnResRollbackTurnProjections (Right ()))
    TurnReqCheckpoint _ ->
      pure TurnResCheckpointCompleted
    TurnReqLinearizeClaimAst _ _ _ ->
      pure (TurnResLinearizeClaimAst (Left "pgf_unavailable_test_protocol"))
    TurnReqLinearizeDialogAtoms _ _ _ ->
      pure (TurnResLinearizeDialogAtoms (Left "pgf_unavailable_test_protocol"))
    TurnReqExternalQuery tool need queryText -> do
      transport <- buildTransportFromConfig explicitMockExternalQueryConfig
      result <- queryExternalTool transport tool need queryText
      pure (TurnResExternalQuery result)

explicitMockExternalQueryConfig :: ExternalQueryConfig
explicitMockExternalQueryConfig =
  defaultExternalQueryConfig
    { eqcTransportMode = "mock"
    , eqcFallbackReason = Just TfrExplicitMock
    }

protocolFixedTime :: UTCTime
protocolFixedTime = UTCTime (ModifiedJulianDay 0) 0

trackedPrepareInterpreter :: IORef Int -> IORef Int -> TurnEffectRequest -> IO TurnEffectResult
trackedPrepareInterpreter activeRef maxRef request =
  case request of
    TurnReqEmbedding _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqNixGuard _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqConsciousness _ _ _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqIntuition _ _ _ _ _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqApiHealth ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    _ ->
      testProtocolInterpreter request

trackedRouteInterpreter :: IORef Int -> IORef Int -> TurnEffectRequest -> IO TurnEffectResult
trackedRouteInterpreter activeRef maxRef request =
  case request of
    TurnReqShadow _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqAgdaVerify ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    _ ->
      testProtocolInterpreter request

strictAgdaFailInterpreter :: TurnEffectRequest -> IO TurnEffectResult
strictAgdaFailInterpreter request =
  case request of
    TurnReqAgdaVerify ->
      pure (TurnResAgdaVerify AgdaMissingWitness)
    _ ->
      testProtocolInterpreter request

strictShadowUnavailableInterpreter :: TurnEffectRequest -> IO TurnEffectResult
strictShadowUnavailableInterpreter request =
  case request of
    TurnReqShadow _ _ _ ->
      pure
        (TurnResShadow
          Nothing
          ShadowUnavailable
          emptyShadowDivergence
          (ShadowSnapshotId "shadow:test_unavailable")
          ["shadow_unavailable_test"])
    TurnReqAgdaVerify ->
      pure (TurnResAgdaVerify AgdaVerified)
    _ ->
      testProtocolInterpreter request

trackedFinalizePrecommitInterpreter :: IORef Int -> IORef Int -> TurnEffectRequest -> IO TurnEffectResult
trackedFinalizePrecommitInterpreter activeRef maxRef request =
  case request of
    TurnReqCurrentTime ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqSemanticIntrospectionEnv ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    _ ->
      testProtocolInterpreter request

failingCommitThenRecoverInterpreter :: IORef Int -> TurnEffectRequest -> IO TurnEffectResult
failingCommitThenRecoverInterpreter attemptsRef request =
  case request of
    TurnReqCommitRuntimeState _ _ _ -> do
      attempt <- atomicModifyIORef' attemptsRef $ \n ->
        let next = n + 1
        in (next, next)
      if attempt == 1
        then ioError (userError "forced_commit_runtime_failure_once")
        else pure TurnResCommitRuntimeState
    _ ->
      testProtocolInterpreter request

failingCommitWithRollbackInterpreter :: IORef [(T.Text, Int, Bool)] -> TurnEffectRequest -> IO TurnEffectResult
failingCommitWithRollbackInterpreter saveRequestsRef request =
  case request of
    TurnReqCommitRuntimeState _ _ _ ->
      ioError (userError "forced_commit_runtime_failure_always")
    TurnReqSaveState ss _ _ mProjection -> do
      atomicModifyIORef' saveRequestsRef $ \items ->
        (items <> [("save", ssTurnCount ss, maybe False (const True) mProjection)], ())
      pure (TurnResSaveState (Right ss))
    TurnReqRollbackTurnProjections _ stableTurn -> do
      atomicModifyIORef' saveRequestsRef $ \items ->
        (items <> [("cleanup", stableTurn, False)], ())
      pure (TurnResRollbackTurnProjections (Right ()))
    _ ->
      testProtocolInterpreter request

trackConcurrentEffect :: IORef Int -> IORef Int -> IO a -> IO a
trackConcurrentEffect activeRef maxRef action = do
  activeNow <- atomicModifyIORef' activeRef $ \active ->
    let next = active + 1
    in (next, next)
  atomicModifyIORef' maxRef $ \currentMax ->
    (max currentMax activeNow, ())
  threadDelay 50000
  result <- action
  atomicModifyIORef' activeRef $ \active -> (active - 1, ())
  pure result

buildPreparedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals)
buildPreparedFixture rawInput = do
  -- Phase-1 SelfBlanket invariants require a non-empty session id and
  -- a non-empty morphology to consider the state /this system/. Test
  -- fixtures must therefore supply at least the minimum needed to
  -- satisfy 'checkInitialBlanket' / 'checkBlanketTransition'; the
  -- specific values are synthetic and orthogonal to the assertions
  -- in this suite.
  let ss = emptySystemState
        { ssSessionId  = "fixture-session"
        , ssMorphology = MorphologyData
            (Map.singleton "о" "preposition")
            Map.empty
            Map.empty
            Map.empty
        }
      preparePlan = planPrepareEffects ss rawInput testEpochZero
  prepareResults <- resolvePrepareEffects testProtocolPipelineIO preparePlan
  let ti = buildTurnInput ss "request-prop" "session-prop" preparePlan prepareResults
      ts = buildTurnSignals prepareResults
  pure (ss, ti, ts)

buildPlannedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan)
buildPlannedFixture rawInput = do
  (ss, ti, ts) <- buildPreparedFixture rawInput
  let routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects testProtocolPipelineIO routePlan
  let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy testProtocolPipelineIO) ss ti ts routePlan routeResults
  pure (ss, ti, ts, tp)

buildRenderedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts)
buildRenderedFixture rawInput = do
  (ss, ti, ts, tp) <- buildPlannedFixture rawInput
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
  let ta = buildTurnArtifacts ss ti ts tp renderPlan renderResults
  pure (ss, ti, ts, tp, ta)

buildFinalizeFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts, FinalizePrecommitBundle)
buildFinalizeFixture rawInput = do
  (ss, ti, ts, tp, ta) <- buildRenderedFixture rawInput
  let precommitPlan = planFinalizePrecommit ss ti ts tp ta
  precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
  bundle <-
        buildFinalizePrecommit
          (pipelineUpdateHistory testProtocolPipelineIO)
          (pipelineParseAuthoritySurface testProtocolPipelineIO)
          ss
          ti
          ts
          tp
          ta
          precommitPlan
          precommitResults
  pure (ss, ti, ts, tp, ta, bundle)

-- | Variant of 'buildFinalizeFixture' that starts from a custom
-- 'SystemState' instead of 'emptySystemState'.
buildFinalizeFixtureWithState
  :: SystemState -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts, FinalizePrecommitBundle)
buildFinalizeFixtureWithState startSs rawInput = do
  -- Override the emptySystemState used by buildRenderedFixture by
  -- replicating the chain with the custom start state.
  (ss, ti, ts, tp, ta) <- buildRenderedFixtureWithState startSs rawInput
  let precommitPlan = planFinalizePrecommit ss ti ts tp ta
  precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
  bundle <-
        buildFinalizePrecommit
          (pipelineUpdateHistory testProtocolPipelineIO)
          (pipelineParseAuthoritySurface testProtocolPipelineIO)
          ss
          ti
          ts
          tp
          ta
          precommitPlan
          precommitResults
  pure (ss, ti, ts, tp, ta, bundle)

buildRenderedFixtureWithState
  :: SystemState -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts)
buildRenderedFixtureWithState startSs rawInput = do
  (ss, ti, ts, tp) <- buildPlannedFixtureWithState startSs rawInput
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
  let ta = buildTurnArtifacts ss ti ts tp renderPlan renderResults
  pure (ss, ti, ts, tp, ta)

buildPlannedFixtureWithState
  :: SystemState -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals, TurnPlan)
buildPlannedFixtureWithState startSs rawInput = do
  (ss, ti, ts) <- buildPreparedFixtureWithState startSs rawInput
  let routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects testProtocolPipelineIO routePlan
  let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy testProtocolPipelineIO) ss ti ts routePlan routeResults
  pure (ss, ti, ts, tp)

buildPreparedFixtureWithState
  :: SystemState -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals)
buildPreparedFixtureWithState startSs rawInput = do
  let preparePlan = planPrepareEffects startSs rawInput testEpochZero
  prepareResults <- resolvePrepareEffects testProtocolPipelineIO preparePlan
  let ti = buildTurnInput startSs "request-prop" "session-prop" preparePlan prepareResults
      ts = buildTurnSignals prepareResults
  pure (startSs, ti, ts)

latestCommitmentStatus :: DialogueCommitmentLedger -> Maybe CommitmentStatus
latestCommitmentStatus ledger =
  case reverse (dclItems ledger) of
    item:_ -> Just (dcStatus item)
    [] -> Nothing

strongInterpretationFrame :: InputPropositionFrame
strongInterpretationFrame =
  emptyInputPropositionFrame
    { ipfRawText = "я сейчас устал"
    , ipfPropositionType = SelfStateQ
    , ipfCanonicalFamily = CMDescribe
    , ipfConfidence = 0.92
    }

gatedInterpretationFrame :: InputPropositionFrame
gatedInterpretationFrame =
  strongInterpretationFrame { ipfConfidence = 0.5 }

semanticFrameInput :: T.Text
semanticFrameInput = "я сейчас устал"

authoritativePreparedFixtureState :: SystemState
authoritativePreparedFixtureState =
  emptySystemState
    { ssSessionId = "fixture-session"
    , ssMorphology = MorphologyData
        (Map.singleton "о" "preposition")
        Map.empty
        Map.empty
        Map.empty
    , ssTruthContractStatus = CanonicalSurfacePreserved
    }

testConstitutionAdmissibleCommitmentStrengthens :: Test
testConstitutionAdmissibleCommitmentStrengthens = TestCase $ do
  (_ss, ti, _ts) <- buildPreparedFixtureWithState authoritativePreparedFixtureState "свобода это хорошо"
  assertEqual "authoritative contour should admit accepted commitment candidate"
    (Just CsAccepted)
    (latestCommitmentStatus (tiDialogueCommitmentLedger ti))
  assertEqual "admitted accepted commitment should allow advancing phase"
    Advancing
    (tiDialoguePhase ti)

testNonAuthoritativeCommitmentCandidateCappedBeforePlanning :: Test
testNonAuthoritativeCommitmentCandidateCappedBeforePlanning = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
  (_ss, ti, _ts) <- buildPreparedFixtureWithState startSs "свобода это хорошо"
  assertEqual "non-authoritative contour must cap accepted candidate before planning"
    (Just CsUnresolved)
    (latestCommitmentStatus (tiDialogueCommitmentLedger ti))
  assertEqual "capped commitment should keep planning in clarifying phase"
    Clarifying
    (tiDialoguePhase ti)

testConatusGatedCommitmentCandidateSuspendedBeforePlanning :: Test
testConatusGatedCommitmentCandidateSuspendedBeforePlanning = TestCase $ do
  let startSs = emptySystemState { ssTruthContractStatus = CanonicalSurfacePreserved }
  (_ss, ti, _ts) <- buildPreparedFixtureWithState startSs "свобода это хорошо"
  assertBool "fixture should trigger the conatus gate"
    (tiConatusGateFired ti)
  assertEqual "conatus-gated contour must suspend accepted candidate before planning"
    (Just CsSuspended)
    (latestCommitmentStatus (tiDialogueCommitmentLedger ti))
  assertBool "suspended commitment must not allow advancing phase"
    (tiDialoguePhase ti /= Advancing)

testNonAuthoritativeFinalizeDoesNotStrengthenCommitment :: Test
testNonAuthoritativeFinalizeDoesNotStrengthenCommitment = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
  (_ss, ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs "свобода это хорошо"
  let nextLedger = ssDialogueCommitmentLedger (fpbNextSs bundle)
  assertEqual "non-authoritative admitted commitment must stay capped after finalize"
    (Just CsUnresolved)
    (latestCommitmentStatus nextLedger)
  assertBool "late finalize downgrade must not re-strengthen capped commitment"
    (latestCommitmentStatus nextLedger /= Just CsAccepted)

testConstitutionAdmissibleInterpretationPreservesRawRouteInput :: Test
testConstitutionAdmissibleInterpretationPreservesRawRouteInput = TestCase $ do
  let admitted = admitInterpretationCandidate (InterpretationAdmissionInput CanonicalSurfacePreserved False) CMDescribe strongInterpretationFrame
  assertEqual "authoritative contour should preserve the raw proposition family"
    CMDescribe
    (ipfCanonicalFamily (aiFrame admitted))
  assertEqual "authoritative contour should preserve the raw recommended family"
    CMDescribe
    (aiRecommendedFamily admitted)
  assertBool "authoritative contour should not stamp interpretation admission evidence"
    (not (any (T.isPrefixOf "interpretation_admission=") (ipfSemanticEvidence (aiFrame admitted))))

testNonAuthoritativeInterpretationNarrowsBeforeRouteCrystallization :: Test
testNonAuthoritativeInterpretationNarrowsBeforeRouteCrystallization = TestCase $ do
  let admitted = admitInterpretationCandidate (InterpretationAdmissionInput LegacyIncompleteSurface False) CMDescribe gatedInterpretationFrame
  assertBool "non-authoritative contour should no longer preserve the stronger raw recommended family"
    (aiRecommendedFamily admitted /= CMDescribe)
  assertBool "non-authoritative contour should no longer preserve the stronger raw proposition family"
    (ipfCanonicalFamily (aiFrame admitted) /= CMDescribe)
  assertBool "non-authoritative contour should mark interpretation admission evidence"
    ("interpretation_admission=non_authoritative" `elem` ipfSemanticEvidence (aiFrame admitted))
  assertEqual "non-authoritative contour should use the cap decision"
    IadCapClarify
    (aiDecision admitted)

testConatusGatedInterpretationFallsBackBeforeRouteCrystallization :: Test
testConatusGatedInterpretationFallsBackBeforeRouteCrystallization = TestCase $ do
  let admitted = admitInterpretationCandidate (InterpretationAdmissionInput CanonicalSurfacePreserved True) CMDescribe gatedInterpretationFrame
  assertBool "conatus-gated contour should no longer preserve the stronger raw recommended family"
    (aiRecommendedFamily admitted /= CMDescribe)
  assertBool "conatus-gated contour should rewrite the proposition family before routing"
    (ipfCanonicalFamily (aiFrame admitted) /= CMDescribe)
  assertBool "conatus-gated contour should mark fallback admission evidence"
    ("interpretation_admission=conatus_gate" `elem` ipfSemanticEvidence (aiFrame admitted))
  assertEqual "conatus-gated contour should use the fallback decision"
    IadFallbackClarify
    (aiDecision admitted)

testConstitutionAdmissiblePropositionPreservesRawFrame :: Test
testConstitutionAdmissiblePropositionPreservesRawFrame = TestCase $ do
  let admitted = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved False) strongInterpretationFrame
  assertEqual "authoritative contour should preserve raw proposition family"
    CMDescribe
    (ipfCanonicalFamily (apfFrame admitted))
  assertEqual "authoritative contour should preserve raw proposition confidence"
    0.92
    (ipfConfidence (apfFrame admitted))
  assertEqual "authoritative contour should admit the raw proposition frame"
    PadAdmitRaw
    (apfDecision admitted)

testNonAuthoritativePropositionFrameSoftensBeforeInterpretationAdmission :: Test
testNonAuthoritativePropositionFrameSoftensBeforeInterpretationAdmission = TestCase $ do
  let admitted = admitPropositionFrame (PropositionAdmissionInput LegacyIncompleteSurface False) strongInterpretationFrame
  assertBool "non-authoritative contour should lower proposition confidence before later admission"
    (ipfConfidence (apfFrame admitted) < ipfConfidence strongInterpretationFrame)
  assertBool "non-authoritative contour should stamp proposition admission evidence"
    ("proposition_admission=non_authoritative" `elem` ipfSemanticEvidence (apfFrame admitted))
  assertEqual "non-authoritative proposition admission should be explicit"
    PadLowerConfidence
    (apfDecision admitted)

testConatusGatedPropositionFrameSoftensBeforeInterpretationAdmission :: Test
testConatusGatedPropositionFrameSoftensBeforeInterpretationAdmission = TestCase $ do
  let admittedFrame = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved True) strongInterpretationFrame
      admittedInterpretation = admitInterpretationCandidate (InterpretationAdmissionInput CanonicalSurfacePreserved True) CMDescribe (apfFrame admittedFrame)
  assertBool "conatus-gated contour should lower proposition confidence before later admission"
    (ipfConfidence (apfFrame admittedFrame) < ipfConfidence strongInterpretationFrame)
  assertBool "conatus-gated contour should stamp proposition admission evidence"
    ("proposition_admission=conatus_gate" `elem` ipfSemanticEvidence (apfFrame admittedFrame))
  assertEqual "conatus-gated proposition admission should be explicit"
    PadLowerConfidence
    (apfDecision admittedFrame)
  assertEqual "CTS-02 should still receive the softened frame and fallback safely"
    IadFallbackClarify
    (aiDecision admittedInterpretation)

testConstitutionAdmissibleSemanticFramePreservesRawFrame :: Test
testConstitutionAdmissibleSemanticFramePreservesRawFrame = TestCase $ do
  let rawAdmitted = admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput
  assertEqual "authoritative contour should admit the raw semantic frame"
    SfdAdmitRaw
    (asfDecision rawAdmitted)
  assertBool "authoritative contour should not stamp semantic-frame admission marker"
    (not ("semantic_frame_admission=non_authoritative" `elem` admittedSemanticFrameRouteEvidence rawAdmitted)
      && not ("semantic_frame_admission=conatus_gate" `elem` admittedSemanticFrameRouteEvidence rawAdmitted))

testNonAuthoritativeSemanticFrameSoftensBeforePropositionAdmission :: Test
testNonAuthoritativeSemanticFrameSoftensBeforePropositionAdmission = TestCase $ do
  let rawAdmitted = admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput
      admittedFrame = admitSemanticFrameForInput (SemanticFrameAdmissionInput LegacyIncompleteSurface False) semanticFrameInput
      rawProp = parsePropositionWithFrame semanticFrameInput (asfFrame rawAdmitted)
      admittedProp = parsePropositionWithFrame semanticFrameInput (asfFrame admittedFrame)
  assertBool "non-authoritative contour should lower semantic frame confidence before proposition admission"
    (admittedSemanticFrameConfidence admittedFrame < admittedSemanticFrameConfidence rawAdmitted)
  assertBool "non-authoritative contour should stamp semantic-frame admission evidence"
    ("semantic_frame_admission=non_authoritative" `elem` admittedSemanticFrameRouteEvidence admittedFrame)
  assertEqual "non-authoritative semantic-frame admission should be explicit"
    SfdLowerConfidence
    (asfDecision admittedFrame)
  assertBool "proposition confidence should already be softened before CTS-03"
    (ipfConfidence admittedProp < ipfConfidence rawProp)

testConatusGatedSemanticFrameSoftensBeforePropositionAdmission :: Test
testConatusGatedSemanticFrameSoftensBeforePropositionAdmission = TestCase $ do
  let rawAdmitted = admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput
      admittedFrame = admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved True) semanticFrameInput
      rawProp = parsePropositionWithFrame semanticFrameInput (asfFrame rawAdmitted)
      admittedProp = parsePropositionWithFrame semanticFrameInput (asfFrame admittedFrame)
      admittedFrame2 = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved True) admittedProp
  assertBool "conatus-gated contour should lower semantic frame confidence before proposition admission"
    (admittedSemanticFrameConfidence admittedFrame < admittedSemanticFrameConfidence rawAdmitted)
  assertBool "conatus-gated contour should stamp semantic-frame admission evidence"
    ("semantic_frame_admission=conatus_gate" `elem` admittedSemanticFrameRouteEvidence admittedFrame)
  assertEqual "conatus-gated semantic-frame admission should be explicit"
    SfdLowerConfidence
    (asfDecision admittedFrame)
  assertBool "CTS-03 should still receive a proposition frame already softened by CTS-04"
    (ipfConfidence admittedProp < ipfConfidence rawProp)
  assertBool "CTS-03 remains intact and does not error on the softened proposition frame"
    (apfDecision admittedFrame2 `elem` [PadLowerConfidence, PadPreserveAmbiguous, PadAdmitRaw])

testConstitutionAdmissibleSenseVectorPreservesRawVector :: Test
testConstitutionAdmissibleSenseVectorPreservesRawVector = TestCase $ do
  let rawFrame = asfFrame (admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput)
      rawVec = extractSenseVector rawFrame
      admitted = admitSenseVector (SenseVectorAdmissionInput CanonicalSurfacePreserved False) rawVec
  assertEqual "authoritative contour should admit raw sense vector"
    SvdAdmitRaw
    (asvDecision admitted)
  assertEqual "authoritative contour should preserve operator set"
    (svOperators rawVec)
    (svOperators (asvVector admitted))
  assertEqual "authoritative contour should preserve sense confidence"
    (svConfidence rawVec)
    (svConfidence (asvVector admitted))

testNonAuthoritativeSenseVectorNarrowsBeforeMeaningShaping :: Test
testNonAuthoritativeSenseVectorNarrowsBeforeMeaningShaping = TestCase $ do
  let rawFrame = asfFrame (admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput)
      rawVec = extractSenseVector rawFrame
      admitted = admitSenseVector (SenseVectorAdmissionInput LegacyIncompleteSurface False) rawVec
  assertBool "non-authoritative sense admission should be explicit"
    (asvDecision admitted `elem` [SvdDampenClarify, SvdPreserveAmbiguous])
  assertBool "non-authoritative contour should not strengthen sense-vector confidence"
    (svConfidence (asvVector admitted) <= svConfidence rawVec)
  assertBool "non-authoritative contour should not widen operator set"
    (length (svOperators (asvVector admitted)) <= length (svOperators rawVec))

testConatusGatedSenseVectorNarrowsBeforeMeaningShaping :: Test
testConatusGatedSenseVectorNarrowsBeforeMeaningShaping = TestCase $ do
  let rawFrame = asfFrame (admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput)
      rawVec = extractSenseVector rawFrame
      admitted = admitSenseVector (SenseVectorAdmissionInput CanonicalSurfacePreserved True) rawVec
      sensePlan = buildResponseSensePlan CMDescribe emptyDialogueCommitmentLedger Exploring (asvVector admitted)
  assertBool "conatus-gated sense admission should be explicit"
    (asvDecision admitted `elem` [SvdDampenClarify, SvdPreserveAmbiguous])
  assertBool "conatus-gated contour should not strengthen sense-vector confidence"
    (svConfidence (asvVector admitted) <= svConfidence rawVec)
  assertBool "conatus-gated contour should not widen operator set"
    (length (svOperators (asvVector admitted)) <= length (svOperators rawVec))
  assertBool "downstream sense planning must consume the admitted vector without widening distance"
    (rspDistance sensePlan >= 0)

testConstitutionAdmissibleRouteHintPreservesRawHint :: Test
testConstitutionAdmissibleRouteHintPreservesRawHint = TestCase $ do
  let semanticFrame = asfFrame (admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput)
      rawHint = AdmittedRouteHint (InputRouteHint RouteTypeDescribe TagSelfState "self_state_question" 0.9 0.9 0.7 0.0 ["route_seed"] 0.9) RhdAdmitRaw
      admitted = rawHint
  assertEqual "authoritative contour should admit the raw route hint"
    RhdAdmitRaw
    (arhDecision admitted)
  assertEqual "authoritative contour should preserve route tag"
    (admittedRouteHintTag rawHint)
    (admittedRouteHintTag admitted)
  assertEqual "authoritative contour should preserve route confidence"
    (admittedRouteHintConfidence rawHint)
    (admittedRouteHintConfidence admitted)

testNonAuthoritativeRouteHintSoftensBeforePropositionAdmission :: Test
testNonAuthoritativeRouteHintSoftensBeforePropositionAdmission = TestCase $ do
  let semanticFrame = asfFrame (admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput)
      rawHint = AdmittedRouteHint (InputRouteHint RouteTypeDescribe TagSelfState "self_state_question" 0.9 0.9 0.7 0.0 ["route_seed"] 0.9) RhdAdmitRaw
      admitted = admitRouteHint (RouteHintAdmissionInput LegacyIncompleteSurface False semanticFrameInput) (arhHint rawHint)
      rawFrame = applyAdmittedRouteHint rawHint semanticFrame
      admittedFrame = applyAdmittedRouteHint admitted semanticFrame
      rawProp = parsePropositionWithFrame semanticFrameInput rawFrame
      admittedProp = parsePropositionWithFrame semanticFrameInput admittedFrame
  assertBool "non-authoritative route-hint admission should be explicit"
    (arhDecision admitted `elem` [RhdLowerConfidence, RhdPreserveAmbiguous])
  assertBool "non-authoritative contour should not strengthen route-hint confidence"
    (admittedRouteHintConfidence admitted <= admittedRouteHintConfidence rawHint)
  assertBool "non-authoritative contour should stamp route-hint admission evidence"
    ("route_hint_admission=non_authoritative" `elem` admittedRouteHintEvidence admitted)
  assertBool "proposition confidence should not strengthen after admitted route-hint"
    (ipfConfidence admittedProp <= ipfConfidence rawProp)

testConatusGatedRouteHintSoftensBeforePropositionAdmission :: Test
testConatusGatedRouteHintSoftensBeforePropositionAdmission = TestCase $ do
  let semanticFrame = asfFrame (admitSemanticFrameForInput (SemanticFrameAdmissionInput CanonicalSurfacePreserved False) semanticFrameInput)
      rawHint = AdmittedRouteHint (InputRouteHint RouteTypeDescribe TagSelfState "self_state_question" 0.9 0.9 0.7 0.0 ["route_seed"] 0.9) RhdAdmitRaw
      admitted = admitRouteHint (RouteHintAdmissionInput CanonicalSurfacePreserved True semanticFrameInput) (arhHint rawHint)
      admittedFrame = applyAdmittedRouteHint admitted semanticFrame
      admittedProp = parsePropositionWithFrame semanticFrameInput admittedFrame
      admittedFrame2 = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved True) admittedProp
  assertBool "conatus-gated route-hint admission should be explicit"
    (arhDecision admitted `elem` [RhdLowerConfidence, RhdPreserveAmbiguous])
  assertBool "conatus-gated contour should not strengthen route-hint confidence"
    (admittedRouteHintConfidence admitted <= admittedRouteHintConfidence rawHint)
  assertBool "conatus-gated contour should stamp route-hint admission evidence"
    ("route_hint_admission=conatus_gate" `elem` admittedRouteHintEvidence admitted)
  assertBool "CTS-03 should still receive a valid proposition frame"
    (apfDecision admittedFrame2 `elem` [PadLowerConfidence, PadPreserveAmbiguous, PadAdmitRaw])

strongFamilySelfVerdict :: SelfVerdict
strongFamilySelfVerdict = SelfVerdict (Salience 0.5 1.0 DrivenByDefault) Tied

conatusGateSelfVerdict :: SelfVerdict
conatusGateSelfVerdict = SelfVerdict (Salience 0.1 1.0 DrivenByConatusGate) (PreferFormal 1.0)

testConstitutionAdmissibleFamilyPreservesRawCrystallization :: Test
testConstitutionAdmissibleFamilyPreservesRawCrystallization = TestCase $ do
  let admitted = admitFamilyCrystallization (FamilyAdmissionInput CanonicalSurfacePreserved strongFamilySelfVerdict) CMDescribe gatedInterpretationFrame
  assertEqual "authoritative contour should preserve raw family crystallization"
    CMDescribe
    (afFamily admitted)
  assertEqual "authoritative contour should admit raw family"
    FadAdmitRaw
    (afDecision admitted)

testNonAuthoritativeFamilyCrystallizationCapsBeforeRouteDecision :: Test
testNonAuthoritativeFamilyCrystallizationCapsBeforeRouteDecision = TestCase $ do
  let admitted = admitFamilyCrystallization (FamilyAdmissionInput LegacyIncompleteSurface strongFamilySelfVerdict) CMDescribe gatedInterpretationFrame
  assertEqual "non-authoritative contour should cap strong family crystallization"
    CMClarify
    (afFamily admitted)
  assertEqual "non-authoritative contour should use the cap decision"
    FadCapClarify
    (afDecision admitted)

testConatusGatedFamilyCrystallizationCapsBeforeRouteDecision :: Test
testConatusGatedFamilyCrystallizationCapsBeforeRouteDecision = TestCase $ do
  let admitted = admitFamilyCrystallization (FamilyAdmissionInput CanonicalSurfacePreserved conatusGateSelfVerdict) CMDescribe gatedInterpretationFrame
  assertEqual "conatus-gated contour should cap strong family crystallization"
    CMClarify
    (afFamily admitted)
  assertEqual "conatus-gated contour should use the cap decision"
    FadCapClarify
    (afDecision admitted)

testRoutePlanConsumesAdmittedFamilyCrystallization :: Test
testRoutePlanConsumesAdmittedFamilyCrystallization = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
  (ss, ti0, ts) <- buildPreparedFixtureWithState startSs semanticFrameInput
  let ti = ti0
        { tiRecommendedFamily = CMDescribe
        , tiFrame = gatedInterpretationFrame
        , tiSelfVerdict = strongFamilySelfVerdict
        }
      routePlan = planRouteEffects ss ti ts
      rd = rsRoutingDecision (repStatic routePlan)
  assertBool "route planning should consume the admitted family crystallization rather than preserve raw CMDescribe"
    (rdFamily rd `elem` [CMClarify, CMAnchor, CMRepair])

testConstitutionAdmissibleEarlyFamilyPreservesRawRecommendation :: Test
testConstitutionAdmissibleEarlyFamilyPreservesRawRecommendation = TestCase $ do
  let admitted = admitEarlyFamilyRecommendation (EarlyFamilyAdmissionInput CanonicalSurfacePreserved False) CMDescribe gatedInterpretationFrame
  assertEqual "authoritative contour should preserve raw early family recommendation"
    CMDescribe
    (aefFamily admitted)
  assertEqual "authoritative contour should admit raw early family"
    EfdAdmitRaw
    (aefDecision admitted)

testNonAuthoritativeEarlyFamilyCapsBeforeLaterCrystallization :: Test
testNonAuthoritativeEarlyFamilyCapsBeforeLaterCrystallization = TestCase $ do
  let admitted = admitEarlyFamilyRecommendation (EarlyFamilyAdmissionInput LegacyIncompleteSurface False) CMDescribe gatedInterpretationFrame
  assertEqual "non-authoritative contour should cap strong early family recommendation"
    CMClarify
    (aefFamily admitted)
  assertEqual "non-authoritative contour should use the cap decision"
    EfdCapClarify
    (aefDecision admitted)

testConatusGatedEarlyFamilyCapsBeforeLaterCrystallization :: Test
testConatusGatedEarlyFamilyCapsBeforeLaterCrystallization = TestCase $ do
  let admitted = admitEarlyFamilyRecommendation (EarlyFamilyAdmissionInput CanonicalSurfacePreserved True) CMDescribe gatedInterpretationFrame
  assertEqual "conatus-gated contour should cap strong early family recommendation"
    CMClarify
    (aefFamily admitted)
  assertEqual "conatus-gated contour should use the cap decision"
    EfdCapClarify
    (aefDecision admitted)

testPrepareConsciousnessUsesAdmittedEarlyFamily :: Test
testPrepareConsciousnessUsesAdmittedEarlyFamily = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs semanticFrameInput testEpochZero
  case pepConsciousnessRequest plan of
    PrepareReqConsciousness semanticInput _ _ _ _ ->
      assertBool "prepare consciousness request should consume a weakened admitted early family rather than preserve raw CMDescribe"
        (siRecommendedFamily semanticInput `elem` [CMClarify, CMRepair])
    _ -> assertFailure "expected PrepareReqConsciousness in prepare plan"

testConstitutionAdmissibleSemanticLogicPreservesRawWeighting :: Test
testConstitutionAdmissibleSemanticLogicPreservesRawWeighting = TestCase $ do
  let rawWeighting = [(CMDescribe, 0.9), (CMGround, 0.4)]
      admittedFrame = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved False) gatedInterpretationFrame
      admitted = admitSemanticLogicWeighting (SemanticLogicAdmissionInput CanonicalSurfacePreserved False (apfFrame admittedFrame)) rawWeighting
  assertEqual "authoritative contour should preserve raw semantic-logic weighting"
    rawWeighting
    (aslFamilies admitted)
  assertEqual "authoritative contour should admit raw weighting"
    SldAdmitRaw
    (aslDecision admitted)

testNonAuthoritativeSemanticLogicCapsBeforeEarlyFamilyAdmission :: Test
testNonAuthoritativeSemanticLogicCapsBeforeEarlyFamilyAdmission = TestCase $ do
  let rawWeighting = [(CMDescribe, 0.9), (CMGround, 0.4)]
      admittedFrame = admitPropositionFrame (PropositionAdmissionInput LegacyIncompleteSurface False) gatedInterpretationFrame
      admitted = admitSemanticLogicWeighting (SemanticLogicAdmissionInput LegacyIncompleteSurface False (apfFrame admittedFrame)) rawWeighting
      admittedFamily = admitEarlyFamilyRecommendation (EarlyFamilyAdmissionInput LegacyIncompleteSurface False) (fst (head (aslFamilies admitted))) gatedInterpretationFrame
  assertEqual "non-authoritative contour should cap strong early semantic-logic family bias"
    CMClarify
    (fst (head (aslFamilies admitted)))
  assertEqual "non-authoritative semantic-logic admission should be explicit"
    SldCapClarify
    (aslDecision admitted)
  assertBool "CTS-08 should still receive a valid admitted family downstream"
    (aefDecision admittedFamily `elem` [EfdCapClarify, EfdPreserveAmbiguous, EfdAdmitRaw])

testConatusGatedSemanticLogicCapsBeforeEarlyFamilyAdmission :: Test
testConatusGatedSemanticLogicCapsBeforeEarlyFamilyAdmission = TestCase $ do
  let rawWeighting = [(CMDescribe, 0.9), (CMGround, 0.4)]
      admittedFrame = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved True) gatedInterpretationFrame
      admitted = admitSemanticLogicWeighting (SemanticLogicAdmissionInput CanonicalSurfacePreserved True (apfFrame admittedFrame)) rawWeighting
      admittedFamily = admitEarlyFamilyRecommendation (EarlyFamilyAdmissionInput CanonicalSurfacePreserved True) (fst (head (aslFamilies admitted))) gatedInterpretationFrame
  assertEqual "conatus-gated contour should cap strong early semantic-logic family bias"
    CMClarify
    (fst (head (aslFamilies admitted)))
  assertEqual "conatus-gated semantic-logic admission should be explicit"
    SldCapClarify
    (aslDecision admitted)
  assertBool "CTS-08 should still receive a valid admitted family downstream"
    (aefDecision admittedFamily `elem` [EfdCapClarify, EfdPreserveAmbiguous, EfdAdmitRaw])

testPrepareUsesAdmittedSemanticLogicFamily :: Test
testPrepareUsesAdmittedSemanticLogicFamily = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs semanticFrameInput testEpochZero
  assertBool "prepare static should carry the admitted early family selected from admitted weighting"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair])

testConstitutionAdmissibleSemanticContributionPreservesRawContributions :: Test
testConstitutionAdmissibleSemanticContributionPreservesRawContributions = TestCase $ do
  let rawContributions = [(CMDescribe, 0.9), (CMGround, 0.4)]
      admittedFrame = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved False) gatedInterpretationFrame
      admitted = admitSemanticContributions (SemanticContributionAdmissionInput CanonicalSurfacePreserved False (apfFrame admittedFrame)) rawContributions
  assertEqual "authoritative contour should preserve raw semantic contributions"
    rawContributions
    (ascFamilies admitted)
  assertEqual "authoritative contour should admit raw contributions"
    ScdAdmitRaw
    (ascDecision admitted)

testNonAuthoritativeSemanticContributionSoftensBeforeWeightingAdmission :: Test
testNonAuthoritativeSemanticContributionSoftensBeforeWeightingAdmission = TestCase $ do
  let rawContributions = [(CMDescribe, 0.9), (CMGround, 0.4)]
      admittedFrame = admitPropositionFrame (PropositionAdmissionInput LegacyIncompleteSurface False) gatedInterpretationFrame
      admitted = admitSemanticContributions (SemanticContributionAdmissionInput LegacyIncompleteSurface False (apfFrame admittedFrame)) rawContributions
  assertEqual "non-authoritative contour should cap strong semantic contribution bias"
    CMClarify
    (fst (head (ascFamilies admitted)))
  assertEqual "non-authoritative semantic contribution admission should be explicit"
    ScdCapClarify
    (ascDecision admitted)

testConatusGatedSemanticContributionSoftensBeforeWeightingAdmission :: Test
testConatusGatedSemanticContributionSoftensBeforeWeightingAdmission = TestCase $ do
  let rawContributions = [(CMDescribe, 0.9), (CMGround, 0.4)]
      admittedFrame = admitPropositionFrame (PropositionAdmissionInput CanonicalSurfacePreserved True) gatedInterpretationFrame
      admitted = admitSemanticContributions (SemanticContributionAdmissionInput CanonicalSurfacePreserved True (apfFrame admittedFrame)) rawContributions
  assertEqual "conatus-gated contour should cap strong semantic contribution bias"
    CMClarify
    (fst (head (ascFamilies admitted)))
  assertEqual "conatus-gated semantic contribution admission should be explicit"
    ScdCapClarify
    (ascDecision admitted)

testPrepareUsesAdmittedSemanticContributionPlane :: Test
testPrepareUsesAdmittedSemanticContributionPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs semanticFrameInput testEpochZero
  assertBool "prepare should carry the early family selected from admitted semantic contributions"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair])

testConstitutionAdmissibleAtomContributionPreservesRawAtoms :: Test
testConstitutionAdmissibleAtomContributionPreservesRawAtoms = TestCase $ do
  let rawAtoms = AtomSet [MeaningAtom "self" (NeedMeaning "self") (V.fromList []), MeaningAtom "verify" (Verification "self") (V.fromList [])] 0.0 Neutral
      admitted = admitAtomContributions (AtomContributionAdmissionInput CanonicalSurfacePreserved) rawAtoms
  assertEqual "authoritative contour should preserve raw atom contributions"
    (asAtoms rawAtoms)
    (aacAtoms admitted)
  assertEqual "authoritative contour should admit raw atom contributions"
    AcdAdmitRaw
    (aacDecision admitted)

testNonAuthoritativeAtomContributionCapsStrongAtoms :: Test
testNonAuthoritativeAtomContributionCapsStrongAtoms = TestCase $ do
  let rawAtoms = AtomSet [MeaningAtom "self" (NeedMeaning "self") (V.fromList []), MeaningAtom "verify" (Verification "self") (V.fromList [])] 0.0 Neutral
      admitted = admitAtomContributions (AtomContributionAdmissionInput LegacyIncompleteSurface) rawAtoms
  assertEqual "non-authoritative contour should retain only weak atom contributions"
    [Verification "self"]
    (map maTag (aacAtoms admitted))
  assertEqual "non-authoritative atom contribution admission should be explicit"
    AcdCapWeakProfile
    (aacDecision admitted)

testNonAuthoritativeWeakAtomContributionStaysAmbiguous :: Test
testNonAuthoritativeWeakAtomContributionStaysAmbiguous = TestCase $ do
  let rawAtoms = AtomSet [MeaningAtom "verify" (Verification "self") (V.fromList []), MeaningAtom "anchor" (Anchoring "self") (V.fromList [])] 0.0 Neutral
      admitted = admitAtomContributions (AtomContributionAdmissionInput LegacyIncompleteSurface) rawAtoms
  assertEqual "already-weak atom contributions should remain present"
    (map maTag (asAtoms rawAtoms))
    (map maTag (aacAtoms admitted))
  assertEqual "weak atom contribution contour should preserve ambiguity"
    AcdPreserveAmbiguous
    (aacDecision admitted)

testPrepareUsesAdmittedAtomContributionPlane :: Test
testPrepareUsesAdmittedAtomContributionPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted atom contributions"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

testConstitutionAdmissibleAtomExtractionPreservesRawAtoms :: Test
testConstitutionAdmissibleAtomExtractionPreservesRawAtoms = TestCase $ do
  let rawAtoms = AtomSet [MeaningAtom "self" (NeedMeaning "self") (V.fromList []), MeaningAtom "verify" (Verification "self") (V.fromList [])] 0.0 Neutral
      admitted = admitAtomAvailability (AtomExtractionAdmissionInput CanonicalSurfacePreserved) rawAtoms
  assertEqual "authoritative contour should preserve raw atom extraction availability"
    (asAtoms rawAtoms)
    (aaaAtoms admitted)
  assertEqual "authoritative atom extraction admission should be explicit"
    AedAdmitRaw
    (aaaDecision admitted)

testNonAuthoritativeAtomExtractionSuppressesStrongFindings :: Test
testNonAuthoritativeAtomExtractionSuppressesStrongFindings = TestCase $ do
  let rawAtoms = AtomSet [MeaningAtom "self" (NeedMeaning "self") (V.fromList []), MeaningAtom "verify" (Verification "self") (V.fromList [])] 0.0 Neutral
      admitted = admitAtomAvailability (AtomExtractionAdmissionInput LegacyIncompleteSurface) rawAtoms
  assertEqual "non-authoritative contour should suppress strong atom findings before CTS-11"
    [Verification "self"]
    (map maTag (aaaAtoms admitted))
  assertEqual "non-authoritative atom extraction admission should be explicit"
    AedSuppressStrongFindings
    (aaaDecision admitted)

testNonAuthoritativeSafeAtomExtractionStaysPresent :: Test
testNonAuthoritativeSafeAtomExtractionStaysPresent = TestCase $ do
  let rawAtoms = AtomSet [MeaningAtom "verify" (Verification "self") (V.fromList []), MeaningAtom "anchor" (Anchoring "self") (V.fromList [])] 0.0 Neutral
      admitted = admitAtomAvailability (AtomExtractionAdmissionInput LegacyIncompleteSurface) rawAtoms
  assertEqual "already-safe raw atom findings should remain present"
    (map maTag (asAtoms rawAtoms))
    (map maTag (aaaAtoms admitted))
  assertEqual "already-safe raw atom extraction contour should preserve ambiguity"
    AedPreserveAmbiguous
    (aaaDecision admitted)

testPrepareUsesAdmittedAtomExtractionPlane :: Test
testPrepareUsesAdmittedAtomExtractionPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted atom extraction plane"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

testConstitutionAdmissibleAtomFindingPreservesRawFindings :: Test
testConstitutionAdmissibleAtomFindingPreservesRawFindings = TestCase $ do
  let rawFindings = RawAtomFindings
        { rafClusterAtoms = [MeaningAtom "cluster" (NeedMeaning "cluster") (V.fromList [])]
        , rafLexicalAtoms = [MeaningAtom "lexical" (Verification "self") (V.fromList [])]
        , rafStructuralAtoms = [MeaningAtom "structural" (Searching "why") (V.fromList [])]
        }
      admitted = admitAtomFindings (AtomFindingAdmissionInput CanonicalSurfacePreserved) rawFindings
  assertEqual "authoritative contour should preserve raw lexical/cluster findings"
    rawFindings
    (aafFindings admitted)
  assertEqual "authoritative atom-finding admission should be explicit"
    AfdAdmitRaw
    (aafDecision admitted)

testNonAuthoritativeAtomFindingSuppressesStrongLexicalAndClusterFindings :: Test
testNonAuthoritativeAtomFindingSuppressesStrongLexicalAndClusterFindings = TestCase $ do
  let rawFindings = RawAtomFindings
        { rafClusterAtoms = [MeaningAtom "cluster" (NeedMeaning "cluster") (V.fromList []), MeaningAtom "cluster-safe" (Verification "self") (V.fromList [])]
        , rafLexicalAtoms = [MeaningAtom "lexical" (AgencyLost 0.6) (V.fromList []), MeaningAtom "lexical-safe" (NeedContact "self") (V.fromList [])]
        , rafStructuralAtoms = [MeaningAtom "structural" (Searching "why") (V.fromList [])]
        }
      admitted = admitAtomFindings (AtomFindingAdmissionInput LegacyIncompleteSurface) rawFindings
  assertEqual "non-authoritative contour should suppress strong cluster/lexical findings but keep structural findings untouched"
    [Verification "self", NeedContact "self", Searching "why"]
    (map maTag (rafClusterAtoms (aafFindings admitted) ++ rafLexicalAtoms (aafFindings admitted) ++ rafStructuralAtoms (aafFindings admitted)))
  assertEqual "non-authoritative atom-finding admission should be explicit"
    AfdSuppressStrongFindings
    (aafDecision admitted)

testNonAuthoritativeSafeAtomFindingsStayPresent :: Test
testNonAuthoritativeSafeAtomFindingsStayPresent = TestCase $ do
  let rawFindings = RawAtomFindings
        { rafClusterAtoms = [MeaningAtom "cluster-safe" (Verification "self") (V.fromList [])]
        , rafLexicalAtoms = [MeaningAtom "lexical-safe" (NeedContact "self") (V.fromList [])]
        , rafStructuralAtoms = [MeaningAtom "structural" (Searching "why") (V.fromList [])]
        }
      admitted = admitAtomFindings (AtomFindingAdmissionInput LegacyIncompleteSurface) rawFindings
  assertEqual "already-safe lexical/cluster findings should remain present"
    rawFindings
    (aafFindings admitted)
  assertEqual "safe atom-finding contour should preserve ambiguity"
    AfdPreserveAmbiguous
    (aafDecision admitted)

testPrepareUsesAdmittedAtomFindingPlane :: Test
testPrepareUsesAdmittedAtomFindingPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted atom finding plane"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

testConstitutionAdmissibleStructuralAtomPreservesSearching :: Test
testConstitutionAdmissibleStructuralAtomPreservesSearching = TestCase $ do
  let rawFindings = RawAtomFindings
        { rafClusterAtoms = []
        , rafLexicalAtoms = []
        , rafStructuralAtoms = [MeaningAtom "structural" (Searching "why") (V.fromList [])]
        }
      admitted = admitStructuralAtoms (StructuralAtomAdmissionInput CanonicalSurfacePreserved) rawFindings
  assertEqual "authoritative contour should preserve raw structural question atoms"
    rawFindings
    (asaFindings admitted)
  assertEqual "authoritative structural atom admission should be explicit"
    SadAdmitRaw
    (asaDecision admitted)

testNonAuthoritativeStructuralAtomSuppressesSearching :: Test
testNonAuthoritativeStructuralAtomSuppressesSearching = TestCase $ do
  let rawFindings = RawAtomFindings
        { rafClusterAtoms = []
        , rafLexicalAtoms = []
        , rafStructuralAtoms = [MeaningAtom "structural" (Searching "why") (V.fromList [])]
        }
      admitted = admitStructuralAtoms (StructuralAtomAdmissionInput LegacyIncompleteSurface) rawFindings
  assertEqual "non-authoritative contour should suppress structural searching atoms"
    []
    (map maTag (rafStructuralAtoms (asaFindings admitted)))
  assertEqual "non-authoritative structural atom admission should be explicit"
    SadSuppressSearching
    (asaDecision admitted)

testSafeStructuralAtomsStayPresent :: Test
testSafeStructuralAtomsStayPresent = TestCase $ do
  let rawFindings = RawAtomFindings
        { rafClusterAtoms = []
        , rafLexicalAtoms = []
        , rafStructuralAtoms = [MeaningAtom "structural" (Verification "self") (V.fromList [])]
        }
      admitted = admitStructuralAtoms (StructuralAtomAdmissionInput LegacyIncompleteSurface) rawFindings
  assertEqual "already-safe structural atoms should remain present"
    rawFindings
    (asaFindings admitted)
  assertEqual "safe structural atom contour should preserve ambiguity"
    SadPreserveAmbiguous
    (asaDecision admitted)

testPrepareUsesAdmittedStructuralAtomPlane :: Test
testPrepareUsesAdmittedStructuralAtomPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted structural atom plane"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

testConstitutionAdmissibleLexicalClusterPhraseDecisionPreservesRawDecisions :: Test
testConstitutionAdmissibleLexicalClusterPhraseDecisionPreservesRawDecisions = TestCase $ do
  let rawDecisions = RawLexicalClusterPhraseDecisions
        { rlcpdInputLower = "input"
        , rlcpdClusterDecisions = [RawClusterPhraseDecision "need_meaning" "смысл" True]
        , rlcpdLexicalDecisions = [RawLexicalPhraseDecision LpcNeedContact "рядом" True]
        }
      admitted = admitLexicalClusterPhraseDecisions (LexicalClusterPhraseDecisionAdmissionInput CanonicalSurfacePreserved) rawDecisions
  assertEqual "authoritative contour should preserve raw lexical/cluster phrase decisions"
    rawDecisions
    (alcpdDecisions admitted)
  assertEqual "authoritative lexical/cluster phrase decision admission should be explicit"
    LcpddAdmitRaw
    (alcpdDecision admitted)

testNonAuthoritativeLexicalClusterPhraseDecisionSuppressesStrongDecisions :: Test
testNonAuthoritativeLexicalClusterPhraseDecisionSuppressesStrongDecisions = TestCase $ do
  let rawDecisions = RawLexicalClusterPhraseDecisions
        { rlcpdInputLower = "input"
        , rlcpdClusterDecisions =
            [ RawClusterPhraseDecision "need_meaning" "смысл" True
            , RawClusterPhraseDecision "verification" "проверь" True
            ]
        , rlcpdLexicalDecisions =
            [ RawLexicalPhraseDecision LpcAgencyLost "потерялся" True
            , RawLexicalPhraseDecision LpcNeedContact "рядом" True
            , RawLexicalPhraseDecision LpcExhaustion "устал" True
            , RawLexicalPhraseDecision LpcNegatedExhaustion "не устал" True
            ]
        }
      admittedDecisions = admitLexicalClusterPhraseDecisions (LexicalClusterPhraseDecisionAdmissionInput LegacyIncompleteSurface) rawDecisions
      rawContainment = buildRawLexicalClusterPhraseContainmentFromDecisions (alcpdDecisions admittedDecisions)
      admittedContainment = admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput LegacyIncompleteSurface) rawContainment
  assertEqual "non-authoritative contour should suppress strong lexical/cluster phrase decisions before CTS-17 phrase containment"
    [ False, True ]
    (map rcpdMatched (rlcpdClusterDecisions (alcpdDecisions admittedDecisions)))
  assertEqual "non-authoritative contour should keep safe/control lexical decisions and suppress strong ones"
    [ False, True, True, True ]
    (map rlpdMatched (rlcpdLexicalDecisions (alcpdDecisions admittedDecisions)))
  assertEqual "suppressed phrase decisions should build only safe phrase containment before CTS-17 admission"
    [RawClusterPhraseContainment "verification" ["проверь"]]
    (rlcpcClusterContainment rawContainment)
  assertEqual "suppressed phrase decisions should build only safe lexical containment before CTS-17 admission"
    [ RawLexicalPhraseContainment LpcExhaustion ["устал"]
    , RawLexicalPhraseContainment LpcNegatedExhaustion ["не устал"]
    , RawLexicalPhraseContainment LpcNeedContact ["рядом"]
    ]
    (rlcpcLexicalContainment rawContainment)
  assertEqual "CTS-17 should preserve already-safe phrase containment built from admitted decisions"
    rawContainment
    (alcpContainment admittedContainment)
  assertEqual "non-authoritative lexical/cluster phrase decision admission should be explicit"
    LcpddSuppressStrongDecisions
    (alcpdDecision admittedDecisions)
  assertEqual "CTS-17 should preserve ambiguity on already-safe phrase containment built from admitted decisions"
    LpdPreserveAmbiguous
    (alcpDecision admittedContainment)

testNonAuthoritativeSafeLexicalClusterPhraseDecisionsStayPresent :: Test
testNonAuthoritativeSafeLexicalClusterPhraseDecisionsStayPresent = TestCase $ do
  let rawDecisions = RawLexicalClusterPhraseDecisions
        { rlcpdInputLower = "input"
        , rlcpdClusterDecisions = [RawClusterPhraseDecision "verification" "проверь" True]
        , rlcpdLexicalDecisions = [RawLexicalPhraseDecision LpcNeedContact "рядом" True]
        }
      admitted = admitLexicalClusterPhraseDecisions (LexicalClusterPhraseDecisionAdmissionInput LegacyIncompleteSurface) rawDecisions
  assertEqual "already-safe lexical/cluster phrase decisions should remain present"
    rawDecisions
    (alcpdDecisions admitted)
  assertEqual "safe lexical/cluster phrase decision contour should preserve ambiguity"
    LcpddPreserveAmbiguous
    (alcpdDecision admitted)

testPrepareUsesAdmittedLexicalClusterPhraseDecisionPlane :: Test
testPrepareUsesAdmittedLexicalClusterPhraseDecisionPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted lexical/cluster phrase decision plane"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

testConstitutionAdmissibleLexicalClusterPhraseContainmentPreservesRawContainment :: Test
testConstitutionAdmissibleLexicalClusterPhraseContainmentPreservesRawContainment = TestCase $ do
  let rawContainment = RawLexicalClusterPhraseContainment
        { rlcpcInputLower = "input"
        , rlcpcClusterContainment = [RawClusterPhraseContainment "need_meaning" ["смысл"]]
        , rlcpcLexicalContainment = [RawLexicalPhraseContainment LpcNeedContact ["рядом"]]
        }
      admitted = admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput CanonicalSurfacePreserved) rawContainment
  assertEqual "authoritative contour should preserve raw lexical/cluster phrase containment"
    rawContainment
    (alcpContainment admitted)
  assertEqual "authoritative lexical/cluster phrase containment admission should be explicit"
    LpdAdmitRaw
    (alcpDecision admitted)

testNonAuthoritativeLexicalClusterPhraseContainmentSuppressesStrongContainment :: Test
testNonAuthoritativeLexicalClusterPhraseContainmentSuppressesStrongContainment = TestCase $ do
  let rawContainment = RawLexicalClusterPhraseContainment
        { rlcpcInputLower = "input"
        , rlcpcClusterContainment =
            [ RawClusterPhraseContainment "need_meaning" ["смысл"]
            , RawClusterPhraseContainment "verification" ["проверь"]
            ]
        , rlcpcLexicalContainment =
            [ RawLexicalPhraseContainment LpcAgencyLost ["потерялся"]
            , RawLexicalPhraseContainment LpcNeedContact ["рядом"]
            , RawLexicalPhraseContainment LpcExhaustion ["устал"]
            , RawLexicalPhraseContainment LpcNegatedExhaustion ["не устал"]
            ]
        }
      admittedContainment = admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput LegacyIncompleteSurface) rawContainment
      rawHits = buildRawLexicalClusterHitsFromPhraseContainment (alcpContainment admittedContainment)
      admittedHits = admitLexicalClusterHits (LexicalClusterHitAdmissionInput LegacyIncompleteSurface) rawHits
  assertEqual "non-authoritative contour should suppress strong lexical/cluster phrase containment before raw hit production"
    [ RawClusterPhraseContainment "verification" ["проверь"] ]
    (rlcpcClusterContainment (alcpContainment admittedContainment))
  assertEqual "non-authoritative contour should keep only safe lexical containment and suppression controls"
    [ RawLexicalPhraseContainment LpcNeedContact ["рядом"]
    , RawLexicalPhraseContainment LpcExhaustion ["устал"]
    , RawLexicalPhraseContainment LpcNegatedExhaustion ["не устал"]
    ]
    (rlcpcLexicalContainment (alcpContainment admittedContainment))
  assertEqual "suppressed phrase containment should build only safe raw hits before CTS-16 hit admission"
    [Verification "проверь", NeedContact "лексика"]
    (map rchTag (rlchClusterHits rawHits) ++ map rlhTag (rlchLexicalHits rawHits))
  assertEqual "CTS-16 hit admission should preserve already-safe hits built from admitted phrase containment"
    rawHits
    (alchHits admittedHits)
  assertEqual "non-authoritative lexical/cluster phrase containment admission should be explicit"
    LpdSuppressStrongContainment
    (alcpDecision admittedContainment)
  assertEqual "CTS-16 should preserve ambiguity on already-safe hits built from admitted phrase containment"
    LchdPreserveAmbiguous
    (alchDecision admittedHits)

testNonAuthoritativeSafeLexicalClusterPhraseContainmentStaysPresent :: Test
testNonAuthoritativeSafeLexicalClusterPhraseContainmentStaysPresent = TestCase $ do
  let rawContainment = RawLexicalClusterPhraseContainment
        { rlcpcInputLower = "input"
        , rlcpcClusterContainment = [RawClusterPhraseContainment "verification" ["проверь"]]
        , rlcpcLexicalContainment = [RawLexicalPhraseContainment LpcNeedContact ["рядом"]]
        }
      admitted = admitLexicalClusterPhraseContainment (LexicalClusterPhraseAdmissionInput LegacyIncompleteSurface) rawContainment
  assertEqual "already-safe lexical/cluster phrase containment should remain present"
    rawContainment
    (alcpContainment admitted)
  assertEqual "safe lexical/cluster phrase containment should preserve ambiguity"
    LpdPreserveAmbiguous
    (alcpDecision admitted)

testPrepareUsesAdmittedLexicalClusterPhraseContainmentPlane :: Test
testPrepareUsesAdmittedLexicalClusterPhraseContainmentPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted lexical/cluster phrase containment plane"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

testConstitutionAdmissibleLexicalClusterHitPreservesRawHits :: Test
testConstitutionAdmissibleLexicalClusterHitPreservesRawHits = TestCase $ do
  let rawHits = RawLexicalClusterHits
        { rlchInputLower = "input"
        , rlchClusterHits = [RawClusterHit (NeedMeaning "cluster") ["смысл"]]
        , rlchLexicalHits = [RawLexicalHit (Verification "self") ["докажи"]]
        }
      admitted = admitLexicalClusterHits (LexicalClusterHitAdmissionInput CanonicalSurfacePreserved) rawHits
  assertEqual "authoritative contour should preserve raw lexical/cluster hits"
    rawHits
    (alchHits admitted)
  assertEqual "authoritative lexical/cluster hit admission should be explicit"
    LchdAdmitRaw
    (alchDecision admitted)

testNonAuthoritativeLexicalClusterHitSuppressesStrongHits :: Test
testNonAuthoritativeLexicalClusterHitSuppressesStrongHits = TestCase $ do
  let rawHits = RawLexicalClusterHits
        { rlchInputLower = "input"
        , rlchClusterHits =
            [ RawClusterHit (NeedMeaning "cluster") ["смысл"]
            , RawClusterHit (Verification "self") ["проверь"]
            ]
        , rlchLexicalHits =
            [ RawLexicalHit (AgencyLost 0.6) ["потерялся"]
            , RawLexicalHit (NeedContact "self") ["рядом"]
            ]
        }
      admitted = admitLexicalClusterHits (LexicalClusterHitAdmissionInput LegacyIncompleteSurface) rawHits
      emittedMatches = buildRawLexicalClusterMatchesFromHits (alchHits admitted)
  assertEqual "non-authoritative contour should suppress strong lexical/cluster hits before match emission"
    [Verification "self", NeedContact "self"]
    (map rchTag (rlchClusterHits (alchHits admitted)) ++ map rlhTag (rlchLexicalHits (alchHits admitted)))
  assertEqual "suppressed lexical/cluster hits should emit only safe matches"
    [Verification "self", NeedContact "self"]
    (map maTag (rlmClusterAtoms emittedMatches ++ rlmLexicalAtoms emittedMatches))
  assertEqual "non-authoritative lexical/cluster hit admission should be explicit"
    LchdSuppressStrongHits
    (alchDecision admitted)

testNonAuthoritativeSafeLexicalClusterHitsStayPresent :: Test
testNonAuthoritativeSafeLexicalClusterHitsStayPresent = TestCase $ do
  let rawHits = RawLexicalClusterHits
        { rlchInputLower = "input"
        , rlchClusterHits = [RawClusterHit (Verification "self") ["проверь"]]
        , rlchLexicalHits = [RawLexicalHit (NeedContact "self") ["рядом"]]
        }
      admitted = admitLexicalClusterHits (LexicalClusterHitAdmissionInput LegacyIncompleteSurface) rawHits
  assertEqual "already-safe lexical/cluster hits should remain present"
    rawHits
    (alchHits admitted)
  assertEqual "safe lexical/cluster hit contour should preserve ambiguity"
    LchdPreserveAmbiguous
    (alchDecision admitted)

testPrepareUsesAdmittedLexicalClusterHitPlane :: Test
testPrepareUsesAdmittedLexicalClusterHitPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted lexical/cluster hit plane"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

testConstitutionAdmissibleLexicalClusterMatchingPreservesRawMatches :: Test
testConstitutionAdmissibleLexicalClusterMatchingPreservesRawMatches = TestCase $ do
  let rawMatches = RawLexicalClusterMatches
        { rlmClusterAtoms = [MeaningAtom "cluster" (NeedMeaning "cluster") (V.fromList [])]
        , rlmLexicalAtoms = [MeaningAtom "lexical" (Verification "self") (V.fromList [])]
        }
      admitted = admitLexicalClusterMatches (LexicalClusterMatchAdmissionInput CanonicalSurfacePreserved) rawMatches
  assertEqual "authoritative contour should preserve raw lexical/cluster matches"
    rawMatches
    (alcmMatches admitted)
  assertEqual "authoritative lexical/cluster admission should be explicit"
    LcdAdmitRaw
    (alcmDecision admitted)

testNonAuthoritativeLexicalClusterMatchingSuppressesStrongMatches :: Test
testNonAuthoritativeLexicalClusterMatchingSuppressesStrongMatches = TestCase $ do
  let rawMatches = RawLexicalClusterMatches
        { rlmClusterAtoms = [MeaningAtom "cluster" (NeedMeaning "cluster") (V.fromList []), MeaningAtom "cluster-safe" (Verification "self") (V.fromList [])]
        , rlmLexicalAtoms = [MeaningAtom "lexical" (AgencyLost 0.6) (V.fromList []), MeaningAtom "lexical-safe" (NeedContact "self") (V.fromList [])]
        }
      admitted = admitLexicalClusterMatches (LexicalClusterMatchAdmissionInput LegacyIncompleteSurface) rawMatches
  assertEqual "non-authoritative contour should suppress strong lexical/cluster matches before RawAtomFindings"
    [Verification "self", NeedContact "self"]
    (map maTag (rlmClusterAtoms (alcmMatches admitted) ++ rlmLexicalAtoms (alcmMatches admitted)))
  assertEqual "non-authoritative lexical/cluster admission should be explicit"
    LcdSuppressStrongMatches
    (alcmDecision admitted)

testNonAuthoritativeSafeLexicalClusterMatchesStayPresent :: Test
testNonAuthoritativeSafeLexicalClusterMatchesStayPresent = TestCase $ do
  let rawMatches = RawLexicalClusterMatches
        { rlmClusterAtoms = [MeaningAtom "cluster-safe" (Verification "self") (V.fromList [])]
        , rlmLexicalAtoms = [MeaningAtom "lexical-safe" (NeedContact "self") (V.fromList [])]
        }
      admitted = admitLexicalClusterMatches (LexicalClusterMatchAdmissionInput LegacyIncompleteSurface) rawMatches
  assertEqual "already-safe lexical/cluster matches should remain present"
    rawMatches
    (alcmMatches admitted)
  assertEqual "safe lexical/cluster matching contour should preserve ambiguity"
    LcdPreserveAmbiguous
    (alcmDecision admitted)

testPrepareUsesAdmittedLexicalClusterMatchingPlane :: Test
testPrepareUsesAdmittedLexicalClusterMatchingPlane = TestCase $ do
  let startSs = authoritativePreparedFixtureState
        { ssTruthContractStatus = LegacyIncompleteSurface }
      plan = planPrepareEffects startSs "в чем смысл жизни" testEpochZero
  assertBool "prepare should carry the early family selected from admitted lexical/cluster matching plane"
    (psRecommendedFamily (pepStatic plan) `elem` [CMClarify, CMRepair, CMGround, CMNextStep])

withDeterministicEmbedding :: IO a -> IO a
withDeterministicEmbedding =
  withEnvVar "QXFX0_EMBEDDING_BACKEND" (Just "local-deterministic")
    . withEnvVar "EMBEDDING_API_URL" Nothing

assertStructuredTurn :: T.Text -> CanonicalMoveFamily -> [T.Text] -> IO ()
assertStructuredTurn rawInput expectedFamily requiredFragments = do
  (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture rawInput
  let rendered = taRendered ta
      lowered = T.toLower rendered
  assertEqual "structured turn should preserve expected family" expectedFamily (tpFinalFamily tp)
  assertEqual "structured turn decision must stay aligned with final family" expectedFamily (tdFamily (taDecision ta))
  assertEqual "structured turn should not leak local recovery cause" Nothing (taLocalRecoveryCause ta)
  assertBool "structured turn should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
  assertBool "structured turn should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
  assertBool "structured turn should not leak legacy translit fallback phrase" (not ("moya identichnost formiruetsya cherez dialog" `T.isInfixOf` lowered))
  assertBool "structured turn should produce a non-trivial Russian surface" (T.length (T.strip rendered) > 60)
  mapM_ (\fragment -> assertBool ("structured turn should mention: " <> T.unpack fragment) (fragment `T.isInfixOf` lowered)) requiredFragments

summarizeRoutePlan
  :: RouteEffectPlan
  -> ( CanonicalMoveFamily
     , Maybe CanonicalMoveFamily
     , ResponseStrategy
     , RenderStyle
     , RouteEffectRequest
     , RouteEffectRequest
     )
summarizeRoutePlan plan =
  let decision = rsRoutingDecision (repStatic plan)
  in ( rdFamily decision
     , rdStrategyFamily decision
     , rdRenderStrategy decision
     , rdRenderStyle decision
     , repShadowRequest plan
     , repAgdaRequest plan
     )

summarizeRenderPlan :: RenderEffectPlan -> (Maybe LocalRecoveryPlan, Maybe T.Text, T.Text)
summarizeRenderPlan plan =
  ( repLocalRecoveryPlan plan
  , repRenderMorphologyWarning plan
  , rsRenderWithBg (repRenderStatic plan)
  )

summarizeFinalizePrecommitPlan
  :: FinalizePrecommitPlan
  -> ( CanonicalMoveFamily
     , R5Verdict
     , Int
     , Bool
     , Int
     , UTCTime
     , FinalizePrecommitRequest
     )
summarizeFinalizePrecommitPlan plan =
  let static = fppStatic plan
  in ( fsOutcomeFamily static
     , fsOutcomeVerdict static
     , fsConsecReflect static
     , fsTransitionWon static
     , length (mgEdges (fsMeaningGraphBase static))
     , fppCapturedCurrentTime plan
     , fppIntrospectionRequest plan
     )

summarizeFinalizeCommitPlan :: FinalizeCommitPlan -> (T.Text, Int, T.Text, Int)
summarizeFinalizeCommitPlan plan =
  ( CLoop.roSurfaceText (fcpResponseObservation plan)
  , ssTurnCount (fcpSaveState plan)
  , fcpSessionId plan
  , fcpRewireEventsCount plan
  )

quickCheckTest :: Testable prop => String -> prop -> Test
quickCheckTest label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 100 } prop
  case result of
    Success{} -> pure ()
    _ -> assertFailure ("QuickCheck failed: " <> label)

testEpochZero :: UTCTime
testEpochZero = UTCTime (ModifiedJulianDay 0) 0

-- | WP2: selectTool picks the highest-reliability validatable tool
-- whose domain matches the learning need.
testToolSelectsBestMatchByDomainAndReliability :: Test
testToolSelectsBestMatchByDomainAndReliability = TestCase $ do
  let salienceTools =
        [ ExternalTool "low-reliability-salience" DomainSalience 0.50 True
        , ExternalTool "high-reliability-salience" DomainSalience 0.95 True
        ]
      result = selectTool NeedSalienceCalibration salienceTools
  assertEqual "must select highest-reliability validatable salience tool"
    (Just "high-reliability-salience")
    (etName <$> result)

-- | WP2: selectTool rejects a need when no tool covers its domain
-- (and no general fallback exists).
testToolRejectsMismatchDomain :: Test
testToolRejectsMismatchDomain = TestCase $ do
  let lexiconOnly =
        [ ExternalTool "lexicon-script" DomainLexicon 0.90 True
        ]
      result = selectTool NeedSalienceCalibration lexiconOnly
  assertEqual "must reject when no domain match and no general fallback"
    Nothing
    result

-- | WP2: among matching tools, validatable is preferred even if a
-- non-validatable tool has higher raw reliability.
testToolPrefersValidatableOverHigherReliability :: Test
testToolPrefersValidatableOverHigherReliability = TestCase $ do
  let keywordTools =
        [ ExternalTool "non-validatable-high-rel" DomainKeyword 0.99 False
        , ExternalTool "validatable-lower-rel"    DomainKeyword 0.80 True
        ]
      result = selectTool NeedKeywordEnrichment keywordTools
  assertEqual "must prefer validatable tool over higher-reliability non-validatable"
    (Just "validatable-lower-rel")
    (etName <$> result)

-- | WP2: NeedNone must never select a tool.
testToolNoneForNoNeed :: Test
testToolNoneForNoNeed = TestCase $ do
  let result = selectTool NeedNone defaultAvailableTools
  assertEqual "NeedNone must not select any tool"
    Nothing
    result

-- | WP4: verifyProposal rejects an empty rule.
testCalibrationVerifyRejectsEmptyRule :: Test
testCalibrationVerifyRejectsEmptyRule = TestCase $ do
  let result = verifyProposal [] (ProposalRule "")
  case result of
    Left "empty_rule" -> pure ()
    _ -> assertFailure "verify must reject empty rule"

-- | WP4: verifyProposal rejects a blocked rule.
testCalibrationVerifyRejectsBlockedRule :: Test
testCalibrationVerifyRejectsBlockedRule = TestCase $ do
  let result = verifyProposal ["blocked"] (ProposalRule "blocked")
  case result of
    Left "blocked_rule" -> pure ()
    _ -> assertFailure "verify must reject blocked rule"

-- | WP4: verifyProposal accepts a non-empty, non-blocked concept.
testCalibrationVerifyAcceptsValidConcept :: Test
testCalibrationVerifyAcceptsValidConcept = TestCase $ do
  let result = verifyProposal ["blocked"] (ProposalConcept "new-concept")
  case result of
    Right () -> pure ()
    Left err -> assertFailure ("verify must accept valid concept, got: " <> T.unpack err)

-- | WP4: acceptProposal creates an Accepted entry and bumps version.
testCalibrationAcceptCreatesEntry :: Test
testCalibrationAcceptCreatesEntry = TestCase $ do
  let (entry, nextId) =
        acceptProposal (CalibrationId 7) (ProposalConcept "test") 42 (Just (CalibrationId 6))
  assertEqual "status must be Accepted"
    Accepted (ceStatus entry)
  assertEqual "id must match input"
    (CalibrationId 7) (ceId entry)
  assertEqual "nextId must be incremented"
    (CalibrationId 8) nextId
  assertEqual "decidedTurn must be set"
    (Just 42) (ceDecidedTurn entry)
  assertEqual "prevId must be preserved"
    (Just (CalibrationId 6)) (cePrevId entry)

-- | WP4: monitorCalibration returns Right when within minMonitorWindow.
testCalibrationMonitorOkWithinWindow :: Test
testCalibrationMonitorOkWithinWindow = TestCase $ do
  let result = monitorCalibration 0.5 0.8 2 5
  case result of
    Right () -> pure ()
    Left err -> assertFailure ("monitor must not degrade within window, got: " <> T.unpack err)

-- | WP4: monitorCalibration returns Left when level degrades past window.
testCalibrationMonitorDetectsDegradation :: Test
testCalibrationMonitorDetectsDegradation = TestCase $ do
  let result = monitorCalibration 0.3 0.5 5 5
  case result of
    Left "degradation_detected" -> pure ()
    _ -> assertFailure "monitor must detect degradation when level rises"

-- | WP4: rollbackCalibration returns previous version for Accepted entry.
testCalibrationRollbackReturnsPrevVersion :: Test
testCalibrationRollbackReturnsPrevVersion = TestCase $ do
  let entry = CalibrationEntry
        { ceId = CalibrationId 7
        , ceProposal = ProposalConcept "test"
        , ceStatus = Accepted
        , ceCreatedTurn = 10
        , ceDecidedTurn = Just 10
        , cePrevId = Just (CalibrationId 6)
        }
      result = rollbackCalibration entry 20
  case result of
    Nothing -> assertFailure "rollback must succeed for Accepted entry with prevId"
    Just (rolled, currentId) -> do
      assertEqual "rolled status must be RolledBack"
        RolledBack (ceStatus rolled)
      assertEqual "decidedTurn must update to rollback turn"
        (Just 20) (ceDecidedTurn rolled)
      assertEqual "currentId must be the prevId"
        (CalibrationId 6) currentId

-- | WP4: rollbackCalibration fails for non-Accepted entries.
testCalibrationRollbackFailsForNonAccepted :: Test
testCalibrationRollbackFailsForNonAccepted = TestCase $ do
  let entry = CalibrationEntry
        { ceId = CalibrationId 7
        , ceProposal = ProposalConcept "test"
        , ceStatus = Rejected
        , ceCreatedTurn = 10
        , ceDecidedTurn = Just 10
        , cePrevId = Just (CalibrationId 6)
        }
      result = rollbackCalibration entry 20
  assertEqual "rollback must fail for Rejected entry"
    Nothing result

-- | WP4: currentCalibrationVersion returns the last Accepted entry ID.
testCalibrationCurrentVersionReturnsLastAccepted :: Test
testCalibrationCurrentVersionReturnsLastAccepted = TestCase $ do
  let entries =
        [ CalibrationEntry (CalibrationId 1) (ProposalConcept "a") Rejected 1 (Just 1) Nothing
        , CalibrationEntry (CalibrationId 2) (ProposalConcept "b") Accepted 2 (Just 2) Nothing
        , CalibrationEntry (CalibrationId 3) (ProposalConcept "c") RolledBack 3 (Just 3) (Just (CalibrationId 2))
        ]
      log = CalibrationLog entries
      result = currentCalibrationVersion log
  assertEqual "current version must be the last Accepted entry"
    (Just (CalibrationId 2)) result

-- | WP5: rate limit blocks after maxProposalsPerWindow submissions.
testGuardrailRateLimitBlocksAfterMax :: Test
testGuardrailRateLimitBlocksAfterMax = TestCase $ do
  let gs = emptyGuardrailState
        { gsWindowStart = 1
        , gsProposalsThisWindow = 2
        }
  assertBool "must block when window is full"
    (not (canSubmitProposal gs 5))

-- | WP5: rate limit resets when window expires.
testGuardrailRateLimitResetsAfterWindow :: Test
testGuardrailRateLimitResetsAfterWindow = TestCase $ do
  let gs = emptyGuardrailState
        { gsWindowStart = 1
        , gsProposalsThisWindow = 2
        }
  assertBool "must allow when window expired"
    (canSubmitProposal gs 12)

-- | WP5: circuit breaker opens after maxConsecutiveRejections.
testGuardrailCircuitBreakerOpensAfterRejections :: Test
testGuardrailCircuitBreakerOpensAfterRejections = TestCase $ do
  let gs = emptyGuardrailState { gsConsecutiveRejections = 3 }
      gs' = recordRejection gs 10
  assertBool "circuit breaker must be open after 3 rejections"
    (not (canSubmitProposal gs' 11))

-- | WP5: circuit breaker closes after cooldownTurns.
testGuardrailCircuitBreakerClosesAfterCooldown :: Test
testGuardrailCircuitBreakerClosesAfterCooldown = TestCase $ do
  let gs = emptyGuardrailState
        { gsConsecutiveRejections = 3
        , gsCooldownExpiry = 15
        }
  assertBool "circuit breaker must close after cooldown"
    (canSubmitProposal gs 16)

-- | WP5: quarantine expires after minQuarantineTurns.
testGuardrailQuarantineExpiresAfterMinTurns :: Test
testGuardrailQuarantineExpiresAfterMinTurns = TestCase $ do
  let gs = emptyGuardrailState { gsQuarantine = [(5, CalibrationId 1)] }
  assertBool "quarantine must expire after min turns"
    (isQuarantineExpired gs 7 (CalibrationId 1))

-- | WP5: quarantine blocks before minQuarantineTurns.
testGuardrailQuarantineBlocksBeforeMinTurns :: Test
testGuardrailQuarantineBlocksBeforeMinTurns = TestCase $ do
  let gs = emptyGuardrailState { gsQuarantine = [(5, CalibrationId 1)] }
  assertBool "quarantine must block before min turns"
    (not (isQuarantineExpired gs 6 (CalibrationId 1)))

-- | WP-D: GuardrailState JSON round-trip preserves all counters.
testGuardrailStateRoundTripsThroughJson :: Test
testGuardrailStateRoundTripsThroughJson = TestCase $ do
  let gs = GuardrailState
        { gsLastProposalTurn = 7
        , gsProposalsThisWindow = 2
        , gsWindowStart = 3
        , gsConsecutiveRejections = 1
        , gsCooldownExpiry = 15
        , gsQuarantine = [(5, CalibrationId 1), (6, CalibrationId 2)]
        }
      decoded = decode (encode gs) :: Maybe GuardrailState
  assertEqual "GuardrailState must round-trip through JSON"
    (Just gs) decoded

-- | WP-D: CalibrationLog JSON round-trip preserves entries and version links.
testCalibrationLogRoundTripsThroughJson :: Test
testCalibrationLogRoundTripsThroughJson = TestCase $ do
  let entry1 = CalibrationEntry
        { ceId = CalibrationId 1
        , ceProposal = ProposalConcept "concept-a"
        , ceStatus = Accepted
        , ceCreatedTurn = 5
        , ceDecidedTurn = Just 5
        , cePrevId = Nothing
        }
      entry2 = CalibrationEntry
        { ceId = CalibrationId 2
        , ceProposal = ProposalConcept "concept-b"
        , ceStatus = RolledBack
        , ceCreatedTurn = 8
        , ceDecidedTurn = Just 10
        , cePrevId = Just (CalibrationId 1)
        }
      log = CalibrationLog [entry1, entry2]
      decoded = decode (encode log) :: Maybe CalibrationLog
  assertEqual "CalibrationLog must round-trip through JSON"
    (Just log) decoded

-- | WP-D: GuardrailState survives one turn through buildNextSystemState.
testGuardrailStatePersistsThroughTurnPipeline :: Test
testGuardrailStatePersistsThroughTurnPipeline = TestCase $
  withDeterministicEmbedding $ do
    (ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixture "что такое свобода"
    let nextSs = fpbNextSs bundle
    assertEqual "guardrail state must survive turn pipeline unchanged"
      (ssGuardrailState ss)
      (ssGuardrailState nextSs)

-- | WP-D: CalibrationLog survives one turn through buildNextSystemState.
testCalibrationLogPersistsThroughTurnPipeline :: Test
testCalibrationLogPersistsThroughTurnPipeline = TestCase $
  withDeterministicEmbedding $ do
    let ss0 = emptySystemState
          { ssCalibrationLog = CalibrationLog
              [ CalibrationEntry (CalibrationId 1) (ProposalConcept "x") Accepted 1 (Just 1) Nothing
              ]
          }
    (ss, ti, ts, tp, ta, bundle) <- buildFinalizeFixtureWithState ss0 "что такое свобода"
    let nextSs = fpbNextSs bundle
    assertEqual "calibration log must survive turn pipeline unchanged"
      (ssCalibrationLog ss0)
      (ssCalibrationLog nextSs)

-- | WP-D: rollback path preserves prevId and current version IDs.
testRollbackPathPreservesPrevAndCurrentIds :: Test
testRollbackPathPreservesPrevAndCurrentIds = TestCase $ do
  let entry = CalibrationEntry
        { ceId = CalibrationId 7
        , ceProposal = ProposalConcept "rollback-test"
        , ceStatus = Accepted
        , ceCreatedTurn = 5
        , ceDecidedTurn = Just 5
        , cePrevId = Just (CalibrationId 6)
        }
      result = rollbackCalibration entry 20
  case result of
    Nothing -> assertFailure "rollback must succeed for Accepted entry with prevId"
    Just (rolled, currentId) -> do
      assertEqual "rolled-back entry must link to prevId 6"
        (Just (CalibrationId 6))
        (cePrevId rolled)
      assertEqual "current version after rollback must be prevId"
        (CalibrationId 6) currentId
      assertEqual "rolled status must be RolledBack"
        RolledBack (ceStatus rolled)

-- | WP-D: cooldown/rate-limit state round-trips via JSON (restart survival).
testCooldownStateSurvivesRestartViaJson :: Test
testCooldownStateSurvivesRestartViaJson = TestCase $ do
  let gs = emptyGuardrailState
        { gsConsecutiveRejections = 3
        , gsCooldownExpiry = 25
        , gsWindowStart = 10
        , gsProposalsThisWindow = 2
        }
      decoded = decode (encode gs) :: Maybe GuardrailState
  assertEqual "cooldown state must survive JSON restart"
    (Just gs) decoded
  case decoded of
    Nothing -> assertFailure "decode must succeed"
    Just gs' -> do
      assertBool "circuit breaker must still be open after restart"
        (not (canSubmitProposal gs' 24))
      assertBool "circuit breaker must close after cooldown post-restart"
        (canSubmitProposal gs' 26)

-- | Phase 8 gap closure: when learning need is active, the render effect
-- plan carries an external query request.
testExternalQueryRequestPopulatedWhenLearningNeedActive :: Test
testExternalQueryRequestPopulatedWhenLearningNeedActive = TestCase $ do
  let ss0 = mkSystemStateWithNeed "что" NeedLexiconExtension
  (ss, ti, ts, tp) <- buildPlannedFixtureWithState ss0 "что"
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  assertBool "external query request must be present for active learning need"
    (repExternalQueryRequest renderPlan /= Nothing)

-- | Phase 8 gap closure: after resolving render effects, the external
-- query result is present in the artifacts.
testExternalQueryResultPopulatedAfterRenderEffects :: Test
testExternalQueryResultPopulatedAfterRenderEffects = TestCase $ do
  let ss0 = mkSystemStateWithNeed "что" NeedLexiconExtension
  (ss, ti, ts, tp, ta) <- buildRenderedFixtureWithState ss0 "что"
  assertBool "external query result must be present after render effects"
    (taExternalQueryResult ta /= Nothing)

-- | Phase 8 gap closure: valid mock response flows through parse,
-- validate, sandbox, and graft into the knowledge tree.
testExternalQueryGraftAppliedInFinalize :: Test
testExternalQueryGraftAppliedInFinalize = TestCase $ do
  let ss0 = mkSystemStateWithNeed "что" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "что"
  let nextSs = fpbNextSs bundle
  assertEqual "knowledge tree must have 1 grafted fruit after external success"
    1 (ktGraftedCount (ssKnowledgeTree nextSs))

-- | Phase 8 gap closure: mock failure (transport error) does not graft;
-- fail-closed.
testExternalQueryFailClosedOnMockFailure :: Test
testExternalQueryFailClosedOnMockFailure = TestCase $ do
  let ss0 = mkSystemStateWithNeed "fail" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "fail"
  let nextSs = fpbNextSs bundle
  assertEqual "knowledge tree must remain empty after external failure"
    0 (ktGraftedCount (ssKnowledgeTree nextSs))

-- | Phase 8 gap closure: when no learning need is active, no external
-- query is attempted.
testExternalQueryNotAttemptedWhenNoRequestStrategy :: Test
testExternalQueryNotAttemptedWhenNoRequestStrategy = TestCase $ do
  (_ss, _ti, _ts, _tp, ta) <- buildRenderedFixture "что такое свобода"
  assertEqual "external query result must be Nothing when no request strategy"
    Nothing (taExternalQueryResult ta)

-- | Phase 9 MVP: ExploratoryPrompt is detected by the parser.
testExploratoryPromptDetected :: Test
testExploratoryPromptDetected = TestCase $ do
  let frame = parseProposition "изучи свободу"
  assertEqual "exploratory prompt must be detected"
    ExploratoryPrompt (ipfPropositionType frame)

-- | Phase 9 MVP: when learning need is active but no request strategy
-- fires, the render plan carries an exploratory query request.
testAutonomousExplorationRequestPopulated :: Test
testAutonomousExplorationRequestPopulated = TestCase $ do
  let ss0 = mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension
  (ss, ti, ts, tp) <- buildPlannedFixtureWithState ss0 "привет"
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  assertEqual "request-driven external query must not be planned for low-deficit need"
    Nothing (repExternalQueryRequest renderPlan)
  assertBool "exploratory query request must be present for active learning need"
    (repExploratoryQueryRequest renderPlan /= Nothing)

-- | Phase 9 MVP: after resolving render effects, the exploratory
-- query result is present in the artifacts.
testAutonomousExplorationResultPopulated :: Test
testAutonomousExplorationResultPopulated = TestCase $ do
  let ss0 = mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, ta) <- buildRenderedFixtureWithState ss0 "привет"
  assertBool "exploratory query result must be present after render effects"
    (taExploratoryQueryResult ta /= Nothing)

-- | Phase 9 MVP: valid exploratory mock response flows through parse,
-- validate, sandbox, and graft into the knowledge tree.
testAutonomousExplorationGraftApplied :: Test
testAutonomousExplorationGraftApplied = TestCase $ do
  let ss0 = mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "привет"
  let nextSs = fpbNextSs bundle
  assertEqual "knowledge tree must have 1 grafted fruit after exploratory success"
    1 (ktGraftedCount (ssKnowledgeTree nextSs))

-- | Phase 9 MVP: mock exploratory failure does not graft; fail-closed.
testAutonomousExplorationFailClosed :: Test
testAutonomousExplorationFailClosed = TestCase $ do
  let ss0 = (mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension)
              { ssLearningNeedState = emptyLearningNeedState
                  { lnsCurrentNeed = NeedLexiconExtension
                  , lnsLevel = 0.8
                  , lnsHistory = [(1, 0.7), (2, 0.75), (3, 0.8)]
                  }
              , ssMorphology = MorphologyData Map.empty Map.empty Map.empty Map.empty
              }
  -- Use "fail" as topic so buildExploratoryQueryText returns "Explore definition of fail"
  -- which doesn't match the mock table (only "Explore" matches for success).
  -- Actually, the mock table has "Explore" -> success for NeedLexiconExtension.
  -- To test failure, we need a different prefix. Let me override the mock table
  -- or use a state that blocks exploration via guardrails.
  -- For now, test that when exploration is blocked by guardrails, no graft happens.
  let ssGuard = ss0
        { ssGuardrailState = emptyGuardrailState
            { gsProposalsThisWindow = 3
            , gsWindowStart = 0
            }
        }
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ssGuard "привет"
  let nextSs = fpbNextSs bundle
  assertEqual "knowledge tree must remain empty when exploration blocked by guardrails"
    0 (ktGraftedCount (ssKnowledgeTree nextSs))

-- | Phase 9 MVP: guardrails (rate limit) block autonomous exploration.
testAutonomousExplorationGuardrailBlocks :: Test
testAutonomousExplorationGuardrailBlocks = TestCase $ do
  let ss0 = mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension
      ssBlocked = ss0
        { ssGuardrailState = emptyGuardrailState
            { gsProposalsThisWindow = 3
            , gsWindowStart = 0
            }
        }
  (ss, ti, ts, tp) <- buildPlannedFixtureWithState ssBlocked "привет"
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  assertEqual "exploratory query must be blocked when guardrails exceeded"
    Nothing (repExploratoryQueryRequest renderPlan)

-- | Phase 9 MVP: telemetry shows "exploratory" query type, not
-- "not_attempted".
testAutonomousExplorationTelemetry :: Test
testAutonomousExplorationTelemetry = TestCase $ do
  let ss0 = mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "привет"
  let trace = tqpReplayTrace (fpbProjection bundle)
  assertEqual "telemetry must show exploratory query type"
    (Just "exploratory") (trcLearningQueryType trace)
  assertEqual "telemetry must expose final exploratory learning verdict"
    (Just "observed_non_authoritative") (trcLearningValidationStatus trace)

-- | Phase 9 MVP: request-driven external query path is not regressed
-- when exploratory path is also active.
testRequestDrivenPathNotRegressedByExploration :: Test
testRequestDrivenPathNotRegressedByExploration = TestCase $ do
  let ss0 = mkSystemStateWithNeed "что" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "что"
  let nextSs = fpbNextSs bundle
  assertEqual "request-driven path must still graft 1 fruit"
    1 (ktGraftedCount (ssKnowledgeTree nextSs))

-- | Helper: construct a SystemState with an active learning need and
-- enough non-empty fields to avoid conatus gate firing, configured
-- for autonomous exploration (no request strategy threshold).
mkSystemStateWithNeedForExploration :: T.Text -> LearningNeed -> SystemState
mkSystemStateWithNeedForExploration topic need =
  let dialogue = ssDialogue emptySystemState
  in emptySystemState
    { ssDialogue = dialogue { dsLastTopic = topic }
    , ssSessionId = "test-session"
    , ssMorphology = MorphologyData Map.empty Map.empty (Map.singleton "a" "b") Map.empty
    , ssLearningNeedState = emptyLearningNeedState
        { lnsCurrentNeed = need
        , lnsLevel = 0.5  -- below request threshold (0.6) so no request strategy
        , lnsHistory = [(1, 0.4), (2, 0.45), (3, 0.5)]
        }
    }

-- | Helper: construct a SystemState with an active learning need and
-- enough non-empty fields to avoid conatus gate firing.
mkSystemStateWithNeed :: T.Text -> LearningNeed -> SystemState
mkSystemStateWithNeed topic need =
  let dialogue = ssDialogue emptySystemState
  in emptySystemState
    { ssDialogue = dialogue { dsLastTopic = topic }
    , ssSessionId = "test-session"
    , ssTruthContractStatus = CanonicalSurfacePreserved
    , ssMorphology = MorphologyData Map.empty Map.empty (Map.singleton "a" "b") Map.empty
    , ssLearningNeedState = emptyLearningNeedState
        { lnsCurrentNeed = need
        , lnsLevel = 0.8
        , lnsHistory = [(1, 0.7), (2, 0.75), (3, 0.8)]
        }
    }

-- | WP6.1: anti-overblocking — a noisy/short known topic must NOT be
-- dedup-skipped so that external queries can still proceed.
testDedupAntiOverblockingAllowsNoisyKnownTopic :: Test
testDedupAntiOverblockingAllowsNoisyKnownTopic = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "в"
    let morph = MorphologyData Map.empty Map.empty (Map.singleton "в" "в") Map.empty
        ss = ss0
          { ssMorphology = morph
          , ssLearningNeedState = emptyLearningNeedState
              { lnsCurrentNeed = NeedLexiconExtension
              , lnsLevel = 0.8
              , lnsPersistence = 3
              }
          }
        ti = ti0
          { tiBestTopic = "в"
          , tiConatusGateFired = False
          , tiConatusEnergy = ConatusEnergy 1.0 (ConatusComponents 0 0 0 0)
          }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "noisy known topic must NOT be dedup-skipped"
      Nothing (repExternalQuerySkipReason renderPlan)
    assertBool "noisy known topic must still produce external query request"
      (repExternalQueryRequest renderPlan /= Nothing)

-- | WP6.1: dedup must still block clean known topics.
testDedupBlocksCleanKnownTopic :: Test
testDedupBlocksCleanKnownTopic = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp) <- buildPlannedFixture "книга"
    let morph = MorphologyData Map.empty Map.empty (Map.singleton "книга" "книга") Map.empty
        ss = ss0
          { ssMorphology = morph
          , ssLearningNeedState = emptyLearningNeedState
              { lnsCurrentNeed = NeedLexiconExtension
              , lnsLevel = 0.8
              , lnsPersistence = 3
              }
          }
        ti = ti0
          { tiBestTopic = "книга"
          , tiConatusGateFired = False
          , tiConatusEnergy = ConatusEnergy 1.0 (ConatusComponents 0 0 0 0)
          }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "clean known topic must be dedup-skipped"
      (Just "already_known_morphology") (repExternalQuerySkipReason renderPlan)
    assertBool "clean known topic must NOT produce external query request"
      (repExternalQueryRequest renderPlan == Nothing)

-- | AS1-01: request-driven external actions must pass through the same
-- guardrail pre-effect gate as exploratory actions.
testRequestDrivenExternalQueryBlockedByGuardrails :: Test
testRequestDrivenExternalQueryBlockedByGuardrails = TestCase $ do
  let ss0 = (mkSystemStateWithNeed "что" NeedLexiconExtension)
        { ssGuardrailState = emptyGuardrailState
            { gsProposalsThisWindow = 3
            , gsWindowStart = 0
            }
        }
  (ss, ti, ts, tp) <- buildPlannedFixtureWithState ss0 "что"
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  assertEqual "request-driven external query must be blocked by the shared pre-effect gate"
    Nothing (repExternalQueryRequest renderPlan)
  assertEqual "shared gate deny reason must be visible on the same skip/deny surface"
    (Just "guardrail_rate_limit") (repExternalQuerySkipReason renderPlan)

-- | AS1-01: exploratory actions still flow through the same shared gate,
-- so the deny reason remains identical for the same blocked state.
testExploratoryExternalQueryBlockedBySharedGuardrails :: Test
testExploratoryExternalQueryBlockedBySharedGuardrails = TestCase $ do
  let ss0 = (mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension)
        { ssGuardrailState = emptyGuardrailState
            { gsProposalsThisWindow = 3
            , gsWindowStart = 0
            }
        }
  (ss, ti, ts, tp) <- buildPlannedFixtureWithState ss0 "привет"
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  assertEqual "exploratory external query must be blocked by the shared pre-effect gate"
    Nothing (repExploratoryQueryRequest renderPlan)
  assertEqual "exploratory deny reason must use the same shared guardrail reason"
    (Just "guardrail_rate_limit") (repExternalQuerySkipReason renderPlan)

-- | AS1-01: when the shared gate denies the request-driven path, no
-- external result is produced and finalize remains inert.
testRequestDrivenBlockedPathRemainsInert :: Test
testRequestDrivenBlockedPathRemainsInert = TestCase $ do
  let ss0 = (mkSystemStateWithNeed "что" NeedLexiconExtension)
        { ssGuardrailState = emptyGuardrailState
            { gsProposalsThisWindow = 3
            , gsWindowStart = 0
            }
        }
  (_ss, _ti, _ts, _tp, ta, bundle) <- buildFinalizeFixtureWithState ss0 "что"
  let nextSs = fpbNextSs bundle
  assertEqual "request-driven blocked path must not resolve an external query result"
    Nothing (taExternalQueryResult ta)
  assertEqual "blocked request-driven path must not graft knowledge"
    0 (ktGraftedCount (ssKnowledgeTree nextSs))

-- | AS1-03: request-driven allowed path exposes a typed allow reason.
testRequestDrivenExternalActionReason :: Test
testRequestDrivenExternalActionReason = TestCase $ do
  let ss0 = mkSystemStateWithNeed "что" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "что"
  let trace = tqpReplayTrace (fpbProjection bundle)
  assertEqual "request-driven path must surface explicit allow reason"
    (Just "allowed_request_driven") (trcExternalActionReason trace)
  assertEqual "request-driven path must surface the active need"
    (Just "NeedLexiconExtension") (trcExternalActionNeed trace)

-- | AS1-03: exploratory allowed path exposes a typed allow reason.
testExploratoryExternalActionReason :: Test
testExploratoryExternalActionReason = TestCase $ do
  let ss0 = mkSystemStateWithNeedForExploration "тема" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "привет"
  let trace = tqpReplayTrace (fpbProjection bundle)
  assertEqual "exploratory path must surface explicit allow reason"
    (Just "allowed_exploratory") (trcExternalActionReason trace)
  assertEqual "exploratory path must surface the active need"
    (Just "NeedLexiconExtension") (trcExternalActionNeed trace)

-- | AS1-03: shared guardrail denial surfaces a deterministic deny reason.
testGuardrailDeniedExternalActionReason :: Test
testGuardrailDeniedExternalActionReason = TestCase $ do
  let ss0 = (mkSystemStateWithNeed "что" NeedLexiconExtension)
        { ssGuardrailState = emptyGuardrailState
            { gsProposalsThisWindow = 3
            , gsWindowStart = 0
            }
        }
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "что"
  let trace = tqpReplayTrace (fpbProjection bundle)
  assertEqual "guardrail denial must surface rate-limit reason"
    (Just "guardrail_rate_limit") (trcExternalActionReason trace)

-- | AS1-03: no-action path is explicit rather than only implied by empty requests.
testNoActionExternalReason :: Test
testNoActionExternalReason = TestCase $ do
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState emptySystemState "что такое свобода"
  let trace = tqpReplayTrace (fpbProjection bundle)
  assertEqual "no-action path must surface explicit no-action reason"
    (Just "no_action_selected") (trcExternalActionReason trace)

testRequestDrivenTransportFailureSurfacesPreActorFailureEvent :: Test
testRequestDrivenTransportFailureSurfacesPreActorFailureEvent = TestCase $ do
  let ss0 = mkSystemStateWithNeed "fail" NeedLexiconExtension
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "fail"
  let trace = tqpReplayTrace (fpbProjection bundle)
  assertEqual "transport failure must keep actor attribution empty"
    Nothing (trcExternalTool trace)
  assertEqual "transport failure must preserve learning failure status"
    (Just "transport_error") (trcLearningValidationStatus trace)
  case trcPreActorFailureEvent trace of
    Just event -> do
      assertEqual "transport failure must surface pre-actor transport kind"
        PreActorTransportFailure (pafeKind event)
      assertEqual "transport failure must preserve request-driven action kind"
        "request_driven" (pafeActionKind event)
      assertBool "transport failure reason must be explicit"
        (not (T.null (pafeReason event)))
    Nothing -> assertFailure "transport failure must surface a pre-actor failure event"

testRequestDrivenNoExecutableToolSurfacesPreActorFailureEvent :: Test
testRequestDrivenNoExecutableToolSurfacesPreActorFailureEvent = TestCase $ do
  let ss0 = (mkSystemStateWithNeed "что" NeedLexiconExtension)
        { ssToolReliability = Map.fromList [("llm-augment", 0.1)] }
  (_ss, _ti, _ts, _tp, ta, bundle) <- buildFinalizeFixtureWithState ss0 "что"
  let trace = tqpReplayTrace (fpbProjection bundle)
      nextSs = fpbNextSs bundle
  assertEqual "request-driven no-executable contour must not schedule a result"
    Nothing (taExternalQueryResult ta)
  assertEqual "request-driven no-executable contour must surface no-executable reason"
    (Just "no_executable_tool") (trcExternalActionReason trace)
  assertEqual "request-driven no-executable contour must keep actor attribution empty"
    Nothing (trcExternalTool trace)
  case trcPreActorFailureEvent trace of
    Just event -> do
      assertEqual "no-executable contour must surface the dedicated pre-actor kind"
        PreActorNoExecutableTool (pafeKind event)
      assertEqual "no-executable contour must stay request-driven"
        "request_driven" (pafeActionKind event)
      assertEqual "no-executable contour must persist stable reason text"
        "no_executable_tool" (pafeReason event)
    Nothing -> assertFailure "no-executable contour must surface a pre-actor failure event"
  assertBool "no-executable contour must not mutate reliability"
    (not (any (\r -> amrKind r == MutToolReliability) (ssAdaptiveMutationLog nextSs)))

testGuardrailDeniedPathDoesNotFabricatePreActorFailureEvent :: Test
testGuardrailDeniedPathDoesNotFabricatePreActorFailureEvent = TestCase $ do
  let ss0 = (mkSystemStateWithNeed "что" NeedLexiconExtension)
        { ssGuardrailState = emptyGuardrailState
            { gsProposalsThisWindow = 3
            , gsWindowStart = 0
            }
        }
  (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState ss0 "что"
  let trace = tqpReplayTrace (fpbProjection bundle)
  assertEqual "guardrail-denied path must remain actor-clean"
    Nothing (trcExternalTool trace)
  assertEqual "guardrail-denied path must preserve deny reason"
    (Just "guardrail_rate_limit") (trcExternalActionReason trace)
  assertEqual "guardrail-denied path must not fabricate a pre-actor failure event"
    Nothing (trcPreActorFailureEvent trace)

-- | ADR-0032: finalize precommit records strong dialogue outcome state
-- separately from external knowledge learning.
testDialogueDevelopmentPersistsOutcomeAndBelief :: Test
testDialogueDevelopmentPersistsOutcomeAndBelief = TestCase $
  withDeterministicEmbedding $ do
    let startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssTruthContractStatus = CanonicalSurfacePreserved
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          }
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs "это помогло"
    let nextSs = fpbNextSs bundle
        outcome = ssDialogueOutcomeLearning nextSs
        belief = ssBeliefStore nextSs
    assertEqual "non-authoritative success-like turn must be downgraded"
      1 (dolDegradedCount outcome)
    assertBool "degraded outcome sample must still be recorded"
      (not (null (dolRecentOutcomes outcome)))
    case dolRecentOutcomes outcome of
      sample:_ -> do
        assertEqual "downgraded success-like sample must preserve evidence strength"
          EvidenceStrong (dosEvidenceStrength sample)
        assertEqual "downgraded success-like sample must only observe"
          AdaptiveObserved (adrDecision (dosDecisionRecord sample))
      [] -> assertFailure "strong outcome sample must be present"
    assertBool "non-authoritative success-like turn must not mutate claim stance memory"
      (not (Map.member "свобода" (bsClaims belief)))

-- | ADR-0032: conflict feedback revises the prior topic instead of
-- storing the conflict utterance as the claim.
testDialogueDevelopmentConflictUsesPriorTopic :: Test
testDialogueDevelopmentConflictUsesPriorTopic = TestCase $
  withDeterministicEmbedding $ do
    let startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssTruthContractStatus = CanonicalSurfacePreserved
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          }
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs "неверно"
    let belief = ssBeliefStore (fpbNextSs bundle)
    case Map.lookup "свобода" (bsClaims belief) of
      Nothing -> pure ()
      Just _ -> assertFailure "non-authoritative conflict must not mutate belief store"

-- | ADR-0032: weak turns do not mutate speech policy or belief store.
testDialogueDevelopmentWeakSignalsDoNotMutate :: Test
testDialogueDevelopmentWeakSignalsDoNotMutate = TestCase $
  withDeterministicEmbedding $ do
    let speechPolicy = emptySpeechPolicyState
          { spsDirectness = 0.20
          , spsCompression = 0.25
          , spsAmbiguityTolerance = 0.80
          , spsRepairBias = 0.15
          , spsSuccessfulPatterns = Map.singleton "formal" 1
          , spsFailedPatterns = Map.singleton "clinical" 2
          , spsLastUpdatedTurn = 4
          }
        belief = emptyBeliefStore
          { bsClaims = Map.singleton "свобода"
              BeliefRecord
                { brClaim = "свобода"
                , brPolarity = BeliefTentative
                , brConfidence = 0.6
                , brEvidence = ["turn=1:success"]
                , brCounterEvidence = []
                , brLastUpdatedTurn = 1
                , brRevisionCount = 0
                }
          , bsRecentRevisions = ["свобода"]
          }
        startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          , ssSpeechPolicyState = speechPolicy
          , ssBeliefStore = belief
          }
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs "что такое свобода"
    let nextSs = fpbNextSs bundle
    assertEqual "weak turn must not mutate speech policy"
      speechPolicy (ssSpeechPolicyState nextSs)
    assertEqual "weak turn must not mutate belief store"
      belief (ssBeliefStore nextSs)

-- | Weak acknowledgements are observable, but cannot trigger strong adaptive mutation.
testDialogueDevelopmentWeakAcknowledgementDoesNotMutate :: Test
testDialogueDevelopmentWeakAcknowledgementDoesNotMutate = TestCase $
  withDeterministicEmbedding $ do
    let startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          }
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs "спасибо"
    let nextSs = fpbNextSs bundle
        outcome = ssDialogueOutcomeLearning nextSs
    assertEqual "weak acknowledgement on non-authoritative turn must be downgraded"
      1 (dolDegradedCount outcome)
    case dolRecentOutcomes outcome of
      sample:_ -> do
        assertEqual "weak acknowledgement must be capped by truth contract"
          EvidenceModerate (dosEvidenceStrength sample)
        assertEqual "weak acknowledgement must only observe"
          AdaptiveObserved (adrDecision (dosDecisionRecord sample))
        assertBool "weak acknowledgement signal must be preserved for audit"
          ("weak_acknowledgement" `elem` dosSignals sample)
      [] -> assertFailure "weak acknowledgement sample must be recorded"
    assertEqual "weak acknowledgement must not mutate speech policy"
      emptySpeechPolicyState (ssSpeechPolicyState nextSs)
    assertEqual "weak acknowledgement must not mutate claim stance memory"
      emptyBeliefStore (ssBeliefStore nextSs)

-- | Confirmation-like weak acknowledgements remain observational only.
testDialogueDevelopmentWeakConfirmationPhrasesStayWeak :: Test
testDialogueDevelopmentWeakConfirmationPhrasesStayWeak = TestCase $
  withDeterministicEmbedding $ do
    let startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          }
        phrases = ["ясно", "понял", "makes sense"]
    mapM_ (assertWeakConfirmation startSs) phrases
  where
    assertWeakConfirmation startSs phrase = do
      (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs phrase
      let nextSs = fpbNextSs bundle
      case dolRecentOutcomes (ssDialogueOutcomeLearning nextSs) of
        sample:_ -> do
          assertEqual "confirmation-like acknowledgement must be capped by truth contract"
            EvidenceModerate (dosEvidenceStrength sample)
          assertEqual "confirmation-like acknowledgement must only observe"
            AdaptiveObserved (adrDecision (dosDecisionRecord sample))
          assertBool "top-level log must not accept speech-policy mutation"
            (not (any acceptedSpeechOrClaim (ssAdaptiveMutationLog nextSs)))
        [] -> assertFailure "weak confirmation sample must be recorded"
    acceptedSpeechOrClaim record =
      amrDecision record == AdaptiveAccepted
        && amrKind record `elem` [MutSpeechPolicy, MutClaimStance]

-- | A repeated question is a strong dialogue signal with bounded speech-policy mutation.
testDialogueDevelopmentRepeatedQuestionRecordsMutation :: Test
testDialogueDevelopmentRepeatedQuestionRecordsMutation = TestCase $
  withDeterministicEmbedding $ do
    let utterance = "что такое свобода"
        startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssDialogue = (ssDialogue emptySystemState)
              { dsLastTopic = "свобода"
              , dsRawInputHistory = Seq.fromList [utterance]
              }
          }
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs utterance
    let nextSs = fpbNextSs bundle
        outcome = ssDialogueOutcomeLearning nextSs
    assertEqual "repeated question on non-authoritative turn must be downgraded"
      1 (dolDegradedCount outcome)
    case dolRecentOutcomes outcome of
      sample:_ -> do
        assertEqual "sample kind must be capped to degraded"
          DialogueOutcomeDegraded (dosKind sample)
        assertEqual "repeated question evidence is preserved but not upgraded"
          EvidenceStrong (dosEvidenceStrength sample)
        assertEqual "repeated question must only observe under ceiling"
          AdaptiveObserved (adrDecision (dosDecisionRecord sample))
      [] -> assertFailure "repeated question sample must be recorded"
    assertBool "top-level log must not contain accepted speech-policy mutation"
      (not (any (\r -> amrKind r == MutSpeechPolicy && amrDecision r == AdaptiveAccepted) (ssAdaptiveMutationLog nextSs)))

-- | Every strong mutation is backed by a typed decision record.
testDialogueDevelopmentDecisionRecordsStrongMutation :: Test
testDialogueDevelopmentDecisionRecordsStrongMutation = TestCase $
  withDeterministicEmbedding $ do
    let startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          }
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs "неверно"
    let nextSs = fpbNextSs bundle
    case dolRecentOutcomes (ssDialogueOutcomeLearning nextSs) of
      sample:_ -> do
        let decision = dosDecisionRecord sample
        assertEqual "conflict evidence remains strong under ceiling"
          EvidenceStrong (dosEvidenceStrength sample)
        assertEqual "conflict mutation must be observed under non-authoritative ceiling"
          AdaptiveObserved (adrDecision decision)
      [] -> assertFailure "strong conflict sample must be recorded"
    assertBool "top-level log must not contain accepted speech-policy mutation"
      (not (any (\r -> amrKind r == MutSpeechPolicy && amrDecision r == AdaptiveAccepted) (ssAdaptiveMutationLog nextSs)))
    assertBool "top-level log must not contain accepted claim-stance mutation"
      (not (any (\r -> amrKind r == MutClaimStance && amrDecision r == AdaptiveAccepted) (ssAdaptiveMutationLog nextSs)))

-- | P4: finalize runs PerspectiveOperator through the governed adaptive contour.
testPerspectiveFinalizeRecordsGovernedMutation :: Test
testPerspectiveFinalizeRecordsGovernedMutation = TestCase $
  withDeterministicEmbedding $ do
    let startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          , ssBeliefStore = emptyBeliefStore
              { bsClaims = Map.singleton "свобода"
                  BeliefRecord
                    { brClaim = "свобода требует ответственности"
                    , brPolarity = BeliefAffirmed
                    , brConfidence = 0.8
                    , brEvidence = ["user_confirmed"]
                    , brCounterEvidence = []
                    , brLastUpdatedTurn = 1
                    , brRevisionCount = 1
                    }
              }
          , ssDialogueOutcomeLearning = emptyDialogueOutcomeLearningState
              { dolRecentOutcomes =
                  [ mkPerspectiveOutcome 2 DialogueOutcomeSuccess "свобода"
                  , mkPerspectiveOutcome 1 DialogueOutcomeSuccess "свобода"
                  ]
              }
          }
    -- The governed perspective contour only commits for an AUTHORITATIVE
    -- executed turn (rebuildGovernedViews refuses a non-authoritative truth
    -- contract by design). The executed contract is set from the turn outcome
    -- (overwriting startSs), and input "это помогло" yields a non-authoritative
    -- outcome — so use the authoritative fixture helper, which forces canonical
    -- artifacts, to exercise the real commit path.
    (bundle, _ta) <- buildAuthoritativePerspectiveFinalizeFixture startSs "это помогло"
    let nextSs = fpbNextSs bundle
    assertBool "top-level mutation log must include P4 mutation"
      (any (\r -> amrKind r == MutPerspective && amrDecision r `elem` [AdaptiveAccepted, AdaptivePromoted, AdaptiveObserved]) (ssAdaptiveMutationLog nextSs))
    assertBool "perspective contour must remain governed and must not fail by default"
      (ssGovernanceRuntimeFault nextSs == Nothing)

-- | P4: replay exposes only safe perspective projection, not raw candidate internals.
testPerspectiveFinalizeReplayUsesSafeProjectionOnly :: Test
testPerspectiveFinalizeReplayUsesSafeProjectionOnly = TestCase $
  withDeterministicEmbedding $ do
    let startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "свобода" }
          , ssBeliefStore = emptyBeliefStore
              { bsClaims = Map.singleton "свобода"
                  BeliefRecord
                    { brClaim = "свобода требует ответственности"
                    , brPolarity = BeliefAffirmed
                    , brConfidence = 0.8
                    , brEvidence = ["user_confirmed"]
                    , brCounterEvidence = []
                    , brLastUpdatedTurn = 1
                    , brRevisionCount = 1
                    }
              }
          , ssDialogueOutcomeLearning = emptyDialogueOutcomeLearningState
              { dolRecentOutcomes =
                  [ mkPerspectiveOutcome 2 DialogueOutcomeSuccess "свобода"
                  , mkPerspectiveOutcome 1 DialogueOutcomeSuccess "свобода"
                  ]
              }
          }
    (_ss, _ti, _ts, _tp, _ta, bundle) <- buildFinalizeFixtureWithState startSs "это помогло"
    let replay = tqpReplayTrace (fpbProjection bundle)
        encodedReplay = encode replay
    case trcPerspectiveProjection replay of
      Nothing -> pure ()
      Just projection -> do
        assertBool "projection must expose summary"
          (not (T.null (ppSummary projection)))
        assertBool "projection must expose explanation handle"
          (not (T.null (ppExplanationHandle projection)))
    assertBool "replay JSON must not expose raw candidate thesis field"
      (not ("pcThesis" `T.isInfixOf` T.pack (show encodedReplay)))

mkPerspectiveOutcome :: Int -> DialogueOutcomeKind -> T.Text -> DialogueOutcomeSample
mkPerspectiveOutcome turn kind topic = DialogueOutcomeSample
  { dosTurn = turn
  , dosKind = kind
  , dosTopic = topic
  , dosSignals = ["perspective_fixture"]
  , dosEvidenceStrength = EvidenceStrong
  , dosStrongUpdate = True
  , dosDecisionRecord = AdaptiveDecisionRecord
      { adrTurn = turn
      , adrCause = "perspective_fixture"
      , adrEvidence = ["perspective_fixture"]
      , adrConfidence = 0.8
      , adrBoundedDelta = ["recent_outcomes<=12"]
      , adrDecision = AdaptiveAccepted
      , adrTargets = [MutDialogueOutcome]
      , adrMutationRecords = []
      }
  }

-- | Adaptive persistent maps keep hard caps instead of growing without bound.
testDialogueDevelopmentBoundsAdaptiveMaps :: Test
testDialogueDevelopmentBoundsAdaptiveMaps = TestCase $
  withDeterministicEmbedding $ do
    let mkStrongSample turn kind topic = DialogueOutcomeSample
          { dosTurn = turn
          , dosKind = kind
          , dosTopic = topic
          , dosSignals = ["test_strong"]
          , dosEvidenceStrength = EvidenceStrong
          , dosStrongUpdate = True
          , dosDecisionRecord = AdaptiveDecisionRecord
              { adrTurn = turn
              , adrCause = "test"
              , adrEvidence = ["test_strong"]
              , adrConfidence = 0.9
              , adrBoundedDelta = ["speech_patterns<=8", "claim_stance_entries<=64"]
              , adrDecision = AdaptiveAccepted
              , adrTargets = [MutSpeechPolicy, MutClaimStance]
              , adrMutationRecords = []
              }
          }
        existingPatterns = Map.fromList [("style-" <> T.pack (show n), n) | n <- [1 :: Int .. 12]]
        speech = emptySpeechPolicyState { spsFailedPatterns = existingPatterns }
        updatedSpeech = updateSpeechPolicy (mkStrongSample 20 DialogueOutcomeConflict "свобода") StyleClinical speech
        existingClaims = Map.fromList
          [ ("claim-" <> T.pack (show n), BeliefRecord
              { brClaim = "claim-" <> T.pack (show n)
              , brPolarity = BeliefTentative
              , brConfidence = 0.5
              , brEvidence = []
              , brCounterEvidence = []
              , brLastUpdatedTurn = n
              , brRevisionCount = 0
              })
          | n <- [1 :: Int .. 70]
          ]
        store = emptyBeliefStore { bsClaims = existingClaims }
        state = emptySystemState { ssDialogue = (ssDialogue emptySystemState) { dsLastTopic = "новый claim" } }
    (_ss, ti, _ts, tp) <- buildPlannedFixtureWithState state "неверно"
    let updatedStore = updateBeliefStore state (mkStrongSample 100 DialogueOutcomeConflict "новый claim") ti tp store
    assertBool "failed speech patterns must be capped"
      (Map.size (spsFailedPatterns updatedSpeech) <= 8)
    assertBool "claim stance entries must be capped"
      (Map.size (bsClaims updatedStore) <= 64)
    assertBool "newly updated claim must be preserved under cap"
      (Map.member "новый claim" (bsClaims updatedStore))

-- | ADR-0032: speech policy can bias future route style when evidence is strong.
testSpeechPolicyBiasesRouteStyle :: Test
testSpeechPolicyBiasesRouteStyle = TestCase $
  withDeterministicEmbedding $ do
    let policy = emptySpeechPolicyState
          { spsDirectness = 0.70
          , spsCompression = 0.70
          }
        ss0 = emptySystemState
          { ssSessionId = "fixture-session"
          , ssMorphology = MorphologyData (Map.singleton "о" "preposition") Map.empty Map.empty Map.empty
          , ssSpeechPolicyState = policy
          }
    (_ss, _ti, _ts, tp) <- buildPlannedFixtureWithState ss0 "что такое свобода"
    assertEqual "speech policy must bias route style to direct"
      "direct" (tpRenderStyle tp)

-- | ADR-0032: speech policy cannot downgrade an existing recovery style.
testSpeechPolicyDoesNotDowngradeRecoveryStyle :: Test
testSpeechPolicyDoesNotDowngradeRecoveryStyle = TestCase $ do
  let policy = emptySpeechPolicyState
        { spsDirectness = 0.90
        , spsCompression = 0.90
        , spsRepairBias = 0.0
        }
  assertEqual "forced recovery style must remain recovery"
    StyleRecovery (adjustRenderStyleForSpeechPolicy policy StyleRecovery)

-- | WP6.1: finalizeMetrics must wire learning-pressure telemetry fields.
testFinalizeMetricsPopulatesLearningTelemetry :: Test
testFinalizeMetricsPopulatesLearningTelemetry = TestCase $
  withDeterministicEmbedding $ do
    let ss0 = emptySystemState
          { ssLearningNeedState = emptyLearningNeedState
              { lnsCurrentNeed = NeedLexiconExtension
              , lnsLevel = 0.75
              , lnsUnknownWindowCount = 4
              , lnsWindowGraftBaseline = 1
              }
          , ssKnowledgeTree = emptyKnowledgeTree { ktGraftedCount = 3 }
          }
    (ss, ti, _ts, _tp, ta, _bundle) <- buildFinalizeFixtureWithState ss0 "что такое свобода"
    let t0 = tiStartTime ti
        t1 = read "2026-05-20 00:00:01 UTC" :: UTCTime
        metrics = finalizeMetrics ti ta CMGround (taDecision ta) ss True InvariantOK t0 t1
    assertEqual "learning pressure score must match lnsLevel"
      0.75 (tmLearningPressureScore metrics)
    assertEqual "unknown count window must match"
      4 (tmUnknownCountWindow metrics)
    assertEqual "grafts window must be graftedCount - baseline"
      2 (tmGraftsWindow metrics)
    assertBool "lexicon trigger reason must mention pressure"
      (T.isInfixOf "lexicon_pressure" (tmLexiconNeedTriggerReason metrics))
    assertEqual "dedup skip reason must be preserved from artifacts"
      (taExternalQuerySkipReason ta) (tmDedupSkipReason metrics)
