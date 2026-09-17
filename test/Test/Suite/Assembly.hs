{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'QxFx0.Semantic.Assembly' (shadow-only v1).
-- Pins the bridge rule: shared concept + differing sources compose;
-- identical sources and bridgeless pairs do not.
module Test.Suite.Assembly
  ( assemblyTests
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Semantic.Assembly
import QxFx0.Semantic.Composition

testLemmaMap :: M.Map T.Text T.Text
testLemmaMap = M.fromList
  [ ("требует", "требовать")
  , ("ответственности", "ответственность")
  , ("свободы", "свобода")
  , ("исключает", "исключать")
  ]

term :: T.Text -> PredicateTerm
term = parsePredicateTerm testLemmaMap

assemblyTests :: [Test]
assemblyTests =
  [ TestLabel "shared bridge composes" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      case assemblePair a b of
        Nothing -> assertFailure "bridge on ответственность expected"
        Just asm -> do
          assertEqual "bridge concept"
            "ответственность" (asmBridge asm)
          assertEqual "head donor is A"
            (Just "свобода") (ptHead (asmTerm asm))
          assertEqual "two sources recorded" 2 (length (asmSources asm))
          assertEqual "skeleton path length" 1 (asmPathLen asm)
          assertBool "union carries both relations"
            (S.size (ptRels (asmTerm asm)) == 2)

  , TestLabel "identical sources are rejected (non-tautology)" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
      assertEqual "same topic and term must not assemble"
        Nothing (assemblePair a a)

  , TestLabel "bridgeless pairs are rejected (no invented bridge)" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("зло", "зло", term "зло")
      assertEqual "disjoint concepts must not assemble"
        Nothing (assemblePair a b)

  , TestLabel "bridge is deterministic (smallest shared concept)" $ TestCase $ do
      let a = ("свобода", "свобода требует осознанной ответственности",
               term "свобода требует осознанной ответственности")
          b = ("ответственность", "ответственность требует осознанной свободы",
               term "ответственность требует осознанной свободы")
          r1 = assemblePair a b
          r2 = assemblePair a b
      assertEqual "same inputs, same assembly" r1 r2
      case r1 of
        Nothing -> assertFailure "expected a bridge"
        Just asm -> assertEqual "lexicographically smallest shared concept"
          (S.findMin (S.intersection (assemblyConcepts (term "свобода требует осознанной ответственности"))
                                     (assemblyConcepts (term "ответственность требует осознанной свободы"))))
          (asmBridge asm)

  , TestLabel "negation is never silently dropped" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "не ответственность исключает произвол",
               term "не ответственность исключает произвол")
      case assemblePair a b of
        Nothing -> assertFailure "expected a bridge"
        Just asm -> assertBool "negation survives composition"
          (ptNeg (asmTerm asm))

  , TestLabel "proposition view is total and lemma-formed" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      case assemblePair a b of
        Nothing -> assertFailure "expected a bridge"
        Just asm ->
          assertEqual "head plus both relation pairs"
            (Just "свобода",
             [("исключать", "произвол"), ("требовать", "ответственность")])
            (assemblyProposition asm)

  , TestLabel "assembly stays close to both sources" $ TestCase $ do
      let ta = term "свобода требует ответственности"
          tb = term "ответственность исключает произвол"
          a = ("свобода", "свобода требует ответственности", ta)
          b = ("ответственность", "ответственность исключает произвол", tb)
      case assemblePair a b of
        Nothing -> assertFailure "expected a bridge"
        Just asm -> do
          let (oa, ob) = assemblySourceOverlap asm ta tb
          assertBool ("overlap with A too low: " ++ show oa) (oa >= 0.5)
          assertBool ("overlap with B too low: " ++ show ob) (ob >= 0.5)

  , TestLabel "rating labels are the decided two" $ TestCase $
      assertEqual "coherent + grounded"
        ["assembly_coherent", "assembly_grounded"] assemblyRatingLabels
  ]
