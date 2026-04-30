{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.Define
  ( detectConceptKnowledge
  , detectDistinctionQuestion
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  )
import Data.Text (Text)
import qualified Data.Text as T

detectConceptKnowledge :: Text -> [Text] -> Maybe PropositionType
detectConceptKnowledge rawText tokens
  | containsKeywordPhrase tokens "знаешь"
      && (containsKeywordPhrase tokens "что такое" || containsKeywordPhrase tokens "что значит") =
          Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "кто такой" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "кто такая" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "кто такое" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "что есть" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "что значит быть" = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "что известно о"
      && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "знаешь"
      && hasConceptLikeNoun tokens
      && T.isSuffixOf "?" (T.strip rawText) = Just ConceptKnowledgeQ
  | otherwise = Nothing

detectDistinctionQuestion :: Text -> [Text] -> Maybe PropositionType
detectDistinctionQuestion rawText tokens
  | containsKeywordPhrase tokens "как отличить"
      && any (`elem` tokens) ["от"] = Just DistinctionQ
  | containsKeywordPhrase tokens "чем отличается" = Just DistinctionQ
  | T.isInfixOf "как отличить" (T.toLower rawText)
      && T.isInfixOf " от " (T.toLower rawText) = Just DistinctionQ
  | otherwise = Nothing

hasConceptLikeNoun :: [Text] -> Bool
hasConceptLikeNoun tokens = hasConcreteWorldNoun tokens || hasMentalNoun tokens || any (`elem` tokens)
  [ "логика", "свобода", "смысл", "тишина", "любовь", "страх", "истина", "дом", "душа", "бог" ]

hasConcreteWorldNoun :: [Text] -> Bool
hasConcreteWorldNoun tokens =
  any (`elem` tokens)
    [ "солнце", "дождь", "небо", "мир", "земля", "вода", "огонь"
    , "время", "пространство", "природа", "вселенная", "жизнь"
    , "дом", "город", "лес", "море", "река", "камень", "ветер", "звезда", "осень"
    ]

hasMentalNoun :: [Text] -> Bool
hasMentalNoun tokens =
  any (`elem` tokens)
    [ "мысль", "мысли", "идея", "идеи", "знание", "знания"
    , "сознание", "память", "воспоминание", "воображение"
    , "фокус", "внимание", "смысл", "образ", "мышление"
    ]
