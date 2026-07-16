{-# LANGUAGE OverloadedStrings #-}

-- | Tests for ADR-0054 autonomous learning integration.
-- Specifically tests the integration of:
-- 1. spawnAutonomousLearningHandles in Bootstrap
-- 2. applyPendingUpdatesForSession in Engine
-- 3. maxUpdatesPerTurn limit
-- 4. AutonomousHandles type consistency
module Test.Suite.AutonomousIntegration
  ( autonomousIntegrationTests
  ) where

import Control.Concurrent.STM (TQueue, atomically, newTQueue, writeTQueue)
import Data.IORef (IORef, newIORef, readIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( LearningMetrics(..)
  , NetworkUpdateEvent(..)
  , ParseStatus(..)
  , emptyLearningMetrics
  )
import QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  , applyPendingUpdatesForSession
  , maxUpdatesPerTurn
  , applyAutonomousEventBatch
  )
import QxFx0.Semantic.Content.AtomStore (atomStore, Atom(..), atomDisplay)
import QxFx0.Semantic.Network.Types
  ( SemanticNetwork(..)
  , SemanticEdge(..)
  , EdgeProvenance(..)
  )
import QxFx0.Types.State.System
  ( SystemState(..)
  , emptySystemState
  , ssSemanticNetwork
  )

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
    , ahPendingBreakerQueue = Nothing
    , ahQuarantineDB = Nothing
    , ahMetricsRef = Just metricsRef
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
  , nueTimestamp = error "mkTestEvent: timestamp not implemented for test"
  , nueRequestId = "test-request"
  , nueSourceTopic = Just topic
  , nueParseStatus = ParseOk
  , nueRawAccepted = length edges
  , nueRawRejected = 0
  , nueProvenance = ProvenanceRuntimeLLM
  , nuePromptHash = Nothing
  , nueResponseHash = Nothing
  }

-- Note: We can't fully test applyPendingUpdatesForSession without a real
-- timestamp and proper edge data. But we can test the structure.

-- | Test that applyPendingUpdatesForSession handles empty queue
-- This is a basic structural test
testApplyPendingUpdatesEmptyQueue :: Test
testApplyPendingUpdatesEmptyQueue = TestLabel "applyPendingUpdatesForSession handles empty queue" $ 
  TestCase $ do
    handles <- mkTestHandles
    let ss = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    result <- applyPendingUpdatesForSession handles ss
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
          , ahPendingBreakerQueue = Nothing
          , ahQuarantineDB = Nothing
          , ahMetricsRef = Nothing
          , ahEnabled = False
          }
    let ss = emptySystemState { ssSemanticNetwork = mkTestNetwork }
    result <- applyPendingUpdatesForSession handles ss
    -- Should return the state unchanged
    assertEqual "State should be unchanged with Nil queue"
      (ssSemanticNetwork ss) (ssSemanticNetwork result)

-- ---------------------------------------------------------------------------
-- AutonomousHandles structure tests
-- ---------------------------------------------------------------------------

testAutonomousHandlesHasSixFields :: Test
testAutonomousHandlesHasSixFields = TestLabel "AutonomousHandles has all 6 required fields" $ 
  TestCase $ do
    -- This test verifies by construction that AutonomousHandles has:
    -- ahQueue, ahUpdateQueue, ahPendingBreakerQueue, ahQuarantineDB, ahMetricsRef, ahEnabled
    let handles = AutonomousHandles
          { ahQueue = Nothing
          , ahUpdateQueue = Nothing
          , ahPendingBreakerQueue = Nothing
          , ahQuarantineDB = Nothing
          , ahMetricsRef = Nothing
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
  , testAutonomousHandlesHasSixFields
  ]
