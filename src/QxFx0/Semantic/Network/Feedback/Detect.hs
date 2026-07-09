{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Feedback.Detect
  ( detectUserFeedback
  ) where

import Data.Char (isPunctuation, isSpace)
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
-- If a marker is found the remainder of the sentence is captured for
-- 'Challenge' and 'Clarify'.  If no marker is present 'Nothing' is returned.
detectUserFeedback :: Text -> Maybe UserFeedback
detectUserFeedback input =
  let lowered = T.toLower input
  in case findFirstInfix challengeMarkers lowered of
       Just (_, rest) -> Just (Challenge rest)
       Nothing ->
         case findFirstInfix clarifyMarkers lowered of
           Just (_, rest) -> Just (Clarify rest)
           Nothing ->
             case findFirstInfix acceptMarkers lowered of
               Just _  -> Just Accept
               Nothing -> Nothing

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

findFirstInfix :: [Text] -> Text -> Maybe (Text, Text)
findFirstInfix markers text =
  listToMaybe
    [ (marker, remainderAfter marker text)
    | marker <- markers
    , marker `T.isInfixOf` text
    ]

remainderAfter :: Text -> Text -> Text
remainderAfter marker text =
  let (before, after) = T.breakOn marker text
      rest = before <> T.drop (T.length marker) after
  in T.dropWhileEnd isSpace (T.dropWhile (\c -> isSpace c || isPunctuation c) rest)
