{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.MorphologicalNormalization (morphologicalNormalizationTests) where

import Test.HUnit
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)

import QxFx0.Semantic.Morphology (buildLemmaMap, normalizeToken, normalizeAtoms)
import QxFx0.Types.Domain.Atoms (MorphologyData(..), LexemeForm(..), LexemeCase(..), LexemeNumber(..), SourceTier(..))

morphologicalNormalizationTests :: [Test]
morphologicalNormalizationTests =
  [ TestLabel "buildLemmaMap constructs map from MorphologyData" testBuildLemmaMap
  , TestLabel "normalizeToken normalizes known surface form" testNormalizeTokenKnown
  , TestLabel "normalizeToken returns lowercased input for unknown form" testNormalizeTokenUnknown
  , TestLabel "normalizeAtoms normalizes set of atoms" testNormalizeAtoms
  , TestLabel "normalizeAtoms handles empty set" testNormalizeAtomsEmpty
  , TestLabel "buildLemmaMap handles empty MorphologyData" testBuildLemmaMapEmpty
  ]

testBuildLemmaMap :: Test
testBuildLemmaMap = TestCase $ do
  let md = MorphologyData
        { mdNominative = M.fromList [("свобода" :: Text, "свобода" :: Text)]
        , mdGenitive = M.fromList [("свободы" :: Text, "свобода" :: Text)]
        , mdPrepositional = M.fromList [("свободе" :: Text, "свобода" :: Text)]
        , mdFormsBySurface = M.fromList
            [("свободу" :: Text, [LexemeForm "свободу" "свобода" "NOUN" AccusativeCase SingularNumber CuratedTier 0.9])]
        }
      lemmaMap = buildLemmaMap md
  assertEqual "nominative form" (Just "свобода") (M.lookup "свобода" lemmaMap)
  assertEqual "genitive form" (Just "свобода") (M.lookup "свободы" lemmaMap)
  assertEqual "prepositional form" (Just "свобода") (M.lookup "свободе" lemmaMap)
  assertEqual "accusative form from formsBySurface" (Just "свобода") (M.lookup "свободу" lemmaMap)

testNormalizeTokenKnown :: Test
testNormalizeTokenKnown = TestCase $ do
  let lemmaMap = M.fromList [("свободы" :: Text, "свобода" :: Text)]
  assertEqual "normalize known form" "свобода" (normalizeToken lemmaMap "свободы")

testNormalizeTokenUnknown :: Test
testNormalizeTokenUnknown = TestCase $ do
  let lemmaMap = M.fromList [("свобода" :: Text, "свобода" :: Text)]
  assertEqual "normalize unknown form" "неизвестное" (normalizeToken lemmaMap "Неизвестное")

testNormalizeAtoms :: Test
testNormalizeAtoms = TestCase $ do
  let lemmaMap = M.fromList
        [ ("свободы" :: Text, "свобода" :: Text)
        , ("ответственности" :: Text, "ответственность" :: Text)
        ]
      atoms = S.fromList ["свободы" :: Text, "ответственности" :: Text, "неизвестное" :: Text]
      normalized = normalizeAtoms lemmaMap atoms
  assertBool "contains свобода" (S.member "свобода" normalized)
  assertBool "contains ответственность" (S.member "ответственность" normalized)
  assertBool "contains неизвестное" (S.member "неизвестное" normalized)
  assertEqual "size unchanged" 3 (S.size normalized)

testNormalizeAtomsEmpty :: Test
testNormalizeAtomsEmpty = TestCase $ do
  let lemmaMap = M.fromList [("свобода" :: Text, "свобода" :: Text)]
      atoms = S.empty
      normalized = normalizeAtoms lemmaMap atoms
  assertBool "empty result" (S.null normalized)

testBuildLemmaMapEmpty :: Test
testBuildLemmaMapEmpty = TestCase $ do
  let md = MorphologyData M.empty M.empty M.empty M.empty
      lemmaMap = buildLemmaMap md
  assertBool "empty lemma map" (M.null lemmaMap)
