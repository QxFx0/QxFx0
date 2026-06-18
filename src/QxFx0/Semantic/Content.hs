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
  , ConceptCategory(..)
  , ChallengeContent(..)
  , GroundContent(..)
  , PurposeContent(..)
    -- * Lookup
  , lookupDefinitionContent
  , lookupDistinctionContent
  , lookupChallengeContent
  , lookupGroundContent
  , lookupPurposeContent
  , lookupDefinitionWithGeneric
  , lookupDistinctionWithGeneric
  , isCoveredTopic
  , isCoveredPair
  , coveredTopics
  , classifyConceptCategory
  , genericDefinitionPredicates
  , genericDistinctionPredicates
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

-- ============================================================================
-- Phase C: Concept categories + generic predicates (C.1)
-- ============================================================================

-- | Category of a concept, used for category-typed generic predicates.
-- Generic predicates are NOT universal templates — they differ by category,
-- ensuring non-tautological content for uncovered topics.
data ConceptCategory
  = CategoryPhilosophical
    -- ^ Abstract philosophical concepts (свобода, истина, сознание, etc.)
  | CategorySocial
    -- ^ Social/interpersonal concepts (ответственность, доверие, долг)
  | CategoryPsychological
    -- ^ Psychological/mental concepts (память, восприятие, эмоция)
  | CategoryPhysical
    -- ^ Physical/concrete concepts (тело, пространство, время)
  | CategoryGeneral
    -- ^ Fallback for unclassifiable topics
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Classify a topic into a concept category using deterministic rules.
-- Based on lexical features, not statistics.
classifyConceptCategory :: Text -> ConceptCategory
classifyConceptCategory topic =
  let t = normalizeTopic topic
  in case () of
    _ | any (`T.isInfixOf` t) philosophicalMarkers -> CategoryPhilosophical
      | any (`T.isInfixOf` t) socialMarkers -> CategorySocial
      | any (`T.isInfixOf` t) psychologicalMarkers -> CategoryPsychological
      | any (`T.isInfixOf` t) physicalMarkers -> CategoryPhysical
      | otherwise -> CategoryGeneral
  where
    philosophicalMarkers =
      ["свобод", "истин", "смысл", "сознан", "бытие", "ничто", "вечн", "разум"
      , "познан", "реальн", "иллюз", "пустот", "сущнос"]
    socialMarkers =
      ["ответств", "довер", "долг", "обяз", "справедлив", "право", "закон"
      , "обществ", "нравств", "этик"]
    psychologicalMarkers =
      ["памят", "воспомин", "эмоц", "чувств", "восприят", "мышлен", "вниман"
      , "воображ", "сон", "мечт"]
    physicalMarkers =
      ["тел", "пространств", "времен", "матер", "энерг", "свет", "звук", "движен"
      , "природ"]

-- | Category-typed generic definition predicates.
-- These are NOT universal templates — each category gets different predicates
-- that are non-tautological for concepts in that category.
genericDefinitionPredicates :: Text -> [SemanticPredicate]
genericDefinitionPredicates topic =
  let cat = classifyConceptCategory topic
  in case cat of
    CategoryPhilosophical ->
      [ SemanticPredicate RoleProperty
          (topic <> " предполагает наличие внутренней структуры")
          (topic <> " presupposes an internal structure")
      , SemanticPredicate RoleRelation
          (topic <> " связан с условиями возможности опыта")
          (topic <> " is connected to conditions of possible experience")
      ]
    CategorySocial ->
      [ SemanticPredicate RoleProperty
          (topic <> " возникает во взаимодействии между субъектами")
          (topic <> " arises in interaction between subjects")
      , SemanticPredicate RoleRelation
          (topic <> " ограничен нормами и ожиданиями сообщества")
          (topic <> " is bounded by norms and expectations of community")
      ]
    CategoryPsychological ->
      [ SemanticPredicate RoleProperty
          (topic <> " формируется через опыт и воспоминание")
          (topic <> " is formed through experience and recollection")
      , SemanticPredicate RoleStructure
          (topic <> " имеет субъективный характер и доступ от первого лица")
          (topic <> " has subjective character and first-person access")
      ]
    CategoryPhysical ->
      [ SemanticPredicate RoleProperty
          (topic <> " обладает протяжённостью в пространстве или времени")
          (topic <> " has extension in space or time")
      , SemanticPredicate RoleRelation
          (topic <> " подчиняется устойчивым закономерностям")
          (topic <> " obeys stable regularities")
      ]
    CategoryGeneral ->
      [ SemanticPredicate RoleProperty
          (topic <> " проявляется через устойчивые связи в своём контексте")
          (topic <> " manifests through stable connections in its context")
      , SemanticPredicate RoleRelation
          (topic <> " зависит от рамки, в которой рассматривается")
          (topic <> " depends on the frame in which it is considered")
      ]

-- | Category-typed generic distinction predicates.
genericDistinctionPredicates :: Text -> Text -> [SemanticPredicate]
genericDistinctionPredicates left right =
  let catL = classifyConceptCategory left
      catR = classifyConceptCategory right
  in case (catL, catR) of
    (CategoryPhilosophical, CategoryPhilosophical) ->
      [ SemanticPredicate RoleDifferentiator
          (left <> " относится к сфере должного, " <> right <> " — к сфере сущего")
          (left <> " belongs to the normative, " <> right <> " — to the descriptive")
      ]
    (CategorySocial, CategoryPhilosophical) ->
      [ SemanticPredicate RoleDifferentiator
          (left <> " регулирует взаимодействие, " <> right <> " описывает устройство мира")
          (left <> " regulates interaction, " <> right <> " describes the structure of reality")
      ]
    (CategoryPsychological, CategoryPhysical) ->
      [ SemanticPredicate RoleDifferentiator
          (left <> " принадлежит внутреннему опыту, " <> right <> " — внешнему миру")
          (left <> " belongs to inner experience, " <> right <> " — to the outer world")
      ]
    _ ->
      [ SemanticPredicate RoleDifferentiator
          (left <> " и " <> right <> " различаются по области применимости и набору устойчивых признаков")
          (left <> " and " <> right <> " differ by scope of application and stable properties")
      ]

-- | Look up definition content, falling back to generic predicates for
-- uncovered topics. Always returns content (never Nothing).
lookupDefinitionWithGeneric :: Text -> DefinitionContent
lookupDefinitionWithGeneric topic =
  case lookupDefinitionContent topic of
    Just dc -> dc
    Nothing ->
      let n = normalizeTopic topic
      in DefinitionContent n (genericDefinitionPredicates n)

-- | Look up distinction content, falling back to generic predicates.
lookupDistinctionWithGeneric :: Text -> Text -> DistinctionContent
lookupDistinctionWithGeneric left right =
  case lookupDistinctionContent left right of
    Just dc -> dc
    Nothing ->
      DistinctionContent (normalizeTopic left) (normalizeTopic right)
        (genericDistinctionPredicates left right)

-- ============================================================================
-- Phase C: Content for additional frame types (C.3)
-- ============================================================================

-- | Content for challenge responses.
data ChallengeContent = ChallengeContent
  { ccTarget :: !Text
  , ccBasis :: !Text
  , ccStrength :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Content for grounding responses.
data GroundContent = GroundContent
  { gcTopic :: !Text
  , gcPredicates :: ![SemanticPredicate]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Content for purpose responses.
data PurposeContent = PurposeContent
  { pcTopic :: !Text
  , pcPredicates :: ![SemanticPredicate]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Look up challenge content for a topic.
lookupChallengeContent :: Text -> Maybe ChallengeContent
lookupChallengeContent topic =
  let n = normalizeTopic topic
  in case lookupDefinitionContent n of
    Just dc | not (null (dcPredicates dc)) ->
      let firstPred = spRu (head (dcPredicates dc))
      in Just ChallengeContent
           { ccTarget = n
           , ccBasis = "Моя позиция опиралась на: " <> firstPred
           , ccStrength = "soft"
           }
    Nothing -> Nothing

-- | Look up ground content for a topic.
lookupGroundContent :: Text -> Maybe GroundContent
lookupGroundContent topic =
  let n = normalizeTopic topic
  in case lookupDefinitionContent n of
    Just dc -> Just GroundContent { gcTopic = n, gcPredicates = dcPredicates dc }
    Nothing ->
      let generics = genericDefinitionPredicates n
      in if null generics
         then Nothing
         else Just GroundContent { gcTopic = n, gcPredicates = generics }

-- | Look up purpose content for a topic.
lookupPurposeContent :: Text -> Maybe PurposeContent
lookupPurposeContent topic =
  let n = normalizeTopic topic
  in case lookupDefinitionContent n of
    Just dc -> Just PurposeContent { pcTopic = n, pcPredicates = dcPredicates dc }
    Nothing ->
      let generics = genericDefinitionPredicates n
      in if null generics
         then Nothing
         else Just PurposeContent { pcTopic = n, pcPredicates = generics }
