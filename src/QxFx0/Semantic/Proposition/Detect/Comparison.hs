{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.Comparison
  ( detectComparisonPlausibility
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  )
import Data.Text (Text)

detectComparisonPlausibility :: Text -> [Text] -> Maybe PropositionType
detectComparisonPlausibility _rawText tokens
  | (containsKeywordPhrase tokens "логичнее" || containsKeywordPhrase tokens "вероятнее"
     || containsKeywordPhrase tokens "естественнее" || containsKeywordPhrase tokens "правильнее")
      && containsKeywordPhrase tokens "или" = Just ComparisonPlausibilityQ
  | otherwise = Nothing
