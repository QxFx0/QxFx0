{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.Ground
  ( detectOperationalStatus
  , detectOperationalCause
  , detectSystemLogic
  , detectWorldCause
  , detectLocationFormation
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  )
import Data.Text (Text)
import qualified Data.Text as T

detectOperationalStatus :: Text -> [Text] -> Maybe PropositionType
detectOperationalStatus rawText tokens
  | T.isInfixOf "работа" (T.toLower rawText)
      && any (`elem` tokens) ["ты", "система"]
      && not (containsKeywordPhrase tokens "почему") = Just OperationalStatusQ
  | otherwise = Nothing

detectOperationalCause :: Text -> [Text] -> Maybe PropositionType
detectOperationalCause rawText tokens
  | containsKeywordPhrase tokens "почему"
      && T.isInfixOf "работа" (T.toLower rawText)
      && any (`elem` tokens) ["ты", "система"] = Just OperationalCauseQ
  | otherwise = Nothing

detectSystemLogic :: Text -> [Text] -> Maybe PropositionType
detectSystemLogic rawText tokens
  | containsKeywordPhrase tokens "как ты будешь" = Just SystemLogicQ
  | containsKeywordPhrase tokens "как вы будете" = Just SystemLogicQ
  | any (`elem` tokens) ["логика", "устроен", "работаешь"]
      && any (`elem` tokens) ["твоя", "ты"] = Just SystemLogicQ
  | T.isInfixOf "твоя логика" (T.toLower rawText) = Just SystemLogicQ
  | otherwise = Nothing

detectWorldCause :: Text -> [Text] -> Maybe PropositionType
detectWorldCause _rawText tokens
  | containsKeywordPhrase tokens "почему"
      && hasConcreteWorldNoun tokens = Just WorldCauseQ
  | otherwise = Nothing

detectLocationFormation :: Text -> [Text] -> Maybe PropositionType
detectLocationFormation _rawText tokens
  | (containsKeywordPhrase tokens "где" || containsKeywordPhrase tokens "откуда")
      && hasMentalNoun tokens = Just LocationFormationQ
  | otherwise = Nothing

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
