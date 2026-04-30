{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.Repair
  ( detectRepairDirective
  , detectMisunderstanding
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  )
import Data.Text (Text)
import qualified Data.Text as T

detectRepairDirective :: Text -> [Text] -> Maybe PropositionType
detectRepairDirective rawText tokens
  | containsKeywordPhrase tokens "объясни проще" = Just RepairSignal
  | containsKeywordPhrase tokens "переформулируй" = Just RepairSignal
  | containsKeywordPhrase tokens "скажи короче" = Just RepairSignal
  | containsKeywordPhrase tokens "давай сначала" = Just RepairSignal
  | containsKeywordPhrase tokens "повтори по шагам" = Just RepairSignal
  | containsKeywordPhrase tokens "вернись к вопросу" = Just RepairSignal
  | containsKeywordPhrase tokens "уточни термин" = Just RepairSignal
  | containsKeywordPhrase tokens "исправь ответ" = Just RepairSignal
  | containsKeywordPhrase tokens "дай пример" = Just RepairSignal
  | containsKeywordPhrase tokens "объясни иначе" = Just RepairSignal
  | containsKeywordPhrase tokens "не по вопросу" = Just RepairSignal
  | containsKeywordPhrase tokens "не вижу связи" = Just RepairSignal
  | containsKeywordPhrase tokens "ты меня не услышал" = Just RepairSignal
  | containsKeywordPhrase tokens "это не помогает" = Just RepairSignal
  | containsKeywordPhrase tokens "проверь логику ответа" = Just RepairSignal
  | containsKeywordPhrase tokens "без лишнего" = Just RepairSignal
  | any (`elem` tokens) ["непонятно", "неясно", "запутался", "запуталась", "шаблон", "шаблона", "конкретику", "абстрактно", "расплывчато"] = Just RepairSignal
  | T.isInfixOf "ты ушел в шаблон" (T.toLower rawText) = Just RepairSignal
  | T.isInfixOf "ты ушёл в шаблон" (T.toLower rawText) = Just RepairSignal
  | otherwise = Nothing

detectMisunderstanding :: Text -> [Text] -> Maybe PropositionType
detectMisunderstanding rawText tokens
  | T.isInfixOf "не понимаю" (T.toLower rawText)
      && any (`elem` tokens) ["тебя", "тебе", "вас", "диалог", "разговор"] = Just MisunderstandingReport
  | T.isInfixOf "контакт потерян" (T.toLower rawText) = Just MisunderstandingReport
  | any (`elem` tokens) ["извини", "извините", "прости", "простите", "сорри"]
      = Just RepairSignal
  | containsKeywordPhrase tokens "прошу прощения" = Just RepairSignal
  | otherwise = Nothing
