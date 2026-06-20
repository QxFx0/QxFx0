{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.ContentSelector (contentSelectorTests) where

import Test.HUnit
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Vector as V

import QxFx0.Semantic.ContentSelector
import QxFx0.Semantic.Space
import QxFx0.Semantic.Content
import QxFx0.Semantic.Network
import QxFx0.Core.MeaningGraph
import QxFx0.Self.Field

contentSelectorTests :: [Test]
contentSelectorTests =
  [ TestLabel "tokenizePredicate filters stop words" $ TestCase $ do
      let result = tokenizePredicate M.empty "это есть и или но"
      assertEqual "should filter all stop words" S.empty result

  , TestLabel "tokenizePredicate keeps content words" $ TestCase $ do
      let result = tokenizePredicate M.empty "ответственность требует осознания"
      assertBool "should keep 'ответственность'" (S.member "ответственность" result)
      assertBool "should keep 'требует'" (S.member "требует" result)
      assertBool "should keep 'осознания'" (S.member "осознания" result)

  , TestLabel "tokenizePredicate overlaps with fieldDimensionPrototypes" $ TestCase $ do
      let predicates = [ "истина претендует на соответствие реальности"
                       , "ответственность требует осознания последствий"
                       , "мнение выражает позицию субъекта"
                       ]
          allTokens = S.unions [tokenizePredicate M.empty p | p <- predicates]
          allPrototypeWords = S.unions [S.fromList words | words <- M.elems fieldDimensionPrototypes]
          overlap = S.intersection allTokens allPrototypeWords
      assertBool "should have overlap with prototypes" (not (S.null overlap))

  , TestLabel "selectPredicates returns empty for unknown topic" $ TestCase $ do
      let cs = emptyContentSelector
          field = emptyField
          result = selectPredicates cs field "unknown_topic" Nothing
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
          topicPredicates = M.singleton "test_topic" [SemanticPredicate RoleProperty "atom1 atom2" "atom1 atom2" "atom1"]
          cs = buildContentSelector space topicAtoms topicPredicates M.empty
          field = emptyField { fieldResonance = Resonance 0.8, fieldAtmosphere = Atmosphere 0.5 0.5 }
          result = selectPredicates cs field "test_topic" Nothing
      assertBool "should return at least one predicate" (not (null result))
      let sp = head result
      assertEqual "predicate id should match topic" "test_topic" (spPredicateId sp)
      assertBool "score should be positive" (spScore sp > 0)

  , TestLabel "different Field values produce different scores" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0]))
                , (FdAtmosphere, DimensionPrototype FdAtmosphere (S.fromList ["atom2"]) (V.fromList [0.0, 1.0]))
                ]
            }
          topicAtoms = M.singleton "test_topic" (S.fromList ["atom1"])
          topicPredicates = M.singleton "test_topic" [SemanticPredicate RoleProperty "atom1 atom2" "atom1 atom2" "atom1"]
          cs = buildContentSelector space topicAtoms topicPredicates M.empty
          field1 = emptyField { fieldResonance = Resonance 0.9, fieldAtmosphere = Atmosphere 0.1 0.5 }
          field2 = emptyField { fieldResonance = Resonance 0.2, fieldAtmosphere = Atmosphere 0.9 0.5 }
          result1 = selectPredicates cs field1 "test_topic" Nothing
          result2 = selectPredicates cs field2 "test_topic" Nothing
      assertBool "should return predicates for field1" (not (null result1))
      assertBool "should return predicates for field2" (not (null result2))
      let score1 = spScore (head result1)
          score2 = spScore (head result2)
      assertBool "scores should differ based on field" (abs (score1 - score2) > 0.01)

  , TestLabel "affinity is not always 0.5 when atoms match prototypes" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0]))
                ]
            }
          topicAtoms = M.singleton "test_topic" (S.fromList ["atom1"])
          topicPredicates = M.singleton "test_topic" [SemanticPredicate RoleProperty "atom1 atom2" "atom1 atom2" "atom1"]
          cs = buildContentSelector space topicAtoms topicPredicates M.empty
          field = emptyField { fieldResonance = Resonance 1.0 }
          result = selectPredicates cs field "test_topic" Nothing
      assertBool "should return predicates" (not (null result))
      let sp = head result
      assertBool "score should not be exactly 0.5" (abs (spScore sp - 0.5) > 0.01)

  , TestLabel "real definitionCorpus atom overlap" $ TestCase $ do
      let predicates = [ SemanticPredicate RoleProperty "истина претендует на соответствие реальности" "truth claims correspondence with reality" "истина"
                       , SemanticPredicate RoleRelation "ответственность требует осознания последствий" "responsibility requires awareness of consequences" "ответственность"
                       ]
          tokenizedAtoms = S.unions [tokenizePredicate M.empty (spRu p) | p <- predicates]
          mg = MeaningGraph
            { mgEdges =
                [ MeaningEdge "state1" "state2"
                    (MeaningState ResonanceHigh PressNone DepthAxiom)
                    (MeaningState ResonanceHigh PressNone DepthAxiom)
                    (ResponseStrategy DeepResp OpenStance ValidateMove DensityHigh)
                    10 5 0.8 Nothing
                    tokenizedAtoms
                ]
            , mgTurnCount = 1
            }
          sn = buildSemanticNetwork mg
          topic = "истина"
          topicAtoms = M.singleton topic tokenizedAtoms
          space = buildSemanticSpace sn topicAtoms
          topicPreds = M.singleton topic predicates
          cs = buildContentSelector space topicAtoms topicPreds M.empty
          field1 = emptyField { fieldResonance = Resonance 0.9, fieldAtmosphere = Atmosphere 0.1 0.5, fieldConsolidation = Consolidation 0.9 }
          field2 = emptyField { fieldResonance = Resonance 0.1, fieldAtmosphere = Atmosphere 0.9 0.5, fieldConsolidation = Consolidation 0.1 }
          result1 = selectPredicates cs field1 topic Nothing
          result2 = selectPredicates cs field2 topic Nothing
          hasOverlap = any (\dim -> any (\word -> S.member word (snNodes sn))
            (M.findWithDefault [] dim fieldDimensionPrototypes)) [FdResonance ..]
          totalScore1 = sum [spScore sp | sp <- result1]
          totalScore2 = sum [spScore sp | sp <- result2]
      assertBool "atoms must overlap with fieldDimensionPrototypes" hasOverlap
      assertBool "should return predicates for field1" (not (null result1))
      assertBool "should return predicates for field2" (not (null result2))
      assertBool "different field → different total scores" (abs (totalScore1 - totalScore2) > 0.01)

  , TestLabel "different Field selects different predicates for same topic" $ TestCase $ do
      let pred1 = SemanticPredicate RoleProperty "истина претендует на соответствие реальности" "truth claims correspondence" "истина"
          pred2 = SemanticPredicate RoleStructure "истина проверяется через воспроизводимость" "truth is verified through reproducibility" "истина"
          atoms1 = tokenizePredicate M.empty (spRu pred1)
          atoms2 = tokenizePredicate M.empty (spRu pred2)
          allAtoms = S.union atoms1 atoms2
          atomList = S.toList allAtoms
          atomIdx = M.fromList (zip atomList [0..])
          dimCount = length atomList
          mkVec atoms = V.generate dimCount (\i ->
            let atom = atomList !! i in if S.member atom atoms then 1.0 else 0.0)
          confVec = V.generate dimCount (\i ->
            let atom = atomList !! i in if atom == "претендует" then 1.0 else 0.0)
          counterVec = V.generate dimCount (\i ->
            let atom = atomList !! i in if atom == "воспроизводимость" then 1.0 else 0.0)
          space = emptySemanticSpace
            { ssDimensionCount = dimCount
            , ssAtomIndex = atomIdx
            , ssPrototypes = M.fromList
                [ (FdConfidence, DimensionPrototype FdConfidence (S.singleton "претендует") confVec)
                , (FdCounterfactual, DimensionPrototype FdCounterfactual (S.singleton "воспроизводимость") counterVec)
                ]
            }
          topicPreds = M.singleton "истина" [pred1, pred2]
          cs = buildContentSelector space M.empty topicPreds M.empty
          fieldConf = emptyField { fieldConfidence = FieldConfidence 1.0, fieldCounterfactual = Counterfactual 0.0 }
          fieldCounter = emptyField { fieldConfidence = FieldConfidence 0.0, fieldCounterfactual = Counterfactual 1.0 }
          resultConf = selectPredicates cs fieldConf "истина" Nothing
          resultCounter = selectPredicates cs fieldCounter "истина" Nothing
          predsConf = concatMap spPredicates resultConf
          predsCounter = concatMap spPredicates resultCounter
      assertBool "high-confidence field should select pred1" (pred1 `elem` predsConf)
      assertBool "high-counterfactual field should select pred2" (pred2 `elem` predsCounter)
      assertBool "selected predicate sets should differ" (predsConf /= predsCounter)

  , TestLabel "activation bonus increases score" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0]))
                ]
            }
          topicAtoms = M.singleton "test_topic" (S.fromList ["atom1", "atom2"])
          topicPredicates = M.singleton "test_topic" [SemanticPredicate RoleProperty "atom1 atom2" "atom1 atom2" "atom1"]
          cs = buildContentSelector space topicAtoms topicPredicates M.empty
          field = emptyField { fieldResonance = Resonance 0.8 }
          activatedNetwork = SemanticNetwork
            { snNodes = S.fromList ["atom1", "atom2"]
            , snEdges = M.empty
            , snActivation = M.fromList [("atom1", 1.0), ("atom2", 0.5)]
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
          resultWithout = selectPredicates cs field "test_topic" Nothing
          resultWith = selectPredicates cs field "test_topic" (Just activatedNetwork)
      assertBool "should return predicates without activation" (not (null resultWithout))
      assertBool "should return predicates with activation" (not (null resultWith))
      let scoreWithout = spScore (head resultWithout)
          scoreWith = spScore (head resultWith)
      assertBool "activation should increase score" (scoreWith > scoreWithout)
      assertBool "score increase should be significant" (scoreWith > scoreWithout * 1.1)

  , TestLabel "composePredicates returns empty for empty input" $ TestCase $ do
      let cs = emptyContentSelector
          field = emptyField
          result = composePredicates cs field [] Nothing
      assertEqual "should return empty list" [] result

  , TestLabel "composePredicates combines multiple predicates" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0]))
                , (FdAtmosphere, DimensionPrototype FdAtmosphere (S.fromList ["atom2"]) (V.fromList [0.0, 1.0]))
                ]
            }
          pred1 = SemanticPredicate RoleProperty "atom1 atom2" "atom1 atom2" "test_topic"
          pred2 = SemanticPredicate RoleRelation "atom2 atom1" "atom2 atom1" "test_topic"
          cs = buildContentSelector space M.empty (M.singleton "test_topic" [pred1, pred2]) M.empty
          field = emptyField { fieldResonance = Resonance 0.8, fieldAtmosphere = Atmosphere 0.5 0.5 }
          result = composePredicates cs field [pred1, pred2] Nothing
      assertBool "should return at least one predicate" (not (null result))
      assertBool "should return at most 2 predicates" (length result <= 2)

  , TestLabel "composePredicates filters low-activation predicates" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0]))
                ]
            }
          pred1 = SemanticPredicate RoleProperty "atom1" "atom1" "test_topic"
          pred2 = SemanticPredicate RoleRelation "atom2" "atom2" "test_topic"
          cs = buildContentSelector space M.empty (M.singleton "test_topic" [pred1, pred2]) M.empty
          field = emptyField { fieldResonance = Resonance 0.9 }
          result = composePredicates cs field [pred1, pred2] Nothing
      assertBool "should return predicates" (not (null result))
      assertBool "high-activation pred1 should be included" (pred1 `elem` result)
      assertBool "low-activation pred2 should be filtered" (pred2 `notElem` result)

  , TestLabel "composePredicates respects activation from network" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0]))
                ]
            }
          pred1 = SemanticPredicate RoleProperty "atom1" "atom1" "test_topic"
          pred2 = SemanticPredicate RoleRelation "atom1 atom2" "atom1 atom2" "test_topic"
          cs = buildContentSelector space M.empty (M.singleton "test_topic" [pred1, pred2]) M.empty
          field = emptyField { fieldResonance = Resonance 0.5 }
          activatedNetwork = SemanticNetwork
            { snNodes = S.fromList ["atom1", "atom2"]
            , snEdges = M.empty
            , snActivation = M.fromList [("atom2", 5.0)]
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
          resultWithout = composePredicates cs field [pred1, pred2] Nothing
          resultWith = composePredicates cs field [pred1, pred2] (Just activatedNetwork)
      assertBool "should return predicates without activation" (not (null resultWithout))
      assertBool "should return predicates with activation" (not (null resultWith))
      assertBool "activation should include more predicates" (length resultWith >= length resultWithout)

  , TestLabel "composeFromActivation finds overlapping topics" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 3
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1), ("atom3", 2)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1"]) (V.fromList [1.0, 0.0, 0.0]))
                ]
            }
          pred1 = SemanticPredicate RoleProperty "atom1 atom2" "atom1 atom2" "topic1"
          pred2 = SemanticPredicate RoleRelation "atom2 atom3" "atom2 atom3" "topic2"
          topicAtoms = M.fromList
            [ ("topic1", S.fromList ["atom1", "atom2"])
            , ("topic2", S.fromList ["atom2", "atom3"])
            ]
          topicPreds = M.fromList
            [ ("topic1", [pred1])
            , ("topic2", [pred2])
            ]
          cs = buildContentSelector space topicAtoms topicPreds M.empty
          field = emptyField { fieldResonance = Resonance 0.8 }
          network = SemanticNetwork
            { snNodes = S.fromList ["atom1", "atom2", "atom3"]
            , snEdges = M.fromList
                [ (("atom1", "atom2"), SemanticEdge "atom1" "atom2" 0.8 10 ExplicitEdge)
                , (("atom2", "atom3"), SemanticEdge "atom2" "atom3" 0.8 10 ExplicitEdge)
                ]
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
          result = composeFromActivation cs field "topic1" network
      assertBool "should return predicates from overlapping topics" (length result >= 1)
      assertBool "pred1 from topic1 should be included" (pred1 `elem` result)

  , TestLabel "composeFromActivation weights by activation" $ TestCase $ do
      let space = emptySemanticSpace
            { ssDimensionCount = 2
            , ssAtomIndex = M.fromList [("atom1", 0), ("atom2", 1)]
            , ssPrototypes = M.fromList
                [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["atom1", "atom2"]) (V.fromList [1.0, 1.0]))
                ]
            }
          pred1 = SemanticPredicate RoleProperty "atom1" "atom1" "topic1"
          pred2 = SemanticPredicate RoleRelation "atom2" "atom2" "topic2"
          topicAtoms = M.fromList
            [ ("topic1", S.fromList ["atom1"])
            , ("topic2", S.fromList ["atom2"])
            ]
          topicPreds = M.fromList
            [ ("topic1", [pred1])
            , ("topic2", [pred2])
            ]
          cs = buildContentSelector space topicAtoms topicPreds M.empty
          field = emptyField { fieldResonance = Resonance 0.9 }
          network = SemanticNetwork
            { snNodes = S.fromList ["atom1", "atom2"]
            , snEdges = M.fromList
                [ (("atom1", "atom2"), SemanticEdge "atom1" "atom2" 0.9 10 ExplicitEdge)
                ]
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            }
          result = composeFromActivation cs field "topic1" network
      assertBool "should return predicates" (not (null result))
      assertBool "should return at most 3 predicates" (length result <= 3)
  ]
