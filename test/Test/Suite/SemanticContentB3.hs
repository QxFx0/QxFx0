{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SemanticContentB3
  ( semanticContentB3Tests
  ) where

import Test.HUnit (Test(..), assertBool, assertEqual, assertFailure)

import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Semantic.Content

-- | B3 Gate 1: every covered topic has ≥2 substantive predicates.
testGate1AllCoveredTopicsHaveMinPredicates :: Test
testGate1AllCoveredTopicsHaveMinPredicates =
  TestLabel "B3 Gate 1: every covered topic has ≥2 substantive predicates" $
    TestCase $ do
      let failures = [ topic
                     | topic <- coveredTopics
                     , case lookupDefinitionContent topic of
                         Just dc -> not (hasMinimumPredicates dc)
                         Nothing -> True
                     ]
      assertBool ("Topics with <2 predicates: " <> show failures)
                 (null failures)

-- | B3 Gate 1: predicates are non-tautological (not "X is a concept").
testGate1PredicatesAreNonTautological :: Test
testGate1PredicatesAreNonTautological =
  TestLabel "B3 Gate 1: no predicate is a tautological classification" $
    TestCase $ do
      let tautologicals = [ (topic, spRu sp)
                          | topic <- coveredTopics
                          , Just dc <- [lookupDefinitionContent topic]
                          , sp <- dcPredicates dc
                          , isTautological (spRu sp)
                          ]
      assertBool ("Tautological predicates found: " <> show tautologicals)
                 (null tautologicals)

-- | B3 Gate 1: predicates do not contain recovery/fallback phrases.
testGate1NoRecoveryPhrases :: Test
testGate1NoRecoveryPhrases =
  TestLabel "B3 Gate 1: no predicate contains recovery/fallback phrases" $
    TestCase $ do
      let bad = [ (topic, spRu sp)
                | topic <- coveredTopics
                , Just dc <- [lookupDefinitionContent topic]
                , sp <- dcPredicates dc
                , containsRecoveryPhrase (spRu sp)
                ]
      assertBool ("Recovery phrases in predicates: " <> show bad)
                 (null bad)

-- | B3 Gate 1: predicates do not contain meta-frame statements.
testGate1NoMetaFrame :: Test
testGate1NoMetaFrame =
  TestLabel "B3 Gate 1: no predicate is a meta-frame statement" $
    TestCase $ do
      let bad = [ (topic, spRu sp)
                | topic <- coveredTopics
                , Just dc <- [lookupDefinitionContent topic]
                , sp <- dcPredicates dc
                , isMetaFrame (spRu sp)
                ]
      assertBool ("Meta-frame predicates found: " <> show bad)
                 (null bad)

-- | B3 Gate 1: predicates are not request paraphrases.
testGate1NoRequestParaphrase :: Test
testGate1NoRequestParaphrase =
  TestLabel "B3 Gate 1: no predicate is a request paraphrase" $
    TestCase $ do
      let bad = [ (topic, spRu sp)
                | topic <- coveredTopics
                , Just dc <- [lookupDefinitionContent topic]
                , sp <- dcPredicates dc
                , isRequestParaphrase (spRu sp)
                ]
      assertBool ("Request paraphrase predicates: " <> show bad)
                 (null bad)

-- | B3 Gate 1: specific topic (свобода) has exactly the expected predicates.
testGate1SpecificTopicSvoboda :: Test
testGate1SpecificTopicSvoboda =
  TestLabel "B3 Gate 1: 'свобода' has ≥2 predicates with specific content" $
    TestCase $ do
      let mDc = lookupDefinitionContent "свобода"
      case mDc of
        Nothing -> assertFailure "свобода should be covered"
        Just dc -> do
          assertEqual "свобода should have ≥2 predicates" True (hasMinimumPredicates dc)
          let ruPreds = map spRu (dcPredicates dc)
          assertBool "should mention 'выбор' (choice)"
                     (any ("выбор" `T.isInfixOf`) ruPreds)
          assertBool "should mention 'ответственность' (responsibility)"
                     (any ("ответственность" `T.isInfixOf`) ruPreds)

-- | B3 Gate 2: every covered pair has ≥1 differentiating predicate.
testGate2AllCoveredPairsHaveDifferentiators :: Test
testGate2AllCoveredPairsHaveDifferentiators =
  TestLabel "B3 Gate 2: every covered pair has ≥1 differentiator" $
    TestCase $ do
      let pairs = [ ("свобода", "произвол")
                  , ("истина", "мнение")
                  , ("память", "воспоминание")
                  , ("сознание", "самосознание")
                  , ("свобода", "ответственность")
                  ]
          failures = [ pair
                     | pair <- pairs
                     , case uncurry lookupDistinctionContent pair of
                         Just dc -> null (dcDifferentiators dc)
                         Nothing -> True
                     ]
      assertBool ("Pairs with <1 differentiator: " <> show failures)
                 (null failures)

-- | B3 Gate 2: distinction content is specific to the pair (not generic).
testGate2DifferentiatorsArePairSpecific :: Test
testGate2DifferentiatorsArePairSpecific =
  TestLabel "B3 Gate 2: differentiators mention both X and Y or their properties" $
    TestCase $ do
      let pairs = [ ("свобода", "произвол")
                  , ("истина", "мнение")
                  , ("сознание", "самосознание")
                  ]
          failures = [ pair
                     | pair <- pairs
                     , Just dc <- [uncurry lookupDistinctionContent pair]
                     , sp <- dcDifferentiators dc
                     , not (isPairSpecific (dcLeft dc) (dcRight dc) (spRu sp))
                     ]
      assertBool ("Non-pair-specific differentiators: " <> show failures)
                 (null failures)

-- | B3 Gate 2: reverse lookup works (Y vs X returns swapped content).
testGate2ReverseLookup :: Test
testGate2ReverseLookup =
  TestLabel "B3 Gate 2: reverse lookup (произвол vs свобода) works" $
    TestCase $ do
      let mDc = lookupDistinctionContent "произвол" "свобода"
      case mDc of
        Nothing -> assertFailure "reverse lookup should work"
        Just dc -> do
          assertEqual "left should be произвол" "произвол" (dcLeft dc)
          assertEqual "right should be свобода" "свобода" (dcRight dc)
          assertBool "should have ≥1 differentiator"
                     (not (null (dcDifferentiators dc)))

-- | Coverage: uncovered topics return Nothing.
testUncoveredTopicReturnsNothing :: Test
testUncoveredTopicReturnsNothing =
  TestLabel "Coverage: uncovered topic returns Nothing" $
    TestCase $ do
      assertBool "uncovered topic should return Nothing"
                 (lookupDefinitionContent "квадратный корень" == Nothing)

-- | Coverage: isCoveredTopic works.
testIsCoveredTopic :: Test
testIsCoveredTopic =
  TestLabel "Coverage: isCoveredTopic correctly identifies covered topics" $
    TestCase $ do
      assertBool "свобода should be covered" (isCoveredTopic "свобода")
      assertBool "СВОБОДА should be covered (case-insensitive)" (isCoveredTopic "СВОБОДА")
      assertBool "неизвестность should NOT be covered" (not (isCoveredTopic "неизвестность"))

-- ============================================================================
-- Helpers: B3 exclusion list checks
-- ============================================================================

isTautological :: Text -> Bool
isTautological t =
  let lt = T.toLower t
  in "есть понятие" `T.isInfixOf` lt
     || "является понятием" `T.isInfixOf` lt
     || "is a concept" `T.isInfixOf` lt

containsRecoveryPhrase :: Text -> Bool
containsRecoveryPhrase t =
  let lt = T.toLower t
  in any (`T.isInfixOf` lt)
       [ "локальный режим восстановления"
       , "я сужаю ответ"
       , "local recovery mode"
       , "i will keep the answer"
       ]

isMetaFrame :: Text -> Bool
isMetaFrame t =
  let lt = T.toLower t
  in any (`T.isInfixOf` lt)
       [ "зафиксирую рабочее определение"
       , "отделю его от употребления"
       , "i will provide a working definition"
       , "separate it from usage"
       ]

isRequestParaphrase :: Text -> Bool
isRequestParaphrase t =
  let lt = T.toLower t
  in any (`T.isInfixOf` lt)
       [ "если говорить о"
       , "if we consider"
       , "if we speak of"
       ]

isPairSpecific :: Text -> Text -> Text -> Bool
isPairSpecific left right t =
  let lt = T.toLower t
      l = T.toLower left
      r = T.toLower right
  in (l `T.isInfixOf` lt || r `T.isInfixOf` lt)
     && not (isTautological t)

-- ============================================================================
-- Test group
-- ============================================================================

semanticContentB3Tests :: [Test]
semanticContentB3Tests =
  [ testGate1AllCoveredTopicsHaveMinPredicates
  , testGate1PredicatesAreNonTautological
  , testGate1NoRecoveryPhrases
  , testGate1NoMetaFrame
  , testGate1NoRequestParaphrase
  , testGate1SpecificTopicSvoboda
  , testGate2AllCoveredPairsHaveDifferentiators
  , testGate2DifferentiatorsArePairSpecific
  , testGate2ReverseLookup
  , testUncoveredTopicReturnsNothing
  , testIsCoveredTopic
  ]
