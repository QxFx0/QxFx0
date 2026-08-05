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
  , categoryFromOntology
  , normalizeTopic
  , genericDefinitionPredicates
  , genericDistinctionPredicates
    -- * B3 helpers
  , substantivePredicateCount
  , hasMinimumPredicates
    -- * Utilities
  , extractTopicForm
  , mkPred
  , mkArguedPred
  , renderPredicateArgued
  , ChallengeResponse(..)
  , lookupChallengeResponse
  , challengeIntros
  , pickChallengeIntro
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

import QxFx0.Semantic.Content.Base
  ( PredicateRole(..)
  , SemanticPredicate(..)
  , ChallengeResponse(..)
  , mkPred
  , mkArguedPred
  , extractTopicForm
  , renderPredicateArgued
  , challengeIntros
  , pickChallengeIntro
  )
import QxFx0.Semantic.Content.Argued (arguedPredicates)
import QxFx0.Semantic.Content.Challenges (challengeResponseCorpusFull)
import QxFx0.Semantic.Content.Category (ConceptCategory(..))
import QxFx0.Semantic.Ontology (Ontology, emptyOntology, lookupCategory)

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
  -- ==========================================================================
  -- Phase E: Expanded seed corpus to 100+ topics
  -- ==========================================================================
  -- Metaphysics and Ontology (15 topics)
  , entry "существование"
      [ prop "существование есть основная категория бытия"
             "existence is the fundamental category of being"
      , rel "существование отличается от сущности как факт от структуры"
             "existence differs from essence as fact from structure"
      ]
  , entry "сущность"
      [ prop "сущность определяет что есть вещь"
             "essence defines what a thing is"
      , structure "сущность раскрывается через свойства и отношения"
                "essence is revealed through properties and relations"
      ]
  , entry "материя"
      [ prop "материя есть основание физического существования"
             "matter is the foundation of physical existence"
      , rel "материя взаимодействует с формой в процессе становления"
             "matter interacts with form in the process of becoming"
      ]
  , entry "форма"
      [ prop "форма структурирует материю в определенное целое"
             "form structures matter into a definite whole"
      , rel "форма без материи есть абстракция"
             "form without matter is abstraction"
      ]
  , entry "пространство"
      [ prop "пространство есть условие сосуществования объектов"
             "space is the condition of co-existence of objects"
      , rel "пространство связано с временем через движение"
             "space is connected to time through movement"
      ]
  , entry "движение"
      [ prop "движение есть изменение положения во времени"
             "movement is change of position over time"
      , structure "движение объединяет пространство и время"
                "movement unites space and time"
      ]
  , entry "возможность"
      [ prop "возможность есть то что может быть но еще не есть"
             "possibility is that which may be but is not yet"
      , rel "возможность переходит в действительность через реализацию"
             "possibility transitions to actuality through realization"
      ]
  , entry "действительность"
      [ prop "действительность есть то что существует здесь и теперь"
             "actuality is that which exists here and now"
      , rel "действительность противоположна возможности"
             "actuality is opposite to possibility"
      ]
  , entry "вечность"
      [ prop "вечность есть вневременное существование"
             "eternity is timeless existence"
      , rel "вечность противоположна временности"
             "eternity is opposite to temporality"
      ]
  , entry "конечность"
      [ prop "конечность определяет границы существования"
             "finiteness defines the limits of existence"
      , rel "конечность делает возможным осмысление целого"
             "finiteness makes it possible to comprehend the whole"
      ]
  , entry "бесконечность"
      [ prop "бесконечность выражает неограниченность"
             "infinity expresses unboundedness"
      , rel "бесконечность противоположна конечность"
             "infinity is opposite to finiteness"
      ]
  , entry "единство"
      [ prop "единство есть соединение множества в целое"
             "unity is the connection of the many into a whole"
      , structure "единство сохраняет различия в единстве"
                "unity preserves differences in unity"
      ]
  , entry "многообразие"
      [ prop "многообразие выражает богатство форм"
             "diversity expresses the richness of forms"
      , rel "многообразие противоположно единству"
             "diversity is opposite to unity"
      ]
  -- Epistemology (10 topics)
  , entry "знание"
      [ prop "знание требует обоснования и проверяемости"
             "knowledge requires justification and verifiability"
      , rel "знание отличается от мнения опорой на доказательства"
             "knowledge differs from opinion by reliance on evidence"
      ]
  , entry "опыт"
      [ prop "опыт есть источник эмпирического знания"
             "experience is the source of empirical knowledge"
      , structure "опыт включает восприятие память и интерпретацию"
                "experience includes perception memory and interpretation"
      ]
  , entry "ложь"
      [ prop "ложь есть сознательное искажение истины"
             "lie is a deliberate distortion of truth"
      , rel "ложь существует только на фоне возможности истины"
             "lie exists only against the background of the possibility of truth"
      ]
  , entry "сомнение"
      [ prop "сомнение приостанавливает суждение для проверки"
             "doubt suspends judgment for verification"
      , rel "сомнение есть двигатель познания"
             "doubt is the engine of cognition"
      ]
  , entry "уверенность"
      [ prop "уверенность основывается на достаточных основаниях"
             "certainty is based on sufficient grounds"
      , rel "уверенность противоположна сомнению"
             "certainty is opposite to doubt"
      ]
  , entry "понимание"
      [ prop "понимание есть осознание смысла"
             "understanding is the realization of meaning"
      , structure "понимание возникает через интерпретацию"
                "understanding arises through interpretation"
      ]
  , entry "объяснение"
      [ prop "объяснение раскрывает причины явления"
             "explanation reveals the causes of a phenomenon"
      , rel "объяснение отличается от описания поиском причин"
             "explanation differs from description by seeking causes"
      ]
  , entry "аргумент"
      [ prop "аргумент состоит из посылок и заключения"
             "argument consists of premises and conclusion"
      , rel "аргумент оценивается по валидности и истинности"
             "argument is evaluated by validity and truth"
      ]
  , entry "доказательство"
      [ prop "доказательство устанавливает истинность с необходимостью"
             "proof establishes truth with necessity"
      , structure "доказательство опирается на аксиомы и правила вывода"
                "proof relies on axioms and inference rules"
      ]
  -- Ethics extended (10 topics)
  , entry "добро"
      [ prop "добро есть то что способствует расцвету"
             "good is that which promotes flourishing"
      , rel "добро противоположно злу"
             "good is opposite to evil"
      ]
  , entry "зло"
      [ prop "зло причиняет вред и разрушение"
             "evil causes harm and destruction"
      , structure "зло часто коренится в неведении"
                "evil often has its roots in ignorance"
      ]
  , entry "мораль"
      [ prop "мораль регулирует отношения между людьми"
             "morality regulates relations between people"
      , rel "мораль основывается на ценностях"
             "morality is based on values"
      ]
  , entry "нравственность"
      [ prop "нравственность выражает внутреннюю позицию"
             "morality expresses the internal position"
      , rel "нравственность связана с характером"
             "morality is connected to character"
      ]
  , entry "совесть"
      [ prop "совесть есть внутренний суд над действиями"
             "conscience is the internal court over actions"
      , structure "совесть выражается в чувстве вины"
                "conscience is expressed in the feeling of guilt"
      ]
  , entry "достоинство"
      [ prop "достоинство есть осознание собственной ценности"
             "dignity is the awareness of ones own value"
      , rel "достоинство требует уважения"
             "dignity requires respect"
      ]
  , entry "честь"
      [ prop "честь есть внешнее признание достоинства"
             "honor is the external recognition of dignity"
      , rel "честь связана с репутацией"
             "honor is connected to reputation"
      ]
  , entry "равенство"
      [ prop "равенство есть принцип равных прав и возможностей"
             "equality is the principle of equal rights and opportunities"
      , rel "равенство противоположно дискриминации"
             "equality is opposite to discrimination"
      ]
  , entry "обязанность"
      [ prop "обязанность предписывает необходимые действия"
             "obligation prescribes necessary actions"
      , rel "обязанность связана с ответственностью"
             "obligation is connected to responsibility"
      ]
  , entry "выбор"
      [ prop "выбор есть акт свободы"
             "choice is an act of freedom"
      , rel "выбор несет ответственность"
             "choice bears responsibility"
      ]
  -- Philosophy of Mind (10 topics)
  , entry "душа"
      [ prop "душа традиционно рассматривается как принцип жизни"
             "soul is traditionally considered as the principle of life"
      , rel "душа связывается с телом и разумом"
             "soul is connected with body and mind"
      ]
  , entry "мысль"
      [ prop "мысль есть внутренний диалог с собой"
             "thought is an internal dialogue with oneself"
      , structure "мысль опирается на языке"
                "thought relies on language"
      ]
  , entry "воображение"
      [ prop "воображение создает новые образы и идеи"
             "imagination creates new images and ideas"
      , rel "воображение выходит за пределы опыта"
             "imagination goes beyond the limits of experience"
      ]
  , entry "внимание"
      [ prop "внимание фокусирует сознание на объекте"
             "attention focuses consciousness on an object"
      , structure "внимание имеет селективный характер"
                "attention has selective character"
      ]
  , entry "желание"
      [ prop "желание направлено на достижение ценного"
             "desire is directed at achieving the valuable"
      , rel "желание движет действием"
             "desire drives action"
      ]
  , entry "страсть"
      [ prop "страсть есть сильное устойчивое желание"
             "passion is a strong sustained desire"
      , structure "страсть может вдохновлять или разрушать"
                "passion can inspire or destroy"
      ]
  , entry "чувство"
      [ prop "чувство есть способность восприятия состояний"
             "feeling is the ability to perceive states"
      , structure "чувство включает физические компоненты"
                "feeling includes physical components"
      ]
  , entry "радость"
      [ prop "радость возникает при достижении ценного"
             "joy arises when something valuable is achieved"
      , rel "радость способствует творчеству"
             "joy promotes creativity"
      ]
  , entry "горе"
      [ prop "горе есть переживание потери"
             "grief is the experience of loss"
      , structure "горе требует времени"
                "grief requires time"
      ]
  -- Aesthetics (5 topics)
  , entry "искусство"
      [ prop "искусство есть выражение творческой свободы"
             "art is the expression of creative freedom"
      , rel "искусство открывает новые способы видения"
             "art opens new ways of seeing"
      ]
  , entry "вкус"
      [ prop "вкус есть способность различения и оценки"
             "taste is the ability to distinguish and evaluate"
      , structure "вкус формируется через опыт"
                "taste is formed through experience"
      ]
  , entry "гармония"
      [ prop "гармония есть согласованность частей в целом"
             "harmony is the agreement of parts in a whole"
      , rel "гармония воспринимается как красивая"
             "harmony is perceived as beautiful"
      ]
  , entry "трагедия"
      [ prop "трагедия изображает конфликт и страдание"
             "tragedy depicts conflict and suffering"
      , structure "трагедия ведет к катарсису"
                "tragedy leads to catharsis"
      ]
  , entry "возвышенное"
      [ prop "возвышенное вызывает чувство величия и трепета"
             "sublime evokes a sense of grandeur and awe"
      , rel "возвышенное связано с бесконечным"
             "sublime is connected with the infinite"
      ]
  -- Political Philosophy (5 topics)
  , entry "государство"
      [ prop "государство есть институциональная форма власти"
             "state is the institutional form of power"
      , rel "государство обеспечивает порядок"
             "state ensures order"
      ]
  , entry "закон"
      [ prop "закон устанавливает нормы и границы поведения"
             "law establishes norms and boundaries of behavior"
      , rel "закон получает силу от легитимности"
             "law derives strength from legitimacy"
      ]
  , entry "право"
      [ prop "право защищает свободу и достоинство"
             "right protects freedom and dignity"
      , structure "право закрепляется в конституциях"
                "right is enshrined in constitutions"
      ]
  , entry "гражданин"
      [ prop "гражданин есть член политического сообщества"
             "citizen is a member of a political community"
      , rel "гражданин имеет права и обязанности"
             "citizen has rights and obligations"
      ]
  , entry "общество"
      [ prop "общество есть совокупность социальных отношений"
             "society is the totality of social relations"
      , structure "общество имеет культуру и институты"
                "society has culture and institutions"
      ]
  -- Philosophy of Science (5 topics)
  , entry "наука"
      [ prop "наука стремится к объективному познанию"
             "science strives for objective knowledge"
      , rel "наука основывается на эмпирических данных"
             "science is based on empirical data"
      ]
  , entry "метод"
      [ prop "метод есть систематический путь к знанию"
             "method is a systematic path to knowledge"
      , rel "метод определяет надежность результатов"
             "method determines the reliability of results"
      ]
  , entry "эмпиризм"
      [ prop "эмпиризм основывается на опыте"
             "empiricism is based on experience"
      , rel "эмпиризм противоположен рационализму"
             "empiricism is opposite to rationalism"
      ]
  , entry "рационализм"
      [ prop "рационализм основывается на разume"
             "rationalism is based on reason"
      , rel "рационализм дополняет эмпиризм"
             "rationalism complements empiricism"
      ]
  , entry "эксперимент"
      [ prop "эксперимент проверяет гипотезы"
             "experiment tests hypotheses"
      , structure "эксперимент требует контроля переменных"
                "experiment requires control of variables"
      ]
  -- Social Philosophy (10 topics)
  , entry "общение"
      [ prop "общение есть обмен смыслами между субъектами"
             "communication is the exchange of meanings between subjects"
      , rel "общение основывается на общем языке"
             "communication is based on a common language"
      ]
  , entry "диалог"
      [ prop "диалог требует готовности слушать и отвечать"
             "dialogue requires willingness to listen and respond"
      , structure "диалог ведет к взаимопониманию"
                "dialogue leads to mutual understanding"
      ]
  , entry "конфликт"
      [ prop "конфликт выявляет разногласия"
             "conflict reveals disagreements"
      , rel "конфликт может быть конструктивным"
             "conflict can be constructive"
      ]
  , entry "сотрудничество"
      [ prop "сотрудничество есть совместная деятельность"
             "collaboration is joint activity"
      , rel "сотрудничество основывается на доверии"
             "collaboration is based on trust"
      ]
  , entry "взаимопонимание"
      [ prop "взаимопонимание есть результат успешного диалога"
             "mutual understanding is the result of successful dialogue"
      , structure "взаимопонимание требует эмпатии"
                "mutual understanding requires empathy"
      ]
  , entry "знак"
      [ prop "знак указывает на что-то иное чем он сам"
             "sign points to something other than itself"
      , structure "знак состоит из означающего и означаемого"
                "sign consists of signifier and signified"
      ]
  , entry "символ"
      [ prop "символ выражает глубокие значения"
             "symbol expresses deep meanings"
      , rel "символ отличается от знака конвенциональностью"
             "symbol differs from sign by conventionality"
      ]
  , entry "текст"
      [ prop "текст есть связное выражение смысла"
             "text is a coherent expression of meaning"
      , structure "текст имеет автора и контекст"
                "text has an author and context"
      ]
  , entry "интерпретация"
      [ prop "интерпретация раскрывает смысл текста"
             "interpretation reveals the meaning of the text"
      , rel "интерпретация зависит от контекста"
             "interpretation depends on context"
      ]
  -- Existential Philosophy (5 topics)
  , entry "смысл"
      [ prop "смысл придает направленность существованию"
             "meaning gives direction to existence"
      , rel "смысл ищется в условиях абсурда"
             "meaning is sought in the conditions of absurdity"
      ]
  , entry "абсурд"
      [ prop "абсурд выявляет противоречие между стремлением и молчанием мира"
             "absurd reveals the contradiction between striving and the silence of the world"
      , structure "абсурд требует бунта или принятия"
                "absurd requires revolt or acceptance"
      ]
  , entry "мужество"
      [ prop "мужество есть способность преодолевать страх"
             "courage is the ability to overcome fear"
      , rel "мужество проявляется в действии"
             "courage is manifested in action"
      ]
  , entry "аутентичность"
      [ prop "аутентичность есть подлинность существования"
             "authenticity is the genuineness of existence"
      , rel "аутентичность противоположна отчуждению"
             "authenticity is opposite to alienation"
      ]
  , entry "забота"
      [ prop "забота выражает вовлеченность в мир"
             "care expresses involvement in the world"
      , structure "забота раскрывает бытие"
                "care reveals being"
      ]
  -- Religious Philosophy (5 topics)
  , entry "трансценденция"
      [ prop "трансценденция выходит за пределы опыта"
             "transcendence goes beyond the limits of experience"
      , rel "трансценденция связывается с сакральным"
             "transcendence is associated with the sacred"
      ]
  , entry "святость"
      [ prop "святость выражает полноту ценности"
             "holiness expresses the fullness of value"
      , structure "святость соединяет человека с трансцендентным"
                "holiness connects man with the transcendent"
      ]
  , entry "бог"
      [ prop "бог есть абсолютная реальность"
             "god is absolute reality"
      , rel "бог рассматривается как источник бытия"
             "god is considered as the source of being"
      ]
  , entry "религия"
      [ prop "религия есть система верований и практик"
             "religion is a system of beliefs and practices"
      , rel "религия связывает человека с сакральным"
             "religion connects man with the sacred"
      ]
  , entry "молитва"
      [ prop "молитва есть обращение к трансцендентному"
             "prayer is an appeal to the transcendent"
      , structure "молитва выражает веру и надежду"
                "prayer expresses faith and hope"
      ]
  -- Additional practical (10 topics)
  , entry "дружба"
      [ prop "дружба основывается на взаимном доверии"
             "friendship is based on mutual trust"
      , structure "дружба развивается через общие переживания"
                "friendship develops through shared experiences"
      ]
  , entry "рутина"
      [ prop "рутина обеспечивает стабильность"
             "routine ensures stability"
      , rel "рутина противоположна изменению"
             "routine is opposite to change"
      ]
  , entry "счастье"
      [ prop "счастье есть оценка жизненной ситуации"
             "happiness is an evaluation of life situation"
      , rel "счастье связано с реализацией потенциала"
             "happiness is connected with the realization of potential"
      ]
  , entry "страдание"
      [ prop "страдание есть переживание боли"
             "suffering is the experience of pain"
      , rel "страдание может быть путем к преобразованию"
             "suffering can be a path to transformation"
      ]
  , entry "мудрость"
      [ prop "мудрость соединяет знание и опыт"
             "wisdom connects knowledge and experience"
      , rel "мудрость выражается в правильных суждениях"
             "wisdom is expressed in right judgments"
      ]
  , entry "удивление"
      [ prop "удивление открывает разум для нового"
             "wonder opens the mind to the new"
      , rel "удивление есть начало философии"
             "wonder is the beginning of philosophy"
      ]
  , entry "любопытство"
      [ prop "любопытство движет познанием"
             "curiosity drives cognition"
      , rel "любопытство может быть удовлетворено или разожжено"
             "curiosity can be satisfied or kindled"
      ]
  , entry "творчество"
      [ prop "творчество порождает новое и ценное"
             "creativity generates new and valuable things"
      , structure "творчество требует свободы и дисциплины"
                "creativity requires freedom and discipline"
      ]
  , entry "насилие"
      [ prop "насилие есть применение силы против воли"
             "violence is the application of force against will"
      , rel "насилие причиняет вред отношениям"
             "violence damages relationships"
      ]
  , entry "прощение"
      [ prop "прощение есть освобождение от обиды"
             "forgiveness is liberation from resentment"
      , structure "прощение восстанавливает关系"
                "forgiveness restores relationship"
      ]
  , entry "природа"
      [ prop "природа есть совокупность естественных явлений"
             "nature is the totality of natural phenomena"
      , rel "природа противоположна культуре"
             "nature is opposite to culture"
      ]
  , entry "культура"
      [ prop "культура есть совокупность духовных ценностей"
             "culture is the totality of spiritual values"
      , structure "культура передается через символы"
                "culture is transmitted through symbols"
      ]
  , entry "будущее"
      [ prop "будущее есть то что еще не наступило"
             "future is that which has not yet arrived"
      , rel "будущее открыто для возможности"
             "future is open to possibility"
      ]
  , entry "прошлое"
      [ prop "прошлое есть то что уже состоялось"
             "past is that which has already occurred"
      , rel "прошлое фиксировано в памяти"
             "past is fixed in memory"
      ]
  , entry "настоящее"
      [ prop "настоящее есть момент перехода от прошлого к будущему"
             "present is the moment of transition from past to future"
      , structure "настоящее есть единственная реальность"
                "present is the only reality"
      ]
  ]
  where
    entry topic preds = (topic, DefinitionContent topic (mergeArgued topic preds))
    prop ru en = SemanticPredicate RoleProperty ru en (extractTopicForm ru) Nothing Nothing Nothing
    rel ru en = SemanticPredicate RoleRelation ru en (extractTopicForm ru) Nothing Nothing Nothing
    structure ru en = SemanticPredicate RoleStructure ru en (extractTopicForm ru) Nothing Nothing Nothing

-- | Merge argued predicates into a topic's predicate list.
-- Replaces flat predicates with their argued versions (matching by ru text),
-- then appends any argued predicates not already present.
-- Ensures each topic retains ≥2 predicates (B3 Gate 1).
mergeArgued :: Text -> [SemanticPredicate] -> [SemanticPredicate]
mergeArgued topic flatPreds =
  case lookup topic arguedPredicates of
    Nothing -> flatPreds
    Just argued ->
      let flatRuTexts = map spRu flatPreds
          arguedRuTexts = map spRu argued
          -- Replace flat predicates that have argued versions
          upgraded = [ fromMaybe fp (findArgued (spRu fp) argued) | fp <- flatPreds ]
          -- Add argued predicates not already in flat list
          newArgued = [ ap | ap <- argued, spRu ap `notElem` flatRuTexts ]
      in upgraded ++ newArgued
  where
    findArgued ruTxt argued = case [ a | a <- argued, spRu a == ruTxt ] of
      (a:_) -> Just a
      []    -> Nothing

-- ============================================================================
-- Phase E: Argumentative rendering
-- ============================================================================

-- | Lookup a challenge response for a given topic and user objection text.
-- Searches challengeResponseCorpus for keyword matches in the objection.
lookupChallengeResponse :: Text -> Text -> [SemanticPredicate] -> Maybe (Text, ChallengeResponse)
lookupChallengeResponse topic objectionText _availablePreds =
  let lower = T.toLower objectionText
      matches = [ cr | cr <- challengeResponseCorpus
                     , crTopic cr == topic
                     , any (`T.isInfixOf` lower) (crObjectionKeywords cr)
                     ]
  in case matches of
       (cr:_) -> Just (pickChallengeIntro objectionText, cr)
       [] -> Nothing

-- | Challenge response corpus — maps topics to expected objections and responses.
-- 34 entries for 20 topics, with argued predicates (rationale/counter/synthesis).
challengeResponseCorpus :: [ChallengeResponse]
challengeResponseCorpus = challengeResponseCorpusFull

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
    diff ru en = SemanticPredicate RoleDifferentiator ru en (extractTopicForm ru) Nothing Nothing Nothing

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

-- | Lookup a concept's category in the ontology, returning 'Nothing' when
-- the concept is not present.  Lookup key is case-insensitive and
-- whitespace-stripped.
categoryFromOntology :: Ontology -> Text -> Maybe ConceptCategory
categoryFromOntology ont name = lookupCategory ont (normalizeTopic name)

-- | Classify a topic into a concept category.
--
-- ADR-0052 Phase IV: ontology is consulted first; if the concept is absent,
-- fall back to deterministic lexical markers and morphological suffixes.
-- Passing 'emptyOntology' recovers the legacy lexical-only behavior.
classifyConceptCategory :: Ontology -> Text -> ConceptCategory
classifyConceptCategory ontology topic =
  case categoryFromOntology ontology (normalizeTopic topic) of
    Just cat -> cat
    Nothing  -> lexicalClassifyConceptCategory topic

-- | Lexical-only classifier used as the fallback when the ontology has no
-- entry for a concept. Based on keyword markers + morphological suffixes.
lexicalClassifyConceptCategory :: Text -> ConceptCategory
lexicalClassifyConceptCategory topic =
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
      ["филос", "свобод", "истин", "смысл", "сознан", "бытие", "ничто", "вечн", "разум"
      , "познан", "реальн", "иллюз", "пустот", "сущнос", "вер", "красот"
      , "добр", "благ", "мудрост", "истин", "справедлив"]
    socialMarkers =
      ["соци", "ответств", "довер", "долг", "обяз", "справедлив", "право", "закон"
      , "обществ", "нравств", "этик", "морал", "совест", "чест", "верност"
      , "предан", "уважен"]
    psychologicalMarkers =
      ["псих", "памят", "воспомин", "эмоц", "чувств", "восприят", "мышлен", "вниман"
      , "воображ", "сон", "мечт", "страх", "надежд", "радост", "груст"
      , "тревог", "пережив", "интуиц"]
    physicalMarkers =
      ["физ", "тел", "пространств", "времен", "матер", "энерг", "свет", "звук", "движен"
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
  let cat = lexicalClassifyConceptCategory topic
  in case cat of
    CategoryPhilosophical ->
      [ mkPred RoleProperty (topic <> " предполагает наличие внутренней структуры") (topic <> " presupposes an internal structure")
      , mkPred RoleRelation (topic <> " связан с условиями возможности опыта") (topic <> " is connected to conditions of possible experience")
      ]
    CategorySocial ->
      [ mkPred RoleProperty (topic <> " возникает во взаимодействии между субъектами") (topic <> " arises in interaction between subjects")
      , mkPred RoleRelation (topic <> " ограничен нормами и ожиданиями сообщества") (topic <> " is bounded by norms and expectations of community")
      ]
    CategoryPsychological ->
      [ mkPred RoleProperty (topic <> " формируется через опыт и воспоминание") (topic <> " is formed through experience and recollection")
      , mkPred RoleStructure (topic <> " имеет субъективный характер и доступ от первого лица") (topic <> " has subjective character and first-person access")
      ]
    CategoryPhysical ->
      [ mkPred RoleProperty (topic <> " обладает протяжённостью в пространстве или времени") (topic <> " has extension in space or time")
      , mkPred RoleRelation (topic <> " подчиняется устойчивым закономерностям") (topic <> " obeys stable regularities")
      ]
    CategoryGeneral ->
      [ mkPred RoleProperty (topic <> " проявляется через устойчивые связи в своём контексте") (topic <> " manifests through stable connections in its context")
      , mkPred RoleRelation (topic <> " зависит от рамки, в которой рассматривается") (topic <> " depends on the frame in which it is considered")
      ]

-- | Category-typed generic distinction predicates.
genericDistinctionPredicates :: Text -> Text -> [SemanticPredicate]
genericDistinctionPredicates left right =
  let catL = lexicalClassifyConceptCategory left
      catR = lexicalClassifyConceptCategory right
  in case (catL, catR) of
    (CategoryPhilosophical, CategoryPhilosophical) ->
      [ mkPred RoleDifferentiator (left <> " относится к сфере должного, " <> right <> " — к сфере сущего") (left <> " belongs to the normative, " <> right <> " — to the descriptive")
      ]
    (CategorySocial, CategoryPhilosophical) ->
      [ mkPred RoleDifferentiator (left <> " регулирует взаимодействие, " <> right <> " описывает устройство мира") (left <> " regulates interaction, " <> right <> " describes the structure of reality")
      ]
    (CategoryPsychological, CategoryPhysical) ->
      [ mkPred RoleDifferentiator (left <> " принадлежит внутреннему опыту, " <> right <> " — внешнему миру") (left <> " belongs to inner experience, " <> right <> " — to the outer world")
      ]
    _ ->
      [ mkPred RoleDifferentiator (left <> " и " <> right <> " различаются по области применимости и набору устойчивых признаков") (left <> " and " <> right <> " differ by scope of application and stable properties")
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
      let firstPred = case dcPredicates dc of (p:_) -> spRu p; [] -> ""
      in Just ChallengeContent
           { ccTarget = n
           , ccBasis = "Моя позиция опиралась на: " <> firstPred
           , ccStrength = "soft"
           }
    Just _  -> Nothing
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
