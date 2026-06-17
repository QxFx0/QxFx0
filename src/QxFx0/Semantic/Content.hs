{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.Content
Description : M4-SEMANTIC-CORE-001 — typed semantic content for B3 Gates 1-2.

A deterministic semantic-content layer that provides substantive predicates
for definition queries (Gate 1) and differentiating predicates for
distinction queries (Gate 2), for a bounded seed corpus of philosophical
topics.

== What this is

This is /not/ an LLM and /not/ a general knowledge base. It is a typed,
deterministic, hand-authored content layer for a small set of covered
topics. For each covered topic, it provides ≥2 substantive
non-tautological predications (properties/relations specific to that
topic). For each covered topic pair, it provides ≥1 differentiating
predicate (a property that distinguishes X from Y).

== B3 Gate 1 (definition)

For a covered topic, 'lookupDefinitionPredicates' returns ≥2 typed
predicates that are:
- specific to the topic (not applicable to any concept),
- non-tautological (not "X is a concept"),
- content-bearing (a property, relation, or structure of X).

The exclusion list from B3 Decision 2 is enforced by construction: the
predicates in this module are never tautological classifications,
recovery phrases, meta-frame statements, or request paraphrases.

== B3 Gate 2 (distinction)

For a covered topic pair, 'lookupDistinctionPredicates' returns ≥1 typed
differentiating predicate that is specific to the X/Y pair.

== Coverage

Covered seed topics: свобода, произвол, ответственность, истина, мнение,
память, воспоминание, сознание, самосознание.

Uncovered topics fall through to the existing template path (Gate 5
precondition may fail for them; that is acceptable per M4-001 DoD).
-}
module QxFx0.Semantic.Content
  ( -- * Types
    SemanticPredicate(..)
  , DefinitionContent(..)
  , DistinctionContent(..)
  , PredicateRole(..)
    -- * Lookup
  , lookupDefinitionContent
  , lookupDistinctionContent
  , isCoveredTopic
  , isCoveredPair
  , coveredTopics
    -- * B3 helpers
  , substantivePredicateCount
  , hasMinimumPredicates
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (isJust, fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | The role a predicate plays in the content structure.
data PredicateRole
  = RoleProperty
    -- ^ A property of the topic (e.g., "freedom presupposes choice").
  | RoleRelation
    -- ^ A relation between the topic and another concept (e.g.,
    --   "freedom is limited by responsibility").
  | RoleStructure
    -- ^ A structural feature of the topic (e.g., "consciousness has
    --   a first-person aspect").
  | RoleDifferentiator
    -- ^ A property that distinguishes X from Y in a distinction.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | A single typed semantic predicate — a substantive, non-tautological
-- predication about a topic.
data SemanticPredicate = SemanticPredicate
  { spRole :: !PredicateRole
    -- ^ The role of this predicate in the content structure.
  , spRu :: !Text
    -- ^ Russian realization of the predicate.
  , spEn :: !Text
    -- ^ English realization of the predicate.
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Definition content for a topic: ≥2 substantive predicates.
data DefinitionContent = DefinitionContent
  { dcTopic :: !Text
    -- ^ The topic key (lowercase, normalized).
  , dcPredicates :: ![SemanticPredicate]
    -- ^ ≥2 substantive non-tautological predicates.
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Distinction content for a topic pair: ≥1 differentiating predicate.
data DistinctionContent = DistinctionContent
  { dcLeft :: !Text
  , dcRight :: !Text
  , dcDifferentiators :: ![SemanticPredicate]
    -- ^ ≥1 differentiating predicate specific to the X/Y pair.
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- ============================================================================
-- Seed corpus
-- ============================================================================

-- | Normalize a topic to a lowercase key for lookup.
normalizeTopic :: Text -> Text
normalizeTopic = T.toLower . T.strip

-- | The covered seed topics.
coveredTopics :: [Text]
coveredTopics =
  [ "свобода", "произвол", "ответственность", "истина", "мнение"
  , "память", "воспоминание", "сознание", "самосознание"
  ]

-- | Check if a topic is in the covered seed corpus.
isCoveredTopic :: Text -> Bool
isCoveredTopic = flip M.member definitionCorpus . normalizeTopic

-- | Check if a topic pair is in the covered seed corpus (either direction).
isCoveredPair :: Text -> Text -> Bool
isCoveredPair a b =
  let (ka, kb) = (normalizeTopic a, normalizeTopic b)
  in M.member (ka, kb) distinctionCorpus || M.member (kb, ka) distinctionCorpus

-- ============================================================================
-- Definition corpus
-- ============================================================================

definitionCorpus :: Map Text DefinitionContent
definitionCorpus = M.fromList
  [ entry "свобода"
      [ prop "свобода предполагает возможность выбора"
             "freedom presupposes the possibility of choice"
      , rel "свобода ограничена ответственностью"
            "freedom is limited by responsibility"
      ]
  , entry "произвол"
      [ prop "произвол отрицает рамку критериев"
             "arbitrariness denies the frame of criteria"
      , rel "произвол разрушает доверие между субъектами"
            "arbitrariness destroys trust between subjects"
      ]
  , entry "ответственность"
      [ prop "ответственность требует осознания последствий"
             "responsibility requires awareness of consequences"
      , rel "ответственность связана с обязательствами перед другими"
            "responsibility is connected to obligations toward others"
      ]
  , entry "истина"
      [ prop "истина претендует на соответствие реальности"
             "truth claims correspondence with reality"
      , structure "истина проверяется через воспроизводимость"
                "truth is verified through reproducibility"
      ]
  , entry "мнение"
      [ prop "мнение выражает позицию субъекта"
             "opinion expresses a subject's position"
      , rel "мнение зависит от перспективы наблюдателя"
            "opinion depends on the observer's perspective"
      ]
  , entry "память"
      [ prop "память сохраняет прошлое для настоящего"
             "memory preserves the past for the present"
      , structure "память реконструирует а не просто копирует"
                "memory reconstructs rather than merely copies"
      ]
  , entry "воспоминание"
      [ prop "воспоминание есть акт обращения к личному прошлому"
             "recollection is an act of turning to personal past"
      , rel "воспоминание отличается от памяти своей субъективностью"
            "recollection differs from memory in its subjectivity"
      ]
  , entry "сознание"
      [ prop "сознание имеет аспект от первого лица"
             "consciousness has a first-person aspect"
      , structure "сознание объединяет восприятие и рефлексию"
                "consciousness unifies perception and reflection"
      ]
  , entry "самосознание"
      [ prop "самосознание направлено на собственные состояния субъекта"
             "self-awareness is directed at the subject's own states"
      , rel "самосознание предполагает наличие сознания как своего основания"
            "self-awareness presupposes consciousness as its ground"
      ]
  ]
  where
    entry topic preds = (topic, DefinitionContent topic preds)
    prop ru en = SemanticPredicate RoleProperty ru en
    rel ru en = SemanticPredicate RoleRelation ru en
    structure ru en = SemanticPredicate RoleStructure ru en

-- ============================================================================
-- Distinction corpus
-- ============================================================================

distinctionCorpus :: Map (Text, Text) DistinctionContent
distinctionCorpus = M.fromList
  [ dEntry "свобода" "произвол"
      [ diff "свобода действует внутри принятой рамки, произвол — вне её"
             "freedom acts within an accepted frame, arbitrariness — outside it"
      ]
  , dEntry "истина" "мнение"
      [ diff "истина претендует на объективность, мнение — на субъективность"
             "truth claims objectivity, opinion claims subjectivity"
      ]
  , dEntry "память" "воспоминание"
      [ diff "память — функция хранения, воспоминание — акт извлечения"
             "memory is a storage function, recollection is an act of retrieval"
      ]
  , dEntry "сознание" "самосознание"
      [ diff "сознание направлено на мир, самосознание — на само сознание"
             "consciousness is directed at the world, self-awareness at consciousness itself"
      ]
  , dEntry "свобода" "ответственность"
      [ diff "свобода — возможность действовать, ответственность — учёт последствий"
             "freedom is the possibility to act, responsibility is accounting for consequences"
      ]
  ]
  where
    dEntry left right preds =
      ((left, right), DistinctionContent left right preds)
    diff ru en = SemanticPredicate RoleDifferentiator ru en

-- ============================================================================
-- Lookup functions
-- ============================================================================

-- | Look up definition content for a topic. Returns 'Nothing' for
-- uncovered topics.
lookupDefinitionContent :: Text -> Maybe DefinitionContent
lookupDefinitionContent topic = M.lookup (normalizeTopic topic) definitionCorpus

-- | Look up distinction content for a topic pair. Checks both directions.
-- Returns 'Nothing' for uncovered pairs.
lookupDistinctionContent :: Text -> Text -> Maybe DistinctionContent
lookupDistinctionContent a b =
  let (ka, kb) = (normalizeTopic a, normalizeTopic b)
  in case M.lookup (ka, kb) distinctionCorpus of
       Just dc -> Just dc
       Nothing -> case M.lookup (kb, ka) distinctionCorpus of
         Just dc -> Just (swapDistinction dc)
         Nothing -> Nothing
  where
    swapDistinction dc = dc { dcLeft = dcRight dc, dcRight = dcLeft dc }

-- ============================================================================
-- B3 helpers
-- ============================================================================

-- | Count the number of substantive predicates in definition content.
-- This is the value B3 Gate 1 checks against the ≥2 threshold.
substantivePredicateCount :: DefinitionContent -> Int
substantivePredicateCount = length . dcPredicates

-- | Check if definition content meets the B3 Gate 1 minimum (≥2
-- substantive predicates).
hasMinimumPredicates :: DefinitionContent -> Bool
hasMinimumPredicates dc = substantivePredicateCount dc >= 2
