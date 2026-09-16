{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'QxFx0.Semantic.Composition' (shadow-only v1).
--
-- The suite pins the structural-discrimination contract that
-- justifies replacing Jaccard overlap: role-blind scoring cannot
-- tell «свобода требует ответственности» from its converse, while
-- 'structScore' can.  No runtime behaviour depends on these tests;
-- cutover needs a corpus win on human labels (see
-- docs\/closure\/CALIBRATION_CORPUS.md).
module Test.Suite.Composition
  ( compositionTests
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Semantic.Composition

testLemmaMap :: M.Map T.Text T.Text
testLemmaMap = M.fromList
  [ ("требует", "требовать")
  , ("ответственности", "ответственность")
  , ("свободы", "свобода")
  , ("исключает", "исключать")
  ]

compositionTests :: [Test]
compositionTests =
  [ TestLabel "parse is total on empty text" $ TestCase $ do
      let t = parsePredicateTerm M.empty ""
      assertEqual "headless" Nothing (ptHead t)
      assertBool "no rels" (S.null (ptRels t))
      assertBool "no mods" (S.null (ptMods t))
      assertBool "no negation" (not (ptNeg t))

  , TestLabel "short roots are kept (Jaccard len>3 channel reopened)" $ TestCase $ do
      let t = parsePredicateTerm M.empty "зло требует осмысления"
      assertEqual "head keeps 3-letter root" (Just "зло") (ptHead t)

  , TestLabel "negation is recorded, marker never enters sets" $ TestCase $ do
      let t = parsePredicateTerm M.empty "не хочу жить"
      assertBool "neg flag" (ptNeg t)
      assertEqual "head is the content word" (Just "хочу") (ptHead t)
      assertBool "marker not a modifier" (not (S.member "не" (ptMods t)))
      let plain = parsePredicateTerm M.empty "хочу жить"
      assertBool "plain has no neg" (not (ptNeg plain))
      assertBool "negation caps score below 1"
        (structScore plain t < 1.0)

  , TestLabel "relation pairs verb with following concept" $ TestCase $ do
      let t = parsePredicateTerm testLemmaMap
                "свобода требует ответственности"
      assertEqual "head" (Just "свобода") (ptHead t)
      assertEqual "rel pair"
        (S.singleton ("требовать", "ответственность")) (ptRels t)

  , TestLabel "self score is exactly 1" $ TestCase $ do
      let t = parsePredicateTerm testLemmaMap
                "свобода требует осознанной ответственности"
      assertEqual "identity" 1.0 (structScore t t)

  , TestLabel "converse predicates: struct discriminates, Jaccard does not" $ TestCase $ do
      let fwd = parsePredicateTerm testLemmaMap
                  "свобода требует ответственности"
          bwd = parsePredicateTerm testLemmaMap
                  "ответственность требует свободы"
          j = jaccardBaseline fwd bwd
          s = structScore fwd bwd
      assertEqual "jaccard is blind to direction" 1.0 j
      assertBool ("struct sees direction, got " ++ show s) (s < 0.5)
      assertBool "struct below jaccard here" (s < j)

  , TestLabel "directionality: superset predicate covers subset query" $ TestCase $ do
      let q = parsePredicateTerm testLemmaMap "свобода требует выбора"
          p = parsePredicateTerm testLemmaMap
                "свобода требует выбора и исключает принуждение"
      assertBool "query-covered scores higher"
        (structScore q p > structScore p q)

  , TestLabel "scores stay in [0,1]" $ TestCase $ do
      let terms = [ parsePredicateTerm testLemmaMap s
                  | s <- [ "свобода требует ответственности"
                         , "ответственность требует свободы"
                         , "не хочу жить", "", "зло", "истина" ] ]
          scores = [ structScore a b | a <- terms, b <- terms ]
      assertBool "all in range" (all (\x -> x >= 0.0 && x <= 1.0) scores)

  , TestLabel "relation lexicon v1 is frozen and copula-free" $ TestCase $ do
      assertEqual "version pin" "relation-lexicon-v1" relationLexiconVersion
      assertBool "content verb present"
        (S.member "требовать" relationLexicon)
      assertBool "copula excluded"
        (not (S.member "является" relationLexicon))
      assertBool "negation marker not a relation"
        (not (S.member "не" relationLexicon))
  ]
