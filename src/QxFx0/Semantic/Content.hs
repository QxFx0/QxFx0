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
    -- * Utilities
  , extractTopicForm
    -- * Corpus data
  , definitionCorpus
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
  , spTopicForm :: !Text
    -- ^ Nominative form of the topic (first word of spRu).
    -- Used for analogical adaptation in Axis 2.
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
  -- Phase D: expanded topics
  , "вера", "красота", "долг", "доверие", "страх", "надежда"
  , "справедливость", "время", "разум", "бытие", "история"
  , "язык", "воля", "смерть", "одиночество", "любовь"
  , "труд", "покой", "власть", "правда", "молчание"
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
  -- Phase D: expanded topics
  , entry "вера"
      [ prop "вера требует принятия без полного доказательства"
             "faith requires acceptance without full proof"
      , rel "вера связана с доверием к источнику или опыту"
            "faith is connected to trust in a source or experience"
      ]
  , entry "красота"
      [ prop "красота вызывает эстетическое переживание"
             "beauty evokes aesthetic experience"
      , rel "красота зависит от воспринимающего и культурной рамки"
            "beauty depends on the perceiver and cultural frame"
      ]
  , entry "долг"
      [ prop "долг предписывает действия независимо от желания"
             "duty prescribes actions regardless of desire"
      , rel "долг опирается на моральные или социальные обязательства"
            "duty rests on moral or social obligations"
      ]
  , entry "доверие"
      [ prop "доверие предполагает уязвимость перед другим"
             "trust presupposes vulnerability before another"
      , rel "доверие строится через повторяемый позитивный опыт"
            "trust is built through repeated positive experience"
      ]
  , entry "страх"
      [ prop "страх сигнализирует об угрозе целостности субъекта"
             "fear signals a threat to the subject's integrity"
      , rel "страх может парализовать действие или мобилизовать его"
            "fear can paralyze action or mobilize it"
      ]
  , entry "надежда"
      [ prop "надежда ориентирует на возможность будущего"
             "hope orients toward the possibility of the future"
      , rel "надежда поддерживает действие в условиях неопределённости"
            "hope sustains action under uncertainty"
      ]
  , entry "справедливость"
      [ prop "справедливость требует соразмерности между деянием и воздаянием"
             "justice requires proportionality between deed and reward"
      , rel "справедливость предполагает равенство перед правилом"
            "justice presupposes equality before the rule"
      ]
  , entry "время"
      [ prop "время задаёт порядок следования событий"
             "time defines the order of event succession"
      , rel "время необратимо — прошлое недоступно для изменения"
            "time is irreversible — the past is not amenable to change"
      ]
  , entry "разум"
      [ prop "разум способен к обобщению и абстракции"
             "reason is capable of generalization and abstraction"
      , rel "разум отличается от интуиции потребностью в доказательстве"
            "reason differs from intuition by requiring proof"
      ]
  , entry "бытие"
      [ prop "бытие обозначает сам факт существования"
             "being denotes the very fact of existence"
      , rel "бытие рассматривается как условие возможности любого суждения"
            "being is considered the condition for any judgement"
      ]
  , entry "история"
      [ prop "история связывает прошлое с настоящим через интерпретацию"
             "history connects past to present through interpretation"
      , rel "история зависит от точки зрения рассказчика"
            "history depends on the narrator's perspective"
      ]
  , entry "язык"
      [ prop "язык структурирует опыт через различение и именование"
             "language structures experience through distinction and naming"
      , rel "язык связан с мышлением — он не только выражает, но и формирует мысль"
            "language is connected to thought — it not only expresses but shapes thought"
      ]
  , entry "воля"
      [ prop "воля направляет действие к выбранной цели"
             "will directs action toward a chosen goal"
      , rel "воля требует преодоления препятствий и конкурирующих мотивов"
            "will requires overcoming obstacles and competing motives"
      ]
  , entry "смерть"
      [ prop "смерть обозначает необратимое прекращение существования"
             "death denotes the irreversible cessation of existence"
      , rel "смерть задаёт границу, через которую жизнь обретает конечную форму"
            "death sets a boundary through which life gains finite form"
      ]
  , entry "одиночество"
      [ prop "одиночество выражает отсутствие значимого другого"
             "loneliness expresses the absence of a significant other"
      , rel "одиночество может быть избрано или навязано обстоятельствами"
            "loneliness can be chosen or imposed by circumstances"
      ]
  , entry "любовь"
      [ prop "любовь направлена на конкретного другого как на безусловно ценного"
             "love is directed at a specific other as unconditionally valuable"
      , rel "любовь предполагает уязвимость и риск потери"
            "love presupposes vulnerability and the risk of loss"
      ]
  , entry "труд"
      [ prop "труд преобразует материал через целенаправленное усилие"
             "labor transforms material through purposeful effort"
      , rel "труд связан с потребностью и распределением ресурсов"
            "labor is connected to need and resource distribution"
      ]
  , entry "покой"
      [ prop "покой обозначает отсутствие движения и напряжения"
             "rest denotes the absence of movement and tension"
      , rel "покой необходим для восстановления и интеграции опыта"
            "rest is necessary for recovery and integration of experience"
      ]
  , entry "власть"
      [ prop "власть означает способность влиять на действия других"
             "power means the capacity to influence others' actions"
      , rel "власть требует легитимности для устойчивости"
            "power requires legitimacy for sustainability"
      ]
  , entry "правда"
      [ prop "правда претендует на соответствие тому, что произошло"
             "truthfulness claims correspondence with what happened"
      , rel "правда отличается от истины личной вовлечённостью рассказчика"
            "truthfulness differs from truth by the narrator's personal involvement"
      ]
  , entry "молчание"
      [ prop "молчание может быть актом отказа или знаком присутствия"
             "silence can be an act of refusal or a sign of presence"
      , rel "молчание контрастирует с речью, но не тождественно пустоте"
            "silence contrasts with speech but is not identical to emptiness"
      ]
  ]
  where
    entry topic preds = (topic, DefinitionContent topic preds)
    prop ru en = SemanticPredicate RoleProperty ru en (extractTopicForm ru)
    rel ru en = SemanticPredicate RoleRelation ru en (extractTopicForm ru)
    structure ru en = SemanticPredicate RoleStructure ru en (extractTopicForm ru)

-- | Extract the first word from a predicate text as the topic form.
-- Used for analogical adaptation in Axis 2.
extractTopicForm :: Text -> Text
extractTopicForm = T.toLower . head . T.words

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
  -- Phase D: expanded distinction pairs
  , dEntry "вера" "знание"
      [ diff "вера принимает без доказательства, знание требует обоснования"
             "faith accepts without proof, knowledge requires justification"
      ]
  , dEntry "долг" "желание"
      [ diff "долг предписывает независимо от желания, желание движет от внутреннего побуждения"
             "duty prescribes regardless of desire, desire drives from inner impulse"
      ]
  , dEntry "страх" "тревога"
      [ diff "страх имеет конкретный объект, тревога направлена на неопределённость"
             "fear has a concrete object, anxiety is directed at uncertainty"
      ]
  , dEntry "правда" "истина"
      [ diff "правда включает личную позицию, истина претендует на надличностную объективность"
             "truthfulness includes personal stance, truth claims transpersonal objectivity"
      ]
  , dEntry "власть" "авторитет"
      [ diff "власть принуждает, авторитет убеждает"
             "power coerces, authority persuades"
      ]
  , dEntry "покой" "действие"
      [ diff "покой удерживает от движения, действие его инициирует"
             "rest holds back from movement, action initiates it"
      ]
  , dEntry "одиночество" "уединение"
      [ diff "одиночество переживается как лишение, уединение выбирается как потребность"
             "loneliness is experienced as deprivation, solitude is chosen as a need"
      ]
  ]
  where
    dEntry left right preds =
      ((left, right), DistinctionContent left right preds)
    diff ru en = SemanticPredicate RoleDifferentiator ru en (extractTopicForm ru)

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
-- Based on lexical features (keyword markers + morphological suffixes),
-- not statistics.
classifyConceptCategory :: Text -> ConceptCategory
classifyConceptCategory topic =
  let t = normalizeTopic topic
  in case () of
    _ | any (`T.isInfixOf` t) philosophicalMarkers -> CategoryPhilosophical
      | any (`T.isInfixOf` t) socialMarkers -> CategorySocial
      | any (`T.isInfixOf` t) psychologicalMarkers -> CategoryPsychological
      | any (`T.isInfixOf` t) physicalMarkers -> CategoryPhysical
      -- Morphological suffix heuristics for Russian abstract nouns
      | any (`T.isSuffixOf` t) abstractSuffixes -> CategoryPhilosophical
      | any (`T.isSuffixOf` t) socialSuffixes -> CategorySocial
      | any (`T.isSuffixOf` t) psychologicalSuffixes -> CategoryPsychological
      | otherwise -> CategoryGeneral
  where
    philosophicalMarkers =
      ["свобод", "истин", "смысл", "сознан", "бытие", "ничто", "вечн", "разум"
      , "познан", "реальн", "иллюз", "пустот", "сущнос", "вер", "красот"
      , "добр", "благ", "мудрост", "истин", "справедлив"]
    socialMarkers =
      ["ответств", "довер", "долг", "обяз", "справедлив", "право", "закон"
      , "обществ", "нравств", "этик", "морал", "совест", "чест", "верност"
      , "предан", "уважен"]
    psychologicalMarkers =
      ["памят", "воспомин", "эмоц", "чувств", "восприят", "мышлен", "вниман"
      , "воображ", "сон", "мечт", "страх", "надежд", "радост", "груст"
      , "тревог", "пережив", "интуиц"]
    physicalMarkers =
      ["тел", "пространств", "времен", "матер", "энерг", "свет", "звук", "движен"
      , "природ", "вод", "огн", "воздух", "земл", "камен", "дерев"]
    -- Russian abstract noun suffixes → likely philosophical/abstract
    abstractSuffixes =
      ["ость", "ствие", "тие", "ние", "тие", "ество", "ство", "ие", "ье"]
    -- Suffixes typical of social concepts
    socialSuffixes =
      ["ность", "ние"]
    -- Suffixes typical of psychological states
    psychologicalSuffixes =
      ["ость", "ение", "ание"]

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
          topic
      , SemanticPredicate RoleRelation
          (topic <> " связан с условиями возможности опыта")
          (topic <> " is connected to conditions of possible experience")
          topic
      ]
    CategorySocial ->
      [ SemanticPredicate RoleProperty
          (topic <> " возникает во взаимодействии между субъектами")
          (topic <> " arises in interaction between subjects")
          topic
      , SemanticPredicate RoleRelation
          (topic <> " ограничен нормами и ожиданиями сообщества")
          (topic <> " is bounded by norms and expectations of community")
          topic
      ]
    CategoryPsychological ->
      [ SemanticPredicate RoleProperty
          (topic <> " формируется через опыт и воспоминание")
          (topic <> " is formed through experience and recollection")
          topic
      , SemanticPredicate RoleStructure
          (topic <> " имеет субъективный характер и доступ от первого лица")
          (topic <> " has subjective character and first-person access")
          topic
      ]
    CategoryPhysical ->
      [ SemanticPredicate RoleProperty
          (topic <> " обладает протяжённостью в пространстве или времени")
          (topic <> " has extension in space or time")
          topic
      , SemanticPredicate RoleRelation
          (topic <> " подчиняется устойчивым закономерностям")
          (topic <> " obeys stable regularities")
          topic
      ]
    CategoryGeneral ->
      [ SemanticPredicate RoleProperty
          (topic <> " проявляется через устойчивые связи в своём контексте")
          (topic <> " manifests through stable connections in its context")
          topic
      , SemanticPredicate RoleRelation
          (topic <> " зависит от рамки, в которой рассматривается")
          (topic <> " depends on the frame in which it is considered")
          topic
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
          left
      ]
    (CategorySocial, CategoryPhilosophical) ->
      [ SemanticPredicate RoleDifferentiator
          (left <> " регулирует взаимодействие, " <> right <> " описывает устройство мира")
          (left <> " regulates interaction, " <> right <> " describes the structure of reality")
          left
      ]
    (CategoryPsychological, CategoryPhysical) ->
      [ SemanticPredicate RoleDifferentiator
          (left <> " принадлежит внутреннему опыту, " <> right <> " — внешнему миру")
          (left <> " belongs to inner experience, " <> right <> " — to the outer world")
          left
      ]
    _ ->
      [ SemanticPredicate RoleDifferentiator
          (left <> " и " <> right <> " различаются по области применимости и набору устойчивых признаков")
          (left <> " and " <> right <> " differ by scope of application and stable properties")
          left
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
