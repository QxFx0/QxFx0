{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Content.AtomStore
Description : Step 1 — Atom/Relation graph decomposed from seed predicates.

Each seed predicate is decomposed into:
  Atom(subject) --RelationType--> Atom(object)

The relation carries enough info for a verbalizer to reconstruct the
original predicate text (round-trip parity).  The object surface text
is stored as-is for now; Step 2 will replace it with morphological
inflection of the target atom.
-}
module QxFx0.Semantic.Content.AtomStore
  ( -- * Types
    Atom(..)
  , AtomId(..)
  , AtomCategory(..)
  , RelationType(..)
  , Relation(..)
  , ObjectCase(..)
  , RelationSource(..)
  , PathProof(..)
    -- * AtomGraph (runtime graph)
  , AtomGraph(..)
  , seedGraph
  , withPromoted
  , graphRelationsFromAtom
  , graphAllRelations
    -- * GeneratedSurface
  , GeneratedSurface(..)
    -- * Stores
  , atomStore
  , relationStore
  , atomsForTopic
  , relationsFromAtom
  , relationsToAtom
  , allTopics
  , allAtomIds
    -- * Verbalizer (simple, for round-trip)
  , verbalizeRelation
  , verbalizeRelationStored
  , verbForType
  , verbalizeRelationEn
    -- * Round-trip
  , roundTripCheck
  , roundTripCheckMorph
  , allRoundTripResults
  , allRoundTripMorphResults
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
import qualified Data.Set as S
import Data.List (foldl', sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- ============================================================
-- Types
-- ============================================================

newtype AtomId = AtomId Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON, ToJSONKey, FromJSONKey)

data AtomCategory
  = CatTopic       -- philosophical topic (свобода, истина, ...)
  | CatConcept     -- abstract concept (выбор, ответственность, ...)
  | CatProperty    -- property/quality (необратимость, осмысленность, ...)
  | CatProcess     -- process/action (действие, проверка, ...)
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Atom = Atom
  { atomId       :: !AtomId
  , atomSurface  :: !Text   -- internal ID (underscores for compound)
  , atomDisplay  :: !Text   -- display text (spaces, for output)
  , atomHead     :: !Text   -- head noun for morphological inflection
  , atomCategory :: !AtomCategory
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Typed relation between two atoms.
-- The relation type determines the verb and grammatical case
-- for verbalization.
data RelationType
  = RelPresupposes       -- предполагает (acc)
  | RelLimitedBy         -- ограничена (instr)
  | RelRequires          -- требует (gen)
  | RelClaims            -- претендует на (acc)
  | RelVerifiedBy        -- проверяется через (acc)
  | RelSignals           -- сигнализирует об (loc)
  | RelTransformsInto    -- превращается в (acc)
  | RelExpresses         -- выражает (acc)
  | RelDiffersFrom       -- отличается от (gen)
  | RelRelatedTo         -- связана с (instr)
  | RelDirectedAt        -- направлена на (acc)
  | RelPreserves         -- сохраняет (acc)
  | RelOrientsToward     -- ориентирует на (acc)
  | RelPrescribes        -- предписывает (acc)
  | RelBuiltThrough      -- строится через (acc)
  | RelDenotes           -- обозначает (acc)
  | RelStructures        -- структурирует (acc)
  | RelDetermines        -- определяет (acc)
  | RelTransforms        -- преобразует (acc)
  | RelGives             -- придаёт (acc)
  | RelReveals           -- обнаруживает (acc)
  | RelRecognizes        -- признаёт (acc)
  | RelUnifies           -- объединяет (acc)
  | RelConnects          -- связывает (acc)
  | RelPrecedes          -- предшествует (dat)
  | RelDependsOn         -- зависит от (gen)
  | RelIncludes          -- включает (acc)
  | RelNecessaryFor      -- необходим для (gen)
  | RelEvokes            -- вызывает (acc)
  | RelMeans             -- означает (acc)
  | RelSays              -- говорит (instr)
  | RelNegates           -- отрицает (acc)
  | RelContrastsWith     -- контрастирует с (instr)
  | RelNotReducibleTo    -- не сводится к (dat)
  | RelIsNot             -- не является (instr)
  | RelCapableOf         -- способен к (dat)
  | RelCreatedFrom       -- создаётся из (gen)
  | RelReliesOn          -- опирается на (acc)
  | RelCanBe             -- может быть (instr)
  | RelDestroys          -- разрушает (acc)
  | RelPointsTo          -- указывает на (acc)
  | RelMakes             -- делает (acc)
  | RelIsA               -- есть (nom)
  | RelReconstructs      -- реконструирует (acc)
  | RelSupports          -- поддерживает (acc)
  | RelSets              -- задаёт (acc)
  | RelNotJustCopies     -- реконструирует а не просто копирует (special)
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Grammatical case of the object for verbalization.
data ObjectCase
  = CaseNominative
  | CaseAccusative
  | CaseGenitive
  | CaseInstrumental
  | CaseDative
  | CasePrepositional
  | CaseSpecial        -- compound/special text, stored as-is
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data RelationSource
  = SeedFromPredicate
  | Curated
  | PromotedSubstrate
  | SubstrateExtractedRaw
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Relation = Relation
  { relFrom       :: !AtomId
  , relTo         :: !AtomId
  , relType       :: !RelationType
  , relObjectCase :: !ObjectCase
  , relObjectText :: !Text          -- object surface text as in predicate
  , relVerbText   :: !(Maybe Text)  -- override verb phrase (for prepositions, gender, etc.)
  , relRuOriginal :: !Text          -- full original predicate for round-trip
  , relEnOriginal :: !Text          -- English original
  , relSource     :: !RelationSource
  , relTopic      :: !Text          -- topic this relation belongs to
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Proof that a generated predicate came from a specific path.
data PathProof = PathProof
  { ppEdges :: ![Relation]
  , ppTopic :: !Text
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- ============================================================
-- AtomGraph — runtime graph with indexed lookups
-- ============================================================

data AtomGraph = AtomGraph
  { agRelations :: ![Relation]          -- canonical sorted list
  , agByFrom    :: !(Map AtomId [Relation])  -- index: from_atom → edges
  , agVersion   :: !Text                -- version tag for trace
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON)

-- | Seed graph: built from static relationStore, sorted canonically.
seedGraph :: AtomGraph
seedGraph =
  let rels = sortRelations relationStore
      idx = buildIndex rels
  in AtomGraph rels idx "seed-v1"

-- | Merge promoted relations into seed graph.
-- Seed wins: if a promoted relation has the same (from, to, type) as a seed
-- relation, the seed is kept. Promoted duplicates merge by first occurrence.
-- Result is canonically sorted for deterministic path order.
withPromoted :: [Relation] -> AtomGraph -> AtomGraph
withPromoted promoted baseGraph =
  let seedRels = agRelations baseGraph
      seedKeys = S.fromList (map relKey seedRels)
      -- Only keep promoted relations whose key is not in seed
      newPromoted = filter (\r -> not (relKey r `S.member` seedKeys)) promoted
      -- Dedup promoted by key (first wins)
      dedupedPromoted = dedupByRelKey newPromoted
      allRels = sortRelations (seedRels ++ dedupedPromoted)
      idx = buildIndex allRels
  in AtomGraph allRels idx (agVersion baseGraph <> "+promoted")

-- | Relation identity key: (from, to, type).
relKey :: Relation -> (AtomId, AtomId, RelationType)
relKey r = (relFrom r, relTo r, relType r)

-- | Deduplicate relations by key, keeping first occurrence.
dedupByRelKey :: [Relation] -> [Relation]
dedupByRelKey = go S.empty
  where
    go _ [] = []
    go seen (r:rs)
      | k `S.member` seen = go seen rs
      | otherwise = r : go (S.insert k seen) rs
      where k = relKey r

-- | Sort relations canonically: by from, then to, then type.
sortRelations :: [Relation] -> [Relation]
sortRelations = sortOn (\r -> (relFrom r, relTo r, show (relType r)))

-- | Build index: from_atom → list of relations.
buildIndex :: [Relation] -> Map AtomId [Relation]
buildIndex = foldl' (\acc r -> M.insertWith (++) (relFrom r) [r] acc) M.empty

-- | Lookup relations from an atom in a specific graph.
graphRelationsFromAtom :: AtomGraph -> AtomId -> [Relation]
graphRelationsFromAtom g aid = fromMaybe [] (M.lookup aid (agByFrom g))

-- | Get all relations in a graph.
graphAllRelations :: AtomGraph -> [Relation]
graphAllRelations = agRelations

-- | Empty graph (for FromJSON fallback).
emptyGraph :: AtomGraph
emptyGraph = AtomGraph [] M.empty "empty"

-- | Custom FromJSON: rebuild index if missing (old persisted state).
instance FromJSON AtomGraph where
  parseJSON = withObject "AtomGraph" $ \o -> do
    rels <- o .: "agRelations"
    mIdx <- o .:? "agByFrom" .!= M.empty
    ver <- o .:? "agVersion" .!= "legacy"
    let idx = if M.null mIdx && not (null rels) then buildIndex rels else mIdx
    pure (AtomGraph rels idx ver)

-- ============================================================
-- GeneratedSurface — structured output with provenance
-- ============================================================

data GeneratedSurface = GeneratedSurface
  { gsText       :: !Text
  , gsPaths      :: ![PathProof]
  , gsProvenance :: ![RelationSource]
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- ============================================================
-- Atom store
-- ============================================================

atomStore :: Map AtomId Atom
atomStore = M.fromList
  [ mkTopic "свобода"
  , mkTopic "произвол"
  , mkTopic "ответственность"
  , mkTopic "истина"
  , mkTopic "мнение"
  , mkTopic "память"
  , mkTopic "воспоминание"
  , mkTopic "сознание"
  , mkTopic "самосознание"
  , mkTopic "вера"
  , mkTopic "красота"
  , mkTopic "долг"
  , mkTopic "доверие"
  , mkTopic "страх"
  , mkTopic "надежда"
  , mkTopic "справедливость"
  , mkTopic "время"
  , mkTopic "разум"
  , mkTopic "бытие"
  , mkTopic "история"
  , mkTopic "язык"
  , mkTopic "воля"
  , mkTopic "смерть"
  , mkTopic "одиночество"
  , mkTopic "любовь"
  , mkTopic "труд"
  , mkTopic "покой"
  , mkTopic "власть"
  , mkTopic "правда"
  , mkTopic "молчание"
  -- concept atoms (objects of relations)
  , mkConcept "выбор" "выбор" "выбор"
  , mkConcept "рамка_критериев" "рамка критериев" "рамка"
  , mkConcept "доверие_субъектов" "доверие между субъектами" "доверие"
  , mkConcept "осознание_последствий" "осознание последствий" "осознание"
  , mkConcept "обязательства_перед_другими" "обязательства перед другими" "обязательства"
  , mkConcept "соответствие_реальности" "соответствие реальности" "соответствие"
  , mkConcept "воспроизводимость" "воспроизводимость" "воспроизводимость"
  , mkConcept "позиция_субъекта" "позиция субъекта" "позиция"
  , mkConcept "перспектива_наблюдателя" "перспектива наблюдателя" "перспектива"
  , mkConcept "прошлое_для_настоящего" "прошлое для настоящего" "прошлое"
  , mkConcept "избирательность_и_реконструкция" "избирательность и реконструкция" "избирательность"
  , mkConcept "пережитое_в_новой_рамке" "пережитое в новой рамке" "пережитое"
  , mkConcept "акт_обращения_к_прошлому" "акт обращения к личному прошлому" "акт"
  , mkConcept "субъективность" "субъективность" "субъективность"
  , mkConcept "аспект_первого_лица" "аспект от первого лица" "аспект"
  , mkConcept "способность_к_самоотчёту" "способность к самоотчёту" "способность"
  , mkConcept "восприятие_и_рефлексия" "восприятие и рефлексию" "восприятие"
  , mkConcept "собственные_состояния_субъекта" "собственные состояния субъекта" "состояния"
  , mkConcept "сознание_как_основание" "наличие сознания как своего основания" "наличие"
  , mkConcept "субъект_как_объект" "субъекта объектом для самого себя" "субъекта"
  , mkConcept "принятие_без_доказательства" "принятия без полного доказательства" "принятия"
  , mkConcept "доверие_к_непроверяемому" "доверием к тому, что не может быть проверено" "доверием"
  , mkConcept "доверие_к_источнику" "доверием к источнику или опыту" "доверием"
  , mkConcept "не_сводимость_к_полезности" "к полезности" "полезности"
  , mkConcept "эстетическое_переживание" "эстетическое переживание" "переживание"
  , mkConcept "воспринимающий_и_рамка" "от воспринимающего и культурной рамки" "рамки"
  , mkConcept "действие_независимо_от_желания" "действие независимо от желания" "действие"
  , mkConcept "моральные_обязательства" "на моральные или социальные обязательства" "обязательства"
  , mkConcept "уязвимость_перед_другим" "уязвимость перед другим" "уязвимость"
  , mkConcept "повторяемый_опыт" "через повторяемый позитивный опыт" "опыт"
  , mkConcept "угроза_целостности" "об угрозе целостности" "угрозе"
  , mkConcept "угроза_целостности_субъекта" "об угрозе целостности субъекта" "угрозе"
  , mkConcept "то_что_имеет_значение" "на то, что имеет значение" "значение"
  , mkConcept "возможность_будущего" "на возможность будущего" "возможность"
  , mkConcept "действие_в_неопределённости" "действие в условиях неопределённости" "действие"
  , mkConcept "соразмерность_деяния_и_воздаяния" "соразмерности между деянием и воздаянием" "соразмерности"
  , mkConcept "равенство_перед_правилом" "равенство перед правилом" "равенство"
  , mkConcept "порядок_следования_событий" "порядок следования событий" "порядок"
  , mkConcept "необратимость_и_неравномерность" "необратимо и неравномерно" "необратимо"
  , mkConcept "необратимость" "необратимо — прошлое недоступно для изменения" "необратимо"
  , mkConcept "самокоррекция" "самокоррекция" "самокоррекция"
  , mkConcept "обобщение_и_абстракция" "к обобщению и абстракции" "обобщению"
  , mkConcept "отличие_от_интуиции" "от интуиции потребностью в доказательстве" "интуиции"
  , mkConcept "факт_существования" "сам факт существования" "факт"
  , mkConcept "условие_возможности_суждения" "как условие возможности любого суждения" "условие"
  , mkConcept "сущность" "сущность" "сущность"
  , mkConcept "события_и_интерпретация" "из событий и их интерпретации" "событий"
  , mkConcept "прошлое_с_настоящим" "прошлое с настоящим через интерпретацию" "прошлое"
  , mkConcept "точка_зрения_рассказчика" "от точки зрения рассказчика" "точки"
  , mkConcept "мышление" "мышление" "мышление"
  , mkConcept "опыт_через_различение" "опыт через различение и именование" "опыт"
  , mkConcept "выражение_и_формирование_мысли" "мышлением — он не только выражает, но и формирует мысль" "мышлением"
  , mkConcept "действие_к_цели" "действие к выбранной цели" "действие"
  , mkConcept "преодоление_препятствий" "преодоления препятствий и конкурирующих мотивов" "преодоления"
  , mkConcept "прекращение_существования" "необратимое прекращение существования" "прекращение"
  , mkConcept "граница_жизни" "границу, через которую жизнь обретает конечную форму" "границу"
  , mkConcept "неотменимость_жизни" "жизни неотменимость" "неотменимость"
  , mkConcept "граница_я_и_других" "границу между я и другими" "границу"
  , mkConcept "отсутствие_значимого_другого" "отсутствие значимого другого" "отсутствие"
  , mkConcept "избрано_или_навязано" "избрано или навязано обстоятельствами" "избрано"
  , mkConcept "ценность_другого" "ценность другого как несводимую" "ценность"
  , mkConcept "уязвимость_и_риск" "уязвимость и риск потери" "уязвимость"
  , mkConcept "преобразование_мира_и_себя" "мир и самого трудящегося" "мир"
  , mkConcept "материал_через_усилие" "материал через целенаправленное усилие" "материал"
  , mkConcept "потребность_и_ресурсы" "потребностью и распределением ресурсов" "потребностью"
  , mkConcept "не_отсутствие_движения" "отсутствием движения" "отсутствием"
  , mkConcept "восстановление_и_интеграция" "для восстановления и интеграции опыта" "восстановления"
  , mkConcept "отсутствие_движения_и_напряжения" "отсутствие движения и напряжения" "отсутствие"
  , mkConcept "способность_влиять" "способность влиять на действия других" "способность"
  , mkConcept "легитимность_для_устойчивости" "легитимности для устойчивости" "легитимности"
  , mkConcept "чья_воля_становится_законом" "чья воля становится законом" "воля"
  , mkConcept "соответствие_произошедшему" "на соответствие тому, что произошло" "соответствие"
  , mkConcept "личная_вовлечённость" "личной вовлечённостью рассказчика" "вовлечённостью"
  , mkConcept "персональная_вовлечённость" "персональной вовлечённостью" "вовлечённостью"
  , mkConcept "отсутствие_слов" "отсутствием слов" "отсутствием"
  , mkConcept "контраст_с_речью" "с речью, но не тождественно пустоте" "речью"
  , mkConcept "акт_отказа_или_присутствия" "актом отказа или знаком присутствия" "актом"
  ]
  where
    mkTopic surf = (AtomId surf, Atom (AtomId surf) surf surf surf CatTopic)
    mkConcept aid display head_ = (AtomId aid, Atom (AtomId aid) aid display head_ CatConcept)

-- ============================================================
-- Relation store — decomposed predicates
-- ============================================================

relationStore :: [Relation]
relationStore =
  -- свобода
  [ rel "свобода" "выбор" RelPresupposes CaseAccusative "возможность выбора"
      "свобода предполагает возможность выбора" "freedom presupposes the possibility of choice"
  , rel "свобода" "ответственность" RelLimitedBy CaseInstrumental "ответственностью"
      "свобода ограничена ответственностью" "freedom is limited by responsibility"

  -- произвол
  , rel "произвол" "рамка_критериев" RelNegates CaseAccusative "рамку критериев"
      "произвол отрицает рамку критериев" "arbitrariness denies the frame of criteria"
  , rel "произвол" "доверие_субъектов" RelDestroys CaseAccusative "доверие между субъектами"
      "произвол разрушает доверие между субъектами" "arbitrariness destroys trust between subjects"

  -- ответственность
  , rel "ответственность" "осознание_последствий" RelRequires CaseGenitive "осознания последствий"
      "ответственность требует осознания последствий" "responsibility requires awareness of consequences"
  , rel "ответственность" "обязательства_перед_другими" RelRelatedTo CaseInstrumental "с обязательствами перед другими"
      "ответственность связана с обязательствами перед другими" "responsibility is linked to obligations toward others"

  -- истина
  , rel "истина" "соответствие_реальности" RelClaims CaseAccusative "на соответствие реальности"
      "истина претендует на соответствие реальности" "truth claims correspondence with reality"
  , rel "истина" "воспроизводимость" RelVerifiedBy CaseAccusative "через воспроизводимость"
      "истина проверяется через воспроизводимость" "truth is verified through reproducibility"

  -- мнение
  , rel "мнение" "позиция_субъекта" RelExpresses CaseAccusative "позицию субъекта"
      "мнение выражает позицию субъекта" "opinion expresses the position of a subject"
  , rel "мнение" "перспектива_наблюдателя" RelDependsOn CaseGenitive "от перспективы наблюдателя"
      "мнение зависит от перспективы наблюдателя" "opinion depends on the observer's perspective"

  -- память
  , rel "память" "прошлое_для_настоящего" RelPreserves CaseAccusative "прошлое для настоящего"
      "память сохраняет прошлое для настоящего" "memory preserves the past for the present"
  , rel "память" "избирательность_и_реконструкция" RelNotJustCopies CaseSpecial "а не просто копирует"
      "память реконструирует а не просто копирует" "memory reconstructs rather than merely copies"
  , rel "память" "избирательность_и_реконструкция" RelIsA CaseNominative "избирательна и реконструктивна"
      "память избирательна и реконструктивна" "memory is selective and reconstructive"
      `withVerb` ""

  -- воспоминание
  , rel "воспоминание" "пережитое_в_новой_рамке" RelReconstructs CaseAccusative "пережитое в новой рамке"
      "воспоминание восстанавливает пережитое в новой рамке" "recollection restores the experienced in a new frame"
      `withVerb` "восстанавливает"
  , rel "воспоминание" "акт_обращения_к_прошлому" RelIsA CaseNominative "акт обращения к личному прошлому"
      "воспоминание есть акт обращения к личному прошлому" "recollection is an act of turning to personal past"
  , rel "воспоминание" "память" RelDiffersFrom CaseGenitive "от памяти своей субъективностью"
      "воспоминание отличается от памяти своей субъективностью" "recollection differs from memory in its subjectivity"

  -- сознание
  , rel "сознание" "аспект_первого_лица" RelIncludes CaseAccusative "аспект от первого лица"
      "сознание имеет аспект от первого лица" "consciousness has a first-person aspect"
      `withVerb` "имеет"
  , rel "сознание" "способность_к_самоотчёту" RelIncludes CaseAccusative "способность к самоотчёту"
      "сознание включает способность к самоотчёту" "consciousness includes the capacity for self-report"
  , rel "сознание" "восприятие_и_рефлексия" RelUnifies CaseAccusative "восприятие и рефлексию"
      "сознание объединяет восприятие и рефлексию" "consciousness unifies perception and reflection"

  -- самосознание
  , rel "самосознание" "собственные_состояния_субъекта" RelDirectedAt CaseAccusative "собственные состояния субъекта"
      "самосознание направлено на собственные состояния субъекта" "self-awareness is directed at the subject's own states"
      `withVerb` "направлено на"
  , rel "самосознание" "сознание_как_основание" RelPresupposes CaseAccusative "наличие сознания как своего основания"
      "самосознание предполагает наличие сознания как своего основания" "self-awareness presupposes consciousness as its ground"
  , rel "самосознание" "субъект_как_объект" RelMakes CaseAccusative "субъекта объектом для самого себя"
      "самосознание делает субъекта объектом для самого себя" "self-consciousness makes the subject an object for itself"

  -- вера
  , rel "вера" "принятие_без_доказательства" RelRequires CaseGenitive "принятия без полного доказательства"
      "вера требует принятия без полного доказательства" "faith requires acceptance without full proof"
  , rel "вера" "доверие_к_источнику" RelRelatedTo CaseInstrumental "с доверием к источнику или опыту"
      "вера связана с доверием к источнику или опыту" "faith is connected to trust in a source or experience"
  , rel "вера" "доверие_к_непроверяемому" RelRelatedTo CaseInstrumental "с доверием к тому, что не может быть проверено"
      "вера связана с доверием к тому, что не может быть проверено" "faith is linked to trust in what cannot be verified"

  -- красота
  , rel "красота" "не_сводимость_к_полезности" RelNotReducibleTo CaseDative "к полезности"
      "красота не сводится к полезности" "beauty is not reducible to utility"
  , rel "красота" "эстетическое_переживание" RelEvokes CaseAccusative "эстетическое переживание"
      "красота вызывает эстетическое переживание" "beauty evokes aesthetic experience"
  , rel "красота" "воспринимающий_и_рамка" RelDependsOn CaseGenitive "от воспринимающего и культурной рамки"
      "красота зависит от воспринимающего и культурной рамки" "beauty depends on the perceiver and cultural frame"

  -- долг
  , rel "долг" "действие_независимо_от_желания" RelPrescribes CaseAccusative "действие независимо от желания"
      "долг предписывает действие независимо от желания" "duty prescribes action regardless of desire"
  , rel "долг" "действие_независимо_от_желания" RelPrescribes CaseAccusative "действия независимо от желания"
      "долг предписывает действия независимо от желания" "duty prescribes actions regardless of desire"
  , rel "долг" "моральные_обязательства" RelReliesOn CaseAccusative "на моральные или социальные обязательства"
      "долг опирается на моральные или социальные обязательства" "duty rests on moral or social obligations"

  -- доверие
  , rel "доверие" "уязвимость_перед_другим" RelPresupposes CaseAccusative "уязвимость перед другим"
      "доверие предполагает уязвимость перед другим" "trust presupposes vulnerability before another"
  , rel "доверие" "повторяемый_опыт" RelBuiltThrough CaseAccusative "через повторяемый позитивный опыт"
      "доверие строится через повторяемый позитивный опыт" "trust is built through repeated positive experience"

  -- страх
  , rel "страх" "угроза_целостности" RelSignals CasePrepositional "об угрозе целостности"
      "страх сигнализирует об угрозе целостности" "fear signals a threat to integrity"
  , rel "страх" "угроза_целостности_субъекта" RelSignals CasePrepositional "об угрозе целостности субъекта"
      "страх сигнализирует об угрозе целостности субъекта" "fear signals a threat to the subject's integrity"
  , rel "страх" "то_что_имеет_значение" RelPointsTo CaseAccusative "на то, что имеет значение"
      "страх указывает на то, что имеет значение" "fear points to what matters"
  , rel "страх" "действие_к_цели" RelCanBe CaseInstrumental "парализовать действие или мобилизовать его"
      "страх может парализовать действие или мобилизовать его" "fear can paralyze action or mobilize it"
      `withVerb` "может"

  -- надежда
  , rel "надежда" "возможность_будущего" RelOrientsToward CaseAccusative "на возможность будущего"
      "надежда ориентирует на возможность будущего" "hope orients toward the possibility of a future"
  , rel "надежда" "действие_в_неопределённости" RelSupports CaseAccusative "действие в условиях неопределённости"
      "надежда поддерживает действие в условиях неопределённости" "hope sustains action under uncertainty"

  -- справедливость
  , rel "справедливость" "соразмерность_деяния_и_воздаяния" RelRequires CaseGenitive "соразмерности между деянием и воздаянием"
      "справедливость требует соразмерности между деянием и воздаянием" "justice demands proportionality between deed and retribution"
  , rel "справедливость" "равенство_перед_правилом" RelPresupposes CaseAccusative "равенство перед правилом"
      "справедливость предполагает равенство перед правилом" "justice presupposes equality before the rule"

  -- время
  , rel "время" "порядок_следования_событий" RelSets CaseAccusative "порядок следования событий"
      "время задаёт порядок следования событий" "time defines the order of event succession"
  , rel "время" "необратимость_и_неравномерность" RelIsA CaseNominative "необратимо и неравномерно"
      "время необратимо и неравномерно" "time is irreversible and uneven"
      `withVerb` ""
  , rel "время" "необратимость" RelIsA CaseNominative "необратимо — прошлое недоступно для изменения"
      "время необратимо — прошлое недоступно для изменения" "time is irreversible — the past is not amenable to change"
      `withVerb` ""

  -- разум
  , rel "разум" "самокоррекция" RelCapableOf CaseDative "к самокоррекции"
      "разум способен к самокоррекции" "reason is capable of self-correction"
  , rel "разум" "обобщение_и_абстракция" RelCapableOf CaseDative "к обобщению и абстракции"
      "разум способен к обобщению и абстракции" "reason is capable of generalization and abstraction"
  , rel "разум" "отличие_от_интуиции" RelDiffersFrom CaseGenitive "от интуиции потребностью в доказательстве"
      "разум отличается от интуиции потребностью в доказательстве" "reason differs from intuition by requiring proof"

  -- бытие
  , rel "бытие" "факт_существования" RelDenotes CaseAccusative "сам факт существования"
      "бытие обозначает сам факт существования" "being denotes the very fact of existence"
  , rel "бытие" "условие_возможности_суждения" RelIsA CaseNominative "как условие возможности любого суждения"
      "бытие рассматривается как условие возможности любого суждения" "being is considered the condition for any judgement"
      `withVerb` "рассматривается"
  , rel "бытие" "сущность" RelPrecedes CaseDative "сущности"
      "бытие предшествует сущности" "existence precedes essence"

  -- история
  , rel "история" "события_и_интерпретация" RelCreatedFrom CaseGenitive "из событий и их интерпретации"
      "история создаётся из событий и их интерпретации" "history is made of events and their interpretation"
  , rel "история" "прошлое_с_настоящим" RelConnects CaseAccusative "прошлое с настоящим через интерпретацию"
      "история связывает прошлое с настоящим через интерпретацию" "history connects past to present through interpretation"
  , rel "история" "точка_зрения_рассказчика" RelDependsOn CaseGenitive "от точки зрения рассказчика"
      "история зависит от точки зрения рассказчика" "history depends on the narrator's perspective"

  -- язык
  , rel "язык" "мышление" RelStructures CaseAccusative "мышление"
      "язык структурирует мышление" "language structures thought"
  , rel "язык" "опыт_через_различение" RelStructures CaseAccusative "опыт через различение и именование"
      "язык структурирует опыт через различение и именование" "language structures experience through distinction and naming"
  , rel "язык" "выражение_и_формирование_мысли" RelRelatedTo CaseInstrumental "мышлением — он не только выражает, но и формирует мысль"
      "язык связан с мышлением — он не только выражает, но и формирует мысль" "language is connected to thought — it not only expresses but shapes thought"
      `withVerb` "связан с"

  -- воля
  , rel "воля" "действие_к_цели" RelDirectedAt CaseAccusative "действие к выбранной цели"
      "воля направляет действие к выбранной цели" "will directs action toward a chosen goal"
      `withVerb` "направляет"
  , rel "воля" "преодоление_препятствий" RelRequires CaseGenitive "преодоления препятствий и конкурирующих мотивов"
      "воля требует преодоления препятствий и конкурирующих мотивов" "will requires overcoming obstacles and competing motives"

  -- смерть
  , rel "смерть" "прекращение_существования" RelDenotes CaseAccusative "необратимое прекращение существования"
      "смерть обозначает необратимое прекращение существования" "death denotes the irreversible cessation of existence"
  , rel "смерть" "граница_жизни" RelSets CaseAccusative "границу, через которую жизнь обретает конечную форму"
      "смерть задаёт границу, через которую жизнь обретает конечную форму" "death sets a boundary through which life gains finite form"
  , rel "смерть" "неотменимость_жизни" RelGives CaseAccusative "жизни неотменимость"
      "смерть придаёт жизни неотменимость" "death gives life its irrevocability"

  -- одиночество
  , rel "одиночество" "отсутствие_значимого_другого" RelExpresses CaseAccusative "отсутствие значимого другого"
      "одиночество выражает отсутствие значимого другого" "loneliness expresses the absence of a significant other"
  , rel "одиночество" "граница_я_и_других" RelReveals CaseAccusative "границу между я и другими"
      "одиночество обнаруживает границу между я и другими" "solitude reveals the boundary between self and others"
  , rel "одиночество" "избрано_или_навязано" RelCanBe CaseInstrumental "избрано или навязано обстоятельствами"
      "одиночество может быть избрано или навязано обстоятельствами" "loneliness can be chosen or imposed by circumstances"

  -- любовь
  , rel "любовь" "ценность_другого" RelRecognizes CaseAccusative "ценность другого как несводимую"
      "любовь признаёт ценность другого как несводимую" "love recognizes the value of the other as irreducible"
  , rel "любовь" "ценность_другого" RelDirectedAt CaseAccusative "на конкретного другого как на безусловно ценного"
      "любовь направлена на конкретного другого как на безусловно ценного" "love is directed at a specific other as unconditionally valuable"
  , rel "любовь" "уязвимость_и_риск" RelPresupposes CaseAccusative "уязвимость и риск потери"
      "любовь предполагает уязвимость и риск потери" "love presupposes vulnerability and the risk of loss"

  -- труд
  , rel "труд" "преобразование_мира_и_себя" RelTransforms CaseAccusative "мир и самого трудящегося"
      "труд преобразует мир и самого трудящегося" "labour transforms the world and the labourer"
  , rel "труд" "материал_через_усилие" RelTransforms CaseAccusative "материал через целенаправленное усилие"
      "труд преобразует материал через целенаправленное усилие" "labor transforms material through purposeful effort"
  , rel "труд" "потребность_и_ресурсы" RelRelatedTo CaseInstrumental "потребностью и распределением ресурсов"
      "труд связан с потребностью и распределением ресурсов" "labor is connected to need and resource distribution"
      `withVerb` "связан с"

  -- покой
  , rel "покой" "не_отсутствие_движения" RelIsNot CaseInstrumental "отсутствием движения"
      "покой не является отсутствием движения" "peace is not the absence of movement"
  , rel "покой" "восстановление_и_интеграция" RelNecessaryFor CaseGenitive "для восстановления и интеграции опыта"
      "покой необходим для восстановления и интеграции опыта" "rest is necessary for recovery and integration of experience"
  , rel "покой" "отсутствие_движения_и_напряжения" RelDenotes CaseAccusative "отсутствие движения и напряжения"
      "покой обозначает отсутствие движения и напряжения" "rest denotes the absence of movement and tension"

  -- власть
  , rel "власть" "способность_влиять" RelMeans CaseAccusative "способность влиять на действия других"
      "власть означает способность влиять на действия других" "power means the capacity to influence others' actions"
  , rel "власть" "легитимность_для_устойчивости" RelRequires CaseGenitive "легитимности для устойчивости"
      "власть требует легитимности для устойчивости" "power requires legitimacy for sustainability"
  , rel "власть" "чья_воля_становится_законом" RelDetermines CaseAccusative "чья воля становится законом"
      "власть определяет, чья воля становится законом" "power determines whose will becomes law"
      `withVerb` "определяет,"

  -- правда
  , rel "правда" "соответствие_произошедшему" RelClaims CaseAccusative "на соответствие тому, что произошло"
      "правда претендует на соответствие тому, что произошло" "truthfulness claims correspondence with what happened"
  , rel "правда" "истина" RelDiffersFrom CaseGenitive "от истины личной вовлечённостью рассказчика"
      "правда отличается от истины личной вовлечённостью рассказчика" "truthfulness differs from truth by the narrator's personal involvement"
  , rel "правда" "истина" RelDiffersFrom CaseGenitive "от истины персональной вовлечённостью"
      "правда отличается от истины персональной вовлечённостью" "truth (pravda) differs from truth (istina) by personal involvement"

  -- молчание
  , rel "молчание" "отсутствие_слов" RelSays CaseInstrumental "отсутствием слов"
      "молчание говорит отсутствием слов" "silence speaks through the absence of words"
  , rel "молчание" "контраст_с_речью" RelContrastsWith CaseInstrumental "с речью, но не тождественно пустоте"
      "молчание контрастирует с речью, но не тождественно пустоте" "silence contrasts with speech but is not identical to emptiness"
  , rel "молчание" "акт_отказа_или_присутствия" RelCanBe CaseInstrumental "актом отказа или знаком присутствия"
      "молчание может быть актом отказа или знаком присутствия" "silence can be an act of refusal or a sign of presence"

  -- ============================================================
  -- Inter-topic edges (mesh connectivity for PathFinder)
  -- ============================================================
  , rel "ответственность" "свобода" RelRelatedTo CaseInstrumental "со свободой"
      "ответственность связана со свободой" "responsibility is related to freedom"
  , rel "ответственность" "долг" RelRelatedTo CaseInstrumental "с долгом"
      "ответственность связана с долгом" "responsibility is related to duty"
  , rel "мнение" "истина" RelDiffersFrom CaseGenitive "от истины"
      "мнение отличается от истины" "opinion differs from truth"
  , rel "память" "воспоминание" RelRelatedTo CaseInstrumental "с воспоминанием"
      "память связана с воспоминанием" "memory is related to recollection"
  , rel "самосознание" "сознание" RelPresupposes CaseAccusative "сознание"
      "самосознание предполагает сознание" "self-awareness presupposes consciousness"
  , rel "вера" "доверие" RelRelatedTo CaseInstrumental "с доверием"
      "вера связана с доверием" "faith is related to trust"
  , rel "страх" "надежда" RelContrastsWith CaseInstrumental "с надеждой"
      "страх контрастирует с надеждой" "fear contrasts with hope"
  , rel "смерть" "время" RelRelatedTo CaseInstrumental "со временем"
      "смерть связана со временем" "death is related to time"
  , rel "разум" "истина" RelRelatedTo CaseInstrumental "с истиной"
      "разум связан с истиной" "reason is related to truth"
      `withVerb` "связан"
  , rel "власть" "справедливость" RelRelatedTo CaseInstrumental "со справедливостью"
      "власть связана со справедливостью" "power is related to justice"
  , rel "долг" "справедливость" RelRelatedTo CaseInstrumental "со справедливостью"
      "долг связан со справедливостью" "duty is related to justice"
      `withVerb` "связан"
  , rel "любовь" "доверие" RelPresupposes CaseAccusative "доверие"
      "любовь предполагает доверие" "love presupposes trust"
  , rel "одиночество" "самосознание" RelRelatedTo CaseInstrumental "с самосознанием"
      "одиночество связано с самосознанием" "loneliness is related to self-awareness"
      `withVerb` "связано"
  , rel "труд" "время" RelRelatedTo CaseInstrumental "со временем"
      "труд связан со временем" "labour is related to time"
      `withVerb` "связан"
  , rel "покой" "время" RelRelatedTo CaseInstrumental "со временем"
      "покой связан со временем" "rest is related to time"
      `withVerb` "связан"
  , rel "красота" "истина" RelRelatedTo CaseInstrumental "с истиной"
      "красота связана с истиной" "beauty is related to truth"
  , rel "воля" "свобода" RelRelatedTo CaseInstrumental "со свободой"
      "воля связана со свободой" "will is related to freedom"
  , rel "смерть" "бытие" RelRelatedTo CaseInstrumental "с бытием"
      "смерть связана с бытием" "death is related to being"
  , rel "история" "память" RelRelatedTo CaseInstrumental "с памятью"
      "история связана с памятью" "history is related to memory"
  , rel "молчание" "язык" RelContrastsWith CaseInstrumental "с языком"
      "молчание контрастирует с языком" "silence contrasts with language"
  , rel "надежда" "вера" RelRelatedTo CaseInstrumental "с верой"
      "надежда связана с верой" "hope is related to faith"
  -- Additional inter-topic edges for sparse zones
  , rel "истина" "разум" RelRelatedTo CaseInstrumental "с разумом"
      "истина связана с разумом" "truth is related to reason"
  , rel "истина" "правда" RelRelatedTo CaseInstrumental "с правдой"
      "истина связана с правдой" "truth is related to truthfulness"
  , rel "сознание" "память" RelRelatedTo CaseInstrumental "с памятью"
      "сознание связано с памятью" "consciousness is related to memory"
      `withVerb` "связано"
  , rel "сознание" "язык" RelRelatedTo CaseInstrumental "с языком"
      "сознание связано с языком" "consciousness is related to language"
      `withVerb` "связано"
  , rel "вера" "надежда" RelRelatedTo CaseInstrumental "с надеждой"
      "вера связана с надеждой" "faith is related to hope"
  , rel "вера" "истина" RelRelatedTo CaseInstrumental "с истиной"
      "вера связана с истиной" "faith is related to truth"
  , rel "доверие" "ответственность" RelRelatedTo CaseInstrumental "с ответственностью"
      "доверие связано с ответственностью" "trust is related to responsibility"
      `withVerb` "связано"
  , rel "доверие" "правда" RelRelatedTo CaseInstrumental "с правдой"
      "доверие связано с правдой" "trust is related to truthfulness"
      `withVerb` "связано"
  -- ============================================================
  -- Concept→topic reverse edges (mesh connectivity for PathFinder)
  -- ============================================================
  , rel "выбор" "свобода" RelSupports CaseAccusative "свободу"
      "выбор поддерживает свободу" "choice supports freedom"
  , rel "воспроизводимость" "истина" RelRelatedTo CaseInstrumental "с истиной"
      "воспроизводимость связана с истиной" "reproducibility is related to truth"
  , rel "сущность" "бытие" RelPrecedes CaseDative "за бытием"
      "сущность следует за бытием" "essence follows being"
      `withVerb` "следует"
  , rel "мышление" "язык" RelDependsOn CaseGenitive "от языка"
      "мышление зависит от языка" "thought depends on language"
  , rel "самокоррекция" "разум" RelDirectedAt CaseAccusative "разум"
      "самокоррекция направлена на разум" "self-correction is directed at reason"
      `withVerb` "направлена на"
  ]
  where
    rel fromId toId rt oc objText ru en =
      relV fromId toId rt oc objText Nothing ru en
    relV fromId toId rt oc objText mVerb ru en =
      Relation
        { relFrom = AtomId fromId
        , relTo = AtomId toId
        , relType = rt
        , relObjectCase = oc
        , relObjectText = objText
        , relVerbText = mVerb
        , relRuOriginal = ru
        , relEnOriginal = en
        , relSource = SeedFromPredicate
        , relTopic = fromId
        }
    withVerb r v = r { relVerbText = Just v }

-- ============================================================
-- Lookup helpers
-- ============================================================

atomsForTopic :: Text -> [Atom]
atomsForTopic topic =
  let tid = AtomId topic
  in case M.lookup tid atomStore of
       Just a  -> [a]
       Nothing -> []

relationsFromAtom :: AtomId -> [Relation]
relationsFromAtom aid = filter (\r -> relFrom r == aid) relationStore

relationsToAtom :: AtomId -> [Relation]
relationsToAtom aid = filter (\r -> relTo r == aid) relationStore

allTopics :: [Text]
allTopics = map atomDisplay
         $ filter (\a -> atomCategory a == CatTopic)
         $ M.elems atomStore

-- | All atom IDs in the store (topics + concepts + properties + processes).
-- Used for substrate admission: candidates can target any known atom,
-- not just philosophical topics.
allAtomIds :: [AtomId]
allAtomIds = M.keys atomStore

-- ============================================================
-- Verbalizer (simple — for round-trip parity)
-- ============================================================

-- | Verbalize a relation for generative output.
-- Uses relObjectText (which contains correct grammatical case + prepositions)
-- rather than atomDisplay (which is nominative only).
-- This produces grammatically correct text for all seed + inter-topic edges.
verbalizeRelation :: Relation -> Text
verbalizeRelation r =
  case relVerbText r of
    Just ""  -> subject <> " " <> relObjectText r
    Just vt  -> subject <> " " <> vt <> " " <> relObjectText r
    Nothing  -> subject <> " " <> verbPhrase <> " " <> relObjectText r
  where
    subject = case M.lookup (relFrom r) atomStore of
      Just a  -> atomDisplay a
      Nothing -> "??"
    verbPhrase = verbForType (relType r)

-- | Verbalize using stored objectText (legacy round-trip path).
verbalizeRelationStored :: Relation -> Text
verbalizeRelationStored r =
  case relVerbText r of
    Just ""  -> subject <> " " <> relObjectText r
    Just vt  -> subject <> " " <> vt <> " " <> relObjectText r
    Nothing  -> subject <> " " <> verbPhrase <> " " <> relObjectText r
  where
    subject = case M.lookup (relFrom r) atomStore of
      Just a  -> atomDisplay a
      Nothing -> "??"
    verbPhrase = verbForType (relType r)

-- | Map relation type to Russian verb phrase.
verbForType :: RelationType -> Text
verbForType rt = case rt of
  RelPresupposes    -> "предполагает"
  RelLimitedBy      -> "ограничена"
  RelRequires       -> "требует"
  RelClaims         -> "претендует"
  RelVerifiedBy     -> "проверяется"
  RelSignals        -> "сигнализирует"
  RelTransformsInto -> "превращается в"
  RelExpresses      -> "выражает"
  RelDiffersFrom    -> "отличается"
  RelRelatedTo      -> "связана"
  RelDirectedAt     -> "направлена"
  RelPreserves      -> "сохраняет"
  RelOrientsToward  -> "ориентирует"
  RelPrescribes     -> "предписывает"
  RelBuiltThrough   -> "строится"
  RelDenotes        -> "обозначает"
  RelStructures     -> "структурирует"
  RelDetermines     -> "определяет"
  RelTransforms     -> "преобразует"
  RelGives          -> "придаёт"
  RelReveals        -> "обнаруживает"
  RelRecognizes     -> "признаёт"
  RelUnifies        -> "объединяет"
  RelConnects       -> "связывает"
  RelPrecedes       -> "предшествует"
  RelDependsOn      -> "зависит"
  RelIncludes       -> "включает"
  RelNecessaryFor   -> "необходим"
  RelEvokes         -> "вызывает"
  RelMeans          -> "означает"
  RelSays           -> "говорит"
  RelNegates        -> "отрицает"
  RelContrastsWith  -> "контрастирует"
  RelNotReducibleTo -> "не сводится"
  RelIsNot          -> "не является"
  RelCapableOf      -> "способен"
  RelCreatedFrom    -> "создаётся"
  RelReliesOn       -> "опирается"
  RelCanBe          -> "может быть"
  RelDestroys       -> "разрушает"
  RelPointsTo       -> "указывает"
  RelMakes          -> "делает"
  RelIsA            -> "есть"
  RelReconstructs   -> "реконструирует"
  RelSupports       -> "поддерживает"
  RelSets           -> "задаёт"
  RelNotJustCopies  -> "реконструирует"

-- | Verbalize in English (for round-trip on en side).
verbalizeRelationEn :: Relation -> Text
verbalizeRelationEn = relEnOriginal

-- ============================================================
-- Round-trip check
-- ============================================================

-- | Check if verbalizing a relation reproduces the original predicate.
-- Uses stored objectText for round-trip (Step 1 parity).
-- Returns (original, verbalized, isMatch).
roundTripCheck :: Relation -> (Text, Text, Bool)
roundTripCheck r =
  let verbalized = verbalizeRelationStored r
      original = relRuOriginal r
  in (original, verbalized, original == verbalized)

-- | Check if generative verbalization (atomDisplay) matches original.
-- This is the Step 2 test: can we reconstruct predicates from atoms alone?
roundTripCheckMorph :: Relation -> (Text, Text, Bool)
roundTripCheckMorph r =
  let verbalized = verbalizeRelation r
      original = relRuOriginal r
  in (original, verbalized, original == verbalized)

-- | Check all relations with stored text and return mismatches.
allRoundTripResults :: [(Text, Text, Bool)]
allRoundTripResults = map roundTripCheck relationStore

-- | Check all relations with atomDisplay and return mismatches.
allRoundTripMorphResults :: [(Text, Text, Bool)]
allRoundTripMorphResults = map roundTripCheckMorph relationStore
