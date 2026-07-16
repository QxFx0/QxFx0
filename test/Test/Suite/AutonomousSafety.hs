{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.AutonomousSafety
  ( autonomousSafetyTests
  ) where

import Control.Concurrent.STM (atomically, newTQueue)
import Data.Aeson (Value(..), toJSON)
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Map.Strict as M
import Data.IORef (newIORef, readIORef)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime(..))
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( LearningMetrics(..)
  , LearningTask(..)
  , NetworkUpdateEvent(..)
  , ParseStatus(..)
  , authorityRank
  , autonomousApplyLLMResponse
  , buildAtomMorphology
  , emptyLearningMetrics
  , incomingWinsByScore
  , isContradictory
  )
import QxFx0.Learning.CircuitBreaker
  ( dequeueBreakerCloseQueue
  , enqueueBreakerSideQueue
  , newPendingBreakerCloseQueue
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  , applyAutonomousEventBatch
  )
import QxFx0.Semantic.Content.AtomStore
  ( RelationType(..)
  , atomStore
  )
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )
import QxFx0.Types.ExternalQuery (ExternalQueryResponse(..))

mkEdge :: EdgeProvenance -> RelationType -> Double -> Int -> SemanticEdge
mkEdge prov rel conf cooc = SemanticEdge
  { seFrom = "свобода"
  , seTo = "выбор"
  , seWeight = conf
  , seCoOccurrence = cooc
  , seSource = ExplicitEdge
  , seRelationType = Just rel
  , seDomain = Nothing
  , seTemporalScope = Nothing
  , seVerb = Nothing
  , seRationale = Nothing
  , seCounter = Nothing
  , seSynthesis = Nothing
  , seConfidence = conf
  , seProvenance = prov
  , seNamespace = NamespaceSessionLocal
  , seLineage = Nothing
  }

mkNetwork :: [SemanticEdge] -> SemanticNetwork
mkNetwork edges = SemanticNetwork
  { snNodes = mempty
  , snEdges = M.fromList [((seFrom e, seTo e), e) | e <- edges]
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = mempty
  }

mkEvent :: [SemanticEdge] -> NetworkUpdateEvent
mkEvent edges = NetworkUpdateEvent
  { nueTopic = "свобода"
  , nueRequestId = "test:m4"
  , nueSourceTopic = Just "свобода"
  , nueEdges = edges
  , nueParseStatus = ParseOk
  , nueRawAccepted = length edges
  , nueRawRejected = 0
  , nueProvenance = ProvenanceRuntimeLLM
  , nuePromptHash = Nothing
  , nueResponseHash = Nothing
  , nueTimestamp = UTCTime (fromGregorian 2026 7 11) 0
  }

mkHandles :: IO AutonomousHandles
mkHandles = do
  updates <- atomically newTQueue
  metrics <- newIORef emptyLearningMetrics
  pure AutonomousHandles
    { ahQueue = Nothing
    , ahUpdateQueue = Just updates
    , ahPendingBreakerQueue = Nothing
    , ahQuarantineDB = Nothing
    , ahMetricsRef = Just metrics
    , ahEnabled = True
    }

testProvenanceRuntimeLLM :: Test
testProvenanceRuntimeLLM = TestLabel "runtime LLM edges use ProvenanceRuntimeLLM" $ TestCase $ do
  let resp = ExternalQueryResponse
        { eqrRawBody = "свобода | связана | выбор | relatedto\n"
        , eqrStructured = ""
        , eqrToolName = "test"
        , eqrLatencyMs = 0
        }
      net = autonomousApplyLLMResponse atomStore (buildAtomMorphology atomStore) NeedKeywordEnrichment resp
  assertBool "all admitted edges are runtime LLM provenance" $
    all ((== ProvenanceRuntimeLLM) . seProvenance) (M.elems (snEdges net))

testAuthorityRankOrdering :: Test
testAuthorityRankOrdering = TestLabel "authorityRank orders runtime LLM below curated" $ TestCase $ do
  assertEqual "curated rank" 4 (authorityRank ProvenanceCurated)
  assertEqual "runtime rank" 1 (authorityRank ProvenanceRuntimeLLM)

testContradictionQuarantinesLowerAuthority :: Test
testContradictionQuarantinesLowerAuthority = TestLabel "contradiction keeps authoritative edge and quarantines runtime edge" $ TestCase $ do
  handles <- mkHandles
  let existing = mkEdge ProvenanceCurated RelPresupposes 0.9 1
      incoming = mkEdge ProvenanceRuntimeLLM RelNegates 0.95 1
  net <- applyAutonomousEventBatch handles (mkNetwork [existing]) [mkEvent [incoming]]
  assertEqual "existing edge preserved" (Just existing) (M.lookup ("свобода", "выбор") (snEdges net))
  case ahMetricsRef handles of
    Nothing -> assertFailure "missing metrics ref"
    Just ref -> do
      metrics <- readIORef ref
      assertEqual "one quarantined edge" 1 (lmEdgesQuarantined metrics)

testSameAuthorityReplacement :: Test
testSameAuthorityReplacement = TestLabel "same-authority higher score replaces existing" $ TestCase $ do
  handles <- mkHandles
  let existing = mkEdge ProvenanceRuntimeLLM RelRelatedTo 0.4 1
      incoming = mkEdge ProvenanceRuntimeLLM RelRelatedTo 0.7 1
  assertBool "incoming wins by score" (incomingWinsByScore incoming existing)
  net <- applyAutonomousEventBatch handles (mkNetwork [existing]) [mkEvent [incoming]]
  assertEqual "incoming edge replaces existing" (Just incoming) (M.lookup ("свобода", "выбор") (snEdges net))

testPendingBreakerCloseQueueBound :: Test
testPendingBreakerCloseQueueBound = TestLabel "PendingBreakerCloseQueue rejects when full" $ TestCase $ do
  q <- newPendingBreakerCloseQueue 1
  let t1 = LearningTask "свобода" 1.0 "r1"
      t2 = LearningTask "истина" 0.5 "r2"
  ok1 <- enqueueBreakerSideQueue q t1
  ok2 <- enqueueBreakerSideQueue q t2
  assertBool "first accepted" ok1
  assertBool "second rejected" (not ok2)
  mt <- dequeueBreakerCloseQueue q
  assertEqual "dequeued first" (Just t1) mt

testObservabilityMetricsJson :: Test
testObservabilityMetricsJson = TestLabel "LearningMetrics serializes expected fields" $ TestCase $ do
  case toJSON emptyLearningMetrics of
    Object obj -> do
      assertBool "queueSize present" (KM.member "queueSize" obj)
      assertBool "edgesQuarantined present" (KM.member "edgesQuarantined" obj)
    _ -> assertFailure "LearningMetrics should encode as object"

autonomousSafetyTests :: [Test]
autonomousSafetyTests =
  [ testProvenanceRuntimeLLM
  , testAuthorityRankOrdering
  , TestLabel "isContradictory detects presupposes/negates" $
      TestCase (assertBool "contradicts" (isContradictory RelPresupposes RelNegates))
  , testContradictionQuarantinesLowerAuthority
  , testSameAuthorityReplacement
  , testPendingBreakerCloseQueueBound
  , testObservabilityMetricsJson
  ]
