{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.Contact
  ( detectContactSignal
  , detectAffectiveSupport
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  , containsAnyKeywordPhrase
  )
import QxFx0.Policy.ParserKeywords
  ( contactKeywords
  )
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.List as L

detectContactSignal :: Text -> [Text] -> Maybe PropositionType
detectContactSignal rawText tokens
  | containsKeywordPhrase tokens "как ты работаешь" = Nothing
  | containsKeywordPhrase tokens "как вы работаете" = Nothing
  | containsKeywordPhrase tokens "как ты устроен" = Nothing
  | containsKeywordPhrase tokens "как дела" = Just ContactSignal
  | containsKeywordPhrase tokens "как жизнь" = Just ContactSignal
  | containsKeywordPhrase tokens "как ты" && isShortHowYouContact tokens
      && not (containsKeywordPhrase tokens "как ты устроен")
      && not (containsKeywordPhrase tokens "как ты работаешь") = Just ContactSignal
  | T.toLower (T.strip rawText) `elem` ["привет", "здравствуй", "здравствуйте", "салют", "хай", "hello", "hi"]
      = Just ContactSignal
  | any (`T.isInfixOf` T.toLower rawText) ["добрый день", "доброе утро", "добрый вечер", "рад видеть"]
      = Just ContactSignal
  | containsKeywordPhrase tokens "до свидания" = Just ContactSignal
  | containsKeywordPhrase tokens "до встречи" = Just ContactSignal
  | containsKeywordPhrase tokens "всего доброго" = Just ContactSignal
  | containsKeywordPhrase tokens "всего хорошего" = Just ContactSignal
  | any (`elem` tokens) ["пока", "прощай", "бывай", "увидимся", "спасибо", "благодарю", "thanks"]
      = Just ContactSignal
  | containsKeywordPhrase tokens "как сам" = Just ContactSignal
  | containsKeywordPhrase tokens "как настроение" = Just ContactSignal
  | containsKeywordPhrase tokens "рад тебя видеть" = Just ContactSignal
  | containsKeywordPhrase tokens "рад вас видеть" = Just ContactSignal
  | containsKeywordPhrase tokens "начнем разговор" = Just ContactSignal
  | containsKeywordPhrase tokens "начнём разговор" = Just ContactSignal
  | containsKeywordPhrase tokens "можем пообщаться" = Just ContactSignal
  | containsKeywordPhrase tokens "я вернулся" = Just ContactSignal
  | containsKeywordPhrase tokens "снова привет" = Just ContactSignal
  | containsKeywordPhrase tokens "готов к разговору" = Just ContactSignal
  | containsKeywordPhrase tokens "контакт есть" = Just ContactSignal
  | containsKeywordPhrase tokens "есть контакт" = Just ContactSignal
  | containsKeywordPhrase tokens "мы на связи" = Just ContactSignal
  | containsKeywordPhrase tokens "слышишь меня" = Just ContactSignal
  | containsKeywordPhrase tokens "ты онлайн" = Just ContactSignal
  | shortDialogueProbe tokens && any (`elem` tokens) ["поговорим", "обсудим"] = Just ContactSignal
  | otherwise = Nothing
  where
    shortDialogueProbe ts = length ts <= 2

isShortHowYouContact :: [Text] -> Bool
isShortHowYouContact tokens =
  length tokens <= 4
    && not (any (`elem` tokens) ["будешь", "будете", "можешь", "можете", "умеешь", "умеете", "определять", "сделать", "делать", "объяснить"])

detectAffectiveSupport :: Text -> [Text] -> Maybe PropositionType
detectAffectiveSupport rawText tokens
  | containsKeywordPhrase tokens "как не переживать" = Just ContactSignal
  | containsKeywordPhrase tokens "как не волноваться" = Just ContactSignal
  | containsKeywordPhrase tokens "как успокоиться" = Just ContactSignal
  | containsKeywordPhrase tokens "как сохранить спокойствие" = Just ContactSignal
  | containsKeywordPhrase tokens "как держать спокойствие" = Just ContactSignal
  | containsKeywordPhrase tokens "как не паниковать" = Just ContactSignal
  | containsKeywordPhrase tokens "как перестать тревожиться" = Just ContactSignal
  | containsKeywordPhrase tokens "как не тревожиться" = Just ContactSignal
  | containsKeywordPhrase tokens "как выйти из апатии" = Just ContactSignal
  | containsKeywordPhrase tokens "как вернуть мотивацию" = Just ContactSignal
  | containsKeywordPhrase tokens "как вернуть силы" = Just ContactSignal
  | containsKeywordPhrase tokens "как найти силы" = Just ContactSignal
  | containsKeywordPhrase tokens "как перестать переживать" = Just ContactSignal
  | containsKeywordPhrase tokens "как перестать волноваться" = Just ContactSignal
  | containsKeywordPhrase tokens "как справиться с тревогой" = Just ContactSignal
  | containsKeywordPhrase tokens "как справиться со страхом" = Just ContactSignal
  | containsKeywordPhrase tokens "как справиться с апатией" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать если тревожно" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать если страшно" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать когда тревожно" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать когда плохо" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать когда грустно" = Just ContactSignal
  | containsKeywordPhrase tokens "не хочется ничего делать" = Just ContactSignal
  | containsKeywordPhrase tokens "ничего не хочется делать" = Just ContactSignal
  | containsKeywordPhrase tokens "нет сил" = Just ContactSignal
  | containsKeywordPhrase tokens "нет энергии" = Just ContactSignal
  | containsKeywordPhrase tokens "руки опускаются" = Just ContactSignal
  | containsKeywordPhrase tokens "ничего не радует" = Just ContactSignal
  | containsKeywordPhrase tokens "ничего не хочу" = Just ContactSignal
  | containsKeywordPhrase tokens "не могу собраться" = Just ContactSignal
  | containsKeywordPhrase tokens "все бесит" = Just ContactSignal
  | containsKeywordPhrase tokens "всё бесит" = Just ContactSignal
  | containsKeywordPhrase tokens "устал и ничего не хочется" = Just ContactSignal
  | containsKeywordPhrase tokens "устала и ничего не хочется" = Just ContactSignal
  | hasAffectiveLexeme && T.isSuffixOf "?" (T.strip rawText) = Just ContactSignal
  | hasRelaxedRegulationProbe && T.isSuffixOf "?" (T.strip rawText) = Just ContactSignal
  | otherwise = Nothing
  where
    hasAffectiveLexeme =
      any (`elem` tokens)
        [ "тревожно", "тревога", "грустно", "тоскливо", "плохо", "одиноко", "страшно"
        , "паника", "апатия", "выгорел", "выгорела", "переживать", "переживаю"
        , "волноваться", "волнуюсь", "устал", "устала", "сил", "тяжело"
        ]
    hasRelaxedRegulationProbe =
      any (`elem` tokens) ["как"]
        && any (\tok -> any (`T.isPrefixOf` tok) ["пережив", "волнов", "тревож", "паник", "успок", "апат"]) tokens
