{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Feedback.Detect
  ( detectUserFeedback
  ) where

import Data.Char (isAlpha)
import Data.List (isPrefixOf)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Network.Feedback (UserFeedback(..))

-- | Detect a simple user-feedback marker in Russian input.
--
--   * Accept markers: "да", "согласен", "понятно", "ясно", "продолжай", "хорошо".
--   * Challenge markers: "нет", "не согласен", "ошибка", "спорно", "не так".
--   * Clarify markers: "уточни", "то есть", "имеешь в виду", "поясни", "объясни".
--
-- Markers are matched at word boundaries: the input is tokenised by
-- non-alphabetic characters, and a marker matches only when its words
-- appear as a contiguous token sequence.  This prevents substring-only
-- false positives such as @"да"@ matching inside @"загадка"@ or
-- @"надо"@.
--
-- If a marker is found the remainder of the sentence is captured for
-- 'Challenge' and 'Clarify'.  If no marker is present 'Nothing' is returned.
detectUserFeedback :: Text -> Maybe UserFeedback
detectUserFeedback input =
  let tokens = alphaTokens input
  in case findFirstTokenMarker challengeMarkers tokens of
       Just (_, rest) -> Just (Challenge rest)
       Nothing ->
         case findFirstTokenMarker clarifyMarkers tokens of
           Just (_, rest) -> Just (Clarify rest)
           Nothing ->
             case findFirstTokenMarker acceptMarkers tokens of
               Just _  -> Just Accept
               Nothing -> Nothing

-- | Convert input to lower-cased alphabetic tokens.  Punctuation and
-- other non-alphabetic characters become whitespace, which gives us
-- word-boundary matching without adding a regex dependency.
alphaTokens :: Text -> [Text]
alphaTokens = T.words . T.map (\c -> if isAlpha c then c else ' ') . T.toLower

-- | Find the first marker (in list order) whose words occur as a
-- contiguous token sequence, returning the marker and the remaining
-- tokens joined back into text.
findFirstTokenMarker :: [Text] -> [Text] -> Maybe (Text, Text)
findFirstTokenMarker markers tokens =
  listToMaybe
    [ (marker, T.unwords rest)
    | marker <- markers
    , Just rest <- [findSubseq (T.words marker) tokens]
    ]

-- | Return the suffix of the token list after the first contiguous
-- occurrence of the needle tokens.
findSubseq :: [Text] -> [Text] -> Maybe [Text]
findSubseq needle tokens
  | needle `isPrefixOf` tokens = Just (drop (length needle) tokens)
findSubseq needle (_:xs) = findSubseq needle xs
findSubseq _ [] = Nothing

acceptMarkers :: [Text]
acceptMarkers =
  [ "да"
  , "согласен"
  , "понятно"
  , "ясно"
  , "продолжай"
  , "хорошо"
  ]

challengeMarkers :: [Text]
challengeMarkers =
  [ "не согласен"
  , "нет"
  , "ошибка"
  , "спорно"
  , "не так"
  ]

clarifyMarkers :: [Text]
clarifyMarkers =
  [ "имеешь в виду"
  , "то есть"
  , "уточни"
  , "поясни"
  , "объясни"
  ]


