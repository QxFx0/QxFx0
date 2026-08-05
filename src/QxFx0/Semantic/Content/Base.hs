{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Content.Base
  ( PredicateRole(..)
  , CanonicalPredicateRelation(..)
  , SemanticPredicate(..)
  , ChallengeResponse(..)
  , mkPred
  , mkArguedPred
  , extractTopicForm
  , renderPredicateArgued
  , challengeIntros
  , pickChallengeIntro
  ) where

import Data.Char (toUpper)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Types.Semantic.Content
  ( PredicateRole(..)
  , CanonicalPredicateRelation(..)
  , SemanticPredicate(..)
  , ChallengeResponse(..)
  )

extractTopicForm :: Text -> Text
extractTopicForm t =
  case T.words t of
    (w:_) -> T.toLower w
    []    -> ""

mkPred :: PredicateRole -> Text -> Text -> SemanticPredicate
mkPred role ru en = SemanticPredicate role ru en (extractTopicForm ru) Nothing Nothing Nothing Nothing

mkArguedPred :: PredicateRole -> Text -> Text -> Maybe Text -> Maybe Text -> Maybe Text -> SemanticPredicate
mkArguedPred role ru en rationale counter synthesis =
  SemanticPredicate role ru en (extractTopicForm ru) Nothing rationale counter synthesis

renderPredicateArgued :: SemanticPredicate -> Text
renderPredicateArgued p =
  spRu p
  <> maybe "" (prefixWith "Потому что" "потому что") (spRationale p)
  <> maybe "" (prefixWith "Но" "но") (spCounter p)
  <> maybe "" (prefixWith "Именно поэтому" "именно поэтому") (spSynthesis p)
  where
    prefixWith _ lower txt
      | T.toLower txt `T.isPrefixOf` T.toLower lower = ". " <> txt
      | lower `T.isPrefixOf` T.toLower txt = ". " <> txt
      | otherwise = ". " <> capitalize lower <> " " <> txt
    capitalize t = case T.uncons t of
      Just (c, rest) -> T.singleton (toUpper c) <> rest
      Nothing -> t

challengeIntros :: [Text]
challengeIntros =
  [ "Ты указываешь на"
  , "Твой вопрос затрагивает"
  , "Это возражение касается"
  , "Ты прав в том, что"
  , "Здесь важно различие между"
  , "Это возвращает нас к"
  , "Интересно, что ты затронул"
  ]

pickChallengeIntro :: Text -> Text
pickChallengeIntro input =
  let h = fromIntegral (T.length input * 31 + sum (map fromEnum (T.unpack input)))
      idx = h `mod` length challengeIntros
  in challengeIntros !! idx
