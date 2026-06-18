{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.ContentSelector (contentSelectorTests) where

import Test.HUnit
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Vector as V

import QxFx0.Semantic.ContentSelector
import QxFx0.Semantic.Space
import QxFx0.Self.Field

contentSelectorTests :: [Test]
contentSelectorTests =
  [ TestLabel "selectPredicates returns empty for unknown topic" $ TestCase $ do
      let cs = emptyContentSelector
          field = emptyField
          result = selectPredicates cs field "unknown_topic"
      assertEqual "should return empty list" [] result

  , TestLabel "selectPredicates returns predicates for known topic" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0]))
                , (FdAtmosphere, DimensionPrototype FdAtmosphere (S.fromList ["atom2"]) (V.fromList [0.0, 1.0]))
                ]
            }
          topicAtoms = M.singleton "test_topic" (S.fromList ["atom1", "atom2"])
          cs = buildContentSelector space topicAtoms
          field = emptyField
          result = selectPredicates cs field "test_topic"
      assertBool "should return at least one predicate" (not (null result))
      let sp = head result
      assertEqual "predicate id should match topic" "test_topic" (spPredicateId sp)
      assertBool "score should be positive" (spScore sp > 0)
  ]
