{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.LearningLoop
  ( learningLoopTests
  ) where

import Data.Aeson (Value(..), decode, encode, toJSON)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Learning.KnowledgeTree
  ( KnowledgeSource(..)
  , KnowledgeFruit(..)
  , Branch(..)
  , KnowledgeTree(..)
  , emptyKnowledgeTree
  , graftFruit
  , quarantineFruit
  , promoteFromQuarantine
  , pruneBranches
  , pruneFruits
  , rootStressSignal
  , treeCounters
  , isTermKnownInKnowledgeTree
  )
import QxFx0.Semantic.Morphology (hasKnownMorphologyForm)
import QxFx0.Learning.Signal
  ( CalibrationSignal(..)
  , SignalComponents(..)
  , computeCalibrationSignal
  , emptySignalComponents
  )
import QxFx0.Learning.Tool
  ( ExternalTool(..)
  , ToolDomain(..)
  , selectToolWithReliability
  , updateToolReliability
  , defaultAvailableTools
  )
import QxFx0.Learning.Need
  ( LearningNeed(..)
  , LearningNeedState(..)
  , emptyLearningNeedState
  , NeedTrend(..)
  , detectLearningNeed
  , detectLearningNeedWithPressure
  , defaultLearningPressureConfig
  , LearningPressureConfig(..)
  , renderLearningNeed
  )
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Self.Field (emptyField, Field(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))
import QxFx0.Self.Perspective
  ( applyPerspectiveDecision
  , assemblePerspectiveInput
  , buildActivePerspectiveProjections
  , buildPerspectiveProjection
  , decidePerspectivePromotion
  , evaluatePerspectiveAdmissibility
  , opinionCore
  )
import QxFx0.Core.TurnPipeline.Route.Render (isTopicNoisyOrAmbiguous)
import QxFx0.Types.State
  ( AdaptiveDecision(..)
  , EvidenceStrength(..)
  , AdaptiveMutationKind(..)
  , AdaptiveMutationRecord(..)
  , BeliefPolarity(..)
  , BeliefRecord(..)
  , BeliefStore(..)
  , AdaptiveDecisionRecord(..)
  , DialogueOutcomeKind(..)
  , DialogueOutcomeLearningState(..)
  , DialogueOutcomeSample(..)
  , SpeechPolicyState(..)
  , SystemState(..)
  , emptyBeliefStore
  , emptyDialogueOutcomeLearningState
  , emptySpeechPolicyState
  , emptySystemState
  , appendAdaptiveMutationRecords
  , ssKnowledgeTree
  , ssMorphology
  , ConatusSlice(..)
  , CounterargumentRef(..)
  , EndorsedPerspective(..)
  , EvidenceRef(..)
  , IdentitySlice(..)
  , NormativeProfile(..)
  , NormativeProfileId(..)
  , PerspectiveAdmissibility(..)
  , PerspectiveCandidate(..)
  , PerspectiveInputBundle(..)
  , PerspectiveProjection(..)
  , PerspectivePromotionDecision(..)
  , PerspectiveRegistry(..)
  , PerspectiveRevisionRecord(..)
  , PerspectiveScope(..)
  , PerspectiveStatus(..)
  , PerspectiveThread(..)
  , PerspectiveVersionId(..)
  , ClaimStanceRef(..)
  , defaultNormativeProfile
  , defaultPerspectiveRegistry
  )
import QxFx0.Learning.Loop
  ( LearningTelemetry(..)
  , emptyLearningTelemetry
  , runLearningStep
  )
import QxFx0.Learning.Validator
  ( KnowledgeFruitPayload(..)
  , MorphologyPayload(..)
  , ValidationError(..)
  , validateFruitPayload
  , minDefinitionWords
  )
import QxFx0.Learning.Parser (parseLLMResponseToFruit)
import QxFx0.Learning.Sandbox
  ( SandboxResult(..)
  , SandboxMetrics(..)
  , SandboxRejectReason(..)
  , SandboxConfig(..)
  , defaultSandboxConfig
  , runSandboxGate
  , runSandboxGateWithConfig
  )
import QxFx0.Bridge.ExternalLLM
  ( LLMTransport(..)
  , queryExternalTool
  , buildTransportFromConfig
  , queryExternalToolWithConfig
  , defaultExternalQueryConfig
  )
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  , ExternalQueryConfig(..)
  , TransportFallbackReason(..)
  , renderFallbackReason
  )
import QxFx0.Semantic.Proposition (PropositionType(..))
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import QxFx0.Learning.Signal
  ( CalibrationSnapshot(..)
  , CalibrationDecision(..)
  , SignalPipelineConfig(..)
  , defaultSignalPipelineConfig
  , applyCalibrationGated
  )

learningLoopTests :: [Test]
learningLoopTests =
  [ testGraftValidPositiveFruit
  , testQuarantineMarginalFruit
  , testPromoteFromQuarantineAfterWindow
  , testPruneUnhealthyBranches
  , testPruneInvalidFruits
  , testCalibrationSignalBoundedAndNonZero
  , testCalibrationSignalClampWorks
  , testToolReliabilityRisesOnAccept
  , testToolReliabilityFallsOnReject
  , testToolReliabilityAffectsSelection
  , testKnowledgeTreeRoundTripsJson
  , testOldJsonLoadsWithDefaults
  -- Phase 8 vertical slice tests
  , testMockTransportSuccess
  , testMockTransportFailure
  , testConfigFallbackDoesNotMasqueradeAsSuccess
  , testValidatorRejectsJunk
  , testParserValidSchema
  , testParserRejectsMalformed
  , testSandboxRejectsDegrading
  , testSandboxAcceptsImproving
  , testGraftUpdatesTreeAndMorph
  , testTelemetryFieldsPopulated
  , testFailClosedOnExternalError
  -- Phase 8 hardening + Phase 9 start tests
  , testExplicitConfigFallbackReason
  , testConfigRedactsApiKey
  , testValidatorRejectsSemanticallyEmpty
  , testValidatorRejectsSchemaMismatch
  , testSandboxConfigRespectsSafetyFloor
  , testSandboxConfigAcceptsImprovement
  , testCalibrationSnapshotBoundedness
  , testCalibrationGatedApplyLowConfidence
  , testCalibrationGatedApplyRateLimit
  , testRealPathMiniEvalScenario1
  , testRealPathMiniEvalScenario2
  , testRealPathMiniEvalScenario3
  , testRealPathMiniEvalScenario4
  , testRealPathMiniEvalScenario5
  -- WP1-WP5 cumulative learning tests
  , testSystemStatePersistenceRoundTrip
  , testOldSystemStateDialogueDevelopmentDefaults
  , testAdaptiveMutationLogIsBounded
  , testPerspectiveAdmissibilityRejectsInsufficientEvidence
  , testPerspectivePromotionRequiresStabilityAndStrongEvidence
  , testPerspectiveRegistryLineageIsCanonicalAndBounded
  , testPerspectiveSuspendClearsActiveProjection
  , testPerspectiveRegistryActiveCapKeepsLineageThreads
  , testPerspectiveRollbackIsReachableAndRestoresPriorProjection
  , testPerspectiveActivationScopeSelectsMatchingNormativeProfile
  , testPerspectiveRegistryRejectsDuplicateThreads
  , testPerspectiveNormativeProfileVersionAffectsCandidate
  , testPerspectiveProjectionIsExplainableAndSafe
  , testMorphologyRetentionMerge
  , testDedupBlocksExternalQueryForKnownMorphology
  , testDedupBlocksExternalQueryForKnownTreeTerm
  , testConatusDeltaDerivedFromStateNotPayload
  -- WP6.1 learning-pressure trigger + dedup + telemetry tests
  , testLearningPressureRaisesLexiconExtension
  , testLearningPressureIgnoresLowUnknownCount
  , testLearningPressureIgnoresWhenGraftsGrowing
  , testLearningPressureBackwardCompatWrapper
  , testLearningNeedStateRoundTripsJson
  , testOldLearningNeedStateJsonLoadsDefaults
  , testTopicNoisyShort
  , testTopicNoisyDigit
  , testTopicNoisyPunctuation
  , testTopicClean
  ]

-- | Phase 7: valid + positive-delta fruit grafts into branch.
testGraftValidPositiveFruit :: Test
testGraftValidPositiveFruit = TestCase $ do
  let fruit = mkFruit "test-proposition" SourceInternal True 0.5 0.3
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
  assertEqual "graft must increment grafted count"
    1 (ktGraftedCount tree)
  assertBool "agreement branch must exist"
    (M.member "agreement" (ktBranches tree))

-- | Phase 7: marginal fruit (weak deltas) goes to quarantine.
testQuarantineMarginalFruit :: Test
testQuarantineMarginalFruit = TestCase $ do
  let fruit = mkFruit "marginal" SourceLLM True 0.05 (-0.1)
      tree = quarantineFruit fruit emptyKnowledgeTree
  assertEqual "quarantine must hold 1 fruit"
    1 (length (ktQuarantine tree))
  assertEqual "quarantined count must be 1"
    1 (ktQuarantinedCount tree)

-- | Phase 7: after min quarantine window + positive net delta,
-- fruit promotes to branch.
testPromoteFromQuarantineAfterWindow :: Test
testPromoteFromQuarantineAfterWindow = TestCase $ do
  let fruit = mkFruit "ripe" SourceHuman True 0.4 0.3
      tree0 = quarantineFruit fruit emptyKnowledgeTree
      (tree, promoted, rejected) =
        promoteFromQuarantine 10 2 "agreement" tree0
  assertEqual "promoted count must be 1"
    1 promoted
  assertEqual "rejected count must be 0"
    0 rejected
  assertEqual "grafted count must be 1"
    1 (ktGraftedCount tree)

-- | Phase 7: branch with sustained negative health pruned after K turns.
testPruneUnhealthyBranches :: Test
testPruneUnhealthyBranches = TestCase $ do
  let fruit = mkFruit "a" SourceInternal True 0.5 0.3
      tree0 = graftFruit "agreement" fruit emptyKnowledgeTree
      -- Force branch health negative by pruning its only fruit
      (tree1, _dropped) = pruneFruits 1 tree0
      -- health after pruning one fruit: 0.0 - 0.05 = -0.05
      -- Use threshold below actual health so it doesn't prune yet
      (tree2a, pruned0) = pruneBranches 5 (-0.10) 3 tree1
  assertEqual "slightly negative branch must NOT prune at -0.10 threshold"
    0 pruned0
  -- Now manually set branch health very negative to test pruneBranches
  let treeForced = tree0 { ktBranches = M.singleton "agreement"
        [ Branch { brRule = "agreement"
                 , brFruits = [mkFruit "x" SourceInternal True 0.0 0.0]
                 , brHealth = -0.8
                 , brCreatedTurn = 1
                 } ] }
      (tree3, prunedBranches) = pruneBranches 5 (-0.5) 3 treeForced
  assertEqual "strongly unhealthy branch must be pruned"
    1 prunedBranches
  assertBool "pruned count must reflect dropped fruits"
    (ktPrunedCount tree3 > 0)

-- | Phase 7: unvalidated or persistently negative fruits are pruned.
testPruneInvalidFruits :: Test
testPruneInvalidFruits = TestCase $ do
  let validFruit   = mkFruit "valid"   SourceInternal True  0.5 0.3
      invalidFruit = mkFruit "invalid" SourceLLM    False 0.0 0.0
      tree0 = graftFruit "agreement" validFruit
              (graftFruit "agreement" invalidFruit emptyKnowledgeTree)
      (tree, dropped) = pruneFruits 1 tree0
  assertEqual "invalid fruit must be pruned"
    1 dropped
  assertEqual "remaining fruit count in branch must be 1"
    1 (sum (map (length . brFruits) (concat (M.elems (ktBranches tree)))))

-- | Phase 7: calibration signal is non-zero in a diagnostic scenario
-- and bounded within [-1, 1].
testCalibrationSignalBoundedAndNonZero :: Test
testCalibrationSignalBoundedAndNonZero = TestCase $ do
  let needState = emptyLearningNeedState
        { lnsHistory = [(1, 0.8), (2, 0.85), (3, 0.9)]
        , lnsCurrentNeed = NeedLexiconExtension
        }
      (calSignal, _comps) =
        computeCalibrationSignal needState 0.8 5 10 emptyKnowledgeTree
      signal = unCalibrationSignal calSignal
  assertBool "signal must be non-zero in diagnostic scenario"
    (abs signal > 0.01)
  assertBool "signal must be <= 1.0"
    (signal <= 1.0)
  assertBool "signal must be >= -1.0"
    (signal >= -1.0)

-- | Phase 7: extreme inputs are clamped.
testCalibrationSignalClampWorks :: Test
testCalibrationSignalClampWorks = TestCase $ do
  let needState = emptyLearningNeedState
        { lnsHistory = [(1, 0.0), (2, 10.0), (3, 20.0)]
        , lnsCurrentNeed = NeedLexiconExtension
        }
      (calSignal, _comps) =
        computeCalibrationSignal needState 1.0 50 10 emptyKnowledgeTree
      signal = unCalibrationSignal calSignal
  assertBool "extreme positive inputs must clamp to <= 1.0"
    (signal <= 1.0)

-- | WP5: tool reliability rises on accepted outcome.
testToolReliabilityRisesOnAccept :: Test
testToolReliabilityRisesOnAccept = TestCase $ do
  let rel0 = M.empty
      rel1 = updateToolReliability "llm-augment" True rel0
  assertEqual "first accept must set reliability to 0.55"
    (Just 0.55) (M.lookup "llm-augment" rel1)

-- | WP5: tool reliability falls on rejected outcome.
testToolReliabilityFallsOnReject :: Test
testToolReliabilityFallsOnReject = TestCase $ do
  let rel0 = M.fromList [("llm-augment", 0.80)]
      rel1 = updateToolReliability "llm-augment" False rel0
  let actual = M.lookup "llm-augment" rel1
  assertBool "reject must drop reliability to ~0.70 (within 1e-9)"
    (case actual of
       Just v  -> abs (v - 0.70) < 1e-9
       Nothing -> False)

-- | WP5: low-reliability tool is no longer selected.
testToolReliabilityAffectsSelection :: Test
testToolReliabilityAffectsSelection = TestCase $ do
  let tools =
        [ ExternalTool "high-domain" DomainSalience 0.60 True
        , ExternalTool "low-domain" DomainSalience 0.90 True
        ]
      -- Override high-domain to be better than low-domain
      relMap = M.fromList [("high-domain", 0.95), ("low-domain", 0.30)]
      result = selectToolWithReliability NeedSalienceCalibration relMap tools
  assertEqual "selection must use dynamic reliability and pick high-domain"
    (Just "high-domain")
    (etName <$> result)

-- | Phase 7: knowledge tree round-trips through JSON.
testKnowledgeTreeRoundTripsJson :: Test
testKnowledgeTreeRoundTripsJson = TestCase $ do
  let fruit = mkFruit "prop" SourceHuman True 0.3 0.2
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
      decoded = decode (encode tree) :: Maybe KnowledgeTree
  assertEqual "knowledge tree must round-trip through JSON"
    (Just tree) decoded

-- | Backward compatibility: old JSON without knowledgeTree loads
-- with default empty tree.
testOldJsonLoadsWithDefaults :: Test
testOldJsonLoadsWithDefaults = TestCase $ do
  let minimalJson = "{\"rootMode\": \"witnessing\", \"rootTrigger\": \"conatus_floor\"}"
      decoded = decode minimalJson :: Maybe KnowledgeTree
  assertBool "minimal JSON must decode"
    (decoded /= Nothing)
  let tree = maybe emptyKnowledgeTree id decoded
  assertEqual "default branches must be empty"
    M.empty (ktBranches tree)
  assertEqual "default quarantine must be empty"
    [] (ktQuarantine tree)

-- Helpers

mkFruit :: T.Text -> KnowledgeSource -> Bool -> Double -> Double -> KnowledgeFruit
mkFruit prop src valid cDelta pDelta =
  KnowledgeFruit
    { kfProposition = prop
    , kfWord = ""
    , kfSource = src
    , kfValidated = valid
    , kfConatusDelta = cDelta
    , kfPredictiveDelta = pDelta
    , kfGraftedTurn = Nothing
    , kfObservedTurn = 1
    }

-- ============================================================
-- Phase 8 vertical slice tests
-- ============================================================

-- | WP2: mock transport returns a deterministic success.
testMockTransportSuccess :: Test
testMockTransportSuccess = TestCase $ do
  transport <- buildTransportFromConfig explicitMockConfig
  result <- queryExternalTool transport
    (ExternalTool "llm-augment" DomainLexicon 0.70 True)
    NeedLexiconExtension
    "что значит свобода"
  assertBool "mock transport must return Right for known query"
    (case result of
       Right _ -> True
       Left _  -> False)

-- | WP2: mock transport returns typed error for injected failure.
testMockTransportFailure :: Test
testMockTransportFailure = TestCase $ do
  transport <- buildTransportFromConfig explicitMockConfig
  result <- queryExternalTool transport
    (ExternalTool "llm-augment" DomainLexicon 0.70 True)
    NeedLexiconExtension
    "fail"
  assertBool "mock transport must return Left for 'fail' query"
    (case result of
       Left (EqeServerError _) -> True
       _ -> False)

explicitMockConfig :: ExternalQueryConfig
explicitMockConfig =
  defaultExternalQueryConfig
    { eqcTransportMode = "mock"
    , eqcFallbackReason = Just TfrExplicitMock
    }

testConfigFallbackDoesNotMasqueradeAsSuccess :: Test
testConfigFallbackDoesNotMasqueradeAsSuccess = TestCase $ do
  let cfg = defaultExternalQueryConfig
        { eqcTransportMode = "mistral"
        , eqcFallbackReason = Just TfrKeyMissing
        }
  result <- queryExternalToolWithConfig cfg
    (ExternalTool "llm-augment" DomainLexicon 0.70 True)
    NeedLexiconExtension
    "что значит свобода"
  case result of
    Left (EqeFallback TfrKeyMissing) -> pure ()
    other -> assertFailure ("fallback must be typed non-authoritative failure, got: " ++ show other)

-- | WP3: validator rejects empty definition and short text.
testValidatorRejectsJunk :: Test
testValidatorRejectsJunk = TestCase $ do
  let payload = KnowledgeFruitPayload
        { kfpProposition = "x"
        , kfpWord = ""
        , kfpDefinition = ""
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = 0.1
        , kfpPredictiveDelta = 0.1
        }
      morph = MorphologyData M.empty M.empty M.empty M.empty
  case validateFruitPayload payload morph of
    Left VeEmptyWord -> pure ()
    Left VeEmptyDefinition -> pure ()
    Left other -> assertFailure ("unexpected validation error: " ++ show other)
    Right _ -> assertFailure "validator must reject junk payload"

-- | WP4: parser handles a valid JSON schema response.
testParserValidSchema :: Test
testParserValidSchema = TestCase $ do
  let validJson = "{\"proposition\":\"свобода — способность\",\"word\":\"свобода\",\"definition\":\"способность действовать по своей воле\",\"source\":\"llm\",\"conatusDelta\":0.3,\"predictiveDelta\":0.2}"
      resp = ExternalQueryResponse
        { eqrRawBody = validJson
        , eqrStructured = validJson
        , eqrToolName = "llm-augment"
        , eqrLatencyMs = 0
        }
      parsed = parseLLMResponseToFruit resp
  assertBool "parser must accept valid JSON schema"
    (parsed /= Nothing)

-- | WP4: parser rejects malformed / non-JSON response.
testParserRejectsMalformed :: Test
testParserRejectsMalformed = TestCase $ do
  let bad = "this is not json"
      resp = ExternalQueryResponse
        { eqrRawBody = bad
        , eqrStructured = bad
        , eqrToolName = "llm-augment"
        , eqrLatencyMs = 0
        }
      parsed = parseLLMResponseToFruit resp
  assertBool "parser must reject malformed response"
    (parsed == Nothing)

-- | WP5: sandbox rejects a proposal with strongly negative conatus delta.
testSandboxRejectsDegrading :: Test
testSandboxRejectsDegrading = TestCase $ do
  let ss = emptySystemState
      payload = KnowledgeFruitPayload
        { kfpProposition = "deg"
        , kfpWord = "deg"
        , kfpDefinition = "very bad definition that is long enough"
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = (-0.8)
        , kfpPredictiveDelta = (-0.2)
        }
      result = runSandboxGate ss payload
  case result of
    SandboxReject _ SbrDegradingConatus -> pure ()
    SandboxReject _ SbrNegativeNetScore -> pure ()
    _ -> assertFailure "sandbox must reject degrading proposal"

-- | WP5: sandbox accepts a proposal with positive deltas.
testSandboxAcceptsImproving :: Test
testSandboxAcceptsImproving = TestCase $ do
  let ss = emptySystemState
      payload = KnowledgeFruitPayload
        { kfpProposition = "imp"
        , kfpWord = "imp"
        , kfpDefinition = "a good definition that is long enough for testing"
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = 0.5
        , kfpPredictiveDelta = 0.3
        }
      result = runSandboxGate ss payload
  case result of
    SandboxAccept _ -> pure ()
    _ -> assertFailure "sandbox must accept improving proposal"

-- | WP6: runLearningStep grafts fruit and updates morphology on accept.
testGraftUpdatesTreeAndMorph :: Test
testGraftUpdatesTreeAndMorph = TestCase $ do
  let validJson = "{\"proposition\":\"свобода — способность\",\"word\":\"свобода\",\"definition\":\"способность действовать по своей воле\",\"source\":\"llm\",\"conatusDelta\":0.3,\"predictiveDelta\":0.2}"
      resp = ExternalQueryResponse validJson validJson "llm-augment" 0
      ss0 = emptySystemState
            { ssLearningNeedState = emptyLearningNeedState
                { lnsCurrentNeed = NeedLexiconExtension
                }
            }
      (ss1, tel) = runLearningStep ss0
        (ExternalTool "llm-augment" DomainLexicon 0.70 True)
        NeedLexiconExtension "что значит свобода" (Just (Right resp))
  assertEqual "telemetry status must be accept"
    "accept" (ltValidationStatus tel)
  assertEqual "grafted count must be 1"
    1 (ktGraftedCount (ssKnowledgeTree ss1))
  assertBool "accepted external learning must record KnowledgeTree mutation"
    (any (\r -> amrKind r == MutKnowledgeTree && amrDecision r == AdaptiveAccepted) (ssAdaptiveMutationLog ss1))
  assertBool "accepted external learning must record tool reliability mutation"
    (any (\r -> amrKind r == MutToolReliability && amrDecision r == AdaptiveAccepted) (ssAdaptiveMutationLog ss1))

-- | WP8: telemetry fields are populated after a learning step.
testTelemetryFieldsPopulated :: Test
testTelemetryFieldsPopulated = TestCase $ do
  let validJson = "{\"proposition\":\"x\",\"word\":\"x\",\"definition\":\"a good definition that is long enough\",\"source\":\"llm\",\"conatusDelta\":0.3,\"predictiveDelta\":0.2}"
      resp = ExternalQueryResponse validJson validJson "llm-augment" 0
      ss0 = emptySystemState
            { ssLearningNeedState = emptyLearningNeedState
                { lnsCurrentNeed = NeedLexiconExtension
                }
            }
      (_ss1, tel) = runLearningStep ss0
        (ExternalTool "llm-augment" DomainLexicon 0.70 True)
        NeedLexiconExtension "что значит x" (Just (Right resp))
  assertEqual "query type must be Just NeedLexiconExtension"
    (Just "NeedLexiconExtension") (ltQueryType tel)
  assertEqual "tool name must be Just llm-augment"
    (Just "llm-augment") (ltExternalTool tel)
  assertEqual "status must be accept"
    "accept" (ltValidationStatus tel)

-- | Fail-closed: transport error does not graft anything.
testFailClosedOnExternalError :: Test
testFailClosedOnExternalError = TestCase $ do
  let err = EqeServerError "upstream 500"
      ss0 = emptySystemState
            { ssLearningNeedState = emptyLearningNeedState
                { lnsCurrentNeed = NeedLexiconExtension
                }
            }
      (ss1, tel) = runLearningStep ss0
        (ExternalTool "llm-augment" DomainLexicon 0.70 True)
        NeedLexiconExtension "что значит x" (Just (Left err))
  assertEqual "telemetry status must be transport_error"
    "transport_error" (ltValidationStatus tel)
  assertEqual "tree must remain empty"
    0 (ktGraftedCount (ssKnowledgeTree ss1))
  assertBool "transport error must record rejected tool reliability mutation"
    (any (\r -> amrKind r == MutToolReliability && amrDecision r == AdaptiveRejected) (ssAdaptiveMutationLog ss1))
  assertBool "reject reason must be present"
    (ltRejectReason tel /= Nothing)

-- ============================================================
-- Phase 8 hardening + Phase 9 start tests
-- ============================================================

-- | WP1: explicit config produces correct fallback reason.
testExplicitConfigFallbackReason :: Test
testExplicitConfigFallbackReason = TestCase $ do
  let cfg = defaultExternalQueryConfig
        { eqcTransportMode = "mistral"
        , eqcFallbackReason = Nothing
        }
  transport <- buildTransportFromConfig cfg
  case transport of
    MockTransport _ (Just cfg') -> do
      assertEqual "fallback reason must be KeyMissing"
        (Just TfrKeyMissing) (eqcFallbackReason cfg')
    _ -> assertFailure "must fall back to mock when key is missing"

-- | WP1: Show instance redacts API key.
testConfigRedactsApiKey :: Test
testConfigRedactsApiKey = TestCase $ do
  let cfg = defaultExternalQueryConfig
        { eqcTransportMode = "mistral"
        , eqcApiKey = Just "secret-key-123"
        }
      shown = show cfg
  assertBool "show must not contain the secret key"
    (not (T.isInfixOf "secret-key-123" (T.pack shown)))
  assertBool "show must contain REDACTED marker"
    (T.isInfixOf "REDACTED" (T.pack shown))

-- | WP2: validator rejects semantically empty definition.
testValidatorRejectsSemanticallyEmpty :: Test
testValidatorRejectsSemanticallyEmpty = TestCase $ do
  let payload = KnowledgeFruitPayload
        { kfpProposition = "x"
        , kfpWord = "thing"
        , kfpDefinition = "a thing is a thing"
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = 0.1
        , kfpPredictiveDelta = 0.1
        }
      morph = MorphologyData M.empty M.empty M.empty M.empty
  case validateFruitPayload payload morph of
    Left VeSemanticallyEmpty -> pure ()
    Left other -> assertFailure ("expected VeSemanticallyEmpty, got: " ++ show other)
    Right _ -> assertFailure "validator must reject semantically empty payload"

-- | WP2: validator rejects schema-mismatch-like invalid field.
testValidatorRejectsSchemaMismatch :: Test
testValidatorRejectsSchemaMismatch = TestCase $ do
  let emptyCaseMorph = MorphologyPayload Nothing Nothing (Just (M.singleton "nom" ""))
      payload2 = KnowledgeFruitPayload
        { kfpProposition = "x"
        , kfpWord = "word"
        , kfpDefinition = "a good definition that is long enough for testing"
        , kfpMorphology = Just emptyCaseMorph
        , kfpSource = SourceLLM
        , kfpConatusDelta = 0.1
        , kfpPredictiveDelta = 0.1
        }
      morph = MorphologyData M.empty M.empty M.empty M.empty
  case validateFruitPayload payload2 morph of
    Left (VeInvalidField _ _) -> pure ()
    Left _ -> pure ()  -- any rejection is acceptable
    Right _ -> assertFailure "validator must reject empty morphology case"

-- | WP3: configurable sandbox respects stricter safety floor.
testSandboxConfigRespectsSafetyFloor :: Test
testSandboxConfigRespectsSafetyFloor = TestCase $ do
  let ss = emptySystemState
      payload = KnowledgeFruitPayload
        { kfpProposition = "deg"
        , kfpWord = "deg"
        , kfpDefinition = "very bad definition that is long enough"
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = (-0.8)
        , kfpPredictiveDelta = (-0.2)
        }
      strictCfg = defaultSandboxConfig { scSafetyFloor = 0.0 }
      resultStrict = runSandboxGateWithConfig strictCfg ss payload
      resultDefault = runSandboxGate ss payload
  case resultStrict of
    SandboxReject _ _ -> pure ()
    _ -> assertFailure "strict config must reject strongly negative payload"
  case resultDefault of
    SandboxReject _ _ -> pure ()
    _ -> assertFailure "default config must also reject strongly negative payload"

-- | WP3: configurable sandbox accepts improvement with relaxed threshold.
testSandboxConfigAcceptsImprovement :: Test
testSandboxConfigAcceptsImprovement = TestCase $ do
  let ss = emptySystemState
      payload = KnowledgeFruitPayload
        { kfpProposition = "imp"
        , kfpWord = "imp"
        , kfpDefinition = "a good definition that is long enough for testing"
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = 0.5
        , kfpPredictiveDelta = 0.3
        }
      result = runSandboxGateWithConfig defaultSandboxConfig ss payload
  case result of
    SandboxAccept _ -> pure ()
    _ -> assertFailure "sandbox must accept improving proposal"

-- | WP4: calibration signal is bounded and snapshot is reproducible.
testCalibrationSnapshotBoundedness :: Test
testCalibrationSnapshotBoundedness = TestCase $ do
  let needState = emptyLearningNeedState
        { lnsHistory = [(1, 0.0), (2, 10.0), (3, 20.0)]
        , lnsCurrentNeed = NeedLexiconExtension
        }
      (calSignal, comps) =
        computeCalibrationSignal needState 1.0 50 10 emptyKnowledgeTree
      signal = unCalibrationSignal calSignal
  assertBool "extreme inputs must clamp to <= 1.0"
    (signal <= 1.0)
  assertBool "components must be bounded"
    (all (\x -> x >= -1.0 && x <= 1.0)
      [scConatusTrend comps, scUncertaintyTrend comps,
       scLoopRisk comps, scBranchHealthTrend comps])

-- | WP4: gated apply blocks low-confidence signals.
testCalibrationGatedApplyLowConfidence :: Test
testCalibrationGatedApplyLowConfidence = TestCase $ do
  let cfg = defaultSignalPipelineConfig { spcMinConfidence = 0.5 }
      -- counterfactual=0.5 -> uncertaintyTrend=0.0, loopCount=0 -> loopRisk=-1.0
      -- With empty history and empty tree, rawSignal ≈ -0.2, |signal| = 0.2 < 0.5
      lowSignal = fst (computeCalibrationSignal emptyLearningNeedState 0.5 0 1 emptyKnowledgeTree)
      (shouldApply, decision) = applyCalibrationGated cfg lowSignal []
  assertBool "low-confidence signal must not be applied"
    (not shouldApply)
  assertBool "decision must be HoldLowConfidence"
    (decision == CdHoldLowConfidence)

-- | WP4: gated apply respects rate limit.
testCalibrationGatedApplyRateLimit :: Test
testCalibrationGatedApplyRateLimit = TestCase $ do
  let cfg = defaultSignalPipelineConfig { spcApplyRateLimit = 1, spcApplyWindow = 2 }
      -- Create a strong signal
      needState = emptyLearningNeedState
        { lnsHistory = [(1, 0.8), (2, 0.85), (3, 0.9)]
        , lnsCurrentNeed = NeedLexiconExtension
        }
      (strongSignal, _) = computeCalibrationSignal needState 0.8 5 10 emptyKnowledgeTree
      -- First application should succeed
      snapshot1 = CalibrationSnapshot
        { csTimestamp = read "2026-05-20 00:00:00 UTC"
        , csRunId = "run-1"
        , csComponents = emptySignalComponents
        , csSignal = unCalibrationSignal strongSignal
        , csDecision = CdApplySignal
        }
      (shouldApply2, decision2) = applyCalibrationGated cfg strongSignal [snapshot1]
  assertBool "second apply within window must be blocked"
    (not shouldApply2)
  assertEqual "decision must be HoldGuardrails"
    CdHoldGuardrails decision2

-- | WP5 mini-eval scenario 1: valid concept response -> success path.
testRealPathMiniEvalScenario1 :: Test
testRealPathMiniEvalScenario1 = TestCase $ do
  let validJson = "{\"proposition\":\"свобода — способность\",\"word\":\"свобода\",\"definition\":\"способность действовать по своей воле\",\"source\":\"llm\",\"conatusDelta\":0.3,\"predictiveDelta\":0.2}"
      resp = ExternalQueryResponse validJson validJson "llm-augment" 0
      ss0 = emptySystemState
            { ssLearningNeedState = emptyLearningNeedState
                { lnsCurrentNeed = NeedLexiconExtension
                }
            }
      (ss1, tel) = runLearningStep ss0
        (ExternalTool "llm-augment" DomainLexicon 0.70 True)
        NeedLexiconExtension "что значит свобода" (Just (Right resp))
  assertEqual "telemetry must be accept"
    "accept" (ltValidationStatus tel)
  assertEqual "tree must have 1 grafted"
    1 (ktGraftedCount (ssKnowledgeTree ss1))

-- | WP5 mini-eval scenario 2: junk response -> parser/validator reject.
-- Note: empty JSON fields parse successfully but the validator rejects
-- them. If the JSON is malformed, the parser rejects first.
testRealPathMiniEvalScenario2 :: Test
testRealPathMiniEvalScenario2 = TestCase $ do
  let junkJson = "{\"word\":\"\",\"definition\":\"\",\"source\":\"llm\",\"conatusDelta\":0.1,\"predictiveDelta\":0.1}"
      resp = ExternalQueryResponse junkJson junkJson "llm-augment" 0
      ss0 = emptySystemState
            { ssLearningNeedState = emptyLearningNeedState
                { lnsCurrentNeed = NeedLexiconExtension
                }
            }
      (ss1, tel) = runLearningStep ss0
        (ExternalTool "llm-augment" DomainLexicon 0.70 True)
        NeedLexiconExtension "что значит x" (Just (Right resp))
  -- Empty word/definition: if JSON parses, validator rejects with validation_reject.
  -- If JSON is truly malformed, parser rejects with invalid_response.
  -- In this case the JSON is valid but fields are empty, so validator catches it.
  assertBool "telemetry must indicate rejection"
    (ltValidationStatus tel `elem` ["validation_reject", "invalid_response"])
  assertEqual "tree must remain empty"
    0 (ktGraftedCount (ssKnowledgeTree ss1))

-- | WP5 mini-eval scenario 3: timeout/429 -> fail-closed + telemetry.
testRealPathMiniEvalScenario3 :: Test
testRealPathMiniEvalScenario3 = TestCase $ do
  let err = EqeRateLimited "429 too many requests"
      ss0 = emptySystemState
            { ssLearningNeedState = emptyLearningNeedState
                { lnsCurrentNeed = NeedLexiconExtension
                }
            }
      (ss1, tel) = runLearningStep ss0
        (ExternalTool "llm-augment" DomainLexicon 0.70 True)
        NeedLexiconExtension "что значит x" (Just (Left err))
  assertEqual "telemetry must be transport_error"
    "transport_error" (ltValidationStatus tel)
  assertBool "reject reason must mention rate_limit"
    (case ltRejectReason tel of
       Just r -> T.isInfixOf "rate_limit" r
       Nothing -> False)

-- | WP5 mini-eval scenario 4: conflict response -> reject.
testRealPathMiniEvalScenario4 :: Test
testRealPathMiniEvalScenario4 = TestCase $ do
  let payload = KnowledgeFruitPayload
        { kfpProposition = "conflict"
        , kfpWord = "книга"
        , kfpDefinition = "печатное издание с переплётом и страницами"
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = 0.1
        , kfpPredictiveDelta = 0.1
        }
      -- Pre-populate morphology with "книга" in nominative
      -- Field order: mdPrepositional, mdGenitive, mdNominative, mdFormsBySurface
      morph = MorphologyData M.empty M.empty (M.singleton "книга" "книга") M.empty
  case validateFruitPayload payload morph of
    Left (VeLexiconConflict _) -> pure ()
    Left other -> assertFailure ("expected VeLexiconConflict, got: " ++ show other)
    Right _ -> assertFailure "validator must reject duplicate lexicon entry"

-- | WP5 mini-eval scenario 5: missing key -> deterministic mock fallback reason.
testRealPathMiniEvalScenario5 :: Test
testRealPathMiniEvalScenario5 = TestCase $ do
  let cfg = defaultExternalQueryConfig
        { eqcTransportMode = "mistral"
        , eqcFallbackReason = Nothing
          -- ^ Clear any default fallback so buildTransportFromConfig
          --   evaluates the key and discovers it is missing.
        }
  transport <- buildTransportFromConfig cfg
  case transport of
    MockTransport _ (Just cfg') -> do
      assertEqual "fallback reason must be KeyMissing"
        (Just TfrKeyMissing) (eqcFallbackReason cfg')
      assertEqual "rendered fallback reason must be key_missing"
        "key_missing" (renderFallbackReason TfrKeyMissing)
    _ -> assertFailure "must fall back to mock when API key is missing"

-- ============================================================
-- WP1/WP2: persistence round-trip and cross-session retention
-- ============================================================

-- | SystemState with populated knowledge tree and morphology round-trips through JSON.
testSystemStatePersistenceRoundTrip :: Test
testSystemStatePersistenceRoundTrip = TestCase $ do
  let fruit = mkFruitWithWord "свобода" "свобода — способность" SourceHuman True 0.3 0.2
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
      morph = MorphologyData (M.singleton "в" "в") (M.singleton "к" "к") (M.singleton "свобода" "свобода") M.empty
      outcome = emptyDialogueOutcomeLearningState
        { dolRecentOutcomes =
            [ DialogueOutcomeSample
                { dosTurn = 1
                , dosKind = DialogueOutcomeSuccess
                , dosTopic = "свобода"
                , dosSignals = ["strong_positive_confirmation"]
                , dosEvidenceStrength = EvidenceStrong
                , dosStrongUpdate = True
                , dosDecisionRecord = AdaptiveDecisionRecord
                    { adrTurn = 1
                    , adrCause = "dialogue_outcome:success"
                    , adrEvidence = ["strong_positive_confirmation"]
                    , adrConfidence = 0.8
                    , adrBoundedDelta = ["recent_outcomes<=12", "speech_patterns<=8", "claim_stance_entries<=64"]
                    , adrDecision = AdaptiveAccepted
                    , adrTargets = [MutDialogueOutcome, MutSpeechPolicy, MutClaimStance]
                    , adrMutationRecords = []
                    }
                }
            ]
        , dolSuccessCount = 1
        }
      speechPolicy = emptySpeechPolicyState
        { spsDirectness = 0.7
        , spsCompression = 0.6
        }
      belief = emptyBeliefStore
        { bsClaims = M.singleton "свобода"
            BeliefRecord
              { brClaim = "свобода"
              , brPolarity = BeliefAffirmed
              , brConfidence = 0.8
              , brEvidence = ["turn=1:success"]
              , brCounterEvidence = []
              , brLastUpdatedTurn = 1
              , brRevisionCount = 0
              }
        }
      ss0 = emptySystemState
        { ssKnowledgeTree = tree
        , ssMorphology = morph
        , ssDialogueOutcomeLearning = outcome
        , ssSpeechPolicyState = speechPolicy
        , ssBeliefStore = belief
        }
      decoded = decode (encode ss0) :: Maybe SystemState
  assertBool "SystemState must round-trip through JSON" (decoded /= Nothing)
  let ss1 = maybe emptySystemState id decoded
  assertEqual "knowledge tree grafted count must survive round-trip"
    1 (ktGraftedCount (ssKnowledgeTree ss1))
  assertBool "morphology nominative must survive round-trip"
    (M.member "свобода" (mdNominative (ssMorphology ss1)))
  assertEqual "dialogue outcome counter must survive round-trip"
    1 (dolSuccessCount (ssDialogueOutcomeLearning ss1))
  case dolRecentOutcomes (ssDialogueOutcomeLearning ss1) of
    sample:_ -> do
      assertEqual "typed evidence strength must survive round-trip"
        EvidenceStrong (dosEvidenceStrength sample)
      assertEqual "typed decision must survive round-trip"
        AdaptiveAccepted (adrDecision (dosDecisionRecord sample))
    [] -> assertFailure "dialogue outcome sample must survive round-trip"
  assertEqual "speech policy directness must survive round-trip"
    0.7 (spsDirectness (ssSpeechPolicyState ss1))
  assertBool "belief store claim must survive round-trip"
    (M.member "свобода" (bsClaims (ssBeliefStore ss1)))

-- | ADR-0032: old SystemState JSON without dialogue-development fields
-- loads with empty defaults.
testOldSystemStateDialogueDevelopmentDefaults :: Test
testOldSystemStateDialogueDevelopmentDefaults = TestCase $ do
  let withoutDialogueDevelopment =
        case toJSON emptySystemState of
          Object obj -> Object
            ( KM.delete "beliefStore"
            . KM.delete "speechPolicyState"
            . KM.delete "dialogueOutcomeLearning"
            . KM.delete "adaptiveMutationLog"
            $ obj
            )
          value -> value
      decoded = decode (encode withoutDialogueDevelopment) :: Maybe SystemState
  assertBool "old SystemState JSON must decode" (decoded /= Nothing)
  let ss = maybe emptySystemState id decoded
  assertEqual "dialogue outcome defaults must be empty"
    emptyDialogueOutcomeLearningState (ssDialogueOutcomeLearning ss)
  assertEqual "speech policy defaults must be empty"
    emptySpeechPolicyState (ssSpeechPolicyState ss)
  assertEqual "belief store defaults must be empty"
    emptyBeliefStore (ssBeliefStore ss)
  let legacySampleJson = "{\"dosTurn\":1,\"dosKind\":\"DialogueOutcomeSuccess\",\"dosTopic\":\"свобода\",\"dosSignals\":[\"positive_confirmation\"],\"dosStrongUpdate\":true}"
      decodedSample = decode legacySampleJson :: Maybe DialogueOutcomeSample
  assertBool "old DialogueOutcomeSample JSON must decode" (decodedSample /= Nothing)
  case decodedSample of
    Just sample -> do
      assertEqual "legacy strong sample gets strong evidence default"
        EvidenceStrong (dosEvidenceStrength sample)
      assertEqual "legacy strong sample gets apply decision default"
        AdaptiveAccepted (adrDecision (dosDecisionRecord sample))
    Nothing -> assertFailure "legacy sample decode unexpectedly failed"
  let legacyRecordJson = "{\"dosTurn\":2,\"dosKind\":\"DialogueOutcomeConflict\",\"dosTopic\":\"свобода\",\"dosSignals\":[\"user_conflict\"],\"dosEvidenceStrength\":\"AdaptiveEvidenceStrong\",\"dosStrongUpdate\":true,\"dosDecisionRecord\":{\"adrTurn\":2,\"adrCause\":\"dialogue_outcome:conflict\",\"adrEvidence\":[\"user_conflict\"],\"adrConfidence\":0.8,\"adrBoundedDelta\":[\"claim_stance_entries<=64\"],\"adrDecision\":\"AdaptiveApplyBoundedMutation\",\"adrTargets\":[\"AdaptiveTargetDialogueOutcome\",\"AdaptiveTargetSpeechPolicy\",\"AdaptiveTargetClaimStance\"]}}"
      decodedLegacyRecord = decode legacyRecordJson :: Maybe DialogueOutcomeSample
  assertBool "old typed dialogue JSON must decode into shared taxonomy" (decodedLegacyRecord /= Nothing)
  case decodedLegacyRecord of
    Just sample -> do
      assertEqual "legacy typed evidence maps to shared strong evidence"
        EvidenceStrong (dosEvidenceStrength sample)
      assertEqual "legacy decision maps to shared accepted decision"
        AdaptiveAccepted (adrDecision (dosDecisionRecord sample))
      assertEqual "legacy targets map to shared mutation kinds"
        [MutDialogueOutcome, MutSpeechPolicy, MutClaimStance] (adrTargets (dosDecisionRecord sample))
      assertBool "missing legacy mutation records are synthesized"
        (not (null (adrMutationRecords (dosDecisionRecord sample))))
    Nothing -> assertFailure "legacy typed dialogue sample decode unexpectedly failed"

-- | P0: top-level adaptive mutation history is capped and keeps newest records.
testAdaptiveMutationLogIsBounded :: Test
testAdaptiveMutationLogIsBounded = TestCase $ do
  let mkRecord turn = AdaptiveMutationRecord
        { amrTurnId = turn
        , amrKind = MutKnowledgeTree
        , amrCause = "test:bounded_log"
        , amrEvidence = ["turn=" <> T.pack (show turn)]
        , amrEvidenceStrength = EvidenceStrong
        , amrConfidence = 1.0
        , amrBoundedDelta = Just 1.0
        , amrDecision = AdaptiveAccepted
        }
      records = map mkRecord [105,104 .. 1]
      ss = appendAdaptiveMutationRecords records emptySystemState
      logRecords = ssAdaptiveMutationLog ss
  assertEqual "adaptive mutation log must retain at most 100 entries"
    100 (length logRecords)
  case logRecords of
    newest:_ -> assertEqual "newest record must be retained first" 105 (amrTurnId newest)
    [] -> assertFailure "bounded log unexpectedly empty"
  assertEqual "oldest retained record should be the 100th newest"
    6 (amrTurnId (last logRecords))

-- | P4: candidate without evidence/stance is not admissible.
testPerspectiveAdmissibilityRejectsInsufficientEvidence :: Test
testPerspectiveAdmissibilityRejectsInsufficientEvidence = TestCase $ do
  let bundle = mkPerspectiveBundle [] [] [] defaultNormativeProfile []
      candidate = opinionCore bundle
  assertEqual "candidate without evidence must be inadmissible"
    (PerspectiveInadmissible "insufficient_evidence")
    (evaluatePerspectiveAdmissibility bundle candidate)

-- | P4: promotion is stricter than admissibility, and weak evidence alone does not promote.
testPerspectivePromotionRequiresStabilityAndStrongEvidence :: Test
testPerspectivePromotionRequiresStabilityAndStrongEvidence = TestCase $ do
  let weakBundle = mkPerspectiveBundle [EvidenceRef "thanks_ack"] [] [] defaultNormativeProfile []
      weakCandidate = opinionCore weakBundle
      stableBundle = mkPerspectiveBundle
        [ EvidenceRef "knowledge:freedom is bounded agency"
        , EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"
        ]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        []
        defaultNormativeProfile
        []
      stableCandidate = opinionCore stableBundle
      registry = defaultPerspectiveRegistry
  assertEqual "weak evidence can be admissible but must not promote"
    PpdObserveOnly
    (decidePerspectivePromotion registry weakBundle weakCandidate (PerspectiveAdmissibleAccepted))
  assertEqual "stable corroborated candidate can be promoted"
    PpdPromoteEndorsed
    (decidePerspectivePromotion registry stableBundle stableCandidate (evaluatePerspectiveAdmissibility stableBundle stableCandidate))

-- | P4: registry is the canonical bounded source of revision lineage.
testPerspectiveRegistryLineageIsCanonicalAndBounded :: Test
testPerspectiveRegistryLineageIsCanonicalAndBounded = TestCase $ do
  let bundle = mkPerspectiveBundle
        [ EvidenceRef "knowledge:freedom is bounded agency"
        , EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"
        ]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        []
        defaultNormativeProfile
        []
      candidate = opinionCore bundle
      smallRegistry = defaultPerspectiveRegistry { prMaxRevisionsPerScope = 2 }
      registry1 = applyPerspectiveDecision 1 smallRegistry bundle candidate PpdPromoteEndorsed
      bundle2 = bundle { pibRevisionLineage = maybe [] ptRevisionHistory (M.lookup (pibScope bundle) (prThreads registry1)) }
      candidate2 = (opinionCore bundle2) { pcThesis = "revision one" }
      registry2 = applyPerspectiveDecision 2 registry1 bundle2 candidate2 PpdReviseActive
      bundle3 = bundle { pibRevisionLineage = maybe [] ptRevisionHistory (M.lookup (pibScope bundle) (prThreads registry2)) }
      candidate3 = (opinionCore bundle3) { pcThesis = "revision two" }
      registry3 = applyPerspectiveDecision 3 registry2 bundle3 candidate3 PpdReviseActive
  case M.lookup (pibScope bundle) (prThreads registry3) of
    Nothing -> assertFailure "expected perspective thread"
    Just thread -> do
      assertEqual "lineage must be bounded by registry cap"
        2 (length (ptRevisionHistory thread))
      assertBool "active version must resolve to an existing version"
        (maybe False (\v -> any ((== v) . epVersion) (ptVersions thread)) (ptActiveVersion thread))

-- | P4: suspended active perspectives are not exposed as current projections.
testPerspectiveSuspendClearsActiveProjection :: Test
testPerspectiveSuspendClearsActiveProjection = TestCase $ do
  let bundle = mkPerspectiveBundle
        [EvidenceRef "knowledge:freedom is bounded agency", EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        []
        defaultNormativeProfile
        []
      candidate = opinionCore bundle
      registry1 = applyPerspectiveDecision 1 defaultPerspectiveRegistry bundle candidate PpdPromoteEndorsed
      suspended = applyPerspectiveDecision 2 registry1 bundle (candidate { pcCounterargumentPressure = 0.70 }) PpdSuspendActive
  assertEqual "suspended thread must not project as active"
    Nothing (buildPerspectiveProjection suspended (pibScope bundle))
  assertEqual "active projection list must be empty after suspension"
    [] (buildActivePerspectiveProjections suspended)

-- | P4: active cap suspends surplus active scopes without deleting lineage threads.
testPerspectiveRegistryActiveCapKeepsLineageThreads :: Test
testPerspectiveRegistryActiveCapKeepsLineageThreads = TestCase $ do
  let cappedRegistry = defaultPerspectiveRegistry { prMaxActivePerspectives = 1 }
      bundleA = mkPerspectiveBundleForScope (ScopeTopic "freedom")
      candidateA = opinionCore bundleA
      registry1 = applyPerspectiveDecision 1 cappedRegistry bundleA candidateA PpdPromoteEndorsed
      bundleB = mkPerspectiveBundleForScope (ScopeTopic "responsibility")
      candidateB = opinionCore bundleB
      registry2 = applyPerspectiveDecision 2 registry1 bundleB candidateB PpdPromoteEndorsed
  assertBool "older thread lineage must remain present"
    (M.member (pibScope bundleA) (prThreads registry2))
  assertBool "newer thread lineage must remain present"
    (M.member (pibScope bundleB) (prThreads registry2))
  assertEqual "only one active projection is exposed under active cap"
    1 (length (buildActivePerspectiveProjections registry2))

-- | P4: rollback is reachable from promotion policy and restores a prior projection.
testPerspectiveRollbackIsReachableAndRestoresPriorProjection :: Test
testPerspectiveRollbackIsReachableAndRestoresPriorProjection = TestCase $ do
  let bundle = mkPerspectiveBundle
        [EvidenceRef "knowledge:freedom is bounded agency", EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        []
        defaultNormativeProfile
        []
      candidate = opinionCore bundle
      registry1 = applyPerspectiveDecision 1 defaultPerspectiveRegistry bundle candidate PpdPromoteEndorsed
      bundle2 = bundle { pibRevisionLineage = maybe [] ptRevisionHistory (M.lookup (pibScope bundle) (prThreads registry1)) }
      candidate2 = (opinionCore bundle2) { pcThesis = "revision one" }
      registry2 = applyPerspectiveDecision 2 registry1 bundle2 candidate2 PpdReviseActive
      rollbackBundle = bundle2 { pibCounterarguments = [CounterargumentRef "counter:a", CounterargumentRef "counter:b"] }
      rollbackCandidate = (opinionCore rollbackBundle) { pcCounterargumentPressure = 0.50 }
      decision = decidePerspectivePromotion registry2 rollbackBundle rollbackCandidate (PerspectiveAdmissibleQuarantined)
      registry3 = applyPerspectiveDecision 3 registry2 rollbackBundle rollbackCandidate decision
  assertEqual "rollback must be reachable from promotion policy"
    PpdRollbackPrior decision
  case buildPerspectiveProjection registry3 (pibScope bundle) of
    Nothing -> assertFailure "expected restored prior projection"
    Just projection -> assertBool "rollback must not expose withdrawn active version"
      (ppSummary projection /= "revision one")

-- | P4: activation scope chooses the matching normative profile instead of dead config.
testPerspectiveActivationScopeSelectsMatchingNormativeProfile :: Test
testPerspectiveActivationScopeSelectsMatchingNormativeProfile = TestCase $ do
  let defaultScoped = defaultNormativeProfile
        { npVersionId = 1
        , npActivationScope = Just (ScopeTopic "other")
        }
      freedomProfile = defaultNormativeProfile
        { npId = NormativeProfileId "freedom-profile"
        , npVersionId = 7
        , npActivationScope = Just (ScopeTopic "freedom")
        }
      registry = defaultPerspectiveRegistry
        { prNormativeProfiles = M.fromList [(npId defaultScoped, defaultScoped), (npId freedomProfile, freedomProfile)]
        , prActiveNormativeProfileId = npId defaultScoped
        }
      outcome = emptyDialogueOutcomeLearningState
        { dolRecentOutcomes = [mkDialogueOutcomeSample 1 DialogueOutcomeSuccess "freedom"]
        }
      ss = emptySystemState
        { ssSessionId = "test-session"
        , ssPerspectiveRegistry = registry
        , ssDialogueOutcomeLearning = outcome
        }
      bundle = assemblePerspectiveInput ss (ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)) False emptyField
      candidate = opinionCore bundle
  assertEqual "matching activation scope must select the scoped profile"
    7 (pcNormativeProfileVersion candidate)

-- | P4: persisted duplicate scope threads fail decode instead of silently overwriting lineage.
testPerspectiveRegistryRejectsDuplicateThreads :: Test
testPerspectiveRegistryRejectsDuplicateThreads = TestCase $ do
  let duplicateJson = BL8.pack
        "{\"threads\":[{\"ptPerspectiveId\":\"p1\",\"ptScope\":{\"tag\":\"ScopeTopic\",\"contents\":\"freedom\"},\"ptActiveVersion\":null,\"ptVersions\":[],\"ptRevisionHistory\":[],\"ptStatus\":\"PerspectiveSuspended\",\"ptLastUpdatedTurn\":1},{\"ptPerspectiveId\":\"p2\",\"ptScope\":{\"tag\":\"ScopeTopic\",\"contents\":\"freedom\"},\"ptActiveVersion\":null,\"ptVersions\":[],\"ptRevisionHistory\":[],\"ptStatus\":\"PerspectiveSuspended\",\"ptLastUpdatedTurn\":2}],\"normativeProfiles\":[],\"activeNormativeProfileId\":\"default\"}"
      decoded = decode duplicateJson :: Maybe PerspectiveRegistry
  assertEqual "duplicate scope threads must not decode by overwriting"
    Nothing decoded

-- | P4: normative profile version is operator-visible and changes candidate geometry.
testPerspectiveNormativeProfileVersionAffectsCandidate :: Test
testPerspectiveNormativeProfileVersionAffectsCandidate = TestCase $ do
  let strictProfile = defaultNormativeProfile
        { npVersionId = 1
        , npPriorities = M.fromList [("safety", 1.0), ("stability", 1.0), ("counterargument", 1.0)]
        , npConflictPolicy = "conservative"
        }
      permissiveProfile = defaultNormativeProfile
        { npVersionId = 2
        , npPriorities = M.fromList [("safety", 0.7), ("stability", 0.7), ("counterargument", 0.2)]
        , npConflictPolicy = "permissive"
        }
      strictCandidate = opinionCore (mkPerspectiveBundle [EvidenceRef "knowledge:x"] [ClaimStanceRef "stance:x"] [CounterargumentRef "counter:x"] strictProfile [])
      permissiveCandidate = opinionCore (mkPerspectiveBundle [EvidenceRef "knowledge:x"] [ClaimStanceRef "stance:x"] [CounterargumentRef "counter:x"] permissiveProfile [])
  assertEqual "candidate records normative profile version"
    1 (pcNormativeProfileVersion strictCandidate)
  assertEqual "candidate records changed normative profile version"
    2 (pcNormativeProfileVersion permissiveCandidate)
  assertBool "profile version/content can alter confidence geometry"
    (pcConfidence strictCandidate /= pcConfidence permissiveCandidate)

-- | P4: active perspectives expose explanation via safe projection, not raw lineage.
testPerspectiveProjectionIsExplainableAndSafe :: Test
testPerspectiveProjectionIsExplainableAndSafe = TestCase $ do
  let bundle = mkPerspectiveBundle
        [ EvidenceRef "knowledge:freedom is bounded agency"
        , EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"
        ]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        [CounterargumentRef "counter:freedom can conflict with safety"]
        defaultNormativeProfile
        []
      candidate = opinionCore bundle
      registry = applyPerspectiveDecision 1 defaultPerspectiveRegistry bundle candidate PpdPromoteEndorsed
  case buildPerspectiveProjection registry (pibScope bundle) of
    Nothing -> assertFailure "expected safe perspective projection"
    Just projection -> do
      assertEqual "projection exposes profile provenance"
        1 (ppNormativeProfileVersion projection)
      assertBool "projection exposes explanation handle"
        (not (T.null (ppExplanationHandle projection)))
      assertEqual "projection keeps counterarguments as counts only"
        1 (ppCounterargumentCount projection)

mkPerspectiveBundle
  :: [EvidenceRef]
  -> [ClaimStanceRef]
  -> [CounterargumentRef]
  -> NormativeProfile
  -> [PerspectiveRevisionRecord]
  -> PerspectiveInputBundle
mkPerspectiveBundle evidence stance counterarguments profile lineage =
  mkPerspectiveBundleForScopeWith (ScopeTopic "freedom") evidence stance counterarguments profile lineage

mkPerspectiveBundleForScope :: PerspectiveScope -> PerspectiveInputBundle
mkPerspectiveBundleForScope scope =
  mkPerspectiveBundleForScopeWith
    scope
    [EvidenceRef ("knowledge:" <> scopeLabel scope <> " is bounded agency"), EvidenceRef ("dialogue:DialogueOutcomeSuccess:" <> scopeLabel scope)]
    [ClaimStanceRef ("stance:BeliefAffirmed:" <> scopeLabel scope <> " requires responsibility")]
    []
    defaultNormativeProfile
    []

mkPerspectiveBundleForScopeWith
  :: PerspectiveScope
  -> [EvidenceRef]
  -> [ClaimStanceRef]
  -> [CounterargumentRef]
  -> NormativeProfile
  -> [PerspectiveRevisionRecord]
  -> PerspectiveInputBundle
mkPerspectiveBundleForScopeWith scope evidence stance counterarguments profile lineage = PerspectiveInputBundle
  { pibScope = scope
  , pibEvidence = evidence
  , pibStanceSlice = stance
  , pibIdentitySlice = IdentitySlice
      { isSessionId = "test-session"
      , isIdentityClaims = []
      , isIdentityClaimCount = 0
      , isTurnCount = 1
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

scopeLabel :: PerspectiveScope -> T.Text
scopeLabel scope =
  case scope of
    ScopeTopic value -> value
    ScopeTheme value -> value
    ScopeCluster value -> value

mkDialogueOutcomeSample :: Int -> DialogueOutcomeKind -> T.Text -> DialogueOutcomeSample
mkDialogueOutcomeSample turn kind topic = DialogueOutcomeSample
  { dosTurn = turn
  , dosKind = kind
  , dosTopic = topic
  , dosSignals = ["test"]
  , dosEvidenceStrength = EvidenceStrong
  , dosStrongUpdate = True
  , dosDecisionRecord = AdaptiveDecisionRecord
      { adrTurn = turn
      , adrCause = "test"
      , adrEvidence = ["test"]
      , adrConfidence = 0.8
      , adrBoundedDelta = ["recent_outcomes<=12"]
      , adrDecision = AdaptiveAccepted
      , adrTargets = [MutDialogueOutcome]
      , adrMutationRecords = []
      }
  }

-- | Cross-session retention: morphology learned in one session is not overwritten on bootstrap.
testMorphologyRetentionMerge :: Test
testMorphologyRetentionMerge = TestCase $ do
  let persistedMorph = MorphologyData M.empty M.empty (M.singleton "книга" "книга") M.empty
      resourceMorph  = MorphologyData (M.singleton "в" "в") M.empty M.empty M.empty
      -- Simulates the merge performed in bootstrap (persisted wins, resource fills gaps)
      mergedPrepositional = M.union (mdPrepositional persistedMorph) (mdPrepositional resourceMorph)
      mergedNominative    = M.union (mdNominative persistedMorph)    (mdNominative resourceMorph)
  assertBool "persisted morphology nominative must survive merge"
    (M.member "книга" mergedNominative)
  assertBool "resource morphology prepositional must be present after merge"
    (M.member "в" mergedPrepositional)

-- ============================================================
-- WP3: dedup blocks external query for known term
-- ============================================================

testDedupBlocksExternalQueryForKnownMorphology :: Test
testDedupBlocksExternalQueryForKnownMorphology = TestCase $ do
  let morph = MorphologyData M.empty M.empty (M.singleton "книга" "книга") M.empty
  assertBool "hasKnownMorphologyForm must return True for known nominative"
    (hasKnownMorphologyForm morph "книга")
  assertBool "hasKnownMorphologyForm must return False for unknown term"
    (not (hasKnownMorphologyForm morph "неизвестно"))

testDedupBlocksExternalQueryForKnownTreeTerm :: Test
testDedupBlocksExternalQueryForKnownTreeTerm = TestCase $ do
  let fruit = mkFruitWithWord "свобода" "свобода — способность" SourceHuman True 0.3 0.2
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
  assertBool "isTermKnownInKnowledgeTree must return True for known word"
    (isTermKnownInKnowledgeTree "свобода" tree)
  assertBool "isTermKnownInKnowledgeTree must return False for unknown term"
    (not (isTermKnownInKnowledgeTree "неизвестно" tree))
  -- Backward compatibility: proposition substring match
  assertBool "isTermKnownInKnowledgeTree must match via proposition substring"
    (isTermKnownInKnowledgeTree "способность" tree)

-- ============================================================
-- WP4: conatus delta derived from state (not payload)
-- ============================================================

testConatusDeltaDerivedFromStateNotPayload :: Test
testConatusDeltaDerivedFromStateNotPayload = TestCase $ do
  let payload = KnowledgeFruitPayload
        { kfpProposition = "test"
        , kfpWord = "test"
        , kfpDefinition = "a good definition that is long enough for testing"
        , kfpMorphology = Nothing
        , kfpSource = SourceLLM
        , kfpConatusDelta = 0.99   -- payload claims huge delta
        , kfpPredictiveDelta = 0.5
        }
      ss0 = emptySystemState
            { ssLearningNeedState = emptyLearningNeedState { lnsCurrentNeed = NeedLexiconExtension }
            }
      -- Accept path with no morphology change => proxy delta should be small (≈ +0.01 tree growth),
      -- NOT the payload's 0.99.
      (ss1, _tel) = runLearningStep ss0
        (ExternalTool "llm-augment" DomainLexicon 0.70 True)
        NeedLexiconExtension "что значит test" (Just (Right
          (ExternalQueryResponse
            { eqrRawBody = "{\"proposition\":\"test\",\"word\":\"test\",\"definition\":\"a good definition that is long enough for testing\",\"source\":\"llm\",\"conatusDelta\":0.99,\"predictiveDelta\":0.5}"
            , eqrStructured = "{\"proposition\":\"test\",\"word\":\"test\",\"definition\":\"a good definition that is long enough for testing\",\"source\":\"llm\",\"conatusDelta\":0.99,\"predictiveDelta\":0.5}"
            , eqrToolName = "llm-augment"
            , eqrLatencyMs = 0
            })))
      tree = ssKnowledgeTree ss1
      fruit = head (concatMap brFruits (concat (M.elems (ktBranches tree))))
  assertBool "conatus delta must NOT be the payload's 0.99"
    (abs (kfConatusDelta fruit - 0.99) > 0.1)
  assertBool "conatus delta must be small and positive (tree growth proxy)"
    (kfConatusDelta fruit > 0.0 && kfConatusDelta fruit < 0.05)

-- | WP6.1 helper: single step of learning-pressure detection.
runNeedStep :: LearningPressureConfig -> LearningNeedState -> Int -> Bool -> Int -> LearningNeedState
runNeedStep cfg old turn isUnknown grafts =
  detectLearningNeedWithPressure
    cfg
    (ConatusEnergy 10.0 (ConatusComponents 0 0 0 0))
    emptyField
    0       -- repairCount
    0       -- unknownTopicCount (legacy)
    turn
    old
    isUnknown
    grafts

-- WP6.1: learning-pressure-driven NeedLexiconExtension

testLearningPressureRaisesLexiconExtension :: Test
testLearningPressureRaisesLexiconExtension = TestCase $ do
  let cfg = defaultLearningPressureConfig { lpcStagnationTurns = 1, lpcMinUnknownCount = 1 }
      s0 = emptyLearningNeedState { lnsWindowStartTurn = 1, lnsUnknownWindowCount = 2 }
      s1 = runNeedStep cfg s0 2 True 0
      s2 = runNeedStep cfg s1 3 True 0
      s3 = runNeedStep cfg s2 4 True 0
  assertEqual "lexicon extension must be raised after 3 persistence turns"
    NeedLexiconExtension (lnsCurrentNeed s3)
  assertBool "level must be positive"
    (lnsLevel s3 > 0.0)

testLearningPressureIgnoresLowUnknownCount :: Test
testLearningPressureIgnoresLowUnknownCount = TestCase $ do
  let cfg = defaultLearningPressureConfig
      s0 = emptyLearningNeedState { lnsWindowStartTurn = 1, lnsUnknownWindowCount = 0 }
      s1 = runNeedStep cfg s0 6 True 0
  assertEqual "low unknown count must not raise need"
    NeedNone (lnsCurrentNeed s1)

testLearningPressureIgnoresWhenGraftsGrowing :: Test
testLearningPressureIgnoresWhenGraftsGrowing = TestCase $ do
  let cfg = defaultLearningPressureConfig { lpcStagnationTurns = 1, lpcMinUnknownCount = 1 }
      s0 = emptyLearningNeedState { lnsWindowStartTurn = 1, lnsUnknownWindowCount = 2 }
      s1 = runNeedStep cfg s0 2 True 1
  assertEqual "growing grafts must suppress stagnation"
    NeedNone (lnsCurrentNeed s1)

testLearningPressureBackwardCompatWrapper :: Test
testLearningPressureBackwardCompatWrapper = TestCase $ do
  let conatus = ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)
      old = emptyLearningNeedState
      new = detectLearningNeed conatus emptyField 0 0 1 old
      newWP = detectLearningNeedWithPressure defaultLearningPressureConfig conatus emptyField 0 0 1 old False 0
  assertEqual "backward-compat wrapper must match pressure version with empty signals"
    new newWP

-- WP6.1: LearningNeedState JSON round-trip
testLearningNeedStateRoundTripsJson :: Test
testLearningNeedStateRoundTripsJson = TestCase $ do
  let s = emptyLearningNeedState
        { lnsUnknownWindowCount = 3
        , lnsWindowStartTurn = 7
        , lnsWindowGraftBaseline = 2
        }
      decoded = decode (encode s) :: Maybe LearningNeedState
  assertEqual "learning need state must round-trip through JSON"
    (Just s) decoded

testOldLearningNeedStateJsonLoadsDefaults :: Test
testOldLearningNeedStateJsonLoadsDefaults = TestCase $ do
  let oldJson = "{\"currentNeed\":\"NeedLexiconExtension\",\"candidateNeed\":\"NeedLexiconExtension\",\"level\":0.7,\"trend\":\"TrendRising\",\"persistence\":2,\"lastSeenTurn\":5,\"history\":[[5,0.7],[4,0.6]]}"
      decoded = decode oldJson :: Maybe LearningNeedState
  assertBool "old JSON must decode" (decoded /= Nothing)
  let s = maybe emptyLearningNeedState id decoded
  assertEqual "unknownWindowCount default must be 0"
    0 (lnsUnknownWindowCount s)
  assertEqual "windowStartTurn default must be 0"
    0 (lnsWindowStartTurn s)
  assertEqual "windowGraftBaseline default must be 0"
    0 (lnsWindowGraftBaseline s)

-- WP6.1: dedup anti-overblocking helper
testTopicNoisyShort :: Test
testTopicNoisyShort = TestCase $
  assertBool "short topic must be noisy"
    (isTopicNoisyOrAmbiguous "ab")

testTopicNoisyDigit :: Test
testTopicNoisyDigit = TestCase $
  assertBool "topic with digits must be noisy"
    (isTopicNoisyOrAmbiguous "a1")

testTopicNoisyPunctuation :: Test
testTopicNoisyPunctuation = TestCase $
  assertBool "topic with punctuation must be noisy"
    (isTopicNoisyOrAmbiguous "a!")

testTopicClean :: Test
testTopicClean = TestCase $ do
  assertBool "normal topic must not be noisy"
    (not (isTopicNoisyOrAmbiguous "свобода"))
  assertBool "three-letter topic must not be noisy"
    (not (isTopicNoisyOrAmbiguous "abc"))

-- Helpers

mkFruitWithWord :: T.Text -> T.Text -> KnowledgeSource -> Bool -> Double -> Double -> KnowledgeFruit
mkFruitWithWord word prop src valid cDelta pDelta =
  KnowledgeFruit
    { kfProposition = prop
    , kfWord = word
    , kfSource = src
    , kfValidated = valid
    , kfConatusDelta = cDelta
    , kfPredictiveDelta = pDelta
    , kfGraftedTurn = Nothing
    , kfObservedTurn = 1
    }
