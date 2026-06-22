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
  | CatDiscovered  -- auto-discovered from brain_kb (evidence, boundary, ...)
  | CatDomain      -- cross-domain bridge concept (закон, нейрон, искусство, ...)
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
  , gsDepthScore :: !Double
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
  -- NEW TOPICS
  , mkTopic "смысл"
  , mkTopic "граница"
  , mkTopic "цифра"
  , mkTopic "идентичность"
  , mkTopic "ремонт"
  -- NEW CONCEPTS: смысл
  , mkConcept "целостность_жизни" "целостность жизни" "целостность"
  , mkConcept "соотнесённость_с_целым" "соотнесённость с целым" "соотнесённость"
  , mkConcept "направление_вектора_жизни" "направление вектора жизни" "направление"
  , mkConcept "почему_а_не_зачем" "почему а не зачем" "почему"
  , mkConcept "переживание_значимости" "переживание значимости" "значимость"
  -- NEW CONCEPTS: граница
  , mkConcept "различение_внутри_и_снаружи" "различение внутри и снаружи" "различение"
  , mkConcept "условие_формы" "условие формы" "форма"
  , mkConcept "предел_действия" "предел действия" "предел"
  , mkConcept "контактная_поверхность" "контактная поверхность" "поверхность"
  , mkConcept "защита_и_ограничение" "защита и ограничение" "защита"
  -- NEW CONCEPTS: цифра
  , mkConcept "дискретность_и_точность" "дискретность и точность" "дискретность"
  , mkConcept "формализация_опыта" "формализация опыта" "формализация"
  , mkConcept "утрата_контекста" "утрата контекста" "утрата"
  , mkConcept "сжимает_мир_до_значения" "сжимает мир до значения" "сжатие"
  , mkConcept "маскировка_качества_количеством" "маскировка качества количеством" "маскировка"
  -- NEW CONCEPTS: идентичность
  , mkConcept "преемственность_я" "преемственность я" "преемственность"
  , mkConcept "ответ_на_вопрос_кто_я" "ответ на вопрос кто я" "ответ"
  , mkConcept "нарратив_о_себе" "нарратив о себе" "нарратив"
  , mkConcept "совпадение_с_собой" "совпадение с собой" "совпадение"
  , mkConcept "разрыв_и_восстановление" "разрыв и восстановление" "разрыв"
  -- NEW CONCEPTS: ремонт
  , mkConcept "восстановление_функции" "восстановление функции" "восстановление"
  , mkConcept "диагностика_поломки" "диагностика поломки" "диагностика"
  , mkConcept "различение_починить_и_заменить" "различение починить и заменить" "различение"
  , mkConcept "возвращение_к_работоспособности" "возвращение к работоспособности" "возвращение"
  , mkConcept "усилие_против_энтропии" "усилие против энтропии" "усилие"
  -- NEW CONCEPTS: свобода
  , mkConcept "осознанность_выбора" "осознанность выбора" "осознанность"
  , mkConcept "автономия_суждения" "автономия суждения" "автономия"
  , mkConcept "самоопределение" "самоопределение" "самоопределение"
  , mkConcept "отсутствие_принуждения" "отсутствие принуждения" "принуждение"
  , mkConcept "пространство_возможностей" "пространство возможностей" "пространство"
  -- NEW CONCEPTS: истина
  , mkConcept "объективность" "объективность" "объективность"
  , mkConcept "доказательство" "доказательство" "доказательство"
  , mkConcept "когерентность" "когерентность" "когерентность"
  , mkConcept "открытость_проверке" "открытость проверке" "открытость"
  , mkConcept "независимость_от_наблюдателя" "независимость от наблюдателя" "независимость"
  -- NEW CONCEPTS: память
  , mkConcept "идентичность_через_время" "идентичность через время" "идентичность"
  , mkConcept "след_прошлого" "след прошлого" "след"
  , mkConcept "забывание_как_условие" "забывание как условие" "забывание"
  , mkConcept "узнавание" "узнавание" "узнавание"
  , mkConcept "привычка_и_рутина" "привычка и рутина" "привычка"
  -- NEW CONCEPTS: сознание
  , mkConcept "интенциональность" "интенциональность" "интенциональность"
  , mkConcept "качественность_опыта" "качественность опыта" "качественность"
  , mkConcept "единство_поля_опыта" "единство поля опыта" "единство"
  , mkConcept "присутствие" "присутствие" "присутствие"
  , mkConcept "поток_переживаний" "поток переживаний" "поток"
  -- NEW CONCEPTS: вера
  , mkConcept "акт_доверия" "акт доверия" "акт"
  , mkConcept "обоснованность_не_доказательством" "обоснованность не доказательством" "обоснованность"
  , mkConcept "готовность_к_риску" "готовность к риску" "готовность"
  , mkConcept "верность" "верность" "верность"
  , mkConcept "прыжок_за_горизонт" "прыжок за горизонт" "прыжок"
  -- NEW CONCEPTS: красота
  , mkConcept "гармония_формы" "гармония формы" "гармония"
  , mkConcept "соразмерность_частей" "соразмерность частей" "соразмерность"
  , mkConcept "праздность_созерцания" "праздность созерцания" "созерцание"
  , mkConcept "превосходство_над_полезным" "превосходство над полезным" "превосходство"
  , mkConcept "мгновение_и_вечность" "мгновение и вечность" "мгновение"
  -- NEW CONCEPTS: долг
  , mkConcept "долженствование" "долженствование" "долженствование"
  , mkConcept "приоритет_над_желанием" "приоритет над желанием" "приоритет"
  , mkConcept "внутренний_закон" "внутренний закон" "закон"
  , mkConcept "совесть_как_свидетель" "совесть как свидетель" "совесть"
  , mkConcept "исполнение_обещания" "исполнение обещания" "исполнение"
  -- NEW CONCEPTS: доверие
  , mkConcept "риск_уязвимости" "риск уязвимости" "риск"
  , mkConcept "опора_на_другого" "опора на другого" "опора"
  , mkConcept "проверка_опытом" "проверка опытом" "проверка"
  , mkConcept "прозрачность_намерений" "прозрачность намерений" "прозрачность"
  , mkConcept "разрыв_и_восстановление_доверия" "разрыв и восстановление доверия" "восстановление"
  -- NEW CONCEPTS: страх
  , mkConcept "ожидание_угрозы" "ожидание угрозы" "ожидание"
  , mkConcept "сигнал_опасности" "сигнал опасности" "сигнал"
  , mkConcept "паралич_или_действие" "паралич или действие" "паралич"
  , mkConcept "перед_неизвестным" "перед неизвестным" "неизвестность"
  , mkConcept "защитная_реакция" "защитная реакция" "защита"
  -- NEW CONCEPTS: надежда
  , mkConcept "ориентация_на_будущее" "ориентация на будущее" "ориентация"
  , mkConcept "наперекор_очевидности" "наперекор очевидности" "наперекор"
  , mkConcept "утешение_и_мотив" "утешение и мотив" "утешение"
  , mkConcept "обещание_себе" "обещание себе" "обещание"
  , mkConcept "пустота_или_вектор" "пустота или вектор" "вектор"
  -- NEW CONCEPTS: справедливость
  , mkConcept "мера_и_соразмерность" "мера и соразмерность" "мера"
  , mkConcept "беспристрастность" "беспристрастность" "беспристрастность"
  , mkConcept "воздаяние_по_заслугам" "воздаяние по заслугам" "воздаяние"
  , mkConcept "процедура_и_результат" "процедура и результат" "процедура"
  , mkConcept "признание_прав_другого" "признание прав другого" "признание"
  -- NEW CONCEPTS: время
  , mkConcept "длительность" "длительность" "длительность"
  , mkConcept "настоящее_как_точка" "настоящее как точка" "настоящее"
  , mkConcept "будущее_как_возможность" "будущее как возможность" "будущее"
  , mkConcept "цикличность_и_линейность" "цикличность и линейность" "цикличность"
  , mkConcept "темп_и_ритм" "темп и ритм" "темп"
  -- NEW CONCEPTS: разум
  , mkConcept "логическое_умозаключение" "логическое умозаключение" "умозаключение"
  , mkConcept "способность_к_обобщению" "способность к обобщению" "обобщение"
  , mkConcept "различение_истинного_и_ложного" "различение истинного и ложного" "различение"
  , mkConcept "критика_и_сомнение" "критика и сомнение" "критика"
  , mkConcept "порядок_мысли" "порядок мысли" "порядок"
  -- NEW CONCEPTS: бытие
  , mkConcept "факт_присутствия" "факт присутствия" "присутствие"
  , mkConcept "различение_сущего_и_ничто" "различение сущего и ничто" "сущее"
  , mkConcept "основание_всего" "основание всего" "основание"
  , mkConcept "необходимость_и_случайность" "необходимость и случайность" "необходимость"
  , mkConcept "становление" "становление" "становление"
  -- NEW CONCEPTS: история
  , mkConcept "память_коллектива" "память коллектива" "коллектив"
  , mkConcept "интерпретация_прошлого" "интерпретация прошлого" "интерпретация"
  , mkConcept "урок_и_предупреждение" "урок и предупреждение" "урок"
  , mkConcept "нарратив_и_факт" "нарратив и факт" "нарратив"
  , mkConcept "причина_и_следствие" "причина и следствие" "причина"
  -- NEW CONCEPTS: язык
  , mkConcept "структура_значения" "структура значения" "структура"
  , mkConcept "граница_выразимого" "граница выразимого" "граница"
  , mkConcept "конвенция_и_произвол" "конвенция и произвол" "конвенция"
  , mkConcept "переводимость_и_непереводимость" "переводимость и непереводимость" "переводимость"
  , mkConcept "метафора_и_буква" "метафора и буква" "метафора"
  -- NEW CONCEPTS: воля
  , mkConcept "направленность_усилия" "направленность усилия" "направленность"
  , mkConcept "выбор_цели" "выбор цели" "цель"
  , mkConcept "преодоление_сопротивления" "преодоление сопротивления" "преодоление"
  , mkConcept "решимость" "решимость" "решимость"
  , mkConcept "свобода_и_необходимость" "свобода и необходимость" "свобода_и_необходимость"
  -- NEW CONCEPTS: смерть
  , mkConcept "предел_существования" "предел существования" "предел"
  , mkConcept "осмысление_конечности" "осмысление конечности" "конечность"
  , mkConcept "уравнивание_всех" "уравнивание всех" "уравнивание"
  , mkConcept "страх_и_принятие" "страх и принятие" "принятие"
  , mkConcept "граница_смысла" "граница смысла" "граница"
  -- NEW CONCEPTS: одиночество
  , mkConcept "отсутствие_контакта" "отсутствие контакта" "контакт"
  , mkConcept "встреча_с_собой" "встреча с собой" "встреча"
  , mkConcept "изоляция_или_уединение" "изоляция или уединение" "уединение"
  , mkConcept "тишина_и_пустота" "тишина и пустота" "тишина"
  , mkConcept "потребность_в_другом" "потребность в другом" "потребность"
  -- NEW CONCEPTS: любовь
  , mkConcept "признание_ценности_другого" "признание ценности другого" "ценность"
  , mkConcept "преодоление_эгоцентризма" "преодоление эгоцентризма" "эгоцентризм"
  , mkConcept "дар_без_расчёта" "дар без расчёта" "дар"
  , mkConcept "уязвимость_и_близость" "уязвимость и близость" "близость"
  , mkConcept "вечность_в_мгновении" "вечность в мгновении" "вечность"
  -- NEW CONCEPTS: труд
  , mkConcept "преобразование_материи" "преобразование материи" "преобразование"
  , mkConcept "усилие_и_результат" "усилие и результат" "результат"
  , mkConcept "разделение_и_кооперация" "разделение и кооперация" "кооперация"
  , mkConcept "навык_и_мастерство" "навык и мастерство" "мастерство"
  , mkConcept "усталость_и_удовлетворение" "усталость и удовлетворение" "удовлетворение"
  -- NEW CONCEPTS: покой
  , mkConcept "пауза_в_действии" "пауза в действии" "пауза"
  , mkConcept "созерцание_и_присутствие" "созерцание и присутствие" "созерцание"
  , mkConcept "глубина_тишины" "глубина тишины" "тишина"
  , mkConcept "пустота_как_полнота" "пустота как полнота" "полнота"
  , mkConcept "остановка_и_осмысление" "остановка и осмысление" "остановка"
  -- NEW CONCEPTS: власть
  , mkConcept "асимметрия_отношений" "асимметрия отношений" "асимметрия"
  , mkConcept "принуждение_и_авторитет" "принуждение и авторитет" "авторитет"
  , mkConcept "ответственность_власти" "ответственность власти" "ответственность"
  , mkConcept "делегирование_и_контроль" "делегирование и контроль" "делегирование"
  , mkConcept "насилие_или_забота" "насилие или забота" "забота"
  -- NEW CONCEPTS: правда
  , mkConcept "свидетельство" "свидетельство" "свидетельство"
  , mkConcept "искренность_рассказа" "искренность рассказа" "искренность"
  , mkConcept "частная_перспектива" "частная перспектива" "перспектива"
  , mkConcept "долг_памяти" "долг памяти" "долг"
  , mkConcept "против_забвения" "против забвения" "забвение"
  -- NEW CONCEPTS: молчание
  , mkConcept "предел_слова" "предел слова" "предел"
  , mkConcept "присутствие_без_выражения" "присутствие без выражения" "присутствие"
  , mkConcept "глубина_невыразимого" "глубина невыразимого" "невыразимое"
  , mkConcept "слушание" "слушание" "слушание"
  , mkConcept "пауза_и_смысл" "пауза и смысл" "пауза"
  -- NEW CONCEPTS: ответственность
  , mkConcept "готовность_к_ответу" "готовность к ответу" "готовность"
  , mkConcept "свобода_как_условие" "свобода как условие" "условие"
  , mkConcept "вина_и_заслуга" "вина и заслуга" "вина"
  , mkConcept "пределы_контроля" "пределы контроля" "контроль"
  , mkConcept "ответ_перед_другими" "ответ перед другими" "ответ"
  -- NEW CONCEPTS: произвол
  , mkConcept "отсутствие_основания" "отсутствие основания" "основание"
  , mkConcept "каприз_и_случайность" "каприз и случайность" "каприз"
  , mkConcept "игнорирование_последствий" "игнорирование последствий" "игнорирование"
  , mkConcept "псевдосвобода" "псевдосвобода" "псевдосвобода"
  , mkConcept "разрушение_порядка" "разрушение порядка" "порядок"
  -- NEW CONCEPTS: мнение
  , mkConcept "частное_суждение" "частное суждение" "суждение"
  , mkConcept "обоснованность_и_вес" "обоснованность и вес" "обоснованность"
  , mkConcept "открытость_пересмотру" "открытость пересмотру" "пересмотр"
  , mkConcept "выражение_позиции" "выражение позиции" "выражение"
  , mkConcept "различение_с_истиной" "различение с истиной" "различение"
  -- NEW CONCEPTS: воспоминание
  , mkConcept "актуализация_прошлого" "актуализация прошлого" "актуализация"
  , mkConcept "эмоциональная_окраска" "эмоциональная окраска" "окраска"
  , mkConcept "достоверность_и_искажение" "достоверность и искажение" "достоверность"
  , mkConcept "связь_времён" "связь времён" "связь"
  , mkConcept "повторное_переживание" "повторное переживание" "переживание"
  -- NEW CONCEPTS: самосознание
  , mkConcept "рефлексия_над_собой" "рефлексия над собой" "рефлексия"
  , mkConcept "наблюдение_за_состояниями" "наблюдение за состояниями" "наблюдение"
  , mkConcept "идентификация_с_собой" "идентификация с собой" "идентификация"
  , mkConcept "различение_я_и_не_я" "различение я и не я" "различение"
  , mkConcept "самооценка" "самооценка" "самооценка"
  -- ============================================================
  -- Cross-domain bridge atoms (L2 expansion)
  -- Each connects a non-philosophical domain to L1 topics
  -- ============================================================
  , mkDomain "психика"
  , mkDomain "эмоция"
  , mkDomain "доказательство"
  , mkDomain "эксперимент"
  , mkDomain "нейрон"
  , mkDomain "логика"
  , mkDomain "аксиома"
  , mkDomain "закон"
  , mkDomain "право"
  , mkDomain "договор"
  , mkDomain "искусство"
  , mkDomain "музыка"
  , mkDomain "поэзия"
  , mkDomain "государство"
  , mkDomain "революция"
  , mkDomain "нация"
  , mkDomain "собственность"
  , mkDomain "рынок"
  , mkDomain "алгоритм"
  , mkDomain "данные"
  , mkDomain "код"
  , mkDomain "жизнь"
  , mkDomain "инстинкт"
  , mkDomain "эволюция"
  , mkDomain "энтропия"
  , mkDomain "энергия"
  , mkDomain "душа"
  , mkDomain "дух"
  ]
  where
    mkTopic surf = (AtomId surf, Atom (AtomId surf) surf surf surf CatTopic)
    mkConcept aid display head_ = (AtomId aid, Atom (AtomId aid) aid display head_ CatConcept)
    mkDomain surf = (AtomId surf, Atom (AtomId surf) surf surf surf CatDomain)

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
  -- TOPIC EDGES: смысл
  , rel "смысл" "целостность_жизни" RelPresupposes CaseAccusative "целостность жизни"
      "смысл предполагает целостность жизни" "смысл presupposes целостность жизни"
  , rel "смысл" "соотнесённость_с_целым" RelRequires CaseGenitive "соотнесённость с целым"
      "смысл требует соотнесённость с целым" "смысл requires соотнесённость с целым"
  , rel "смысл" "направление_вектора_жизни" RelIsA CaseNominative "направление вектора жизни"
      "смысл есть направление вектора жизни" "смысл is направление вектора жизни"
  , rel "смысл" "почему_а_не_зачем" RelDetermines CaseAccusative "почему а не зачем"
      "смысл определяет почему а не зачем" "смысл determines почему а не зачем"
  , rel "смысл" "переживание_значимости" RelGives CaseAccusative "переживание значимости"
      "смысл придаёт переживание значимости" "смысл gives переживание значимости"
  -- TOPIC EDGES: граница
  , rel "граница" "различение_внутри_и_снаружи" RelEvokes CaseAccusative "различение внутри и снаружи"
      "граница вызывает различение внутри и снаружи" "граница evokes различение внутри и снаружи"
  , rel "граница" "условие_формы" RelReliesOn CaseAccusative "условие формы"
      "граница опирается на условие формы" "граница relies on условие формы"
  , rel "граница" "предел_действия" RelReveals CaseAccusative "предел действия"
      "граница обнаруживает предел действия" "граница reveals предел действия"
  , rel "граница" "контактная_поверхность" RelUnifies CaseAccusative "контактная поверхность"
      "граница объединяет контактная поверхность" "граница unifies контактная поверхность"
  , rel "граница" "защита_и_ограничение" RelDirectedAt CaseAccusative "защита и ограничение"
      "граница направлена на защита и ограничение" "граница is directed at защита и ограничение"
  -- TOPIC EDGES: цифра
  , rel "цифра" "дискретность_и_точность" RelStructures CaseAccusative "дискретность и точность"
      "цифра структурирует дискретность и точность" "цифра structures дискретность и точность"
  , rel "цифра" "формализация_опыта" RelDenotes CaseAccusative "формализация опыта"
      "цифра обозначает формализация опыта" "цифра denotes формализация опыта"
  , rel "цифра" "утрата_контекста" RelSignals CasePrepositional "утрата контекста"
      "цифра сигнализирует о утрата контекста" "цифра signals утрата контекста"
  , rel "цифра" "сжимает_мир_до_значения" RelBuiltThrough CaseAccusative "сжимает мир до значения"
      "цифра строится через сжимает мир до значения" "цифра is built through сжимает мир до значения"
  , rel "цифра" "маскировка_качества_количеством" RelOrientsToward CaseAccusative "маскировка качества количеством"
      "цифра ориентирует на маскировка качества количеством" "цифра orients toward маскировка качества количеством"
  -- TOPIC EDGES: идентичность
  , rel "идентичность" "преемственность_я" RelContrastsWith CaseInstrumental "преемственность я"
      "идентичность контрастирует с преемственность я" "идентичность contrasts with преемственность я"
  , rel "идентичность" "ответ_на_вопрос_кто_я" RelPreserves CaseAccusative "ответ на вопрос кто я"
      "идентичность сохраняет ответ на вопрос кто я" "идентичность preserves ответ на вопрос кто я"
  , rel "идентичность" "нарратив_о_себе" RelPrescribes CaseAccusative "нарратив о себе"
      "идентичность предписывает нарратив о себе" "идентичность prescribes нарратив о себе"
  , rel "идентичность" "совпадение_с_собой" RelNecessaryFor CaseGenitive "совпадение с собой"
      "идентичность необходим для совпадение с собой" "идентичность is necessary for совпадение с собой"
  , rel "идентичность" "разрыв_и_восстановление" RelTransformsInto CaseAccusative "разрыв и восстановление"
      "идентичность превращается в разрыв и восстановление" "идентичность transforms into разрыв и восстановление"
  -- TOPIC EDGES: ремонт
  , rel "ремонт" "восстановление_функции" RelNotReducibleTo CaseDative "восстановление функции"
      "ремонт не сводится к восстановление функции" "ремонт is not reducible to восстановление функции"
  , rel "ремонт" "диагностика_поломки" RelTransforms CaseAccusative "диагностика поломки"
      "ремонт преобразует диагностика поломки" "ремонт transforms диагностика поломки"
  , rel "ремонт" "различение_починить_и_заменить" RelSupports CaseAccusative "различение починить и заменить"
      "ремонт поддерживает различение починить и заменить" "ремонт supports различение починить и заменить"
  , rel "ремонт" "возвращение_к_работоспособности" RelMeans CaseAccusative "возвращение к работоспособности"
      "ремонт означает возвращение к работоспособности" "ремонт means возвращение к работоспособности"
  , rel "ремонт" "усилие_против_энтропии" RelIncludes CaseAccusative "усилие против энтропии"
      "ремонт включает усилие против энтропии" "ремонт includes усилие против энтропии"
  -- TOPIC EDGES: свобода
  , rel "свобода" "осознанность_выбора" RelPresupposes CaseAccusative "осознанность выбора"
      "свобода предполагает осознанность выбора" "свобода presupposes осознанность выбора"
  , rel "свобода" "автономия_суждения" RelRequires CaseGenitive "автономия суждения"
      "свобода требует автономия суждения" "свобода requires автономия суждения"
  , rel "свобода" "самоопределение" RelIsA CaseNominative "самоопределение"
      "свобода есть самоопределение" "свобода is самоопределение"
  , rel "свобода" "отсутствие_принуждения" RelDetermines CaseAccusative "отсутствие принуждения"
      "свобода определяет отсутствие принуждения" "свобода determines отсутствие принуждения"
  , rel "свобода" "пространство_возможностей" RelGives CaseAccusative "пространство возможностей"
      "свобода придаёт пространство возможностей" "свобода gives пространство возможностей"
  -- TOPIC EDGES: истина
  , rel "истина" "объективность" RelEvokes CaseAccusative "объективность"
      "истина вызывает объективность" "истина evokes объективность"
  , rel "истина" "доказательство" RelReliesOn CaseAccusative "доказательство"
      "истина опирается на доказательство" "истина relies on доказательство"
  , rel "истина" "когерентность" RelReveals CaseAccusative "когерентность"
      "истина обнаруживает когерентность" "истина reveals когерентность"
  , rel "истина" "открытость_проверке" RelUnifies CaseAccusative "открытость проверке"
      "истина объединяет открытость проверке" "истина unifies открытость проверке"
  , rel "истина" "независимость_от_наблюдателя" RelDirectedAt CaseAccusative "независимость от наблюдателя"
      "истина направлена на независимость от наблюдателя" "истина is directed at независимость от наблюдателя"
  -- TOPIC EDGES: память
  , rel "память" "идентичность_через_время" RelStructures CaseAccusative "идентичность через время"
      "память структурирует идентичность через время" "память structures идентичность через время"
  , rel "память" "след_прошлого" RelDenotes CaseAccusative "след прошлого"
      "память обозначает след прошлого" "память denotes след прошлого"
  , rel "память" "забывание_как_условие" RelSignals CasePrepositional "забывание как условие"
      "память сигнализирует о забывание как условие" "память signals забывание как условие"
  , rel "память" "узнавание" RelBuiltThrough CaseAccusative "узнавание"
      "память строится через узнавание" "память is built through узнавание"
  , rel "память" "привычка_и_рутина" RelOrientsToward CaseAccusative "привычка и рутина"
      "память ориентирует на привычка и рутина" "память orients toward привычка и рутина"
  -- TOPIC EDGES: сознание
  , rel "сознание" "интенциональность" RelContrastsWith CaseInstrumental "интенциональность"
      "сознание контрастирует с интенциональность" "сознание contrasts with интенциональность"
  , rel "сознание" "качественность_опыта" RelPreserves CaseAccusative "качественность опыта"
      "сознание сохраняет качественность опыта" "сознание preserves качественность опыта"
  , rel "сознание" "единство_поля_опыта" RelPrescribes CaseAccusative "единство поля опыта"
      "сознание предписывает единство поля опыта" "сознание prescribes единство поля опыта"
  , rel "сознание" "присутствие" RelNecessaryFor CaseGenitive "присутствие"
      "сознание необходим для присутствие" "сознание is necessary for присутствие"
  , rel "сознание" "поток_переживаний" RelTransformsInto CaseAccusative "поток переживаний"
      "сознание превращается в поток переживаний" "сознание transforms into поток переживаний"
  -- TOPIC EDGES: вера
  , rel "вера" "акт_доверия" RelNotReducibleTo CaseDative "акт доверия"
      "вера не сводится к акт доверия" "вера is not reducible to акт доверия"
  , rel "вера" "обоснованность_не_доказательством" RelTransforms CaseAccusative "обоснованность не доказательством"
      "вера преобразует обоснованность не доказательством" "вера transforms обоснованность не доказательством"
  , rel "вера" "готовность_к_риску" RelSupports CaseAccusative "готовность к риску"
      "вера поддерживает готовность к риску" "вера supports готовность к риску"
  , rel "вера" "верность" RelMeans CaseAccusative "верность"
      "вера означает верность" "вера means верность"
  , rel "вера" "прыжок_за_горизонт" RelIncludes CaseAccusative "прыжок за горизонт"
      "вера включает прыжок за горизонт" "вера includes прыжок за горизонт"
  -- TOPIC EDGES: красота
  , rel "красота" "гармония_формы" RelPresupposes CaseAccusative "гармония формы"
      "красота предполагает гармония формы" "красота presupposes гармония формы"
  , rel "красота" "соразмерность_частей" RelRequires CaseGenitive "соразмерность частей"
      "красота требует соразмерность частей" "красота requires соразмерность частей"
  , rel "красота" "праздность_созерцания" RelIsA CaseNominative "праздность созерцания"
      "красота есть праздность созерцания" "красота is праздность созерцания"
  , rel "красота" "превосходство_над_полезным" RelDetermines CaseAccusative "превосходство над полезным"
      "красота определяет превосходство над полезным" "красота determines превосходство над полезным"
  , rel "красота" "мгновение_и_вечность" RelGives CaseAccusative "мгновение и вечность"
      "красота придаёт мгновение и вечность" "красота gives мгновение и вечность"
  -- TOPIC EDGES: долг
  , rel "долг" "долженствование" RelEvokes CaseAccusative "долженствование"
      "долг вызывает долженствование" "долг evokes долженствование"
  , rel "долг" "приоритет_над_желанием" RelReliesOn CaseAccusative "приоритет над желанием"
      "долг опирается на приоритет над желанием" "долг relies on приоритет над желанием"
  , rel "долг" "внутренний_закон" RelReveals CaseAccusative "внутренний закон"
      "долг обнаруживает внутренний закон" "долг reveals внутренний закон"
  , rel "долг" "совесть_как_свидетель" RelUnifies CaseAccusative "совесть как свидетель"
      "долг объединяет совесть как свидетель" "долг unifies совесть как свидетель"
  , rel "долг" "исполнение_обещания" RelDirectedAt CaseAccusative "исполнение обещания"
      "долг направлена на исполнение обещания" "долг is directed at исполнение обещания"
  -- TOPIC EDGES: доверие
  , rel "доверие" "риск_уязвимости" RelStructures CaseAccusative "риск уязвимости"
      "доверие структурирует риск уязвимости" "доверие structures риск уязвимости"
  , rel "доверие" "опора_на_другого" RelDenotes CaseAccusative "опора на другого"
      "доверие обозначает опора на другого" "доверие denotes опора на другого"
  , rel "доверие" "проверка_опытом" RelSignals CasePrepositional "проверка опытом"
      "доверие сигнализирует о проверка опытом" "доверие signals проверка опытом"
  , rel "доверие" "прозрачность_намерений" RelBuiltThrough CaseAccusative "прозрачность намерений"
      "доверие строится через прозрачность намерений" "доверие is built through прозрачность намерений"
  , rel "доверие" "разрыв_и_восстановление_доверия" RelOrientsToward CaseAccusative "разрыв и восстановление доверия"
      "доверие ориентирует на разрыв и восстановление доверия" "доверие orients toward разрыв и восстановление доверия"
  -- TOPIC EDGES: страх
  , rel "страх" "ожидание_угрозы" RelContrastsWith CaseInstrumental "ожидание угрозы"
      "страх контрастирует с ожидание угрозы" "страх contrasts with ожидание угрозы"
  , rel "страх" "сигнал_опасности" RelPreserves CaseAccusative "сигнал опасности"
      "страх сохраняет сигнал опасности" "страх preserves сигнал опасности"
  , rel "страх" "паралич_или_действие" RelPrescribes CaseAccusative "паралич или действие"
      "страх предписывает паралич или действие" "страх prescribes паралич или действие"
  , rel "страх" "перед_неизвестным" RelNecessaryFor CaseGenitive "перед неизвестным"
      "страх необходим для перед неизвестным" "страх is necessary for перед неизвестным"
  , rel "страх" "защитная_реакция" RelTransformsInto CaseAccusative "защитная реакция"
      "страх превращается в защитная реакция" "страх transforms into защитная реакция"
  -- TOPIC EDGES: надежда
  , rel "надежда" "ориентация_на_будущее" RelNotReducibleTo CaseDative "ориентация на будущее"
      "надежда не сводится к ориентация на будущее" "надежда is not reducible to ориентация на будущее"
  , rel "надежда" "наперекор_очевидности" RelTransforms CaseAccusative "наперекор очевидности"
      "надежда преобразует наперекор очевидности" "надежда transforms наперекор очевидности"
  , rel "надежда" "утешение_и_мотив" RelSupports CaseAccusative "утешение и мотив"
      "надежда поддерживает утешение и мотив" "надежда supports утешение и мотив"
  , rel "надежда" "обещание_себе" RelMeans CaseAccusative "обещание себе"
      "надежда означает обещание себе" "надежда means обещание себе"
  , rel "надежда" "пустота_или_вектор" RelIncludes CaseAccusative "пустота или вектор"
      "надежда включает пустота или вектор" "надежда includes пустота или вектор"
  -- TOPIC EDGES: справедливость
  , rel "справедливость" "мера_и_соразмерность" RelPresupposes CaseAccusative "мера и соразмерность"
      "справедливость предполагает мера и соразмерность" "справедливость presupposes мера и соразмерность"
  , rel "справедливость" "беспристрастность" RelRequires CaseGenitive "беспристрастность"
      "справедливость требует беспристрастность" "справедливость requires беспристрастность"
  , rel "справедливость" "воздаяние_по_заслугам" RelIsA CaseNominative "воздаяние по заслугам"
      "справедливость есть воздаяние по заслугам" "справедливость is воздаяние по заслугам"
  , rel "справедливость" "процедура_и_результат" RelDetermines CaseAccusative "процедура и результат"
      "справедливость определяет процедура и результат" "справедливость determines процедура и результат"
  , rel "справедливость" "признание_прав_другого" RelGives CaseAccusative "признание прав другого"
      "справедливость придаёт признание прав другого" "справедливость gives признание прав другого"
  -- TOPIC EDGES: время
  , rel "время" "длительность" RelEvokes CaseAccusative "длительность"
      "время вызывает длительность" "время evokes длительность"
  , rel "время" "настоящее_как_точка" RelReliesOn CaseAccusative "настоящее как точка"
      "время опирается на настоящее как точка" "время relies on настоящее как точка"
  , rel "время" "будущее_как_возможность" RelReveals CaseAccusative "будущее как возможность"
      "время обнаруживает будущее как возможность" "время reveals будущее как возможность"
  , rel "время" "цикличность_и_линейность" RelUnifies CaseAccusative "цикличность и линейность"
      "время объединяет цикличность и линейность" "время unifies цикличность и линейность"
  , rel "время" "темп_и_ритм" RelDirectedAt CaseAccusative "темп и ритм"
      "время направлена на темп и ритм" "время is directed at темп и ритм"
  -- TOPIC EDGES: разум
  , rel "разум" "логическое_умозаключение" RelStructures CaseAccusative "логическое умозаключение"
      "разум структурирует логическое умозаключение" "разум structures логическое умозаключение"
  , rel "разум" "способность_к_обобщению" RelDenotes CaseAccusative "способность к обобщению"
      "разум обозначает способность к обобщению" "разум denotes способность к обобщению"
  , rel "разум" "различение_истинного_и_ложного" RelSignals CasePrepositional "различение истинного и ложного"
      "разум сигнализирует о различение истинного и ложного" "разум signals различение истинного и ложного"
  , rel "разум" "критика_и_сомнение" RelBuiltThrough CaseAccusative "критика и сомнение"
      "разум строится через критика и сомнение" "разум is built through критика и сомнение"
  , rel "разум" "порядок_мысли" RelOrientsToward CaseAccusative "порядок мысли"
      "разум ориентирует на порядок мысли" "разум orients toward порядок мысли"
  -- TOPIC EDGES: бытие
  , rel "бытие" "факт_присутствия" RelContrastsWith CaseInstrumental "факт присутствия"
      "бытие контрастирует с факт присутствия" "бытие contrasts with факт присутствия"
  , rel "бытие" "различение_сущего_и_ничто" RelPreserves CaseAccusative "различение сущего и ничто"
      "бытие сохраняет различение сущего и ничто" "бытие preserves различение сущего и ничто"
  , rel "бытие" "основание_всего" RelPrescribes CaseAccusative "основание всего"
      "бытие предписывает основание всего" "бытие prescribes основание всего"
  , rel "бытие" "необходимость_и_случайность" RelNecessaryFor CaseGenitive "необходимость и случайность"
      "бытие необходим для необходимость и случайность" "бытие is necessary for необходимость и случайность"
  , rel "бытие" "становление" RelTransformsInto CaseAccusative "становление"
      "бытие превращается в становление" "бытие transforms into становление"
  -- TOPIC EDGES: история
  , rel "история" "память_коллектива" RelNotReducibleTo CaseDative "память коллектива"
      "история не сводится к память коллектива" "история is not reducible to память коллектива"
  , rel "история" "интерпретация_прошлого" RelTransforms CaseAccusative "интерпретация прошлого"
      "история преобразует интерпретация прошлого" "история transforms интерпретация прошлого"
  , rel "история" "урок_и_предупреждение" RelSupports CaseAccusative "урок и предупреждение"
      "история поддерживает урок и предупреждение" "история supports урок и предупреждение"
  , rel "история" "нарратив_и_факт" RelMeans CaseAccusative "нарратив и факт"
      "история означает нарратив и факт" "история means нарратив и факт"
  , rel "история" "причина_и_следствие" RelIncludes CaseAccusative "причина и следствие"
      "история включает причина и следствие" "история includes причина и следствие"
  -- TOPIC EDGES: язык
  , rel "язык" "структура_значения" RelPresupposes CaseAccusative "структура значения"
      "язык предполагает структура значения" "язык presupposes структура значения"
  , rel "язык" "граница_выразимого" RelRequires CaseGenitive "граница выразимого"
      "язык требует граница выразимого" "язык requires граница выразимого"
  , rel "язык" "конвенция_и_произвол" RelIsA CaseNominative "конвенция и произвол"
      "язык есть конвенция и произвол" "язык is конвенция и произвол"
  , rel "язык" "переводимость_и_непереводимость" RelDetermines CaseAccusative "переводимость и непереводимость"
      "язык определяет переводимость и непереводимость" "язык determines переводимость и непереводимость"
  , rel "язык" "метафора_и_буква" RelGives CaseAccusative "метафора и буква"
      "язык придаёт метафора и буква" "язык gives метафора и буква"
  -- TOPIC EDGES: воля
  , rel "воля" "направленность_усилия" RelEvokes CaseAccusative "направленность усилия"
      "воля вызывает направленность усилия" "воля evokes направленность усилия"
  , rel "воля" "выбор_цели" RelReliesOn CaseAccusative "выбор цели"
      "воля опирается на выбор цели" "воля relies on выбор цели"
  , rel "воля" "преодоление_сопротивления" RelReveals CaseAccusative "преодоление сопротивления"
      "воля обнаруживает преодоление сопротивления" "воля reveals преодоление сопротивления"
  , rel "воля" "решимость" RelUnifies CaseAccusative "решимость"
      "воля объединяет решимость" "воля unifies решимость"
  , rel "воля" "свобода_и_необходимость" RelDirectedAt CaseAccusative "свобода и необходимость"
      "воля направлена на свобода и необходимость" "воля is directed at свобода и необходимость"
  -- TOPIC EDGES: смерть
  , rel "смерть" "предел_существования" RelStructures CaseAccusative "предел существования"
      "смерть структурирует предел существования" "смерть structures предел существования"
  , rel "смерть" "осмысление_конечности" RelDenotes CaseAccusative "осмысление конечности"
      "смерть обозначает осмысление конечности" "смерть denotes осмысление конечности"
  , rel "смерть" "уравнивание_всех" RelSignals CasePrepositional "уравнивание всех"
      "смерть сигнализирует о уравнивание всех" "смерть signals уравнивание всех"
  , rel "смерть" "страх_и_принятие" RelBuiltThrough CaseAccusative "страх и принятие"
      "смерть строится через страх и принятие" "смерть is built through страх и принятие"
  , rel "смерть" "граница_смысла" RelOrientsToward CaseAccusative "граница смысла"
      "смерть ориентирует на граница смысла" "смерть orients toward граница смысла"
  -- TOPIC EDGES: одиночество
  , rel "одиночество" "отсутствие_контакта" RelContrastsWith CaseInstrumental "отсутствие контакта"
      "одиночество контрастирует с отсутствие контакта" "одиночество contrasts with отсутствие контакта"
  , rel "одиночество" "встреча_с_собой" RelPreserves CaseAccusative "встреча с собой"
      "одиночество сохраняет встреча с собой" "одиночество preserves встреча с собой"
  , rel "одиночество" "изоляция_или_уединение" RelPrescribes CaseAccusative "изоляция или уединение"
      "одиночество предписывает изоляция или уединение" "одиночество prescribes изоляция или уединение"
  , rel "одиночество" "тишина_и_пустота" RelNecessaryFor CaseGenitive "тишина и пустота"
      "одиночество необходим для тишина и пустота" "одиночество is necessary for тишина и пустота"
  , rel "одиночество" "потребность_в_другом" RelTransformsInto CaseAccusative "потребность в другом"
      "одиночество превращается в потребность в другом" "одиночество transforms into потребность в другом"
  -- TOPIC EDGES: любовь
  , rel "любовь" "признание_ценности_другого" RelNotReducibleTo CaseDative "признание ценности другого"
      "любовь не сводится к признание ценности другого" "любовь is not reducible to признание ценности другого"
  , rel "любовь" "преодоление_эгоцентризма" RelTransforms CaseAccusative "преодоление эгоцентризма"
      "любовь преобразует преодоление эгоцентризма" "любовь transforms преодоление эгоцентризма"
  , rel "любовь" "дар_без_расчёта" RelSupports CaseAccusative "дар без расчёта"
      "любовь поддерживает дар без расчёта" "любовь supports дар без расчёта"
  , rel "любовь" "уязвимость_и_близость" RelMeans CaseAccusative "уязвимость и близость"
      "любовь означает уязвимость и близость" "любовь means уязвимость и близость"
  , rel "любовь" "вечность_в_мгновении" RelIncludes CaseAccusative "вечность в мгновении"
      "любовь включает вечность в мгновении" "любовь includes вечность в мгновении"
  -- TOPIC EDGES: труд
  , rel "труд" "преобразование_материи" RelPresupposes CaseAccusative "преобразование материи"
      "труд предполагает преобразование материи" "труд presupposes преобразование материи"
  , rel "труд" "усилие_и_результат" RelRequires CaseGenitive "усилие и результат"
      "труд требует усилие и результат" "труд requires усилие и результат"
  , rel "труд" "разделение_и_кооперация" RelIsA CaseNominative "разделение и кооперация"
      "труд есть разделение и кооперация" "труд is разделение и кооперация"
  , rel "труд" "навык_и_мастерство" RelDetermines CaseAccusative "навык и мастерство"
      "труд определяет навык и мастерство" "труд determines навык и мастерство"
  , rel "труд" "усталость_и_удовлетворение" RelGives CaseAccusative "усталость и удовлетворение"
      "труд придаёт усталость и удовлетворение" "труд gives усталость и удовлетворение"
  -- TOPIC EDGES: покой
  , rel "покой" "пауза_в_действии" RelEvokes CaseAccusative "пауза в действии"
      "покой вызывает пауза в действии" "покой evokes пауза в действии"
  , rel "покой" "созерцание_и_присутствие" RelReliesOn CaseAccusative "созерцание и присутствие"
      "покой опирается на созерцание и присутствие" "покой relies on созерцание и присутствие"
  , rel "покой" "глубина_тишины" RelReveals CaseAccusative "глубина тишины"
      "покой обнаруживает глубина тишины" "покой reveals глубина тишины"
  , rel "покой" "пустота_как_полнота" RelUnifies CaseAccusative "пустота как полнота"
      "покой объединяет пустота как полнота" "покой unifies пустота как полнота"
  , rel "покой" "остановка_и_осмысление" RelDirectedAt CaseAccusative "остановка и осмысление"
      "покой направлена на остановка и осмысление" "покой is directed at остановка и осмысление"
  -- TOPIC EDGES: власть
  , rel "власть" "асимметрия_отношений" RelStructures CaseAccusative "асимметрия отношений"
      "власть структурирует асимметрия отношений" "власть structures асимметрия отношений"
  , rel "власть" "принуждение_и_авторитет" RelDenotes CaseAccusative "принуждение и авторитет"
      "власть обозначает принуждение и авторитет" "власть denotes принуждение и авторитет"
  , rel "власть" "ответственность_власти" RelSignals CasePrepositional "ответственность власти"
      "власть сигнализирует о ответственность власти" "власть signals ответственность власти"
  , rel "власть" "делегирование_и_контроль" RelBuiltThrough CaseAccusative "делегирование и контроль"
      "власть строится через делегирование и контроль" "власть is built through делегирование и контроль"
  , rel "власть" "насилие_или_забота" RelOrientsToward CaseAccusative "насилие или забота"
      "власть ориентирует на насилие или забота" "власть orients toward насилие или забота"
  -- TOPIC EDGES: правда
  , rel "правда" "свидетельство" RelContrastsWith CaseInstrumental "свидетельство"
      "правда контрастирует с свидетельство" "правда contrasts with свидетельство"
  , rel "правда" "искренность_рассказа" RelPreserves CaseAccusative "искренность рассказа"
      "правда сохраняет искренность рассказа" "правда preserves искренность рассказа"
  , rel "правда" "частная_перспектива" RelPrescribes CaseAccusative "частная перспектива"
      "правда предписывает частная перспектива" "правда prescribes частная перспектива"
  , rel "правда" "долг_памяти" RelNecessaryFor CaseGenitive "долг памяти"
      "правда необходим для долг памяти" "правда is necessary for долг памяти"
  , rel "правда" "против_забвения" RelTransformsInto CaseAccusative "против забвения"
      "правда превращается в против забвения" "правда transforms into против забвения"
  -- TOPIC EDGES: молчание
  , rel "молчание" "предел_слова" RelNotReducibleTo CaseDative "предел слова"
      "молчание не сводится к предел слова" "молчание is not reducible to предел слова"
  , rel "молчание" "присутствие_без_выражения" RelTransforms CaseAccusative "присутствие без выражения"
      "молчание преобразует присутствие без выражения" "молчание transforms присутствие без выражения"
  , rel "молчание" "глубина_невыразимого" RelSupports CaseAccusative "глубина невыразимого"
      "молчание поддерживает глубина невыразимого" "молчание supports глубина невыразимого"
  , rel "молчание" "слушание" RelMeans CaseAccusative "слушание"
      "молчание означает слушание" "молчание means слушание"
  , rel "молчание" "пауза_и_смысл" RelIncludes CaseAccusative "пауза и смысл"
      "молчание включает пауза и смысл" "молчание includes пауза и смысл"
  -- TOPIC EDGES: ответственность
  , rel "ответственность" "готовность_к_ответу" RelPresupposes CaseAccusative "готовность к ответу"
      "ответственность предполагает готовность к ответу" "ответственность presupposes готовность к ответу"
  , rel "ответственность" "свобода_как_условие" RelRequires CaseGenitive "свобода как условие"
      "ответственность требует свобода как условие" "ответственность requires свобода как условие"
  , rel "ответственность" "вина_и_заслуга" RelIsA CaseNominative "вина и заслуга"
      "ответственность есть вина и заслуга" "ответственность is вина и заслуга"
  , rel "ответственность" "пределы_контроля" RelDetermines CaseAccusative "пределы контроля"
      "ответственность определяет пределы контроля" "ответственность determines пределы контроля"
  , rel "ответственность" "ответ_перед_другими" RelGives CaseAccusative "ответ перед другими"
      "ответственность придаёт ответ перед другими" "ответственность gives ответ перед другими"
  -- TOPIC EDGES: произвол
  , rel "произвол" "отсутствие_основания" RelEvokes CaseAccusative "отсутствие основания"
      "произвол вызывает отсутствие основания" "произвол evokes отсутствие основания"
  , rel "произвол" "каприз_и_случайность" RelReliesOn CaseAccusative "каприз и случайность"
      "произвол опирается на каприз и случайность" "произвол relies on каприз и случайность"
  , rel "произвол" "игнорирование_последствий" RelReveals CaseAccusative "игнорирование последствий"
      "произвол обнаруживает игнорирование последствий" "произвол reveals игнорирование последствий"
  , rel "произвол" "псевдосвобода" RelUnifies CaseAccusative "псевдосвобода"
      "произвол объединяет псевдосвобода" "произвол unifies псевдосвобода"
  , rel "произвол" "разрушение_порядка" RelDirectedAt CaseAccusative "разрушение порядка"
      "произвол направлена на разрушение порядка" "произвол is directed at разрушение порядка"
  -- TOPIC EDGES: мнение
  , rel "мнение" "частное_суждение" RelStructures CaseAccusative "частное суждение"
      "мнение структурирует частное суждение" "мнение structures частное суждение"
  , rel "мнение" "обоснованность_и_вес" RelDenotes CaseAccusative "обоснованность и вес"
      "мнение обозначает обоснованность и вес" "мнение denotes обоснованность и вес"
  , rel "мнение" "открытость_пересмотру" RelSignals CasePrepositional "открытость пересмотру"
      "мнение сигнализирует о открытость пересмотру" "мнение signals открытость пересмотру"
  , rel "мнение" "выражение_позиции" RelBuiltThrough CaseAccusative "выражение позиции"
      "мнение строится через выражение позиции" "мнение is built through выражение позиции"
  , rel "мнение" "различение_с_истиной" RelOrientsToward CaseAccusative "различение с истиной"
      "мнение ориентирует на различение с истиной" "мнение orients toward различение с истиной"
  -- TOPIC EDGES: воспоминание
  , rel "воспоминание" "актуализация_прошлого" RelContrastsWith CaseInstrumental "актуализация прошлого"
      "воспоминание контрастирует с актуализация прошлого" "воспоминание contrasts with актуализация прошлого"
  , rel "воспоминание" "эмоциональная_окраска" RelPreserves CaseAccusative "эмоциональная окраска"
      "воспоминание сохраняет эмоциональная окраска" "воспоминание preserves эмоциональная окраска"
  , rel "воспоминание" "достоверность_и_искажение" RelPrescribes CaseAccusative "достоверность и искажение"
      "воспоминание предписывает достоверность и искажение" "воспоминание prescribes достоверность и искажение"
  , rel "воспоминание" "связь_времён" RelNecessaryFor CaseGenitive "связь времён"
      "воспоминание необходим для связь времён" "воспоминание is necessary for связь времён"
  , rel "воспоминание" "повторное_переживание" RelTransformsInto CaseAccusative "повторное переживание"
      "воспоминание превращается в повторное переживание" "воспоминание transforms into повторное переживание"
  -- TOPIC EDGES: самосознание
  , rel "самосознание" "рефлексия_над_собой" RelNotReducibleTo CaseDative "рефлексия над собой"
      "самосознание не сводится к рефлексия над собой" "самосознание is not reducible to рефлексия над собой"
  , rel "самосознание" "наблюдение_за_состояниями" RelTransforms CaseAccusative "наблюдение за состояниями"
      "самосознание преобразует наблюдение за состояниями" "самосознание transforms наблюдение за состояниями"
  , rel "самосознание" "идентификация_с_собой" RelSupports CaseAccusative "идентификация с собой"
      "самосознание поддерживает идентификация с собой" "самосознание supports идентификация с собой"
  , rel "самосознание" "различение_я_и_не_я" RelMeans CaseAccusative "различение я и не я"
      "самосознание означает различение я и не я" "самосознание means различение я и не я"
  , rel "самосознание" "самооценка" RelIncludes CaseAccusative "самооценка"
      "самосознание включает самооценка" "самосознание includes самооценка"
  -- CROSS-TOPIC EDGES
  , rel "свобода" "ответственность" RelPresupposes CaseAccusative "ответственность"
      "свобода предполагает ответственность" "свобода presupposes ответственность"
  , rel "свобода" "воля" RelRequires CaseGenitive "воля"
      "свобода требует воля" "свобода requires воля"
  , rel "свобода" "смысл" RelPresupposes CaseAccusative "смысл"
      "свобода предполагает смысл" "свобода presupposes смысл"
  , rel "свобода" "сознание" RelRequires CaseGenitive "сознание"
      "свобода требует сознание" "свобода requires сознание"
  , rel "свобода" "истина" RelContrastsWith CaseInstrumental "истина"
      "свобода контрастирует с истина" "свобода contrasts with истина"
      `withVerb` "контрастирует с"
  , rel "истина" "правда" RelGives CaseAccusative "правда"
      "истина придаёт правда" "истина gives правда"
  , rel "истина" "мнение" RelContrastsWith CaseInstrumental "мнение"
      "истина контрастирует с мнение" "истина contrasts with мнение"
      `withVerb` "контрастирует с"
  , rel "истина" "разум" RelReliesOn CaseAccusative "разум"
      "истина опирается на разум" "истина relies on разум"
  , rel "истина" "бытие" RelContrastsWith CaseInstrumental "бытие"
      "истина контрастирует с бытие" "истина contrasts with бытие"
      `withVerb` "контрастирует с"
  , rel "истина" "долг" RelContrastsWith CaseInstrumental "долг"
      "истина контрастирует с долг" "истина contrasts with долг"
      `withVerb` "контрастирует с"
  , rel "память" "воспоминание" RelIncludes CaseAccusative "воспоминание"
      "память включает воспоминание" "память includes воспоминание"
  , rel "память" "время" RelPresupposes CaseAccusative "время"
      "память предполагает время" "память presupposes время"
  , rel "память" "идентичность" RelPreserves CaseAccusative "идентичность"
      "память сохраняет идентичность" "память preserves идентичность"
  , rel "память" "история" RelContrastsWith CaseInstrumental "история"
      "память контрастирует с история" "память contrasts with история"
      `withVerb` "контрастирует с"
  , rel "память" "правда" RelSupports CaseAccusative "правда"
      "память поддерживает правда" "память supports правда"
  , rel "сознание" "самосознание" RelIncludes CaseAccusative "самосознание"
      "сознание включает самосознание" "сознание includes самосознание"
  , rel "сознание" "разум" RelContrastsWith CaseInstrumental "разум"
      "сознание контрастирует с разум" "сознание contrasts with разум"
      `withVerb` "контрастирует с"
  , rel "сознание" "язык" RelPresupposes CaseAccusative "язык"
      "сознание предполагает язык" "сознание presupposes язык"
  , rel "сознание" "время" RelStructures CaseAccusative "время"
      "сознание структурирует время" "сознание structures время"
  , rel "сознание" "воля" RelContrastsWith CaseInstrumental "воля"
      "сознание контрастирует с воля" "сознание contrasts with воля"
      `withVerb` "контрастирует с"
  , rel "вера" "доверие" RelIncludes CaseAccusative "доверие"
      "вера включает доверие" "вера includes доверие"
  , rel "вера" "истина" RelContrastsWith CaseInstrumental "истина"
      "вера контрастирует с истина" "вера contrasts with истина"
      `withVerb` "контрастирует с"
  , rel "вера" "надежда" RelSupports CaseAccusative "надежда"
      "вера поддерживает надежда" "вера supports надежда"
  , rel "вера" "разум" RelContrastsWith CaseInstrumental "разум"
      "вера контрастирует с разум" "вера contrasts with разум"
      `withVerb` "контрастирует с"
  , rel "вера" "смысл" RelGives CaseAccusative "смысл"
      "вера придаёт смысл" "вера gives смысл"
  , rel "красота" "истина" RelContrastsWith CaseInstrumental "истина"
      "красота контрастирует с истина" "красота contrasts with истина"
      `withVerb` "контрастирует с"
  , rel "красота" "смысл" RelEvokes CaseAccusative "смысл"
      "красота вызывает смысл" "красота evokes смысл"
  , rel "красота" "язык" RelReliesOn CaseAccusative "язык"
      "красота опирается на язык" "красота relies on язык"
  , rel "красота" "покой" RelContrastsWith CaseInstrumental "покой"
      "красота контрастирует с покой" "красота contrasts with покой"
      `withVerb` "контрастирует с"
  , rel "красота" "любовь" RelContrastsWith CaseInstrumental "любовь"
      "красота контрастирует с любовь" "красота contrasts with любовь"
      `withVerb` "контрастирует с"
  , rel "долг" "ответственность" RelIsA CaseNominative "ответственность"
      "долг есть ответственность" "долг is ответственность"
  , rel "долг" "свобода" RelPresupposes CaseAccusative "свобода"
      "долг предполагает свобода" "долг presupposes свобода"
  , rel "долг" "справедливость" RelContrastsWith CaseInstrumental "справедливость"
      "долг контрастирует с справедливость" "долг contrasts with справедливость"
      `withVerb` "контрастирует с"
  , rel "долг" "воля" RelRequires CaseGenitive "воля"
      "долг требует воля" "долг requires воля"
  , rel "доверие" "вера" RelContrastsWith CaseInstrumental "вера"
      "доверие контрастирует с вера" "доверие contrasts with вера"
      `withVerb` "контрастирует с"
  , rel "доверие" "правда" RelContrastsWith CaseInstrumental "правда"
      "доверие контрастирует с правда" "доверие contrasts with правда"
      `withVerb` "контрастирует с"
  , rel "доверие" "ответственность" RelContrastsWith CaseInstrumental "ответственность"
      "доверие контрастирует с ответственность" "доверие contrasts with ответственность"
      `withVerb` "контрастирует с"
  , rel "доверие" "любовь" RelSupports CaseAccusative "любовь"
      "доверие поддерживает любовь" "доверие supports любовь"
  , rel "доверие" "надежда" RelSupports CaseAccusative "надежда"
      "доверие поддерживает надежда" "доверие supports надежда"
  , rel "страх" "смерть" RelDirectedAt CaseAccusative "смерть"
      "страх направлена на смерть" "страх is directed at смерть"
      `withVerb` "направлена на"
  , rel "страх" "надежда" RelContrastsWith CaseInstrumental "надежда"
      "страх контрастирует с надежда" "страх contrasts with надежда"
      `withVerb` "контрастирует с"
  , rel "страх" "власть" RelContrastsWith CaseInstrumental "власть"
      "страх контрастирует с власть" "страх contrasts with власть"
      `withVerb` "контрастирует с"
  , rel "страх" "одиночество" RelEvokes CaseAccusative "одиночество"
      "страх вызывает одиночество" "страх evokes одиночество"
  , rel "надежда" "страх" RelContrastsWith CaseInstrumental "страх"
      "надежда контрастирует с страх" "надежда contrasts with страх"
      `withVerb` "контрастирует с"
  , rel "надежда" "вера" RelSupports CaseAccusative "вера"
      "надежда поддерживает вера" "надежда supports вера"
  , rel "надежда" "смысл" RelGives CaseAccusative "смысл"
      "надежда придаёт смысл" "надежда gives смысл"
  , rel "надежда" "любовь" RelSupports CaseAccusative "любовь"
      "надежда поддерживает любовь" "надежда supports любовь"
  , rel "справедливость" "долг" RelContrastsWith CaseInstrumental "долг"
      "справедливость контрастирует с долг" "справедливость contrasts with долг"
      `withVerb` "контрастирует с"
  , rel "справедливость" "власть" RelContrastsWith CaseInstrumental "власть"
      "справедливость контрастирует с власть" "справедливость contrasts with власть"
      `withVerb` "контрастирует с"
  , rel "справедливость" "ответственность" RelRequires CaseGenitive "ответственность"
      "справедливость требует ответственность" "справедливость requires ответственность"
  , rel "справедливость" "правда" RelContrastsWith CaseInstrumental "правда"
      "справедливость контрастирует с правда" "справедливость contrasts with правда"
      `withVerb` "контрастирует с"
  , rel "время" "память" RelSupports CaseAccusative "память"
      "время поддерживает память" "время supports память"
  , rel "время" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "время контрастирует с смерть" "время contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "время" "бытие" RelStructures CaseAccusative "бытие"
      "время структурирует бытие" "время structures бытие"
  , rel "время" "история" RelIncludes CaseAccusative "история"
      "время включает история" "время includes история"
  , rel "время" "надежда" RelOrientsToward CaseAccusative "надежда"
      "время ориентирует на надежда" "время orients toward надежда"
  , rel "разум" "истина" RelDirectedAt CaseAccusative "истина"
      "разум направлена на истина" "разум is directed at истина"
      `withVerb` "направлена на"
  , rel "разум" "сознание" RelContrastsWith CaseInstrumental "сознание"
      "разум контрастирует с сознание" "разум contrasts with сознание"
      `withVerb` "контрастирует с"
  , rel "разум" "язык" RelPresupposes CaseAccusative "язык"
      "разум предполагает язык" "разум presupposes язык"
  , rel "разум" "воля" RelContrastsWith CaseInstrumental "воля"
      "разум контрастирует с воля" "разум contrasts with воля"
      `withVerb` "контрастирует с"
  , rel "бытие" "сущность" RelSupports CaseAccusative "сущность"
      "бытие поддерживает сущность" "бытие supports сущность"
  , rel "бытие" "время" RelIncludes CaseAccusative "время"
      "бытие включает время" "бытие includes время"
  , rel "бытие" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "бытие контрастирует с смерть" "бытие contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "бытие" "становление" RelTransformsInto CaseAccusative "становление"
      "бытие превращается в становление" "бытие transforms into становление"
  , rel "бытие" "разум" RelNecessaryFor CaseGenitive "разум"
      "бытие необходим для разум" "бытие is necessary for разум"
  , rel "история" "память" RelIsA CaseNominative "память"
      "история есть память" "история is память"
  , rel "история" "время" RelPresupposes CaseAccusative "время"
      "история предполагает время" "история presupposes время"
  , rel "история" "правда" RelContrastsWith CaseInstrumental "правда"
      "история контрастирует с правда" "история contrasts with правда"
      `withVerb` "контрастирует с"
  , rel "история" "смысл" RelGives CaseAccusative "смысл"
      "история придаёт смысл" "история gives смысл"
  , rel "история" "идентичность" RelPreserves CaseAccusative "идентичность"
      "история сохраняет идентичность" "история preserves идентичность"
  , rel "язык" "разум" RelContrastsWith CaseInstrumental "разум"
      "язык контрастирует с разум" "язык contrasts with разум"
      `withVerb` "контрастирует с"
  , rel "язык" "сознание" RelContrastsWith CaseInstrumental "сознание"
      "язык контрастирует с сознание" "язык contrasts with сознание"
      `withVerb` "контрастирует с"
  , rel "язык" "молчание" RelContrastsWith CaseInstrumental "молчание"
      "язык контрастирует с молчание" "язык contrasts with молчание"
      `withVerb` "контрастирует с"
  , rel "язык" "истина" RelReliesOn CaseAccusative "истина"
      "язык опирается на истина" "язык relies on истина"
  , rel "язык" "бытие" RelReveals CaseAccusative "бытие"
      "язык обнаруживает бытие" "язык reveals бытие"
  , rel "воля" "свобода" RelContrastsWith CaseInstrumental "свобода"
      "воля контрастирует с свобода" "воля contrasts with свобода"
      `withVerb` "контрастирует с"
  , rel "воля" "долг" RelContrastsWith CaseInstrumental "долг"
      "воля контрастирует с долг" "воля contrasts with долг"
      `withVerb` "контрастирует с"
  , rel "воля" "разум" RelContrastsWith CaseInstrumental "разум"
      "воля контрастирует с разум" "воля contrasts with разум"
      `withVerb` "контрастирует с"
  , rel "воля" "решимость" RelIncludes CaseAccusative "решимость"
      "воля включает решимость" "воля includes решимость"
  , rel "смерть" "бытие" RelContrastsWith CaseInstrumental "бытие"
      "смерть контрастирует с бытие" "смерть contrasts with бытие"
      `withVerb` "контрастирует с"
  , rel "смерть" "смысл" RelContrastsWith CaseInstrumental "смысл"
      "смерть контрастирует с смысл" "смерть contrasts with смысл"
      `withVerb` "контрастирует с"
  , rel "смерть" "время" RelContrastsWith CaseInstrumental "время"
      "смерть контрастирует с время" "смерть contrasts with время"
      `withVerb` "контрастирует с"
  , rel "смерть" "страх" RelEvokes CaseAccusative "страх"
      "смерть вызывает страх" "смерть evokes страх"
  , rel "смерть" "любовь" RelContrastsWith CaseInstrumental "любовь"
      "смерть контрастирует с любовь" "смерть contrasts with любовь"
      `withVerb` "контрастирует с"
  , rel "одиночество" "любовь" RelContrastsWith CaseInstrumental "любовь"
      "одиночество контрастирует с любовь" "одиночество contrasts with любовь"
      `withVerb` "контрастирует с"
  , rel "одиночество" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "одиночество контрастирует с смерть" "одиночество contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "одиночество" "молчание" RelContrastsWith CaseInstrumental "молчание"
      "одиночество контрастирует с молчание" "одиночество contrasts with молчание"
      `withVerb` "контрастирует с"
  , rel "одиночество" "покой" RelContrastsWith CaseInstrumental "покой"
      "одиночество контрастирует с покой" "одиночество contrasts with покой"
      `withVerb` "контрастирует с"
  , rel "любовь" "доверие" RelSupports CaseAccusative "доверие"
      "любовь поддерживает доверие" "любовь supports доверие"
  , rel "любовь" "красота" RelContrastsWith CaseInstrumental "красота"
      "любовь контрастирует с красота" "любовь contrasts with красота"
      `withVerb` "контрастирует с"
  , rel "любовь" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "любовь контрастирует с смерть" "любовь contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "любовь" "смысл" RelGives CaseAccusative "смысл"
      "любовь придаёт смысл" "любовь gives смысл"
  , rel "труд" "ремонт" RelContrastsWith CaseInstrumental "ремонт"
      "труд контрастирует с ремонт" "труд contrasts with ремонт"
      `withVerb` "контрастирует с"
  , rel "труд" "воля" RelRequires CaseGenitive "воля"
      "труд требует воля" "труд requires воля"
  , rel "труд" "смысл" RelGives CaseAccusative "смысл"
      "труд придаёт смысл" "труд gives смысл"
  , rel "труд" "время" RelContrastsWith CaseInstrumental "время"
      "труд контрастирует с время" "труд contrasts with время"
      `withVerb` "контрастирует с"
  , rel "труд" "покой" RelNecessaryFor CaseGenitive "покой"
      "труд необходим для покой" "труд is necessary for покой"
  , rel "покой" "молчание" RelContrastsWith CaseInstrumental "молчание"
      "покой контрастирует с молчание" "покой contrasts with молчание"
      `withVerb` "контрастирует с"
  , rel "покой" "сознание" RelContrastsWith CaseInstrumental "сознание"
      "покой контрастирует с сознание" "покой contrasts with сознание"
      `withVerb` "контрастирует с"
  , rel "покой" "красота" RelContrastsWith CaseInstrumental "красота"
      "покой контрастирует с красота" "покой contrasts with красота"
      `withVerb` "контрастирует с"
  , rel "покой" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "покой контрастирует с смерть" "покой contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "власть" "справедливость" RelContrastsWith CaseInstrumental "справедливость"
      "власть контрастирует с справедливость" "власть contrasts with справедливость"
      `withVerb` "контрастирует с"
  , rel "власть" "ответственность" RelRequires CaseGenitive "ответственность"
      "власть требует ответственность" "власть requires ответственность"
  , rel "власть" "воля" RelContrastsWith CaseInstrumental "воля"
      "власть контрастирует с воля" "власть contrasts with воля"
      `withVerb` "контрастирует с"
  , rel "власть" "страх" RelEvokes CaseAccusative "страх"
      "власть вызывает страх" "власть evokes страх"
  , rel "правда" "истина" RelGives CaseAccusative "истина"
      "правда придаёт истина" "правда gives истина"
  , rel "правда" "память" RelContrastsWith CaseInstrumental "память"
      "правда контрастирует с память" "правда contrasts with память"
      `withVerb` "контрастирует с"
  , rel "правда" "история" RelContrastsWith CaseInstrumental "история"
      "правда контрастирует с история" "правда contrasts with история"
      `withVerb` "контрастирует с"
  , rel "правда" "молчание" RelContrastsWith CaseInstrumental "молчание"
      "правда контрастирует с молчание" "правда contrasts with молчание"
      `withVerb` "контрастирует с"
  , rel "молчание" "язык" RelContrastsWith CaseInstrumental "язык"
      "молчание контрастирует с язык" "молчание contrasts with язык"
      `withVerb` "контрастирует с"
  , rel "молчание" "покой" RelContrastsWith CaseInstrumental "покой"
      "молчание контрастирует с покой" "молчание contrasts with покой"
      `withVerb` "контрастирует с"
  , rel "молчание" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "молчание контрастирует с смерть" "молчание contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "молчание" "слушание" RelIncludes CaseAccusative "слушание"
      "молчание включает слушание" "молчание includes слушание"
  , rel "смысл" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "смысл контрастирует с смерть" "смысл contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "смысл" "время" RelContrastsWith CaseInstrumental "время"
      "смысл контрастирует с время" "смысл contrasts with время"
      `withVerb` "контрастирует с"
  , rel "смысл" "любовь" RelContrastsWith CaseInstrumental "любовь"
      "смысл контрастирует с любовь" "смысл contrasts with любовь"
      `withVerb` "контрастирует с"
  , rel "смысл" "труд" RelContrastsWith CaseInstrumental "труд"
      "смысл контрастирует с труд" "смысл contrasts with труд"
      `withVerb` "контрастирует с"
  , rel "смысл" "надежда" RelSupports CaseAccusative "надежда"
      "смысл поддерживает надежда" "смысл supports надежда"
  , rel "граница" "свобода" RelContrastsWith CaseInstrumental "свобода"
      "граница контрастирует с свобода" "граница contrasts with свобода"
      `withVerb` "контрастирует с"
  , rel "граница" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "граница контрастирует с смерть" "граница contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "граница" "идентичность" RelContrastsWith CaseInstrumental "идентичность"
      "граница контрастирует с идентичность" "граница contrasts with идентичность"
      `withVerb` "контрастирует с"
  , rel "граница" "язык" RelContrastsWith CaseInstrumental "язык"
      "граница контрастирует с язык" "граница contrasts with язык"
      `withVerb` "контрастирует с"
  , rel "цифра" "язык" RelContrastsWith CaseInstrumental "язык"
      "цифра контрастирует с язык" "цифра contrasts with язык"
      `withVerb` "контрастирует с"
  , rel "цифра" "истина" RelContrastsWith CaseInstrumental "истина"
      "цифра контрастирует с истина" "цифра contrasts with истина"
      `withVerb` "контрастирует с"
  , rel "цифра" "разум" RelContrastsWith CaseInstrumental "разум"
      "цифра контрастирует с разум" "цифра contrasts with разум"
      `withVerb` "контрастирует с"
  , rel "цифра" "красота" RelContrastsWith CaseInstrumental "красота"
      "цифра контрастирует с красота" "цифра contrasts with красота"
      `withVerb` "контрастирует с"
  , rel "идентичность" "память" RelContrastsWith CaseInstrumental "память"
      "идентичность контрастирует с память" "идентичность contrasts with память"
      `withVerb` "контрастирует с"
  , rel "идентичность" "история" RelContrastsWith CaseInstrumental "история"
      "идентичность контрастирует с история" "идентичность contrasts with история"
      `withVerb` "контрастирует с"
  , rel "идентичность" "язык" RelContrastsWith CaseInstrumental "язык"
      "идентичность контрастирует с язык" "идентичность contrasts with язык"
      `withVerb` "контрастирует с"
  , rel "идентичность" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "идентичность контрастирует с смерть" "идентичность contrasts with смерть"
      `withVerb` "контрастирует с"
  , rel "ремонт" "труд" RelContrastsWith CaseInstrumental "труд"
      "ремонт контрастирует с труд" "ремонт contrasts with труд"
      `withVerb` "контрастирует с"
  , rel "ремонт" "время" RelContrastsWith CaseInstrumental "время"
      "ремонт контрастирует с время" "ремонт contrasts with время"
      `withVerb` "контрастирует с"
  , rel "ремонт" "покой" RelNecessaryFor CaseGenitive "покой"
      "ремонт необходим для покой" "ремонт is necessary for покой"
  , rel "ремонт" "граница" RelContrastsWith CaseInstrumental "граница"
      "ремонт контрастирует с граница" "ремонт contrasts with граница"
      `withVerb` "контрастирует с"
  -- REVERSE MESH EDGES
  , rel "целостность_жизни" "смысл" RelEvokes CaseAccusative "смысл"
      "целостность жизни вызывает смысл" "целостность жизни evokes смысл"
  , rel "соотнесённость_с_целым" "смысл" RelDetermines CaseAccusative "смысл"
      "соотнесённость с целым определяет смысл" "соотнесённость с целым determines смысл"
  , rel "направление_вектора_жизни" "смысл" RelReliesOn CaseAccusative "смысл"
      "направление вектора жизни опирается на смысл" "направление вектора жизни relies on смысл"
  , rel "почему_а_не_зачем" "смысл" RelGives CaseAccusative "смысл"
      "почему а не зачем придаёт смысл" "почему а не зачем gives смысл"
  , rel "переживание_значимости" "смысл" RelReveals CaseAccusative "смысл"
      "переживание значимости обнаруживает смысл" "переживание значимости reveals смысл"
  , rel "различение_внутри_и_снаружи" "граница" RelStructures CaseAccusative "граница"
      "различение внутри и снаружи структурирует граница" "различение внутри и снаружи structures граница"
  , rel "условие_формы" "граница" RelUnifies CaseAccusative "граница"
      "условие формы объединяет граница" "условие формы unifies граница"
  , rel "предел_действия" "граница" RelDenotes CaseAccusative "граница"
      "предел действия обозначает граница" "предел действия denotes граница"
  , rel "контактная_поверхность" "граница" RelDirectedAt CaseAccusative "граница"
      "контактная поверхность направлена на граница" "контактная поверхность is directed at граница"
  , rel "защита_и_ограничение" "граница" RelSignals CasePrepositional "граница"
      "защита и ограничение сигнализирует о граница" "защита и ограничение signals граница"
  , rel "дискретность_и_точность" "цифра" RelContrastsWith CaseInstrumental "цифра"
      "дискретность и точность контрастирует с цифра" "дискретность и точность contrasts with цифра"
  , rel "формализация_опыта" "цифра" RelBuiltThrough CaseAccusative "цифра"
      "формализация опыта строится через цифра" "формализация опыта is built through цифра"
  , rel "утрата_контекста" "цифра" RelPreserves CaseAccusative "цифра"
      "утрата контекста сохраняет цифра" "утрата контекста preserves цифра"
  , rel "сжимает_мир_до_значения" "цифра" RelOrientsToward CaseAccusative "цифра"
      "сжимает мир до значения ориентирует на цифра" "сжимает мир до значения orients toward цифра"
  , rel "маскировка_качества_количеством" "цифра" RelPrescribes CaseAccusative "цифра"
      "маскировка качества количеством предписывает цифра" "маскировка качества количеством prescribes цифра"
  , rel "преемственность_я" "идентичность" RelNotReducibleTo CaseDative "идентичность"
      "преемственность я не сводится к идентичность" "преемственность я is not reducible to идентичность"
  , rel "ответ_на_вопрос_кто_я" "идентичность" RelNecessaryFor CaseGenitive "идентичность"
      "ответ на вопрос кто я необходим для идентичность" "ответ на вопрос кто я is necessary for идентичность"
  , rel "нарратив_о_себе" "идентичность" RelTransforms CaseAccusative "идентичность"
      "нарратив о себе преобразует идентичность" "нарратив о себе transforms идентичность"
  , rel "совпадение_с_собой" "идентичность" RelTransformsInto CaseAccusative "идентичность"
      "совпадение с собой превращается в идентичность" "совпадение с собой transforms into идентичность"
  , rel "разрыв_и_восстановление" "идентичность" RelSupports CaseAccusative "идентичность"
      "разрыв и восстановление поддерживает идентичность" "разрыв и восстановление supports идентичность"
  , rel "восстановление_функции" "ремонт" RelPresupposes CaseAccusative "ремонт"
      "восстановление функции предполагает ремонт" "восстановление функции presupposes ремонт"
  , rel "диагностика_поломки" "ремонт" RelMeans CaseAccusative "ремонт"
      "диагностика поломки означает ремонт" "диагностика поломки means ремонт"
  , rel "различение_починить_и_заменить" "ремонт" RelRequires CaseGenitive "ремонт"
      "различение починить и заменить требует ремонт" "различение починить и заменить requires ремонт"
  , rel "возвращение_к_работоспособности" "ремонт" RelIncludes CaseAccusative "ремонт"
      "возвращение к работоспособности включает ремонт" "возвращение к работоспособности includes ремонт"
  , rel "усилие_против_энтропии" "ремонт" RelIsA CaseNominative "ремонт"
      "усилие против энтропии есть ремонт" "усилие против энтропии is ремонт"
  , rel "осознанность_выбора" "свобода" RelEvokes CaseAccusative "свобода"
      "осознанность выбора вызывает свобода" "осознанность выбора evokes свобода"
  , rel "автономия_суждения" "свобода" RelDetermines CaseAccusative "свобода"
      "автономия суждения определяет свобода" "автономия суждения determines свобода"
  , rel "самоопределение" "свобода" RelReliesOn CaseAccusative "свобода"
      "самоопределение опирается на свобода" "самоопределение relies on свобода"
  , rel "отсутствие_принуждения" "свобода" RelGives CaseAccusative "свобода"
      "отсутствие принуждения придаёт свобода" "отсутствие принуждения gives свобода"
  , rel "пространство_возможностей" "свобода" RelReveals CaseAccusative "свобода"
      "пространство возможностей обнаруживает свобода" "пространство возможностей reveals свобода"
  , rel "объективность" "истина" RelStructures CaseAccusative "истина"
      "объективность структурирует истина" "объективность structures истина"
  , rel "доказательство" "истина" RelUnifies CaseAccusative "истина"
      "доказательство объединяет истина" "доказательство unifies истина"
  , rel "когерентность" "истина" RelDenotes CaseAccusative "истина"
      "когерентность обозначает истина" "когерентность denotes истина"
  , rel "открытость_проверке" "истина" RelDirectedAt CaseAccusative "истина"
      "открытость проверке направлена на истина" "открытость проверке is directed at истина"
  , rel "независимость_от_наблюдателя" "истина" RelSignals CasePrepositional "истина"
      "независимость от наблюдателя сигнализирует о истина" "независимость от наблюдателя signals истина"
  , rel "идентичность_через_время" "память" RelContrastsWith CaseInstrumental "память"
      "идентичность через время контрастирует с память" "идентичность через время contrasts with память"
  , rel "след_прошлого" "память" RelBuiltThrough CaseAccusative "память"
      "след прошлого строится через память" "след прошлого is built through память"
  , rel "забывание_как_условие" "память" RelPreserves CaseAccusative "память"
      "забывание как условие сохраняет память" "забывание как условие preserves память"
  , rel "узнавание" "память" RelOrientsToward CaseAccusative "память"
      "узнавание ориентирует на память" "узнавание orients toward память"
  , rel "привычка_и_рутина" "память" RelPrescribes CaseAccusative "память"
      "привычка и рутина предписывает память" "привычка и рутина prescribes память"
  , rel "интенциональность" "сознание" RelNotReducibleTo CaseDative "сознание"
      "интенциональность не сводится к сознание" "интенциональность is not reducible to сознание"
  , rel "качественность_опыта" "сознание" RelNecessaryFor CaseGenitive "сознание"
      "качественность опыта необходим для сознание" "качественность опыта is necessary for сознание"
  , rel "единство_поля_опыта" "сознание" RelTransforms CaseAccusative "сознание"
      "единство поля опыта преобразует сознание" "единство поля опыта transforms сознание"
  , rel "присутствие" "сознание" RelTransformsInto CaseAccusative "сознание"
      "присутствие превращается в сознание" "присутствие transforms into сознание"
  , rel "поток_переживаний" "сознание" RelSupports CaseAccusative "сознание"
      "поток переживаний поддерживает сознание" "поток переживаний supports сознание"
  , rel "акт_доверия" "вера" RelPresupposes CaseAccusative "вера"
      "акт доверия предполагает вера" "акт доверия presupposes вера"
  , rel "обоснованность_не_доказательством" "вера" RelMeans CaseAccusative "вера"
      "обоснованность не доказательством означает вера" "обоснованность не доказательством means вера"
  , rel "готовность_к_риску" "вера" RelRequires CaseGenitive "вера"
      "готовность к риску требует вера" "готовность к риску requires вера"
  , rel "верность" "вера" RelIncludes CaseAccusative "вера"
      "верность включает вера" "верность includes вера"
  , rel "прыжок_за_горизонт" "вера" RelIsA CaseNominative "вера"
      "прыжок за горизонт есть вера" "прыжок за горизонт is вера"
  , rel "гармония_формы" "красота" RelEvokes CaseAccusative "красота"
      "гармония формы вызывает красота" "гармония формы evokes красота"
  , rel "соразмерность_частей" "красота" RelDetermines CaseAccusative "красота"
      "соразмерность частей определяет красота" "соразмерность частей determines красота"
  , rel "праздность_созерцания" "красота" RelReliesOn CaseAccusative "красота"
      "праздность созерцания опирается на красота" "праздность созерцания relies on красота"
  , rel "превосходство_над_полезным" "красота" RelGives CaseAccusative "красота"
      "превосходство над полезным придаёт красота" "превосходство над полезным gives красота"
  , rel "мгновение_и_вечность" "красота" RelReveals CaseAccusative "красота"
      "мгновение и вечность обнаруживает красота" "мгновение и вечность reveals красота"
  , rel "долженствование" "долг" RelStructures CaseAccusative "долг"
      "долженствование структурирует долг" "долженствование structures долг"
  , rel "приоритет_над_желанием" "долг" RelUnifies CaseAccusative "долг"
      "приоритет над желанием объединяет долг" "приоритет над желанием unifies долг"
  , rel "внутренний_закон" "долг" RelDenotes CaseAccusative "долг"
      "внутренний закон обозначает долг" "внутренний закон denotes долг"
  , rel "совесть_как_свидетель" "долг" RelDirectedAt CaseAccusative "долг"
      "совесть как свидетель направлена на долг" "совесть как свидетель is directed at долг"
  , rel "исполнение_обещания" "долг" RelSignals CasePrepositional "долг"
      "исполнение обещания сигнализирует о долг" "исполнение обещания signals долг"
  , rel "риск_уязвимости" "доверие" RelContrastsWith CaseInstrumental "доверие"
      "риск уязвимости контрастирует с доверие" "риск уязвимости contrasts with доверие"
  , rel "опора_на_другого" "доверие" RelBuiltThrough CaseAccusative "доверие"
      "опора на другого строится через доверие" "опора на другого is built through доверие"
  , rel "проверка_опытом" "доверие" RelPreserves CaseAccusative "доверие"
      "проверка опытом сохраняет доверие" "проверка опытом preserves доверие"
  , rel "прозрачность_намерений" "доверие" RelOrientsToward CaseAccusative "доверие"
      "прозрачность намерений ориентирует на доверие" "прозрачность намерений orients toward доверие"
  , rel "разрыв_и_восстановление_доверия" "доверие" RelPrescribes CaseAccusative "доверие"
      "разрыв и восстановление доверия предписывает доверие" "разрыв и восстановление доверия prescribes доверие"
  , rel "ожидание_угрозы" "страх" RelNotReducibleTo CaseDative "страх"
      "ожидание угрозы не сводится к страх" "ожидание угрозы is not reducible to страх"
  , rel "сигнал_опасности" "страх" RelNecessaryFor CaseGenitive "страх"
      "сигнал опасности необходим для страх" "сигнал опасности is necessary for страх"
  , rel "паралич_или_действие" "страх" RelTransforms CaseAccusative "страх"
      "паралич или действие преобразует страх" "паралич или действие transforms страх"
  , rel "перед_неизвестным" "страх" RelTransformsInto CaseAccusative "страх"
      "перед неизвестным превращается в страх" "перед неизвестным transforms into страх"
  , rel "защитная_реакция" "страх" RelSupports CaseAccusative "страх"
      "защитная реакция поддерживает страх" "защитная реакция supports страх"
  , rel "ориентация_на_будущее" "надежда" RelPresupposes CaseAccusative "надежда"
      "ориентация на будущее предполагает надежда" "ориентация на будущее presupposes надежда"
  , rel "наперекор_очевидности" "надежда" RelMeans CaseAccusative "надежда"
      "наперекор очевидности означает надежда" "наперекор очевидности means надежда"
  , rel "утешение_и_мотив" "надежда" RelRequires CaseGenitive "надежда"
      "утешение и мотив требует надежда" "утешение и мотив requires надежда"
  , rel "обещание_себе" "надежда" RelIncludes CaseAccusative "надежда"
      "обещание себе включает надежда" "обещание себе includes надежда"
  , rel "пустота_или_вектор" "надежда" RelIsA CaseNominative "надежда"
      "пустота или вектор есть надежда" "пустота или вектор is надежда"
  , rel "мера_и_соразмерность" "справедливость" RelEvokes CaseAccusative "справедливость"
      "мера и соразмерность вызывает справедливость" "мера и соразмерность evokes справедливость"
  , rel "беспристрастность" "справедливость" RelDetermines CaseAccusative "справедливость"
      "беспристрастность определяет справедливость" "беспристрастность determines справедливость"
  , rel "воздаяние_по_заслугам" "справедливость" RelReliesOn CaseAccusative "справедливость"
      "воздаяние по заслугам опирается на справедливость" "воздаяние по заслугам relies on справедливость"
  , rel "процедура_и_результат" "справедливость" RelGives CaseAccusative "справедливость"
      "процедура и результат придаёт справедливость" "процедура и результат gives справедливость"
  , rel "признание_прав_другого" "справедливость" RelReveals CaseAccusative "справедливость"
      "признание прав другого обнаруживает справедливость" "признание прав другого reveals справедливость"
  , rel "длительность" "время" RelStructures CaseAccusative "время"
      "длительность структурирует время" "длительность structures время"
  , rel "настоящее_как_точка" "время" RelUnifies CaseAccusative "время"
      "настоящее как точка объединяет время" "настоящее как точка unifies время"
  , rel "будущее_как_возможность" "время" RelDenotes CaseAccusative "время"
      "будущее как возможность обозначает время" "будущее как возможность denotes время"
  , rel "цикличность_и_линейность" "время" RelDirectedAt CaseAccusative "время"
      "цикличность и линейность направлена на время" "цикличность и линейность is directed at время"
  , rel "темп_и_ритм" "время" RelSignals CasePrepositional "время"
      "темп и ритм сигнализирует о время" "темп и ритм signals время"
  , rel "логическое_умозаключение" "разум" RelContrastsWith CaseInstrumental "разум"
      "логическое умозаключение контрастирует с разум" "логическое умозаключение contrasts with разум"
  , rel "способность_к_обобщению" "разум" RelBuiltThrough CaseAccusative "разум"
      "способность к обобщению строится через разум" "способность к обобщению is built through разум"
  , rel "различение_истинного_и_ложного" "разум" RelPreserves CaseAccusative "разум"
      "различение истинного и ложного сохраняет разум" "различение истинного и ложного preserves разум"
  , rel "критика_и_сомнение" "разум" RelOrientsToward CaseAccusative "разум"
      "критика и сомнение ориентирует на разум" "критика и сомнение orients toward разум"
  , rel "порядок_мысли" "разум" RelPrescribes CaseAccusative "разум"
      "порядок мысли предписывает разум" "порядок мысли prescribes разум"
  , rel "факт_присутствия" "бытие" RelNotReducibleTo CaseDative "бытие"
      "факт присутствия не сводится к бытие" "факт присутствия is not reducible to бытие"
  , rel "различение_сущего_и_ничто" "бытие" RelNecessaryFor CaseGenitive "бытие"
      "различение сущего и ничто необходим для бытие" "различение сущего и ничто is necessary for бытие"
  , rel "основание_всего" "бытие" RelTransforms CaseAccusative "бытие"
      "основание всего преобразует бытие" "основание всего transforms бытие"
  , rel "необходимость_и_случайность" "бытие" RelTransformsInto CaseAccusative "бытие"
      "необходимость и случайность превращается в бытие" "необходимость и случайность transforms into бытие"
  , rel "становление" "бытие" RelSupports CaseAccusative "бытие"
      "становление поддерживает бытие" "становление supports бытие"
  , rel "память_коллектива" "история" RelPresupposes CaseAccusative "история"
      "память коллектива предполагает история" "память коллектива presupposes история"
  , rel "интерпретация_прошлого" "история" RelMeans CaseAccusative "история"
      "интерпретация прошлого означает история" "интерпретация прошлого means история"
  , rel "урок_и_предупреждение" "история" RelRequires CaseGenitive "история"
      "урок и предупреждение требует история" "урок и предупреждение requires история"
  , rel "нарратив_и_факт" "история" RelIncludes CaseAccusative "история"
      "нарратив и факт включает история" "нарратив и факт includes история"
  , rel "причина_и_следствие" "история" RelIsA CaseNominative "история"
      "причина и следствие есть история" "причина и следствие is история"
  , rel "структура_значения" "язык" RelEvokes CaseAccusative "язык"
      "структура значения вызывает язык" "структура значения evokes язык"
  , rel "граница_выразимого" "язык" RelDetermines CaseAccusative "язык"
      "граница выразимого определяет язык" "граница выразимого determines язык"
  , rel "конвенция_и_произвол" "язык" RelReliesOn CaseAccusative "язык"
      "конвенция и произвол опирается на язык" "конвенция и произвол relies on язык"
  , rel "переводимость_и_непереводимость" "язык" RelGives CaseAccusative "язык"
      "переводимость и непереводимость придаёт язык" "переводимость и непереводимость gives язык"
  , rel "метафора_и_буква" "язык" RelReveals CaseAccusative "язык"
      "метафора и буква обнаруживает язык" "метафора и буква reveals язык"
  , rel "направленность_усилия" "воля" RelStructures CaseAccusative "воля"
      "направленность усилия структурирует воля" "направленность усилия structures воля"
  , rel "выбор_цели" "воля" RelUnifies CaseAccusative "воля"
      "выбор цели объединяет воля" "выбор цели unifies воля"
  , rel "преодоление_сопротивления" "воля" RelDenotes CaseAccusative "воля"
      "преодоление сопротивления обозначает воля" "преодоление сопротивления denotes воля"
  , rel "решимость" "воля" RelDirectedAt CaseAccusative "воля"
      "решимость направлена на воля" "решимость is directed at воля"
  , rel "свобода_и_необходимость" "воля" RelSignals CasePrepositional "воля"
      "свобода и необходимость сигнализирует о воля" "свобода и необходимость signals воля"
  , rel "предел_существования" "смерть" RelContrastsWith CaseInstrumental "смерть"
      "предел существования контрастирует с смерть" "предел существования contrasts with смерть"
  , rel "осмысление_конечности" "смерть" RelBuiltThrough CaseAccusative "смерть"
      "осмысление конечности строится через смерть" "осмысление конечности is built through смерть"
  , rel "уравнивание_всех" "смерть" RelPreserves CaseAccusative "смерть"
      "уравнивание всех сохраняет смерть" "уравнивание всех preserves смерть"
  , rel "страх_и_принятие" "смерть" RelOrientsToward CaseAccusative "смерть"
      "страх и принятие ориентирует на смерть" "страх и принятие orients toward смерть"
  , rel "граница_смысла" "смерть" RelPrescribes CaseAccusative "смерть"
      "граница смысла предписывает смерть" "граница смысла prescribes смерть"
  , rel "отсутствие_контакта" "одиночество" RelNotReducibleTo CaseDative "одиночество"
      "отсутствие контакта не сводится к одиночество" "отсутствие контакта is not reducible to одиночество"
  , rel "встреча_с_собой" "одиночество" RelNecessaryFor CaseGenitive "одиночество"
      "встреча с собой необходим для одиночество" "встреча с собой is necessary for одиночество"
  , rel "изоляция_или_уединение" "одиночество" RelTransforms CaseAccusative "одиночество"
      "изоляция или уединение преобразует одиночество" "изоляция или уединение transforms одиночество"
  , rel "тишина_и_пустота" "одиночество" RelTransformsInto CaseAccusative "одиночество"
      "тишина и пустота превращается в одиночество" "тишина и пустота transforms into одиночество"
  , rel "потребность_в_другом" "одиночество" RelSupports CaseAccusative "одиночество"
      "потребность в другом поддерживает одиночество" "потребность в другом supports одиночество"
  , rel "признание_ценности_другого" "любовь" RelPresupposes CaseAccusative "любовь"
      "признание ценности другого предполагает любовь" "признание ценности другого presupposes любовь"
  , rel "преодоление_эгоцентризма" "любовь" RelMeans CaseAccusative "любовь"
      "преодоление эгоцентризма означает любовь" "преодоление эгоцентризма means любовь"
  , rel "дар_без_расчёта" "любовь" RelRequires CaseGenitive "любовь"
      "дар без расчёта требует любовь" "дар без расчёта requires любовь"
  , rel "уязвимость_и_близость" "любовь" RelIncludes CaseAccusative "любовь"
      "уязвимость и близость включает любовь" "уязвимость и близость includes любовь"
  , rel "вечность_в_мгновении" "любовь" RelIsA CaseNominative "любовь"
      "вечность в мгновении есть любовь" "вечность в мгновении is любовь"
  , rel "преобразование_материи" "труд" RelEvokes CaseAccusative "труд"
      "преобразование материи вызывает труд" "преобразование материи evokes труд"
  , rel "усилие_и_результат" "труд" RelDetermines CaseAccusative "труд"
      "усилие и результат определяет труд" "усилие и результат determines труд"
  , rel "разделение_и_кооперация" "труд" RelReliesOn CaseAccusative "труд"
      "разделение и кооперация опирается на труд" "разделение и кооперация relies on труд"
  , rel "навык_и_мастерство" "труд" RelGives CaseAccusative "труд"
      "навык и мастерство придаёт труд" "навык и мастерство gives труд"
  , rel "усталость_и_удовлетворение" "труд" RelReveals CaseAccusative "труд"
      "усталость и удовлетворение обнаруживает труд" "усталость и удовлетворение reveals труд"
  , rel "пауза_в_действии" "покой" RelStructures CaseAccusative "покой"
      "пауза в действии структурирует покой" "пауза в действии structures покой"
  , rel "созерцание_и_присутствие" "покой" RelUnifies CaseAccusative "покой"
      "созерцание и присутствие объединяет покой" "созерцание и присутствие unifies покой"
  , rel "глубина_тишины" "покой" RelDenotes CaseAccusative "покой"
      "глубина тишины обозначает покой" "глубина тишины denotes покой"
  , rel "пустота_как_полнота" "покой" RelDirectedAt CaseAccusative "покой"
      "пустота как полнота направлена на покой" "пустота как полнота is directed at покой"
  , rel "остановка_и_осмысление" "покой" RelSignals CasePrepositional "покой"
      "остановка и осмысление сигнализирует о покой" "остановка и осмысление signals покой"
  , rel "асимметрия_отношений" "власть" RelContrastsWith CaseInstrumental "власть"
      "асимметрия отношений контрастирует с власть" "асимметрия отношений contrasts with власть"
  , rel "принуждение_и_авторитет" "власть" RelBuiltThrough CaseAccusative "власть"
      "принуждение и авторитет строится через власть" "принуждение и авторитет is built through власть"
  , rel "ответственность_власти" "власть" RelPreserves CaseAccusative "власть"
      "ответственность власти сохраняет власть" "ответственность власти preserves власть"
  , rel "делегирование_и_контроль" "власть" RelOrientsToward CaseAccusative "власть"
      "делегирование и контроль ориентирует на власть" "делегирование и контроль orients toward власть"
  , rel "насилие_или_забота" "власть" RelPrescribes CaseAccusative "власть"
      "насилие или забота предписывает власть" "насилие или забота prescribes власть"
  , rel "свидетельство" "правда" RelNotReducibleTo CaseDative "правда"
      "свидетельство не сводится к правда" "свидетельство is not reducible to правда"
  , rel "искренность_рассказа" "правда" RelNecessaryFor CaseGenitive "правда"
      "искренность рассказа необходим для правда" "искренность рассказа is necessary for правда"
  , rel "частная_перспектива" "правда" RelTransforms CaseAccusative "правда"
      "частная перспектива преобразует правда" "частная перспектива transforms правда"
  , rel "долг_памяти" "правда" RelTransformsInto CaseAccusative "правда"
      "долг памяти превращается в правда" "долг памяти transforms into правда"
  , rel "против_забвения" "правда" RelSupports CaseAccusative "правда"
      "против забвения поддерживает правда" "против забвения supports правда"
  , rel "предел_слова" "молчание" RelPresupposes CaseAccusative "молчание"
      "предел слова предполагает молчание" "предел слова presupposes молчание"
  , rel "присутствие_без_выражения" "молчание" RelMeans CaseAccusative "молчание"
      "присутствие без выражения означает молчание" "присутствие без выражения means молчание"
  , rel "глубина_невыразимого" "молчание" RelRequires CaseGenitive "молчание"
      "глубина невыразимого требует молчание" "глубина невыразимого requires молчание"
  , rel "слушание" "молчание" RelIncludes CaseAccusative "молчание"
      "слушание включает молчание" "слушание includes молчание"
  , rel "пауза_и_смысл" "молчание" RelIsA CaseNominative "молчание"
      "пауза и смысл есть молчание" "пауза и смысл is молчание"
  , rel "готовность_к_ответу" "ответственность" RelEvokes CaseAccusative "ответственность"
      "готовность к ответу вызывает ответственность" "готовность к ответу evokes ответственность"
  , rel "свобода_как_условие" "ответственность" RelDetermines CaseAccusative "ответственность"
      "свобода как условие определяет ответственность" "свобода как условие determines ответственность"
  , rel "вина_и_заслуга" "ответственность" RelReliesOn CaseAccusative "ответственность"
      "вина и заслуга опирается на ответственность" "вина и заслуга relies on ответственность"
  , rel "пределы_контроля" "ответственность" RelGives CaseAccusative "ответственность"
      "пределы контроля придаёт ответственность" "пределы контроля gives ответственность"
  , rel "ответ_перед_другими" "ответственность" RelReveals CaseAccusative "ответственность"
      "ответ перед другими обнаруживает ответственность" "ответ перед другими reveals ответственность"
  , rel "отсутствие_основания" "произвол" RelStructures CaseAccusative "произвол"
      "отсутствие основания структурирует произвол" "отсутствие основания structures произвол"
  , rel "каприз_и_случайность" "произвол" RelUnifies CaseAccusative "произвол"
      "каприз и случайность объединяет произвол" "каприз и случайность unifies произвол"
  , rel "игнорирование_последствий" "произвол" RelDenotes CaseAccusative "произвол"
      "игнорирование последствий обозначает произвол" "игнорирование последствий denotes произвол"
  , rel "псевдосвобода" "произвол" RelDirectedAt CaseAccusative "произвол"
      "псевдосвобода направлена на произвол" "псевдосвобода is directed at произвол"
  , rel "разрушение_порядка" "произвол" RelSignals CasePrepositional "произвол"
      "разрушение порядка сигнализирует о произвол" "разрушение порядка signals произвол"
  , rel "частное_суждение" "мнение" RelContrastsWith CaseInstrumental "мнение"
      "частное суждение контрастирует с мнение" "частное суждение contrasts with мнение"
  , rel "обоснованность_и_вес" "мнение" RelBuiltThrough CaseAccusative "мнение"
      "обоснованность и вес строится через мнение" "обоснованность и вес is built through мнение"
  , rel "открытость_пересмотру" "мнение" RelPreserves CaseAccusative "мнение"
      "открытость пересмотру сохраняет мнение" "открытость пересмотру preserves мнение"
  , rel "выражение_позиции" "мнение" RelOrientsToward CaseAccusative "мнение"
      "выражение позиции ориентирует на мнение" "выражение позиции orients toward мнение"
  , rel "различение_с_истиной" "мнение" RelPrescribes CaseAccusative "мнение"
      "различение с истиной предписывает мнение" "различение с истиной prescribes мнение"
  , rel "актуализация_прошлого" "воспоминание" RelNotReducibleTo CaseDative "воспоминание"
      "актуализация прошлого не сводится к воспоминание" "актуализация прошлого is not reducible to воспоминание"
  , rel "эмоциональная_окраска" "воспоминание" RelNecessaryFor CaseGenitive "воспоминание"
      "эмоциональная окраска необходим для воспоминание" "эмоциональная окраска is necessary for воспоминание"
  , rel "достоверность_и_искажение" "воспоминание" RelTransforms CaseAccusative "воспоминание"
      "достоверность и искажение преобразует воспоминание" "достоверность и искажение transforms воспоминание"
  , rel "связь_времён" "воспоминание" RelTransformsInto CaseAccusative "воспоминание"
      "связь времён превращается в воспоминание" "связь времён transforms into воспоминание"
  , rel "повторное_переживание" "воспоминание" RelSupports CaseAccusative "воспоминание"
      "повторное переживание поддерживает воспоминание" "повторное переживание supports воспоминание"
  , rel "рефлексия_над_собой" "самосознание" RelPresupposes CaseAccusative "самосознание"
      "рефлексия над собой предполагает самосознание" "рефлексия над собой presupposes самосознание"
  , rel "наблюдение_за_состояниями" "самосознание" RelMeans CaseAccusative "самосознание"
      "наблюдение за состояниями означает самосознание" "наблюдение за состояниями means самосознание"
  , rel "идентификация_с_собой" "самосознание" RelRequires CaseGenitive "самосознание"
      "идентификация с собой требует самосознание" "идентификация с собой requires самосознание"
  , rel "различение_я_и_не_я" "самосознание" RelIncludes CaseAccusative "самосознание"
      "различение я и не я включает самосознание" "различение я и не я includes самосознание"
  , rel "самооценка" "самосознание" RelIsA CaseNominative "самосознание"
      "самооценка есть самосознание" "самооценка is самосознание"
  -- CONCEPT-CONCEPT EDGES
  , rel "осознанность_выбора" "самоопределение" RelPresupposes CaseAccusative "самоопределение"
      "осознанность выбора предполагает самоопределение" "осознанность выбора presupposes самоопределение"
  , rel "объективность" "доказательство" RelRequires CaseGenitive "доказательство"
      "объективность требует доказательство" "объективность requires доказательство"
  , rel "доказательство" "когерентность" RelIncludes CaseAccusative "когерентность"
      "доказательство включает когерентность" "доказательство includes когерентность"
  , rel "идентичность_через_время" "след_прошлого" RelIncludes CaseAccusative "след прошлого"
      "идентичность через время включает след прошлого" "идентичность через время includes след прошлого"
  , rel "интенциональность" "присутствие" RelIsA CaseNominative "присутствие"
      "интенциональность есть присутствие" "интенциональность is присутствие"
  , rel "акт_доверия" "готовность_к_риску" RelRequires CaseGenitive "готовность к риску"
      "акт доверия требует готовность к риску" "акт доверия requires готовность к риску"
  , rel "гармония_формы" "соразмерность_частей" RelRequires CaseGenitive "соразмерность частей"
      "гармония формы требует соразмерность частей" "гармония формы requires соразмерность частей"
  , rel "долженствование" "приоритет_над_желанием" RelMeans CaseAccusative "приоритет над желанием"
      "долженствование означает приоритет над желанием" "долженствование means приоритет над желанием"
  , rel "риск_уязвимости" "опора_на_другого" RelPresupposes CaseAccusative "опора на другого"
      "риск уязвимости предполагает опора на другого" "риск уязвимости presupposes опора на другого"
  , rel "ожидание_угрозы" "сигнал_опасности" RelMeans CaseAccusative "сигнал опасности"
      "ожидание угрозы означает сигнал опасности" "ожидание угрозы means сигнал опасности"
  , rel "ориентация_на_будущее" "наперекор_очевидности" RelBuiltThrough CaseAccusative "наперекор очевидности"
      "ориентация на будущее строится через наперекор очевидности" "ориентация на будущее is built through наперекор очевидности"
  , rel "мера_и_соразмерность" "беспристрастность" RelRequires CaseGenitive "беспристрастность"
      "мера и соразмерность требует беспристрастность" "мера и соразмерность requires беспристрастность"
  , rel "длительность" "настоящее_как_точка" RelIncludes CaseAccusative "настоящее как точка"
      "длительность включает настоящее как точка" "длительность includes настоящее как точка"
  , rel "логическое_умозаключение" "способность_к_обобщению" RelIncludes CaseAccusative "способность к обобщению"
      "логическое умозаключение включает способность к обобщению" "логическое умозаключение includes способность к обобщению"
  , rel "факт_присутствия" "становление" RelTransformsInto CaseAccusative "становление"
      "факт присутствия превращается в становление" "факт присутствия transforms into становление"
  , rel "память_коллектива" "интерпретация_прошлого" RelIncludes CaseAccusative "интерпретация прошлого"
      "память коллектива включает интерпретация прошлого" "память коллектива includes интерпретация прошлого"
  , rel "структура_значения" "граница_выразимого" RelDenotes CaseAccusative "граница выразимого"
      "структура значения обозначает граница выразимого" "структура значения denotes граница выразимого"
  , rel "направленность_усилия" "выбор_цели" RelDenotes CaseAccusative "выбор цели"
      "направленность усилия обозначает выбор цели" "направленность усилия denotes выбор цели"
  , rel "предел_существования" "осмысление_конечности" RelEvokes CaseAccusative "осмысление конечности"
      "предел существования вызывает осмысление конечности" "предел существования evokes осмысление конечности"
  , rel "отсутствие_контакта" "встреча_с_собой" RelEvokes CaseAccusative "встреча с собой"
      "отсутствие контакта вызывает встреча с собой" "отсутствие контакта evokes встреча с собой"
  , rel "признание_ценности_другого" "преодоление_эгоцентризма" RelRequires CaseGenitive "преодоление эгоцентризма"
      "признание ценности другого требует преодоление эгоцентризма" "признание ценности другого requires преодоление эгоцентризма"
  , rel "преобразование_материи" "усилие_и_результат" RelIncludes CaseAccusative "усилие и результат"
      "преобразование материи включает усилие и результат" "преобразование материи includes усилие и результат"
  , rel "пауза_в_действии" "созерцание_и_присутствие" RelIncludes CaseAccusative "созерцание и присутствие"
      "пауза в действии включает созерцание и присутствие" "пауза в действии includes созерцание и присутствие"
  , rel "асимметрия_отношений" "принуждение_и_авторитет" RelIncludes CaseAccusative "принуждение и авторитет"
      "асимметрия отношений включает принуждение и авторитет" "асимметрия отношений includes принуждение и авторитет"
  , rel "свидетельство" "искренность_рассказа" RelRequires CaseGenitive "искренность рассказа"
      "свидетельство требует искренность рассказа" "свидетельство requires искренность рассказа"
  , rel "предел_слова" "присутствие_без_выражения" RelIncludes CaseAccusative "присутствие без выражения"
      "предел слова включает присутствие без выражения" "предел слова includes присутствие без выражения"
  , rel "готовность_к_ответу" "свобода_как_условие" RelPresupposes CaseAccusative "свобода как условие"
      "готовность к ответу предполагает свобода как условие" "готовность к ответу presupposes свобода как условие"
  , rel "отсутствие_основания" "каприз_и_случайность" RelMeans CaseAccusative "каприз и случайность"
      "отсутствие основания означает каприз и случайность" "отсутствие основания means каприз и случайность"
  , rel "частное_суждение" "обоснованность_и_вес" RelIncludes CaseAccusative "обоснованность и вес"
      "частное суждение включает обоснованность и вес" "частное суждение includes обоснованность и вес"
  , rel "актуализация_прошлого" "эмоциональная_окраска" RelEvokes CaseAccusative "эмоциональная окраска"
      "актуализация прошлого вызывает эмоциональная окраска" "актуализация прошлого evokes эмоциональная окраска"
  , rel "рефлексия_над_собой" "наблюдение_за_состояниями" RelIncludes CaseAccusative "наблюдение за состояниями"
      "рефлексия над собой включает наблюдение за состояниями" "рефлексия над собой includes наблюдение за состояниями"
  , rel "целостность_жизни" "соотнесённость_с_целым" RelIncludes CaseAccusative "соотнесённость с целым"
      "целостность жизни включает соотнесённость с целым" "целостность жизни includes соотнесённость с целым"
  , rel "различение_внутри_и_снаружи" "условие_формы" RelIncludes CaseAccusative "условие формы"
      "различение внутри и снаружи включает условие формы" "различение внутри и снаружи includes условие формы"
  , rel "дискретность_и_точность" "формализация_опыта" RelIncludes CaseAccusative "формализация опыта"
      "дискретность и точность включает формализация опыта" "дискретность и точность includes формализация опыта"
  , rel "преемственность_я" "нарратив_о_себе" RelBuiltThrough CaseAccusative "нарратив о себе"
      "преемственность я строится через нарратив о себе" "преемственность я is built through нарратив о себе"
  , rel "восстановление_функции" "диагностика_поломки" RelRequires CaseGenitive "диагностика поломки"
      "восстановление функции требует диагностика поломки" "восстановление функции requires диагностика поломки"
  -- ============================================================
  -- Cross-domain bridge relations (L2 expansion)
  -- Each bridge connects a domain concept to an L1 topic
  -- ============================================================
  , rel "психика" "сознание" RelIncludes CaseAccusative "сознание"
      "психика включает сознание" "psyche includes consciousness"
  , rel "психика" "память" RelIncludes CaseAccusative "память"
      "психика включает память" "psyche includes memory"
  , rel "эмоция" "страх" RelExpresses CaseAccusative "страх"
      "эмоция выражает страх" "emotion expresses fear"
  , rel "эмоция" "любовь" RelExpresses CaseAccusative "любовь"
      "эмоция выражает любовь" "emotion expresses love"
  , rel "доказательство" "истина" RelSupports CaseAccusative "истину"
      "доказательство поддерживает истину" "proof supports truth"
  , rel "эксперимент" "истина" RelVerifiedBy CaseAccusative "истину"
      "эксперимент проверяет истину" "experiment verifies truth"
  , rel "нейрон" "сознание" RelRelatedTo CaseInstrumental "с сознанием"
      "нейрон связан с сознанием" "neuron is related to consciousness"
  , rel "логика" "разум" RelStructures CaseAccusative "разум"
      "логика структурирует разум" "logic structures reason"
  , rel "аксиома" "вера" RelRelatedTo CaseInstrumental "с верой"
      "аксиома связана с верой" "axiom is related to faith"
  , rel "закон" "справедливость" RelExpresses CaseAccusative "справедливость"
      "закон выражает справедливость" "law expresses justice"
  , rel "право" "свобода" RelSupports CaseAccusative "свободу"
      "право поддерживает свободу" "right supports freedom"
  , rel "договор" "доверие" RelRequires CaseGenitive "доверия"
      "договор требует доверия" "contract requires trust"
  , rel "искусство" "красота" RelExpresses CaseAccusative "красоту"
      "искусство выражает красоту" "art expresses beauty"
  , rel "музыка" "время" RelRelatedTo CaseInstrumental "со временем"
      "музыка связана со временем" "music is related to time"
  , rel "поэзия" "язык" RelStructures CaseAccusative "язык"
      "поэзия структурирует язык" "poetry structures language"
  , rel "государство" "власть" RelMeans CaseAccusative "власть"
      "государство означает власть" "state means power"
  , rel "революция" "свобода" RelRelatedTo CaseInstrumental "со свободой"
      "революция связана со свободой" "revolution is related to freedom"
  , rel "нация" "идентичность" RelRelatedTo CaseInstrumental "с идентичностью"
      "нация связана с идентичностью" "nation is related to identity"
  , rel "собственность" "свобода" RelLimitedBy CaseAccusative "свободу"
      "собственность ограничивает свободу" "property limits freedom"
  , rel "рынок" "доверие" RelRequires CaseGenitive "доверия"
      "рынок требует доверия" "market requires trust"
  , rel "алгоритм" "разум" RelStructures CaseAccusative "разум"
      "алгоритм структурирует разум" "algorithm structures reason"
  , rel "данные" "память" RelPreserves CaseAccusative "память"
      "данные сохраняет память" "data preserves memory"
  , rel "код" "язык" RelIsA CaseNominative "язык"
      "код есть язык" "code is language"
  , rel "жизнь" "смерть" RelContrastsWith CaseInstrumental "со смертью"
      "жизнь контрастирует со смертью" "life contrasts with death"
  , rel "инстинкт" "страх" RelSignals CasePrepositional "о страхе"
      "инстинкт сигнализирует о страхе" "instinct signals fear"
  , rel "эволюция" "время" RelRelatedTo CaseInstrumental "со временем"
      "эволюция связана со временем" "evolution is related to time"
  , rel "энтропия" "время" RelRelatedTo CaseInstrumental "со временем"
      "энтропия связана со временем" "entropy is related to time"
  , rel "энергия" "труд" RelTransforms CaseAccusative "труд"
      "энергия преобразует труд" "energy transforms labour"
  , rel "душа" "сознание" RelRelatedTo CaseInstrumental "с сознанием"
      "душа связана с сознанием" "soul is related to consciousness"
  , rel "дух" "воля" RelRelatedTo CaseInstrumental "с волей"
      "дух связан с волей" "spirit is related to will"
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
