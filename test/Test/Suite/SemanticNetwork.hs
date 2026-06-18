{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SemanticNetwork
  ( semanticNetworkTests
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Core.MeaningGraph
import QxFx0.Semantic.Network

semanticNetworkTests :: [Test]
semanticNetworkTests =
  [ TestLabel "buildFromEmptyGraph" $ TestCase $ do
      let mg = emptyMeaningGraph
          sn = buildSemanticNetwork mg
      assertEqual "nodes should be empty" S.empty (snNodes sn)
      assertEqual "edges should be empty" M.empty (snEdges sn)

  , TestLabel "extractsNodesFromEdges" $ TestCase $ do
      let stateNode = MeaningState ResonanceMed PressNone DepthShallow
          strategy = ResponseStrategy ShallowResp OpenStance ValidateMove DensityLow
          mg = MeaningGraph
            { mgEdges =
                [ MeaningEdge "state1" "state2" stateNode stateNode strategy 5 3 0.0 Nothing (S.fromList ["atom1", "atom2"])
                ]
            , mgTurnCount = 1
            }
          sn = buildSemanticNetwork mg
      assertEqual "should have 2 nodes" 2 (S.size (snNodes sn))
      assertBool "should contain atom1" (S.member "atom1" (snNodes sn))
      assertBool "should contain atom2" (S.member "atom2" (snNodes sn))

  , TestLabel "createsEdgesBetweenCooccurringAtoms" $ TestCase $ do
      let stateNode = MeaningState ResonanceMed PressNone DepthShallow
          strategy = ResponseStrategy ShallowResp OpenStance ValidateMove DensityLow
          mg = MeaningGraph
            { mgEdges =
                [ MeaningEdge "state1" "state2" stateNode stateNode strategy 5 3 0.0 Nothing (S.fromList ["atom1", "atom2", "atom3"])
                ]
            , mgTurnCount = 1
            }
          sn = buildSemanticNetwork mg
      assertBool "should have edge atom1->atom2" (M.member ("atom1", "atom2") (snEdges sn))
      assertBool "should have edge atom2->atom1" (M.member ("atom2", "atom1") (snEdges sn))
      assertBool "should have edge atom1->atom3" (M.member ("atom1", "atom3") (snEdges sn))

  , TestLabel "activatesSeedAtom" $ TestCase $ do
      let sn = SemanticNetwork
            { snNodes = S.fromList ["seed", "neighbor"]
            , snEdges = M.empty
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
          sn' = activate "seed" sn
          act = snActivation sn'
      assertEqual "seed should have activation 1.0" (Just 1.0) (M.lookup "seed" act)

  , TestLabel "propagatesActivationToNeighbors" $ TestCase $ do
      let sn = SemanticNetwork
            { snNodes = S.fromList ["seed", "neighbor"]
            , snEdges = M.fromList
                [ (("seed", "neighbor"), SemanticEdge "seed" "neighbor" 0.8 5)
                ]
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
          sn' = activate "seed" sn
          act = snActivation sn'
      assertEqual "seed should have activation 1.0" (Just 1.0) (M.lookup "seed" act)
      assertBool "neighbor should have activation > 0" (maybe False (> 0) (M.lookup "neighbor" act))
      let Just neighborAct = M.lookup "neighbor" act
      assertBool "neighbor activation should be < 1.0" (neighborAct < 1.0)

  , TestLabel "respectsMaxHopsLimit" $ TestCase $ do
      let sn = SemanticNetwork
            { snNodes = S.fromList ["a", "b", "c", "d", "e"]
            , snEdges = M.fromList
                [ (("a", "b"), SemanticEdge "a" "b" 1.0 5)
                , (("b", "c"), SemanticEdge "b" "c" 1.0 5)
                , (("c", "d"), SemanticEdge "c" "d" 1.0 5)
                , (("d", "e"), SemanticEdge "d" "e" 1.0 5)
                ]
            , snActivation = M.empty
            , snDecayRate = 1.0
            , snMaxHops = 2
            }
          sn' = activate "a" sn
          act = snActivation sn'
      assertBool "a should be activated" (M.member "a" act)
      assertBool "b should be activated (1 hop)" (M.member "b" act)
      assertBool "c should be activated (2 hops)" (M.member "c" act)
      assertBool "d should NOT be activated (3 hops > maxHops=2)" (not (M.member "d" act))
      assertBool "e should NOT be activated (4 hops > maxHops=2)" (not (M.member "e" act))

  , TestLabel "contentDensityGateEmpty" $ TestCase $ do
      let sn = SemanticNetwork
            { snNodes = S.empty
            , snEdges = M.empty
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
      assertBool "should fail gate" (not (contentDensityGate sn))

  , TestLabel "contentDensityGateBelowThreshold" $ TestCase $ do
      let sn = SemanticNetwork
            { snNodes = S.fromList ["a", "b", "c"]
            , snEdges = M.fromList [(("a", "b"), SemanticEdge "a" "b" 1.0 1)]
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
      assertBool "should fail gate (3 nodes < 15)" (not (contentDensityGate sn))

  , TestLabel "contentDensityGateAboveThreshold" $ TestCase $ do
      let nodes = S.fromList [T.pack $ "n" <> show i | i <- [1..20 :: Int]]
          edges = M.fromList [((T.pack $ "n" <> show i, T.pack $ "n" <> show (i+1)), SemanticEdge (T.pack $ "n" <> show i) (T.pack $ "n" <> show (i+1)) 1.0 1) | i <- [1..60 :: Int]]
          sn = SemanticNetwork
            { snNodes = nodes
            , snEdges = edges
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
      assertBool "should pass gate (20 nodes >= 15, 60 edges >= 50)" (contentDensityGate sn)
  ]
