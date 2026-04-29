{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsKeywordPhrase
  , containsAnyKeywordPhrase
  , countKeywordPhraseHits
  ) where

import Data.Char (isAlphaNum)
import Data.List (isPrefixOf, tails)
import Data.Text (Text)
import qualified Data.Text as T

tokenizeKeywordText :: Text -> [Text]
tokenizeKeywordText =
  filter (not . T.null) . T.words . T.map normalizeChar . T.toLower
  where
    normalizeChar ch
      | isAlphaNum ch = ch
      | otherwise = ' '

containsKeywordPhrase :: [Text] -> Text -> Bool
containsKeywordPhrase haystack phrase =
  let needle = tokenizeKeywordText phrase
  in not (null needle) && any (isPrefixOf needle) (tails haystack)

containsAnyKeywordPhrase :: [Text] -> [Text] -> Bool
containsAnyKeywordPhrase haystack = any (containsKeywordPhrase haystack)

countKeywordPhraseHits :: [Text] -> [Text] -> Int
countKeywordPhraseHits haystack = length . filter (containsKeywordPhrase haystack)
