{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.IntentClassifier
Description : Tests for deterministic feature-based intent classifier.

Verifies:
1. Determinism: same input → same intent
2. Coverage: B3 seed corpus topics classify correctly
3. No regression: existing proposition detection still works
-}
module Test.Suite.IntentClassifier
  ( intentClassifierTests
  ) where

import Test.HUnit (Test(..), assertEqual, assertBool)

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Intent.Features (SemanticFeatures(..), extractFeatures)
import QxFx0.Semantic.Intent.Classifier (SemanticIntent(..), classifyIntent, intentToFamily, intentToPropositionType)
import QxFx0.Semantic.Frame.Types (SemanticFrame(..), frameTypeText)
import QxFx0.Semantic.Frame.Builder (buildFrame)
import QxFx0.Types (MorphologyData(..), CanonicalMoveFamily(..))
import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import qualified Data.Map.Strict as M

-- | Empty morphology for testing (no inflection data).
testMorph :: MorphologyData
testMorph = MorphologyData M.empty M.empty M.empty M.empty

-- | Helper: classify utterance and return intent.
classify :: Text -> SemanticIntent
classify text = classifyIntent text (tokenize text) testMorph

-- | Simple whitespace tokenizer for tests.
tokenize :: Text -> [Text]
tokenize = T.words . T.toLower . T.strip

-- ---------------------------------------------------------------------------
-- Test suite
-- ---------------------------------------------------------------------------

intentClassifierTests :: [Test]
intentClassifierTests =
  [ determinismTests
  , structuralTests
  , semanticRoleTests
  , discourseTests
  , b3SeedCorpusTests
  , b3Gate5Tests
  , intentToFamilyTests
  , frameBuilderTests
  ]

-- ---------------------------------------------------------------------------
-- 1. Determinism tests
-- ---------------------------------------------------------------------------

determinismTests :: Test
determinismTests = TestLabel "Determinism" $ TestList
  [ TestCase $ do
      let i1 = classify "что такое свобода"
          i2 = classify "что такое свобода"
      assertEqual "determinism" i1 i2

  , TestCase $ do
      let i1 = classify "разница между свободой и волей"
          i2 = classify "разница между свободой и волей"
      assertEqual "determinism" i1 i2

  , TestCase $ do
      let i1 = classify "это неверно"
          i2 = classify "это неверно"
      assertEqual "determinism" i1 i2

  , TestCase $ do
      let i1 = classify "привет"
          i2 = classify "привет"
      assertEqual "determinism" i1 i2

  , TestCase $ do
      let i1 = classify "что такое свобода"
          i2 = classify "разница между свободой и волей"
      assertBool "different inputs can produce different intents" (i1 /= i2)
  ]

-- ---------------------------------------------------------------------------
-- 2. Structural tests (question + markers)
-- ---------------------------------------------------------------------------

structuralTests :: Test
structuralTests = TestLabel "StructuralClassification" $ TestList
  [ TestCase $ do
      case classify "что такое свобода" of
        IntentDefine topic -> assertEqual "topic" "свобода" topic
        other -> assertEqual "expected IntentDefine" "IntentDefine" (show other)

  , TestCase $ assertEqual "next step" IntentNextStep (classify "что дальше")

  , TestCase $ assertEqual "reflect" IntentReflect (classify "что думаешь")

  , TestCase $ assertEqual "operational" IntentOperational (classify "ты работаешь")
  ]

-- ---------------------------------------------------------------------------
-- 3. Semantic role tests (two concepts + comparison)
-- ---------------------------------------------------------------------------

semanticRoleTests :: Test
semanticRoleTests = TestLabel "SemanticRoleClassification" $ TestList
  [ TestCase $ do
      case classify "разница между свободой и волей" of
        IntentDistinguish left right -> do
          assertEqual "left concept" "свободой" left
          assertEqual "right concept" "волей" right
        other -> assertEqual "expected IntentDistinguish" "IntentDistinguish" (show other)

  , TestCase $ assertEqual "challenge" IntentChallenge (classify "это неверно")

  , TestCase $ assertEqual "competing definition is challenge" IntentChallenge (classify "я считаю что истина — это просто то, во что верит большинство")

  , TestCase $ assertEqual "repair" IntentRepair (classify "не работает")
  ]

-- ---------------------------------------------------------------------------
-- 4. Discourse tests (greetings, deepen, etc.)
-- ---------------------------------------------------------------------------

discourseTests :: Test
discourseTests = TestLabel "DiscourseClassification" $ TestList
  [ TestCase $ assertEqual "contact" IntentContact (classify "привет")

  , TestCase $ assertEqual "contact" IntentContact (classify "добрый день")

  , TestCase $ assertEqual "reflect" IntentReflect (classify "скажи интересную мысль")

  , TestCase $ assertEqual "exploratory" IntentExploratory (classify "а если представить")
  ]

-- ---------------------------------------------------------------------------
-- 5. B3 seed corpus tests (covered topics must classify correctly)
-- ---------------------------------------------------------------------------

b3SeedCorpusTests :: Test
b3SeedCorpusTests = TestLabel "B3SeedCorpus" $ TestList
  [ TestCase $ do
      case classify "что такое свобода" of
        IntentDefine topic -> assertEqual "topic" "свобода" topic
        other -> assertEqual "expected IntentDefine" "IntentDefine" (show other)

  , TestCase $ do
      case classify "что такое истина" of
        IntentDefine topic -> assertEqual "topic" "истина" topic
        other -> assertEqual "expected IntentDefine" "IntentDefine" (show other)

  , TestCase $ do
      case classify "разница между произволом и свободой" of
        IntentDistinguish _ _ -> pure ()
        other -> assertEqual "expected IntentDistinguish" "IntentDistinguish" (show other)

  , TestCase $ do
      case classify "отличие несвободы от подчинения" of
        IntentDistinguish _ _ -> pure ()
        other -> assertEqual "expected IntentDistinguish" "IntentDistinguish" (show other)

  , TestCase $ assertEqual "challenge" IntentChallenge (classify "это неверно")

  , TestCase $ assertEqual "challenge" IntentChallenge (classify "ты ошибаешься")

  , TestCase $ assertEqual "challenge" IntentChallenge (classify "спорю с этим")
  ]

-- ---------------------------------------------------------------------------
-- 6. Intent → Family conversion tests
-- ---------------------------------------------------------------------------

intentToFamilyTests :: Test
intentToFamilyTests = TestLabel "IntentToFamily" $ TestList
  [ TestCase $ assertEqual "define" CMDefine (intentToFamily (IntentDefine "test"))

  , TestCase $ assertEqual "distinguish" CMDistinguish (intentToFamily (IntentDistinguish "a" "b"))

  , TestCase $ assertEqual "challenge" CMConfront (intentToFamily IntentChallenge)

  , TestCase $ assertEqual "repair" CMRepair (intentToFamily IntentRepair)

  , TestCase $ assertEqual "contact" CMContact (intentToFamily IntentContact)

  , TestCase $ assertEqual "reflect" CMReflect (intentToFamily IntentReflect)

  , TestCase $ assertEqual "next_step" CMNextStep (intentToFamily IntentNextStep)

  , TestCase $ assertEqual "unknown" CMGround (intentToFamily (IntentUnknown "test"))
  ]

-- ---------------------------------------------------------------------------
-- 7. Frame builder tests
-- ---------------------------------------------------------------------------

frameBuilderTests :: Test
frameBuilderTests = TestLabel "FrameBuilder" $ TestList
  [ TestCase $ do
      let frame = buildFrame (IntentDefine "свобода") "что такое свобода"
      case frame of
        DefinitionFrame topic _ _ -> assertEqual "topic" "свобода" topic
        other -> assertEqual "expected DefinitionFrame" "definition" (frameTypeText other)

  , TestCase $ do
      let frame = buildFrame (IntentDistinguish "свобода" "воля") "разница"
      case frame of
        DistinctionFrame left right _ -> do
          assertEqual "left" "свобода" left
          assertEqual "right" "воля" right
        other -> assertEqual "expected DistinctionFrame" "distinction" (frameTypeText other)

  , TestCase $ do
      let frame = buildFrame IntentChallenge "это неверно"
      case frame of
        ChallengeFrame {} -> pure ()
        other -> assertEqual "expected ChallengeFrame" "challenge" (frameTypeText other)

  , TestCase $ do
      let frame = buildFrame IntentContact "привет"
      case frame of
        ContactFrame greeting -> assertBool "greeting not empty" (not (T.null greeting))
        other -> assertEqual "expected ContactFrame" "contact" (frameTypeText other)

  , TestCase $ do
      let frame = buildFrame IntentNextStep "что дальше"
      assertEqual "frame type" "next_step" (frameTypeText frame)

  , TestCase $ do
      let frame = buildFrame (IntentUnknown "xyz") "xyz"
      case frame of
        GenericFrame content -> assertEqual "content" "xyz" content
        other -> assertEqual "expected GenericFrame" "generic" (frameTypeText other)
  ]

-- ---------------------------------------------------------------------------
-- B3 Gate 5: covered topics must NEVER produce IntentUnknown
-- ---------------------------------------------------------------------------

-- | B3 seed corpus utterances that MUST be classified correctly.
-- If any of these produces IntentUnknown, Gate 5 fails.
b3Gate5CoveredUtterances :: [(Text, Text)]  -- (utterance, expected_intent_tag)
b3Gate5CoveredUtterances =
  [ ("что такое свобода", "IntentDefine")
  , ("что такое произвол", "IntentDefine")
  , ("что такое ответственность", "IntentDefine")
  , ("что такое истина", "IntentDefine")
  , ("что такое мнение", "IntentDefine")
  , ("что такое память", "IntentDefine")
  , ("что такое воспоминание", "IntentDefine")
  , ("что такое сознание", "IntentDefine")
  , ("что такое самосознание", "IntentDefine")
  , ("разница между свободой и произволом", "IntentDistinguish")
  , ("отличие свободы от ответственности", "IntentDistinguish")
  , ("сравни свободу и произвол", "IntentDistinguish")
  ]

b3Gate5Tests :: Test
b3Gate5Tests = TestLabel "B3Gate5" $ TestList
  (map makeGate5Test b3Gate5CoveredUtterances)
  where
    makeGate5Test (utterance, expectedTag) =
      TestCase $ do
        let intent = classify utterance
        case intent of
          IntentUnknown _ ->
            assertBool
              ("B3 Gate 5 FAIL: covered topic utterance produced IntentUnknown: "
                <> T.unpack utterance)
              False
          _ ->
            let shown = T.pack (show intent)
                expected = expectedTag
            in assertBool
              ("B3 Gate 5: " <> T.unpack utterance
                <> " expected " <> T.unpack expected <> " but got " <> T.unpack shown)
              (expected `T.isPrefixOf` shown)
