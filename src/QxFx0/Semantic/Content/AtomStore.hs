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
    -- * Stores
  , atomStore
  , relationStore
  , atomsForTopic
  , relationsFromAtom
  , relationsToAtom
  , allTopics
    -- * Verbalizer (simple, for round-trip)
  , verbalizeRelation
  , verbalizeRelationEn
    -- * Round-trip
  , roundTripCheck
  , allRoundTripResults
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
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
  deriving anyclass (NFData, ToJSON, FromJSON)

data AtomCategory
  = CatTopic       -- philosophical topic (свобода, истина, ...)
  | CatConcept     -- abstract concept (выбор, ответственность, ...)
  | CatProperty    -- property/quality (необратимость, осмысленность, ...)
  | CatProcess     -- process/action (действие, проверка, ...)
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Atom = Atom
  { atomId       :: !AtomId
  , atomSurface  :: !Text   -- nominative form for display
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
-- Atom store
-- ============================================================

atomStore :: Map AtomId Atom
atomStore = M.fromList
  [ mkAtom "свобода"              CatTopic
  , mkAtom "произвол"             CatTopic
  , mkAtom "ответственность"      CatTopic
  , mkAtom "истина"               CatTopic
  , mkAtom "мнение"               CatTopic
  , mkAtom "память"               CatTopic
  , mkAtom "воспоминание"         CatTopic
  , mkAtom "сознание"             CatTopic
  , mkAtom "самосознание"         CatTopic
  , mkAtom "вера"                 CatTopic
  , mkAtom "красота"              CatTopic
  , mkAtom "долг"                 CatTopic
  , mkAtom "доверие"              CatTopic
  , mkAtom "страх"                CatTopic
  , mkAtom "надежда"              CatTopic
  , mkAtom "справедливость"       CatTopic
  , mkAtom "время"                CatTopic
  , mkAtom "разум"                CatTopic
  , mkAtom "бытие"                CatTopic
  , mkAtom "история"              CatTopic
  , mkAtom "язык"                 CatTopic
  , mkAtom "воля"                 CatTopic
  , mkAtom "смерть"               CatTopic
  , mkAtom "одиночество"          CatTopic
  , mkAtom "любовь"               CatTopic
  , mkAtom "труд"                 CatTopic
  , mkAtom "покой"                CatTopic
  , mkAtom "власть"               CatTopic
  , mkAtom "правда"               CatTopic
  , mkAtom "молчание"             CatTopic
  -- concept atoms (objects of relations)
  , mkAtom "выбор"                CatConcept
  , mkAtom "рамка_критериев"      CatConcept
  , mkAtom "доверие_субъектов"    CatConcept
  , mkAtom "осознание_последствий" CatConcept
  , mkAtom "обязательства_перед_другими" CatConcept
  , mkAtom "соответствие_реальности" CatConcept
  , mkAtom "воспроизводимость"    CatConcept
  , mkAtom "позиция_субъекта"     CatConcept
  , mkAtom "перспектива_наблюдателя" CatConcept
  , mkAtom "прошлое_для_настоящего" CatConcept
  , mkAtom "избирательность_и_реконструкция" CatProperty
  , mkAtom "пережитое_в_новой_рамке" CatConcept
  , mkAtom "акт_обращения_к_прошлому" CatConcept
  , mkAtom "субъективность"       CatProperty
  , mkAtom "аспект_первого_лица"  CatConcept
  , mkAtom "способность_к_самоотчёту" CatConcept
  , mkAtom "восприятие_и_рефлексия" CatConcept
  , mkAtom "собственные_состояния_субъекта" CatConcept
  , mkAtom "сознание_как_основание" CatConcept
  , mkAtom "субъект_как_объект"   CatConcept
  , mkAtom "принятие_без_доказательства" CatConcept
  , mkAtom "доверие_к_непроверяемому" CatConcept
  , mkAtom "доверие_к_источнику"  CatConcept
  , mkAtom "не_сводимость_к_полезности" CatProperty
  , mkAtom "эстетическое_переживание" CatConcept
  , mkAtom "воспринимающий_и_рамка" CatConcept
  , mkAtom "действие_независимо_от_желания" CatConcept
  , mkAtom "моральные_обязательства" CatConcept
  , mkAtom "уязвимость_перед_другим" CatConcept
  , mkAtom "повторяемый_опыт"     CatConcept
  , mkAtom "угроза_целостности"   CatConcept
  , mkAtom "угроза_целостности_субъекта" CatConcept
  , mkAtom "то_что_имеет_значение" CatConcept
  , mkAtom "возможность_будущего" CatConcept
  , mkAtom "действие_в_неопределённости" CatConcept
  , mkAtom "соразмерность_деяния_и_воздаяния" CatConcept
  , mkAtom "равенство_перед_правилом" CatConcept
  , mkAtom "порядок_следования_событий" CatConcept
  , mkAtom "необратимость_и_неравномерность" CatProperty
  , mkAtom "необратимость"        CatProperty
  , mkAtom "самокоррекция"        CatProcess
  , mkAtom "обобщение_и_абстракция" CatConcept
  , mkAtom "отличие_от_интуиции"  CatConcept
  , mkAtom "факт_существования"   CatConcept
  , mkAtom "условие_возможности_суждения" CatConcept
  , mkAtom "сущность"             CatConcept
  , mkAtom "события_и_интерпретация" CatConcept
  , mkAtom "прошлое_с_настоящим"  CatConcept
  , mkAtom "точка_зрения_рассказчика" CatConcept
  , mkAtom "мышление"             CatConcept
  , mkAtom "опыт_через_различение" CatConcept
  , mkAtom "выражение_и_формирование_мысли" CatConcept
  , mkAtom "действие_к_цели"      CatConcept
  , mkAtom "преодоление_препятствий" CatConcept
  , mkAtom "прекращение_существования" CatConcept
  , mkAtom "граница_жизни"        CatConcept
  , mkAtom "неотменимость_жизни"  CatProperty
  , mkAtom "граница_я_и_других"   CatConcept
  , mkAtom "отсутствие_значимого_другого" CatConcept
  , mkAtom "избрано_или_навязано" CatProperty
  , mkAtom "ценность_другого"     CatConcept
  , mkAtom "уязвимость_и_риск"    CatConcept
  , mkAtom "преобразование_мира_и_себя" CatConcept
  , mkAtom "материал_через_усилие" CatConcept
  , mkAtom "потребность_и_ресурсы" CatConcept
  , mkAtom "не_отсутствие_движения" CatProperty
  , mkAtom "восстановление_и_интеграция" CatConcept
  , mkAtom "отсутствие_движения_и_напряжения" CatConcept
  , mkAtom "способность_влиять"   CatConcept
  , mkAtom "легитимность_для_устойчивости" CatConcept
  , mkAtom "чья_воля_становится_законом" CatConcept
  , mkAtom "соответствие_произошедшему" CatConcept
  , mkAtom "личная_вовлечённость" CatProperty
  , mkAtom "персональная_вовлечённость" CatProperty
  , mkAtom "отсутствие_слов"      CatConcept
  , mkAtom "контраст_с_речью"     CatConcept
  , mkAtom "акт_отказа_или_присутствия" CatConcept
  ]
  where
    mkAtom surf cat = (AtomId surf, Atom (AtomId surf) surf cat)

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
allTopics = map atomSurface
         $ filter (\a -> atomCategory a == CatTopic)
         $ M.elems atomStore

-- ============================================================
-- Verbalizer (simple — for round-trip parity)
-- ============================================================

-- | Verbalize a relation back to its original predicate text.
-- Step 1: uses stored object text (round-trip parity).
-- Step 2 will replace objectText with morphological inflection.
verbalizeRelation :: Relation -> Text
verbalizeRelation r =
  case relVerbText r of
    Just ""  -> subject <> " " <> relObjectText r
    Just vt  -> subject <> " " <> vt <> " " <> relObjectText r
    Nothing  -> subject <> " " <> verbPhrase <> " " <> relObjectText r
  where
    subject = case M.lookup (relFrom r) atomStore of
      Just a  -> atomSurface a
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
-- Returns (original, verbalized, isMatch).
roundTripCheck :: Relation -> (Text, Text, Bool)
roundTripCheck r =
  let verbalized = verbalizeRelation r
      original = relRuOriginal r
  in (original, verbalized, original == verbalized)

-- | Check all relations and return mismatches.
allRoundTripResults :: [(Text, Text, Bool)]
allRoundTripResults = map roundTripCheck relationStore
