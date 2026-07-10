{-# LANGUAGE OverloadedStrings #-}

-- | ADR-0054 M2 regression tests for the content density gate.
module Test.Suite.DensityGate
  ( densityGateTests
  ) where

import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( enqueueIfStarving
  , enqueueStarvingTopics
  , newLearningQueue
  , drainLearningQueue
  )
import QxFx0.Semantic.Network.Seed
  ( DensityConfig(..)
  , defaultDensityConfig
  , contentDensity
  , starvingTopics
  )
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , semanticEdge
  )
import qualified QxFx0.Semantic.Network.Types as NetTypes

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkEdge :: Text -> Text -> SemanticEdge
mkEdge f t = semanticEdge f t 0.5 1 ExplicitEdge

mkNetwork :: [(Text, Text)] -> SemanticNetwork
mkNetwork edges =
  let edgeMap = M.fromList [ ((f, t), mkEdge f t) | (f, t) <- edges ]
      nodes   = S.fromList (concat [ [f, t] | (f, t) <- edges ])
  in SemanticNetwork
       { snNodes         = nodes
       , snEdges         = edgeMap
       , snActivation    = M.empty
       , snDecayRate     = 0.5
       , snMaxHops       = 3
       , snActivationLog = mempty
       }

-- ---------------------------------------------------------------------------
-- contentDensity
-- ---------------------------------------------------------------------------

testContentDensityEmptyTopic :: Test
testContentDensityEmptyTopic = TestLabel "contentDensity returns 0 for empty atom set" $
  TestCase $ do
    let net = mkNetwork []
    assertEqual "empty atoms → 0" 0.0 (contentDensity net S.empty 3.0)

testContentDensityFullTopic :: Test
testContentDensityFullTopic = TestLabel "contentDensity = |E_T|/(|A_T|*κ)" $
  TestCase $ do
    let -- topic 't1' has atoms {a,b,c}; edges ab, ac, bc are all internal
        net = mkNetwork [("a","b"), ("a","c"), ("b","c")]
        atoms = S.fromList ["a","b","c"]
    -- 3 internal edges / (3 atoms * 3 κ) = 0.333…
    assertEqual "ρ(t1) = 1/3"  (1.0/3.0 :: Double) (contentDensity net atoms 3.0)

testContentDensityPartialTopic :: Test
testContentDensityPartialTopic = TestLabel "contentDensity counts only internal edges" $
  TestCase $ do
    let -- topic 't1' has atoms {a,b}; only edge ab is internal (ac is out)
        net = mkNetwork [("a","b"), ("a","c")]
        atoms = S.fromList ["a","b"]
    -- 1 internal edge / (2 atoms * 3 κ) = 0.1666…
    assertEqual "ρ = 1/6" (1.0/6.0 :: Double) (contentDensity net atoms 3.0)

-- ---------------------------------------------------------------------------
-- DensityConfig
-- ---------------------------------------------------------------------------

testDefaultDensityConfig :: Test
testDefaultDensityConfig = TestLabel "defaultDensityConfig: κ=3, τ=0.15" $
  TestCase $ do
    let cfg = defaultDensityConfig
    assertEqual "κ"   3.0  (dcKappa cfg)
    assertEqual "τ"   0.15 (dcThreshold cfg)

-- ---------------------------------------------------------------------------
-- starvingTopics
-- ---------------------------------------------------------------------------

testStarvingTopicsEmpty :: Test
testStarvingTopicsEmpty = TestLabel "starvingTopics with empty network" $
  TestCase $ do
    let net = mkNetwork []
        -- single topic with 3 atoms and no internal edges → starving
        map_ = M.fromList [("t1", S.fromList ["a","b","c"])]
    assertEqual "t1 is starving" ["t1"] (starvingTopics net map_ defaultDensityConfig)

testStarvingTopicsFed :: Test
testStarvingTopicsFed = TestLabel "starvingTopics with dense topic" $
  TestCase $ do
    -- 3 atoms, 9 internal edges (complete graph) → ρ = 9/(3*3) = 1.0
    let edges = [ ("a","b"), ("a","c"), ("b","c")
                , ("b","a"), ("c","a"), ("c","b")
                , ("a","a"), ("b","b"), ("c","c") ]
        net = mkNetwork edges
        map_ = M.fromList [("t1", S.fromList ["a","b","c"])]
    assertEqual "t1 not starving" [] (starvingTopics net map_ defaultDensityConfig)

-- ---------------------------------------------------------------------------
-- enqueueIfStarving / enqueueStarvingTopics
-- ---------------------------------------------------------------------------

testEnqueueIfStarvingTrue :: Test
testEnqueueIfStarvingTrue = TestLabel "enqueueIfStarving enqueues starving topic" $
  TestCase $ do
    q <- newLearningQueue
    let net = mkNetwork []
        lemmaMap = M.empty :: M.Map Text Text
    ok <- enqueueIfStarving q lemmaMap defaultDensityConfig "свобода" net
    assertBool "should return True" ok
    tasks <- drainLearningQueue q
    assertEqual "one task enqueued" 1 (length tasks)

testEnqueueIfStarvingFalse :: Test
testEnqueueIfStarvingFalse = TestLabel "enqueueIfStarving skips unknown topic" $
  TestCase $ do
    q <- newLearningQueue
    -- 'несуществующий_топик_99999' is NOT in the curated topicAtomsMap,
    -- so the helper returns False (topic not found).
    let net = mkNetwork []
        lemmaMap = M.empty :: M.Map Text Text
    ok <- enqueueIfStarving q lemmaMap defaultDensityConfig "несуществующий_топик_99999" net
    assertBool "should return False" (not ok)
    tasks <- drainLearningQueue q
    assertEqual "no tasks" 0 (length tasks)

testEnqueueStarvingTopicsCount :: Test
testEnqueueStarvingTopicsCount = TestLabel "enqueueStarvingTopics returns count" $
  TestCase $ do
    q <- newLearningQueue
    -- Empty network → every topic in topicAtomsMap is starving.
    let net = mkNetwork []
        lemmaMap = M.empty :: M.Map Text Text
    n <- enqueueStarvingTopics q lemmaMap defaultDensityConfig net
    assertBool "should enqueue > 0 tasks" (n > 0)

-- ---------------------------------------------------------------------------
-- Test group
-- ---------------------------------------------------------------------------

densityGateTests :: [Test]
densityGateTests =
  [ testContentDensityEmptyTopic
  , testContentDensityFullTopic
  , testContentDensityPartialTopic
  , testDefaultDensityConfig
  , testStarvingTopicsEmpty
  , testStarvingTopicsFed
  , testEnqueueIfStarvingTrue
  , testEnqueueIfStarvingFalse
  , testEnqueueStarvingTopicsCount
  ]
