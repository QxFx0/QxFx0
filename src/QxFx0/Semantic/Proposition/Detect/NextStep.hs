{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.NextStep
  ( detectNextStepSignal
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  )
import Data.Text (Text)
import qualified Data.Text as T

detectNextStepSignal :: Text -> [Text] -> Maybe PropositionType
detectNextStepSignal rawText tokens
  | containsKeywordPhrase tokens "что дальше" = Just NextStepQ
  | containsKeywordPhrase tokens "дальше что" = Just NextStepQ
  | containsKeywordPhrase tokens "что теперь" = Just NextStepQ
  | containsKeywordPhrase tokens "что потом" = Just NextStepQ
  | containsKeywordPhrase tokens "с чего начать" = Just NextStepQ
  | containsKeywordPhrase tokens "какой первый шаг" = Just NextStepQ
  | containsKeywordPhrase tokens "что мне делать дальше" = Just NextStepQ
  | containsKeywordPhrase tokens "как действовать дальше" = Just NextStepQ
  | containsKeywordPhrase tokens "нет понимания что дальше" = Just NextStepQ
  | T.toLower (T.strip rawText) `elem` ["дальше", "что дальше?"] = Just NextStepQ
  | otherwise = Nothing
