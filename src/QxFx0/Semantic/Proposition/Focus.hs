{-# LANGUAGE OverloadedStrings #-}
{-| Focus entity extraction from user utterances.

This module provides functions to identify the primary focus entity
in a proposition, using various heuristics including contrast markers,
marker phrases, and scoring algorithms.
-}
module QxFx0.Semantic.Proposition.Focus
  ( -- * Main extraction
    extractFocusEntity
    -- * Helper functions
  , extractKeyPhrases
  , dedupeNormalized
  , dedupeEvidence
  , isSemanticCandidateSurface
  , isFocusCandidate
  , normalizeFocus
  , logicalFocusStopwords
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.List as L
import qualified Data.Char as Char
import Data.Maybe (fromMaybe, listToMaybe)
import Control.Applicative ((<|>))
import QxFx0.Semantic.Morphology (extractContentNouns)
import QxFx0.Semantic.KeywordMatch (tokenizeKeywordText)
import QxFx0.Policy.ParserKeywords (fallbackFocusWord)

-- | Extract the primary focus entity from raw text.
-- Uses multiple strategies: contrast markers, marker phrases, and scoring.
extractFocusEntity :: Text -> Text
extractFocusEntity rawText =
  let trimWord = T.dropAround (\c -> not (Char.isAlphaNum c) && c /= '-')
      nouns = extractContentNouns rawText
      candidates = filter isFocusCandidate (nouns <> map trimWord (T.words rawText))
      scored = L.sortOn (negate . focusScore rawText) (dedupeNormalized candidates)
  in fromMaybe (fallbackFocus rawText) (contrastFocus rawText <|> markerPhraseFocus rawText <|> listToMaybe scored)
  where
    cleanWord = T.dropAround (\c -> not (Char.isAlphaNum c) && c /= '-')
    fallbackFocus t =
      let words' = filter isFocusCandidate (map cleanWord (T.words t))
      in fromMaybe fallbackFocusWord (listToMaybe words')

-- | Extract focus after contrast markers (e.g., "but", "however").
contrastFocus :: Text -> Maybe Text
contrastFocus rawText =
  let tokens = tokenizeKeywordText rawText
      afterContrast = drop 1 (dropWhile (`notElem` contrastFocusMarkers) tokens)
  in listToMaybe (filter isFocusCandidate afterContrast)

contrastFocusMarkers :: [Text]
contrastFocusMarkers =
  [ "а", "но", "однако", "зато", "but", "however", "although", "whereas" ]

-- | Extract focus after specific marker phrases.
markerPhraseFocus :: Text -> Maybe Text
markerPhraseFocus rawText =
  let tokens = tokenizeKeywordText rawText
      candidates = concatMap (`focusAfterPhrase` tokens) focusMarkerPhrases
  in listToMaybe (filter isFocusCandidate candidates)

focusAfterPhrase :: [Text] -> [Text] -> [Text]
focusAfterPhrase phrase tokens =
  case dropAfterPhrase phrase tokens of
    Nothing -> []
    Just rest -> take 4 rest

dropAfterPhrase :: [Text] -> [Text] -> Maybe [Text]
dropAfterPhrase phrase tokens
  | null phrase = Nothing
  | otherwise = go tokens
  where
    phraseLength = length phrase
    go [] = Nothing
    go xs
      | phrase `L.isPrefixOf` xs = Just (drop phraseLength xs)
      | otherwise = go (drop 1 xs)

focusMarkerPhrases :: [[Text]]
focusMarkerPhrases =
  [ ["имеет", "право"]
  , ["имеет", "основание"]
  , ["является", "причиной"]
  , ["является", "условием"]
  , ["необходимо", "для"]
  , ["достаточно", "для"]
  , ["следует", "из"]
  , ["вытекает", "из"]
  , ["различие", "между"]
  , ["разница", "между"]
  , ["отличается", "от"]
  , ["has", "the", "right"]
  , ["has", "reason"]
  , ["is", "necessary", "for"]
  , ["is", "sufficient", "for"]
  , ["follows", "from"]
  , ["difference", "between"]
  ]

-- | Score a candidate focus entity based on occurrence, markers, and length.
focusScore :: Text -> Text -> Int
focusScore rawText candidate =
  let tokens = tokenizeKeywordText rawText
      key = normalizeFocus candidate
      occurrenceBonus = if countToken key tokens > 1 then 20 else 0
      markerBonus = if followsFocusMarker key tokens then 12 else 0
      lengthBonus = min 8 (T.length key)
  in occurrenceBonus + markerBonus + lengthBonus

followsFocusMarker :: Text -> [Text] -> Bool
followsFocusMarker key tokens =
  any matches (zip tokens (drop 1 tokens))
  where
    matches (marker, value) =
      marker `elem` focusMarkers && value == key

focusMarkers :: [Text]
focusMarkers =
  [ "о", "об", "про", "между", "различить", "вывод", "посылка", "следует"
  , "право", "основание", "причина", "условие", "necessary", "sufficient"
  ]

countToken :: Text -> [Text] -> Int
countToken key = length . filter (== key)

-- | Remove duplicates based on normalized form.
dedupeNormalized :: [Text] -> [Text]
dedupeNormalized = go []
  where
    go _ [] = []
    go seen (x:xs)
      | normalizeFocus x `elem` seen = go seen xs
      | otherwise = x : go (normalizeFocus x : seen) xs

-- | Remove duplicate evidence entries.
dedupeEvidence :: [Text] -> [Text]
dedupeEvidence = go []
  where
    go _ [] = []
    go seen (x:xs)
      | key `elem` seen = go seen xs
      | otherwise = x : go (key : seen) xs
      where
        key = T.toLower (T.strip x)

-- | Check if text is a valid semantic candidate (not internal metadata).
isSemanticCandidateSurface :: Text -> Bool
isSemanticCandidateSurface raw =
  let txt = T.toLower (T.strip raw)
  in not (T.null txt)
      && not ("frame." `T.isPrefixOf` txt)
      && not ("route_" `T.isPrefixOf` txt)
      && not ("clause=" `T.isPrefixOf` txt)
      && not ("score_" `T.isPrefixOf` txt)
      && not ("family=" `T.isPrefixOf` txt)
      && not ("confidence=" `T.isPrefixOf` txt)
      && not (T.any (`elem` ['=', '|']) txt)

-- | Check if text is a valid focus candidate.
isFocusCandidate :: Text -> Bool
isFocusCandidate raw =
  let key = normalizeFocus raw
  in T.length key >= 3 && key `notElem` logicalFocusStopwords

-- | Normalize focus text to lowercase first token.
normalizeFocus :: Text -> Text
normalizeFocus raw =
  case tokenizeKeywordText raw of
    (x:_) -> x
    [] -> T.toLower (T.strip raw)

-- | Stopwords that should not be considered as focus entities.
logicalFocusStopwords :: [Text]
logicalFocusStopwords =
  [ "если", "что", "кто", "как", "зачем", "все", "всякое", "всякий", "каждый", "каждая", "следовательно"
  , "отсюда", "здесь", "где", "когда", "почему", "можно", "нужно", "либо"
  , "если", "тогда", "значит", "вывести", "объясни", "правило"
  , "влечёт", "влечет", "следует", "заключить"
  , "должен", "должна", "должно", "должны", "обязан", "обязана"
  , "обязано", "обязаны", "нельзя", "разрешено", "запрещено"
  , "может", "могу", "нужно", "надо", "необходимо", "необходимое", "необходимый", "необходимая"
  , "необходимым", "достаточно", "достаточное", "достаточный"
  , "достаточная", "достаточным", "вероятно", "возможно", "является", "ещё", "еще"
  , "очевидно", "пока", "прежде", "после", "затем", "потом", "раньше"
  , "позже", "одновременно", "но", "или", "однако", "зато", "хотя"
  , "некоторые", "никто", "ничто", "кроме", "исключением"
  , "иметь", "имеет", "имею", "имеешь", "имеют", "права", "право", "правом"
  , "обязанность", "обязанностью", "обязательство", "долг", "долга"
  , "if", "then", "therefore", "because", "all", "every", "where", "does"
  , "what", "which", "identify", "premise", "conclusion", "must", "should", "not"
  , "may", "can", "could", "allowed", "forbidden", "right", "obligation", "duty"
  , "obligated", "responsible", "boundary", "fault"
  , "necessary", "sufficient", "possible", "probable"
  , "evident", "when", "while", "before", "after", "until", "once"
  , "however", "but", "although", "whereas", "some", "no", "none", "except"
  , "стало", "быть", "итак", "поэтому", "потому"
  , "логически", "логический"
  , "свой", "своя", "своё", "свое", "свои", "свою"
  , "мой", "моя", "моё", "мое", "мои", "мою"
  , "твой", "твоя", "твоё", "твое", "твои", "твою"
  , "его", "ее", "её", "их", "наш", "наша", "наше", "наши", "ваш", "ваша", "ваше", "ваши"
  , "знаешь", "знать", "умеешь", "уметь", "можешь", "мочь", "будешь", "будет", "буду"
  , "думаешь", "думать", "есть", "такой", "такая", "такое", "зовут"
  , "тут", "здесь", "там"
  , "hence", "thus", "so", "consequently", "since"
  ]

-- | Extract key phrases (words longer than 4 characters).
extractKeyPhrases :: [Text] -> [Text]
extractKeyPhrases tokens =
  let long = filter (\w -> T.length w > 4) tokens
  in take 5 long

