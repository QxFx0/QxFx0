{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.LearningLoop
  ( learningLoopTests
  ) where

import Data.Aeson (encode, decode)
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
  )
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
  )
import QxFx0.Types.State (SystemState(..), emptySystemState, ssKnowledgeTree)
import QxFx0.Semantic.Proposition (PropositionType(..))
import QxFx0.Learning.Loop
  ( LearningTelemetry(..)
  , emptyLearningTelemetry
  , runLearningStep
  )
import QxFx0.Learning.Validator
  ( KnowledgeFruitPayload(..)
  , ValidationError(..)
  , validateFruitPayload
  , minDefinitionWords
  )
import QxFx0.Learning.Parser (parseLLMResponseToFruit)
import QxFx0.Learning.Sandbox
  ( SandboxResult(..)
  , SandboxMetrics(..)
  , SandboxRejectReason(..)
  , runSandboxGate
  )
import QxFx0.Bridge.ExternalLLM
  ( queryExternalTool
  , buildTransportFromEnv
  )
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  )
import QxFx0.Semantic.Proposition (PropositionType(..))
import QxFx0.Types.Domain.Atoms (MorphologyData(..))

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
  , testValidatorRejectsJunk
  , testParserValidSchema
  , testParserRejectsMalformed
  , testSandboxRejectsDegrading
  , testSandboxAcceptsImproving
  , testGraftUpdatesTreeAndMorph
  , testTelemetryFieldsPopulated
  , testFailClosedOnExternalError
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
  transport <- buildTransportFromEnv
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
  transport <- buildTransportFromEnv
  result <- queryExternalTool transport
    (ExternalTool "llm-augment" DomainLexicon 0.70 True)
    NeedLexiconExtension
    "fail"
  assertBool "mock transport must return Left for 'fail' query"
    (case result of
       Left (EqeServerError _) -> True
       _ -> False)

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
  assertBool "reject reason must be present"
    (ltRejectReason tel /= Nothing)
