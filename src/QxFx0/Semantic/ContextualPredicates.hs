{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

-- |
-- Module      : QxFx0.Semantic.ContextualPredicates
-- Description : Contextual predicate generation based on Field and context
--
-- This module provides functions for generating relevant predicates based on
-- the current Field state and contextual information. Unlike static predicates
-- from the Content corpus, contextual predicates are dynamically generated to
-- better match the current state and needs of the system.
--
-- == Design Principles
--
-- 1. Field-aware: Generated predicates reflect current Field state
-- 2. Context-sensitive: Generation considers the current context and recent turns
-- 3. Relevant: Predicates are selected based on their affinity to the current Field
-- 4. Diverse: Multiple perspectives and aspects are represented
--
-- == Usage Example
--
-- > let field = Field { fhResonance = Resonance 0.8, ... }
-- > let context = PredicateContext { pcTopic = "истина", ... }
-- > let predicates = generateContextualPredicates field context
-- > -- Returns predicates like "истина проверяется в текущем контексте"
--
module QxFx0.Semantic.ContextualPredicates
  ( -- * Types
    PredicateContext(..)
    , ContextualPredicate(..)
    , PredicateGenerationStrategy(..)
    , GenerationParams(..)
    
    -- * Main generation functions
    , generateContextualPredicates
    , generateFieldSpecificPredicates
    , generateFromCurrentState
    
    -- * Strategy-based generation
    , generateWithStrategy
    , highConfidenceStrategy
    , exploratoryStrategy
    , dialogicStrategy
    , reflectiveStrategy
    
    -- * Predicate transformation
    , adaptPredicateToField
    , intensifyPredicate
    , mitigatePredicate
    
    -- * Context analysis
    , analyzePredicateContext
    , PredicateRelevance(..)
    , scorePredicateRelevance
    
    -- * Field-based template expansion
    , expandPredicateTemplates
    , predicateTemplates
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.List (nub, sortBy)
import Data.Ord (comparing)
import GHC.Generics (Generic)

import QxFx0.Semantic.Content (SemanticPredicate(..), Role(..))
import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..), csSpace)
import QxFx0.Semantic.Space (SemanticSpace(..), computeFieldAffinity)
import QxFx0.Self.Field (Field(..), Resonance(..), Atmosphere(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))

-- ============================================================================
-- TYPES
-- ============================================================================

-- | Context for predicate generation
data PredicateContext = PredicateContext
  { pcTopic :: !(Maybe Text)           -- ^ Main topic being discussed
  , pcRecentTopics :: ![Text]           -- ^ Topics from recent turns
  , pcUserIntent :: !(Maybe Text)       -- ^ Detected user intent
  , pcConversationalMode :: !Text      -- ^ Current mode (dialogue, explanation, etc.)
  , pcTurnCount :: !Int                 -- ^ Number of turns in current conversation
  , pcUnresolvedIssues :: ![Text]      -- ^ Issues that haven't been resolved
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Contextual predicate with metadata
data ContextualPredicate = ContextualPredicate
  { cpPredicate :: !SemanticPredicate  -- ^ The generated predicate
  , cpRelevance :: !Double             -- ^ Relevance score (0-1)
  , cpSource :: !Text                  -- ^ Source of generation (template, adaptation, etc.)
  , cpFieldAffinity :: !Double          -- ^ Affinity to current Field
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Strategy for predicate generation
data PredicateGenerationStrategy
  = HighConfidenceStrategy      -- ^ Focus on high-confidence, established predicates
  | ExploratoryStrategy          -- ^ Generate novel, exploratory predicates
  | DialogicStrategy             -- ^ Focus on dialogue and interaction
  | ReflectiveStrategy           -- ^ Focus on reflection and self-awareness
  | BalancedStrategy             -- ^ Balance of different approaches
  deriving stock (Eq, Show, Enum, Bounded, Generic)

-- | Parameters for predicate generation
data GenerationParams = GenerationParams
  { gpStrategy :: !PredicateGenerationStrategy
  , gpMinRelevance :: !Double           -- ^ Minimum relevance threshold
  , gpMaxPredicates :: !Int              -- ^ Maximum number of predicates to generate
  , gpFieldWeight :: !Double            -- ^ Weight for Field affinity
  , gpContextWeight :: !Double          -- ^ Weight for contextual relevance
  } deriving stock (Eq, Show, Generic)

-- | Default generation parameters
defaultGenerationParams :: GenerationParams
defaultGenerationParams = GenerationParams
  { gpStrategy = BalancedStrategy
  , gpMinRelevance = 0.3
  , gpMaxPredicates = 5
  , gpFieldWeight = 0.6
  , gpContextWeight = 0.4
  }

-- | Predicate relevance score
data PredicateRelevance = PredicateRelevance
  { prFieldMatch :: !Double
  , prContextMatch :: !Double
  , prNovelty :: !Double
  , prTimeliness :: !Double
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ============================================================================
-- MAIN GENERATION FUNCTIONS
-- ============================================================================

-- | Generate contextual predicates based on Field and context
-- This is the main entry point for contextual predicate generation
generateContextualPredicates 
  :: Field 
  -> PredicateContext 
  -> ContentSelector 
  -> [ContextualPredicate]
generateContextualPredicates field context selector =
  let params = defaultGenerationParams
      strategy = gpStrategy params
      templates = expandPredicateTemplates field context
      adapted = adaptExistingPredicates selector field context
      allPredicates = templates ++ adapted
      scored = map (\p -> (p, scorePredicateRelevance field context p)) allPredicates
      sorted = sortBy (comparing (Down . snd)) scored
      filtered = take (gpMaxPredicates params) 
                 [ cp | (cp, relevance) <- sorted, relevance >= gpMinRelevance params ]
  in [ ContextualPredicate
        { cpPredicate = p
        , cpRelevance = relevance
        , cpSource = source
        , cpFieldAffinity = computePredicateFieldAffinity field p
        }
     | (ContextualPredicate { cpPredicate = p, cpRelevance = relevance }, source) <- 
         zip filtered (repeat "contextual_generation")
     ]
  where
    -- For now, use simple adaptation; this can be enhanced
    adaptExistingPredicates _ _ _ = []
    computePredicateFieldAffinity field pred = 
      case csSpace selector of
        Just space -> computeFieldAffinity space (predicateToVector pred)
        Nothing -> 0.5
    predicateToVector pred = error "predicateToVector not implemented yet"

-- | Generate predicates specific to the current Field state
generateFieldSpecificPredicates 
  :: Field 
  -> Maybe Text  -- ^ Current topic
  -> [ContextualPredicate]
generateFieldSpecificPredicates field mTopic =
  let confidenceLevel = fieldConfidenceLevel field
      resonanceLevel = resonanceLevel field
      predicates = fieldAdaptivePredicates confidenceLevel resonanceLevel mTopic
  in [ ContextualPredicate
        { cpPredicate = pred
        , cpRelevance = 0.8  -- Field-specific predicates are highly relevant
        , cpSource = "field_adaptive"
        , cpFieldAffinity = 0.9
        }
     | pred <- predicates
     ]
  where
    fieldConfidenceLevel :: Field -> Double
    fieldConfidenceLevel f = case fhConfidence (fieldHeuristics f) of
      FieldConfidence fc -> fc
      _ -> 0.5
    
    resonanceLevel :: Field -> Double
    resonanceLevel f = case fhResonance (fieldHeuristics f) of
      Resonance r -> r
      _ -> 0.5

-- | Generate predicates from current system state
generateFromCurrentState 
  :: Field 
  -> PredicateContext 
  -> [ContextualPredicate]
generateFromCurrentState field context =
  let unresolved = pcUnresolvedIssues context
      turnCount = pcTurnCount context
      predicates = stateBasedPredicates unresolved turnCount
  in [ ContextualPredicate
        { cpPredicate = pred
        , cpRelevance = 0.7
        , cpSource = "state_based"
        , cpFieldAffinity = 0.8
        }
     | pred <- predicates
     ]

-- ============================================================================
-- STRATEGY-BASED GENERATION
-- ============================================================================

-- | Generate predicates using a specific strategy
generateWithStrategy 
  :: PredicateGenerationStrategy 
  -> Field 
  -> PredicateContext 
  -> ContentSelector 
  -> [ContextualPredicate]
generateWithStrategy strategy field context selector =
  case strategy of
    HighConfidenceStrategy -> highConfidenceStrategy field context selector
    ExploratoryStrategy -> exploratoryStrategy field context selector
    DialogicStrategy -> dialogicStrategy field context selector
    ReflectiveStrategy -> reflectiveStrategy field context selector
    BalancedStrategy -> generateContextualPredicates field context selector

-- | High confidence strategy: Focus on established, reliable predicates
highConfidenceStrategy 
  :: Field 
  -> PredicateContext 
  -> ContentSelector 
  -> [ContextualPredicate]
highConfidenceStrategy field context selector =
  let basePredicates = generateContextualPredicates field context selector
      -- Filter for high field affinity and relevance
      filtered = filter (\cp -> cpFieldAffinity cp > 0.7 && cpRelevance cp > 0.7) basePredicates
  in take 3 (sortBy (comparing (Down . cpRelevance)) filtered)

-- | Exploratory strategy: Generate novel, creative predicates
exploratoryStrategy 
  :: Field 
  -> PredicateContext 
  -> ContentSelector 
  -> [ContextualPredicate]
exploratoryStrategy field context selector =
  let basePredicates = generateContextualPredicates field context selector
      -- Add some novel predicates based on field extremes
      fieldPredicates = generateFieldSpecificPredicates field (pcTopic context)
      combined = basePredicates ++ fieldPredicates
      -- Prefer lower affinity (more novel) but still relevant
      scored = map (\cp -> (cp, cpRelevance cp * (1 - cpFieldAffinity cp))) combined
      sorted = sortBy (comparing (Down . snd)) scored
  in take 5 (map fst sorted)

-- | Dialogic strategy: Focus on interaction and communication
dialogicStrategy 
  :: Field 
  -> PredicateContext 
  -> ContentSelector 
  -> [ContextualPredicate]
dialogicStrategy field context selector =
  let dialogPredicates = dialogFocusedPredicates (pcConversationalMode context) (pcTopic context)
  in [ ContextualPredicate
        { cpPredicate = pred
        , cpRelevance = 0.85
        , cpSource = "dialogic"
        , cpFieldAffinity = 0.8
        }
     | pred <- dialogPredicates
     ]
  where
    dialogFocusedPredicates mode mTopic = case mode of
      "explanation" -> explanationPredicates mTopic
      "clarification" -> clarificationPredicates mTopic
      "exploration" -> explorationPredicates mTopic
      _ -> generalDialogicPredicates mTopic

-- | Reflective strategy: Focus on self-awareness and introspection
reflectiveStrategy 
  :: Field 
  -> PredicateContext 
  -> ContentSelector 
  -> [ContextualPredicate]
reflectiveStrategy field context selector =
  let reflectionLevel = case fhConsolidation (fieldHeuristics field) of
                          Consolidation c -> c
                          _ -> 0.5
      predicates = reflectionPredicates reflectionLevel (pcTopic context)
  in [ ContextualPredicate
        { cpPredicate = pred
        , cpRelevance = 0.9
        , cpSource = "reflective"
        , cpFieldAffinity = 0.85
        }
     | pred <- predicates
     ]

-- ============================================================================
-- PREDICATE ADAPTATION
-- ============================================================================

-- | Adapt existing predicates to current Field
adaptPredicateToField :: SemanticPredicate -> Field -> SemanticPredicate
adaptPredicateToField predicate field =
  let fieldIntensity = fieldIntensityScore field
      adaptedText = adaptTextToIntensity (spRu predicate) fieldIntensity
      adaptedEn = adaptTextToIntensity (spEn predicate) fieldIntensity
  in predicate
     { spRu = adaptedText
     , spEn = adaptedEn
     }
  where
    fieldIntensityScore :: Field -> Double
    fieldIntensityScore f = 
      let resonance = case fhResonance (fieldHeuristics f) of Resonance r -> r; _ -> 0.5
          counter = case fhCounterfactual (fieldHeuristics f) of Counterfactual c -> c; _ -> 0.5
      in (resonance + counter) / 2
    
    adaptTextToIntensity :: Text -> Double -> Text
    adaptTextToIntensity text intensity
      | intensity > 0.8 = text <> " (усилено)"
      | intensity < 0.3 = text <> " (ослаблено)"
      | otherwise = text

-- | Intensify a predicate (make it stronger)
intensifyPredicate :: SemanticPredicate -> SemanticPredicate
intensifyPredicate pred =
  let ruText = spRu pred
      enText = spEn pred
      intensifiers = [("очень ", "very "), ("крайне ", "extremely "), ("абсолютно ", "absolutely ")]
      -- Add intensifier if not already present
      newRu = if any (`T.isPrefixOf` ruText) (map fst intensifiers)
                 then ruText
                 else "очень " <> ruText
      newEn = if any (`T.isPrefixOf` enText) (map snd intensifiers)
                 then enText
                 else "very " <> enText
  in pred { spRu = newRu, spEn = newEn }

-- | Mitigate a predicate (make it weaker)
mitigatePredicate :: SemanticPredicate -> SemanticPredicate
mitigatePredicate pred =
  let ruText = spRu pred
      enText = spEn pred
      mitigators = [("в некоторой мере ", "to some extent "), ("частично ", "partially "), ("пока ", "so far ")]
      newRu = if any (`T.isPrefixOf` ruText) (map fst mitigators)
                 then ruText
                 else "в некоторой мере " <> ruText
      newEn = if any (`T.isPrefixOf` enText) (map snd mitigators)
                 then enText
                 else "to some extent " <> enText
  in pred { spRu = newRu, spEn = newEn }

-- ============================================================================
-- CONTEXT ANALYSIS
-- ============================================================================

-- | Score predicate relevance to current context
scorePredicateRelevance 
  :: Field 
  -> PredicateContext 
  -> ContextualPredicate 
  -> Double
scorePredicateRelevance field context cp =
  let fieldScore = cpFieldAffinity cp
      contextScore = scoreContextMatch context (cpPredicate cp)
      -- Weighted combination
      weightedScore = 0.6 * fieldScore + 0.4 * contextScore
  in weightedScore
  where
    scoreContextMatch :: PredicateContext -> SemanticPredicate -> Double
    scoreContextMatch ctx pred =
      case pcTopic ctx of
        Just topic -> if topic `T.isInfixOf` spRu pred then 0.9 else 0.5
        Nothing -> 0.7

-- ============================================================================
-- PREDICATE TEMPLATES
-- ============================================================================

-- | Predicate templates with placeholders for dynamic generation
-- These are used to generate context-specific predicates
data PredicateTemplate = PredicateTemplate
  { ptTemplate :: !Text           -- ^ Russian template with {topic} placeholder
  , ptTemplateEn :: !Text         -- ^ English template
  , ptRole :: !Role               -- ^ Predicate role
  , ptCondition :: !(Field -> Bool) -- ^ When to use this template
  }

-- | Collection of predicate templates
predicateTemplates :: [PredicateTemplate]
predicateTemplates =
  [ -- High confidence templates
    PredicateTemplate
      { ptTemplate = "{topic} проявляется в текущем контексте"
      , ptTemplateEn = "{topic} manifests in the current context"
      , ptRole = RoleProperty
      , ptCondition = \f -> fieldConfidence f > 0.7
      }
    
    , PredicateTemplate
      { ptTemplate = "{topic} требует углубленного анализа"
      , ptTemplateEn = "{topic} requires in-depth analysis"
      , ptRole = RoleProperty
      , ptCondition = \f -> fieldConfidence f < 0.5
      }
    
    -- High resonance templates
    , PredicateTemplate
      { ptTemplate = "{topic} находится в фокусе внимания"
      , ptTemplateEn = "{topic} is in the focus of attention"
      , ptRole = RoleProperty
      , ptCondition = \f -> resonanceLevel f > 0.7
      }
    
    -- Counterfactual templates
    , PredicateTemplate
      { ptTemplate = "{topic} могло бы быть иным"
      , ptTemplateEn = "{topic} could have been different"
      , ptRole = RoleStructure
      , ptCondition = \f -> counterfactualLevel f > 0.6
      }
    
    -- Dialogic templates
    , PredicateTemplate
      { ptTemplate = "{topic} обсуждается в диалоге"
      , ptTemplateEn = "{topic} is being discussed in dialogue"
      , ptRole = RoleProperty
      , ptCondition = \_ -> True  -- Always applicable
      }
    
    -- Reflective templates
    , PredicateTemplate
      { ptTemplate = "{topic} вызывает размышления"
      , ptTemplateEn = "{topic} provokes reflections"
      , ptRole = RoleRelation
      , ptCondition = \f -> consolidationLevel f > 0.5
      }
    
    -- Connective templates
    , PredicateTemplate
      { ptTemplate = "{topic} связано с другими концепциями"
      , ptTemplateEn = "{topic} is connected to other concepts"
      , ptRole = RoleRelation
      , ptCondition = \_ -> True
      }
  ]
  where
    fieldConfidence f = case fhConfidence (fieldHeuristics f) of FieldConfidence c -> c; _ -> 0.5
    resonanceLevel f = case fhResonance (fieldHeuristics f) of Resonance r -> r; _ -> 0.5
    counterfactualLevel f = case fhCounterfactual (fieldHeuristics f) of Counterfactual c -> c; _ -> 0.5
    consolidationLevel f = case fhConsolidation (fieldHeuristics f) of Consolidation c -> c; _ -> 0.5

-- | Expand templates into concrete predicates based on Field and context
expandPredicateTemplates 
  :: Field 
  -> PredicateContext 
  -> [SemanticPredicate]
expandPredicateTemplates field context =
  [ SemanticPredicate
      { spRole = ptRole template
      , spRu = T.replace "{topic}" (fromMaybe "концепция" (pcTopic context)) (ptTemplate template)
      , spEn = T.replace "{topic}" (fromMaybe "concept" (pcTopic context)) (ptTemplateEn template)
      , spTopicForm = fromMaybe "концепция" (pcTopic context)
      , spOrigin = Nothing
      , spRationale = Nothing
      , spSynthesis = Nothing
      }
  | template <- predicateTemplates
  , ptCondition template field
  ]

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- | Field-adaptive predicates based on confidence and resonance
fieldAdaptivePredicates :: Double -> Double -> Maybe Text -> [SemanticPredicate]
fieldAdaptivePredicates confidence resonance mTopic =
  let baseTopic = fromMaybe "это" mTopic
      predicates = []
  in predicates

-- | Predicates for explanation mode
explanationPredicates :: Maybe Text -> [SemanticPredicate]
explanationPredicates mTopic =
  let topic = fromMaybe "это" mTopic
  in [ mkProp (topic <> " объясняется через") (topic <> " is explained through")
     , mkProp (topic <> " требует разъяснения") (topic <> " requires explanation")
     ]
  where
    mkProp ru en = SemanticPredicate RoleProperty ru en (fromMaybe "это" mTopic) Nothing Nothing Nothing Nothing

-- | Predicates for clarification mode
clarificationPredicates :: Maybe Text -> [SemanticPredicate]
clarificationPredicates mTopic =
  let topic = fromMaybe "это" mTopic
  in [ mkProp (topic <> " уточняется через") (topic <> " is clarified through")
     , mkProp ("необходимо прояснить " <> topic) ("it is necessary to clarify " <> topic)
     ]
  where
    mkProp ru en = SemanticPredicate RoleProperty ru en (fromMaybe "это" mTopic) Nothing Nothing Nothing Nothing

-- | Predicates for exploration mode
explorationPredicates :: Maybe Text -> [SemanticPredicate]
explorationPredicates mTopic =
  let topic = fromMaybe "это" mTopic
  in [ mkProp (topic <> " исследуется в") (topic <> " is explored in")
     , mkProp (topic <> " открывает новые перспективы") (topic <> " opens new perspectives")
     ]
  where
    mkProp ru en = SemanticPredicate RoleProperty ru en (fromMaybe "это" mTopic) Nothing Nothing Nothing Nothing

-- | General dialogic predicates
generalDialogicPredicates :: Maybe Text -> [SemanticPredicate]
generalDialogicPredicates mTopic =
  let topic = fromMaybe "это" mTopic
  in [ mkProp (topic <> " обсуждается") (topic <> " is discussed")
     , mkProp (topic <> " важно для диалога") (topic <> " is important for dialogue")
     ]
  where
    mkProp ru en = SemanticPredicate RoleProperty ru en (fromMaybe "это" mTopic) Nothing Nothing Nothing Nothing

-- | Reflection predicates based on consolidation level
reflectionPredicates :: Double -> Maybe Text -> [SemanticPredicate]
reflectionPredicates consolidationLevel mTopic =
  let topic = fromMaybe "это" mTopic
      predicates =
        [ mkProp (topic <> " отражает текущее состояние") (topic <> " reflects the current state")
        , mkProp (topic <> " требует саморефлексии") (topic <> " requires self-reflection")
        ]
  in if consolidationLevel > 0.7
        then mkProp (topic <> " интегрируется в понимание") (topic <> " is integrated into understanding") : predicates
        else predicates
  where
    mkProp ru en = SemanticPredicate RoleProperty ru en (fromMaybe "это" mTopic) Nothing Nothing Nothing Nothing

-- | State-based predicates
stateBasedPredicates :: [Text] -> Int -> [SemanticPredicate]
stateBasedPredicates unresolved turnCount =
  if not (null unresolved) && turnCount > 5
     then [ SemanticPredicate
             { spRole = RoleProperty
             , spRu = "необходимо разрешить " <> T.intercalate ", " unresolved
             , spEn = "it is necessary to resolve " <> T.intercalate ", " unresolved
             , spTopicForm = "проблема"
             , spOrigin = Nothing
             , spRationale = Nothing
             , spSynthesis = Nothing
             }
          ]
     else []

-- | Empty predicate context for testing
defaultPredicateContext :: PredicateContext
defaultPredicateContext = PredicateContext
  { pcTopic = Nothing
  , pcRecentTopics = []
  , pcUserIntent = Nothing
  , pcConversationalMode = "dialogue"
  , pcTurnCount = 0
  , pcUnresolvedIssues = []
  }