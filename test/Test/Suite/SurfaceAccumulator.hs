{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SurfaceAccumulator (surfaceAccumulatorTests) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Content.Base (SemanticPredicate(..), PredicateRole(..))
import QxFx0.Semantic.SurfaceAccumulator
import QxFx0.Self.Field
  ( Field(..)
  , emptyField
  , FieldConfidence(..)
  , Counterfactual(..)
  , Resonance(..)
  )
import QxFx0.Types (MorphologyData(..))
import qualified Data.Map.Strict as M

emptyMd :: MorphologyData
emptyMd = MorphologyData M.empty M.empty M.empty M.empty

neutralField :: Field
neutralField = emptyField { fieldConfidence = FieldConfidence 0.0 }

mkTestPred :: Text -> Text -> Maybe Text -> Maybe Text -> SemanticPredicate
mkTestPred ru topic mRationale mSynthesis =
  SemanticPredicate RoleProperty ru "" topic Nothing mRationale Nothing mSynthesis

surfaceAccumulatorTests :: [Test]
surfaceAccumulatorTests =
  [ TestLabel "empty predicate list returns empty text" $ TestCase $ do
      let result = accumulateSurface emptyMd neutralField VmDefinition "topic" []
      assertEqual "should be empty" "" result

  , TestLabel "same topic predicates joined with additive connector" $ TestCase $ do
      let p1 = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          p2 = mkTestPred "свобода требует ответственности" "свобода" Nothing Nothing
          p3 = mkTestPred "свобода ограничена законом" "свобода" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p1, p2, p3]
          expected = "свобода предполагает выбор. Кроме того, свобода требует ответственности. Кроме того, свобода ограничена законом"
      assertEqual "should use additive connector" expected result

  , TestLabel "different topic predicates joined with contrastive connector" $ TestCase $ do
      let p1 = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          p2 = mkTestPred "ответственность требует осознания" "ответственность" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p1, p2]
          expected = "свобода предполагает выбор. Вместе с тем, свобода требует осознания"
      assertEqual "should use contrastive connector" expected result

  , TestLabel "duplicate predicates are skipped" $ TestCase $ do
      let p1 = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          p2 = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p1, p2]
          expected = "свобода предполагает выбор"
      assertEqual "should deduplicate" expected result

  , TestLabel "predicate text is stripped of surrounding whitespace" $ TestCase $ do
      let p = mkTestPred "  свобода предполагает выбор  " "свобода" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p]
          expected = "свобода предполагает выбор"
      assertEqual "should strip whitespace" expected result

  , TestLabel "high confidence field adds confidence prefix" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          field = neutralField { fieldConfidence = FieldConfidence 0.8 }
          result = accumulateSurface emptyMd field VmDefinition "свобода" [p]
          expected = "Известно, что свобода предполагает выбор"
      assertEqual "should add confidence prefix" expected result

  , TestLabel "high counterfactual field adds counterfactual prefix" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          field = neutralField { fieldCounterfactual = Counterfactual 0.7 }
          result = accumulateSurface emptyMd field VmDefinition "свобода" [p]
          expected = "Но вместе с тем свобода предполагает выбор"
      assertEqual "should add counterfactual prefix" expected result

  , TestLabel "high resonance field adds hedging prefix" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          field = neutralField { fieldResonance = Resonance 0.8 }
          result = accumulateSurface emptyMd field VmDefinition "свобода" [p]
          expected = "возможно, свобода предполагает выбор"
      assertEqual "should add hedging prefix" expected result

  , TestLabel "multiple stance prefixes concatenate" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          field = neutralField
            { fieldConfidence = FieldConfidence 0.8
            , fieldCounterfactual = Counterfactual 0.7
            , fieldResonance = Resonance 0.8
            }
          result = accumulateSurface emptyMd field VmDefinition "свобода" [p]
          expected = "Известно, что Но вместе с тем возможно, свобода предполагает выбор"
      assertEqual "should concatenate prefixes" expected result

  , TestLabel "rationale included for definition mode" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" (Just "это внутренняя способность") Nothing
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p]
          expected = "свобода предполагает выбор — это внутренняя способность"
      assertEqual "should append rationale" expected result

  , TestLabel "rationale included for reflection mode" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" (Just "это внутренняя способность") Nothing
          result = accumulateSurface emptyMd neutralField VmReflection "свобода" [p]
          expected = "Когда я думаю о свобода, свобода предполагает выбор — это внутренняя способность"
      assertEqual "should append rationale in reflection mode" expected result

  , TestLabel "rationale excluded for challenge mode" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" (Just "это внутренняя способность") Nothing
          result = accumulateSurface emptyMd neutralField VmChallenge "свобода" [p]
          expected = "Я вижу это так: свобода предполагает выбор"
      assertEqual "should not append rationale" expected result

  , TestLabel "synthesis appended for definition mode" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing (Just "поэтому она ценна")
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p]
          expected = "свобода предполагает выбор. поэтому она ценна"
      assertEqual "should append synthesis" expected result

  , TestLabel "synthesis appended for reflection mode" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing (Just "поэтому она ценна")
          result = accumulateSurface emptyMd neutralField VmReflection "свобода" [p]
          expected = "Когда я думаю о свобода, свобода предполагает выбор. поэтому она ценна"
      assertEqual "should append synthesis in reflection mode" expected result

  , TestLabel "synthesis excluded for challenge mode" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing (Just "поэтому она ценна")
          result = accumulateSurface emptyMd neutralField VmChallenge "свобода" [p]
          expected = "Я вижу это так: свобода предполагает выбор"
      assertEqual "should not append synthesis" expected result

  , TestLabel "synthesis predicate uses adversative connector" $ TestCase $ do
      let p1 = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          p2 = mkTestPred "свобода требует ограничений" "свобода" Nothing (Just "поэтому она ответственна")
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p1, p2]
          expected = "свобода предполагает выбор. Однако свобода требует ограничений. поэтому она ответственна"
      assertEqual "should use adversative connector" expected result

  , TestLabel "definition mode respects max predicate count 3" $ TestCase $ do
      let preds = [ mkTestPred ("свобода предикат " <> T.pack (show i)) "свобода" Nothing Nothing
                  | i <- [1 :: Int .. 5] ]
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" preds
      assertEqual "should keep at most 3 predicates" 3 (length (T.splitOn ". Кроме того, " result))

  , TestLabel "challenge mode respects max predicate count 2" $ TestCase $ do
      let preds = [ mkTestPred ("свобода предикат " <> T.pack (show i)) "свобода" Nothing Nothing
                  | i <- [1 :: Int .. 5] ]
          result = accumulateSurface emptyMd neutralField VmChallenge "свобода" preds
          body = T.drop (T.length "Я вижу это так: ") result
      assertEqual "should keep at most 2 predicates" 2 (length (T.splitOn ". Кроме того, " body))

  , TestLabel "reflection mode respects max predicate count 2" $ TestCase $ do
      let preds = [ mkTestPred ("свобода предикат " <> T.pack (show i)) "свобода" Nothing Nothing
                  | i <- [1 :: Int .. 5] ]
          result = accumulateSurface emptyMd neutralField VmReflection "свобода" preds
          body = T.drop (T.length "Когда я думаю о свобода, ") result
      assertEqual "should keep at most 2 predicates" 2 (length (T.splitOn ". Кроме того, " body))

  , TestLabel "distinction mode respects max predicate count 1" $ TestCase $ do
      let preds = [ mkTestPred ("свобода предикат " <> T.pack (show i)) "свобода" Nothing Nothing
                  | i <- [1 :: Int .. 5] ]
          result = accumulateSurface emptyMd neutralField VmDistinction "свобода" preds
          body = T.drop (T.length "Различая свобода: ") result
      assertBool "should keep exactly 1 predicate" (not (T.null body) && ". Кроме того, " `T.isInfixOf` body == False)

  , TestLabel "challenge framing prefix" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmChallenge "свобода" [p]
      assertBool "should start with challenge prefix" ("Я вижу это так: " `T.isPrefixOf` result)

  , TestLabel "reflection framing prefix" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmReflection "свобода" [p]
      assertBool "should start with reflection prefix" ("Когда я думаю о свобода, " `T.isPrefixOf` result)

  , TestLabel "distinction framing prefix" $ TestCase $ do
      let p = mkTestPred "свобода предполагает выбор" "свобода" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmDistinction "свобода" [p]
      assertBool "should start with distinction prefix" ("Различая свобода: " `T.isPrefixOf` result)

  , TestLabel "empty topic form falls back to stripped predicate text" $ TestCase $ do
      let p = mkTestPred "  свобода предполагает выбор  " "" Nothing Nothing
          result = accumulateSurface emptyMd neutralField VmDefinition "свобода" [p]
          expected = "свобода предполагает выбор"
      assertEqual "should use predicate text when topic form empty" expected result
  ]
