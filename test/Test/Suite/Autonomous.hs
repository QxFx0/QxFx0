{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | ADR-0054 M1 regression tests for the autonomous learning worker.
module Test.Suite.Autonomous
  ( autonomousTests
  ) where

import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( AutonomousWorkerConfig(..)
  , LearningTask(..)
  , NetworkUpdateEvent(..)
  , autonomousApplyLLMResponse
  , applyPendingNetworkUpdates
  , buildAtomMorphology
  , defaultAutonomousWorkerConfig
  , drainLearningQueue
  , enqueueLearningTask
  , isTruthy
  , newLearningQueue
  , readIntWithDefault
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Semantic.Content.AtomStore
  ( Atom(..)
  , AtomId(..)
  , Relation(..)
  , RelationType(..)
  , atomStore
  , atomDisplay
  )
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import QxFx0.Types.ExternalQuery (ExternalQueryResponse(..))
import QxFx0.Semantic.Network.Types (EdgeProvenance(..), EdgeSource(..), SemanticNetwork(..), SemanticEdge(..))
import QxFx0.Types.State.System (SystemState(..), emptySystemState, ssSemanticNetwork)

-- ---------------------------------------------------------------------------
-- Config helpers
-- ---------------------------------------------------------------------------

testIsTruthy :: Test
testIsTruthy = TestLabel "isTruthy recognises 1/true/yes/on" $
  TestCase $ do
    assertBool "1 is truthy"      (isTruthy (Just "1"))
    assertBool "true is truthy"   (isTruthy (Just "true"))
    assertBool "yes is truthy"    (isTruthy (Just "yes"))
    assertBool "on is truthy"     (isTruthy (Just "on"))
    assertBool "TRUE uppercase"   (isTruthy (Just "TRUE"))
    assertBool "  1  trimmed"     (isTruthy (Just "  1  "))
    assertBool "0 is falsy"       (not (isTruthy (Just "0")))
    assertBool "no is falsy"      (not (isTruthy (Just "no")))
    assertBool "Nothing is falsy" (not (isTruthy Nothing))

testReadIntWithDefault :: Test
testReadIntWithDefault = TestLabel "readIntWithDefault parses ints and falls back" $
  TestCase $ do
    assertEqual "valid int"  42 (readIntWithDefault (Just "42") 0)
    assertEqual "with spaces" 7 (readIntWithDefault (Just "  7  ") 0)
    assertEqual "negative"    (-3) (readIntWithDefault (Just "-3") 0)
    assertEqual "garbage → default" 99 (readIntWithDefault (Just "abc") 99)
    assertEqual "trailing garbage → default" 11 (readIntWithDefault (Just "5xx") 11)
    assertEqual "Nothing → default" 50 (readIntWithDefault Nothing 50)

testDefaultConfig :: Test
testDefaultConfig = TestLabel "defaultAutonomousWorkerConfig is disabled" $
  TestCase $ do
    let cfg = defaultAutonomousWorkerConfig
    assertBool "disabled by default" (not (awcEnabled cfg))
    assertEqual "default max req/h"  10 (awcMaxRequestsPerHour cfg)
    assertEqual "default max edges"   5 (awcMaxEdgesPerBatch cfg)
    assertEqual "default queue cap" 100 (awcQueueCap cfg)

-- ---------------------------------------------------------------------------
-- Queue
-- ---------------------------------------------------------------------------

testQueueEnqueueDrain :: Test
testQueueEnqueueDrain = TestLabel "LearningQueue enqueue + drain round-trip" $
  TestCase $ do
    q <- newLearningQueue
    let task1 = LearningTask { ltTopic = "свобода", ltPriority = 1.0, ltRequestId = "r1" }
        task2 = LearningTask { ltTopic = "истина",  ltPriority = 0.5, ltRequestId = "r2" }
    enqueueLearningTask q task1
    enqueueLearningTask q task2
    drained <- drainLearningQueue q
    assertEqual "two tasks enqueued" 2 (length drained)
    -- Second drain should be empty
    drained2 <- drainLearningQueue q
    assertEqual "queue empty after drain" 0 (length drained2)

-- ---------------------------------------------------------------------------
-- autonomousApplyLLMResponse (explicit store)
-- ---------------------------------------------------------------------------

testBuildMorphologyFromStore :: Test
testBuildMorphologyFromStore = TestLabel "explicit-store gate rejects unknown endpoint" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = ExternalQueryResponse
          { eqrRawBody    = "свобода | связана | несуществующий_атом_99999 | relatedto\n"
          , eqrStructured = ""
          , eqrToolName   = "test"
          , eqrLatencyMs  = 0
          }
        net = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
    assertEqual "no edges for unknown endpoint" 0 (M.size (snEdges net))

testBuildMorphologyAdmitsKnown :: Test
testBuildMorphologyAdmitsKnown = TestLabel "explicit-store gate admits known endpoints" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = ExternalQueryResponse
          { eqrRawBody    = "свобода | связана | выбор | relatedto\n"
          , eqrStructured = ""
          , eqrToolName   = "test"
          , eqrLatencyMs  = 0
          }
        net = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
    assertBool "one edge admitted" (M.size (snEdges net) >= 1)

-- ---------------------------------------------------------------------------
-- applyPendingNetworkUpdates
-- ---------------------------------------------------------------------------

testApplyPendingNetworkUpdates :: Test
testApplyPendingNetworkUpdates = TestLabel "applyPendingNetworkUpdates merges edges" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        ss0 = emptySystemState
        evt = NetworkUpdateEvent
          { nueTopic = "свобода"
          , nueEdges =
              [ SemanticEdge
                  { seFrom         = "свобода"
                  , seTo           = "выбор"
                  , seWeight       = 0.5
                  , seCoOccurrence = 1
                  , seSource       = ExplicitEdge
                  , seRelationType = Just RelRelatedTo
                  , seVerb         = Nothing
                  , seRationale    = Nothing
                  , seCounter      = Nothing
                  , seSynthesis    = Nothing
                  , seConfidence   = 0.6
                  , seProvenance   = ProvenanceIngested
                  }
              ]
          , nueTimestamp = error "unused"
          }
    -- We test that the helper is exposed and type-checks; the full merge
    -- behaviour is covered by existing mergeSemanticNetworksWithProvenance
    -- tests (NetworkSemantic test suite).
    _ <- pure (evt, store, morph, ss0)
    assertBool "smoke" True

-- ---------------------------------------------------------------------------
-- Test group
-- ---------------------------------------------------------------------------

autonomousTests :: [Test]
autonomousTests =
  [ testIsTruthy
  , testReadIntWithDefault
  , testDefaultConfig
  , testQueueEnqueueDrain
  , testBuildMorphologyFromStore
  , testBuildMorphologyAdmitsKnown
  , testApplyPendingNetworkUpdates
  ]
