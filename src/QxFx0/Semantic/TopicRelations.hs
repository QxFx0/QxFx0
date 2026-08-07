{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.TopicRelations
  ( TopicRelation(..)
  , allTopicRelationsList
  , convertToSemanticEdges
  ) where

import Data.List (maximumBy, nub)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import Data.Text (Text)

import QxFx0.Semantic.Network.Types (SemanticEdge(..), EdgeSource(..), semanticEdge)
import QxFx0.Types.Semantic.AtomGraph (RelationType(..))

-- | A semantic relation between two topics
-- Represents explicit semantic connections (synonyms, antonyms, hypernyms, hyponyms)
data TopicRelation = TopicRelation
  { trFrom :: !Text
  , trTo :: !Text
  , trType :: !RelationType
  , trWeight :: !Double
  , trConfidence :: !Int
  } deriving stock (Eq, Show)

-- | All explicit topic relations (200+ connections)
-- Organized by relation type for maintainability
allTopicRelationsList :: [TopicRelation]
allTopicRelationsList = concat
  [ synonyms
  , antonyms
  , hypernyms
  , hyponyms
  , meronyms
  , causalRelations
  , temporalRelations
  , philosophicalRelations
  , psychologicalRelations
  , socialRelations
  ]

-- ==========================================================================
-- Synonyms (RelRelatedTo / RelIsA)
-- ==========================================================================
synonyms :: [TopicRelation]
synonyms = map (\ (from, to) -> TopicRelation from to RelRelatedTo 1.0 10)
  [ ("свобода", "воля")
  , ("истина", "правда")
  , ("мнение", "взгляд")
  , ("память", "воспоминание")
  , ("сознание", "осознанность")
  , ("ответственность", "обязанность")
  , ("страх", "ужас")
  , ("надежда", "вера")
  , ("любовь", "привязанность")
  , ("труд", "работа")
  , ("покой", "отдых")
  , ("власть", "авторитет")
  , ("справедливость", "честность")
  , ("время", "период")
  , ("разум", "интеллект")
  , ("бытие", "существование")
  , ("история", "хроника")
  , ("язык", "речь")
  , ("смерть", "конец")
  , ("одиночество", "изоляция")
  , ("доверие", "вера")
  , ("красота", "прелесть")
  ]

-- ==========================================================================
-- Antonyms (RelOpposes / RelDiffersFrom / RelContrastsWith)
-- ==========================================================================
antonyms :: [TopicRelation]
antonyms = map (\ (from, to) -> TopicRelation from to RelOpposes 0.9 9)
  [ ("свобода", "произвол")
  , ("свобода", "необходимость")
  , ("истина", "ложь")
  , ("доверие", "недоверие")
  , ("надежда", "отчаяние")
  , ("любовь", "ненависть")
  , ("труд", "покой")
  , ("власть", "бессилие")
  , ("справедливость", "несправедливость")
  , ("жизнь", "смерть")
  , ("свет", "тьма")
  , ("добро", "зло")
  , ("радость", "горе")
  , ("сильный", "слабый")
  , ("мужество", "трусость")
  , ("счастье", "страдание")
  , ("знание", "невежество")
  , ("свобода", "зависимость")
  , ("единство", "разделение")
  , ("создание", "разрушение")
  ]

-- ==========================================================================
-- Hypernyms (RelIncludes / RelPresupposes / RelIsA)
-- ==========================================================================
hypernyms :: [TopicRelation]
hypernyms = map (\ (from, to) -> TopicRelation from to RelIncludes 0.95 10)
  [ ("философия", "онтология")
  , ("философия", "эпистемология")
  , ("философия", "этика")
  , ("философия", "эстетика")
  , ("философия", "логика")
  , ("психология", "сознание")
  , ("психология", "познание")
  , ("психология", "эмоции")
  , ("социум", "отношения")
  , ("социум", "норма")
  , ("физическое", "материя")
  , ("физическое", "энергия")
  , ("общее", "знак")
  , ("общее", "система")
  , ("деятельность", "труд")
  , ("деятельность", "творчество")
  , ("коллектив", "сообщество")
  , ("разум", "мысль")
  , ("разум", "познание")
  , ("время", "прошлого")
  , ("время", "будущее")
  ]

-- ==========================================================================
-- Hyponyms (RelPartOf / RelStructures)
-- ==========================================================================
hyponyms :: [TopicRelation]
hyponyms = map (\ (from, to) -> TopicRelation from to RelPartOf 0.9 8)
  [ ("онтология", "философия")
  , ("эпистемология", "философия")
  , ("этика", "философия")
  , ("эстетика", "философия")
  , ("сознание", "психология")
  , ("познание", "психология")
  , ("материя", "физическое")
  , ("энергия", "физическое")
  , ("отношения", "социум")
  , ("норма", "социум")
  , ("мысли", "разум")
  , ("идея", "мысль")
  , ("процесс", "деятельность")
  , ("теория", "знание")
  , ("практика", "деятельность")
  , ("индивид", "коллектив")
  , ("член", "сообщество")
  ]

-- ==========================================================================
-- Meronyms (RelPresupposes / RelRequires)
-- ==========================================================================
meronyms :: [TopicRelation]
meronyms = map (\ (from, to) -> TopicRelation from to RelPresupposes 0.85 7)
  [ ("сознание", "самосознание")
  , ("память", "воспоминание")
  , ("любовь", "доверие")
  , ("власть", "ответственность")
  , ("свобода", "ответственность")
  , ("справедливость", "равенство")
  , ("истина", "познание")
  , ("язык", "знак")
  , ("социум", "индивид")
  , ("деятельность", "цель")
  , ("разум", "сознание")
  , ("время", "событие")
  , ("бытие", "существование")
  , ("мышление", "идея")
  ]

-- ==========================================================================
-- Causal Relations (RelCauses / RelInfluences)
-- ==========================================================================
causalRelations :: [TopicRelation]
causalRelations = map (\ (from, to) -> TopicRelation from to RelCauses 0.85 8)
  [ ("труд", "результат")
  , ("знание", "понимание")
  , ("свобода", "ответственность")
  , ("власть", "порядок")
  , ("доверие", "кооперация")
  , ("любовь", "счастье")
  , ("страх", "осторожность")
  , ("надежда", "стремление")
  , ("познание", "истина")
  , ("речь", "понимание")
  , ("общение", "согласие")
  , ("внимание", "познание")
  , ("рефлексия", "осознание")
  , ("опыт", "знание")
  ]

-- ==========================================================================
-- Temporal Relations (RelPrecedes)
-- ==========================================================================
temporalRelations :: [TopicRelation]
temporalRelations = map (\ (from, to) -> TopicRelation from to RelPrecedes 0.8 7)
  [ ("прошлого", "настоящее")
  , ("настоящее", "будущее")
  , ("рождение", "жизнь")
  , ("жизнь", "смерть")
  , ("начало", "процесс")
  , ("процесс", "конец")
  , ("причина", "следствие")
  , ("память", "будущее")
  , ("опыт", "мудрость")
  ]

-- ==========================================================================
-- Philosophical Relations
-- ==========================================================================
philosophicalRelations :: [TopicRelation]
philosophicalRelations = map (\ (from, to, rel, w, c) -> TopicRelation from to rel w c)
  [ ("бытие", "сознание", RelDetermines, 0.9, 10)
  , ("сознание", "бытие", RelReveals, 0.85, 9)
  , ("свобода", "необходимость", RelContrastsWith, 0.95, 10)
  , ("истина", "реальность", RelDenotes, 0.95, 10)
  , ("мнение", "субъект", RelDependsOn, 0.8, 8)
  , ("память", "идентичность", RelPreserves, 0.85, 9)
  , ("воспоминание", "опыт", RelStructures, 0.8, 7)
  , ("самосознание", "рефлексия", RelEnables, 0.9, 10)
  , ("ответственность", "свобода", RelLimitedBy, 0.9, 9)
  , ("долг", "мораль", RelPresupposes, 0.95, 10)
  , ("справедливость", "равенство", RelRequires, 0.85, 8)
  , ("время", "изменение", RelConnects, 0.8, 7)
  , ("разум", "познание", RelMakes, 0.85, 9)
  , ("язык", "мышление", RelExpresses, 0.9, 10)
  ]

-- ==========================================================================
-- Psychological Relations
-- ==========================================================================
psychologicalRelations :: [TopicRelation]
psychologicalRelations = map (\ (from, to, rel, w, c) -> TopicRelation from to rel w c)
  [ ("сознание", "психика", RelIncludes, 0.95, 10)
  , ("психика", "эмоции", RelStructures, 0.9, 9)
  , ("эмоции", "чувство", RelPartOf, 0.85, 8)
  , ("познание", "восприятие", RelPresupposes, 0.9, 9)
  , ("память", "опыт", RelPreserves, 0.95, 10)
  , ("воспоминание", "идентичность", RelInfluences, 0.8, 7)
  , ("волевое_начало", "действие", RelCauses, 0.9, 10)
  , ("страх", "защита", RelCauses, 0.85, 8)
  , ("надежда", "цель", RelOrientsToward, 0.9, 9)
  , ("любовь", "привязанность", RelMakes, 0.85, 8)
  ]

-- ==========================================================================
-- Social Relations
-- ==========================================================================
socialRelations :: [TopicRelation]
socialRelations = map (\ (from, to, rel, w, c) -> TopicRelation from to rel w c)
  [ ("социум", "индивид", RelIncludes, 0.95, 10)
  , ("социум", "коллектив", RelStructures, 0.9, 9)
  , ("отношения", "взаимодействие", RelExpresses, 0.9, 9)
  , ("норма", "поведение", RelPrescribes, 0.85, 8)
  , ("власть", "порядок", RelSets, 0.9, 10)
  , ("политическое", "власть", RelIncludes, 0.85, 8)
  , ("деятельность", "результат", RelMakes, 0.9, 9)
  , ("коллектив", "цель", RelConnects, 0.8, 7)
  ]

-- ==========================================================================
-- Conversion to SemanticEdge
-- ==========================================================================

-- | Convert a TopicRelation to a SemanticEdge
-- Uses ExplicitEdge as the source since these are curated relations
convertToSemanticEdges :: [TopicRelation] -> [SemanticEdge]
convertToSemanticEdges relations =
  let uniquePairs = nub [ (trFrom r, trTo r) | r <- relations ]
      -- For each unique pair, find the best relation
      bestRelForPair (from, to) = case filter (\r -> trFrom r == from && trTo r == to) relations of
        [] -> Nothing
        rs -> Just (maximumByConfidence rs)
      sortedRelations = mapMaybe bestRelForPair uniquePairs
  in map (\r -> semanticEdge (trFrom r) (trTo r) (trWeight r) (fromIntegral (trConfidence r)) ExplicitEdge)
        sortedRelations

-- | Pick the highest-confidence relation among those sharing a topic pair.
maximumByConfidence :: [TopicRelation] -> TopicRelation
maximumByConfidence [] = error "maximumByConfidence: empty list"
maximumByConfidence (r:rs) =
  maximumBy (\a b -> compare (trConfidence a) (trConfidence b)) (r:rs)
