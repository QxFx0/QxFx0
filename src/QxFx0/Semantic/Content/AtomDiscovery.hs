{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Content.AtomDiscovery
Description : Automatic atom discovery from brain_kb.

Discovers candidate atoms from brain_kb entries by:
1. Extracting noun-like triggers (Cyrillic, >=4 chars)
2. Filtering by frequency (>=10 occurrences)
3. Excluding existing atoms and stop words
4. Returning as CatDiscovered atoms

These atoms are merged with seed atoms at bootstrap time,
expanding the graph from 85 hand-written atoms to 200+.
-}
module QxFx0.Semantic.Content.AtomDiscovery
  ( discoverAtoms
  , DiscoveredAtom(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (foldl', sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore (Atom(..), AtomId(..), AtomCategory(..), atomStore, allAtomIds)
import QxFx0.Semantic.Network.Substrate (BrainKBEntry(..))

-- | Discovered atom metadata for observability.
data DiscoveredAtom = DiscoveredAtom
  { daAtom   :: !Atom
  , daFreq   :: !Int      -- frequency in brain_kb
  , daSource :: !Text     -- "brain_kb_discovery"
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Discover candidate atoms from brain_kb entries.
-- Returns atoms sorted by frequency (highest first).
-- Filters:
--   - Cyrillic only (Russian nouns)
--   - Length >= 4 chars
--   - Frequency >= 10 across all entries
--   - Not already in atomStore
--   - Not a stop word
discoverAtoms :: [BrainKBEntry] -> [DiscoveredAtom]
discoverAtoms entries =
  let existingIds = allAtomIds
      existingSet = M.fromList [(aid, ()) | aid <- existingIds]
      freqMap = countTriggerFrequency entries
      candidates = [ (trigger, freq)
                   | (trigger, freq) <- M.toList freqMap
                   , freq >= 10
                   , T.length trigger >= 4
                   , isCyrillic trigger
                   , not (isStopWord trigger)
                   , AtomId trigger `M.notMember` existingSet
                   , not (any (\t -> t `T.isInfixOf` trigger) l1TopicPrefixes)
                   ]
      discovered = [ DiscoveredAtom
                       { daAtom = Atom (AtomId trigger) trigger trigger trigger CatDiscovered
                       , daFreq = freq
                       , daSource = "brain_kb_discovery"
                       }
                   | (trigger, freq) <- sortOn (\(t, f) -> (negate f, t)) candidates
                   ]
  in take 300 discovered  -- cap at 300 to keep graph manageable

-- | L1 topic prefixes to exclude (avoid "свободный" matching "свобода")
l1TopicPrefixes :: [Text]
l1TopicPrefixes =
  [ "свобод", "произвол", "ответствен", "истин", "мнен", "памят"
  , "воспомин", "сознан", "вера", "красот", "долг", "довери"
  , "страх", "надежд", "справедлив", "врем", "разум", "быти"
  , "истори", "язык", "вол", "смерт", "одиночеств", "любов"
  , "труд", "поко", "власт", "правд", "молчан", "смысл"
  , "границ", "цифр", "идентичност", "ремонт"
  ]

-- | Count trigger frequency across all brain_kb entries.
countTriggerFrequency :: [BrainKBEntry] -> Map Text Int
countTriggerFrequency = foldl' increment mempty
  where
    increment acc entry =
      let triggers = beTriggers entry
          lowered = map T.toLower triggers
          filtered = [ t | t <- lowered, T.length t >= 4 ]
      in foldl' (\m t -> M.insertWith (+) t 1 m) acc filtered

-- | Check if text is purely Cyrillic.
isCyrillic :: Text -> Bool
isCyrillic text = T.all isCyrillicChar text
  where
    isCyrillicChar c = (c >= 'а' && c <= 'я') || c == 'ё' || (c >= 'А' && c <= 'Я') || c == 'Ё'

-- | Stop words to exclude from discovery.
stopWords :: [Text]
stopWords =
  [ "это", "что", "как", "или", "но", "для", "при", "все", "всё"
  , "если", "чтобы", "потому", "когда", "где", "почему", "зачем"
  , "кто", "сколько", "только", "даже", "уже", "ещё", "еще"
  , "было", "будет", "есть", "нет", "над", "под", "между"
  , "без", "через", "именно", "его", "тебе", "этом", "может"
  , "происходит", "становится", "является", "можно", "прав"
  , "вопрос", "диалог", "режим", "форма", "роль", "точка"
  , "уровень", "ответ", "связи", "отношения", "система"
  , "состояние", "момент", "человек", "процесс", "модель"
  , "реальности", "реальность", "структура", "границы"
  , "правила", "правило", "законы", "закон", "факт", "факты"
  , "доказательство", "свидетельство", "закономерность"
  , "поддержка", "обеспечение", "выполнение", "исполнение"
  , "запрос", "разрыв", "неоднозначность", "проекция"
  , "ясность", "атмосфера", "быть", "связи"
  -- technical / system terms
  , "реляционный", "интеллектуализация", "инварианты"
  , "проектирование", "хаскель", "дизайн", "прерыватель"
  , "рекурсия", "строки", "триггер", "предикат", "предикаты"
  , "типы", "рантайм", "архитектура", "архитектурный"
  , "композиционный", "проецирование", "хранилище"
  , "протокол", "дуга", "перформанс", "абдукция", "домен"
  , "парадигма", "композиция", "онтология", "онтологический"
  , "структурный", "инвариант", "семантический", "семантика"
  , "ошибка", "сбой", "отказ", "стратегия", "значение"
  , "истинность", "предикат", "предикаты"
  ]

isStopWord :: Text -> Bool
isStopWord w = w `elem` stopWords
