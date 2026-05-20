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
  , buildTransportFromEnv
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
  , computeCalibrationSignal
  , emptySignalComponents
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
