{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.AutonomousSafety
  ( autonomousSafetyTests
  ) where

import Control.Concurrent.STM (atomically, newTQueue)
import qualified Data.Map.Strict as M
import Data.IORef (newIORef, readIORef)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime(..))
import qualified Data.Text as T
import System.Directory (doesFileExist)
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( LearningTask(..)
  , NetworkUpdateEvent(..)
  , autonomousApplyLLMResponse
  , buildAtomMorphology
  )
import QxFx0.Learning.Metrics (LearningMetrics(..), emptyLearningMetrics)
import QxFx0.Learning.CircuitBreaker
  ( dequeueBreakerCloseQueue
  , enqueueBreakerSideQueue
  , newPendingBreakerCloseQueue
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  , applyAutonomousEventBatchForTest
  )
import QxFx0.Runtime.AutonomousSmoke
  ( newSemanticEdges
  , resolveAutonomousSmokeDbPath
  , validateAutonomousSmokeDbPath
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
import Test.Support (freshTestDbPath, removeIfExists, withEnvVar)

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
  , seNamespace = Just NamespaceSessionLocal
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
  , nueEdges = edges
  , nuePromptHash = Nothing
  , nueResponseHash = Nothing
  , nueModel = Nothing
  , nueParserDecision = Nothing
  , nueAdmissionDecision = Just "worker_candidate_admitted"
  , nueEvidenceSource = Nothing
  , nueCompetitiveAudit = Nothing
  , nueCorroborationPriority = Nothing
  , nueCorroborationTaskId = Nothing
  , nueApplyToken = Nothing
  , nueTimestamp = UTCTime (fromGregorian 2026 7 11) 0
  }

mkHandles :: IO AutonomousHandles
mkHandles = do
  updates <- atomically newTQueue
  metrics <- newIORef emptyLearningMetrics
  pure AutonomousHandles
    { ahQueue = Nothing
    , ahUpdateQueue = Just updates
    , ahWorkerThread = Nothing
    , ahPendingBreakerQueue = Nothing
    , ahQuarantineDB = Nothing
    , ahMetricsRef = Just metrics
    , ahNetworkOwner = Nothing
    , ahAuditThread = Nothing
    , ahApplyThread = Nothing
    , ahSessionId = Just "test-session"
    , ahEnabled = True
    }

testProvenanceRuntimeLLM :: Test
testProvenanceRuntimeLLM = TestLabel "runtime LLM edges use ProvenanceRuntimeLLM" $ TestCase $ do
  handles <- mkHandles
  let resp = ExternalQueryResponse
        { eqrRawBody = "свобода | связана | выбор | relatedto\n"
        , eqrStructured = ""
        , eqrToolName = "test"
        , eqrLatencyMs = 0
        }
      parsed = autonomousApplyLLMResponse atomStore (buildAtomMorphology atomStore) NeedKeywordEnrichment resp
  net <- applyAutonomousEventBatchForTest handles (mkNetwork []) [mkEvent (M.elems (snEdges parsed))]
  assertBool "all admitted edges are runtime LLM provenance" $
    all ((== ProvenanceRuntimeLLM) . seProvenance) (M.elems (snEdges net))

testContradictionQuarantinesLowerAuthority :: Test
testContradictionQuarantinesLowerAuthority = TestLabel "contradiction keeps authoritative edge and quarantines runtime edge" $ TestCase $ do
  handles <- mkHandles
  let existing = mkEdge ProvenanceCurated RelPresupposes 0.9 1
      incoming = mkEdge ProvenanceRuntimeLLM RelNegates 0.95 1
  net <- applyAutonomousEventBatchForTest handles (mkNetwork [existing]) [mkEvent [incoming]]
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
  net <- applyAutonomousEventBatchForTest handles (mkNetwork [existing]) [mkEvent [incoming]]
  case M.lookup ("свобода", "выбор") (snEdges net) of
    Nothing -> assertFailure "incoming edge was not inserted"
    Just applied -> do
      assertEqual "incoming edge replaces existing payload" (seWeight incoming) (seWeight applied)
      assertEqual "runtime admission records lineage" True (maybe False (not . null) (seLineage applied))

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

testMetricsStartEmpty :: Test
testMetricsStartEmpty = TestLabel "LearningMetrics start empty" $ TestCase $ do
  assertEqual "accepted count" 0 (lmEdgesAccepted emptyLearningMetrics)
  assertEqual "quarantined count" 0 (lmEdgesQuarantined emptyLearningMetrics)

testSmokeDbRequiresExplicitPath :: Test
testSmokeDbRequiresExplicitPath = TestLabel "autonomous smoke DB path is explicit" $ TestCase $
  withEnvVar "QXFX0_AUTONOMOUS_SMOKE_DB" Nothing $ do
    result <- resolveAutonomousSmokeDbPath
    case result of
      Left err -> assertBool "error names the dedicated environment variable"
        ("QXFX0_AUTONOMOUS_SMOKE_DB" `T.isInfixOf` err)
      Right path -> assertFailure ("unexpected smoke DB path: " <> path)

testSmokeDbBoundary :: Test
testSmokeDbBoundary = TestLabel "autonomous smoke DB stays under /tmp and differs from normal DB" $ TestCase $ do
  assertEqual "disposable path accepted"
    (Right "/tmp/qxfx0-autonomous-smoke.db")
    (validateAutonomousSmokeDbPath "/var/lib/qxfx0/qxfx0.db" "/tmp/qxfx0-autonomous-smoke.db")
  assertLeft "non-/tmp path rejected"
    (validateAutonomousSmokeDbPath "/var/lib/qxfx0/qxfx0.db" "/var/tmp/qxfx0-smoke.db")
  assertLeft "traversal out of /tmp rejected"
    (validateAutonomousSmokeDbPath "/var/lib/qxfx0/qxfx0.db" "/tmp/../var/lib/qxfx0/smoke.db")
  assertLeft "normal resolved DB rejected"
    (validateAutonomousSmokeDbPath "/tmp/qxfx0.db" "/tmp/./qxfx0.db")

testSmokePersistsOnlyNewEdgeKeys :: Test
testSmokePersistsOnlyNewEdgeKeys = TestLabel "autonomous smoke selects only genuinely new edges" $ TestCase $ do
  let existing = mkEdge ProvenanceCurated RelPresupposes 0.9 1
      replacement = existing { seWeight = 0.1, seConfidence = 0.1 }
      added = existing
        { seFrom = "истина"
        , seTo = "проверка"
        , seProvenance = ProvenanceRuntimeLLM
        }
      baseline = mkNetwork [existing]
      discovered = mkNetwork [replacement, added]
  assertEqual "existing replacement is excluded" [added]
    (newSemanticEdges baseline discovered)

testSmokeDbMustBeFresh :: Test
testSmokeDbMustBeFresh = TestLabel "autonomous smoke refuses an existing /tmp database" $ TestCase $ do
  path <- freshTestDbPath "qxfx0_existing_autonomous_smoke.db"
  writeFile path "occupied"
  result <- withEnvVar "QXFX0_AUTONOMOUS_SMOKE_DB" (Just path) resolveAutonomousSmokeDbPath
  removeIfExists path
  case result of
    Left err -> assertBool "freshness rejection is explicit" ("must be fresh" `T.isInfixOf` err)
    Right accepted -> assertFailure ("existing smoke DB was accepted: " <> accepted)

testSmokeDbIsReservedExclusively :: Test
testSmokeDbIsReservedExclusively = TestLabel "autonomous smoke atomically reserves its fresh database" $ TestCase $ do
  let path = "/tmp/qxfx0_reserved_autonomous_smoke_test.db"
  removeIfExists path
  result <- withEnvVar "QXFX0_AUTONOMOUS_SMOKE_DB" (Just path) resolveAutonomousSmokeDbPath
  exists <- doesFileExist path
  removeIfExists path
  assertEqual "fresh smoke path is accepted and reserved" (Right path) result
  assertBool "exclusive reservation creates the database inode" exists

assertLeft :: String -> Either a b -> Assertion
assertLeft _ (Left _) = pure ()
assertLeft label (Right _) = assertFailure label

autonomousSafetyTests :: [Test]
autonomousSafetyTests =
  [ testProvenanceRuntimeLLM
  , testContradictionQuarantinesLowerAuthority
  , testSameAuthorityReplacement
  , testPendingBreakerCloseQueueBound
  , testMetricsStartEmpty
  , testSmokeDbRequiresExplicitPath
  , testSmokeDbBoundary
  , testSmokePersistsOnlyNewEdgeKeys
  , testSmokeDbMustBeFresh
  , testSmokeDbIsReservedExclusively
  ]
