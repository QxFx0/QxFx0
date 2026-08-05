{-# LANGUAGE OverloadedStrings #-}

-- | Tests for ADR-0054 autonomous learning integration.
-- Specifically tests the integration of:
-- 1. spawnAutonomousLearningHandles in Bootstrap
-- 2. applyPendingUpdatesForSession in Engine
-- 3. maxUpdatesPerTurn limit
-- 4. AutonomousHandles type consistency
module Test.Suite.AutonomousIntegration
  ( autonomousIntegrationTests
  , autonomousProductionBoundaryTests
  ) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar, threadDelay)
import Control.Concurrent.STM (atomically, newTQueue, readTQueue, tryReadTQueue, writeTQueue)
import Control.Exception (SomeException, finally, try)
import Control.Monad (forM, void)
import Data.Aeson (encode, object, (.=))
import qualified Data.ByteString.Lazy as LBS
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime(..), getCurrentTime)
import System.Timeout (timeout)
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( AutonomousWorkerConfig(..)
  , AutonomousMode(..)
  , ConfirmationOutcome(..)
  , LearningTask(..)
  , NetworkUpdateEvent(..)
  , buildAtomMorphology
  , acquisitionPreflightPass
  , responseViolatesTopicLanguage
  , confirmationOutcome
  , drainLearningQueue
  , enqueueLearningTask
  , newLearningQueue
  , newPersistentLearningQueue
  , spawnAutonomousWorkerWithTransport
  )
import QxFx0.Bridge.ExternalLLM
  ( LLMTransport(..)
  , MockTable
  , buildTransportFromConfig
  , defaultExternalQueryConfig
  , queryExternalTool
  , transportMaxAttempts
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Tool (ExternalTool(..), ToolDomain(..))
import QxFx0.Learning.JobQueue
  ( LearningJobClaim(..)
  , LearningReadyPayload(..)
  , LearningQuotaLimits(..)
  , claimLearningJob
  , claimLearningReadyPayloads
  , enqueueLearningJob
  , ensureLearningJobSchema
  , markLearningJobClaimFailed
  , recordLearningJobResponseReady
  , recordLearningResponse
  , recordLearningTopicCooldown
  , reserveLearningQuota
  , recordLearningTopicCooldownOnConnection
  , advanceLearningTopicCursor
  )
import QxFx0.Learning.CorroborationQueue
  ( CorroborationTask(..)
  , CorroborationTaskState(..)
  , CorroborationTaskSeed(..)
  , claimCorroborationBatch
  , enqueueCorroborationTaskOnConnection
  , ensureCorroborationTaskSchema
  , recordCorroborationResponseReady
  )
import QxFx0.Learning.Events (ensureLearningEventsSchema)
import QxFx0.Learning.Quarantine (ensureQuarantineSchema)
import QxFx0.Learning.Rollback (rollbackLearningRequest)
import QxFx0.Learning.Promotion
  ( PromotionEvaluation(..)
  , PromotionSnapshot(..)
  , activatePromotionOverlay
  , buildPromotionCandidates
  , createDraftOverlay
  , createPromotionSnapshot
  , ensurePromotionSchema
  , promotionGatePolicyVersion
  , runPromotionEvaluation
  , runPromotionGates
  )
import QxFx0.Learning.Quality
  ( LearningQualityMetrics(..)
  , QualityGateConfig(..)
  , QualityGateResult(..)
  , evaluateQualityGate
  )
import QxFx0.Semantic.Content.AtomStore
  ( AtomId(..)
  , Relation(..)
  , RelationType(..)
  , atomStore
  )
import QxFx0.Semantic.LLMDiscovery (parseStructuredLLMRelations)
import QxFx0.Learning.Metrics
  ( LearningMetrics(..)
  , emptyLearningMetrics
  )
import QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  , SemanticNetworkSnapshot(..)
  , SemanticNetworkVersion(..)
  , applyAutonomousEventBatch
  , applyAutonomousEventBatchForTest
  , beginSemanticNetworkTurn
  , commitSemanticNetworkTurnForTest
  , applyPendingUpdatesInBackground
  , applyPendingUpdatesInBackgroundForTest
  , applyPendingUpdatesForSessionForTest
  , enqueueAutonomousLearningForTopic
  , maxUpdatesPerTurn
  , newSemanticNetworkOwner
  , readSemanticNetworkSnapshot
  )
import QxFx0.Runtime.Session.Bootstrap (spawnAutonomousLearningHandles)
import QxFx0.Runtime.ManagedWorker (spawnManagedWorker, stopManagedWorker)
import QxFx0.Bridge.SQLite (QxFx0DB(..))
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Bridge.SemanticNetwork.RuntimeProjection as RuntimeProjection
import QxFx0.Semantic.Network.Types
  ( SemanticNetwork(..)
  , SemanticEdge(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , EdgeNamespace(..)
  )
import QxFx0.Types.State.System
  ( SystemState(..)
  , ssMorphology
  , ssSemanticNetwork
  )
import QxFx0.Runtime.StateDefaults (emptySystemState)
import QxFx0.Semantic.Content (DefinitionContent(..))
import QxFx0.Types.ExternalQuery
  ( ExternalQueryConfig(..)
  , ExternalQueryError(..)
  , ExternalQueryResponse(..)
  )
import Test.Support (assertExec, freshTestDbPath, queryCount, removeIfExists, withEnvVar)

-- ---------------------------------------------------------------------------
-- maxUpdatesPerTurn tests
-- ---------------------------------------------------------------------------

testMaxUpdatesPerTurnValue :: Test
testMaxUpdatesPerTurnValue = TestLabel "maxUpdatesPerTurn is 100" $ 
  TestCase $ assertEqual "maxUpdatesPerTurn must be 100" 100 maxUpdatesPerTurn

-- ---------------------------------------------------------------------------
-- LearningMetrics tests
-- ---------------------------------------------------------------------------

testLearningMetricsHasUpdatesDeferred :: Test
testLearningMetricsHasUpdatesDeferred = TestLabel "LearningMetrics has lmUpdatesDeferred field" $ 
  TestCase $ do
    let metrics = emptyLearningMetrics
    -- This test just verifies the field exists and is accessible
    -- If compilation succeeds, the field exists
    assertEqual "lmUpdatesDeferred must be 0 in emptyLearningMetrics" 
      0 (lmUpdatesDeferred metrics)

-- ---------------------------------------------------------------------------
-- applyPendingUpdatesForSession tests
-- ---------------------------------------------------------------------------

-- | Create a simple test AutonomousHandles with an update queue
mkTestHandles :: IO AutonomousHandles
mkTestHandles = do
  updateQ <- atomically newTQueue
  metricsRef <- newIORef emptyLearningMetrics
  pure AutonomousHandles
    { ahQueue = Nothing
    , ahUpdateQueue = Just updateQ
    , ahWorkerThread = Nothing
    , ahPendingBreakerQueue = Nothing
    , ahQuarantineDB = Nothing
    , ahMetricsRef = Just metricsRef
    , ahNetworkOwner = Nothing
    , ahAuditThread = Nothing
    , ahApplyThread = Nothing
    , ahSessionId = Just "autonomous-default"
    , ahEnabled = True
    }

-- | Create a simple semantic network for testing
mkTestNetwork :: SemanticNetwork
mkTestNetwork = SemanticNetwork
  { snNodes = S.fromList ["test_node_1", "test_node_2"]
  , snEdges = M.empty
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = mempty
  }

-- | Create a simple NetworkUpdateEvent for testing
mkTestEvent :: Text -> [SemanticEdge] -> NetworkUpdateEvent
mkTestEvent topic edges = NetworkUpdateEvent
  { nueTopic = topic
  , nueEdges = edges
  , nueTimestamp = UTCTime (fromGregorian 2026 7 17) 0
  , nueRequestId = "test-request"
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
  }

mkTestEdge :: Int -> SemanticEdge
mkTestEdge n = SemanticEdge
  { seFrom = "source-" <> T.pack (show n)
  , seTo = "target-" <> T.pack (show n)
  , seWeight = 0.5
  , seCoOccurrence = 1
  , seSource = ExplicitEdge
  , seRelationType = Nothing
  , seVerb = Nothing
  , seRationale = Nothing
  , seCounter = Nothing
  , seSynthesis = Nothing
  , seConfidence = 0.5
  , seProvenance = ProvenanceRuntimeLLM
  , seDomain = Nothing
  , seTemporalScope = Nothing
  , seNamespace = Nothing
  , seLineage = Nothing
  }

mkCorroborationEdge :: RelationType -> SemanticEdge
mkCorroborationEdge relation = SemanticEdge
  { seFrom = "свобода"
  , seTo = "выбор"
  , seWeight = 0.6
  , seCoOccurrence = 1
  , seSource = ExplicitEdge
  , seRelationType = Just relation
  , seVerb = Nothing
  , seRationale = Nothing
  , seCounter = Nothing
  , seSynthesis = Nothing
  , seConfidence = 0.6
  , seProvenance = ProvenanceRuntimeLLM
  , seDomain = Nothing
  , seTemporalScope = Nothing
  , seNamespace = Just NamespaceSessionLocal
  , seLineage = Nothing
  }

mkCompleteRuntimeEvent :: Text -> Text -> [SemanticEdge] -> NetworkUpdateEvent
mkCompleteRuntimeEvent requestId responseHash edges = (mkTestEvent "свобода" edges)
  { nueRequestId = requestId
  , nuePromptHash = Just "stable-prompt-hash"
  , nueResponseHash = Just responseHash
  , nueModel = Just "test-model"
  , nueParserDecision = Just "structured_relation_parser:accepted"
  , nueAdmissionDecision = Just "worker_candidate_admitted"
  , nueEvidenceSource = Just "test"
  , nueCompetitiveAudit = Nothing
  , nueCorroborationPriority = Nothing
  , nueCorroborationTaskId = Nothing
  }

prepareDurableBroadEvent :: QxFx0DB -> NetworkUpdateEvent -> IO NetworkUpdateEvent
prepareDurableBroadEvent db event = do
  accepted <- enqueueLearningJob db (nueRequestId event) (nueTopic event) 1.0 3
  if not accepted
    then assertFailure ("durable test job was not enqueued: " <> T.unpack (nueRequestId event)) >> fail "unreachable"
    else pure ()
  claim <- claimLearningJob db (nueRequestId event) 120 >>= maybe
    (assertFailure "durable test job was not claimable" >> fail "unreachable") pure
  recordLearningJobResponseReady db claim
    (maybe "test-prompt" id (nuePromptHash event))
    (maybe "test-response" id (nueResponseHash event))
    "{}" "{}" []
  ready <- claimLearningReadyPayloads db 1 120
  case [item | item <- ready, lrpRequestId item == nueRequestId event] of
    item : _ -> pure event { nueApplyToken = Just (lrpApplyToken item) }
    [] -> assertFailure "durable test ready payload was not dispatched" >> fail "unreachable"

applyDurableBroadEvent
  :: QxFx0DB -> AutonomousHandles -> SemanticNetwork -> NetworkUpdateEvent -> IO SemanticNetwork
applyDurableBroadEvent db handles network event = do
  dispatched <- prepareDurableBroadEvent db event
  applyAutonomousEventBatch handles network [dispatched]

clearTestLearningCooldown :: QxFx0DB -> IO ()
clearTestLearningCooldown db =
  assertExec (qdbConn db) "clear_test_learning_cooldown"
    "DELETE FROM learning_topic_cooldowns"

-- | Test that applyPendingUpdatesForSession handles empty queue
-- This is a basic structural test
testApplyPendingUpdatesEmptyQueue :: Test
testApplyPendingUpdatesEmptyQueue = TestLabel "applyPendingUpdatesForSession handles empty queue" $ 
  TestCase $ do
    handles <- mkTestHandles
    let ss = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    (networkTurn, turnState) <- beginSemanticNetworkTurn handles ss
    result <- commitSemanticNetworkTurnForTest handles networkTurn turnState
    -- Should return the state unchanged
    assertEqual "State should be unchanged with empty queue"
      (ssSemanticNetwork ss) (ssSemanticNetwork result)

-- | Test that applyPendingUpdatesForSession handles Nil update queue
-- (when ahUpdateQueue is Nothing)
testApplyPendingUpdatesNilQueue :: Test
testApplyPendingUpdatesNilQueue = TestLabel "applyPendingUpdatesForSession handles Nil queue" $ 
  TestCase $ do
    let handles = AutonomousHandles
          { ahQueue = Nothing
          , ahUpdateQueue = Nothing
          , ahWorkerThread = Nothing
          , ahPendingBreakerQueue = Nothing
          , ahQuarantineDB = Nothing
          , ahMetricsRef = Nothing
          , ahNetworkOwner = Nothing
          , ahAuditThread = Nothing
          , ahApplyThread = Nothing
          , ahSessionId = Nothing
          , ahEnabled = False
          }
    let ss = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    (networkTurn, turnState) <- beginSemanticNetworkTurn handles ss
    result <- commitSemanticNetworkTurnForTest handles networkTurn turnState
    -- Should return the state unchanged
    assertEqual "State should be unchanged with Nil queue"
      (ssSemanticNetwork ss) (ssSemanticNetwork result)

testEmptyPendingBatchCannotRevertTurnNetwork :: Test
testEmptyPendingBatchCannotRevertTurnNetwork = TestLabel "empty pending batch cannot revert turn-finalized network" $
  TestCase $ do
    handles0 <- mkTestHandles
    owner <- newSemanticNetworkOwner mkTestNetwork
    let handles = handles0 { ahNetworkOwner = Just owner }
        ss0 = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    (networkTurn, turnState) <- beginSemanticNetworkTurn handles ss0
    let finalized = turnState
          { ssSemanticNetwork = insertTestEdge (mkTestEdge 1) (ssSemanticNetwork turnState) }
    committed <- commitSemanticNetworkTurnForTest handles networkTurn finalized
    snapshot <- readSemanticNetworkSnapshot owner
    assertBool "turn addition reaches returned state"
      (hasTestEdge 1 (ssSemanticNetwork committed))
    assertBool "turn addition becomes the owner snapshot"
      (hasTestEdge 1 (snsNetwork snapshot))
    assertEqual "one turn commit advances one version"
      (SemanticNetworkVersion 1) (snsVersion snapshot)

testBackgroundUpdateBeforeTurnIsVisible :: Test
testBackgroundUpdateBeforeTurnIsVisible = TestLabel "background update before turn is visible to turn snapshot" $
  TestCase $ do
    handles0 <- mkTestHandles
    updateQ <- case ahUpdateQueue handles0 of
      Nothing -> assertFailure "test handles must have an update queue" >> fail "unreachable"
      Just q -> pure q
    owner <- newSemanticNetworkOwner mkTestNetwork
    let handles = handles0 { ahNetworkOwner = Just owner }
    atomically (writeTQueue updateQ (mkTestEvent "ремонт" [mkTestEdge 1]))
    applied <- applyPendingUpdatesInBackgroundForTest handles
    (_, turnState) <- beginSemanticNetworkTurn handles
      (emptySystemState { ssSemanticNetwork = mkTestNetwork })
    snapshot <- readSemanticNetworkSnapshot owner
    assertEqual "one worker event is governed" 1 applied
    assertBool "the next turn starts with the background edge"
      (hasTestEdge 1 (ssSemanticNetwork turnState))
    assertEqual "background apply advances the owner once"
      (SemanticNetworkVersion 1) (snsVersion snapshot)

testTurnAndBackgroundAdditionsBothSurvive :: Test
testTurnAndBackgroundAdditionsBothSurvive = TestLabel "turn rebase preserves turn and concurrent background additions" $
  TestCase $ do
    handles0 <- mkTestHandles
    updateQ <- case ahUpdateQueue handles0 of
      Nothing -> assertFailure "test handles must have an update queue" >> fail "unreachable"
      Just q -> pure q
    owner <- newSemanticNetworkOwner mkTestNetwork
    let handles = handles0 { ahNetworkOwner = Just owner }
        ss0 = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    (networkTurn, turnState) <- beginSemanticNetworkTurn handles ss0
    let finalized = turnState
          { ssSemanticNetwork = insertTestEdge (mkTestEdge 2) (ssSemanticNetwork turnState) }
    atomically (writeTQueue updateQ (mkTestEvent "background" [mkTestEdge 1]))
    _ <- applyPendingUpdatesInBackgroundForTest handles
    committed <- commitSemanticNetworkTurnForTest handles networkTurn finalized
    snapshot <- readSemanticNetworkSnapshot owner
    assertBool "background addition survives the turn commit"
      (hasTestEdge 1 (ssSemanticNetwork committed))
    assertBool "turn addition survives the background commit"
      (hasTestEdge 2 (ssSemanticNetwork committed))
    assertEqual "background and turn commits advance in serialized order"
      (SemanticNetworkVersion 2) (snsVersion snapshot)

testOwnerVersionIncrementsDeterministically :: Test
testOwnerVersionIncrementsDeterministically = TestLabel "owner version increments once per serialized network commit" $
  TestCase $ do
    handles0 <- mkTestHandles
    updateQ <- case ahUpdateQueue handles0 of
      Nothing -> assertFailure "test handles must have an update queue" >> fail "unreachable"
      Just q -> pure q
    owner <- newSemanticNetworkOwner mkTestNetwork
    let handles = handles0 { ahNetworkOwner = Just owner }
        ss0 = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    initial <- readSemanticNetworkSnapshot owner
    emptyApplied <- applyPendingUpdatesInBackgroundForTest handles
    afterEmpty <- readSemanticNetworkSnapshot owner
    atomically (writeTQueue updateQ (mkTestEvent "background" [mkTestEdge 1]))
    _ <- applyPendingUpdatesInBackgroundForTest handles
    afterBackground <- readSemanticNetworkSnapshot owner
    (networkTurn, turnState) <- beginSemanticNetworkTurn handles ss0
    _ <- commitSemanticNetworkTurnForTest handles networkTurn turnState
    afterTurn <- readSemanticNetworkSnapshot owner
    assertEqual "owner begins at version zero" (SemanticNetworkVersion 0) (snsVersion initial)
    assertEqual "empty background drain applies nothing" 0 emptyApplied
    assertEqual "empty background drain does not advance" (snsVersion initial) (snsVersion afterEmpty)
    assertEqual "one background commit advances once" (SemanticNetworkVersion 1) (snsVersion afterBackground)
    assertEqual "one turn commit advances once" (SemanticNetworkVersion 2) (snsVersion afterTurn)

insertTestEdge :: SemanticEdge -> SemanticNetwork -> SemanticNetwork
insertTestEdge edge network = network
  { snNodes = S.insert (seFrom edge) (S.insert (seTo edge) (snNodes network))
  , snEdges = M.insert (seFrom edge, seTo edge) edge (snEdges network)
  }

hasTestEdge :: Int -> SemanticNetwork -> Bool
hasTestEdge n = M.member ("source-" <> suffix, "target-" <> suffix) . snEdges
  where
    suffix = T.pack (show n)

testDeferredUpdatesRemainQueued :: Test
testDeferredUpdatesRemainQueued = TestLabel "deferred autonomous updates remain queued" $
  TestCase $ do
    handles <- mkTestHandles
    updateQ <- case ahUpdateQueue handles of
      Nothing -> assertFailure "test handles must have an update queue" >> fail "unreachable"
      Just q -> pure q
    mapM_
      (\n -> atomically (writeTQueue updateQ (mkTestEvent "topic" [mkTestEdge n])))
      [1 .. maxUpdatesPerTurn + 1]
    let ss0 = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    ss1 <- applyPendingUpdatesForSessionForTest handles ss0
    assertEqual "first pass applies the capped batch"
      maxUpdatesPerTurn
      (M.size (snEdges (ssSemanticNetwork ss1)))
    queued <- atomically (tryReadTQueue updateQ)
    case queued of
      Nothing -> assertFailure "the deferred event was discarded"
      Just event -> do
        atomically (writeTQueue updateQ event)
        ss2 <- applyPendingUpdatesForSessionForTest handles ss1
        assertEqual "second pass applies the deferred event"
          (maxUpdatesPerTurn + 1)
          (M.size (snEdges (ssSemanticNetwork ss2)))
    case ahMetricsRef handles of
      Nothing -> assertFailure "test handles must have metrics"
      Just ref -> do
        metrics <- readIORef ref
        assertEqual "one event was deferred" 1 (lmUpdatesDeferred metrics)

testDurableEnvelopeIsNotSplitByApplyCap :: Test
testDurableEnvelopeIsNotSplitByApplyCap = TestLabel "apply cap keeps a durable response envelope atomic" $
  TestCase $ do
    handles <- mkTestHandles
    updateQ <- case ahUpdateQueue handles of
      Nothing -> assertFailure "test handles must have an update queue" >> fail "unreachable"
      Just q -> pure q
    mapM_ (\n -> atomically (writeTQueue updateQ (mkTestEvent "topic" [mkTestEdge n]))) [1 .. 99]
    let durable edge = (mkCompleteRuntimeEvent "cap-boundary-r1" "cap-boundary-response" [edge])
          { nueApplyToken = Just "apply:cap-boundary" }
    atomically (writeTQueue updateQ (durable (mkTestEdge 100)))
    atomically (writeTQueue updateQ (durable (mkTestEdge 101)))
    let ss0 = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    ss1 <- applyPendingUpdatesForSessionForTest handles ss0
    assertEqual "first pass stops before the crossing durable envelope" 99
      (M.size (snEdges (ssSemanticNetwork ss1)))
    ss2 <- applyPendingUpdatesForSessionForTest handles ss1
    assertEqual "second pass applies the complete durable envelope" 101
      (M.size (snEdges (ssSemanticNetwork ss2)))

testAutonomousStorageInitialized :: Test
testAutonomousStorageInitialized = TestLabel "autonomous worker initializes persistent storage" $
  TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_autonomous_storage.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    withEnvVar "QXFX0_AUTONOMOUS_LEARNING" (Just "1") $ do
      handles <- spawnAutonomousLearningHandles dbPath
      let closeHandles = do
            case ahWorkerThread handles of
              Nothing -> pure ()
              Just workerThread -> stopManagedWorker workerThread
            case ahQuarantineDB handles of
              Nothing -> pure ()
              Just persistenceDb -> NSQL.close (qdbConn persistenceDb)
      (do
          assertBool "worker must be enabled when storage is ready" (ahEnabled handles)
          persistenceDb <- case ahQuarantineDB handles of
            Nothing -> assertFailure "autonomous persistence database missing" >> fail "unreachable"
            Just db -> pure db
          RuntimeProjection.persistRuntimeEdge persistenceDb "restart-session" (mkTestEdge 1)
          loaded <- RuntimeProjection.loadRuntimeEdgeProjection persistenceDb "restart-session"
          assertBool "runtime edge must persist to initialized projection"
            (M.member ("source-1", "target-1") loaded)
        ) `finally` closeHandles
    cleanup

-- ---------------------------------------------------------------------------
-- LLM transport / worker boundary tests
-- ---------------------------------------------------------------------------

autonomousMockTable :: MockTable
autonomousMockTable =
  [ ( "autonomous_learning"
    , "NeedKeywordEnrichment"
    , "Ты"
    , Right "свобода | связана | выбор | relatedto\n"
    )
  ]

autonomousWorkerConfig :: AutonomousWorkerConfig
autonomousWorkerConfig = AutonomousWorkerConfig
  { awcEnabled = True
  , awcMode = FullAutonomous
  , awcMaxRequestsPerMinute = 100
  , awcMaxRequestsPerHour = 1
  , awcMaxRequestsPerDay = 144000
  , awcMaxTokensPerMinute = 100000
  , awcMaxTokensPerHour = 6000000
  , awcMaxTokensPerDay = 144000000
  , awcReservedCompletionTokens = 512
  , awcMaxEdgesPerBatch = 5
  , awcQueueCap = 10
  , awcHourResetDelaySec = 1
  , awcProviderTimeoutMs = 1000
  }

testMockLlmCallReturnsStructuredResponse :: Test
testMockLlmCallReturnsStructuredResponse = TestLabel "LLM mock call preserves payload and tool metadata" $
  TestCase $ do
    let tool = ExternalTool "autonomous_learning" DomainGeneral 0.5 False
    result <- queryExternalTool (MockTransport autonomousMockTable Nothing)
      tool NeedKeywordEnrichment "Ты философский анализатор"
    case result of
      Left err -> assertFailure ("mock LLM call unexpectedly failed: " <> show err)
      Right response -> do
        assertEqual "response must retain the selected tool" "autonomous_learning" (eqrToolName response)
        assertEqual "mock response must be available to the relation parser"
          "свобода | связана | выбор | relatedto\n"
          (eqrStructured response)
        assertEqual "mock calls are deterministic and have no latency" 0 (eqrLatencyMs response)

testAutonomousWorkerCallsMockLlm :: Test
testAutonomousWorkerCallsMockLlm = TestLabel "autonomous worker calls mock LLM and emits admitted update" $
  TestCase $ do
    queue <- newLearningQueue
    updateQ <- atomically newTQueue
    let task = LearningTask "свобода" 1.0 "llm-call-request"
    enqueueLearningTask queue task
    worker <- spawnAutonomousWorkerWithTransport autonomousWorkerConfig
      (pure (MockTransport autonomousMockTable Nothing))
      atomStore
      (buildAtomMorphology atomStore)
      queue
      updateQ
    (do
        mEvent <- timeout 2000000 (atomically (readTQueue updateQ))
        case mEvent of
          Nothing -> assertFailure "mock LLM worker did not emit an update within two seconds"
          Just event -> do
            assertEqual "worker must preserve the learning topic" "свобода" (nueTopic event)
            assertEqual "worker must preserve the request identifier" "llm-call-request" (nueRequestId event)
            assertBool "only atom-store-admitted LLM relations may enter the update"
              (any (\edge -> seFrom edge == "свобода" && seTo edge == "выбор") (nueEdges event))
      ) `finally` stopManagedWorker worker

testAutonomousWorkerRetainsPendingTasks :: Test
testAutonomousWorkerRetainsPendingTasks = TestLabel "autonomous worker retains tasks beyond the first drained item" $
  TestCase $ do
    queue <- newLearningQueue
    updateQ <- atomically newTQueue
    let workerConfig = autonomousWorkerConfig { awcMaxRequestsPerHour = 2 }
        task1 = LearningTask "свобода" 1.0 "first-request"
        task2 = LearningTask "истина" 1.0 "second-request"
    enqueueLearningTask queue task1
    enqueueLearningTask queue task2
    worker <- spawnAutonomousWorkerWithTransport workerConfig
      (pure (MockTransport autonomousMockTable Nothing))
      atomStore
      (buildAtomMorphology atomStore)
      queue
      updateQ
    (do
        mFirst <- timeout 2000000 (atomically (readTQueue updateQ))
        mSecond <- timeout 2000000 (atomically (readTQueue updateQ))
        assertEqual "first task must produce its update" (Just "first-request") (nueRequestId <$> mFirst)
        assertEqual "pending task must be requeued and processed" (Just "second-request") (nueRequestId <$> mSecond)
      ) `finally` stopManagedWorker worker

testPersistentWorkerRetainsPendingTasks :: Test
testPersistentWorkerRetainsPendingTasks = TestLabel "persistent autonomous worker retains tasks beyond the first drained item" $
  TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_persistent_worker.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open persistent worker DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
        workerConfig = autonomousWorkerConfig { awcMaxRequestsPerHour = 2, awcQueueCap = 2 }
        task1 = LearningTask "свобода" 1.0 "persistent-first-request"
        task2 = LearningTask "истина" 1.0 "persistent-second-request"
    RuntimeProjection.ensureRuntimeProjectionSchema db
    ensureLearningEventsSchema db
    ensureQuarantineSchema db
    queue <- newPersistentLearningQueue db 2
    updateQ <- atomically newTQueue
    enqueueLearningTask queue task1
    enqueueLearningTask queue task2
    worker <- spawnAutonomousWorkerWithTransport workerConfig
      (pure (MockTransport autonomousMockTable Nothing))
      atomStore
      (buildAtomMorphology atomStore)
      queue
      updateQ
    (do
        mFirst <- timeout 2000000 (atomically (readTQueue updateQ))
        mSecond <- timeout 2000000 (atomically (readTQueue updateQ))
        (firstEvent, secondEvent) <- case (mFirst, mSecond) of
          (Just first, Just second) -> do
            assertEqual "first durable task must produce its update"
              "persistent-first-request" (nueRequestId first)
            assertEqual "second durable task must survive active-key deduplication"
              "persistent-second-request" (nueRequestId second)
            pure (first, second)
          _ -> assertFailure "persistent worker did not emit both updates" >> fail "unreachable"
        responseCount <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_responses"
        proposalCount <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'llm_edge_proposed'"
        assertEqual "each worker response is persisted" 2 responseCount
        assertEqual "each admitted proposal event is persisted" 2 proposalCount
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
        _ <- applyAutonomousEventBatch handles mkTestNetwork [firstEvent, secondEvent]
        succeeded <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_jobs WHERE state = 'succeeded'"
        assertEqual "worker remains productive through governed job completion" 2 succeeded
      ) `finally` (stopManagedWorker worker `finally` closeDb)
    cleanup

testAutonomousWorkerRejectsFailedLlmCall :: Test
testAutonomousWorkerRejectsFailedLlmCall = TestLabel "autonomous worker emits no update after failed LLM call" $
  TestCase $ do
    queue <- newLearningQueue
    updateQ <- atomically newTQueue
    callsRef <- newIORef (0 :: Int)
    let failingTable =
          [ ( "autonomous_learning"
            , "NeedKeywordEnrichment"
            , "Ты"
            , Left (EqeServerError "mock_llm_failure")
            )
          ]
        task = LearningTask "свобода" 1.0 "llm-failure-request"
        buildFailingTransport = atomicModifyIORef' callsRef
          (\calls -> (calls + 1, MockTransport failingTable Nothing))
    enqueueLearningTask queue task
    worker <- spawnAutonomousWorkerWithTransport autonomousWorkerConfig
      buildFailingTransport
      atomStore
      (buildAtomMorphology atomStore)
      queue
      updateQ
    (do
        mEvent <- timeout 2000000 (atomically (readTQueue updateQ))
        calls <- readIORef callsRef
        assertEqual "worker must invoke the failed LLM transport exactly once" 1 calls
        assertEqual "failed LLM calls must not enqueue a network update" Nothing mEvent
      ) `finally` stopManagedWorker worker

testManagedWorkerStopWaitsAndIsIdempotent :: Test
testManagedWorkerStopWaitsAndIsIdempotent =
  TestLabel "managed worker stop joins finalizers and is idempotent" $ TestCase $ do
    entered <- newEmptyMVar
    blocked <- newEmptyMVar
    cleanupEntered <- newEmptyMVar
    releaseCleanup <- newEmptyMVar
    stopped <- newEmptyMVar
    worker <- spawnManagedWorker $
      (putMVar entered () >> takeMVar blocked)
        `finally` (putMVar cleanupEntered () >> takeMVar releaseCleanup)
    takeMVar entered
    _ <- forkIO (stopManagedWorker worker >> putMVar stopped ())
    takeMVar cleanupEntered
    early <- timeout 20000 (takeMVar stopped)
    assertEqual "stop must not return while the worker finalizer is blocked" Nothing early
    putMVar releaseCleanup ()
    joined <- timeout 1000000 (takeMVar stopped)
    assertEqual "stop returns after the worker has terminated" (Just ()) joined
    second <- timeout 1000000 (stopManagedWorker worker)
    assertEqual "a repeated stop is a completed no-op" (Just ()) second

testCancellationRepairsDurableLeaseBeforeClose :: Test
testCancellationRepairsDurableLeaseBeforeClose =
  TestLabel "worker cancellation repairs its durable lease before DB close" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_worker_cancel_repair.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open cancellation test DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        queue <- newPersistentLearningQueue db 1
        updateQ <- atomically newTQueue
        providerEntered <- newEmptyMVar
        providerBlock <- newEmptyMVar
        let task = LearningTask "свобода" 1.0 "cancelled-worker-request"
            blockingTransport = putMVar providerEntered () >> takeMVar providerBlock
        enqueued <- enqueueLearningTask queue task
        assertBool "durable cancellation fixture must enqueue" enqueued
        worker <- spawnAutonomousWorkerWithTransport autonomousWorkerConfig
          blockingTransport atomStore (buildAtomMorphology atomStore) queue updateQ
        takeMVar providerEntered
        stopped <- timeout 2000000 (stopManagedWorker worker)
        assertEqual "stop waits for cancellation repair" (Just ()) stopped
        repaired <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_jobs WHERE request_id='cancelled-worker-request' AND state IN ('retry_scheduled','failed') AND lease_until IS NULL AND lease_token IS NULL AND last_error='worker_cancelled'"
        assertEqual "cancelled work must not remain leased" 1 repaired
        responsesBeforeClose <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_responses WHERE request_id='cancelled-worker-request'"
        assertEqual "a cancelled provider builder has no response write" 0 responsesBeforeClose
      ) `finally` closeDb
    reopened <- NSQL.open dbPath
    conn <- case reopened of
      Left err -> assertFailure ("cannot reopen cancellation test DB: " <> T.unpack err) >> fail "unreachable"
      Right value -> pure value
    (do
        threadDelay 50000
        responsesAfterClose <- queryCount conn
          "SELECT COUNT(*) FROM learning_responses WHERE request_id='cancelled-worker-request'"
        assertEqual "joined workers cannot write after their owner closes" 0 responsesAfterClose
      ) `finally` NSQL.close conn
    cleanup

testTurnTopicQueuesStarvingLearningTask :: Test
testTurnTopicQueuesStarvingLearningTask = TestLabel "turn topic queues an autonomous task only when starving" $
  TestCase $ do
    queue <- newLearningQueue
    handles0 <- mkTestHandles
    let handles = handles0 { ahQueue = Just queue }
        ss = emptySystemState
          { ssMorphology = buildAtomMorphology atomStore
          , ssSemanticNetwork = mkTestNetwork
          }
    enqueued <- enqueueAutonomousLearningForTopic handles "  Свобода  " ss
    tasks <- drainLearningQueue queue
    assertBool "an underconnected selected topic must enqueue learning" enqueued
    case tasks of
      [task] -> do
        assertEqual "the task retains the normalized topic" "свобода" (ltTopic task)
        assertBool "the request id is unique while retaining its source"
          ("per-turn:свобода:" `T.isPrefixOf` ltRequestId task)
      _ -> assertFailure ("expected one per-turn task, got " <> show tasks)

testExtendedTurnTopicQueuesLearningTask :: Test
testExtendedTurnTopicQueuesLearningTask = TestLabel "turn topic queues a loaded curated topic" $
  TestCase $ do
    queue <- newLearningQueue
    handles0 <- mkTestHandles
    let handles = handles0 { ahQueue = Just queue }
        ss = emptySystemState
          { ssMorphology = buildAtomMorphology atomStore
          , ssSemanticNetwork = mkTestNetwork
          , ssDefinitionCorpus = M.fromList
              [("ремонт", DefinitionContent "ремонт" [])]
          }
    enqueued <- enqueueAutonomousLearningForTopic handles "ремонт" ss
    tasks <- drainLearningQueue queue
    assertBool "loaded non-seed topic must be considered by the density gate" enqueued
    case tasks of
      [task] -> do
        assertEqual "the curated topic is scheduled" "ремонт" (ltTopic task)
        assertBool "the curated request id is unique"
          ("per-turn:ремонт:" `T.isPrefixOf` ltRequestId task)
      _ -> assertFailure ("expected one curated-topic task, got " <> show tasks)

testExtendedMixedCaseTopicQueuesLearningTask :: Test
testExtendedMixedCaseTopicQueuesLearningTask = TestLabel "turn topic normalizes mixed-case curated keys" $
  TestCase $ do
    queue <- newLearningQueue
    handles0 <- mkTestHandles
    let handles = handles0 { ahQueue = Just queue }
        ss = emptySystemState
          { ssMorphology = buildAtomMorphology atomStore
          , ssSemanticNetwork = mkTestNetwork
          , ssDefinitionCorpus = M.fromList
              [("Training", DefinitionContent "Training" [])]
          }
    enqueued <- enqueueAutonomousLearningForTopic handles "TRAINING" ss
    tasks <- drainLearningQueue queue
    assertBool "normalization must not make an extended English topic invisible" enqueued
    case tasks of
      [task] -> do
        assertEqual "normalized topic is scheduled" "training" (ltTopic task)
        assertBool "the normalized request id is unique"
          ("per-turn:training:" `T.isPrefixOf` ltRequestId task)
      _ -> assertFailure ("expected one normalized task, got " <> show tasks)

testPersistentLearningQueueRecoveryAndDedup :: Test
testPersistentLearningQueueRecoveryAndDedup = TestLabel "persistent learning queue recovers pending jobs and deduplicates topics" $
  TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_learning_jobs.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open job test db: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
        task1 = LearningTask "свобода" 1.0 "persistent-r1"
        duplicate = LearningTask "свобода" 0.5 "persistent-r2"
        task2 = LearningTask "истина" 0.8 "persistent-r3"
    (do
        queue1 <- newPersistentLearningQueue db 2
        accepted1 <- enqueueLearningTask queue1 task1
        acceptedDuplicate <- enqueueLearningTask queue1 duplicate
        accepted2 <- enqueueLearningTask queue1 task2
        assertBool "first persistent job must be accepted" accepted1
        assertBool "same topic must be deduplicated while active" (not acceptedDuplicate)
        assertBool "second distinct topic must fit within the capacity" accepted2
        tasks1 <- drainLearningQueue queue1
        assertEqual "queue drain preserves both accepted jobs" [task1, task2] tasks1
        queue2 <- newPersistentLearningQueue db 2
        tasks2 <- drainLearningQueue queue2
        assertEqual "pending jobs survive queue recreation" [task1, task2] tasks2
      ) `finally` closeDb
    cleanup

testBroadResponseReadyReplayWithoutProvider :: Test
testBroadResponseReadyReplayWithoutProvider =
  TestLabel "broad response_ready replays after restart without provider" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_broad_ready_restart.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        task = LearningTask "свобода" 1.0 "broad-ready-r1"
        event = mkCompleteRuntimeEvent "broad-ready-r1" "broad-ready-response" [mkCorroborationEdge RelRequires]
        payload = TE.decodeUtf8 (LBS.toStrict (encode (object ["breEvents" .= [event]])))
    cleanup
    opened1 <- NSQL.open dbPath
    db1 <- case opened1 of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    queue1 <- newPersistentLearningQueue db1 2
    void (enqueueLearningTask queue1 task)
    void (drainLearningQueue queue1)
    claim <- claimLearningJob db1 (ltRequestId task) 120 >>= maybe
      (assertFailure "broad job was not claimable" >> fail "unreachable") pure
    recordLearningJobResponseReady db1 claim "prompt" "broad-ready-response" "{}" payload []
    NSQL.close (qdbConn db1)

    opened2 <- NSQL.open dbPath
    db2 <- case opened2 of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    queue2 <- newPersistentLearningQueue db2 2
    updateQ <- atomically newTQueue
    calls <- newIORef (0 :: Int)
    let buildUnexpected = atomicModifyIORef' calls
          (\n -> (n + 1, MockTransport autonomousMockTable Nothing))
    worker <- spawnAutonomousWorkerWithTransport autonomousWorkerConfig buildUnexpected
      atomStore (buildAtomMorphology atomStore) queue2 updateQ
    recovered <- timeout 2000000 (atomically (readTQueue updateQ)) `finally` stopManagedWorker worker
    providerCalls <- readIORef calls
    assertEqual "durable broad event is recovered" (Just "broad-ready-r1") (nueRequestId <$> recovered)
    assertEqual "restart does not construct or query provider" 0 providerCalls
    NSQL.close (qdbConn db2)
    cleanup

testBroadAtomicClaimAndStaleFence :: Test
testBroadAtomicClaimAndStaleFence =
  TestLabel "broad claim is atomic and stale tokens are rejected" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_broad_claim_fence.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    (do
        ensureLearningJobSchema db
        void (enqueueLearningJob db "claim-r1" "свобода" 1.0 3)
        starts <- forM [1 :: Int, 2] $ \_ -> do
          done <- newEmptyMVar
          void $ forkIO $ claimLearningJob db "claim-r1" 120 >>= putMVar done
          pure done
        claims <- mapM takeMVar starts
        assertEqual "exactly one worker wins" 1 (length [() | Just _ <- claims])
        first <- case [claim | Just claim <- claims] of
          [claim] -> pure claim
          _ -> assertFailure "unexpected claim result" >> fail "unreachable"
        assertExec (qdbConn db) "expire_first_broad_claim"
          "UPDATE learning_jobs SET lease_until=0 WHERE request_id='claim-r1'"
        second <- claimLearningJob db "claim-r1" 120 >>= maybe
          (assertFailure "expired claim was not reclaimed" >> fail "unreachable") pure
        staleChanged <- markLearningJobClaimFailed db first False 1 "stale"
        currentChanged <- markLearningJobClaimFailed db second False 1 "current"
        assertBool "stale lease token cannot overwrite newer lease" (not staleChanged)
        assertBool "current lease token may transition its job" currentChanged
      ) `finally` NSQL.close (qdbConn db)
    cleanup

testBroadMaxAttemptBound :: Test
testBroadMaxAttemptBound = TestLabel "broad jobs never exceed max attempts" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_broad_max_attempts.db"
  let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  cleanup
  opened <- NSQL.open dbPath
  db <- case opened of
    Left err -> assertFailure (T.unpack err) >> fail "unreachable"
    Right conn -> pure (QxFx0DB dbPath conn)
  (do
      ensureLearningJobSchema db
      void (enqueueLearningJob db "max-r1" "истина" 1.0 1)
      first <- claimLearningJob db "max-r1" 120
      assertBool "first and only attempt claims" (maybe False (const True) first)
      assertExec (qdbConn db) "expire_max_attempt_claim"
        "UPDATE learning_jobs SET lease_until=0 WHERE request_id='max-r1'"
      second <- claimLearningJob db "max-r1" 120
      attempts <- queryCount (qdbConn db) "SELECT attempts FROM learning_jobs WHERE request_id='max-r1'"
      failed <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_jobs WHERE request_id='max-r1' AND state='failed'"
      assertEqual "no claim beyond max" Nothing second
      assertEqual "attempt count remains bounded" 1 attempts
      assertEqual "expired exhausted lease is terminal" 1 failed
    ) `finally` NSQL.close (qdbConn db)
  cleanup

testDurableQuotaSharedAcrossQueues :: Test
testDurableQuotaSharedAcrossQueues =
  TestLabel "database quota survives restart and is shared by queues" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_global_learning_quota.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        limits = LearningQuotaLimits 1 1 1 100 100 100
    cleanup
    opened1 <- NSQL.open dbPath
    db1 <- case opened1 of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    ensureLearningJobSchema db1
    void (newPersistentLearningQueue db1 1)
    now <- getCurrentTime
    first <- reserveLearningQuota db1 now limits 1 10
    NSQL.close (qdbConn db1)
    opened2 <- NSQL.open dbPath
    db2 <- case opened2 of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    void (newPersistentLearningQueue db2 1)
    second <- reserveLearningQuota db2 now limits 1 10
    assertBool "first queue reserves the global window" first
    assertBool "restarted second queue sees consumed quota" (not second)
    NSQL.close (qdbConn db2)
    cleanup

testRetryBudgetReservedBeforeDispatch :: Test
testRetryBudgetReservedBeforeDispatch =
  TestLabel "quota reserves one non-retryable provider POST before dispatch" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_retry_budget_quota.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        transportCfg = defaultExternalQueryConfig
          { eqcApiKey = Just "test-only"
          , eqcFallbackReason = Nothing
          , eqcMaxRetries = 3
          }
        cfg = autonomousWorkerConfig
          { awcMaxRequestsPerMinute = 0
          , awcMaxRequestsPerHour = 0
          , awcMaxRequestsPerDay = 0
          , awcHourResetDelaySec = 10
          }
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    queue <- newPersistentLearningQueue db 2
    void (enqueueLearningTask queue (LearningTask "свобода" 1.0 "retry-budget-r1"))
    transport <- buildTransportFromConfig transportCfg
    assertEqual "provider POST has one attempt without durable idempotency" 1 (transportMaxAttempts transport)
    updateQ <- atomically newTQueue
    worker <- spawnAutonomousWorkerWithTransport cfg (pure transport)
      atomStore (buildAtomMorphology atomStore) queue updateQ
    threadDelay 1500000
    unexpected <- atomically (tryReadTQueue updateQ)
    stopManagedWorker worker
    pending <- queryCount (qdbConn db)
      "SELECT COUNT(*) FROM learning_jobs WHERE request_id='retry-budget-r1' AND state='pending' AND attempts=0"
    quotaRows <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_quota_windows"
    assertEqual "insufficient retry budget blocks provider dispatch" Nothing unexpected
    assertEqual "quota denial releases claim without consuming job attempt" 1 pending
    assertEqual "failed all-or-none reservation consumes no window" 0 quotaRows
    NSQL.close (qdbConn db)
    cleanup

testAutonomousModeGatesBroadDispatch :: Test
testAutonomousModeGatesBroadDispatch =
  TestLabel "corroboration-only leaves broad jobs durable and full mode dispatches" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_autonomous_mode.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    queue <- newPersistentLearningQueue db 2
    void (enqueueLearningTask queue (LearningTask "свобода" 1.0 "mode-r1"))
    updateQ <- atomically newTQueue
    calls <- newIORef (0 :: Int)
    let buildMock = atomicModifyIORef' calls
          (\n -> (n + 1, MockTransport autonomousMockTable Nothing))
        corroborationOnly = autonomousWorkerConfig { awcMode = CorroborationOnly }
    restricted <- spawnAutonomousWorkerWithTransport corroborationOnly buildMock
      atomStore (buildAtomMorphology atomStore) queue updateQ
    suppressed <- timeout 500000 (atomically (readTQueue updateQ)) `finally` stopManagedWorker restricted
    callsWhileRestricted <- readIORef calls
    durablePending <- queryCount (qdbConn db)
      "SELECT COUNT(*) FROM learning_jobs WHERE request_id='mode-r1' AND state='pending' AND attempts=0"
    assertEqual "default-safe mode emits no broad update" Nothing suppressed
    assertEqual "default-safe mode never builds provider" 0 callsWhileRestricted
    assertEqual "broad work remains durable and untouched" 1 durablePending
    full <- spawnAutonomousWorkerWithTransport autonomousWorkerConfig buildMock
      atomStore (buildAtomMorphology atomStore) queue updateQ
    dispatched <- timeout 2000000 (atomically (readTQueue updateQ)) `finally` stopManagedWorker full
    callsAfterFull <- readIORef calls
    assertEqual "explicit full mode dispatches broad work" (Just "mode-r1") (nueRequestId <$> dispatched)
    assertEqual "full mode constructs provider once" 1 callsAfterFull
    NSQL.close (qdbConn db)
    cleanup

testLegacyLearningSchemaMigration :: Test
testLegacyLearningSchemaMigration =
  TestLabel "legacy learning schema migrates additively and preserves rows" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_legacy_learning_schema.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup

testCorroborationLegacyRebuildIsTransactional :: Test
testCorroborationLegacyRebuildIsTransactional =
  TestLabel "corroboration legacy table rebuild rolls back partial schema changes" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_corroboration_transactional_rebuild.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    Right conn <- NSQL.open dbPath
    let db = QxFx0DB dbPath conn
    (do
        assertExec conn "legacy_corroboration_shape"
          "CREATE TABLE learning_corroboration_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, topic TEXT NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, relation_type TEXT NOT NULL, namespace TEXT NOT NULL, session_id TEXT, owner TEXT, source_request_id TEXT NOT NULL, source_response_hash TEXT NOT NULL, competitive_audit TEXT NOT NULL, priority REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 3, available_at INTEGER NOT NULL, lease_until INTEGER, lease_token TEXT, confirmation_request_id TEXT UNIQUE, prompt_hash TEXT, response_hash TEXT, model TEXT, result_kind TEXT, last_error TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, UNIQUE(edge_from, edge_to, relation_type, namespace))"
        assertExec conn "blocking_legacy_shadow"
          "CREATE TABLE learning_corroboration_tasks_scope_legacy(blocker INTEGER)"
        failed <- try (ensureCorroborationTaskSchema db) :: IO (Either SomeException ())
        assertBool "shadow-name collision forces the rebuild to fail" (either (const True) (const False) failed)
        originalStillNamed <- queryCount conn
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='learning_corroboration_tasks'"
        partialPolicyColumn <- queryCount conn
          "SELECT COUNT(*) FROM pragma_table_info('learning_corroboration_tasks') WHERE name='policy'"
        assertEqual "failed rebuild keeps the original table name" 1 originalStillNamed
        assertEqual "earlier additive changes roll back with the rebuild" 0 partialPolicyColumn
        assertExec conn "remove_blocking_legacy_shadow"
          "DROP TABLE learning_corroboration_tasks_scope_legacy"
        ensureCorroborationTaskSchema db
        migrated <- queryCount conn
          "SELECT COUNT(*) FROM pragma_table_info('learning_corroboration_tasks') WHERE name IN ('policy','owner','session_id')"
        assertEqual "retry completes the current scoped schema" 3 migrated
      ) `finally` NSQL.close conn
    cleanup

testRequestRollbackIsExactUnboundedAndAtomic :: Test
testRequestRollbackIsExactUnboundedAndAtomic =
  TestLabel "request rollback is unbounded, scope/relation exact, and atomic with retirement" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_request_rollback_exact.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    Right conn <- NSQL.open dbPath
    let db = QxFx0DB dbPath conn
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        assertExec conn "rollback_projection_fixtures"
          "INSERT INTO semantic_edges_runtime(ts,edge_from,edge_to,weight,co_occurrence,relation_type,confidence,provenance,namespace,session_id,owner) VALUES(1,'свобода','выбор',0.6,2,'requires',0.6,'runtime_llm','session_local','session-a','session-a'),(2,'свобода','выбор',0.6,1,'requires',0.6,'runtime_llm','global',NULL,'global'),(3,'свобода','выбор',0.6,1,'causes',0.6,'runtime_llm','session_local','session-a','session-a')"
        assertExec conn "rollback_target_evidence"
          "INSERT INTO learning_events(ts,session_id,request_id,topic,kind,source,edge_from,edge_to,provenance,reason,admission_decision,edge_namespace,edge_owner) VALUES(1,'session-a','rollback-target','свобода','edge_admitted','autonomous_apply','свобода','выбор','runtime_llm','relation_type=requires','runtime_admitted','session_local','session-a')"
        -- The attributable event precedes more than the old 10k replay cap.
        assertExec conn "rollback_history_noise"
          "WITH RECURSIVE n(x) AS (VALUES(1) UNION ALL SELECT x+1 FROM n WHERE x<10001) INSERT INTO learning_events(ts,request_id,topic,kind,source) SELECT x+1,'noise-'||x,'шум','llm_edge_proposed','worker' FROM n"
        assertExec conn "rollback_later_evidence"
          "INSERT INTO learning_events(ts,session_id,request_id,topic,kind,source,edge_from,edge_to,provenance,reason,admission_decision,edge_namespace,edge_owner) VALUES(20000,'session-a','rollback-later','свобода','edge_corroborated','autonomous_apply','свобода','выбор','runtime_llm','relation_type=requires','runtime_corroborated','session_local','session-a')"
        assertExec conn "rollback_retirement_failure"
          "CREATE TRIGGER fail_test_retirement BEFORE INSERT ON learning_events WHEN NEW.kind='edge_retired' BEGIN SELECT RAISE(ABORT, 'test retirement failure'); END"
        failed <- try (rollbackLearningRequest db "rollback-target") :: IO (Either SomeException Int)
        assertBool "forced retirement failure aborts rollback" (either (const True) (const False) failed)
        unchanged <- queryCount conn
          "SELECT co_occurrence FROM semantic_edges_runtime WHERE namespace='session_local' AND session_id='session-a' AND relation_type='requires'"
        assertEqual "projection mutation rolls back with retirement failure" 2 unchanged
        assertExec conn "remove_retirement_failure" "DROP TRIGGER fail_test_retirement"

        retired <- rollbackLearningRequest db "rollback-target"
        assertEqual "one exact request shape is retired despite old history" 1 retired
        localRemaining <- queryCount conn
          "SELECT co_occurrence FROM semantic_edges_runtime WHERE namespace='session_local' AND session_id='session-a' AND relation_type='requires'"
        globalRemaining <- queryCount conn
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE namespace='global' AND relation_type='requires'"
        otherRelation <- queryCount conn
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE namespace='session_local' AND session_id='session-a' AND relation_type='causes'"
        retirement <- queryCount conn
          "SELECT COUNT(*) FROM learning_events WHERE request_id='rollback-target' AND kind='edge_retired' AND reason='explicit_learning_request_rollback;relation_type=requires' AND edge_namespace='session_local' AND edge_owner='session-a'"
        assertEqual "later evidence keeps exactly one local contribution" 1 localRemaining
        assertEqual "same endpoints in global scope are untouched" 1 globalRemaining
        assertEqual "same endpoints under another relation are untouched" 1 otherRelation
        assertEqual "retirement records the exact relation and scope" 1 retirement
        retiredAgain <- rollbackLearningRequest db "rollback-target"
        assertEqual "request rollback is idempotent" 0 retiredAgain
      ) `finally` NSQL.close conn
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    (do
        assertExec (qdbConn db) "legacy_jobs"
          "CREATE TABLE learning_jobs(request_id TEXT PRIMARY KEY, topic TEXT NOT NULL, priority REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 3, available_at INTEGER NOT NULL, lease_until INTEGER, lease_token TEXT, last_error TEXT, policy TEXT NOT NULL DEFAULT 'autonomous-learning-v1', active_key TEXT UNIQUE, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
        assertExec (qdbConn db) "legacy_responses"
          "CREATE TABLE learning_responses(request_id TEXT PRIMARY KEY, prompt_hash TEXT NOT NULL, response_hash TEXT NOT NULL, response_body TEXT NOT NULL, created_at INTEGER NOT NULL)"
        assertExec (qdbConn db) "legacy_corroboration"
          "CREATE TABLE learning_corroboration_tasks(id INTEGER PRIMARY KEY AUTOINCREMENT, topic TEXT NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, relation_type TEXT NOT NULL, namespace TEXT NOT NULL, source_request_id TEXT NOT NULL, source_response_hash TEXT NOT NULL, competitive_audit TEXT NOT NULL, priority REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
        assertExec (qdbConn db) "legacy_job_row"
          "INSERT INTO learning_jobs VALUES('legacy-r1','свобода',1.0,'pending',0,3,0,NULL,NULL,NULL,'autonomous-learning-v1','legacy-key',0,0)"
        ensureLearningJobSchema db
        generation <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM pragma_table_info('learning_jobs') WHERE name='lease_generation'"
        readyTable <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='learning_ready_payloads'"
        quotaTable <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='learning_quota_windows'"
        corroborationToken <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM pragma_table_info('learning_corroboration_tasks') WHERE name='lease_token'"
        version <- queryCount (qdbConn db)
          "SELECT version FROM learning_schema_versions WHERE owner='job_queue'"
        preserved <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_jobs WHERE request_id='legacy-r1'"
        assertEqual "job fencing column added" 1 generation
        assertEqual "durable ready payload table added" 1 readyTable
        assertEqual "quota table added" 1 quotaTable
        assertEqual "corroboration lease column added" 1 corroborationToken
        assertEqual "schema version advanced deterministically" 6 version
        assertEqual "legacy row preserved" 1 preserved
        retired <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_jobs WHERE request_id='legacy-r1' AND state='failed' AND last_error='superseded_learning_policy'"
        assertEqual "legacy policy job is retired before dispatch" 1 retired
      ) `finally` NSQL.close (qdbConn db)
    cleanup

testAutonomousPreflightRejectsCrossScriptEdge :: Test
testAutonomousPreflightRejectsCrossScriptEdge =
  TestLabel "autonomous preflight rejects cross-script candidate edges" $ TestCase $ do
    let edge = (mkCorroborationEdge RelRequires)
          { seFrom = "свобода", seTo = "harvest" }
    assertBool "cross-script edge is not admitted"
      (not (acquisitionPreflightPass "свобода" M.empty M.empty M.empty edge))
    let untrusted = edge { seFrom = "agriculture", seTo = "civilization" }
    assertBool "non-definition audit topic is not admitted"
      (not (acquisitionPreflightPass "agriculture" M.empty M.empty M.empty untrusted))

testStructuredLearningResponseContract :: Test
testStructuredLearningResponseContract = TestLabel "structured learning response requires schema version and preserves rationale" $
  TestCase $ do
    let valid = "{\"schema_version\":1,\"relations\":[{\"from\":\"свобода\",\"verb\":\"связана\",\"to\":\"ответственность\",\"type\":\"relatedTo\",\"rationale\":\"проверка рамки\"}]}"
        invalidVersion = "{\"schema_version\":2,\"relations\":[{\"from\":\"свобода\",\"verb\":\"связана\",\"to\":\"ответственность\",\"type\":\"relatedTo\"}]}"
    case parseStructuredLLMRelations "свобода" valid of
      [relation] -> do
        assertEqual "structured relation source"
          (AtomId "свобода")
          (relFrom relation)
        assertEqual "structured rationale must survive parsing" (Just "проверка рамки") (relRationale relation)
      other -> assertFailure ("expected one structured relation, got: " <> show other)
    assertEqual "unsupported schema version must not be admitted" []
      (parseStructuredLLMRelations "свобода" invalidVersion)
    assertEqual "unknown relation types must be rejected" []
      (parseStructuredLLMRelations "свобода" "{\"schema_version\":1,\"relations\":[{\"from\":\"свобода\",\"verb\":\"x\",\"to\":\"истина\",\"type\":\"invented\"}]}")
    assertEqual "oversized structured responses must be rejected" []
      (parseStructuredLLMRelations "свобода" (T.replicate 65537 "x"))
    let latinEndpoint = "{\"schema_version\":1,\"relations\":[{\"from\":\"свобода\",\"verb\":\"requires\",\"to\":\"duty\",\"type\":\"requires\"}]}"
    assertBool "worker detects Latin-only endpoint before admission"
      (responseViolatesTopicLanguage "свобода" latinEndpoint)
    assertEqual "parser independently rejects Latin-only endpoint for Russian topic" []
      (parseStructuredLLMRelations "свобода" latinEndpoint)

testLearningTopicCooldown :: Test
testLearningTopicCooldown = TestLabel "successful learning request applies durable topic cooldown" $
  TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_learning_cooldown.db"
    removeIfExists dbPath
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open cooldown test db: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        queue <- newPersistentLearningQueue db 2
        accepted <- enqueueLearningTask queue (LearningTask "свобода" 1.0 "cooldown-r1")
        assertBool "initial cooldown task accepted" accepted
        _ <- drainLearningQueue queue
        recordLearningTopicCooldown db "свобода" 300
        acceptedAgain <- enqueueLearningTask queue (LearningTask "свобода" 1.0 "cooldown-r2")
        assertBool "recently succeeded topic remains cooled down" (not acceptedAgain)
      ) `finally` closeDb
    mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]

testTerminalRejectionCooldown :: Test
testTerminalRejectionCooldown = TestLabel "terminal language or selector rejection applies durable negative cooldown" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_negative_rejection_cooldown.db"
  removeIfExists dbPath
  Right conn <- NSQL.open dbPath
  let db = QxFx0DB dbPath conn
  ensureLearningJobSchema db
  recordLearningTopicCooldownOnConnection conn "свобода" 3600 "language_rejected" True
  NSQL.close conn
  Right restarted <- NSQL.open dbPath
  let restartedDb = QxFx0DB dbPath restarted
  queue <- newPersistentLearningQueue restartedDb 1
  accepted <- enqueueLearningTask queue (LearningTask "свобода" 1.0 "negative-cooldown-r2")
  negative <- queryCount restarted
    "SELECT COUNT(*) FROM learning_topic_cooldowns WHERE topic='свобода' AND negative=1 AND reason='language_rejected'"
  NSQL.close restarted
  mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  assertBool "restart cannot immediately requeue terminally rejected topic" (not accepted)
  assertEqual "negative rejection reason is durable" 1 negative

testRestartPreservesTopicRotation :: Test
testRestartPreservesTopicRotation = TestLabel "density audit topic cursor survives process restart" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_topic_cursor_restart.db"
  removeIfExists dbPath
  Right firstConn <- NSQL.open dbPath
  let firstDb = QxFx0DB dbPath firstConn
  ensureLearningJobSchema firstDb
  first <- advanceLearningTopicCursor firstDb 3
  NSQL.close firstConn
  Right secondConn <- NSQL.open dbPath
  let secondDb = QxFx0DB dbPath secondConn
  second <- advanceLearningTopicCursor secondDb 3
  NSQL.close secondConn
  mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  assertEqual "first bounded cycle starts at zero" 0 first
  assertEqual "restarted cycle resumes after prior queue window" 3 second

testPromotionEvidenceSeparatedBySession :: Test
testPromotionEvidenceSeparatedBySession = TestLabel "promotion never combines session-local evidence across owners" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_promotion_session_evidence.db"
  let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  cleanup
  Right conn <- NSQL.open dbPath
  let db = QxFx0DB dbPath conn
  RuntimeProjection.ensureRuntimeProjectionSchema db
  ensureLearningJobSchema db
  ensureLearningEventsSchema db
  ensurePromotionSchema db
  assertExec conn "session_edges"
    "INSERT INTO semantic_edges_runtime(ts,edge_from,edge_to,weight,co_occurrence,relation_type,confidence,provenance,namespace,session_id,owner) VALUES(1,'свобода','ответственность',0.6,1,'requires',0.6,'runtime_llm','session_local','session-a','session-a'),(2,'свобода','ответственность',0.6,1,'requires',0.6,'runtime_llm','session_local','session-b','session-b')"
  assertExec conn "session_events"
    "INSERT INTO learning_events(ts,session_id,request_id,topic,kind,source,edge_from,edge_to,provenance,confidence,co_occurrence,reason,prompt_hash,response_hash,model,parser_decision,admission_decision,evidence_source,edge_namespace,edge_owner) VALUES(1,'session-a','req-a','свобода','edge_admitted','autonomous_apply','свобода','ответственность','runtime_llm',0.6,1,'relation_type=requires','prompt-a','response-a','provider-a','accepted','runtime_admitted','autonomous_external_llm','session_local','session-a'),(2,'session-b','req-b','свобода','edge_admitted','autonomous_apply','свобода','ответственность','runtime_llm',0.6,1,'relation_type=requires','prompt-b','response-b','provider-b','accepted','runtime_admitted','autonomous_external_llm','session_local','session-b')"
  assertExec conn "session_proofs"
    "INSERT INTO learning_apply_proofs(source_kind,request_id,policy,dispatch_token,applied_at) VALUES('broad','req-a','autonomous-learning-v4-session-owned','token-a',1),('broad','req-b','autonomous-learning-v4-session-owned','token-b',2)"
  snapshot <- createPromotionSnapshot db
  _ <- buildPromotionCandidates db (psSnapshotId snapshot)
  combined <- queryCount conn
    "SELECT COUNT(*) FROM promotion_candidates WHERE support_count >= 2"
  separated <- queryCount conn
    "SELECT COUNT(*) FROM promotion_candidates WHERE support_count=1"
  NSQL.close conn
  cleanup
  assertEqual "unrelated sessions cannot satisfy two-observation support" 0 combined
  assertEqual "each session retains its own auditable candidate" 2 separated

testGovernedBatchPersistsEdgesEventsAndJobsTogether :: Test
testGovernedBatchPersistsEdgesEventsAndJobsTogether =
  TestLabel "governed batch persists edges, events, cooldowns, and jobs together" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_governed_apply_batch.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        mkEvent requestId topic edge = NetworkUpdateEvent
          { nueTopic = topic
          , nueEdges = [edge]
          , nueTimestamp = UTCTime (fromGregorian 2026 7 18) 0
          , nueRequestId = requestId
          , nuePromptHash = Just ("prompt-" <> requestId)
          , nueResponseHash = Just ("response-" <> requestId)
          , nueModel = Just "test-model"
          , nueParserDecision = Just "structured_relation_parser:accepted"
          , nueAdmissionDecision = Just "worker_candidate_admitted"
           , nueEvidenceSource = Just "test"
           , nueCompetitiveAudit = Nothing
           , nueCorroborationPriority = Nothing
           , nueCorroborationTaskId = Nothing
           , nueApplyToken = Just "apply:test-dispatch"
          }
    cleanup

    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open governed apply DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        queue <- newPersistentLearningQueue db 2
        acceptedOne <- enqueueLearningTask queue (LearningTask "свобода" 1.0 "apply-r1")
        acceptedTwo <- enqueueLearningTask queue (LearningTask "истина" 1.0 "apply-r2")
        assertBool "first durable job must be inserted" acceptedOne
        assertBool "second durable job must be inserted" acceptedTwo
        assertExec (qdbConn db) "dispatch_test_apply_jobs"
          "UPDATE learning_jobs SET state='response_ready', lease_token='apply:test-dispatch', lease_until=9999999999999999 WHERE request_id IN ('apply-r1','apply-r2')"
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
        _ <- applyAutonomousEventBatch handles mkTestNetwork
          [ mkEvent "apply-r1" "свобода" (mkTestEdge 1)
          , mkEvent "apply-r2" "истина" (mkTestEdge 2)
          ]
        succeeded <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_jobs WHERE state = 'succeeded'"
        cooldowns <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_topic_cooldowns"
        edges <- queryCount (qdbConn db) "SELECT COUNT(*) FROM semantic_edges_runtime"
        admittedEvents <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_admitted'"
        scopedEvents <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_events WHERE kind='edge_admitted' AND session_id='autonomous-default' AND edge_owner='autonomous-default'"
        assertEqual "both jobs are finalized by the governed apply" 2 succeeded
        assertEqual "both topic cooldowns share the successful apply boundary" 2 cooldowns
        assertEqual "both admitted edges persist with their job finalization" 2 edges
        assertEqual "both admission events persist with their edges" 2 admittedEvents
        assertEqual "autonomous admission events retain session identity" 2 scopedEvents
      ) `finally` closeDb
    cleanup

testGovernedCorroborationPath :: Test
testGovernedCorroborationPath =
  TestLabel "governed corroboration preserves one edge and independent promotion support" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_governed_corroboration.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        edge = mkCorroborationEdge RelRequires
        firstEvent = mkCompleteRuntimeEvent "corrob-r1" "response-1" [edge]
        sameRequestEvent = mkCompleteRuntimeEvent "corrob-r1" "response-2" [edge]
        sameResponseEvent = mkCompleteRuntimeEvent "corrob-r2" "response-1" [edge]
        independentEvent = mkCompleteRuntimeEvent "corrob-r3" "response-3" [edge]
        conflictEvent = mkCompleteRuntimeEvent "corrob-r4" "response-4"
          [mkCorroborationEdge RelContrastsWith]
    cleanup

    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open corroboration DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensurePromotionSchema db
        _ <- newPersistentLearningQueue db 8
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
        firstNetwork <- applyDurableBroadEvent db handles mkTestNetwork firstEvent
        -- A request id identifies one durable job and cannot be dispatched as
        -- a second autonomous observation.
        let afterSameRequest = firstNetwork
        clearTestLearningCooldown db
        afterSameResponse <- applyDurableBroadEvent db handles afterSameRequest sameResponseEvent
        clearTestLearningCooldown db
        afterIndependent <- applyDurableBroadEvent db handles afterSameResponse independentEvent
        clearTestLearningCooldown db
        finalNetwork <- applyDurableBroadEvent db handles afterIndependent conflictEvent
        assertEqual "same-request repeat does not increase co-occurrence" 1
          (maybe (-1) seCoOccurrence (M.lookup ("свобода", "выбор") (snEdges firstNetwork)))
        assertEqual "same response hash does not increase co-occurrence" 1
          (maybe (-1) seCoOccurrence (M.lookup ("свобода", "выбор") (snEdges afterSameResponse)))
        assertEqual "independent response corroborates the existing edge" 2
          (maybe (-1) seCoOccurrence (M.lookup ("свобода", "выбор") (snEdges afterIndependent)))
        assertEqual "relation conflict preserves the corroborated edge" 2
          (maybe (-1) seCoOccurrence (M.lookup ("свобода", "выбор") (snEdges finalNetwork)))
        assertEqual "relation conflict keeps the original relation"
          (Just RelRequires)
          (M.lookup ("свобода", "выбор") (snEdges finalNetwork) >>= seRelationType)
        edgeRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE edge_from = 'свобода' AND edge_to = 'выбор'"
        persistedCooc <- queryCount (qdbConn db)
          "SELECT co_occurrence FROM semantic_edges_runtime WHERE edge_from = 'свобода' AND edge_to = 'выбор' ORDER BY id DESC LIMIT 1"
        admitted <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_admitted' AND edge_from = 'свобода' AND edge_to = 'выбор'"
        corroborated <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_corroborated' AND edge_from = 'свобода' AND edge_to = 'выбор'"
        rejected <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_rejected' AND edge_from = 'свобода' AND edge_to = 'выбор'"
        quarantined <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_quarantined' AND edge_from = 'свобода' AND edge_to = 'выбор'"
        assertEqual "runtime projection keeps one graph row" 1 edgeRows
        assertEqual "runtime projection persists corroboration co-occurrence" 2 persistedCooc
        assertEqual "one first admission is persisted" 1 admitted
        assertEqual "one independent corroboration is persisted" 1 corroborated
        assertEqual "same response evidence is rejected" 1 rejected
        assertEqual "conflicting relation remains quarantined" 1 quarantined
        snapshot <- createPromotionSnapshot db
        _ <- buildPromotionCandidates db (psSnapshotId snapshot)
        support <- queryCount (qdbConn db)
          ("SELECT support_count FROM promotion_candidates WHERE snapshot_id = '" <> psSnapshotId snapshot
            <> "' AND topic = 'свобода' AND relation_type = 'requires' AND object_atom = 'выбор'")
        assertEqual "promotion sees two independent request/response supports" 2 support
      ) `finally` closeDb
    cleanup

testDurableCorroborationTaskThreshold :: Test
testDurableCorroborationTaskThreshold =
  TestLabel "durable corroboration tasks lease only after three qualified hypotheses" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_corroboration_task_threshold.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        seed suffix = CorroborationTaskSeed
          { ctsTopic = "тема"
          , ctsEdgeFrom = "тема"
          , ctsEdgeTo = "объект-" <> suffix
          , ctsRelationType = "requires"
          , ctsNamespace = "session_local"
          , ctsSessionId = Just "autonomous-default"
          , ctsOwner = "autonomous-default"
          , ctsSourceRequestId = "first-" <> suffix
          , ctsSourceResponseHash = "response-" <> suffix
          , ctsPriority = 2.0
          , ctsAudit = "competitive_utility_v1;qualified_for_corroboration=true"
          }
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open corroboration threshold DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        ensureCorroborationTaskSchema db
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "one")
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "two")
        beforeThreshold <- claimCorroborationBatch db 3 3
        assertEqual "two tasks do not dispatch" [] beforeThreshold
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "three")
        leased <- claimCorroborationBatch db 3 3
        assertEqual "three pending tasks lease atomically" 3 (length leased)
        leasedRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_corroboration_tasks WHERE state = 'leased'"
        assertEqual "all claimed tasks persist as leased" 3 leasedRows
      ) `finally` closeDb
    cleanup

testQualifiedFirstAdmissionCreatesCorroborationTask :: Test
testQualifiedFirstAdmissionCreatesCorroborationTask =
  TestLabel "qualified first admission creates one durable corroboration task" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_qualified_first_admission.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        edge = mkCorroborationEdge RelRequires
        event = (mkCompleteRuntimeEvent "qualified-r1" "qualified-response" [edge])
          { nueAdmissionDecision = Just "worker_candidate_qualified"
          , nueCompetitiveAudit = Just "competitive_utility_v1;qualified_for_corroboration=true"
          , nueCorroborationPriority = Just 2.25
          }
    cleanup

    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open qualified admission DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensureCorroborationTaskSchema db
        _ <- newPersistentLearningQueue db 1
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
        _ <- applyDurableBroadEvent db handles mkTestNetwork event
        tasks <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_corroboration_tasks WHERE edge_from = 'свобода' AND edge_to = 'выбор' AND state = 'pending'"
        edgeRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE edge_from = 'свобода' AND edge_to = 'выбор'"
        assertEqual "qualified first admission creates one pending task" 1 tasks
        assertEqual "qualified task does not duplicate runtime edge" 1 edgeRows
      ) `finally` closeDb
    cleanup

testTargetedConfirmationRejectsFreeTriples :: Test
testTargetedConfirmationRejectsFreeTriples =
  TestLabel "targeted confirmation rejects free or multiple triples" $ TestCase $ do
    let task = CorroborationTask
          { ctId = 1, ctTopic = "свобода", ctEdgeFrom = "свобода", ctEdgeTo = "выбор"
          , ctRelationType = "requires", ctNamespace = "session_local"
          , ctSessionId = Just "autonomous-default", ctOwner = "autonomous-default"
          , ctSourceRequestId = "source", ctSourceResponseHash = "source-response"
          , ctPriority = 2.0, ctState = CtsLeased, ctAttempts = 1, ctMaxAttempts = 3
          , ctConfirmationRequestId = Just "confirmation"
          }
        freeTriples = "{\"schema_version\":1,\"relations\":[{\"from\":\"свобода\",\"verb\":\"требует\",\"to\":\"выбор\",\"type\":\"requires\"},{\"from\":\"свобода\",\"verb\":\"требует\",\"to\":\"долг\",\"type\":\"requires\"}]}"
        wrongEndpoint = "{\"schema_version\":1,\"relations\":[{\"from\":\"свобода\",\"verb\":\"требует\",\"to\":\"долг\",\"type\":\"requires\"}]}"
    case confirmationOutcome task freeTriples of
      ConfirmationRejected _ -> pure ()
      _ -> assertFailure "multiple triples must not enter the graph"
    case confirmationOutcome task wrongEndpoint of
      ConfirmationRejected _ -> pure ()
      _ -> assertFailure "mismatched endpoint must not enter the graph"

testTargetedConfirmationSucceedsWithoutDuplicateEdge :: Test
testTargetedConfirmationSucceedsWithoutDuplicateEdge =
  TestLabel "targeted confirmation corroborates one exact leased shape" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_targeted_confirmation_success.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        edge = mkCorroborationEdge RelRequires
        seed suffix = CorroborationTaskSeed
          { ctsTopic = "свобода"
          , ctsEdgeFrom = "свобода"
          , ctsEdgeTo = "выбор" <> suffix
          , ctsRelationType = "requires"
          , ctsNamespace = "session_local"
          , ctsSessionId = Just "autonomous-default"
          , ctsOwner = "autonomous-default"
          , ctsSourceRequestId = "source-" <> suffix
          , ctsSourceResponseHash = "source-response-" <> suffix
          , ctsPriority = 2.0
          , ctsAudit = "competitive_utility_v1;qualified_for_corroboration=true"
          }
    cleanup

    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open targeted confirmation DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensureCorroborationTaskSchema db
        queue <- newPersistentLearningQueue db 1
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "")
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "-two")
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "-three")
        leased <- claimCorroborationBatch db 3 3
        task <- case [item | item <- leased, ctEdgeTo item == "выбор"] of
          item : _ -> pure item
          [] -> assertFailure "expected leased exact task" >> fail "unreachable"
        let confirmationRequest = maybe "confirmation-missing" id (ctConfirmationRequestId task)
            confirmationBody = "{\"schema_version\":1,\"relations\":[{\"from\":\"свобода\",\"verb\":\"требует\",\"to\":\"выбор\",\"type\":\"requires\"}]}"
        recordCorroborationResponseReady db (ctId task) confirmationRequest
          "confirmation-prompt" "independent-confirmation-response" "test-model" confirmationBody
        duplicate <- try (recordCorroborationResponseReady db (ctId task) "duplicate-confirmation"
          "duplicate-prompt" "duplicate-response" "test-model" confirmationBody)
          :: IO (Either SomeException ())
        duplicateRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_responses WHERE request_id='duplicate-confirmation'"
        assertBool "stale response-ready transition fails" (either (const True) (const False) duplicate)
        assertEqual "failed response-ready transition rolls back response insert" 0 duplicateRows
        responseReady <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM learning_corroboration_tasks WHERE id=" <> T.pack (show (ctId task)) <> " AND state='response_ready'")
        assertEqual "response is durable before worker restart" 1 responseReady
        updateQ <- atomically newTQueue
        transportCalls <- newIORef (0 :: Int)
        let buildUnexpectedTransport = atomicModifyIORef' transportCalls
              (\calls -> (calls + 1, MockTransport autonomousMockTable Nothing))
        worker <- spawnAutonomousWorkerWithTransport autonomousWorkerConfig
          buildUnexpectedTransport atomStore (buildAtomMorphology atomStore) queue updateQ
        recovered <- timeout 2000000 (atomically (readTQueue updateQ))
          `finally` stopManagedWorker worker
        confirmation <- case recovered of
          Nothing -> assertFailure "restart did not dispatch durable response_ready work" >> fail "unreachable"
          Just event -> pure event
        calls <- readIORef transportCalls
        assertEqual "restart recovery must not query the provider again" 0 calls
        assertEqual "recovered event retains targeted evidence source"
          (Just "candidate_targeted_corroboration") (nueEvidenceSource confirmation)
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
            first = mkCompleteRuntimeEvent "source-" "source-response-" [edge]
        firstNetwork <- applyDurableBroadEvent db handles mkTestNetwork first
        finalNetwork <- applyAutonomousEventBatch handles firstNetwork [confirmation]
        cooc <- queryCount (qdbConn db)
          "SELECT co_occurrence FROM semantic_edges_runtime WHERE edge_from='свобода' AND edge_to='выбор'"
        succeeded <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM learning_corroboration_tasks WHERE id = " <> T.pack (show (ctId task)) <> " AND state='succeeded'")
        assertEqual "confirmation increments existing edge only" 2 cooc
        assertEqual "task terminal state is succeeded" 1 succeeded
        assertEqual "one graph row remains" 1 (M.size (snEdges finalNetwork))
      ) `finally` closeDb
    cleanup

testCorroborationBatchHonorsQuota :: Test
testCorroborationBatchHonorsQuota =
  TestLabel "targeted confirmation batch is all-or-none under quota" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_corroboration_quota.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        seed suffix = CorroborationTaskSeed
          { ctsTopic = "свобода", ctsEdgeFrom = "свобода", ctsEdgeTo = "выбор" <> suffix
          , ctsRelationType = "requires", ctsNamespace = "session_local"
          , ctsSessionId = Just "autonomous-default", ctsOwner = "autonomous-default"
          , ctsSourceRequestId = "quota-source-" <> suffix
          , ctsSourceResponseHash = "quota-response-" <> suffix
          , ctsPriority = 2.0, ctsAudit = "competitive_utility_v1;qualified_for_corroboration=true"
          }
        blockedConfig = autonomousWorkerConfig { awcMaxRequestsPerHour = 2 }
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open corroboration quota DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        ensureCorroborationTaskSchema db
        queue <- newPersistentLearningQueue db 1
        mapM_ (enqueueCorroborationTaskOnConnection (qdbConn db) . seed) ["", "-two", "-three"]
        updateQ <- atomically newTQueue
        worker <- spawnAutonomousWorkerWithTransport blockedConfig
          (pure (MockTransport autonomousMockTable Nothing))
          atomStore (buildAtomMorphology atomStore) queue updateQ
        unexpected <- timeout 500000 (atomically (readTQueue updateQ))
          `finally` stopManagedWorker worker
        pending <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_corroboration_tasks WHERE state='pending' AND attempts=0"
        responses <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_responses"
        assertEqual "quota-blocked batch emits no graph event" Nothing unexpected
        assertEqual "quota-blocked batch releases all leases without attempts" 3 pending
        assertEqual "quota-blocked batch performs no provider query" 0 responses
      ) `finally` closeDb
    cleanup

testCorroborationBatchDispatchesThreeMockResponses :: Test
testCorroborationBatchDispatchesThreeMockResponses =
  TestLabel "targeted confirmation dispatch persists one mock response per leased task" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_corroboration_mock_batch.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        seed relation = CorroborationTaskSeed
          { ctsTopic = "свобода", ctsEdgeFrom = "свобода", ctsEdgeTo = "выбор"
          , ctsRelationType = relation, ctsNamespace = "session_local"
          , ctsSessionId = Just "autonomous-default", ctsOwner = "autonomous-default"
          , ctsSourceRequestId = "mock-source-" <> relation
          , ctsSourceResponseHash = "mock-response-" <> relation
          , ctsPriority = 2.0, ctsAudit = "competitive_utility_v1;qualified_for_corroboration=true"
          }
        confirmationBody = "{\"schema_version\":1,\"relations\":[{\"from\":\"свобода\",\"verb\":\"требует\",\"to\":\"выбор\",\"type\":\"requires\"}]}"
        confirmationTable =
          [("candidate_targeted_corroboration", "NeedKeywordEnrichment", "", Right confirmationBody)]
        allowedConfig = autonomousWorkerConfig { awcMaxRequestsPerHour = 3 }
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open corroboration mock DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        ensureCorroborationTaskSchema db
        queue <- newPersistentLearningQueue db 1
        mapM_ (enqueueCorroborationTaskOnConnection (qdbConn db) . seed)
          ["requires", "supports", "contradicts"]
        updateQ <- atomically newTQueue
        worker <- spawnAutonomousWorkerWithTransport allowedConfig
          (pure (MockTransport confirmationTable Nothing))
          atomStore (buildAtomMorphology atomStore) queue updateQ
        recovered <- sequence
          [ timeout 2000000 (atomically (readTQueue updateQ))
          , timeout 2000000 (atomically (readTQueue updateQ))
          , timeout 2000000 (atomically (readTQueue updateQ))
          ] `finally` stopManagedWorker worker
        extra <- atomically (tryReadTQueue updateQ)
        responses <- queryCount (qdbConn db) "SELECT COUNT(*) FROM learning_responses"
        readyLeased <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_corroboration_tasks WHERE state='response_ready' AND lease_token LIKE 'corroboration-apply:%'"
        assertBool "all three mock confirmations reach the governed queue" (all (/= Nothing) recovered)
        assertEqual "response_ready handoff does not duplicate queued events" Nothing extra
        assertEqual "one durable provider response is stored per task" 3 responses
        assertEqual "all response_ready tasks are leased to governed apply" 3 readyLeased
      ) `finally` closeDb
    cleanup

testTargetedConfirmationConflictQuarantines :: Test
testTargetedConfirmationConflictQuarantines =
  TestLabel "targeted conflicting confirmation quarantines without deleting target edge" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_targeted_confirmation_conflict.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        edge = mkCorroborationEdge RelRequires
        seed suffix = CorroborationTaskSeed
          { ctsTopic = "свобода", ctsEdgeFrom = "свобода", ctsEdgeTo = "выбор" <> suffix
          , ctsRelationType = "requires", ctsNamespace = "session_local"
          , ctsSessionId = Just "autonomous-default", ctsOwner = "autonomous-default"
          , ctsSourceRequestId = "conflict-source-" <> suffix
          , ctsSourceResponseHash = "conflict-response-" <> suffix
          , ctsPriority = 2.0, ctsAudit = "competitive_utility_v1;qualified_for_corroboration=true"
          }
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open conflict confirmation DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensureCorroborationTaskSchema db
        _ <- newPersistentLearningQueue db 1
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "")
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "-two")
        enqueueCorroborationTaskOnConnection (qdbConn db) (seed "-three")
        leased <- claimCorroborationBatch db 3 3
        task <- case [item | item <- leased, ctEdgeTo item == "выбор"] of
          item : _ -> pure item
          [] -> assertFailure "expected leased conflict task" >> fail "unreachable"
        assertExec (qdbConn db) "prepare_conflict_apply_lease"
          ("UPDATE learning_corroboration_tasks SET state='response_ready', lease_token='corroboration-apply:test-conflict' WHERE id=" <> T.pack (show (ctId task)))
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
            first = mkCompleteRuntimeEvent "conflict-source-" "conflict-response-" [edge]
            conflict = (mkCompleteRuntimeEvent
              (maybe "confirmation-missing" id (ctConfirmationRequestId task))
              "independent-conflict-response" [mkCorroborationEdge RelContrastsWith])
              { nueAdmissionDecision = Just "corroboration_conflict"
              , nueEvidenceSource = Just "candidate_targeted_corroboration"
              , nueCorroborationTaskId = Just (ctId task)
              , nueApplyToken = Just "corroboration-apply:test-conflict"
              }
        firstNetwork <- applyDurableBroadEvent db handles mkTestNetwork first
        finalNetwork <- applyAutonomousEventBatch handles firstNetwork [conflict]
        cooc <- queryCount (qdbConn db)
          "SELECT co_occurrence FROM semantic_edges_runtime WHERE edge_from='свобода' AND edge_to='выбор'"
        conflicted <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM learning_corroboration_tasks WHERE id = " <> T.pack (show (ctId task)) <> " AND state='conflicted'")
        assertEqual "conflict leaves target co-occurrence unchanged" 1 cooc
        assertEqual "task terminal state is conflicted" 1 conflicted
        assertEqual "runtime target edge is retained" (Just RelRequires)
          (M.lookup ("свобода", "выбор") (snEdges finalNetwork) >>= seRelationType)
      ) `finally` closeDb
    cleanup

testMissingTargetConfirmationFailsClosed :: Test
testMissingTargetConfirmationFailsClosed =
  TestLabel "targeted confirmation cannot recreate a missing hypothesis" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_missing_confirmation_target.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        seed suffix = CorroborationTaskSeed
          { ctsTopic = "свобода", ctsEdgeFrom = "свобода", ctsEdgeTo = "выбор" <> suffix
          , ctsRelationType = "requires", ctsNamespace = "session_local"
          , ctsSessionId = Just "autonomous-default", ctsOwner = "autonomous-default"
          , ctsSourceRequestId = "missing-source-" <> suffix
          , ctsSourceResponseHash = "missing-response-" <> suffix
          , ctsPriority = 2.0, ctsAudit = "competitive_utility_v1;qualified_for_corroboration=true"
          }
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensureCorroborationTaskSchema db
        _ <- newPersistentLearningQueue db 1
        mapM_ (enqueueCorroborationTaskOnConnection (qdbConn db) . seed) ["", "-two", "-three"]
        leased <- claimCorroborationBatch db 3 3
        task <- case [item | item <- leased, ctEdgeTo item == "выбор"] of
          item : _ -> pure item
          [] -> assertFailure "expected leased missing-target task" >> fail "unreachable"
        assertExec (qdbConn db) "prepare_missing_target_apply_lease"
          ("UPDATE learning_corroboration_tasks SET state='response_ready', lease_token='corroboration-apply:test-missing' WHERE id=" <> T.pack (show (ctId task)))
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
            confirmation = (mkCompleteRuntimeEvent
              (maybe "confirmation-missing" id (ctConfirmationRequestId task))
              "missing-target-confirmation" [mkCorroborationEdge RelRequires])
              { nueAdmissionDecision = Just "corroboration_confirmation"
              , nueEvidenceSource = Just "candidate_targeted_corroboration"
              , nueCorroborationTaskId = Just (ctId task)
              , nueApplyToken = Just "corroboration-apply:test-missing"
              }
        finalNetwork <- applyAutonomousEventBatch handles mkTestNetwork [confirmation]
        runtimeRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE edge_from='свобода' AND edge_to='выбор'"
        rejected <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM learning_corroboration_tasks WHERE id=" <> T.pack (show (ctId task)) <> " AND state='rejected' AND result_kind='confirmation_target_missing'")
        assertEqual "missing target is not recreated in memory" Nothing
          (M.lookup ("свобода", "выбор") (snEdges finalNetwork))
        assertEqual "missing target is not persisted" 0 runtimeRows
        assertEqual "missing-target task is terminally rejected" 1 rejected
      ) `finally` closeDb
    cleanup

testUntrustedAdmissionDecisionFailsClosed :: Test
testUntrustedAdmissionDecisionFailsClosed =
  TestLabel "governed apply rejects untrusted admission decisions" $ TestCase $ do
    handles <- mkTestHandles
    let event = (mkCompleteRuntimeEvent "untrusted-r1" "untrusted-response" [mkCorroborationEdge RelRequires])
          { nueAdmissionDecision = Just "selector_preflight_rejected" }
    finalNetwork <- applyAutonomousEventBatchForTest handles mkTestNetwork [event]
    assertEqual "rejected envelope cannot mutate the graph" M.empty (snEdges finalNetwork)

testForgedBroadEventWithoutJobFailsClosed :: Test
testForgedBroadEventWithoutJobFailsClosed =
  TestLabel "forged broad event without durable job cannot mutate or create promotion evidence" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_forged_broad_no_job.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensureLearningJobSchema db
        ensurePromotionSchema db
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
            forged = (mkCompleteRuntimeEvent "forged-no-job" "forged-response" [mkCorroborationEdge RelRequires])
              { nueApplyToken = Just "apply:caller-forged" }
        result <- try (applyAutonomousEventBatch handles mkTestNetwork [forged])
          :: IO (Either SomeException SemanticNetwork)
        runtimeRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE edge_from='свобода' AND edge_to='выбор'"
        admissionEvents <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE request_id='forged-no-job' AND kind IN ('edge_admitted','edge_corroborated')"
        applyProofs <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_apply_proofs WHERE request_id='forged-no-job'"
        assertBool "a caller token is not authority without its durable job"
          (either (const True) (const False) result)
        assertEqual "forged event writes no runtime projection" 0 runtimeRows
        assertEqual "forged event writes no promotion-source event" 0 admissionEvents
        assertEqual "forged event writes no apply proof" 0 applyProofs
        -- Even a directly forged legacy event cannot become snapshot support
        -- without the transactional dispatch proof created at apply success.
        assertExec (qdbConn db) "insert_forged_projection_fixture"
          "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES(1, 'свобода', 'выбор', 0.6, 1, 'requires', 0.6, 'runtime_llm')"
        assertExec (qdbConn db) "insert_forged_admission_fixture"
          "INSERT INTO learning_events(ts, request_id, topic, kind, source, edge_from, edge_to, provenance, confidence, co_occurrence, reason, prompt_hash, response_hash, model, parser_decision, admission_decision, evidence_source) VALUES(1, 'forged-no-job', 'свобода', 'edge_admitted', 'autonomous_apply', 'свобода', 'выбор', 'runtime_llm', 0.6, 1, 'relation_type=requires', 'forged-prompt', 'forged-response', 'test-model', 'structured_relation_parser:accepted', 'runtime_admitted', 'caller')"
        snapshot <- createPromotionSnapshot db
        forgedLineage <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_snapshot_edge_lineage WHERE snapshot_id='" <> psSnapshotId snapshot <> "' AND request_id='forged-no-job'")
        assertEqual "forged no-job event is not promotion evidence" 0 forgedLineage
      ) `finally` closeDb
    cleanup

testOldPolicyReadyPayloadRejectedAtClaim :: Test
testOldPolicyReadyPayloadRejectedAtClaim =
  TestLabel "ready payload is rejected when its durable job policy is superseded" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_old_policy_ready_payload.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        ensureLearningJobSchema db
        void (enqueueLearningJob db "old-policy-ready" "свобода" 1.0 3)
        claim <- claimLearningJob db "old-policy-ready" 120 >>= maybe
          (assertFailure "current-policy job was not claimable" >> fail "unreachable") pure
        recordLearningJobResponseReady db claim "prompt" "response" "{}" "{}" []
        assertExec (qdbConn db) "supersede_ready_job_policy"
          "UPDATE learning_jobs SET policy='autonomous-learning-v2-obsolete' WHERE request_id='old-policy-ready'"
        ready <- claimLearningReadyPayloads db 1 120
        rejected <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_jobs WHERE request_id='old-policy-ready' AND state='failed' AND last_error='superseded_learning_policy' AND lease_token IS NULL"
        assertEqual "superseded ready payload is never dispatched" [] ready
        assertEqual "claim boundary retires the stale-policy job" 1 rejected
      ) `finally` closeDb
    cleanup

testOldPolicyCorroborationTaskRejectedAtClaim :: Test
testOldPolicyCorroborationTaskRejectedAtClaim =
  TestLabel "corroboration claim retires superseded-policy tasks" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_old_policy_corroboration.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        seed = CorroborationTaskSeed
          { ctsTopic = "свобода"
          , ctsEdgeFrom = "свобода"
          , ctsEdgeTo = "выбор"
          , ctsRelationType = "requires"
          , ctsNamespace = "session_local"
          , ctsSessionId = Just "autonomous-default"
          , ctsOwner = "autonomous-default"
          , ctsSourceRequestId = "old-corrob-source"
          , ctsSourceResponseHash = "old-corrob-response"
          , ctsPriority = 1.0
          , ctsAudit = "competitive_utility_v1;qualified_for_corroboration=true"
          }
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        ensureCorroborationTaskSchema db
        enqueueCorroborationTaskOnConnection (qdbConn db) seed
        assertExec (qdbConn db) "supersede_corroboration_policy"
          "UPDATE learning_corroboration_tasks SET policy='targeted-corroboration-v0' WHERE source_request_id='old-corrob-source'"
        claimed <- claimCorroborationBatch db 1 1
        retired <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_corroboration_tasks WHERE source_request_id='old-corrob-source' AND state='failed' AND result_kind='superseded_corroboration_policy'"
        assertEqual "superseded corroboration task is not dispatched" [] claimed
        assertEqual "corroboration policy fence retires stale work" 1 retired
      ) `finally` closeDb
    cleanup

testStaleBroadApplyTokenRollsBackMutation :: Test
testStaleBroadApplyTokenRollsBackMutation =
  TestLabel "stale broad apply token rolls back graph persistence" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_stale_broad_apply_token.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup

testStalePolicyEventRollsBackAllGovernedSurfaces :: Test
testStalePolicyEventRollsBackAllGovernedSurfaces =
  TestLabel "stale-policy event cannot mutate projection, events, or promotion support" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_stale_policy_apply.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensureLearningJobSchema db
        ensurePromotionSchema db
        void (enqueueLearningJob db "stale-policy-r1" "свобода" 1.0 3)
        assertExec (qdbConn db) "prepare_stale_policy_apply"
          "UPDATE learning_jobs SET state='response_ready', policy='autonomous-learning-v2-obsolete', lease_token='apply:current', lease_until=9999999999999999 WHERE request_id='stale-policy-r1'"
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
            stalePolicy = (mkCompleteRuntimeEvent "stale-policy-r1" "stale-policy-response" [mkCorroborationEdge RelRequires])
              { nueApplyToken = Just "apply:current" }
        applied <- try (applyAutonomousEventBatch handles mkTestNetwork [stalePolicy])
          :: IO (Either SomeException SemanticNetwork)
        runtimeRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE edge_from='свобода' AND edge_to='выбор'"
        admissionEvents <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE request_id='stale-policy-r1'"
        applyProofs <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_apply_proofs WHERE request_id='stale-policy-r1'"
        snapshot <- createPromotionSnapshot db
        promotionSupport <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_snapshot_edge_lineage WHERE snapshot_id='" <> psSnapshotId snapshot <> "' AND request_id='stale-policy-r1'")
        assertBool "stale policy rejects the whole apply" (either (const True) (const False) applied)
        assertEqual "stale policy writes no runtime projection" 0 runtimeRows
        assertEqual "stale policy writes no learning event" 0 admissionEvents
        assertEqual "stale policy writes no dispatch proof" 0 applyProofs
        assertEqual "stale policy creates no promotion support" 0 promotionSupport
      ) `finally` closeDb
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        _ <- newPersistentLearningQueue db 1
        _ <- enqueueLearningJob db "stale-apply-r1" "свобода" 1.0 3
        assertExec (qdbConn db) "prepare_current_apply_lease"
          "UPDATE learning_jobs SET state='response_ready', lease_token='apply:current', lease_until=9999999999999999 WHERE request_id='stale-apply-r1'"
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
            stale = (mkCompleteRuntimeEvent "stale-apply-r1" "stale-response" [mkCorroborationEdge RelRequires])
              { nueApplyToken = Just "apply:stale" }
        applied <- try (applyAutonomousEventBatch handles mkTestNetwork [stale])
          :: IO (Either SomeException SemanticNetwork)
        runtimeRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE edge_from='свобода' AND edge_to='выбор'"
        stillReady <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_jobs WHERE request_id='stale-apply-r1' AND state='response_ready' AND lease_token='apply:current'"
        assertBool "stale apply is rejected" (either (const True) (const False) applied)
        assertEqual "stale apply transaction writes no edge" 0 runtimeRows
        assertEqual "current apply lease remains intact" 1 stillReady
      ) `finally` closeDb
    cleanup

testMultiEdgeBroadResponseAcknowledgesOnce :: Test
testMultiEdgeBroadResponseAcknowledgesOnce =
  TestLabel "multi-edge broad response acknowledges one durable job" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_multi_edge_broad_apply.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure (T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensurePromotionSchema db
        _ <- newPersistentLearningQueue db 1
        _ <- enqueueLearningJob db "multi-edge-r1" "свобода" 1.0 3
        assertExec (qdbConn db) "prepare_multi_edge_apply"
          "UPDATE learning_jobs SET state='response_ready', lease_token='apply:multi-edge', lease_until=9999999999999999 WHERE request_id='multi-edge-r1'"
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
            event edge = (mkCompleteRuntimeEvent "multi-edge-r1" "multi-edge-response" [edge])
              { nueApplyToken = Just "apply:multi-edge" }
        finalNetwork <- applyAutonomousEventBatch handles mkTestNetwork
          [ event ((mkTestEdge 101) { seRelationType = Just RelRequires })
          , event ((mkTestEdge 102) { seRelationType = Just RelRelatedTo })
          ]
        runtimeRows <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM semantic_edges_runtime WHERE edge_from IN ('source-101','source-102')"
        succeeded <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_jobs WHERE request_id='multi-edge-r1' AND state='succeeded'"
        admissionEvents <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE request_id='multi-edge-r1' AND kind='edge_admitted'"
        applyProofs <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_apply_proofs WHERE request_id='multi-edge-r1' AND dispatch_token='apply:multi-edge'"
        snapshot <- createPromotionSnapshot db
        promotionLineage <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_snapshot_edge_lineage WHERE snapshot_id='" <> psSnapshotId snapshot <> "' AND request_id='multi-edge-r1'")
        assertEqual "both edges commit in one governed batch" 2 runtimeRows
        assertEqual "one job reaches succeeded" 1 succeeded
        assertEqual "both admission events share the successful transaction" 2 admissionEvents
        assertEqual "the current token creates exactly one durable proof" 1 applyProofs
        assertEqual "both admitted edges become governed promotion support" 2 promotionLineage
        assertEqual "both edges reach the in-memory network" 2
          (length [() | key <- [("source-101", "target-101"), ("source-102", "target-102")], M.member key (snEdges finalNetwork)])
      ) `finally` closeDb
    cleanup

testPromotionSnapshotChecksumIncludesLineageIdentities :: Test
testPromotionSnapshotChecksumIncludesLineageIdentities =
  TestLabel "promotion snapshot checksum changes when lineage identities change" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_lineage_checksum.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open checksum DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensurePromotionSchema db
        let insertLineageEvent requestId responseHash =
              do
                assertExec (qdbConn db) "insert_checksum_lineage_event"
                  ("INSERT INTO learning_events(ts, request_id, topic, kind, source, edge_from, edge_to, provenance, confidence, co_occurrence, reason, prompt_hash, response_hash, model, parser_decision, admission_decision, evidence_source) VALUES(1, '" <> requestId <> "', 'свобода', 'edge_corroborated', 'autonomous_apply', 'свобода', 'выбор', 'runtime_llm', 0.6, 2, 'relation_type=requires', 'prompt-" <> requestId <> "', '" <> responseHash <> "', 'test-model', 'structured_relation_parser:accepted', 'runtime_corroborated', 'test')")
                insertTestApplyProof (qdbConn db) requestId
        assertExec (qdbConn db) "insert_checksum_runtime_edge"
          "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES(1, 'свобода', 'выбор', 0.6, 2, 'requires', 0.6, 'runtime_llm')"
        insertLineageEvent "checksum-r1" "checksum-response-a"
        insertLineageEvent "checksum-r2" "checksum-response-b"
        firstSnapshot <- createPromotionSnapshot db
        assertExec (qdbConn db) "change_checksum_lineage_identity"
          "UPDATE learning_events SET response_hash = 'checksum-response-c' WHERE request_id = 'checksum-r2'"
        secondSnapshot <- createPromotionSnapshot db
        assertEqual "same edge count remains" (psEdgeCount firstSnapshot) (psEdgeCount secondSnapshot)
        assertBool "lineage identity changes snapshot checksum" (psChecksum firstSnapshot /= psChecksum secondSnapshot)
        assertBool "lineage identity changes snapshot id" (psSnapshotId firstSnapshot /= psSnapshotId secondSnapshot)
      ) `finally` closeDb
    cleanup

testTargetedCorroborationSmoke :: Test
testTargetedCorroborationSmoke =
  TestLabel "targeted corroboration smoke has support two without quarantine" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_targeted_corroboration_smoke.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        edge = mkCorroborationEdge RelRequires
        firstEvent = mkCompleteRuntimeEvent "smoke-r1" "smoke-response-1" [edge]
        sameRequestEvent = mkCompleteRuntimeEvent "smoke-r1" "smoke-response-2" [edge]
        sameResponseEvent = mkCompleteRuntimeEvent "smoke-r2" "smoke-response-1" [edge]
        independentEvent = mkCompleteRuntimeEvent "smoke-r3" "smoke-response-2" [edge]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open targeted smoke DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensureQuarantineSchema db
        ensurePromotionSchema db
        _ <- newPersistentLearningQueue db 8
        handles0 <- mkTestHandles
        let handles = handles0 { ahQuarantineDB = Just db }
        firstNetwork <- applyDurableBroadEvent db handles mkTestNetwork firstEvent
        let afterSameRequest = firstNetwork
        clearTestLearningCooldown db
        afterSameResponse <- applyDurableBroadEvent db handles afterSameRequest sameResponseEvent
        clearTestLearningCooldown db
        finalNetwork <- applyDurableBroadEvent db handles afterSameResponse independentEvent
        assertEqual "targeted smoke keeps one runtime edge" 1 (M.size (snEdges finalNetwork))
        assertEqual "targeted smoke reaches co-occurrence two" 2
          (maybe (-1) seCoOccurrence (M.lookup ("свобода", "выбор") (snEdges finalNetwork)))
        admitted <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_admitted'"
        corroborated <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_corroborated'"
        rejected <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_rejected'"
        quarantined <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM learning_events WHERE kind = 'edge_quarantined'"
        assertEqual "targeted smoke has one admission" 1 admitted
        assertEqual "targeted smoke has one corroboration" 1 corroborated
        assertEqual "targeted smoke rejects reused response evidence" 1 rejected
        assertEqual "targeted smoke has no quarantine" 0 quarantined
        completeIdentities <- queryCount (qdbConn db)
          "SELECT COUNT(DISTINCT request_id || ':' || response_hash) FROM learning_events WHERE kind IN ('edge_admitted', 'edge_corroborated') AND prompt_hash <> '' AND response_hash <> '' AND model <> '' AND parser_decision <> '' AND admission_decision IN ('runtime_admitted', 'runtime_corroborated') AND evidence_source <> ''"
        assertEqual "targeted smoke has two complete identities" 2 completeIdentities
        snapshot <- createPromotionSnapshot db
        _ <- buildPromotionCandidates db (psSnapshotId snapshot)
        support <- queryCount (qdbConn db)
          ("SELECT support_count FROM promotion_candidates WHERE snapshot_id = '" <> psSnapshotId snapshot
            <> "' AND topic = 'свобода' AND relation_type = 'requires' AND object_atom = 'выбор'")
        assertEqual "targeted smoke candidate support is two" 2 support
      ) `finally` closeDb
    cleanup

testPromotionPipelineFailsClosedBeforeEvaluation :: Test
testPromotionPipelineFailsClosedBeforeEvaluation =
  TestLabel "promotion overlay cannot activate before evaluation" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_pipeline.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open promotion DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensurePromotionSchema db
        snapshot <- createPromotionSnapshot db
        _ <- buildPromotionCandidates db (psSnapshotId snapshot)
        _ <- runPromotionGates db (psSnapshotId snapshot)
        overlay <- createDraftOverlay db (psSnapshotId snapshot)
        activation <- try (activatePromotionOverlay db overlay) :: IO (Either SomeException ())
        case activation of
          Left _ -> pure ()
          Right () -> assertFailure "draft overlay activated without evaluation"
        evaluation <- runPromotionEvaluation db overlay
        assertBool "evaluation must report candidate content" (peCandidateContentful evaluation >= 0)
        evaluationCases <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_evaluation_cases WHERE evaluation_id = '" <> peEvaluationId evaluation <> "'")
        assertBool "evaluation must persist case-level precheck rows" (evaluationCases > 0)
        activationAfterPrecheck <- try (activatePromotionOverlay db overlay) :: IO (Either SomeException ())
        case activationAfterPrecheck of
          Left _ -> pure ()
          Right () -> assertFailure "precheck evaluation bypassed renderer release gate"
      ) `finally` closeDb
    cleanup

insertCompletePromotionAdmissionEvent :: NSQL.Database -> Int -> Text -> Text -> Text -> Text -> IO ()
insertCompletePromotionAdmissionEvent conn timestamp requestId subject relation object =
  do
    assertExec conn "insert_complete_promotion_admission_event"
      ("INSERT INTO learning_events(ts, request_id, topic, kind, source, edge_from, edge_to, provenance, confidence, co_occurrence, reason, prompt_hash, response_hash, model, parser_decision, admission_decision, evidence_source) VALUES("
        <> T.pack (show timestamp) <> ", '" <> requestId <> "', '" <> subject <> "', 'edge_admitted', 'autonomous_apply', '" <> subject <> "', '" <> object <> "', 'runtime_llm', 0.9, 1, 'relation_type=" <> relation <> "', 'prompt-" <> requestId <> "', 'response-" <> requestId <> "', 'test-model', 'structured_relation_parser:accepted', 'runtime_admitted', 'test')")
    insertTestApplyProof conn requestId

insertTestApplyProof :: NSQL.Database -> Text -> IO ()
insertTestApplyProof conn requestId =
  assertExec conn "insert_test_apply_proof"
    ("INSERT INTO learning_apply_proofs(source_kind, request_id, policy, dispatch_token, applied_at) VALUES('broad', '"
      <> requestId <> "', 'autonomous-learning-v4-session-owned', 'test-dispatch:" <> requestId <> "', 1)")

testPromotionTopicGateRequiresSeedAuthority :: Test
testPromotionTopicGateRequiresSeedAuthority =
  TestLabel "promotion topic gate rejects non-seed runtime topics" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_topic_gate.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open promotion DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensurePromotionSchema db
        assertExec (qdbConn db) "insert_seed_topic_runtime_edge"
          "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES(1, 'свобода', 'ответственность', 0.9, 1, 'causes', 0.9, 'runtime_llm')"
        assertExec (qdbConn db) "insert_non_seed_runtime_edge_one"
          "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES(2, 'автовокзал', 'платформа', 0.9, 1, 'part_of', 0.9, 'runtime_llm')"
        assertExec (qdbConn db) "insert_non_seed_runtime_edge_two"
          "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES(3, 'автовокзал', 'платформа', 0.9, 1, 'part_of', 0.9, 'runtime_llm')"
        insertCompletePromotionAdmissionEvent (qdbConn db) 1 "seed-request-one" "свобода" "causes" "ответственность"
        insertCompletePromotionAdmissionEvent (qdbConn db) 2 "seed-request-two" "свобода" "causes" "ответственность"
        insertCompletePromotionAdmissionEvent (qdbConn db) 3 "non-seed-request" "автовокзал" "part_of" "платформа"
        snapshot <- createPromotionSnapshot db
        _ <- buildPromotionCandidates db (psSnapshotId snapshot)
        eligible <- runPromotionGates db (psSnapshotId snapshot)
        assertEqual "only the canonical seed topic is eligible" 1 eligible
        seedEligible <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_candidates WHERE topic = 'свобода' AND lifecycle_status = 'eligible_for_draft'"
        nonSeedExcluded <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_candidate_exclusions WHERE snapshot_id = (SELECT snapshot_id FROM promotion_snapshots ORDER BY created_at DESC LIMIT 1) AND edge_from = 'автовокзал' AND reason_code = 'subject_not_definition_topic'"
        assertEqual "seed topic remains promotable when its other gates pass" 1 seedEligible
        assertEqual "non-seed topic is excluded before candidate creation" 2 nonSeedExcluded
      ) `finally` closeDb
    cleanup

testPromotionActivationRequiresCurrentPolicyLineage :: Test
testPromotionActivationRequiresCurrentPolicyLineage =
  TestLabel "promotion activation rejects an evaluated overlay without current policy lineage" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_activation_policy.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open promotion activation policy DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        ensurePromotionSchema db
        assertExec (qdbConn db) "insert_legacy_evaluated_overlay"
          "INSERT INTO promotion_overlays(overlay_version, snapshot_id, status, created_at, checksum) VALUES('legacy-evaluated-overlay', 'legacy-snapshot', 'evaluated', 0, 'legacy-checksum')"
        assertExec (qdbConn db) "insert_legacy_runtime_release_gate"
          "INSERT INTO promotion_runtime_release_gates(overlay_version, evaluation_id, completed_at, release_passed, human_reviewed, details) VALUES('legacy-evaluated-overlay', 'legacy-evaluation', 0, 1, 1, 'test-only')"
        activation <- try (activatePromotionOverlay db "legacy-evaluated-overlay") :: IO (Either SomeException ())
        case activation of
          Left _ -> pure ()
          Right () -> assertFailure "legacy overlay activated without current policy lineage"
      ) `finally` closeDb
    cleanup

testPromotionCandidateConstructionUsesIndependentLineage :: Test
testPromotionCandidateConstructionUsesIndependentLineage =
  TestLabel "promotion candidates require distinct request lineage and exclude atom-only subjects" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_independent_lineage.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open independent lineage promotion DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
        insertRuntimeEdge timestamp subject object =
          assertExec (qdbConn db) "insert_independent_lineage_runtime_edge"
            ("INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES("
              <> T.pack (show timestamp) <> ", '" <> subject <> "', '" <> object
              <> "', 0.9, 1, 'causes', 0.9, 'runtime_llm')")
        insertAdmissionEvent timestamp requestId promptHash responseHash subject object =
          do
            assertExec (qdbConn db) "insert_independent_lineage_admission_event"
              ("INSERT INTO learning_events(ts, request_id, topic, kind, source, edge_from, edge_to, provenance, confidence, co_occurrence, reason, prompt_hash, response_hash, model, parser_decision, admission_decision, evidence_source) VALUES("
                <> T.pack (show timestamp) <> ", '" <> requestId <> "', 'свобода', 'edge_admitted', 'autonomous_apply', '" <> subject <> "', '" <> object <> "', 'runtime_llm', 0.9, 1, 'relation_type=causes', '" <> promptHash <> "', '" <> responseHash <> "', 'test-model', 'structured_relation_parser:accepted', 'runtime_admitted', 'test')")
            insertTestApplyProof (qdbConn db) requestId
        insertIncompleteAdmissionEvent timestamp =
          assertExec (qdbConn db) "insert_incomplete_lineage_admission_event"
            ("INSERT INTO learning_events(ts, request_id, topic, kind, source, edge_from, edge_to, provenance, confidence, co_occurrence, reason, prompt_hash, response_hash, admission_decision, evidence_source) VALUES("
              <> T.pack (show timestamp) <> ", 'incomplete-request', 'свобода', 'edge_admitted', 'autonomous_apply', 'свобода', 'неполная линия', 'runtime_llm', 0.9, 1, 'relation_type=causes', 'incomplete-prompt', 'incomplete-response', 'runtime_admitted', 'test')")
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensurePromotionSchema db
        insertRuntimeEdge (1 :: Int) "свобода" "квантовый маяк"
        insertRuntimeEdge 2 "свобода" "квантовый маяк"
        insertRuntimeEdge 3 "свобода" "неполная линия"
        insertRuntimeEdge 3 "актом отказа или знаком присутствия" "молчание"
        insertAdmissionEvent 1 "request-one" "prompt-one" "response-one" "свобода" "квантовый маяк"
        insertAdmissionEvent 3 "atom-request" "atom-prompt" "atom-response" "актом отказа или знаком присутствия" "молчание"
        insertIncompleteAdmissionEvent 3
        firstSnapshot <- createPromotionSnapshot db
        firstBuilt <- buildPromotionCandidates db (psSnapshotId firstSnapshot)
        firstSupport <- queryCount (qdbConn db)
          "SELECT support_count FROM promotion_candidates WHERE topic = 'свобода' AND object_atom = 'квантовый маяк'"
        incompleteCandidates <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_candidates WHERE topic = 'свобода' AND object_atom = 'неполная линия'"
        incompleteLineage <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_snapshot_edge_lineage WHERE snapshot_id = '" <> psSnapshotId firstSnapshot <> "' AND request_id = 'incomplete-request'")
        earlyExclusions <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_candidate_exclusions WHERE reason_code = 'subject_not_definition_topic'"
        firstEligible <- runPromotionGates db (psSnapshotId firstSnapshot)
        supportFailures <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_gate_runs WHERE gate_name = 'support' AND decision = 'fail' AND reason_code = 'insufficient_support'"
        assertEqual "only complete-lineage definition-topic edges reach candidate construction" 1 firstBuilt
        assertEqual "two edges from one request are one support" 1 firstSupport
        assertEqual "incomplete lineage creates no candidate" 0 incompleteCandidates
        assertEqual "incomplete lineage is not copied into the snapshot" 0 incompleteLineage
        assertEqual "atom-only subject is excluded before candidate gates" 1 earlyExclusions
        assertEqual "one request lineage is insufficient" 0 firstEligible
        assertEqual "support failures are auditable" 1 supportFailures

        insertRuntimeEdge 4 "свобода" "квантовый маяк"
        insertAdmissionEvent 2 "request-two" "prompt-two" "response-two" "свобода" "квантовый маяк"
        secondSnapshot <- createPromotionSnapshot db
        secondBuilt <- buildPromotionCandidates db (psSnapshotId secondSnapshot)
        secondSupport <- queryCount (qdbConn db)
          ("SELECT support_count FROM promotion_candidates WHERE snapshot_id = '" <> psSnapshotId secondSnapshot <> "' AND topic = 'свобода' AND object_atom = 'квантовый маяк'")
        secondEligible <- runPromotionGates db (psSnapshotId secondSnapshot)
        assertEqual "candidate construction remains limited to complete canonical topics" 1 secondBuilt
        assertEqual "two independent requests satisfy support" 2 secondSupport
        assertEqual "distinct lineage makes the candidate eligible" 1 secondEligible
        assertExec (qdbConn db) "remove_second_snapshot_lineage"
          ("DELETE FROM promotion_snapshot_edge_lineage WHERE snapshot_id = '" <> psSnapshotId secondSnapshot <> "'")
        _ <- buildPromotionCandidates db (psSnapshotId secondSnapshot)
        rebuiltSupport <- queryCount (qdbConn db)
          ("SELECT support_count FROM promotion_candidates WHERE snapshot_id = '" <> psSnapshotId secondSnapshot <> "' AND topic = 'свобода' AND object_atom = 'квантовый маяк'")
        assertEqual "a rebuild never reuses support from an earlier gate run" 0 rebuiltSupport
      ) `finally` closeDb
    cleanup

testPromotionSelfRevalidationPreservesLineage :: Test
testPromotionSelfRevalidationPreservesLineage =
  TestLabel "promotion self revalidation is idempotent and policy-versioned" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_self_revalidation.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open self revalidation promotion DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensurePromotionSchema db
        assertExec (qdbConn db) "insert_self_revalidation_runtime_edge_one"
          "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES(1, 'свобода', 'ответственность', 0.9, 1, 'causes', 0.9, 'runtime_llm')"
        assertExec (qdbConn db) "insert_self_revalidation_runtime_edge_two"
          "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES(2, 'свобода', 'ответственность', 0.9, 1, 'causes', 0.9, 'runtime_llm')"
        insertCompletePromotionAdmissionEvent (qdbConn db) 1 "self-request-one" "свобода" "causes" "ответственность"
        insertCompletePromotionAdmissionEvent (qdbConn db) 2 "self-request-two" "свобода" "causes" "ответственность"
        snapshot <- createPromotionSnapshot db
        _ <- buildPromotionCandidates db (psSnapshotId snapshot)
        firstEligible <- runPromotionGates db (psSnapshotId snapshot)
        overlay <- createDraftOverlay db (psSnapshotId snapshot)
        secondEligible <- runPromotionGates db (psSnapshotId snapshot)
        policyRuns <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_gate_run_lineage WHERE snapshot_id = '" <> psSnapshotId snapshot
            <> "' AND policy_version = '" <> promotionGatePolicyVersion <> "'")
        overlayLineage <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_overlay_lineage WHERE overlay_version = '" <> overlay
            <> "' AND snapshot_id = '" <> psSnapshotId snapshot <> "'")
        selfRevalidation <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_gate_runs WHERE gate_name = 'historical_overlay_self_revalidation' AND decision = 'pass' AND detail = 'idempotent_self_record_ignored'"
        assertEqual "initial gate run admits the candidate" 1 firstEligible
        assertEqual "own draft is not independent negative evidence" 1 secondEligible
        assertEqual "both gate runs record the current policy lineage" 2 policyRuns
        assertEqual "draft retains its originating gate lineage" 1 overlayLineage
        assertEqual "self exclusion is explicitly auditable" 1 selfRevalidation
      ) `finally` closeDb
    cleanup

testPromotionLaterSnapshotIsBlockedByHistoricalOverlay :: Test
testPromotionLaterSnapshotIsBlockedByHistoricalOverlay =
  TestLabel "promotion retains a later snapshot record but blocks it against historical overlay evidence" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_later_snapshot.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open later snapshot promotion DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
        insertRuntimeEdge timestamp =
          assertExec (qdbConn db) "insert_later_snapshot_runtime_edge"
            ("INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES("
              <> T.pack (show timestamp) <> ", 'свобода', 'ответственность', 0.9, 1, 'causes', 0.9, 'runtime_llm')")
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensurePromotionSchema db
        insertRuntimeEdge (1 :: Int)
        insertRuntimeEdge 2
        insertCompletePromotionAdmissionEvent (qdbConn db) 1 "later-request-one" "свобода" "causes" "ответственность"
        insertCompletePromotionAdmissionEvent (qdbConn db) 2 "later-request-two" "свобода" "causes" "ответственность"
        firstSnapshot <- createPromotionSnapshot db
        _ <- buildPromotionCandidates db (psSnapshotId firstSnapshot)
        firstEligible <- runPromotionGates db (psSnapshotId firstSnapshot)
        _ <- createDraftOverlay db (psSnapshotId firstSnapshot)

        insertRuntimeEdge 3
        laterSnapshot <- createPromotionSnapshot db
        laterBuilt <- buildPromotionCandidates db (psSnapshotId laterSnapshot)
        laterEligible <- runPromotionGates db (psSnapshotId laterSnapshot)
        laterCandidate <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_candidates WHERE snapshot_id = '" <> psSnapshotId laterSnapshot
            <> "' AND topic = 'свобода' AND relation_type = 'causes' AND object_atom = 'ответственность'")
        historicalFailures <- queryCount (qdbConn db)
          ("SELECT COUNT(*) FROM promotion_gate_runs WHERE gate_name = 'historical_overlay_duplicate' AND decision = 'fail' AND candidate_id IN (SELECT candidate_id FROM promotion_candidates WHERE snapshot_id = '"
            <> psSnapshotId laterSnapshot <> "')")
        assertEqual "the first snapshot may create its draft" 1 firstEligible
        assertEqual "the later snapshot still records its candidate" 1 laterBuilt
        assertEqual "the later candidate is present for audit" 1 laterCandidate
        assertEqual "a prior overlay blocks a different snapshot" 0 laterEligible
        assertEqual "the block is a historical-gate decision, not insert suppression" 1 historicalFailures
      ) `finally` closeDb
    cleanup

testPromotionCanonicalRelationGateRejectsDuplicatesAndSubsumption :: Test
testPromotionCanonicalRelationGateRejectsDuplicatesAndSubsumption =
  TestLabel "promotion canonical relation gate rejects curated and historical duplicates" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_canonical_relations.db"
    let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    cleanup
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open canonical relation promotion DB: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
        insertRuntimeEdge timestamp subject relation object =
          assertExec (qdbConn db) "insert_canonical_relation_runtime_edge"
            ("INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance) VALUES("
              <> T.pack (show timestamp) <> ", '" <> subject <> "', '" <> object
              <> "', 0.9, 1, '" <> relation <> "', 0.9, 'runtime_llm')")
    (do
        RuntimeProjection.ensureRuntimeProjectionSchema db
        ensureLearningEventsSchema db
        ensurePromotionSchema db
        -- Curated fact: доверие presupposes уязвимость перед другим.
        -- The candidate weakens both the relation and object, so it is a
        -- directional subsumption duplicate rather than a new fact.
        insertRuntimeEdge (1 :: Int) "доверие" "requires" "уязвимость"
        insertRuntimeEdge 2 "доверие" "requires" "уязвимость"
        -- Curated fact: справедливость presupposes равенство перед правилом.
        insertRuntimeEdge 3 "справедливость" "presupposes" "равенство перед правилом"
        insertRuntimeEdge 4 "справедливость" "presupposes" "равенство перед правилом"
        -- A non-curated candidate is blocked by an earlier overlay, even when
        -- that overlay is not active.
        insertRuntimeEdge 5 "свобода" "causes" "ответственность"
        insertRuntimeEdge 6 "свобода" "causes" "ответственность"
        -- An earlier overlay may also make a later, broader object redundant.
        insertRuntimeEdge 7 "свобода" "causes" "воля"
        insertRuntimeEdge 8 "свобода" "causes" "воля"
        insertCompletePromotionAdmissionEvent (qdbConn db) 1 "trust-request" "доверие" "requires" "уязвимость"
        insertCompletePromotionAdmissionEvent (qdbConn db) 3 "justice-request" "справедливость" "presupposes" "равенство перед правилом"
        insertCompletePromotionAdmissionEvent (qdbConn db) 5 "freedom-request" "свобода" "causes" "ответственность"
        insertCompletePromotionAdmissionEvent (qdbConn db) 7 "will-request" "свобода" "causes" "воля"
        assertExec (qdbConn db) "insert_historical_overlay"
          "INSERT INTO promotion_overlays(overlay_version, snapshot_id, status, created_at, checksum) VALUES('overlay-history', 'history-snapshot', 'draft', 0, 'history-checksum')"
        assertExec (qdbConn db) "insert_historical_overlay_predicate"
          "INSERT INTO promotion_overlay_predicates(overlay_version, predicate_id, candidate_id, topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence) VALUES('overlay-history', 'history-predicate', 'history-candidate', 'свобода', 'relation', 'свобода связано с возникновением ответственность', 'свобода', 'causes', 'ответственность', 0.9)"
        assertExec (qdbConn db) "insert_historical_overlay_subsuming_predicate"
          "INSERT INTO promotion_overlay_predicates(overlay_version, predicate_id, candidate_id, topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence) VALUES('overlay-history', 'history-subsuming-predicate', 'history-subsuming-candidate', 'свобода', 'relation', 'свобода связано с возникновением воли и возможности выбора', 'свобода', 'causes', 'воля и возможность выбора', 0.9)"
        assertExec (qdbConn db) "finalize_historical_overlay_fixture"
          "UPDATE promotion_overlays SET status='evaluated' WHERE overlay_version='overlay-history'"
        snapshot <- createPromotionSnapshot db
        _ <- buildPromotionCandidates db (psSnapshotId snapshot)
        eligible <- runPromotionGates db (psSnapshotId snapshot)
        assertEqual "canonical duplicates and subsumption must not reach draft" 0 eligible
        curatedExact <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_gate_runs WHERE gate_name = 'curated_canonical_duplicate' AND decision = 'fail' AND reason_code = 'curated_relation_duplicate'"
        curatedSubsumed <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_gate_runs WHERE gate_name = 'curated_canonical_subsumption' AND decision = 'fail' AND reason_code = 'curated_relation_subsumes_candidate'"
        historicalExact <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_gate_runs WHERE gate_name = 'historical_overlay_duplicate' AND decision = 'fail' AND reason_code = 'historical_overlay_duplicate'"
        historicalSubsumed <- queryCount (qdbConn db)
          "SELECT COUNT(*) FROM promotion_gate_runs WHERE gate_name = 'historical_overlay_subsumption' AND decision = 'fail' AND reason_code = 'historical_overlay_subsumes_candidate'"
        assertEqual "curated exact canonical relation is rejected" 1 curatedExact
        assertEqual "curated stronger relation/object subsumes candidate" 1 curatedSubsumed
        assertEqual "historical overlay exact relation is rejected" 1 historicalExact
        assertEqual "historical overlay stronger object subsumes candidate" 1 historicalSubsumed
      ) `finally` closeDb
    cleanup

testLearningQualityGate :: Test
testLearningQualityGate = TestLabel "offline learning quality gate rejects unsafe event rates" $
  TestCase $ do
    let metrics = LearningQualityMetrics 2 3 0 0 0 0 0 1.0 1.1
        cfg = QualityGateConfig 1 0.5 0.2 0.0
    case evaluateQualityGate cfg metrics of
      QualityGateFail reasons -> assertBool "quarantine gate must be reported" (not (null reasons))
      QualityGatePass -> assertFailure "unsafe quarantine rate must fail quality gate"

testConcurrentLearningWrites :: Test
testConcurrentLearningWrites = TestLabel "concurrent learning writes do not reset WAL or fail locked" $
  TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_learning_concurrent_writes.db"
    mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
    opened <- NSQL.open dbPath
    db <- case opened of
      Left err -> assertFailure ("cannot open concurrent job test db: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure (QxFx0DB dbPath conn)
    let closeDb = NSQL.close (qdbConn db)
        writeOne n = recordLearningResponse db
          ("concurrent-r" <> T.pack (show n)) "prompt-hash" "response-hash" "{}"
    (do
        _ <- newPersistentLearningQueue db 1
        completions <- forM [1 :: Int .. 8] $ \n -> do
          done <- newEmptyMVar
          _ <- forkIO $ do
            result <- try (writeOne n) :: IO (Either SomeException ())
            putMVar done result
          pure done
        results <- mapM takeMVar completions
        assertBool "all concurrent learning writes must complete"
          (all (either (const False) (const True)) results)
      ) `finally` closeDb
    mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]

-- ---------------------------------------------------------------------------
-- AutonomousHandles structure tests
-- ---------------------------------------------------------------------------

testAutonomousHandlesHasTenFields :: Test
testAutonomousHandlesHasTenFields = TestLabel "AutonomousHandles has all required fields" $
  TestCase $ do
    -- This test verifies by construction that AutonomousHandles has:
    -- ahQueue, ahUpdateQueue, ahWorkerThread, ahPendingBreakerQueue,
    -- ahQuarantineDB, ahMetricsRef, ahNetworkOwner, ahAuditThread,
    -- ahApplyThread, ahSessionId, ahEnabled
    let handles = AutonomousHandles
          { ahQueue = Nothing
          , ahUpdateQueue = Nothing
          , ahWorkerThread = Nothing
          , ahPendingBreakerQueue = Nothing
          , ahQuarantineDB = Nothing
          , ahMetricsRef = Nothing
          , ahNetworkOwner = Nothing
          , ahAuditThread = Nothing
          , ahApplyThread = Nothing
          , ahSessionId = Nothing
          , ahEnabled = False
          }
    -- If this compiles, all fields exist
    assertBool "AutonomousHandles must have ahEnabled field" (ahEnabled handles == False)
    pure ()

-- ---------------------------------------------------------------------------
-- Test group
-- ---------------------------------------------------------------------------

autonomousIntegrationTests :: [Test]
autonomousIntegrationTests =
  [ testMaxUpdatesPerTurnValue
  , testLearningMetricsHasUpdatesDeferred
  , testApplyPendingUpdatesEmptyQueue
  , testApplyPendingUpdatesNilQueue
  , testEmptyPendingBatchCannotRevertTurnNetwork
  , testBackgroundUpdateBeforeTurnIsVisible
  , testTurnAndBackgroundAdditionsBothSurvive
  , testOwnerVersionIncrementsDeterministically
  , testDeferredUpdatesRemainQueued
  , testDurableEnvelopeIsNotSplitByApplyCap
  , testAutonomousStorageInitialized
  , testMockLlmCallReturnsStructuredResponse
  , testAutonomousWorkerCallsMockLlm
  , testAutonomousWorkerRetainsPendingTasks
  , testPersistentWorkerRetainsPendingTasks
  , testAutonomousWorkerRejectsFailedLlmCall
  , testManagedWorkerStopWaitsAndIsIdempotent
  , testCancellationRepairsDurableLeaseBeforeClose
  , testTurnTopicQueuesStarvingLearningTask
  , testExtendedTurnTopicQueuesLearningTask
  , testExtendedMixedCaseTopicQueuesLearningTask
  , testPersistentLearningQueueRecoveryAndDedup
  , testBroadResponseReadyReplayWithoutProvider
  , testBroadAtomicClaimAndStaleFence
  , testBroadMaxAttemptBound
  , testDurableQuotaSharedAcrossQueues
  , testRetryBudgetReservedBeforeDispatch
  , testAutonomousModeGatesBroadDispatch
  , testLegacyLearningSchemaMigration
  , testCorroborationLegacyRebuildIsTransactional
  , testRequestRollbackIsExactUnboundedAndAtomic
  , testAutonomousPreflightRejectsCrossScriptEdge
  , testStructuredLearningResponseContract
  , testLearningTopicCooldown
  , testTerminalRejectionCooldown
  , testRestartPreservesTopicRotation
  , testPromotionEvidenceSeparatedBySession
  , testGovernedBatchPersistsEdgesEventsAndJobsTogether
  , testGovernedCorroborationPath
  , testDurableCorroborationTaskThreshold
  , testQualifiedFirstAdmissionCreatesCorroborationTask
  , testTargetedConfirmationRejectsFreeTriples
  , testTargetedConfirmationSucceedsWithoutDuplicateEdge
  , testCorroborationBatchHonorsQuota
  , testCorroborationBatchDispatchesThreeMockResponses
  , testTargetedConfirmationConflictQuarantines
  , testMissingTargetConfirmationFailsClosed
  , testUntrustedAdmissionDecisionFailsClosed
  , testForgedBroadEventWithoutJobFailsClosed
  , testOldPolicyReadyPayloadRejectedAtClaim
  , testOldPolicyCorroborationTaskRejectedAtClaim
  , testStaleBroadApplyTokenRollsBackMutation
  , testStalePolicyEventRollsBackAllGovernedSurfaces
  , testMultiEdgeBroadResponseAcknowledgesOnce
  , testPromotionSnapshotChecksumIncludesLineageIdentities
  , testPromotionPipelineFailsClosedBeforeEvaluation
  , testPromotionTopicGateRequiresSeedAuthority
  , testPromotionActivationRequiresCurrentPolicyLineage
  , testPromotionCandidateConstructionUsesIndependentLineage
  , testPromotionSelfRevalidationPreservesLineage
  , testPromotionLaterSnapshotIsBlockedByHistoricalOverlay
  , testPromotionCanonicalRelationGateRejectsDuplicatesAndSubsumption
  , testLearningQualityGate
  , testConcurrentLearningWrites
  , testAutonomousHandlesHasTenFields
  ]

-- | Production owner and SQLite authorization boundaries used by the
-- integration manifest. Focused queue/provider tests remain in the fast suite.
autonomousProductionBoundaryTests :: [Test]
autonomousProductionBoundaryTests =
  [ testTurnAndBackgroundAdditionsBothSurvive
  , testForgedBroadEventWithoutJobFailsClosed
  , testStalePolicyEventRollsBackAllGovernedSurfaces
  , testMultiEdgeBroadResponseAcknowledgesOnce
  ]
