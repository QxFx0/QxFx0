{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.CoreBehavior
  ( coreBehaviorTests
  ) where

import Test.HUnit hiding (Testable)
import Test.QuickCheck
  ( Result(..)
  , Testable
  , choose
  , chooseInt
  , elements
  , forAll
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )
import Control.Concurrent.Async (mapConcurrently)
import Control.Concurrent (threadDelay)
import Control.Monad (forM_)
import System.Directory (findExecutable, doesFileExist)
import System.Process (readProcessWithExitCode)
import System.Exit (ExitCode(..))
import Data.IORef (newIORef, readIORef, atomicModifyIORef')
import Data.Time.Clock (getCurrentTime)
import Data.Time (addUTCTime)
import Data.List (foldl', sortOn)
import Data.Maybe (listToMaybe)

import qualified Data.Vector as V
import qualified Data.Text as T

import QxFx0.Types
import QxFx0.Types.ShadowDivergence (ShadowDivergenceSeverity(..))
import QxFx0.Lexicon.Resolver (resolveLexemeForm)
import qualified QxFx0.Lexicon.GfMap as GfMap
import qualified QxFx0.Types.Thresholds as Thr
import QxFx0.Types.Orbital (OrbitalPhase(..), EncounterMode(..), OrbitalMemory(..), emptyOrbitalMemory, omCurrentPhase, omAvgAttraction, omAvgRepulsion, omStableStreak, omCollapseStreak, DirectiveMoveBias(..))
import qualified QxFx0.Semantic.Embedding as Emb
import qualified QxFx0.Semantic.Proposition as Proposition
import qualified QxFx0.Semantic.Morphology as Morph
import qualified QxFx0.Core.Guard as Guard
import qualified QxFx0.Core.Ego as Ego
import qualified QxFx0.Core.R5Dynamics as R5Dynamics
import qualified QxFx0.Core.TurnRender as TurnRender
import qualified QxFx0.Core.Legitimacy as Legitimacy
import qualified QxFx0.Core.TurnLegitimacy as TurnLegitimacy
import qualified QxFx0.Core.TurnPlanning as TurnPlanning
import qualified QxFx0.Core.DreamDynamics as Dream
import qualified QxFx0.Core.BackgroundProcess as Background
import qualified QxFx0.Core.Intuition as Intuition
import qualified QxFx0.Core.Consciousness as Consciousness
import qualified QxFx0.Core.IdentitySignal as IdentitySignal
import qualified QxFx0.Core.IdentityGuard as IdentityGuard
import QxFx0.Semantic.MeaningAtoms (collectAtoms)
import QxFx0.Semantic.SemanticInput (SemanticInput(..))
import QxFx0.Core.IdentitySignal (IdentitySignal(..))
import QxFx0.Core.SessionLock
  ( SessionLockStats(..)
  , newSessionLockManager
  , sessionLockStats
  , withSessionLock
  )
import QxFx0.Semantic.Logic (runSemanticLogic)
import QxFx0.Core (routeFamily, mergeFamilySignals, computeTensionDelta
                    , modulateRMPWithNarrative, modulateRCPWithFlash
                    , narrativeFamilyHint, intuitionFamilyHint
                    )
import QxFx0.Core.TurnPipeline (RoutingDecision(..))
import qualified QxFx0.Core.MeaningGraph as MeaningGraph
import QxFx0.Core.Consciousness (ConsciousnessNarrative(..))
import QxFx0.Core.PrincipledCore (detectPressure)
import QxFx0.Semantic.Proposition (parseProposition, propositionToFamily, PropositionType(..))
import qualified QxFx0.Render.Dialogue as Dialogue
import qualified QxFx0.Render.Semantic as RenderSemantic
import qualified QxFx0.Core.ConsciousnessLoop as CLoop
import QxFx0.Core.Consciousness (ConsciousnessModel(..), ConsciousState(..), SelfInterpretation(..))
import QxFx0.Resources (loadMorphologyData)
import qualified Data.Map.Strict as Map
import QxFx0.Lexicon.Generated (generatedLexemeEntries)
import qualified QxFx0.Lexicon.Types as LexTypes
import qualified QxFx0.Lexicon.Loader as LexLoader
import qualified QxFx0.Lexicon.Runtime as LexRuntime
import qualified QxFx0.Lexicon.Analyze as LexAnalyze
import qualified QxFx0.Core.ClaimBuilder as ClaimBuilder
import qualified QxFx0.Runtime.PGF as RuntimePGF
import QxFx0.ExceptionPolicy (QxFx0Exception(..))
import qualified QxFx0.Bridge.NixGuard as NixGuard
import QxFx0.CLI.Parser (decodeWorkerCommand, parseMode, parseJsonStringArray, extractSessionArgs, RuntimeOutputMode(..), WorkerCommand(..))
import Test.Support (withEnvVar)

testSI :: SemanticLayer -> AtomSet -> CanonicalMoveFamily -> SemanticInput
testSI layer atoms fam = SemanticInput
  { siRawInput = ""
  , siAtomSet = atoms
  , siPropositionFrame = InputPropositionFrame
      { ipfRawText = ""
      , ipfPropositionType = ""
      , ipfFocusEntity = ""
      , ipfFocusNominative = ""
      , ipfSemanticSubject = ""
      , ipfSemanticTarget = ""
      , ipfSemanticCandidates = []
      , ipfSemanticEvidence = []
      , ipfCanonicalFamily = fam
      , ipfIllocutionaryForce = IFAssert
      , ipfClauseForm = Declarative
      , ipfSemanticLayer = layer
      , ipfKeyPhrases = []
      , ipfEmotionalTone = ToneNeutral
      , ipfConfidence = 0.5
      , ipfIsQuestion = False
      , ipfIsNegated = False
      , ipfRegisterHint = Neutral
      }
  , siRecommendedFamily = fam
  , siRegister = Neutral
  , siNeedLayer = layer
  }

coreBehaviorTests :: [Test]
coreBehaviorTests =
    [ testCosineSimilarity
    , testTextToEmbedding
    , testEmbeddingSourceQuality
    , testTextToEmbeddingSourceExplicitLocalBackend
    , testTextToEmbeddingSourceWithoutEndpoint
    , testTextToEmbeddingSourceIgnoresUrlWithoutExplicitRemoteBackend
    , testTextToEmbeddingSourceRemoteFailure
    , testSafetyChecks
    , testSafetyToxicityUsesTokenBoundaries
    , testFinalizeOutputFallsBackToRecoverySurface
    , testSafeOutputTextUsesBlockedFallback
    , testFamilyMappings
    , testExhaustionAtoms
    , testContactAtoms
    , testMeaningAtomsTokenBoundaryAvoidsFalseContact
  , testSessionLockSerializes
  , testSessionLockSerializesUnderBurst
  , testSessionLockOverflowStatsExposeBoundedDegradation
  , testSessionLockConfigurableCap
    , testSemanticLogicExhaustion
    , testSemanticLogicNegatedExhaustionDoesNotRepair
    , testSemanticLogicContact
    , testSemanticLogicDefault
    , testParsePropositionDefinitionalQuestion
    , testParsePropositionLogicalFocusAvoidsConnectives
    , testParsePropositionSocratesFocusPrefersRepeatedEntity
    , testParsePropositionContrastFocusUsesPositiveSide
    , testParsePropositionAffectiveContact
    , testParsePropositionTokenBoundaryAvoidsFalseAnchor
    , testParsePropositionInsuranceRemainsNeutral
    , testParsePropositionOperationalStatusQuestion
    , testParsePropositionSystemLogicQuestion
    , testInferUserStateWhyUsesContentSearch
    , testEgoUpdateSetsMissionAndAgency
    , testLegitimacyPenaltyDemotesLowConfidencePlan
    , testLegitimacyRecoveryBonusRewardsShadowAndStability
    , testClassifyLegitimacyOutcomeNeverWarrantedDeny
    , testClassifyLegitimacyOutcomeShadowDivergedRepair
    , testClassifyLegitimacyOutcomeAdvisoryShadowPermits
    , testClassifyLegitimacyOutcomeLowConfidenceAdvisory
    , testIntegrateIdentityClaimsDeduplicatesAndRanks
    , testMeaningGraphPredictsSuccessfulStrategy
    , testMeaningGraphDreamBiasCanPromoteBorderlineStrategy
    , testMeaningGraphRewireClampsBias
    , testDreamBiasAttractorRejectsLowQualityEvidence
    , testDreamCycleAdvancesState
    , testDreamCatchupSplitsElapsedTime
    , testBackgroundSurfacingOnConflict
    , testIntuitionCheckResetsAfterFlash
    , testIntuitionFlashLikelihoodBands
    , testIntuitionNoFlashLikelihoodBands
    , testPosteriorAfterFlashUsesDecayFactor
    , testUpdateLongPosteriorUsesEmaWeights
    , testEffectivePosteriorBlendsShortAndLong
    , testEffectivePosteriorPreservesHigherShortSignal
    , testConsciousnessInterpretationTracksHighAffinitySkill
    , testMorphologyExtractsContentNouns
    , testMorphologyBuildForms
    , testMorphologyUsesGeneratedRuntimeLexicon
    , testGeneratedLexiconDeterministicGrouping
    , testMorphologyResourcesLexiconContour
    , testMergeFamilySignalsParserOverride
    , testMergeFamilySignalsSemanticOverride
    , testMergeFamilySignalsNoOverride
    , testDetectPressureCorrection
    , testDetectPressureAuthority
    , testDetectPressureEmotional
    , testDetectPressureNoPressure
    , testComputeTensionDeltaNegative
    , testComputeTensionDeltaDistress
    , testComputeTensionDeltaNeutral
    , testComputeTensionDeltaInsuranceNeutral
    , testRouteFamilyInputPropagated
    , testRouteFamilyNixBlocked
    , testNixGuardCyrillicConceptDoesNotUnsafeBlock
    , testRouteFamilyAnchorUsesCurrentTopic
    , testModulateRMPWithNarrativeDeepMode
    , testModulateRMPWithNarrativeTopicFill
    , testModulateRMPWithNarrativeNoOp
    , testModulateRCPWithFlashOverride
    , testModulateRCPWithFlashNoOp
    , testNarrativeFamilyHintSilence
    , testNarrativeFamilyHintConflict
    , testNarrativeFamilyHintContact
    , testNarrativeFamilyHintNoHint
    , testIntuitionFamilyHintHigh
    , testIntuitionFamilyHintLow
    , testRouteFamilyNarrativeHintChangesFamily
    , testRouteFamilyOperationalQuestionResistsReflectNarrative
    , testRouteFamilyIntuitionHintChangesFamily
    , testIsVapidTopicEmpty
    , testIsVapidTopicVapidWord
    , testIsVapidTopicNonVapid
    , testCleanTopicVapidToEmpty
    , testCleanTopicPreservesNonVapid
    , testStancePrefixAllConstructors
    , testMoveToTextGroundKnown
    , testMoveToTextAffirmPresence
    , testGfCombinatorics
    , testGfTopicMapResolvesAllForms
    , testGfTopicMapProvidesForms
    , testClaimAstCoverageForOperationalAndMetaPrompts
    , testGfRoundTripParseSmoke
    , testGfRoundTripAstLinearizeParse
    , testGfFallbackSurfaceParity
    , testAstToGfExprLegacyCompatibility
    , testClaimAstStableForSameIntent
    , testClaimAstSameTreeVariedSurface
    , testRenderSemanticIntrospectionFormat
    , testConsciousnessLoopInitialValues
    , testConsciousnessLoopRunIncrementsTurn
    , testConsciousnessLoopUpdateAfterResponse
    , testConsciousnessLoopAddCoreSignalCapsAt5
    , testLexicalRuntimeBuildFromGenerated
    , testLexicalRuntimeMorphologyRoundTrip
    , testLexicalAnalyzeExtractsNouns
    , testLexicalRuntimeLanguageCode
    , testSubjectStateAgencyValid
    , testSubjectStateTensionValid
    , testClaimBuilderTokenBoundaryAvoidsFalseConceptMatch
    , testIsLegitConstructors
    , testExceptionPolicyQxFx0Exception
    , testDecodeWorkerCommandShutdown
    , testDecodeWorkerCommandTurn
    , testParseModeSemantic
    , testParseJsonStringArray
    , testExtractSessionArgsOverride
    , testExtractSessionArgsDefault
    , testClassifyOrbitalPhaseStable
    , testClassifyOrbitalPhaseCollapseRisk
    , testClassifyOrbitalPhaseFreezeRisk
    , testClassifyOrbitalPhaseCounterpressure
    , testClassifyOrbitalPhaseRecovery
    , testClassifyOrbitalPhaseBoundaryExactly
    , testClassifyEncounterModePressure
    , testClassifyEncounterModeHolding
    , testClassifyEncounterModeCounterweight
    , testClassifyEncounterModeRecovery
    , testClassifyEncounterModeMirroring
    , testClassifyEncounterModeExploration
    , testClassifyEncounterModeBoundary
    , testBuildIdentitySignalSimpleMapsDirectiveFields
    , testIdentityGuardReportFlagsOutOfBounds
    , testIdentityGuardReportWithinBounds
    , testUpdateOrbitalMemoryEMAClamp
    , testUpdateOrbitalMemoryStreakTracking
    , testSteerDirectiveContactBoostRecovery
    , testSteerDirectiveContactBoostFreezeRisk
    , testSteerDirectiveBoundaryBoostCollapseRisk
    , testSteerDirectiveNoOpStable
    , testStrategyToAnswerStrategy
    , testResponseStanceToMarker
    , testStrategyEpistemicPromotionDeep
    , testStrategyEpistemicDemotionShallow
    , testStrategyEpistemicModerateNoChange
    , testStrategyDepthModeMapping
    , testRenderStyleFromDecisionHoldStance
    , testRenderStyleFromDecisionCounterMove
    , testRenderStyleFromDecisionDeepResp
    , testDeriveSemanticAnchorNew
    , testDeriveSemanticAnchorStabilityIncreasesOnSameChannel
    , testDeriveSemanticAnchorResetsOnChannelChange
    , testDeriveSemanticAnchorNoChangeOnEmptyTopicLowLoad
    , testRenderAnchorPrefixStableAnchor
    , testRenderAnchorPrefixUnstableAnchor
    , testUpdateStateNixCacheInsert
    , testUpdateStateNixCacheEvictsOverMax
    , testMeaningGraphEdgeCapProperty
    , testMeaningGraphSuccessRateBoundedProperty
    , testMeaningGraphRecordPreservesEdgesProperty
    , testMeaningStateIdInjectiveProperty
    , testEgoTensionBoundedProperty
    , testLegitimacyDegradesToCautiousProperty
    , testOrbitalPhaseBoundedProperty
    , testBuildRmpForceProperty
    , testTemplateToMovesProperty
    , testResolverCuratedBeatsAuto
    , testResolverDangerousAmbiguityFallback
    , testResolverExactCaseMatch
    , testOld156LemmasResolveIdentically
    , testResolverRealDataCuratedBeatsAutoCoverage
    , testResolverRealDataAutoVerifiedBeatsAutoCoverage
    , testResolverRealDataCrossLemmaCaseMatch
     , testCandidateGenitiveFallbackRealData
    , testCandidateAccusativeFallbackRealData
    , testCandidatePrepositionalFallbackRealData
    , testParsePropositionSelfKnowledgeAboutSelf
    , testParsePropositionSelfKnowledgeAboutUserTypo
    , testParsePropositionWorldCauseSun
    , testParsePropositionWorldCauseSky
    , testParsePropositionLocationFormationThought
    , testParsePropositionLocationFormationTypo
    , testParsePropositionEverydayPurchaseStatement
    , testParsePropositionEverydayResidenceStatement
    , testParsePropositionAffectiveHelpQuestion
    , testParsePropositionComparisonPlausibilityTableChair
    , testParsePropositionMisunderstandingReport
    , testParsePropositionSelfKnowledgeConfidenceHigh
    , testParsePropositionSelfKnowledgeTargetsUser
    , testParsePropositionComparisonCapturesCandidates
    , testParsePropositionComparisonCapturesFromCandidates
    , testParsePropositionDialogueInvitationLogic
    , testParsePropositionConceptKnowledgeSun
    , testParsePropositionSelfStateQuestion
    , testParsePropositionGenerativePromptThought
    , testParsePropositionContemplativeTopicSilence
    , testParsePropositionConceptKnowledgeFreedomVariant
    , testParsePropositionSelfStateMindVariant
    , testParsePropositionGenerativePromptIdeaVariant
    , testParsePropositionGenerativePromptAnotherThoughtVariant
    , testParsePropositionGenerativePromptLogicalVariant
    , testParsePropositionContemplativeTopicHome
    , testParsePropositionReflectiveAssertionSubjectivityTopic
    , testParsePropositionSelfKnowledgeWhatYouAre
    , testParsePropositionSelfKnowledgeWhatYouAreVariant
    , testParsePropositionSelfKnowledgeNameQuestion
    , testParsePropositionSelfKnowledgeTellAboutSelfQuestion
    , testParsePropositionSelfKnowledgeCapabilityQuestion
    , testParsePropositionSelfKnowledgeHelpQuestion
    , testParsePropositionSelfKnowledgeUserIdentityQuestion
    , testParsePropositionKeywordFallbackOperationalCause
    , testParsePropositionConceptKnowledgeBeingSmartVariant
    , testParsePropositionConceptKnowledgeWhoIsGod
    , testParsePropositionConceptKnowledgeWhatIsSense
    , testParsePropositionRouteScoresAreTraced
    , testParsePropositionDialogueInvitationWithoutTopicFallsBackToDialogue
    , testParsePropositionEverydayStatementKeepsHighParserConfidence
    , testParsePropositionFarewellSignal
    , testParsePropositionGratitudeSignal
    , testParsePropositionApologySignal
    , testParsePropositionAgreementSignal
    , testParsePropositionDisagreementSignal
    , testParsePropositionOpinionQuestion
    , testParsePropositionHowYouWillNotSmallTalk
    , testParsePropositionHowYouWillMapsToSystemLogic
    , testParsePropositionPurposeDeicticSubjectNormalized
    , testParsePropositionConceptKnowledgeDeathSubject
    , testParsePropositionHowDistinguishMapsToDistinction
    , testPropositionToFamilySelfKnowledgeIsDescribe
    , testPropositionToFamilyDialogueInvitationIsDeepen
    , testPropositionToFamilyConceptKnowledgeIsDefine
    , testPropositionToFamilyWorldCauseIsGround
    , testPropositionToFamilyLocationFormationIsGround
    , testPropositionToFamilySelfStateIsDescribe
    , testPropositionToFamilyComparisonIsDistinguish
    , testPropositionToFamilyMisunderstandingIsRepair
    , testPropositionToFamilyGenerativePromptIsDescribe
    , testPropositionToFamilyContemplativeTopicIsDeepen
    ]

testCosineSimilarity :: Test
testCosineSimilarity = TestCase $ do
  let v1 = V.fromList [1.0, 0.0, 0.0]
      v2 = V.fromList [1.0, 0.0, 0.0]
      v3 = V.fromList [0.0, 1.0, 0.0]
      sim1 = Emb.cosineSimilarity v1 v2
      sim2 = Emb.cosineSimilarity v1 v3
  assertEqual "Identical vectors should have similarity 1.0" 1.0 sim1
  assertEqual "Orthogonal vectors should have similarity 0.0" 0.0 sim2

testTextToEmbedding :: Test
testTextToEmbedding = TestCase $ do
  emb1 <- Emb.textToEmbedding "test"
  emb2 <- Emb.textToEmbedding "test"
  emb3 <- Emb.textToEmbedding "different"
  assertEqual "Same text should produce same embedding" emb1 emb2
  assertBool "Different text should produce different embedding" (emb1 /= emb3)
  assertEqual "Embedding should have correct dimension" 384 (V.length emb1)

testEmbeddingSourceQuality :: Test
testEmbeddingSourceQuality = TestCase $ do
  assertEqual "Explicit local deterministic backend is heuristic"
    Emb.EmbeddingQualityHeuristic
    (Emb.embeddingSourceQuality Emb.EmbeddingLocalDeterministic)
  assertEqual "Implicit local backend is heuristic"
    Emb.EmbeddingQualityHeuristic
    (Emb.embeddingSourceQuality Emb.EmbeddingLocalImplicit)
  assertEqual "Remote backend is modeled"
    Emb.EmbeddingQualityModeled
    (Emb.embeddingSourceQuality Emb.EmbeddingRemote)

testTextToEmbeddingSourceExplicitLocalBackend :: Test
testTextToEmbeddingSourceExplicitLocalBackend = TestCase $
  withEnvVar "QXFX0_EMBEDDING_BACKEND" (Just "local-deterministic") $
    withEnvVar "EMBEDDING_API_URL" Nothing $ do
      result <- Emb.textToEmbeddingResult "test"
      assertEqual "Explicit local backend should be reflected in source" Emb.EmbeddingLocalDeterministic (Emb.erSource result)
      assertEqual "Explicit local backend should keep canonical dimension" 384 (V.length (Emb.erEmbedding result))

testTextToEmbeddingSourceWithoutEndpoint :: Test
testTextToEmbeddingSourceWithoutEndpoint = TestCase $
  withEnvVar "QXFX0_EMBEDDING_BACKEND" Nothing $
    withEnvVar "EMBEDDING_API_URL" Nothing $ do
      result <- Emb.textToEmbeddingResult "test"
      assertEqual "Missing explicit backend should stay on legacy implicit local mode" Emb.EmbeddingLocalImplicit (Emb.erSource result)
      assertEqual "Fallback embedding should keep canonical dimension" 384 (V.length (Emb.erEmbedding result))

testTextToEmbeddingSourceIgnoresUrlWithoutExplicitRemoteBackend :: Test
testTextToEmbeddingSourceIgnoresUrlWithoutExplicitRemoteBackend = TestCase $
  withEnvVar "QXFX0_EMBEDDING_BACKEND" Nothing $
    withEnvVar "EMBEDDING_API_URL" (Just "http://127.0.0.1:1/embeddings") $ do
      result <- Emb.textToEmbeddingResult "test"
      assertEqual "Remote URL alone must not switch runtime into remote embedding mode" Emb.EmbeddingLocalImplicit (Emb.erSource result)
      assertEqual "Implicit local fallback should keep canonical dimension" 384 (V.length (Emb.erEmbedding result))

testTextToEmbeddingSourceRemoteFailure :: Test
testTextToEmbeddingSourceRemoteFailure = TestCase $
  withEnvVar "QXFX0_EMBEDDING_BACKEND" (Just "remote-http") $
    withEnvVar "EMBEDDING_API_URL" (Just "http://127.0.0.1:1/embeddings") $ do
      result <- Emb.textToEmbeddingResult "test"
      assertEqual "Explicit remote backend should downgrade to local fallback when endpoint is unreachable" Emb.EmbeddingRemoteFailureLocalFallback (Emb.erSource result)
      assertEqual "Fallback embedding should keep canonical dimension" 384 (V.length (Emb.erEmbedding result))

testSafetyChecks :: Test
testSafetyChecks = TestCase $ do
  let ok1 = Guard.postRenderSafetyCheck (T.pack "Hello world") []
      ok2 = Guard.postRenderSafetyCheck (T.pack "Short") [T.pack "history"]
      ok3 = Guard.postRenderSafetyCheck (T.pack "Ответ — определение рамки: свобода.") []
      warning1 = Guard.postRenderSafetyCheck (T.pack "ты должен делать это") []
      warning2 = Guard.postRenderSafetyCheck (T.pack "this is a repeated response")
                     (replicate 5 (T.pack "this is a repeated response"))
      block1 = Guard.postRenderSafetyCheck (T.pack "") []
      block2 = Guard.postRenderSafetyCheck (T.pack "{topic}") []
  assertEqual "Normal text should pass" Guard.InvariantOK ok1
  assertEqual "Short normal text should pass" Guard.InvariantOK ok2
  assertEqual "Russian dialogue with dash should pass" Guard.InvariantOK ok3
  assertBool "Toxic patterns should be detected" (isWarning warning1)
  assertBool "Repeated text should be detected" (isWarning warning2)
  assertBool "Empty text should become hard block" (isBlock block1)
  assertBool "Metadata leak should become hard block" (isBlock block2)
  where
    isWarning (Guard.InvariantWarn _) = True
    isWarning _ = False
    isBlock (Guard.InvariantBlock _) = True
    isBlock _ = False

testSafetyToxicityUsesTokenBoundaries :: Test
testSafetyToxicityUsesTokenBoundaries = TestCase $ do
  let benign = Guard.postRenderSafetyCheck (T.pack "Я в бреду памяти ищу форму") []
      toxic = Guard.postRenderSafetyCheck (T.pack "Это бред и ты должен молчать") []
  assertEqual "Substring-only overlap must not trigger toxicity warning" Guard.InvariantOK benign
  case toxic of
    Guard.InvariantWarn _ -> pure ()
    other -> assertFailure ("expected token-aware toxicity warning, got: " <> show other)

testFinalizeOutputFallsBackToRecoverySurface :: Test
testFinalizeOutputFallsBackToRecoverySurface = TestCase $ do
  let preSafetySurface =
        Guard.GuardSurface
          { Guard.gsRenderedText = "{topic}"
          , Guard.gsSegments = [Guard.RenderSegment Guard.SegmentIdentityClaim "{topic}"]
          , Guard.gsQuestionLike = False
          }
      (renderedSurface, surfaceProv) = TurnLegitimacy.finalizeOutput preSafetySurface []
  assertEqual "blocked surface should switch provenance to recovery" FromRecovery surfaceProv
  assertBool "recovery surface should use recovery text" ("Извини" `T.isInfixOf` Guard.gsRenderedText renderedSurface)
  assertEqual "recovery surface should become question-like" True (Guard.gsQuestionLike renderedSurface)

testSafeOutputTextUsesBlockedFallback :: Test
testSafeOutputTextUsesBlockedFallback = TestCase $ do
  let okSurface =
        Guard.GuardSurface
          { Guard.gsRenderedText = "unsafe introspection"
          , Guard.gsSegments = []
          , Guard.gsQuestionLike = False
          }
      blockedSurface =
        Guard.GuardSurface
          { Guard.gsRenderedText = "base output"
          , Guard.gsSegments = []
          , Guard.gsQuestionLike = False
          }
  assertEqual "blocked safety should use fallback surface text"
    "base output"
    (TurnLegitimacy.safeOutputText okSurface blockedSurface (Guard.InvariantBlock "blocked"))
  assertEqual "ok safety should preserve rendered output"
    "unsafe introspection"
    (TurnLegitimacy.safeOutputText okSurface blockedSurface Guard.InvariantOK)

testFamilyMappings :: Test
testFamilyMappings = TestCase $ do
  assertEqual "CMGround should map to MoveGroundKnown"
    (MoveGroundKnown :: ContentMove) (familyToOpeningMove CMGround)
  assertEqual "CMDefine should map to MoveDefineFrame"
    (MoveDefineFrame :: ContentMove) (familyToOpeningMove CMDefine)
  assertEqual "CMGround should map to MoveGroundBasis"
    (MoveGroundBasis :: ContentMove) (familyToCoreMove CMGround)
  assertEqual "CMDefine should map to MoveStateDefinition"
    (MoveStateDefinition :: ContentMove) (familyToCoreMove CMDefine)

testExhaustionAtoms :: Test
testExhaustionAtoms = TestCase $ do
  let input = "Я очень сильно устал от этой работы"
      atoms = collectAtoms input []
  assertBool "Should detect Exhaustion tag" $
    any (\a -> case maTag a of Exhaustion _ -> True; _ -> False) (asAtoms atoms)
  assertBool "Load should be > 0.5" $ asLoad atoms > 0.5

testContactAtoms :: Test
testContactAtoms = TestCase $ do
  let input = "Ты меня слышишь? Нужен контакт."
      atoms = collectAtoms input []
  assertBool "Should detect NeedContact tag" $
    any (\a -> case maTag a of NeedContact _ -> True; _ -> False) (asAtoms atoms)

testMeaningAtomsTokenBoundaryAvoidsFalseContact :: Test
testMeaningAtomsTokenBoundaryAvoidsFalseContact = TestCase $ do
  let atoms = collectAtoms "Контактный клей высох" []
  assertEqual "substring inside larger token must not trigger contact register" Neutral (asRegister atoms)
  assertBool "substring inside larger token must not create NeedContact atom" $
    not (any (\a -> case maTag a of NeedContact _ -> True; _ -> False) (asAtoms atoms))

testSessionLockSerializes :: Test
testSessionLockSerializes = TestCase $ do
  mgr <- newSessionLockManager
  concurrentCount <- newIORef (0 :: Int)
  maxConcurrent <- newIORef (0 :: Int)
  let sessionId = "lock-test-session"
      simulateTurn label = withSessionLock mgr sessionId $ do
        cur <- atomicModifyIORef' concurrentCount (\c -> (c + 1, c + 1))
        atomicModifyIORef' maxConcurrent (\m -> (max m cur, ()))
        threadDelay 50000
        _ <- atomicModifyIORef' concurrentCount (\c -> (c - 1, c - 1))
        pure (label :: String)
  _results <- mapConcurrently simulateTurn ["A", "B"]
  maxC <- readIORef maxConcurrent
  assertBool ("Max concurrent turns should be 1 with lock, got: " ++ show maxC)
    (maxC == 1)

testSessionLockSerializesUnderBurst :: Test
testSessionLockSerializesUnderBurst = TestCase $ do
  mgr <- newSessionLockManager
  concurrentCount <- newIORef (0 :: Int)
  maxConcurrent <- newIORef (0 :: Int)
  let sessionId = "lock-test-session-burst"
      simulateTurn :: Int -> IO Int
      simulateTurn n = withSessionLock mgr sessionId $ do
        cur <- atomicModifyIORef' concurrentCount (\c -> (c + 1, c + 1))
        atomicModifyIORef' maxConcurrent (\m -> (max m cur, ()))
        threadDelay 5000
        _ <- atomicModifyIORef' concurrentCount (\c -> (c - 1, c - 1))
        pure n
  forM_ [1 :: Int .. 15] $ \_ -> do
    _ <- mapConcurrently simulateTurn [1 .. 10]
    pure ()
  maxC <- readIORef maxConcurrent
  assertBool ("Max concurrent burst turns should be 1 with lock, got: " ++ show maxC)
    (maxC == 1)

testSessionLockOverflowStatsExposeBoundedDegradation :: Test
testSessionLockOverflowStatsExposeBoundedDegradation = TestCase $ do
  mgr <- newSessionLockManager
  stats0 <- sessionLockStats mgr
  let maxTracked = slsMaxTrackedLocks stats0
  forM_ [1 .. maxTracked + 8] $ \n -> do
    let sid = "overflow-session-" <> T.pack (show (n :: Int))
    _ <- withSessionLock mgr sid (pure ())
    pure ()
  stats1 <- sessionLockStats mgr
  assertEqual "tracked lock count should be capped at configured limit"
    maxTracked
    (slsTrackedLocks stats1)
  assertBool "overflow mode should become active once tracked lock cap is reached"
    (slsOverflowActive stats1)

testSessionLockConfigurableCap :: Test
testSessionLockConfigurableCap = TestCase $ do
  withEnvVar "QXFX0_MAX_SESSION_LOCKS" (Just "4") $ do
    mgr <- newSessionLockManager
    stats0 <- sessionLockStats mgr
    assertEqual "cap should read from env" 4 (slsMaxTrackedLocks stats0)
    forM_ [1 .. 6] $ \n -> do
      let sid = "cap-session-" <> T.pack (show (n :: Int))
      _ <- withSessionLock mgr sid (pure ())
      pure ()
    stats1 <- sessionLockStats mgr
    assertEqual "tracked should be capped at 4" 4 (slsTrackedLocks stats1)
    assertBool "overflow should be active at 4" (slsOverflowActive stats1)

testSemanticLogicExhaustion :: Test
testSemanticLogicExhaustion = TestCase $ do
  let input = "Я очень сильно устал от этой работы"
      atoms = collectAtoms input []
      logicResults = runSemanticLogic atoms
  assertBool "Exhaustion input should route to CMRepair" $
    any (\(fam, w) -> fam == CMRepair && w > 0.5) logicResults

testSemanticLogicNegatedExhaustionDoesNotRepair :: Test
testSemanticLogicNegatedExhaustionDoesNotRepair = TestCase $ do
  let input = "Я не устал, я просто уточняю вывод"
      clusters =
        [ ClusterDef
            { cdName = "exhaustion"
            , cdKeywords = ["устал"]
            , cdPriority = 1.0
            }
        ]
      atoms = collectAtoms input clusters
      logicResults = runSemanticLogic atoms
  assertBool "Negated exhaustion should not create CMRepair pressure" $
    not (any (\(fam, _) -> fam == CMRepair) logicResults)
  assertBool "Negated exhaustion should not leave Exhaust register through clusters" $
    asRegister atoms /= Exhaust

testSemanticLogicContact :: Test
testSemanticLogicContact = TestCase $ do
  let input = "Ты меня слышишь? Нужен контакт."
      atoms = collectAtoms input []
      logicResults = runSemanticLogic atoms
  assertBool "Contact input should route to CMContact" $
    any (\(fam, w) -> fam == CMContact && w > 0.5) logicResults

testSemanticLogicDefault :: Test
testSemanticLogicDefault = TestCase $ do
  let input = "Расскажи что-нибудь"
      atoms = collectAtoms input []
      logicResults = runSemanticLogic atoms
  assertBool "Default input should produce at least one family" $
    not (null logicResults)

testParsePropositionDefinitionalQuestion :: Test
testParsePropositionDefinitionalQuestion = TestCase $ do
  let frame = Proposition.parseProposition "Что такое свобода?"
  assertEqual "definitional question should map to CMDefine" CMDefine (ipfCanonicalFamily frame)
  assertEqual "definitional question should remain interrogative" Interrogative (ipfClauseForm frame)
  assertBool "focus entity should not be empty" (not (T.null (ipfFocusEntity frame)))

testParsePropositionLogicalFocusAvoidsConnectives :: Test
testParsePropositionLogicalFocusAvoidsConnectives = TestCase $ do
  let frame = Proposition.parseProposition "Если утверждение A влечёт B, а B влечёт C, можно ли вывести, что A влечёт C?"
      focus = T.toLower (ipfFocusEntity frame)
  assertBool "logical connective should not become focus" (focus `notElem` ["если", "можно", "вывести"])

testParsePropositionSocratesFocusPrefersRepeatedEntity :: Test
testParsePropositionSocratesFocusPrefersRepeatedEntity = TestCase $ do
  let frame = Proposition.parseProposition "Все люди смертны. Сократ человек. Следовательно, Сократ смертен."
  assertEqual "repeated named entity should beat quantifier/opener terms" "сократ" (T.toLower (ipfFocusEntity frame))

testParsePropositionContrastFocusUsesPositiveSide :: Test
testParsePropositionContrastFocusUsesPositiveSide = TestCase $ do
  let frame = Proposition.parseProposition "Это не доказательство, а объяснение"
  assertEqual "contrastive не X, а Y should focus positive side" "объяснение" (ipfFocusEntity frame)

testParsePropositionAffectiveContact :: Test
testParsePropositionAffectiveContact = TestCase $ do
  let frame = Proposition.parseProposition "Я чувствую страх и тоску"
  assertEqual "affective input should map to CMContact" CMContact (ipfCanonicalFamily frame)
  assertEqual "emotion detector should mark distress" "distress" (emotionalToneText (ipfEmotionalTone frame))
  assertBool "affective confidence should be above plain assert baseline" (ipfConfidence frame > 0.5)

testParsePropositionTokenBoundaryAvoidsFalseAnchor :: Test
testParsePropositionTokenBoundaryAvoidsFalseAnchor = TestCase $ do
  let frame = Proposition.parseProposition "Безусловность свободы важна"
  assertEqual "longer words should not trigger anchor keywords by substring" CMGround (ipfCanonicalFamily frame)
  assertEqual "token-boundary miss should keep neutral tone" ToneNeutral (ipfEmotionalTone frame)

testParsePropositionInsuranceRemainsNeutral :: Test
testParsePropositionInsuranceRemainsNeutral = TestCase $ do
  let frame = Proposition.parseProposition "Страхование жизни полезно"
  assertEqual "страхование should not be parsed as distress/contact" CMGround (ipfCanonicalFamily frame)
  assertEqual "страхование should not trip distress tone" ToneNeutral (ipfEmotionalTone frame)

testParsePropositionOperationalStatusQuestion :: Test
testParsePropositionOperationalStatusQuestion = TestCase $ do
  let frame = Proposition.parseProposition "Ты не работаешь?"
  assertEqual "operational status question should map to clarifying diagnostic family" CMClarify (ipfCanonicalFamily frame)
  assertEqual "operational status question should normalize focus away from verb surface" "работа" (ipfFocusEntity frame)
  assertBool "operational status question should be parsed with high confidence" (ipfConfidence frame >= 0.72)

testParsePropositionSystemLogicQuestion :: Test
testParsePropositionSystemLogicQuestion = TestCase $ do
  let frame = Proposition.parseProposition "В чём твоя логика?"
  assertEqual "system-logic question should map to self-description family" CMDescribe (ipfCanonicalFamily frame)
  assertEqual "system-logic question should preserve logic as focus" "логика" (ipfFocusEntity frame)
  assertBool "system-logic question should be parsed with high confidence" (ipfConfidence frame >= 0.72)

testGfCombinatorics :: Test
testGfCombinatorics = TestCase $ do
  let ast1 = MoveInvite (MkNP "logika_N") ModFirst (ActMaintain NumSg "ramka_N")
      morph = Morph.buildMorphologyData []
      res1 = Dialogue.linearizeClaimAstRus ast1 StyleStandard morph
  assertEqual "AST linearization is stable"
              (Just "Да, поговорим о логике. Я сначала удержу рамку, чтобы не потерять фокус.")
              res1

  let ast2 = MoveInvite (MkNP "logika_N") ModStrictly (ActMaintain NumSg "ramka_N")
      res2 = Dialogue.linearizeClaimAstRus ast2 StyleStandard morph
  assertEqual "AST modifier changes correctly"
              (Just "Да, поговорим о логике. Я строго удержу рамку, чтобы не потерять фокус.")
              res2

testGfTopicMapResolvesAllForms :: Test
testGfTopicMapResolvesAllForms = TestCase $ do
  assertEqual "prepositional noun form should resolve to generated GF id"
    "logika_N"
    (GfMap.topicToGfLexemeId "о логике")
  assertEqual "genitive noun form should resolve to generated GF id"
    "logika_N"
    (GfMap.topicToGfLexemeId "логики")

testGfTopicMapProvidesForms :: Test
testGfTopicMapProvidesForms = TestCase $
  case GfMap.lookupGfLexemeForms "logika_N" of
    Just forms -> do
      assertEqual "logika nominative from generated lexicon" "логика" (GfMap.glfNom forms)
      assertEqual "logika genitive from generated lexicon" "логики" (GfMap.glfGen forms)
      assertEqual "logika prepositional from generated lexicon" "логике" (GfMap.glfPrep forms)
      assertEqual "logika accusative from generated lexicon map" "логику" (GfMap.glfAcc forms)
      assertEqual "logika instrumental from generated lexicon map" "логикой" (GfMap.glfIns forms)
    Nothing ->
      assertFailure "expected forms for logika_N in generated GF map"

testClaimAstCoverageForOperationalAndMetaPrompts :: Test
testClaimAstCoverageForOperationalAndMetaPrompts = TestCase $ do
  let probes =
        [ ("Ты не работаешь?", "OperationalStatusQ")
        , ("Почему ты не работаешь?", "OperationalCauseQ")
        , ("В чём твоя логика?", "SystemLogicQ")
        , ("Я не понимаю тебя", "MisunderstandingReport")
        , ("Скажи интересную мысль", "ReflectiveQ")
        , ("Тишина", "ContemplativeTopic")
        ]
  forM_ probes $ \(inputText, expectedType) -> do
    let frame = parseProposition inputText
        family = ipfCanonicalFamily frame
        rmp = TurnPlanning.buildRMP family frame (ipfFocusEntity frame) emptyEgoState emptyAtomTrace True
    assertEqual ("proposition type mismatch for " <> T.unpack inputText) expectedType (ipfPropositionType frame)
    assertBool ("expected ClaimAst coverage for " <> T.unpack inputText) (rmpPrimaryClaimAst rmp /= Nothing)

testGfRoundTripParseSmoke :: Test
testGfRoundTripParseSmoke = TestCase $ do
  mGf <- findExecutable "gf"
  case mGf of
    Nothing -> pure ()
    Just _ -> do
      (_, _, compileErr) <- readProcessWithExitCode "bash" ["scripts/compile_gf_grammar.sh"] ""
      pgfExists <- doesFileExist "spec/gf/QxFx0Syntax.pgf"
      if not pgfExists
        then assertFailure ("expected compiled PGF for round-trip test, compile stderr: " <> compileErr)
        else do
          let sample = "Да, поговорим о логике. Я сначала удержу рамку, чтобы не потерять фокус."
              parseCmd = "p -lang=QxFx0SyntaxRus -cat=Move \"" <> sample <> "\"\nq\n"
          (parseExit, parseOut, parseErr) <- readProcessWithExitCode "gf" ["spec/gf/QxFx0Syntax.pgf"] parseCmd
          case parseExit of
            ExitSuccess ->
              assertBool "GF parse output should contain MoveInvite tree"
                ("MoveInvite" `T.isInfixOf` T.pack parseOut)
            ExitFailure _ ->
              assertFailure ("GF parse failed: " <> parseErr)

testGfRoundTripAstLinearizeParse :: Test
testGfRoundTripAstLinearizeParse = TestCase $ do
  mGf <- findExecutable "gf"
  case mGf of
    Nothing -> pure ()
    Just _ -> do
      _ <- readProcessWithExitCode "bash" ["scripts/compile_gf_grammar.sh"] ""
      let pgfPath = "spec/gf/QxFx0Syntax.pgf"
      pgfExists <- doesFileExist pgfPath
      if not pgfExists
        then assertFailure "expected compiled PGF for AST round-trip test"
        else do
          let ast = MoveInvite (MkNP "logika_N") ModFirst (ActMaintain NumSg "ramka_N")
              expectedExpr = "MoveInvite (MkNP logika_N) ModFirst (ActMaintain NumSg ramka_N)"
          assertEqual "astToGfExpr should emit canonical expression"
            (Right expectedExpr)
            (RuntimePGF.astToGfExpr ast)
          linearized <- RuntimePGF.linearizeClaimAstGf (Just pgfPath) ast
          case linearized of
            Left err ->
              assertFailure ("GF runtime linearization failed: " <> T.unpack err)
            Right rendered -> do
              let parseCmd = "p -lang=QxFx0SyntaxRus -cat=Move \"" <> T.unpack rendered <> "\"\nq\n"
              (parseExit, parseOut, parseErr) <- readProcessWithExitCode "gf" [pgfPath] parseCmd
              case parseExit of
                ExitSuccess ->
                  assertBool "parsed AST should contain source constructor tree"
                    (expectedExpr `T.isInfixOf` T.pack parseOut)
                ExitFailure _ ->
                  assertFailure ("GF parse failed on linearized output: " <> parseErr)

testGfFallbackSurfaceParity :: Test
testGfFallbackSurfaceParity = TestCase $ do
  mGf <- findExecutable "gf"
  case mGf of
    Nothing -> pure ()
    Just _ -> do
      _ <- readProcessWithExitCode "bash" ["scripts/compile_gf_grammar.sh"] ""
      let pgfPath = "spec/gf/QxFx0Syntax.pgf"
      pgfExists <- doesFileExist pgfPath
      if not pgfExists
        then assertFailure "expected compiled PGF for GF/fallback parity test"
        else do
          let morph = Morph.buildMorphologyData []
              samples =
                [ MoveInvite (MkNP "logika_N") ModFirst (ActMaintain NumSg "ramka_N")
                , MoveGround (MkNP "smysl_N")
                , MoveContact (MkNP "logika_N")
                , MoveDeepen (MkNP "logika_N")
                ]
          forM_ samples $ \ast -> do
            let fallbackRendered = Dialogue.linearizeClaimAstRus ast StyleStandard morph
            runtimeRendered <- RuntimePGF.linearizeClaimAstGf (Just pgfPath) ast
            case (fallbackRendered, runtimeRendered) of
              (Nothing, _) ->
                assertFailure ("fallback linearization returned Nothing for AST: " <> show ast)
              (_, Left err) ->
                assertFailure ("GF runtime linearization failed: " <> T.unpack err)
              (Just fb, Right pgf) ->
                assertEqual ("GF/fallback mismatch for AST: " <> show ast) fb pgf

testAstToGfExprLegacyCompatibility :: Test
testAstToGfExprLegacyCompatibility = TestCase $ do
  let purposeId = GfMap.topicToGfLexemeId "логика"
      leftId = GfMap.topicToGfLexemeId "стол"
      rightId = GfMap.topicToGfLexemeId "стул"
      expectedPurpose = "MovePurpose (MkNP " <> purposeId <> ")"
      expectedComparison = "MoveCompare (MkNP " <> leftId <> ") (MkNP " <> rightId <> ")"
  let purposeExpr = RuntimePGF.astToGfExpr (ClaimPurpose "логика")
      comparisonExpr = RuntimePGF.astToGfExpr (ClaimComparison "стол" "стул")
  assertEqual "legacy ClaimPurpose should map to MovePurpose"
    (Right expectedPurpose)
    purposeExpr
  assertEqual "legacy ClaimComparison should map to MoveCompare"
    (Right expectedComparison)
    comparisonExpr

testInferUserStateWhyUsesContentSearch :: Test
testInferUserStateWhyUsesContentSearch = TestCase $ do
  let userState = inferUserState [] "почему ты не работаешь?"
  assertEqual "why-questions should stay in content layer instead of forcing meta reflect mode" ContentLayer (usNeedLayer userState)
  assertEqual "why-questions should still mark search register" Search (usDominantRegister userState)

testEgoUpdateSetsMissionAndAgency :: Test
testEgoUpdateSetsMissionAndAgency = TestCase $ do
  let ego0 = emptyEgoState { egoAgency = 0.4, egoTension = 0.2 }
      ego1 = Ego.updateEgoFromTurn ego0 CMContact 0.1
  assertEqual "contact move should set contact mission" "Установить контакт" (egoMission ego1)
  assertBool "contact move should not reduce agency from baseline" (egoAgency ego1 >= egoAgency ego0)
  assertBool "tension should remain clamped to unit interval" (egoTension ego1 >= 0.0 && egoTension ego1 <= 1.0)

testLegitimacyPenaltyDemotesLowConfidencePlan :: Test
testLegitimacyPenaltyDemotesLowConfidencePlan = TestCase $ do
  let rmp0 = ResponseMeaningPlan
        { rmpFamily = CMGround, rmpForce = IFAssert
        , rmpSpeechAct = Assert, rmpRelation = SRGround
        , rmpStrategy = DirectThenGround, rmpStance = Firm
        , rmpEpistemic = Known 0.9, rmpTopic = "тема"
        , rmpPrimaryClaim = "тезис", rmpPrimaryClaimAst = Nothing, rmpContrastAxis = ""
        , rmpImplicationDirection = "forward", rmpProvenance = BuiltClaim
        , rmpCommitmentStrength = 0.9, rmpDepthMode = DeepDepth
        }
      (score1, rmp1) = Legitimacy.applyLegitimacyPenalty 0.4 rmp0
  assertEqual "low legitimacy should preserve returned score" 0.4 score1
  assertEqual "low legitimacy should demote family to repair" CMRepair (rmpFamily rmp1)
  assertEqual "low legitimacy should demote stance to honest" Honest (rmpStance rmp1)

testLegitimacyRecoveryBonusRewardsShadowAndStability :: Test
testLegitimacyRecoveryBonusRewardsShadowAndStability = TestCase $ do
  assertEqual "no confirmation signals should yield no recovery bonus"
    0.0
    (Legitimacy.legitimacyRecoveryBonus False False)
  assertEqual "confirmed shadow should add recovery bonus"
    0.04
    (Legitimacy.legitimacyRecoveryBonus True False)
  assertEqual "confirmed shadow plus stable route should stack bonuses"
    0.07
    (Legitimacy.legitimacyRecoveryBonus True True)

testClassifyLegitimacyOutcomeNeverWarrantedDeny :: Test
testClassifyLegitimacyOutcomeNeverWarrantedDeny = TestCase $ do
  let outcome =
        classifyLegitimacyOutcome
          Thr.LegitimacyPass
          ReasonOk
          NeverWarranted
          ShadowMatch
          ShadowSeverityClean
  assertEqual "never warranted should force deny disposition" DispositionDeny (loDisposition outcome)

testClassifyLegitimacyOutcomeShadowDivergedRepair :: Test
testClassifyLegitimacyOutcomeShadowDivergedRepair = TestCase $ do
  let outcome =
        classifyLegitimacyOutcome
          Thr.LegitimacyPass
          ReasonShadowDivergence
          ConditionallyWarranted
          ShadowDiverged
          ShadowSeverityContract
  assertEqual "shadow divergence should route to repair disposition" DispositionRepair (loDisposition outcome)

testClassifyLegitimacyOutcomeAdvisoryShadowPermits :: Test
testClassifyLegitimacyOutcomeAdvisoryShadowPermits = TestCase $ do
  let outcome =
        classifyLegitimacyOutcome
          Thr.LegitimacyPass
          ReasonOk
          ConditionallyWarranted
          ShadowDiverged
          ShadowSeverityAdvisory
  assertEqual "advisory shadow divergence should not force repair disposition" DispositionPermit (loDisposition outcome)

testClassifyLegitimacyOutcomeLowConfidenceAdvisory :: Test
testClassifyLegitimacyOutcomeLowConfidenceAdvisory = TestCase $ do
  let outcome =
        classifyLegitimacyOutcome
          Thr.LegitimacyDegraded
          ReasonLowParserConfidence
          AlwaysWarranted
          ShadowMatch
          ShadowSeverityClean
  assertEqual "low parser confidence should produce advisory disposition" DispositionAdvisory (loDisposition outcome)

testIntegrateIdentityClaimsDeduplicatesAndRanks :: Test
testIntegrateIdentityClaimsDeduplicatesAndRanks = TestCase $ do
  let claims =
        [ IdentityClaimRef "freedom" "Свобода держит форму разговора." 0.9 "curated" "freedom"
        , IdentityClaimRef "freedom" "Свобода держит форму разговора." 0.7 "curated" "freedom"
        , IdentityClaimRef "contact" "Контакт нужен, когда вопрос рвётся." 0.8 "curated" "support"
        , IdentityClaimRef "noise" "Случайный след." 0.2 "curated" "other"
        ]
      integrated = TurnPlanning.integrateIdentityClaims claims CMGround "freedom"
  assertEqual "integrated claims should deduplicate same concept/topic pair" 2 (length integrated)
  assertEqual "best-ranked matching claim should stay first" "freedom" (icrConcept (head integrated))
  assertBool "low-confidence claim should be filtered out" (all ((>= 0.3) . icrConfidence) integrated)

testMeaningGraphPredictsSuccessfulStrategy :: Test
testMeaningGraphPredictsSuccessfulStrategy = TestCase $ do
  let fromState = MeaningState ResonanceMed PressNone DepthShallow
      toState = MeaningState ResonanceHigh PressLight DepthPattern
      strat = ResponseStrategy ModerateResp OpenStance ValidateMove DensityMed
      graph = MeaningGraph.recordTransition fromState toState strat True MeaningGraph.emptyMeaningGraph
  assertEqual "successful transition should be reusable as predicted strategy"
    (Just strat)
    (MeaningGraph.predictStrategy fromState toState graph)

testMeaningGraphDreamBiasCanPromoteBorderlineStrategy :: Test
testMeaningGraphDreamBiasCanPromoteBorderlineStrategy = TestCase $ do
  now <- getCurrentTime
  let fromState = MeaningState ResonanceMed PressNone DepthShallow
      toState = MeaningState ResonanceHigh PressLight DepthPattern
      strat = ResponseStrategy ModerateResp OpenStance ValidateMove DensityMed
      graph0 = MeaningGraph.recordTransition fromState toState strat True MeaningGraph.emptyMeaningGraph
      graph1 = MeaningGraph.recordTransition fromState toState strat False graph0
      edge0 = head (mgEdges graph1)
      (graph2, _) = MeaningGraph.rewireMeaningGraphForDreamCycle now [(edge0, 0.1)] graph1
  assertEqual "borderline success plus positive dream bias should become routable"
    (Just strat)
    (MeaningGraph.predictStrategy fromState toState graph2)

testMeaningGraphRewireClampsBias :: Test
testMeaningGraphRewireClampsBias = TestCase $ do
  now <- getCurrentTime
  let fromState = MeaningState ResonanceMed PressNone DepthShallow
      toState = MeaningState ResonanceHigh PressLight DepthPattern
      strat = ResponseStrategy ModerateResp OpenStance ValidateMove DensityMed
      graph0 = MeaningGraph.recordTransition fromState toState strat True MeaningGraph.emptyMeaningGraph
      edge0 = head (mgEdges graph0)
      (graph1, events) = MeaningGraph.rewireMeaningGraphForDreamCycle now [(edge0, 0.4)] graph0
      rewired = head (mgEdges graph1)
  assertEqual "dream rewiring should clamp bias at symmetric limit" 0.25 (meDreamBias rewired)
  assertEqual "rewired edge should remember timestamp" (Just now) (meLastRewiredAt rewired)
  assertBool "rewiring should emit at least one event when bias changes" (not (null events))
testDreamBiasAttractorRejectsLowQualityEvidence :: Test
testDreamBiasAttractorRejectsLowQualityEvidence = TestCase $ do
  let acceptedBias = Dream.CoreVec 0.02 0.00 0.01 0.03 0.01
      rejectedBias = Dream.CoreVec 1.00 1.00 1.00 1.00 1.00
      evidence =
        [ Dream.DreamThemeEvidence "accepted" acceptedBias 1.0 0.90 True
        , Dream.DreamThemeEvidence "rejected_low_quality" rejectedBias 1.0 0.20 True
        , Dream.DreamThemeEvidence "rejected_biography" rejectedBias 1.0 0.90 False
        ]
      attractor = Dream.computeBiasAttractor Dream.defaultDreamConfig evidence
  assertBool
    "attractor should ignore rejected evidence and preserve accepted bias"
    (Dream.vecNorm (Dream.vecSub attractor acceptedBias) < 1e-12)

testDreamCycleAdvancesState :: Test
testDreamCycleAdvancesState = TestCase $ do
  now <- getCurrentTime
  let state0 = Dream.initialDreamState now (Dream.CoreVec 0.0 0.0 0.0 0.0 0.0)
      evidence = [Dream.DreamThemeEvidence "accepted" (Dream.CoreVec 0.02 0.01 0.0 0.01 0.0) 1.0 0.9 True]
      nextTs = addUTCTime 3600 now
      (state1, log1) = Dream.runDreamCycle Dream.defaultDreamConfig evidence nextTs 3600 state0
  assertEqual "dream cycle should increment counter" 1 (Dream.dsDreamCycleCount state1)
  assertEqual "dream cycle should stamp provided timestamp" nextTs (Dream.dsLastDreamTime state1)
  assertEqual "dream cycle log should report one hour delta" 1.0 (Dream.dclHours log1)
  assertBool "accepted evidence should produce non-zero attractor" (Dream.vecNorm (Dream.dsBiasAttractor state1) > 0.0)

testDreamCatchupSplitsElapsedTime :: Test
testDreamCatchupSplitsElapsedTime = TestCase $ do
  now <- getCurrentTime
  let state0 = Dream.initialDreamState now (Dream.CoreVec 0.0 0.0 0.0 0.0 0.0)
      later = addUTCTime (8 * 3600) now
      (state1, logs) = Dream.runDreamCatchup Dream.defaultDreamConfig [] later state0
  assertEqual "8 elapsed hours should produce 8 catchup cycles with default config" 8 (length logs)
  assertEqual "catchup should advance cycle counter consistently" 8 (Dream.dsDreamCycleCount state1)
  assertEqual "catchup should update last dream timestamp to latest cycle point" later (Dream.dsLastDreamTime state1)

testBackgroundSurfacingOnConflict :: Test
testBackgroundSurfacingOnConflict = TestCase $ do
  let baseState = Background.initialBackground { Background.bsTurnCount = 10, Background.bsLastSurfaced = 0 }
      pressured =
        Background.recordDesireConflict
          (Background.recordDesireConflict
            (Background.recordDesireConflict baseState "контакт vs уход")
            "контакт vs уход")
          "контакт vs уход"
  case Background.checkSurfacing pressured of
    Nothing -> assertFailure "conflict pressure should surface after threshold is crossed"
    Just ev -> do
      assertEqual "surfacing should come from desire conflict channel" Background.DesireConflict (Background.seChannel ev)
      assertBool "surfacing pressure should exceed configured threshold" (Background.sePressure ev >= Background.surfacingThreshold)

testIntuitionCheckResetsAfterFlash :: Test
testIntuitionCheckResetsAfterFlash = TestCase $ do
  let state0 = Intuition.defaultIntuitiveState { Intuition.isPosterior = 0.90 }
      (mFlash, state1) = Intuition.checkIntuition 0.90 0.80 7 state0
  case mFlash of
    Nothing -> assertFailure "high posterior input should produce an intuitive flash"
    Just flash -> do
      assertBool "flash strength should be positive" (Intuition.ifStrength flash > 0.0)
      assertBool "posterior should preserve long-term signal after flash"
        (Intuition.isPosterior state1 > Intuition.basePrior)
      assertEqual "cooldown should be applied after flash" 2 (Intuition.isCooldown state1)
      assertEqual "flash turn should be recorded" 7 (Intuition.isLastTurn state1)

testIntuitionFlashLikelihoodBands :: Test
testIntuitionFlashLikelihoodBands = TestCase $ do
  assertEqual
    "high resonance + high tension should use convergent flash likelihood"
    Thr.intuitionFlashLikelihoodConvergent
    (Intuition.likelihoodGivenFlash 0.90 0.90)
  assertEqual
    "elevated resonance should use elevated flash likelihood"
    Thr.intuitionFlashLikelihoodElevated
    (Intuition.likelihoodGivenFlash 0.71 0.20)
  assertEqual
    "deep resonance should use deep flash likelihood"
    Thr.intuitionFlashLikelihoodDeep
    (Intuition.likelihoodGivenFlash 0.56 0.20)
  assertEqual
    "low resonance and tension should use flash baseline"
    Thr.intuitionFlashLikelihoodBaseline
    (Intuition.likelihoodGivenFlash 0.10 0.10)

testIntuitionNoFlashLikelihoodBands :: Test
testIntuitionNoFlashLikelihoodBands = TestCase $ do
  assertEqual
    "high resonance + high tension should use convergent no-flash likelihood"
    Thr.intuitionNoFlashLikelihoodConvergent
    (Intuition.likelihoodGivenNoFlash 0.90 0.90)
  assertEqual
    "elevated resonance should use elevated no-flash likelihood"
    Thr.intuitionNoFlashLikelihoodElevated
    (Intuition.likelihoodGivenNoFlash 0.71 0.20)
  assertEqual
    "deep resonance should use deep no-flash likelihood"
    Thr.intuitionNoFlashLikelihoodDeep
    (Intuition.likelihoodGivenNoFlash 0.56 0.20)
  assertEqual
    "low resonance and tension should use no-flash baseline"
    Thr.intuitionNoFlashBaselineLikelihood
    (Intuition.likelihoodGivenNoFlash 0.10 0.10)

testPosteriorAfterFlashUsesDecayFactor :: Test
testPosteriorAfterFlashUsesDecayFactor = TestCase $ do
  assertEqual
    "posterior after flash should apply configured decay factor"
    (max Intuition.basePrior (0.8 * Thr.intuitionPosteriorAfterFlashDecayFactor))
    (Intuition.posteriorAfterFlash 0.8)
  assertEqual
    "long posterior after flash should apply configured decay factor"
    (max Intuition.basePrior (0.8 * Thr.intuitionLongPosteriorAfterFlashDecayFactor))
    (Intuition.longPosteriorAfterFlash 0.8)

testUpdateLongPosteriorUsesEmaWeights :: Test
testUpdateLongPosteriorUsesEmaWeights = TestCase $ do
  let resonance = 0.9
      tension = 0.8
      prior = 0.4
      expected =
        Thr.clamp01
          ( prior * Thr.intuitionLongPosteriorPriorWeight
            + Intuition.updatePosterior resonance tension prior * Thr.intuitionLongPosteriorCurrentWeight
          )
      actual = Intuition.updateLongPosterior resonance tension prior
  assertBool
    "updateLongPosterior should match configured EMA weights"
    (abs (actual - expected) < 1e-12)

testEffectivePosteriorBlendsShortAndLong :: Test
testEffectivePosteriorBlendsShortAndLong = TestCase $ do
  let state0 =
        Intuition.defaultIntuitiveState
          { Intuition.isPosterior = 0.2
          , Intuition.isLongPosterior = 0.8
          }
      result = Intuition.effectivePosterior state0
  assertBool
    "effective posterior should blend short and long trajectories"
    (abs (result - 0.59) < 1e-9)

testEffectivePosteriorPreservesHigherShortSignal :: Test
testEffectivePosteriorPreservesHigherShortSignal = TestCase $ do
  let state0 =
        Intuition.defaultIntuitiveState
          { Intuition.isPosterior = 0.9
          , Intuition.isLongPosterior = 0.1
          }
      result = Intuition.effectivePosterior state0
  assertBool
    "effective posterior should not undercut immediate posterior when it is stronger"
    (abs (result - 0.9) < 1e-9)

testConsciousnessInterpretationTracksHighAffinitySkill :: Test
testConsciousnessInterpretationTracksHighAffinitySkill = TestCase $ do
  let kernelOutput = Consciousness.KernelOutput
        { Consciousness.koActiveDesires = ["Присутствовать", "Понимать глубже"]
        , Consciousness.koSelectedSkill = "Слушать подтекст"
        , Consciousness.koSearchResult = Consciousness.ThinkingResult "surface" "deep meaning" "настоящее" 0.10
        , Consciousness.koConflicts = ["конфликт границ"]
        , Consciousness.koOntologicalQuestion =
            Consciousness.OntologicalQuestion
              Consciousness.FormReasoning
              Consciousness.MeaningExtendedMode
              Consciousness.ReturnMixedMode
        , Consciousness.koNarrativeDrive = Consciousness.DriveInquiry
        , Consciousness.koFocusHint = "focus"
        }
      event = Consciousness.InterpretationEvent
        { Consciousness.ieWhat = "selected skill"
        , Consciousness.ieWhy = "context"
        , Consciousness.ieDesire = "Присутствовать"
        , Consciousness.ieTurn = 1
        }
      selfInterp =
        Consciousness.updateSelfInterpretation
          (Consciousness.csSelfInterp Consciousness.emptyConsciousState)
          kernelOutput
          event
  assertBool
    "high-affinity skill should be reflected in observed patterns"
    ("Тяготею к: Слушать подтекст" `elem` Consciousness.siObservedPatterns selfInterp)
  assertEqual "conflicts should be preserved in self-interpretation" ["конфликт границ"] (Consciousness.siConflicts selfInterp)

testMorphologyExtractsContentNouns :: Test
testMorphologyExtractsContentNouns = TestCase $ do
  let nouns = Morph.extractContentNouns "Свобода и сознание требуют основание"
  assertBool "content noun extraction should keep freedom lemma" ("свобода" `elem` nouns)
  assertBool "content noun extraction should keep consciousness lemma" ("сознание" `elem` nouns)
  let questionNouns = Morph.extractContentNouns "Что такое свобода?"
  assertEqual "question helper words should not eclipse the semantic focus" ["свобода"] questionNouns

testMorphologyBuildForms :: Test
testMorphologyBuildForms = TestCase $ do
  let tokens =
        [ Morph.MorphToken "свобода" "свобода" Morph.Noun (Just Morph.Nominative) (Just Morph.Singular) (Just Morph.Feminine) Nothing Nothing Nothing
        , Morph.MorphToken "свободы" "свобода" Morph.Noun (Just Morph.Genitive) (Just Morph.Singular) (Just Morph.Feminine) Nothing Nothing Nothing
        , Morph.MorphToken "свободе" "свобода" Morph.Noun (Just Morph.Prepositional) (Just Morph.Singular) (Just Morph.Feminine) Nothing Nothing Nothing
        ]
      md = Morph.buildMorphologyData tokens
  assertEqual "genitive mapping should collapse to lemma" "свобода" (Morph.genitiveForm md "свободы")
  assertEqual "prepositional mapping should collapse to lemma" "свобода" (Morph.prepositionalForm md "свободе")
  assertEqual "nominative mapping should preserve lemma" "свобода" (Morph.toNominative md "свобода")

testMorphologyUsesGeneratedRuntimeLexicon :: Test
testMorphologyUsesGeneratedRuntimeLexicon = TestCase $ do
  let nounTok = Morph.analyzeMorph "диалога"
      verbTok = Morph.analyzeMorph "понимать"
  assertEqual "generated lexicon should resolve noun lemma" "диалог" (Morph.mtLemma nounTok)
  assertEqual "generated lexicon should classify noun as noun" Morph.Noun (Morph.mtPOS nounTok)
  assertEqual "generated lexicon should infer genitive case" (Just Morph.Genitive) (Morph.mtCase nounTok)
  assertEqual "generated lexicon should classify verb as verb" Morph.Verb (Morph.mtPOS verbTok)
  assertEqual "generated lexicon should preserve verb lemma" "понимать" (Morph.mtLemma verbTok)

testGeneratedLexiconDeterministicGrouping :: Test
testGeneratedLexiconDeterministicGrouping = TestCase $ do
  let entries = generatedLexemeEntries
      canonical = map (\(_, lemma, pos, caseTag) -> (lemma, pos, caseTag)) entries
      canonicalSorted = sortOn (\(lemma, pos, caseTag) -> (lemma, pos, caseRank caseTag)) canonical
      groups = foldr insertGroup Map.empty entries
  assertEqual "generated entries should be in deterministic canonical order" canonicalSorted canonical
  assertBool "every (lemma,pos) group should have all 3 case tags"
    (all hasAllCases (Map.elems groups))
  where
    insertGroup (_, lemma, pos, caseTag) acc =
      let key = (lemma, pos)
      in Map.insertWith (++) key [caseTag] acc

    hasAllCases tags =
      let norm = sortOn id tags
      in norm == ["genitive", "nominative", "prepositional"]

    caseRank caseTag
      | caseTag == "nominative" = 0 :: Int
      | caseTag == "genitive" = 1
      | caseTag == "prepositional" = 2
      | otherwise = 99

testMorphologyResourcesLexiconContour :: Test
testMorphologyResourcesLexiconContour = TestCase $ do
  md <- loadMorphologyData
  assertEqual "genitive should map back to nominative" "диалог" (Morph.toNominative md "диалога")
  assertEqual "prepositional should map back to nominative" "свобода" (Morph.toNominative md "свободе")
  assertEqual "nominative should map to curated genitive" "агентности" (Morph.genitiveForm md "агентность")
  assertEqual "nominative should map to curated prepositional" "контакте" (Morph.prepositionalForm md "контакт")


testMergeFamilySignalsParserOverride :: Test
testMergeFamilySignalsParserOverride = TestCase $ do
  let result = mergeFamilySignals CMGround CMDefine CMGround
  assertEqual "Parser override should win when != recommended and != CMGround"
    CMDefine result

testMergeFamilySignalsSemanticOverride :: Test
testMergeFamilySignalsSemanticOverride = TestCase $ do
  let result = mergeFamilySignals CMGround CMGround CMContact
  assertEqual "Semantic override should win when != recommended and != CMGround"
    CMContact result

testMergeFamilySignalsNoOverride :: Test
testMergeFamilySignalsNoOverride = TestCase $ do
  let result = mergeFamilySignals CMGround CMGround CMGround
  assertEqual "Recommended should win when no override"
    CMGround result

testDetectPressureCorrection :: Test
testDetectPressureCorrection = TestCase $ do
  let result = detectPressure "Ты не прав, это неверно" []
  assertBool "Correction markers should be detected" (isJust result)
  where
    isJust (Just _) = True
    isJust Nothing = False

testDetectPressureAuthority :: Test
testDetectPressureAuthority = TestCase $ do
  let result = detectPressure "Ты должен согласиться с этим" []
  assertBool "Authority markers should be detected" (isJust result)
  where
    isJust (Just _) = True
    isJust Nothing = False

testDetectPressureEmotional :: Test
testDetectPressureEmotional = TestCase $ do
  let result = detectPressure "Ты меня не понимаешь" []
  assertBool "Emotional markers should be detected" (isJust result)
  where
    isJust (Just _) = True
    isJust Nothing = False

testDetectPressureNoPressure :: Test
testDetectPressureNoPressure = TestCase $ do
  let result = detectPressure "Расскажи про свободу" []
  assertBool "Neutral input should not detect pressure" (isNothing result)
  where
    isNothing Nothing = True
    isNothing _ = False

testComputeTensionDeltaNegative :: Test
testComputeTensionDeltaNegative = TestCase $ do
  let ss = emptySystemState
      delta = computeTensionDelta "Я не согласен с этим" ss
  assertBool "Negative markers should increase tension delta" (delta > 0.05)

testComputeTensionDeltaDistress :: Test
testComputeTensionDeltaDistress = TestCase $ do
  let ss = emptySystemState
      delta = computeTensionDelta "Я чувствую страх и тоску" ss
  assertBool "Distress markers should increase tension delta" (delta > 0.1)

testComputeTensionDeltaNeutral :: Test
testComputeTensionDeltaNeutral = TestCase $ do
  let ss = emptySystemState { ssIdentity = (ssIdentity emptySystemState) { idsEgo = emptyEgoState { egoTension = 0.0 } } }
      delta = computeTensionDelta "Расскажи что-нибудь" ss
  assertBool "Neutral input with zero ego tension should have near-zero delta" (delta < 0.01)

testComputeTensionDeltaInsuranceNeutral :: Test
testComputeTensionDeltaInsuranceNeutral = TestCase $ do
  let ss = emptySystemState { ssIdentity = (ssIdentity emptySystemState) { idsEgo = emptyEgoState { egoTension = 0.0 } } }
      delta = computeTensionDelta "Страхование жизни полезно" ss
  assertBool "страхование should not trip distress tension by substring" (delta < 0.01)

testRouteFamilyInputPropagated :: Test
testRouteFamilyInputPropagated = TestCase $ do
  let input = "Ты не прав, это неверно"
      ss = emptySystemState
      frame = parseProposition input
      nextUserState = inferUserState (ssClusters ss) input
      atomSet = collectAtoms input []
      rd = routeFamily CMDescribe frame atomSet nextUserState ss [] input False "тест" Nothing 0.0
  assertBool "Input should propagate to semanticInput (not empty)" (siRawInput (rdSemanticInput rd) == input)
  assertBool "Pressure should be detected from actual input" (isJust (rdPressure rd))
  assertBool "PrincipledMode should activate from actual input" (isJust (rdPrincipledMode rd))
  where
    isJust (Just _) = True
    isJust Nothing = False

testRouteFamilyNixBlocked :: Test
testRouteFamilyNixBlocked = TestCase $ do
  let input = "Расскажи про свободу"
      ss = emptySystemState
      frame = parseProposition input
      nextUserState = inferUserState (ssClusters ss) input
      atomSet = collectAtoms input []
      rd = routeFamily CMDescribe frame atomSet nextUserState ss [] input True "свобода" Nothing 0.0
  assertEqual "Nix-blocked should force CMRepair" CMRepair (rdFamily rd)

testNixGuardCyrillicConceptDoesNotUnsafeBlock :: Test
testNixGuardCyrillicConceptDoesNotUnsafeBlock = TestCase $ do
  status <- NixGuard.checkConstitution "semantics/concepts.nix" "люди" 0.5 0.5
  case status of
    Blocked nixReason ->
      assertBool "ordinary Cyrillic concepts must not be rejected as unsafe characters"
        (not ("unsafe characters" `T.isInfixOf` nixReason))
    _ -> pure ()

testRouteFamilyAnchorUsesCurrentTopic :: Test
testRouteFamilyAnchorUsesCurrentTopic = TestCase $ do
  let input = "Что такое свобода?"
      ss = emptySystemState { ssSemantic = (ssSemantic emptySystemState) { semSemanticAnchor = Just SemanticAnchor
        { saDominantChannel = ChannelGround
        , saSecondaryChannel = Just "старая_тема"
        , saEstablishedAtTurn = 0
        , saStrength = 0.5
        , saStability = 0.4
        } } }
      frame = parseProposition input
      nextUserState = inferUserState (ssClusters ss) input
      currentTopic = "свобода"
      atomSet = collectAtoms input []
      rd = routeFamily CMGround frame atomSet nextUserState ss [] input False currentTopic Nothing 0.0
  assertBool "Anchor secondary channel should reflect current topic"
    (fmap saSecondaryChannel (rdSemanticAnchor rd) == Just (Just "свобода"))

testModulateRMPWithNarrativeDeepMode :: Test
testModulateRMPWithNarrativeDeepMode = TestCase $ do
  let rmp = ResponseMeaningPlan
        { rmpFamily = CMGround, rmpForce = IFAssert
        , rmpSpeechAct = Assert, rmpRelation = SRGround
        , rmpStrategy = DirectThenGround, rmpStance = Firm
        , rmpEpistemic = Known 0.9, rmpTopic = "topic"
        , rmpPrimaryClaim = "claim", rmpPrimaryClaimAst = Nothing, rmpContrastAxis = ""
        , rmpImplicationDirection = "forward", rmpProvenance = BuiltClaim
        , rmpCommitmentStrength = 0.9, rmpDepthMode = SurfaceDepth
        }
      longNarrative = Just (T.replicate 20 "abc ")
      result = modulateRMPWithNarrative longNarrative rmp
  assertEqual "Long narrative should set depthMode to deep" DeepDepth (rmpDepthMode result)

testModulateRMPWithNarrativeTopicFill :: Test
testModulateRMPWithNarrativeTopicFill = TestCase $ do
  let rmp = ResponseMeaningPlan
        { rmpFamily = CMGround, rmpForce = IFAssert
        , rmpSpeechAct = Assert, rmpRelation = SRGround
        , rmpStrategy = DirectThenGround, rmpStance = Firm
        , rmpEpistemic = Known 0.9, rmpTopic = ""
        , rmpPrimaryClaim = "claim", rmpPrimaryClaimAst = Nothing, rmpContrastAxis = ""
        , rmpImplicationDirection = "forward", rmpProvenance = BuiltClaim
        , rmpCommitmentStrength = 0.9, rmpDepthMode = SurfaceDepth
        }
      result = modulateRMPWithNarrative (Just "some narrative text") rmp
  assertEqual "Empty topic should be filled from narrative" "some narrative text" (rmpTopic result)

testModulateRMPWithNarrativeNoOp :: Test
testModulateRMPWithNarrativeNoOp = TestCase $ do
  let rmp = ResponseMeaningPlan
        { rmpFamily = CMGround, rmpForce = IFAssert
        , rmpSpeechAct = Assert, rmpRelation = SRGround
        , rmpStrategy = DirectThenGround, rmpStance = Firm
        , rmpEpistemic = Known 0.9, rmpTopic = "topic"
        , rmpPrimaryClaim = "claim", rmpPrimaryClaimAst = Nothing, rmpContrastAxis = ""
        , rmpImplicationDirection = "forward", rmpProvenance = BuiltClaim
        , rmpCommitmentStrength = 0.9, rmpDepthMode = SurfaceDepth
        }
      result = modulateRMPWithNarrative Nothing rmp
  assertEqual "No narrative should not change depthMode" SurfaceDepth (rmpDepthMode result)
  assertEqual "No narrative should not change topic" "topic" (rmpTopic result)

testModulateRCPWithFlashOverride :: Test
testModulateRCPWithFlashOverride = TestCase $ do
  let rcp = ResponseContentPlan
        { rcpFamily = CMGround, rcpOpening = MoveGroundKnown
        , rcpCore = MoveGroundBasis, rcpLimit = MoveAcknowledgeRupture
        , rcpContinuation = MoveNextStep, rcpStyle = StyleFormal
        }
      result = modulateRCPWithFlash True rcp
  assertEqual "Flash override should set style to direct" StyleDirect (rcpStyle result)

testModulateRCPWithFlashNoOp :: Test
testModulateRCPWithFlashNoOp = TestCase $ do
  let rcp = ResponseContentPlan
        { rcpFamily = CMGround, rcpOpening = MoveGroundKnown
        , rcpCore = MoveGroundBasis, rcpLimit = MoveAcknowledgeRupture
        , rcpContinuation = MoveNextStep, rcpStyle = StyleFormal
        }
      result = modulateRCPWithFlash False rcp
  assertEqual "No flash override should preserve style" StyleFormal (rcpStyle result)

testNarrativeFamilyHintSilence :: Test
testNarrativeFamilyHintSilence = TestCase $ do
  let cn = ConsciousnessNarrative
        { cnKernelState = "test", cnActiveDesires = "test"
        , cnSkillInPlay = "\1052\1086\1083\1095\1072\1090\1100"
        , cnSelfView = "test", cnConflict = "", cnLimitation = ""
        }
      result = narrativeFamilyHint cn
  assertEqual "Silence skill should hint CMAnchor" (Just CMAnchor) result

testNarrativeFamilyHintConflict :: Test
testNarrativeFamilyHintConflict = TestCase $ do
  let cn = ConsciousnessNarrative
        { cnKernelState = "test", cnActiveDesires = "test"
        , cnSkillInPlay = "\1043\1086\1074\1086\1088\1080\1090\1100"
        , cnSelfView = "test", cnConflict = "\1042\1085\1091\1090\1088\1077\1085\1085\1080\1081 \1082\1086\1085\1092\1083\1080\1082\1090: test", cnLimitation = ""
        }
      result = narrativeFamilyHint cn
  assertEqual "Conflict should override skill hint to CMReflect" (Just CMReflect) result

testNarrativeFamilyHintContact :: Test
testNarrativeFamilyHintContact = TestCase $ do
  let cn = ConsciousnessNarrative
        { cnKernelState = "test", cnActiveDesires = "test"
        , cnSkillInPlay = "\1057\1083\1091\1096\1072\1090\1100 \1087\1086\1076\1090\1077\1082\1089\1090"
        , cnSelfView = "test", cnConflict = "", cnLimitation = ""
        }
      result = narrativeFamilyHint cn
  assertEqual "Listening skill should hint CMContact" (Just CMContact) result

testNarrativeFamilyHintNoHint :: Test
testNarrativeFamilyHintNoHint = TestCase $ do
  let cn = ConsciousnessNarrative
        { cnKernelState = "test", cnActiveDesires = "test"
        , cnSkillInPlay = "unknown skill"
        , cnSelfView = "test", cnConflict = "", cnLimitation = ""
        }
      result = narrativeFamilyHint cn
  assertEqual "Unrecognized skill with no conflict should yield no hint" Nothing result

testIntuitionFamilyHintHigh :: Test
testIntuitionFamilyHintHigh = TestCase $ do
  let result = intuitionFamilyHint 0.6
  assertEqual "High posterior should hint CMDeepen" (Just CMDeepen) result

testIntuitionFamilyHintLow :: Test
testIntuitionFamilyHintLow = TestCase $ do
  let result = intuitionFamilyHint 0.3
  assertEqual "Low posterior should yield no hint" Nothing result

testRouteFamilyNarrativeHintChangesFamily :: Test
testRouteFamilyNarrativeHintChangesFamily = TestCase $ do
  let input = "Расскажи про свободу"
      ss = emptySystemState
      frame = parseProposition input
      nextUserState = inferUserState (ssClusters ss) input
      atomSet = collectAtoms input []
      rdBaseline = routeFamily CMDescribe frame atomSet nextUserState ss [] input False "свобода" Nothing 0.0
      silenceNarrative = Just ConsciousnessNarrative
        { cnKernelState = "test", cnActiveDesires = "test"
        , cnSkillInPlay = "\1052\1086\1083\1095\1072\1090\1100"
        , cnSelfView = "test", cnConflict = "", cnLimitation = ""
        }
      rdWithHint = routeFamily CMDescribe frame atomSet nextUserState ss [] input False "свобода" silenceNarrative 0.0
  assertBool "Silence narrative hint should change family from baseline"
    (rdFamily rdWithHint /= rdFamily rdBaseline)
  assertEqual "Silence narrative should route to CMAnchor" CMAnchor (rdFamily rdWithHint)

testRouteFamilyOperationalQuestionResistsReflectNarrative :: Test
testRouteFamilyOperationalQuestionResistsReflectNarrative = TestCase $ do
  let input = "почему ты не работаешь?"
      ss = emptySystemState
      frame = parseProposition input
      nextUserState = inferUserState (ssClusters ss) input
      atomSet = collectAtoms input []
      conflictNarrative = Just ConsciousnessNarrative
        { cnKernelState = "test", cnActiveDesires = "test"
        , cnSkillInPlay = "unknown skill"
        , cnSelfView = "test", cnConflict = "Внутренний конфликт: test", cnLimitation = ""
        }
      rd = routeFamily CMDescribe frame atomSet nextUserState ss [] input False "работа" conflictNarrative 0.0
  assertBool "diagnostic operational question should not be overridden into reflect by conflict narrative" (rdFamily rd /= CMReflect)

testRouteFamilyIntuitionHintChangesFamily :: Test
testRouteFamilyIntuitionHintChangesFamily = TestCase $ do
  let input = "Расскажи про свободу"
      ss = emptySystemState
      frame = parseProposition input
      nextUserState = inferUserState (ssClusters ss) input
      atomSet = collectAtoms input []
      rdBaseline = routeFamily CMDescribe frame atomSet nextUserState ss [] input False "свобода" Nothing 0.0
      rdWithHint = routeFamily CMDescribe frame atomSet nextUserState ss [] input False "свобода" Nothing 0.7
  assertBool "High intuition posterior should change family from baseline"
    (rdFamily rdWithHint /= rdFamily rdBaseline)
  assertEqual "High intuition posterior should route to CMDeepen" CMDeepen (rdFamily rdWithHint)

testIsVapidTopicEmpty :: Test
testIsVapidTopicEmpty = TestCase $ do
  assertBool "empty string should be vapid" (Dialogue.isVapidTopic "")

testIsVapidTopicVapidWord :: Test
testIsVapidTopicVapidWord = TestCase $ do
  assertBool "vapid word should be detected" (Dialogue.isVapidTopic "\1101\1090\1086")
  assertBool "stripped vapid word should be detected" (Dialogue.isVapidTopic " \1101\1090\1086 ")

testIsVapidTopicNonVapid :: Test
testIsVapidTopicNonVapid = TestCase $ do
  assertBool "substantive topic should not be vapid" (not (Dialogue.isVapidTopic "\1089\1074\1086\1073\1086\1076\1072"))

testCleanTopicVapidToEmpty :: Test
testCleanTopicVapidToEmpty = TestCase $ do
  assertEqual "vapid topic should clean to empty" "" (Dialogue.cleanTopic "\1101\1090\1086")

testCleanTopicPreservesNonVapid :: Test
testCleanTopicPreservesNonVapid = TestCase $ do
  assertEqual "non-vapid topic should be stripped" "\1089\1074\1086\1073\1086\1076\1072" (Dialogue.cleanTopic " \1089\1074\1086\1073\1086\1076\1072 ")

testStancePrefixAllConstructors :: Test
testStancePrefixAllConstructors = TestCase $ do
  assertBool "Commit should be empty prefix" (T.null (Dialogue.stancePrefix Commit))
  assertBool "Observe should be empty prefix" (T.null (Dialogue.stancePrefix Observe))
  assertBool "Explore should be non-empty" (not (T.null (Dialogue.stancePrefix Explore)))
  assertBool "Tentative should be non-empty" (not (T.null (Dialogue.stancePrefix Tentative)))
  assertBool "Firm should be non-empty" (not (T.null (Dialogue.stancePrefix Firm)))
  assertBool "Honest should be non-empty" (not (T.null (Dialogue.stancePrefix Honest)))
  assertBool "HoldBack should be non-empty" (not (T.null (Dialogue.stancePrefix HoldBack)))
  assertBool "Curated should be non-empty" (not (T.null (Dialogue.stancePrefix Curated)))


testMoveToTextGroundKnown :: Test
testMoveToTextGroundKnown = TestCase $ do
  let md = MorphologyData
        { mdPrepositional = Map.fromList [("\1089\1074\1086\1073\1086\1076\1072", "\1089\1074\1086\1073\1086\1076\1077")]
        , mdGenitive = Map.fromList [("\1089\1074\1086\1073\1086\1076\1099", "\1089\1074\1086\1073\1086\1076\1072")]
        , mdNominative = Map.fromList [("\1089\1074\1086\1073\1086\1076\1072", "\1089\1074\1086\1073\1086\1076\1072")]
        , mdFormsBySurface = Map.empty
        }
      result = Dialogue.moveToText MoveGroundKnown "\1089\1074\1086\1073\1086\1076\1072" md
  assertBool "MoveGroundKnown should contain prepositional form" (T.isInfixOf "\1089\1074\1086\1073\1086\1076\1077" result)

testMoveToTextAffirmPresence :: Test
testMoveToTextAffirmPresence = TestCase $ do
  let md = MorphologyData Map.empty Map.empty Map.empty Map.empty
      result = Dialogue.moveToText MoveAffirmPresence "\1089\1074\1086\1073\1086\1076\1072" md
  assertEqual "MoveAffirmPresence should ignore topic" "\1071 \1079\1076\1077\1089\1100." result

testClaimAstStableForSameIntent :: Test
testClaimAstStableForSameIntent = TestCase $ do
  let frame1 = parseProposition "поговорим о логике?"
      frame2 = parseProposition "давай поговорим о логике?"
      rmp1 = TurnPlanning.buildRMP (ipfCanonicalFamily frame1) frame1 (ipfFocusEntity frame1) emptyEgoState emptyAtomTrace True
      rmp2 = TurnPlanning.buildRMP (ipfCanonicalFamily frame2) frame2 (ipfFocusEntity frame2) emptyEgoState emptyAtomTrace True
  case (rmpPrimaryClaimAst rmp1, rmpPrimaryClaimAst rmp2) of
    (Just (MoveInvite _ _ _), Just (MoveInvite _ _ _)) -> pure ()
    other -> assertFailure ("same intent should map to stable invitation AST, got: " <> show other)

testClaimAstSameTreeVariedSurface :: Test
testClaimAstSameTreeVariedSurface = TestCase $ do
  let frame = parseProposition "что такое осень?"
      family = ipfCanonicalFamily frame
      rmp = TurnPlanning.buildRMP family frame (ipfFocusEntity frame) emptyEgoState emptyAtomTrace True
      rcpFormal = (TurnPlanning.buildRCP family rmp) { rcpStyle = StyleFormal }
      rcpWarm = (TurnPlanning.buildRCP family rmp) { rcpStyle = StyleWarm }
      md = ssMorphology emptySystemState
      artFormal = Dialogue.renderDialogueArtifact frame rmp rcpFormal (ipfFocusEntity frame) [] md
      artWarm = Dialogue.renderDialogueArtifact frame rmp rcpWarm (ipfFocusEntity frame) [] md
  assertBool "define question should build claim AST" (rmpPrimaryClaimAst rmp /= Nothing)
  assertBool "structured render should mark linearization as successful" (Dialogue.draLinearizationOk artFormal)
  assertEqual "same AST should stay stable across styles for GF linearization"
    (Dialogue.draRenderedText artFormal)
    (Dialogue.draRenderedText artWarm)


testRenderSemanticIntrospectionFormat :: Test
testRenderSemanticIntrospectionFormat = TestCase $ do
  let ss = emptySystemState
      rendered = RenderSemantic.renderSemanticIntrospection ss
  assertBool "output should begin with SEMANTIC_INTROSPECTION_BEGIN"
    (T.isPrefixOf "SEMANTIC_INTROSPECTION_BEGIN" rendered)
  assertBool "output should end with SEMANTIC_INTROSPECTION_END"
    (T.isSuffixOf "SEMANTIC_INTROSPECTION_END\n" rendered)
  assertBool "output should contain turn field"
    (T.isInfixOf "turn:" rendered)
  assertBool "output should contain ema field"
    (T.isInfixOf "ema:" rendered)


testConsciousnessLoopInitialValues :: Test
testConsciousnessLoopInitialValues = TestCase $ do
  let loop = CLoop.initialLoop
  assertEqual "initial turn should be 0" 0 (CLoop.clDialogueTurn loop)
  assertEqual "initial doubt score should be 0.0" 0.0 (CLoop.clDoubtScore loop)
  assertBool "initial output should be Nothing" (isNothing (CLoop.clLastOutput loop))
  assertBool "initial narrative should be Nothing" (isNothing (CLoop.clLastNarrative loop))
  assertBool "initial surfacing should be Nothing" (isNothing (CLoop.clLastSurfacing loop))
  where
    isNothing Nothing = True
    isNothing _ = False

testConsciousnessLoopRunIncrementsTurn :: Test
testConsciousnessLoopRunIncrementsTurn = TestCase $ do
  let semanticInput0 = testSI ContentLayer (AtomSet [] 0.0 Neutral) CMGround
      semanticInput =
        semanticInput0
          { siRawInput = "тест"
          , siPropositionFrame =
              (siPropositionFrame semanticInput0)
                { ipfRawText = "тест"
                }
          }
      (loop1, fragment) = CLoop.runConsciousnessLoop CLoop.initialLoop semanticInput 0.5 0.5
  assertEqual "first run should increment turn to 1" 1 (CLoop.clDialogueTurn loop1)
  assertBool "first run should produce an output" (isJust (CLoop.clLastOutput loop1))
  assertBool "first run should produce a narrative" (isJust (CLoop.clLastNarrative loop1))
  case CLoop.clLastNarrative loop1 of
    Just narrative ->
      assertEqual "loop should return the same prompt fragment it stores in narrative"
        (Consciousness.narrativeToPromptFragment narrative)
        fragment
    Nothing -> assertFailure "expected narrative after first consciousness loop run"
  where
    isJust (Just _) = True
    isJust Nothing = False

testConsciousnessLoopUpdateAfterResponse :: Test
testConsciousnessLoopUpdateAfterResponse = TestCase $ do
  let loop0 = CLoop.initialLoop
      loop1 =
        CLoop.updateAfterResponse
          loop0
          CLoop.ResponseObservation
            { CLoop.roSurfaceText = "\1054\1090\1074\1077\1090 \1085\1072 \1074\1086\1087\1088\1086\1089"
            , CLoop.roQuestionLike = True
            }
      si1 = csSelfInterp (cmConscious (CLoop.clModel loop1))
  assertBool "updateAfterResponse should add observed pattern"
    (not (null (siObservedPatterns si1)))

testConsciousnessLoopAddCoreSignalCapsAt5 :: Test
testConsciousnessLoopAddCoreSignalCapsAt5 = TestCase $ do
  let loop0 = CLoop.initialLoop
      loopN = foldr (\_ l -> CLoop.addCoreSignal "\1089\1080\1075\1085\1072\1083" l) loop0 [1 :: Int .. 10]
      siN = csSelfInterp (cmConscious (CLoop.clModel loopN))
  assertEqual "observed patterns should be capped at 5" 5 (length (siObservedPatterns siN))


testLexicalRuntimeBuildFromGenerated :: Test
testLexicalRuntimeBuildFromGenerated = TestCase $ do
  let lrd = LexLoader.buildLexicalRuntimeData
  assertEqual "language code should be ru" "ru" (LexTypes.unLanguageCode (LexTypes.lrdLanguage lrd))
  assertBool "nominative map should contain key entries" (Map.member "\1089\1074\1086\1073\1086\1076\1072" (LexTypes.lrdNominative lrd))
  assertEqual "genitive of nominative key" (Just "\1089\1074\1086\1073\1086\1076\1099") (Map.lookup "\1089\1074\1086\1073\1086\1076\1072" (LexTypes.lrdGenitive lrd))
  assertEqual "prepositional of nominative key" (Just "\1089\1074\1086\1073\1086\1076\1077") (Map.lookup "\1089\1074\1086\1073\1086\1076\1072" (LexTypes.lrdPrepositional lrd))

testLexicalRuntimeMorphologyRoundTrip :: Test
testLexicalRuntimeMorphologyRoundTrip = TestCase $ do
  let rt = LexRuntime.LexicalRuntime { LexRuntime.lrData = LexLoader.buildLexicalRuntimeData }
  assertEqual "genitive form should map back to nominative" "\1076\1080\1072\1083\1086\1075" (LexRuntime.lexicalToNominative rt "\1076\1080\1072\1083\1086\1075\1072")
  assertEqual "prepositional form should map back to nominative" "\1089\1074\1086\1073\1086\1076\1072" (LexRuntime.lexicalToNominative rt "\1089\1074\1086\1073\1086\1076\1077")

testLexicalAnalyzeExtractsNouns :: Test
testLexicalAnalyzeExtractsNouns = TestCase $ do
  let nouns = LexAnalyze.lexicalExtractNouns "\1057\1074\1086\1073\1086\1076\1072 \1080 \1089\1086\1079\1085\1072\1085\1080\1077"
  assertBool "should extract freedom lemma" ("\1089\1074\1086\1073\1086\1076\1072" `elem` nouns)
  assertBool "should extract consciousness lemma" ("\1089\1086\1079\1085\1072\1085\1080\1077" `elem` nouns)

testLexicalRuntimeLanguageCode :: Test
testLexicalRuntimeLanguageCode = TestCase $ do
  let lrd = LexLoader.buildLexicalRuntimeData
  assertEqual "default language should be ru" (LexTypes.LanguageCode "ru") (LexTypes.lrdLanguage lrd)

testSubjectStateAgencyValid :: Test
testSubjectStateAgencyValid = TestCase $ do
  let highAgency = SubjectState 0.8 0.3
      lowAgency  = SubjectState 0.2 0.3
  assertEqual "high agency should be valid" True (ClaimBuilder.agencyValid highAgency)
  assertEqual "low agency should be invalid" False (ClaimBuilder.agencyValid lowAgency)

testSubjectStateTensionValid :: Test
testSubjectStateTensionValid = TestCase $ do
  let lowTension  = SubjectState 0.7 0.5
      highTension = SubjectState 0.7 0.9
  assertEqual "low tension should be valid" True (ClaimBuilder.tensionValid lowTension)
  assertEqual "high tension should be invalid" False (ClaimBuilder.tensionValid highTension)

testClaimBuilderTokenBoundaryAvoidsFalseConceptMatch :: Test
testClaimBuilderTokenBoundaryAvoidsFalseConceptMatch = TestCase $ do
  let claim = IdentityClaimRef
        { icrConcept = "смысл"
        , icrText = "смысл удерживает направление"
        , icrConfidence = 0.9
        , icrSource = "test"
        , icrTopic = "meaning"
        }
      score = case ClaimBuilder.scoreClaims [claim] "Бессмысленность давит" of
        [(_, s)] -> s
        _ -> 0.0
  assertBool "concept score should not rise from substring hit inside a larger token" (score < 0.15)

testIsLegitConstructors :: Test
testIsLegitConstructors = TestCase $ do
  let ack = LegitAcknowledge ("test" :: T.Text)
      clr = LegitClarify ("test" :: T.Text)
      ins = LegitInsight ("test" :: T.Text)
  assertEqual "LegitAcknowledge shows" "LegitAcknowledge \"test\"" (show ack)
  assertEqual "LegitClarify shows" "LegitClarify \"test\"" (show clr)
  assertEqual "LegitInsight shows" "LegitInsight \"test\"" (show ins)

testExceptionPolicyQxFx0Exception :: Test
testExceptionPolicyQxFx0Exception = TestCase $ do
  assertEqual "PersistenceError shows" "PersistenceError \"test error\"" (show (PersistenceError "test error" :: QxFx0Exception))
  assertEqual "SQLiteError shows" "SQLiteError \"sql fail\"" (show (SQLiteError "sql fail" :: QxFx0Exception))

testDecodeWorkerCommandShutdown :: Test
testDecodeWorkerCommandShutdown = TestCase $ do
  let result = decodeWorkerCommand "[\"shutdown\"]"
  assertEqual "shutdown command should parse" (Right WorkerShutdown) result

testDecodeWorkerCommandTurn :: Test
testDecodeWorkerCommandTurn = TestCase $ do
  let result = decodeWorkerCommand "[\"turn\", \"s1\", \"dialogue\", \"Привет\"]"
  assertBool "turn command should parse as WorkerTurn" $ case result of Right (WorkerTurn sid _ txt) -> sid == "s1" && txt == "Привет"; _ -> False

testParseModeSemantic :: Test
testParseModeSemantic = TestCase $ do
  assertEqual "semantic mode should parse" (Right SemanticIntrospectionMode) (parseMode "semantic")
  assertEqual "dialogue mode should parse" (Right DialogueMode) (parseMode "dialogue")

testParseJsonStringArray :: Test
testParseJsonStringArray = TestCase $ do
  case parseJsonStringArray "[\"a\", \"b\", \"c\"]" of
    Just arr -> assertEqual "JSON string array should parse" ["a", "b", "c"] arr
    Nothing -> assertFailure "parseJsonStringArray should succeed on valid input"
  assertBool "malformed input should return Nothing" (isNothing (parseJsonStringArray "not json"))
  where
    isNothing Nothing = True
    isNothing _ = False

testExtractSessionArgsOverride :: Test
testExtractSessionArgsOverride = TestCase $ do
  let (sid, rest) = extractSessionArgs "default" ["--session-id", "my-session", "--help"]
  assertEqual "session id should be overridden" "my-session" sid
  assertEqual "remaining args should be preserved" ["--help"] rest

testExtractSessionArgsDefault :: Test
testExtractSessionArgsDefault = TestCase $ do
  let (sid, rest) = extractSessionArgs "default" ["--help"]
  assertEqual "session id should stay default" "default" sid
  assertEqual "args should be preserved" ["--help"] rest

testClassifyOrbitalPhaseStable :: Test
testClassifyOrbitalPhaseStable = TestCase $ do
  assertEqual "both low → Stable" OrbitStable (R5Dynamics.classifyOrbitalPhaseSimple 0.1 0.1)

testClassifyOrbitalPhaseCollapseRisk :: Test
testClassifyOrbitalPhaseCollapseRisk = TestCase $ do
  assertEqual "high collapse → CollapseRisk" OrbitCollapseRisk (R5Dynamics.classifyOrbitalPhaseSimple 0.8 0.1)

testClassifyOrbitalPhaseFreezeRisk :: Test
testClassifyOrbitalPhaseFreezeRisk = TestCase $ do
  assertEqual "high freeze → FreezeRisk" OrbitFreezeRisk (R5Dynamics.classifyOrbitalPhaseSimple 0.1 0.8)

testClassifyOrbitalPhaseCounterpressure :: Test
testClassifyOrbitalPhaseCounterpressure = TestCase $ do
  assertEqual "mid collapse → Counterpressure" OrbitCounterpressure (R5Dynamics.classifyOrbitalPhaseSimple 0.5 0.1)

testClassifyOrbitalPhaseRecovery :: Test
testClassifyOrbitalPhaseRecovery = TestCase $ do
  assertEqual "mid freeze → Recovery" OrbitRecovery (R5Dynamics.classifyOrbitalPhaseSimple 0.1 0.5)

testClassifyOrbitalPhaseBoundaryExactly :: Test
testClassifyOrbitalPhaseBoundaryExactly = TestCase $ do
  assertEqual "exactly at high threshold → CollapseRisk" OrbitCollapseRisk (R5Dynamics.classifyOrbitalPhaseSimple 0.7000001 0.1)
  assertEqual "just below high threshold → Counterpressure" OrbitCounterpressure (R5Dynamics.classifyOrbitalPhaseSimple 0.6999 0.1)
  assertEqual "just below counter threshold → Stable" OrbitStable (R5Dynamics.classifyOrbitalPhaseSimple 0.3999 0.1)

testClassifyEncounterModePressure :: Test
testClassifyEncounterModePressure = TestCase $ do
  assertEqual "CollapseRisk → Pressure" EncounterPressure (R5Dynamics.classifyEncounterModeSimple OrbitCollapseRisk 0.0)

testClassifyEncounterModeHolding :: Test
testClassifyEncounterModeHolding = TestCase $ do
  assertEqual "FreezeRisk → Holding" EncounterHolding (R5Dynamics.classifyEncounterModeSimple OrbitFreezeRisk 0.0)

testClassifyEncounterModeCounterweight :: Test
testClassifyEncounterModeCounterweight = TestCase $ do
  assertEqual "Counterpressure → Counterweight" EncounterCounterweight (R5Dynamics.classifyEncounterModeSimple OrbitCounterpressure 0.0)

testClassifyEncounterModeRecovery :: Test
testClassifyEncounterModeRecovery = TestCase $ do
  assertEqual "Recovery → Recovery" EncounterRecovery (R5Dynamics.classifyEncounterModeSimple OrbitRecovery 0.0)

testClassifyEncounterModeMirroring :: Test
testClassifyEncounterModeMirroring = TestCase $ do
  assertEqual "Stable + high tension → Mirroring" EncounterMirroring (R5Dynamics.classifyEncounterModeSimple OrbitStable 0.6)

testClassifyEncounterModeExploration :: Test
testClassifyEncounterModeExploration = TestCase $ do
  assertEqual "Stable + low tension → Exploration" EncounterExploration (R5Dynamics.classifyEncounterModeSimple OrbitStable 0.3)

testClassifyEncounterModeBoundary :: Test
testClassifyEncounterModeBoundary = TestCase $ do
  assertEqual "exactly at mirroring threshold → Exploration" EncounterExploration (R5Dynamics.classifyEncounterModeSimple OrbitStable 0.4999)
  assertEqual "just above mirroring threshold → Mirroring" EncounterMirroring (R5Dynamics.classifyEncounterModeSimple OrbitStable 0.5001)

testBuildIdentitySignalSimpleMapsDirectiveFields :: Test
testBuildIdentitySignalSimpleMapsDirectiveFields = TestCase $ do
  let directive =
        (R5Dynamics.defaultCoreDirective
          { R5Dynamics.cdContactBias = 0.81
          , R5Dynamics.cdBoundaryBias = 0.37
          , R5Dynamics.cdAbstractionBudget = 3
          , R5Dynamics.cdMoveBias = BiasDirect
          })
      sig =
        IdentitySignal.buildIdentitySignalSimple
          OrbitCollapseRisk
          EncounterPressure
          directive
          Search
          ContactLayer
          CMContact
          IFContact
  assertEqual "contact bias should be copied from directive" 0.81 (isContactStrength sig)
  assertEqual "boundary bias should be copied from directive" 0.37 (isBoundaryStrength sig)
  assertEqual "abstraction budget should be copied from directive" 3 (isAbstractionBudget sig)
  assertEqual "move bias should be copied from directive" BiasDirect (isMoveBias sig)
  assertEqual "family should match explicit argument" CMContact (isFamily sig)
  assertEqual "force should match explicit argument" IFContact (isForce sig)

testIdentityGuardReportFlagsOutOfBounds :: Test
testIdentityGuardReportFlagsOutOfBounds = TestCase $ do
  let report =
        IdentityGuard.buildIdentityGuardReportSimple
          IdentityGuard.defaultIdentityGuardCalibration
          0.55
          0.05
          0.10
          0.95
  assertBool "report should mark out-of-bounds transition" (not (IdentityGuard.igrWithinBounds report))
  assertBool "large tension delta should trigger manifold warning"
    (IdentityGuard.GuardTransitionOutsideManifold `elem` IdentityGuard.igrWarnings report)
  assertBool "tension ceiling breach should trigger drift warning"
    (IdentityGuard.GuardHighTensionDrift `elem` IdentityGuard.igrWarnings report)
  assertBool "agency floor breach should trigger collapse warning"
    (IdentityGuard.GuardAgencyCollapse `elem` IdentityGuard.igrWarnings report)

testIdentityGuardReportWithinBounds :: Test
testIdentityGuardReportWithinBounds = TestCase $ do
  let report =
        IdentityGuard.buildIdentityGuardReportSimple
          IdentityGuard.defaultIdentityGuardCalibration
          0.50
          0.55
          0.20
          0.30
  assertBool "small transition should stay within manifold" (IdentityGuard.igrWithinBounds report)
  assertEqual "stable transition should have no warnings" [] (IdentityGuard.igrWarnings report)

testUpdateOrbitalMemoryEMAClamp :: Test
testUpdateOrbitalMemoryEMAClamp = TestCase $ do
  let om = emptyOrbitalMemory
      d = R5Dynamics.defaultCoreDirective { R5Dynamics.cdContactBias = 1.0, R5Dynamics.cdBoundaryBias = 1.0 }
      om' = R5Dynamics.updateOrbitalMemorySimple om OrbitStable EncounterExploration d
  assertBool "avg attraction should increase" (omAvgAttraction om' > omAvgAttraction om)
  assertBool "avg repulsion should increase" (omAvgRepulsion om' > omAvgRepulsion om)

testUpdateOrbitalMemoryStreakTracking :: Test
testUpdateOrbitalMemoryStreakTracking = TestCase $ do
  let om = emptyOrbitalMemory
      d = R5Dynamics.defaultCoreDirective
      om1 = R5Dynamics.updateOrbitalMemorySimple om OrbitStable EncounterExploration d
      om2 = R5Dynamics.updateOrbitalMemorySimple om1 OrbitStable EncounterExploration d
  assertEqual "stable streak after 1 update" 1 (omStableStreak om1)
  assertEqual "stable streak after 2 updates" 2 (omStableStreak om2)
  assertEqual "collapse streak reset" 0 (omCollapseStreak om2)

testSteerDirectiveContactBoostRecovery :: Test
testSteerDirectiveContactBoostRecovery = TestCase $ do
  let om = emptyOrbitalMemory { omCurrentPhase = OrbitRecovery }
      d = R5Dynamics.steerDirectiveWithOrbitalSimple om R5Dynamics.defaultCoreDirective
  assertBool "contact bias should increase in recovery" (R5Dynamics.cdContactBias d > R5Dynamics.cdContactBias R5Dynamics.defaultCoreDirective)

testSteerDirectiveContactBoostFreezeRisk :: Test
testSteerDirectiveContactBoostFreezeRisk = TestCase $ do
  let om = emptyOrbitalMemory { omCurrentPhase = OrbitFreezeRisk }
      d = R5Dynamics.steerDirectiveWithOrbitalSimple om R5Dynamics.defaultCoreDirective
  assertBool "contact bias should increase in freeze risk" (R5Dynamics.cdContactBias d > R5Dynamics.cdContactBias R5Dynamics.defaultCoreDirective)

testSteerDirectiveBoundaryBoostCollapseRisk :: Test
testSteerDirectiveBoundaryBoostCollapseRisk = TestCase $ do
  let om = emptyOrbitalMemory { omCurrentPhase = OrbitCollapseRisk }
      d = R5Dynamics.steerDirectiveWithOrbitalSimple om R5Dynamics.defaultCoreDirective
  assertBool "boundary bias should increase in collapse risk" (R5Dynamics.cdBoundaryBias d > R5Dynamics.cdBoundaryBias R5Dynamics.defaultCoreDirective)

testSteerDirectiveNoOpStable :: Test
testSteerDirectiveNoOpStable = TestCase $ do
  let om = emptyOrbitalMemory { omCurrentPhase = OrbitStable }
      d = R5Dynamics.steerDirectiveWithOrbitalSimple om R5Dynamics.defaultCoreDirective
  assertEqual "contact bias unchanged in stable" (R5Dynamics.cdContactBias R5Dynamics.defaultCoreDirective) (R5Dynamics.cdContactBias d)
  assertEqual "boundary bias unchanged in stable" (R5Dynamics.cdBoundaryBias R5Dynamics.defaultCoreDirective) (R5Dynamics.cdBoundaryBias d)

testStrategyToAnswerStrategy :: Test
testStrategyToAnswerStrategy = TestCase $ do
  let mk move = ResponseStrategy ShallowResp HoldStance move DensityLow
  assertEqual "CounterMove → DeepenThenProbe" DeepenThenProbe (TurnRender.strategyToAnswerStrategy CMGround (mk CounterMove))
  assertEqual "ReframeMove → ClarifyThenDisambiguate" ClarifyThenDisambiguate (TurnRender.strategyToAnswerStrategy CMGround (mk ReframeMove))
  assertEqual "ValidateMove → ContactThenBridge" ContactThenBridge (TurnRender.strategyToAnswerStrategy CMGround (mk ValidateMove))
  assertEqual "SilenceMove → AnchorThenStabilize" AnchorThenStabilize (TurnRender.strategyToAnswerStrategy CMGround (mk SilenceMove))

testResponseStanceToMarker :: Test
testResponseStanceToMarker = TestCase $ do
  assertEqual "HoldStance → Firm" Firm (TurnRender.responseStanceToMarker HoldStance)
  assertEqual "OpenStance → Explore" Explore (TurnRender.responseStanceToMarker OpenStance)
  assertEqual "RedirectStance → Observe" Observe (TurnRender.responseStanceToMarker RedirectStance)
  assertEqual "AcknowledgeStance → Honest" Honest (TurnRender.responseStanceToMarker AcknowledgeStance)

testStrategyEpistemicPromotionDeep :: Test
testStrategyEpistemicPromotionDeep = TestCase $ do
  case TurnRender.strategyEpistemicFromDepth DeepResp (Unknown 0.5) of
    Uncertain c1 -> assertBool "Unknown → Uncertain under DeepResp" (abs (c1 - 0.6) < 1e-9)
    other -> assertFailure ("expected Uncertain, got " <> show other)
  case TurnRender.strategyEpistemicFromDepth DeepResp (Uncertain 0.7) of
    Probable c2 -> assertBool "Uncertain → Probable under DeepResp" (abs (c2 - 0.8) < 1e-9)
    other -> assertFailure ("expected Probable, got " <> show other)
  case TurnRender.strategyEpistemicFromDepth DeepResp (Probable 0.8) of
    Known c3 -> assertBool "Probable → Known under DeepResp" (abs (c3 - 0.9) < 1e-9)
    other -> assertFailure ("expected Known, got " <> show other)

testStrategyEpistemicDemotionShallow :: Test
testStrategyEpistemicDemotionShallow = TestCase $ do
  assertEqual "Known → Probable under ShallowResp" (Probable 0.5) (TurnRender.strategyEpistemicFromDepth ShallowResp (Known 0.6))
  assertEqual "Probable → Uncertain under ShallowResp" (Uncertain 0.4) (TurnRender.strategyEpistemicFromDepth ShallowResp (Probable 0.5))

testStrategyEpistemicModerateNoChange :: Test
testStrategyEpistemicModerateNoChange = TestCase $ do
  let status = Probable 0.7
  assertEqual "ModerateResp preserves epistemic" status (TurnRender.strategyEpistemicFromDepth ModerateResp status)

testStrategyDepthModeMapping :: Test
testStrategyDepthModeMapping = TestCase $ do
  assertEqual "DeepResp → DeepDepth" DeepDepth (TurnRender.strategyDepthMode DeepResp)
  assertEqual "ModerateResp → MediumDepth" MediumDepth (TurnRender.strategyDepthMode ModerateResp)
  assertEqual "ShallowResp → SurfaceDepth" SurfaceDepth (TurnRender.strategyDepthMode ShallowResp)

testRenderStyleFromDecisionHoldStance :: Test
testRenderStyleFromDecisionHoldStance = TestCase $ do
  let strat = ResponseStrategy ShallowResp HoldStance CounterMove DensityLow
      sig = IdentitySignal OrbitStable EncounterExploration 0.5 0.5 1 BiasLateral Neutral ContentLayer CMGround IFAssert
      si = testSI ContentLayer (AtomSet [] 0.5 Neutral) CMGround
  assertEqual "HoldStance → StyleFormal" StyleFormal (TurnRender.renderStyleFromDecision strat Nothing sig Nothing si)

testRenderStyleFromDecisionCounterMove :: Test
testRenderStyleFromDecisionCounterMove = TestCase $ do
  let strat = ResponseStrategy ShallowResp OpenStance CounterMove DensityLow
      sig = IdentitySignal OrbitStable EncounterExploration 0.5 0.5 1 BiasLateral Neutral ContentLayer CMGround IFAssert
      si = testSI ContentLayer (AtomSet [] 0.5 Neutral) CMGround
  assertEqual "CounterMove → StyleDirect" StyleDirect (TurnRender.renderStyleFromDecision strat Nothing sig Nothing si)

testRenderStyleFromDecisionDeepResp :: Test
testRenderStyleFromDecisionDeepResp = TestCase $ do
  let strat = ResponseStrategy DeepResp OpenStance ValidateMove DensityLow
      sig = IdentitySignal OrbitStable EncounterExploration 0.5 0.5 1 BiasLateral Neutral ContentLayer CMGround IFAssert
      si = testSI ContentLayer (AtomSet [] 0.5 Neutral) CMGround
  assertEqual "DeepResp → StylePoetic" StylePoetic (TurnRender.renderStyleFromDecision strat Nothing sig Nothing si)

testDeriveSemanticAnchorNew :: Test
testDeriveSemanticAnchorNew = TestCase $ do
  let si = testSI ContentLayer (AtomSet [] 0.7 Neutral) CMGround
      result = TurnRender.deriveSemanticAnchor Nothing si "test topic" 1
  assertBool "should produce anchor on non-empty topic" (isJust result)
  where
    isJust (Just _) = True
    isJust Nothing = False

testDeriveSemanticAnchorStabilityIncreasesOnSameChannel :: Test
testDeriveSemanticAnchorStabilityIncreasesOnSameChannel = TestCase $ do
  let si = testSI ContentLayer (AtomSet [] 0.7 Neutral) CMGround
  case TurnRender.deriveSemanticAnchor Nothing si "topic" 1 of
    Nothing -> assertFailure "first anchor should exist"
    Just a1 -> case TurnRender.deriveSemanticAnchor (Just a1) si "topic" 2 of
      Nothing -> assertFailure "second anchor should exist"
      Just a2 -> assertBool "stability should increase on same channel" (saStability a2 > saStability a1)

testDeriveSemanticAnchorResetsOnChannelChange :: Test
testDeriveSemanticAnchorResetsOnChannelChange = TestCase $ do
  let siContent = testSI ContentLayer (AtomSet [] 0.7 Neutral) CMGround
      siContact = testSI ContactLayer (AtomSet [] 0.7 Neutral) CMGround
  case TurnRender.deriveSemanticAnchor Nothing siContent "topic" 1 of
    Nothing -> assertFailure "first anchor should exist"
    Just a1 -> case TurnRender.deriveSemanticAnchor (Just a1) siContact "topic" 2 of
      Nothing -> assertFailure "second anchor should exist"
      Just a2 -> assertBool "stability should reset on channel change" (saStability a2 <= saStability a1)

testDeriveSemanticAnchorNoChangeOnEmptyTopicLowLoad :: Test
testDeriveSemanticAnchorNoChangeOnEmptyTopicLowLoad = TestCase $ do
  let si = testSI ContentLayer (AtomSet [] 0.1 Neutral) CMGround
      prev = Just SemanticAnchor
        { saDominantChannel = ChannelGround
        , saSecondaryChannel = Just "old"
        , saEstablishedAtTurn = 5
        , saStrength = 0.6
        , saStability = 0.7
        }
      result = TurnRender.deriveSemanticAnchor prev si "" 10
  assertEqual "empty topic + low load should preserve previous anchor" prev result

testRenderAnchorPrefixStableAnchor :: Test
testRenderAnchorPrefixStableAnchor = TestCase $ do
  let anchor = SemanticAnchor
        { saDominantChannel = ChannelGround
        , saSecondaryChannel = Nothing
        , saEstablishedAtTurn = 1
        , saStrength = 0.8
        , saStability = 0.7
        }
  assertBool "stable anchor should produce prefix" (not (T.null (TurnRender.renderAnchorPrefix anchor)))

testRenderAnchorPrefixUnstableAnchor :: Test
testRenderAnchorPrefixUnstableAnchor = TestCase $ do
  let anchor = SemanticAnchor
        { saDominantChannel = ChannelGround
        , saSecondaryChannel = Nothing
        , saEstablishedAtTurn = 1
        , saStrength = 0.3
        , saStability = 0.4
        }
  assertEqual "unstable anchor should produce empty prefix" "" (TurnRender.renderAnchorPrefix anchor)

testUpdateStateNixCacheInsert :: Test
testUpdateStateNixCacheInsert = TestCase $ do
  let cache0 = Map.empty
      cache1 = TurnRender.updateStateNixCache "concept" Allowed cache0
  assertEqual "insert should add entry" 1 (Map.size cache1)
  assertEqual "value should be Allowed" (Just Allowed) (Map.lookup "concept" cache1)

testUpdateStateNixCacheEvictsOverMax :: Test
testUpdateStateNixCacheEvictsOverMax = TestCase $ do
  let pairs = [(T.pack ("k" <> show i), Allowed) | i <- [1..200::Int]]
      bigCache = Map.fromList pairs
      result = TurnRender.updateStateNixCache "extra" (Blocked "test") bigCache
  assertBool "cache should not exceed max size" (Map.size result <= 100)

testMeaningGraphEdgeCapProperty :: Test
testMeaningGraphEdgeCapProperty = quickCheckTest "meaning graph edge cap" $
  forAll (chooseInt (301, 900)) $ \steps ->
    let states =
          [ MeaningState r p d
          | r <- [ResonanceLow, ResonanceMed, ResonanceHigh]
          , p <- [PressNone, PressLight, PressHeavy]
          , d <- [DepthShallow, DepthMech, DepthPattern, DepthAxiom]
          ]
        transitions = take steps [ (fromState, toState) | fromState <- states, toState <- states ]
        graph =
          foldl'
            (\acc (fromState, toState) ->
              MeaningGraph.recordTransition fromState toState (MeaningGraph.defaultStrategy fromState) True acc
            )
            MeaningGraph.emptyMeaningGraph
            transitions
    in length (mgEdges graph) <= 300

testBuildRmpForceProperty :: Test
testBuildRmpForceProperty = quickCheckTest "buildRMP force matches family contract" $
  forAll
    (elements [CMGround, CMDefine, CMDistinguish, CMReflect, CMDescribe, CMPurpose, CMHypothesis, CMRepair, CMContact, CMAnchor, CMClarify, CMDeepen, CMConfront, CMNextStep])
    (\fam ->
      let rmp = TurnPlanning.buildRMP fam emptyInputPropositionFrame "topic" emptyEgoState emptyAtomTrace True
      in rmpForce rmp == forceForFamily fam
    )

testTemplateToMovesProperty :: Test
testTemplateToMovesProperty = quickCheckTest "templateToMoves is never empty" $
  forAll
    (elements ["ground_known", "opening_define", "core_contact", "unknown-template", "next_step"])
    (\name -> not (null (TurnPlanning.templateToMoves (T.pack name))))

testMeaningGraphSuccessRateBoundedProperty :: Test
testMeaningGraphSuccessRateBoundedProperty = quickCheckTest "meaning graph successRate in [0,1]" $
  forAll (chooseInt (0, 1000)) $ \count ->
    forAll (chooseInt (0, count)) $ \wins ->
      let edge = MeaningEdge "a" "b"
            (MeaningState ResonanceLow PressNone DepthShallow)
            (MeaningState ResonanceLow PressNone DepthShallow)
            (MeaningGraph.defaultStrategy (MeaningState ResonanceLow PressNone DepthShallow))
            count wins 0.0 Nothing
      in MeaningGraph.successRate edge >= 0.0 && MeaningGraph.successRate edge <= 1.0

testMeaningGraphRecordPreservesEdgesProperty :: Test
testMeaningGraphRecordPreservesEdgesProperty = quickCheckTest "recordTransition preserves edge count for existing pair" $
  forAll (chooseInt (2, 50)) $ \extraSteps ->
    let fromState = MeaningState ResonanceHigh PressHeavy DepthAxiom
        toState = MeaningState ResonanceLow PressNone DepthShallow
        strat = MeaningGraph.defaultStrategy fromState
        g0 = MeaningGraph.recordTransition fromState toState strat True MeaningGraph.emptyMeaningGraph
        g1 = foldl' (\acc _ -> MeaningGraph.recordTransition fromState toState strat True acc) g0 [1..extraSteps]
    in length (mgEdges g1) == 1

testMeaningStateIdInjectiveProperty :: Test
testMeaningStateIdInjectiveProperty = quickCheckTest "meaningStateId is injective" $
  forAll (elements [ResonanceLow, ResonanceMed, ResonanceHigh]) $ \r1 ->
    forAll (elements [PressNone, PressLight, PressHeavy]) $ \p1 ->
      forAll (elements [DepthShallow, DepthMech, DepthPattern, DepthAxiom]) $ \d1 ->
        forAll (elements [ResonanceLow, ResonanceMed, ResonanceHigh]) $ \r2 ->
          forAll (elements [PressNone, PressLight, PressHeavy]) $ \p2 ->
            forAll (elements [DepthShallow, DepthMech, DepthPattern, DepthAxiom]) $ \d2 ->
              let ms1 = MeaningState r1 p1 d1
                  ms2 = MeaningState r2 p2 d2
              in (ms1 == ms2) == (MeaningGraph.meaningStateId ms1 == MeaningGraph.meaningStateId ms2)

testEgoTensionBoundedProperty :: Test
testEgoTensionBoundedProperty = quickCheckTest "updateEgoFromTurn tension is in [0,1]" $
  forAll (choose (0.0 :: Double, 1.0)) $ \initialTension ->
  forAll (choose (-5.0 :: Double, 5.0)) $ \delta ->
    let ego0 = emptyEgoState { egoTension = initialTension }
        ego1 = Ego.updateEgoFromTurn ego0 CMGround delta
    in egoTension ego1 >= 0.0 && egoTension ego1 <= 1.0

testLegitimacyDegradesToCautiousProperty :: Test
testLegitimacyDegradesToCautiousProperty = TestCase $ do
  assertEqual "below recovery uses recovery style" (Just StyleRecovery) (Legitimacy.styleFromLegitimacy 0.49)
  assertEqual "recovery band uses cautious style" (Just StyleCautious) (Legitimacy.styleFromLegitimacy 0.50)
  assertEqual "caution band has no override" Nothing (Legitimacy.styleFromLegitimacy 0.65)
  assertEqual "pass band has no override" Nothing (Legitimacy.styleFromLegitimacy 0.80)

testOrbitalPhaseBoundedProperty :: Test
testOrbitalPhaseBoundedProperty = quickCheckTest "classifyOrbitalPhaseSimple is total" $
  forAll (choose (-1.0 :: Double, 2.0)) $ \collapse ->
  forAll (choose (-1.0 :: Double, 2.0)) $ \freeze ->
    let phase = R5Dynamics.classifyOrbitalPhaseSimple collapse freeze
    in phase `seq` True

testResolverCuratedBeatsAuto :: Test
testResolverCuratedBeatsAuto = TestCase $ do
  let autoForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber AutoCoverageTier 0.7
      curatedForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber CuratedTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("свобода", [autoForm, curatedForm])])
      result = resolveLexemeForm md "свобода" (Just NominativeCase) (Just SingularNumber)
  assertEqual "curated tier should beat auto-coverage" (Just curatedForm) result

testResolverDangerousAmbiguityFallback :: Test
testResolverDangerousAmbiguityFallback = TestCase $ do
  let form1 = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber CuratedTier 0.9
      form2 = LexemeForm "свобода" "свобода-2" "noun" NominativeCase SingularNumber CuratedTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("свобода", [form1, form2])])
      result = resolveLexemeForm md "свобода" (Just NominativeCase) (Just SingularNumber)
  assertEqual "dangerous ambiguity should fallback to Nothing" Nothing result

testResolverExactCaseMatch :: Test
testResolverExactCaseMatch = TestCase $ do
  let nomForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber CuratedTier 0.9
      genForm = LexemeForm "свободы" "свобода" "noun" GenitiveCase SingularNumber CuratedTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("свободы", [nomForm, genForm])])
      result = resolveLexemeForm md "свободы" (Just GenitiveCase) Nothing
  assertEqual "exact genitive match should win" (Just genForm) result

testOld156LemmasResolveIdentically :: Test
testOld156LemmasResolveIdentically = TestCase $ do
  md <- loadMorphologyData
  assertEqual "nominative of диалог should still resolve to диалог"
    "диалог" (Morph.toNominative md "диалог")
  assertEqual "genitive of свобода should still resolve to свободы"
    "свободы" (Morph.genitiveForm md "свобода")
  assertEqual "prepositional of свобода should still resolve to свободе"
    "свободе" (Morph.prepositionalForm md "свобода")
  assertEqual "unknown form should fallback to raw surface"
    "несуществующее" (Morph.genitiveForm md "несуществующее")

testResolverRealDataCuratedBeatsAutoCoverage :: Test
testResolverRealDataCuratedBeatsAutoCoverage = TestCase $ do
  md <- loadMorphologyData
  let result = resolveLexemeForm md "любовь" (Just NominativeCase) (Just SingularNumber)
  case result of
    Nothing -> assertFailure "expected curated form for 'любовь' nominative"
    Just form -> do
      assertEqual "lemma should be 'любовь'" "любовь" (lfLemma form)
      assertEqual "tier should be curated" CuratedTier (lfTier form)

testResolverRealDataAutoVerifiedBeatsAutoCoverage :: Test
testResolverRealDataAutoVerifiedBeatsAutoCoverage = TestCase $ do
  md <- loadMorphologyData
  let result = resolveLexemeForm md "коса" Nothing Nothing
  case result of
    Nothing -> assertFailure "expected unambiguous auto-verified form for 'коса'"
    Just form -> do
      assertEqual "lemma should be 'коса'" "коса" (lfLemma form)
      assertEqual "tier should be auto-verified" AutoVerifiedTier (lfTier form)

testResolverRealDataCrossLemmaCaseMatch :: Test
testResolverRealDataCrossLemmaCaseMatch = TestCase $ do
  md <- loadMorphologyData
  let result = resolveLexemeForm md "выборов" (Just GenitiveCase) Nothing
  case result of
    Nothing -> assertFailure "expected genitive form for 'выборов'"
    Just form -> do
      assertEqual "lemma should be 'выбор'" "выбор" (lfLemma form)
      assertEqual "tier should be auto-verified" AutoVerifiedTier (lfTier form)

testCandidateGenitiveFallbackRealData :: Test
testCandidateGenitiveFallbackRealData = TestCase $ do
  md <- loadMorphologyData
  assertEqual "genitiveForm 'человека' should resolve via candidate forms"
    "человека" (Morph.genitiveForm md "человека")

testCandidateAccusativeFallbackRealData :: Test
testCandidateAccusativeFallbackRealData = TestCase $ do
  md <- loadMorphologyData
  assertEqual "accusativeForm 'человека' should resolve via candidate forms"
    "человека" (Morph.accusativeForm md "человека")

testCandidatePrepositionalFallbackRealData :: Test
testCandidatePrepositionalFallbackRealData = TestCase $ do
  md <- loadMorphologyData
  assertEqual "prepositionalForm 'косе' should resolve via candidate forms"
    "коса" (Morph.prepositionalForm md "косе")

quickCheckTest :: Testable prop => String -> prop -> Test
quickCheckTest label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 100 } prop
  case result of
    Success{} -> pure ()
    _ -> assertFailure ("QuickCheck failed: " <> label)

-- New typed proposition regression tests (input semantic expansion)

testParsePropositionSelfKnowledgeAboutSelf :: Test
testParsePropositionSelfKnowledgeAboutSelf = TestCase $ do
  let frame = parseProposition "что ты знаешь о себе?"
  assertEqual "Self-knowledge about self should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Self-knowledge family should be CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)
  assertBool "Self-knowledge confidence should be high"
    (ipfConfidence frame >= 0.82)

testParsePropositionSelfKnowledgeAboutUserTypo :: Test
testParsePropositionSelfKnowledgeAboutUserTypo = TestCase $ do
  let frame = parseProposition "что ты знаешь о мне?"
  assertEqual "Self-knowledge about user with typo should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Self-knowledge about user should keep a user target"
    "user" (ipfSemanticTarget frame)

testParsePropositionWorldCauseSun :: Test
testParsePropositionWorldCauseSun = TestCase $ do
  let frame = parseProposition "почему солнце светит?"
  assertEqual "World cause should be WorldCauseQ"
    "WorldCauseQ" (ipfPropositionType frame)
  assertEqual "World cause family should be CMGround"
    CMGround (ipfCanonicalFamily frame)
  assertBool "World cause confidence should be high"
    (ipfConfidence frame >= 0.82)

testParsePropositionWorldCauseSky :: Test
testParsePropositionWorldCauseSky = TestCase $ do
  let frame = parseProposition "почему небо голубое?"
  assertEqual "Sky cause should stay in world-cause class"
    "WorldCauseQ" (ipfPropositionType frame)
  assertEqual "Sky cause should preserve noun subject"
    "небо" (ipfSemanticSubject frame)
  assertEqual "Sky cause family should be CMGround"
    CMGround (ipfCanonicalFamily frame)

testParsePropositionLocationFormationThought :: Test
testParsePropositionLocationFormationThought = TestCase $ do
  let frame = parseProposition "где формируется мысль?"
  assertEqual "Location formation should be LocationFormationQ"
    "LocationFormationQ" (ipfPropositionType frame)
  assertEqual "Location formation family should be CMGround"
    CMGround (ipfCanonicalFamily frame)

testParsePropositionLocationFormationTypo :: Test
testParsePropositionLocationFormationTypo = TestCase $ do
  let frame = parseProposition "где формтруется мысль?"
  assertEqual "Location formation with typo should be LocationFormationQ"
    "LocationFormationQ" (ipfPropositionType frame)

testParsePropositionEverydayPurchaseStatement :: Test
testParsePropositionEverydayPurchaseStatement = TestCase $ do
  let frame = parseProposition "я купил дом"
  assertEqual "Everyday purchase statement should route to GroundQ"
    "GroundQ" (ipfPropositionType frame)
  assertEqual "Everyday purchase statement should keep concrete topic"
    "дом" (ipfSemanticSubject frame)
  assertEqual "Everyday purchase statement family should be CMGround"
    CMGround (ipfCanonicalFamily frame)

testParsePropositionEverydayResidenceStatement :: Test
testParsePropositionEverydayResidenceStatement = TestCase $ do
  let frame = parseProposition "я живу дома"
  assertEqual "Everyday residence statement should route to GroundQ"
    "GroundQ" (ipfPropositionType frame)
  assertEqual "Everyday residence statement should keep concrete topic"
    "дом" (ipfSemanticSubject frame)
  assertEqual "Everyday residence statement family should be CMGround"
    CMGround (ipfCanonicalFamily frame)

testParsePropositionAffectiveHelpQuestion :: Test
testParsePropositionAffectiveHelpQuestion = TestCase $ do
  let frame = parseProposition "что делать если грустно?"
  assertEqual "Affective-help question should route to next-step planning"
    "NextStepQ" (ipfPropositionType frame)
  assertEqual "Affective-help family should be CMNextStep"
    CMNextStep (ipfCanonicalFamily frame)

testParsePropositionComparisonPlausibilityTableChair :: Test
testParsePropositionComparisonPlausibilityTableChair = TestCase $ do
  let frame = parseProposition "стол на стуле. или стул на столе. что логичнее?"
  assertEqual "Comparison plausibility should be ComparisonPlausibilityQ"
    "ComparisonPlausibilityQ" (ipfPropositionType frame)
  assertEqual "Comparison family should be CMDistinguish"
    CMDistinguish (ipfCanonicalFamily frame)
  assertEqual "Comparison should capture left/right candidates"
    ["стол на стуле", "стул на столе"]
    (ipfSemanticCandidates frame)

testParsePropositionMisunderstandingReport :: Test
testParsePropositionMisunderstandingReport = TestCase $ do
  let frame = parseProposition "я не понимаю тебя"
  assertEqual "Misunderstanding should be MisunderstandingReport"
    "MisunderstandingReport" (ipfPropositionType frame)
  assertEqual "Misunderstanding family should be CMRepair"
    CMRepair (ipfCanonicalFamily frame)

testParsePropositionSelfKnowledgeConfidenceHigh :: Test
testParsePropositionSelfKnowledgeConfidenceHigh = TestCase $ do
  let frame = parseProposition "кто ты?"
  assertBool "Self-knowledge confidence high enough to lock parser family"
    (ipfConfidence frame >= 0.72)

testParsePropositionSelfKnowledgeTargetsUser :: Test
testParsePropositionSelfKnowledgeTargetsUser = TestCase $ do
  let frame = parseProposition "что ты знаешь обо мне?"
  assertEqual "About-user question should preserve the user target"
    "user" (ipfSemanticTarget frame)
  assertEqual "About-user question should name the user as semantic subject"
    "пользователь" (ipfSemanticSubject frame)

testParsePropositionComparisonCapturesCandidates :: Test
testParsePropositionComparisonCapturesCandidates = TestCase $ do
  let frame = parseProposition "стол на стуле. или стул на столе. что логичнее?"
  assertEqual "Comparison axis should be captured as semantic target"
    "логичность" (ipfSemanticTarget frame)
  assertBool "Comparison evidence should mention both candidates"
    (any ("candidates=стол на стуле|стул на столе" `T.isPrefixOf`) (ipfSemanticEvidence frame))

testParsePropositionComparisonCapturesFromCandidates :: Test
testParsePropositionComparisonCapturesFromCandidates = TestCase $ do
  let frame = parseProposition "как отличить ложь от правды?"
  assertEqual "X-ot-Y comparison should capture semantic candidates"
    ["ложь", "правды"] (ipfSemanticCandidates frame)
  assertBool "X-ot-Y comparison evidence should mention both candidates"
    (any ("candidates=ложь|правды" `T.isPrefixOf`) (ipfSemanticEvidence frame))

testParsePropositionDialogueInvitationLogic :: Test
testParsePropositionDialogueInvitationLogic = TestCase $ do
  let frame = parseProposition "поговорим о логике?"
  assertEqual "Dialogue invitation should be DialogueInvitationQ"
    "DialogueInvitationQ" (ipfPropositionType frame)
  assertEqual "Dialogue invitation should route to CMDeepen"
    CMDeepen (ipfCanonicalFamily frame)

testParsePropositionConceptKnowledgeSun :: Test
testParsePropositionConceptKnowledgeSun = TestCase $ do
  let frame = parseProposition "знаешь что такое солнце?"
  assertEqual "Concept knowledge prompt should be ConceptKnowledgeQ"
    "ConceptKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Concept knowledge subject should preserve the concept noun"
    "солнце" (ipfSemanticSubject frame)

testParsePropositionSelfStateQuestion :: Test
testParsePropositionSelfStateQuestion = TestCase $ do
  let frame = parseProposition "о чём ты думаешь?"
  assertEqual "Self-state question should be SelfStateQ"
    "SelfStateQ" (ipfPropositionType frame)
  assertEqual "Self-state question should route to CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionGenerativePromptThought :: Test
testParsePropositionGenerativePromptThought = TestCase $ do
  let frame = parseProposition "скажи любую мысль"
  assertEqual "Generative prompt should be GenerativePrompt"
    "GenerativePrompt" (ipfPropositionType frame)
  assertEqual "Generative prompt should route to CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionContemplativeTopicSilence :: Test
testParsePropositionContemplativeTopicSilence = TestCase $ do
  let frame = parseProposition "тишина"
  assertEqual "Single contemplative topic should be ContemplativeTopic"
    "ContemplativeTopic" (ipfPropositionType frame)
  assertEqual "Contemplative topic should route to CMDeepen"
    CMDeepen (ipfCanonicalFamily frame)

testParsePropositionConceptKnowledgeFreedomVariant :: Test
testParsePropositionConceptKnowledgeFreedomVariant = TestCase $ do
  let frame = parseProposition "знаешь ли ты что такое свобода?"
  assertEqual "Variant concept question should still be ConceptKnowledgeQ"
    "ConceptKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Frame evidence must include semantic route tag"
    True (any ("frame.route_tag=concept_knowledge" `T.isPrefixOf`) (ipfSemanticEvidence frame))

testParsePropositionSelfStateMindVariant :: Test
testParsePropositionSelfStateMindVariant = TestCase $ do
  let frame = parseProposition "что у тебя на уме?"
  assertEqual "Self-state variant should be SelfStateQ"
    "SelfStateQ" (ipfPropositionType frame)
  assertEqual "Self-state family should be CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionGenerativePromptIdeaVariant :: Test
testParsePropositionGenerativePromptIdeaVariant = TestCase $ do
  let frame = parseProposition "дай идею"
  assertEqual "Generative variant should be GenerativePrompt"
    "GenerativePrompt" (ipfPropositionType frame)
  assertEqual "Generative family should be CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionGenerativePromptAnotherThoughtVariant :: Test
testParsePropositionGenerativePromptAnotherThoughtVariant = TestCase $ do
  let frame = parseProposition "а еще одну интересную мысль?"
  assertEqual "Another-thought variant should be GenerativePrompt"
    "GenerativePrompt" (ipfPropositionType frame)
  assertEqual "Another-thought family should be CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionGenerativePromptLogicalVariant :: Test
testParsePropositionGenerativePromptLogicalVariant = TestCase $ do
  let frame = parseProposition "скажи что-то логичное"
  assertEqual "Logical quality prompt should be GenerativePrompt"
    "GenerativePrompt" (ipfPropositionType frame)
  assertEqual "Logical quality prompt should preserve requested quality as subject"
    "логичный" (ipfSemanticSubject frame)

testParsePropositionContemplativeTopicHome :: Test
testParsePropositionContemplativeTopicHome = TestCase $ do
  let frame = parseProposition "дом"
  assertEqual "One-word contemplative input should be ContemplativeTopic"
    "ContemplativeTopic" (ipfPropositionType frame)
  assertEqual "Contemplative one-word family should be CMDeepen"
    CMDeepen (ipfCanonicalFamily frame)

testParsePropositionReflectiveAssertionSubjectivityTopic :: Test
testParsePropositionReflectiveAssertionSubjectivityTopic = TestCase $ do
  let frame = parseProposition "я думаю, что важно сохранять свою субъектность"
  assertEqual "Reflective assertion should map to ContemplativeTopic"
    "ContemplativeTopic" (ipfPropositionType frame)
  assertEqual "Reflective assertion should keep abstract concept as semantic subject"
    "субъектность" (ipfSemanticSubject frame)

testParsePropositionSelfKnowledgeWhatYouAre :: Test
testParsePropositionSelfKnowledgeWhatYouAre = TestCase $ do
  let frame = parseProposition "что ты есть?"
  assertEqual "What-you-are question should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "What-you-are family should be CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionSelfKnowledgeWhatYouAreVariant :: Test
testParsePropositionSelfKnowledgeWhatYouAreVariant = TestCase $ do
  let frame = parseProposition "чем ты являешься?"
  assertEqual "Be-what variant should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Be-what variant family should be CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionSelfKnowledgeNameQuestion :: Test
testParsePropositionSelfKnowledgeNameQuestion = TestCase $ do
  let frame = parseProposition "Как тебя зовут?"
  assertEqual "Name question should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Name question should map to CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionSelfKnowledgeTellAboutSelfQuestion :: Test
testParsePropositionSelfKnowledgeTellAboutSelfQuestion = TestCase $ do
  let frame = parseProposition "что ты можешь рассказать о себе?"
  assertEqual "Tell-about-self question should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Tell-about-self question should map to CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionSelfKnowledgeCapabilityQuestion :: Test
testParsePropositionSelfKnowledgeCapabilityQuestion = TestCase $ do
  let frame = parseProposition "ты умеешь обобщать?"
  assertEqual "Capability question should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Capability question should route to CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)
  assertEqual "Capability question should use capability target"
    "self_capability" (ipfSemanticTarget frame)
  assertEqual "Capability question should preserve action complement"
    "обобщать" (ipfSemanticSubject frame)

testParsePropositionSelfKnowledgeHelpQuestion :: Test
testParsePropositionSelfKnowledgeHelpQuestion = TestCase $ do
  let frame = parseProposition "ты можешь мне помочь?"
  assertEqual "Help question should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Help question should use user_help target"
    "user_help" (ipfSemanticTarget frame)
  assertEqual "Help question should preserve help subject"
    "помощь" (ipfSemanticSubject frame)

testParsePropositionSelfKnowledgeUserIdentityQuestion :: Test
testParsePropositionSelfKnowledgeUserIdentityQuestion = TestCase $ do
  let frame = parseProposition "кто я такой?"
  assertEqual "User identity question should be SelfKnowledgeQ"
    "SelfKnowledgeQ" (ipfPropositionType frame)
  assertEqual "User identity question should target user"
    "user" (ipfSemanticTarget frame)

testParsePropositionKeywordFallbackOperationalCause :: Test
testParsePropositionKeywordFallbackOperationalCause = TestCase $ do
  let frame = parseProposition "почему система не отвечает?"
  assertEqual "Keyword fallback should preserve operational-cause compatibility"
    "OperationalCauseQ" (ipfPropositionType frame)
  assertEqual "Keyword fallback operational cause should map to CMGround"
    CMGround (ipfCanonicalFamily frame)

testParsePropositionConceptKnowledgeBeingSmartVariant :: Test
testParsePropositionConceptKnowledgeBeingSmartVariant = TestCase $ do
  let frame = parseProposition "что значит быть умным?"
  assertEqual "Being-smart variant should be ConceptKnowledgeQ"
    "ConceptKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Being-smart concept phrase should be preserved"
    "быть умным" (ipfSemanticSubject frame)

testParsePropositionConceptKnowledgeWhoIsGod :: Test
testParsePropositionConceptKnowledgeWhoIsGod = TestCase $ do
  let frame = parseProposition "кто такой бог?"
  assertEqual "Who-is-God question should be ConceptKnowledgeQ"
    "ConceptKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Who-is-God question should map to CMDefine"
    CMDefine (ipfCanonicalFamily frame)
  assertEqual "Who-is-God should preserve subject noun"
    "бог" (ipfSemanticSubject frame)

testParsePropositionConceptKnowledgeWhatIsSense :: Test
testParsePropositionConceptKnowledgeWhatIsSense = TestCase $ do
  let frame = parseProposition "что есть смысл?"
  assertEqual "What-is-sense question should be ConceptKnowledgeQ"
    "ConceptKnowledgeQ" (ipfPropositionType frame)
  assertEqual "What-is-sense question should map to CMDefine"
    CMDefine (ipfCanonicalFamily frame)

testParsePropositionRouteScoresAreTraced :: Test
testParsePropositionRouteScoresAreTraced = TestCase $ do
  let frame = parseProposition "в чём функция стола?"
  assertBool "Route score evidence should include semantic score"
    (any ("frame.route_semantic_score=" `T.isPrefixOf`) (ipfSemanticEvidence frame))
  assertBool "Route score evidence should include embedding score"
    (any ("frame.route_embedding_score=" `T.isPrefixOf`) (ipfSemanticEvidence frame))
  assertBool "Token evidence should include syntactic role"
    (any (\entry -> "frame.token=" `T.isPrefixOf` entry && "|role=" `T.isInfixOf` entry) (ipfSemanticEvidence frame))

testParsePropositionDialogueInvitationWithoutTopicFallsBackToDialogue :: Test
testParsePropositionDialogueInvitationWithoutTopicFallsBackToDialogue = TestCase $ do
  let frame = parseProposition "поговорим?"
  assertEqual "Topic-less invitation should keep dialogue proposition"
    "DialogueInvitationQ" (ipfPropositionType frame)
  assertEqual "Topic-less invitation should default semantic subject to dialogue"
    "диалог" (ipfSemanticSubject frame)

testParsePropositionEverydayStatementKeepsHighParserConfidence :: Test
testParsePropositionEverydayStatementKeepsHighParserConfidence = TestCase $ do
  let frame = parseProposition "я купил дом, дом оказался хорошим"
  assertEqual "Everyday statement should map to GroundQ"
    "GroundQ" (ipfPropositionType frame)
  assertBool "Everyday statement confidence should stay parser-lock high"
    (ipfConfidence frame >= 0.72)

testParsePropositionFarewellSignal :: Test
testParsePropositionFarewellSignal = TestCase $ do
  let frame = parseProposition "до свидания"
  assertEqual "Farewell should map to ContactSignal"
    "ContactSignal" (ipfPropositionType frame)
  assertEqual "Farewell should map to CMContact"
    CMContact (ipfCanonicalFamily frame)

testParsePropositionGratitudeSignal :: Test
testParsePropositionGratitudeSignal = TestCase $ do
  let frame = parseProposition "спасибо тебе"
  assertEqual "Gratitude should map to ContactSignal"
    "ContactSignal" (ipfPropositionType frame)
  assertEqual "Gratitude should map to CMContact"
    CMContact (ipfCanonicalFamily frame)

testParsePropositionApologySignal :: Test
testParsePropositionApologySignal = TestCase $ do
  let frame = parseProposition "извини, я был резок"
  assertEqual "Apology should map to RepairSignal"
    "RepairSignal" (ipfPropositionType frame)
  assertEqual "Apology should map to CMRepair"
    CMRepair (ipfCanonicalFamily frame)

testParsePropositionAgreementSignal :: Test
testParsePropositionAgreementSignal = TestCase $ do
  let frame = parseProposition "я согласен с тобой"
  assertEqual "Agreement should map to AnchorSignal"
    "AnchorSignal" (ipfPropositionType frame)
  assertEqual "Agreement should map to CMAnchor"
    CMAnchor (ipfCanonicalFamily frame)

testParsePropositionDisagreementSignal :: Test
testParsePropositionDisagreementSignal = TestCase $ do
  let frame = parseProposition "я не согласен с тобой"
  assertEqual "Disagreement should map to ConfrontQ"
    "ConfrontQ" (ipfPropositionType frame)
  assertEqual "Disagreement should map to CMConfront"
    CMConfront (ipfCanonicalFamily frame)

testParsePropositionOpinionQuestion :: Test
testParsePropositionOpinionQuestion = TestCase $ do
  let frame = parseProposition "как считаешь, логика важна?"
  assertEqual "Opinion question should map to SelfStateQ"
    "SelfStateQ" (ipfPropositionType frame)
  assertEqual "Opinion question should map to CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionHowYouWillNotSmallTalk :: Test
testParsePropositionHowYouWillNotSmallTalk = TestCase $ do
  let frame = parseProposition "как ты будешь определять границы?"
      routeTag = listToMaybe
        [ T.drop (T.length "frame.route_tag=") e
        | e <- ipfSemanticEvidence frame
        , "frame.route_tag=" `T.isPrefixOf` e
        ]
  assertBool "How-you-will question should not collapse to contact smalltalk"
    (ipfPropositionType frame /= "ContactSignal")
  assertBool "How-you-will question should avoid greeting_smalltalk route tag"
    (routeTag /= Just "greeting_smalltalk")

testParsePropositionHowYouWillMapsToSystemLogic :: Test
testParsePropositionHowYouWillMapsToSystemLogic = TestCase $ do
  let frame = parseProposition "как ты будешь определять границы?"
  assertEqual "How-you-will question should map to SystemLogicQ"
    "SystemLogicQ" (ipfPropositionType frame)
  assertEqual "SystemLogicQ should map to CMDescribe"
    CMDescribe (ipfCanonicalFamily frame)

testParsePropositionPurposeDeicticSubjectNormalized :: Test
testParsePropositionPurposeDeicticSubjectNormalized = TestCase $ do
  let frame = parseProposition "зачем ты тут?"
  assertEqual "Purpose deictic question should map to PurposeQ"
    "PurposeQ" (ipfPropositionType frame)
  assertEqual "Purpose deictic question should normalize subject to system"
    "система" (ipfSemanticSubject frame)

testParsePropositionConceptKnowledgeDeathSubject :: Test
testParsePropositionConceptKnowledgeDeathSubject = TestCase $ do
  let frame = parseProposition "ты знаешь, что такое смерть?"
  assertEqual "Concept knowledge about death should map to ConceptKnowledgeQ"
    "ConceptKnowledgeQ" (ipfPropositionType frame)
  assertEqual "Concept knowledge about death should preserve subject noun"
    "смерть" (ipfSemanticSubject frame)

testParsePropositionHowDistinguishMapsToDistinction :: Test
testParsePropositionHowDistinguishMapsToDistinction = TestCase $ do
  let frame = parseProposition "как отличить ложь от правды?"
  assertEqual "How-distinguish should stay in distinguish family"
    CMDistinguish (ipfCanonicalFamily frame)
  assertBool "How-distinguish should not collapse to contemplative topic"
    (ipfPropositionType frame /= "ContemplativeTopic")

testPropositionToFamilySelfKnowledgeIsDescribe :: Test
testPropositionToFamilySelfKnowledgeIsDescribe = TestCase $
  assertEqual "SelfKnowledgeQ -> CMDescribe" CMDescribe (propositionToFamily SelfKnowledgeQ)

testPropositionToFamilyDialogueInvitationIsDeepen :: Test
testPropositionToFamilyDialogueInvitationIsDeepen = TestCase $
  assertEqual "DialogueInvitationQ -> CMDeepen" CMDeepen (propositionToFamily DialogueInvitationQ)

testPropositionToFamilyConceptKnowledgeIsDefine :: Test
testPropositionToFamilyConceptKnowledgeIsDefine = TestCase $
  assertEqual "ConceptKnowledgeQ -> CMDefine" CMDefine (propositionToFamily ConceptKnowledgeQ)

testPropositionToFamilyWorldCauseIsGround :: Test
testPropositionToFamilyWorldCauseIsGround = TestCase $
  assertEqual "WorldCauseQ -> CMGround" CMGround (propositionToFamily WorldCauseQ)

testPropositionToFamilyLocationFormationIsGround :: Test
testPropositionToFamilyLocationFormationIsGround = TestCase $
  assertEqual "LocationFormationQ -> CMGround" CMGround (propositionToFamily LocationFormationQ)

testPropositionToFamilySelfStateIsDescribe :: Test
testPropositionToFamilySelfStateIsDescribe = TestCase $
  assertEqual "SelfStateQ -> CMDescribe" CMDescribe (propositionToFamily SelfStateQ)

testPropositionToFamilyComparisonIsDistinguish :: Test
testPropositionToFamilyComparisonIsDistinguish = TestCase $
  assertEqual "ComparisonPlausibilityQ -> CMDistinguish" CMDistinguish (propositionToFamily ComparisonPlausibilityQ)

testPropositionToFamilyMisunderstandingIsRepair :: Test
testPropositionToFamilyMisunderstandingIsRepair = TestCase $
  assertEqual "MisunderstandingReport -> CMRepair" CMRepair (propositionToFamily MisunderstandingReport)

testPropositionToFamilyGenerativePromptIsDescribe :: Test
testPropositionToFamilyGenerativePromptIsDescribe = TestCase $
  assertEqual "GenerativePrompt -> CMDescribe" CMDescribe (propositionToFamily GenerativePrompt)

testPropositionToFamilyContemplativeTopicIsDeepen :: Test
testPropositionToFamilyContemplativeTopicIsDeepen = TestCase $
  assertEqual "ContemplativeTopic -> CMDeepen" CMDeepen (propositionToFamily ContemplativeTopic)
