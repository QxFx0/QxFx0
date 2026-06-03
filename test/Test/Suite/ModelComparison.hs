{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.ModelComparison
  ( modelComparisonTests
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Bridge.ExternalLLM
  ( LLMTransport(..)
  , MockTable
  )
import QxFx0.Evaluation.ModelComparison
import QxFx0.Learning.Loop (LearningTelemetry(..), emptyLearningTelemetry)
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  )
import QxFx0.Types.State (emptySystemState)

-- ---------------------------------------------------------------------------
-- JSON bodies for mock responses

perfectBody :: Text
perfectBody =
  "{\"proposition\":\"тест\",\"word\":\"тест\",\"definition\":\"длинное определение для прохождения валидации\",\"source\":\"llm\",\"conatusDelta\":0.3,\"predictiveDelta\":0.2,\"morphology\":{\"gender\":\"feminine\",\"declension\":\"first\"}}"

invalidBody :: Text
invalidBody = "this is not json"

degradingBody :: Text
degradingBody =
  "{\"proposition\":\"тест\",\"word\":\"тест\",\"definition\":\"длинное определение для прохождения валидации\",\"source\":\"llm\",\"conatusDelta\":-0.5,\"predictiveDelta\":0.0,\"morphology\":{\"gender\":\"feminine\",\"declension\":\"first\"}}"

-- | Build a mock table covering all first-word prefixes used by
-- 'deterministicCorpus'.  Each row maps a prefix to a response.
mkModelMockTable :: [(Text, Either ExternalQueryError Text)] -> MockTable
mkModelMockTable overrides =
  let defaults =
        [ ("llm-augment", "NeedLexiconExtension", "что",        Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "тема",       Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "как",        Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "Explore",    Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "fail",       Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "определение",Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "What",       Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "Explain",    Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "Describe",   Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "Analyze",    Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "Discuss",    Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "Evaluate",   Right perfectBody)
        , ("llm-augment", "NeedLexiconExtension", "Interpret",  Right perfectBody)
        ]
      applyOverride (prefix, result) table =
        map (\(t,n,p,r) -> if p == prefix then (t,n,p,result) else (t,n,p,r)) table
  in foldr applyOverride defaults overrides

perfectMockTable :: MockTable
perfectMockTable = mkModelMockTable []

errorMockTable :: MockTable
errorMockTable = mkModelMockTable [("fail", Left (EqeServerError "mock_injected_failure"))]

invalidMockTable :: MockTable
invalidMockTable = mkModelMockTable [("fail", Right invalidBody)]

degradingMockTable :: MockTable
degradingMockTable =
  map (\(t,n,p,_) -> (t,n,p,Right degradingBody))
    (mkModelMockTable [])

-- ---------------------------------------------------------------------------
-- Helpers

mkTurnResult :: ModelId -> Text -> Maybe Text -> Maybe Int -> Either ExternalQueryError ExternalQueryResponse -> TurnResult
mkTurnResult modelId status mReject mGraft outcome =
  TurnResult
    { trModelId     = modelId
    , trPromptIndex = 1
    , trOutcome     = outcome
    , trLatencyMs   = 0
    , trTelemetry   = emptyLearningTelemetry
        { ltValidationStatus = status
        , ltRejectReason     = mReject
        , ltGraftTurn        = mGraft
        }
    }

-- ---------------------------------------------------------------------------
-- Tests

modelComparisonTests :: [Test]
modelComparisonTests =
  [ TestLabel "corpus-length"                         testCorpusLength
  , TestLabel "sequential-perfect"                    testSequentialSessionPerfect
  , TestLabel "sequential-errors"                     testSequentialSessionErrors
  , TestLabel "sequential-invalid"                    testSequentialSessionInvalid
  , TestLabel "sequential-degrading"                  testSequentialSessionDegrading
  , TestLabel "aggregate-session"                     testAggregateSession
  , TestLabel "detect-transport-incidents"            testDetectTransportIncidents
  , TestLabel "detect-validator-incidents"            testDetectValidatorIncidents
  , TestLabel "detect-sandbox-incidents"              testDetectSandboxIncidents
  , TestLabel "detect-request-reject-loop"            testDetectRequestRejectLoop
  , TestLabel "comparison-run-three-models"           testComparisonRunThreeModels
  , TestLabel "interleaved-counts-match-sequential"  testInterleavedCountsMatch
  ]

testCorpusLength :: Test
testCorpusLength = TestCase $
  assertEqual "deterministic corpus must contain 40 prompts" 40 (length deterministicCorpus)

testSequentialSessionPerfect :: Test
testSequentialSessionPerfect = TestCase $ do
  let transport = MockTransport perfectMockTable Nothing
  (_ss, results) <- runModelSession 1 "perfect" transport deterministicCorpus emptySystemState
  assertEqual "all 40 turns must execute" 40 (length results)
  let accepts = filter ((== "accept") . ltValidationStatus . trTelemetry) results
  assertEqual "all 40 must pass parser, validator and sandbox" 40 (length accepts)

testSequentialSessionErrors :: Test
testSequentialSessionErrors = TestCase $ do
  let transport = MockTransport errorMockTable Nothing
  (_ss, results) <- runModelSession 1 "error" transport deterministicCorpus emptySystemState
  let statuses = map (ltValidationStatus . trTelemetry) results
  assertEqual "total turns" 40 (length statuses)
  assertEqual "transport errors on 'fail' prompts" 8 (length (filter (== "transport_error") statuses))
  assertEqual "remaining accepts" 32 (length (filter (== "accept") statuses))
  let incidents = detectIncidents "error" results
  assertEqual "no 3+ consecutive transport errors because fails are spaced" 0 (length incidents)

testSequentialSessionInvalid :: Test
testSequentialSessionInvalid = TestCase $ do
  let transport = MockTransport invalidMockTable Nothing
  (_ss, results) <- runModelSession 1 "invalid" transport deterministicCorpus emptySystemState
  let statuses = map (ltValidationStatus . trTelemetry) results
  assertEqual "total turns" 40 (length statuses)
  assertEqual "parse rejects on 'fail' prompts" 8 (length (filter (== "invalid_response") statuses))
  assertEqual "remaining accepts" 32 (length (filter (== "accept") statuses))

testSequentialSessionDegrading :: Test
testSequentialSessionDegrading = TestCase $ do
  let transport = MockTransport degradingMockTable Nothing
  (_ss, results) <- runModelSession 1 "degrading" transport deterministicCorpus emptySystemState
  let statuses = map (ltValidationStatus . trTelemetry) results
  assertEqual "total turns" 40 (length statuses)
  assertEqual "all 40 sandbox rejects" 40 (length (filter (== "sandbox_reject") statuses))
  let incidents = detectIncidents "degrading" results
  assertBool "at least one incident detected" (length incidents >= 1)

testAggregateSession :: Test
testAggregateSession = TestCase $ do
  let results =
        [ mkTurnResult "m" "accept" Nothing (Just 1) (Right (ExternalQueryResponse "" "" "" 0))
        , mkTurnResult "m" "accept" Nothing (Just 2) (Right (ExternalQueryResponse "" "" "" 0))
        , mkTurnResult "m" "transport_error" (Just "network") Nothing (Left (EqeServerError "mock"))
        , mkTurnResult "m" "invalid_response" (Just "parser") Nothing (Right (ExternalQueryResponse "" "" "" 0))
        , mkTurnResult "m" "validation_reject" (Just "conflict") Nothing (Right (ExternalQueryResponse "" "" "" 0))
        , mkTurnResult "m" "sandbox_reject" (Just "degrading_conatus") Nothing (Right (ExternalQueryResponse "" "" "" 0))
        , mkTurnResult "m" "accept" Nothing (Just 7) (Right (ExternalQueryResponse "" "" "" 0))
        ]
      so = aggregateSession "m" 1 results
  assertEqual "total turns" 7 (soTotalTurns so)
  assertEqual "successes" 3 (soSuccessCount so)
  assertEqual "transport errors" 1 (soTransportErrorCount so)
  assertEqual "parse rejects" 1 (soParseRejectCount so)
  assertEqual "validation rejects" 1 (soValidationRejectCount so)
  assertEqual "sandbox rejects" 1 (soSandboxRejectCount so)
  assertEqual "sandbox accepts" 3 (soSandboxAcceptCount so)

testDetectTransportIncidents :: Test
testDetectTransportIncidents = TestCase $ do
  let results = replicate 5 (mkTurnResult "m" "transport_error" (Just "network") Nothing (Left (EqeServerError "mock")))
      incidents = detectIncidents "m" results
  assertBool "transport incident of length 5 present"
    (any (\case IncidentConsecutiveTransportErrors "m" 1 5 -> True; _ -> False) incidents)

testDetectValidatorIncidents :: Test
testDetectValidatorIncidents = TestCase $ do
  let results = replicate 6 (mkTurnResult "m" "invalid_response" (Just "parser") Nothing (Right (ExternalQueryResponse "" "" "" 0)))
      incidents = detectIncidents "m" results
  assertBool "validator incident of length 6 present"
    (any (\case IncidentConsecutiveValidatorRejects "m" 1 6 -> True; _ -> False) incidents)

testDetectSandboxIncidents :: Test
testDetectSandboxIncidents = TestCase $ do
  let results = replicate 4 (mkTurnResult "m" "sandbox_reject" (Just "degrading_conatus") Nothing (Right (ExternalQueryResponse "" "" "" 0)))
      incidents = detectIncidents "m" results
  assertBool "sandbox incident present"
    (any (\case IncidentConsecutiveSandboxRejects "m" 1 "degrading_conatus" 4 -> True; _ -> False) incidents)

testDetectRequestRejectLoop :: Test
testDetectRequestRejectLoop = TestCase $ do
  let results = replicate 6 (mkTurnResult "m" "sandbox_reject" (Just "degrading_conatus") Nothing (Right (ExternalQueryResponse "" "" "" 0)))
      incidents = detectIncidents "m" results
  assertBool "request-reject-loop incident present"
    (any (\case IncidentRequestRejectLoop "m" 6 -> True; _ -> False) incidents)

testComparisonRunThreeModels :: Test
testComparisonRunThreeModels = TestCase $ do
  let models =
        [ ("glm",      MockTransport perfectMockTable   Nothing)
        , ("deepseek", MockTransport errorMockTable       Nothing)
        , ("kimi",     MockTransport degradingMockTable   Nothing)
        ]
  run <- runComparison "test-run-001" Sequential models deterministicCorpus emptySystemState
  assertEqual "3 model outcomes" 3 (length (crModelOutcomes run))
  let outcomes = crModelOutcomes run
      glm = case filter ((== "glm") . moModelId) outcomes of
        []    -> error "testComparisonRunThreeModels: glm outcome not found"
        (x:_) -> x
      ds  = case filter ((== "deepseek") . moModelId) outcomes of
        []    -> error "testComparisonRunThreeModels: deepseek outcome not found"
        (x:_) -> x
      km  = case filter ((== "kimi") . moModelId) outcomes of
        []    -> error "testComparisonRunThreeModels: kimi outcome not found"
        (x:_) -> x
  assertEqual "glm perfect success rate" 1.0 (moAvgSuccessRate glm)
  assertEqual "glm zero incidents" 0 (moTotalIncidents glm)
  assertBool "deepseek has reduced success rate" (moAvgSuccessRate ds < 1.0)
  assertEqual "deepseek validator accept rate still 1.0 (non-transport responses pass)"
    1.0 (moAvgValidatorAcceptRate ds)
  assertEqual "kimi sandbox pass rate 0.0 (all degraded)" 0.0 (moAvgSandboxPassRate km)
  assertBool "kimi has incidents" (moTotalIncidents km > 0)

testInterleavedCountsMatch :: Test
testInterleavedCountsMatch = TestCase $ do
  let transport = MockTransport perfectMockTable Nothing
  (_ssSeq, seqResults) <- runModelSession 1 "m" transport deterministicCorpus emptySystemState
  interleaved <- runInterleavedSession 1 [("m", transport)] deterministicCorpus emptySystemState
  let intResults = case lookup "m" interleaved of Just r -> r; Nothing -> []
  assertEqual "interleaved count matches sequential" (length seqResults) (length intResults)
  assertEqual "interleaved accept count matches sequential"
    (length (filter ((== "accept") . ltValidationStatus . trTelemetry) seqResults))
    (length (filter ((== "accept") . ltValidationStatus . trTelemetry) intResults))
