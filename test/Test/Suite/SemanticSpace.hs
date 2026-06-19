{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SemanticSpace (semanticSpaceTests) where

import Test.HUnit
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Vector as V

import QxFx0.Semantic.Space
import QxFx0.Semantic.Network

semanticSpaceTests :: [Test]
semanticSpaceTests =
  [ TestLabel "computeFieldAffinity returns 1.0 for identical vectors" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 3
            , ssAtomIndex = M.fromList [("a", 0), ("b", 1), ("c", 2)]
            , ssPrototypes = M.singleton FdResonance $ DimensionPrototype
                { dpDimension = FdResonance
                , dpAtoms = S.fromList ["a", "b"]
                , dpVector = V.fromList [1.0, 1.0, 0.0]
                }
            }
          pv = PredicateVector
            { pvPredicateId = "test"
            , pvAtoms = S.fromList ["a", "b"]
            , pvVector = V.fromList [1.0, 1.0, 0.0]
            }
          affinity = computeFieldAffinity space FdResonance pv
      assertBool "affinity should be 1.0" (abs (affinity - 1.0) < 0.001)

  , TestLabel "computeFieldAffinity returns 0.0 for unknown prototype" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 3
            , ssAtomIndex = M.fromList [("a", 0), ("b", 1), ("c", 2)]
            , ssPrototypes = M.empty
            }
          pv = PredicateVector
            { pvPredicateId = "test"
            , pvAtoms = S.fromList ["a", "b"]
            , pvVector = V.fromList [1.0, 1.0, 0.0]
            }
          affinity = computeFieldAffinity space FdResonance pv
      assertBool "affinity should be 0.0 (no prototype)" (abs (affinity - 0.0) < 0.001)

  , TestLabel "computeFieldAffinity changes with prototype" $ TestCase $ do
      let space1 = emptySemanticSpace
            { ssDimensionCount = 3
            , ssAtomIndex = M.fromList [("a", 0), ("b", 1), ("c", 2)]
            , ssPrototypes = M.singleton FdResonance $ DimensionPrototype
                { dpDimension = FdResonance
                , dpAtoms = S.fromList ["a", "b"]
                , dpVector = V.fromList [1.0, 1.0, 0.0]
                }
            }
          space2 = emptySemanticSpace
            { ssDimensionCount = 3
            , ssAtomIndex = M.fromList [("a", 0), ("b", 1), ("c", 2)]
            , ssPrototypes = M.singleton FdResonance $ DimensionPrototype
                { dpDimension = FdResonance
                , dpAtoms = S.fromList ["c"]
                , dpVector = V.fromList [0.0, 0.0, 1.0]
                }
            }
          pv = PredicateVector
            { pvPredicateId = "test"
            , pvAtoms = S.fromList ["a", "b"]
            , pvVector = V.fromList [1.0, 1.0, 0.0]
            }
          affinity1 = computeFieldAffinity space1 FdResonance pv
          affinity2 = computeFieldAffinity space2 FdResonance pv
      assertBool "affinity1 should be > 0.5" (affinity1 > 0.5)
      assertBool "affinity2 should be < 0.5" (affinity2 < 0.5)
      assertBool "affinities should differ" (abs (affinity1 - affinity2) > 0.1)

  , TestLabel "FdResonance prototype gives high affinity for relation atoms" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 4
            , ssAtomIndex = M.fromList [("связь", 0), ("отношение", 1), ("эффект", 2), ("количество", 3)]
            , ssPrototypes = M.singleton FdResonance $ DimensionPrototype
                { dpDimension = FdResonance
                , dpAtoms = S.fromList ["связь", "отношение"]
                , dpVector = V.fromList [1.0, 1.0, 0.0, 0.0]
                }
            }
          pv = PredicateVector
            { pvPredicateId = "test"
            , pvAtoms = S.fromList ["связь", "отношение"]
            , pvVector = V.fromList [1.0, 1.0, 0.0, 0.0]
            }
          affinity = computeFieldAffinity space FdResonance pv
      assertBool "affinity should be > 0.5" (affinity > 0.5)

  , TestLabel "buildPredicateVector creates correct vector" $ TestCase $ do
      let sn = emptySemanticNetwork
            { snNodes = S.fromList ["a", "b", "c"]
            }
          pv = buildPredicateVector sn "test" (S.fromList ["a", "c"])
      assertEqual "vector length should match node count" 3 (V.length (pvVector pv))
      assertBool "atom 'a' should be active" (pvVector pv V.! 0 > 0.5)
      assertBool "atom 'c' should be active" (pvVector pv V.! 2 > 0.5)
      assertBool "atom 'b' should be inactive" (pvVector pv V.! 1 < 0.5)
  ]
