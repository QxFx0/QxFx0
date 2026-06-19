{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Analogy
  ( analogicalResponse
  , adaptPredicate
  , fallbackSimilarity
  , replaceFirst
  , findNearestCoveredTopic
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.List (maximumBy)
import Data.Function (on)
import QxFx0.Semantic.Content (SemanticPredicate(..), DefinitionContent(..), lookupDefinitionContent, coveredTopics)

analogicalResponse :: Text -> Text -> Maybe Text
analogicalResponse uncoveredTopic sourceTopic =
  case lookupDefinitionContent sourceTopic of
    Nothing -> Nothing
    Just dc ->
      case dcPredicates dc of
        [] -> Nothing
        (p:_) -> Just $ adaptPredicate uncoveredTopic p

adaptPredicate :: Text -> SemanticPredicate -> Text
adaptPredicate newTopic pred =
  let oldTopic = spTopicForm pred
      ru = spRu pred
  in replaceFirst oldTopic newTopic ru

replaceFirst :: Text -> Text -> Text -> Text
replaceFirst old new txt =
  case T.breakOn old txt of
    (before, after) ->
      if T.null after
        then txt
        else before <> new <> T.drop (T.length old) after

fallbackSimilarity :: Text -> Text -> Double
fallbackSimilarity t1 t2 =
  let common = length (takeWhile id (zipWith (==) (T.unpack t1) (T.unpack t2)))
      maxLen = max (T.length t1) (T.length t2)
  in if maxLen == 0
     then 1.0
     else fromIntegral common / fromIntegral maxLen

findNearestCoveredTopic :: Text -> Maybe Text
findNearestCoveredTopic topic =
  if null coveredTopics
    then Nothing
    else
      let scored = [(t, fallbackSimilarity topic t) | t <- coveredTopics]
          (nearest, score) = maximumBy (compare `on` snd) scored
      in if score >= 0.3
         then Just nearest
         else Nothing
