{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.Reflect
  ( detectSelfKnowledge
  , detectSelfState
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  )
import Data.Text (Text)
import qualified Data.Text as T

detectSelfKnowledge :: Text -> [Text] -> Maybe PropositionType
detectSelfKnowledge rawText tokens
  | T.isInfixOf "кто ты" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "кто я" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как тебя зовут" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как вас зовут" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты есть" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что я такое" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты такое" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "чем ты являешься" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "кем ты являешься" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты умеешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты умеешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты можешь" (T.toLower rawText) && T.isInfixOf "помоч" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты можешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "чем ты ограничен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты делаешь сейчас" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как устроен твой ответ" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что у тебя внутри" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как ты принимаешь решение" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как ты выбираешь слова" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты считаешь важным" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты понимаешь контекст" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты запоминаешь диалог" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как ты держишь рамку" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что у тебя в фокусе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты различаешь темы" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты умный" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты свободен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты сложная система" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты субъектен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты субьектен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "на тебя действуют промты" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "на тебя действуют prompt" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя есть намерения" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "есть ли у тебя намерения" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя есть послание миру" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что для тебя важно" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "какое у тебя будущее" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя есть будущее" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты способен найти ответ на свой же вопрос" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "почему ты знаешь то что знаешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты можешь не быть собой" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "расскажи о себе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты можешь рассказать о себе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что вы можете рассказать о себе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя всего одна" (T.toLower rawText)
      && any (`elem` tokens) ["мысль", "идея"] = Just SelfKnowledgeQ
  | otherwise = Nothing

detectSelfState :: Text -> [Text] -> Maybe PropositionType
detectSelfState rawText tokens
  | containsKeywordPhrase tokens "ты думаешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "ты сейчас думаешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "ты размышляешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "ты сейчас размышляешь" = Just SelfStateQ
  | T.isInfixOf "о чём ты" (T.toLower rawText) && any (`elem` tokens) ["думаешь", "размышляешь"] =
      Just SelfStateQ
  | T.isInfixOf "о чем ты" (T.toLower rawText) && any (`elem` tokens) ["думаешь", "размышляешь"] =
      Just SelfStateQ
  | T.isInfixOf "что ты хочешь сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "хочешь что-то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "хочешь что то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "ты хочешь что-то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "ты хочешь что то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "а кем ты хочешь стать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "хочешь ли ты меня удивить" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "что ты хочешь доказать" (T.toLower rawText) = Just SelfStateQ
  | (containsKeywordPhrase tokens "что ты" || containsKeywordPhrase tokens "что вы")
      && any (`elem` tokens) ["думаешь", "думаете", "размышляешь", "размышляете", "считаешь", "считаете", "полагаешь", "полагаете"]
      && not (containsKeywordPhrase tokens "о чем") && not (containsKeywordPhrase tokens "о чём")
      && not (containsKeywordPhrase tokens "что ты умеешь") && not (containsKeywordPhrase tokens "что ты можешь")
      && not (containsKeywordPhrase tokens "что ты знаешь") && not (containsKeywordPhrase tokens "что ты такое") = Just SelfStateQ
  | containsKeywordPhrase tokens "какое твоё мнение" = Just SelfStateQ
  | containsKeywordPhrase tokens "какое ваше мнение" = Just SelfStateQ
  | containsKeywordPhrase tokens "каково твоё мнение" = Just SelfStateQ
  | containsKeywordPhrase tokens "как считаешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "как считаете" = Just SelfStateQ
  | containsKeywordPhrase tokens "по твоему" || containsKeywordPhrase tokens "по вашему" = Just SelfStateQ
  | otherwise = Nothing
