{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Semantic.ContentSelector.Integration
  ( -- * Integration types
    ContentSelectorState(..)
    , emptyContentSelectorState
    
    -- * Initialization
    , initContentSelectorState
    , initSelectorWithOptimizations
    
    -- * Optimized selection with state
    , selectPredicatesOptimized
    , selectWithCaching
    
    -- * Dynamic learning integration
    , processLearningCycle
    , updateWithObservations
    
    -- * State utilities
    , getSelectorState
    , updateSelectorState
    ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Foldable (foldl')
import Data.List (maximumBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (comparing)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.AtomGraph (RelationType(..))
import QxFx0.Types.Semantic.ContentSelector
  ( ContentSelector(..), SelectedPredicate(..), ContentSelectorState(..)
  , emptyContentSelectorState, initContentSelectorState
  )
import QxFx0.Semantic.ContentSelector.Optimized (TopicPredicateIndex, AtomTopicIndex, ScoreCache, emptyScoreCache, buildTopicPredicateIndex, buildAtomTopicIndex, scorePredWithCache, selectPredicatesWithCache, warmCacheForTopic)
import QxFx0.Semantic.Content (SemanticPredicate(..))
import QxFx0.Semantic.Space (SemanticSpace(..))
import QxFx0.Semantic.Network (SemanticNetwork(..))
import QxFx0.Semantic.Ontology (Ontology(..), emptyOntology)
import QxFx0.Semantic.Ontology.Dynamic (LearningObservation(..), OntologyLearningConfig(..), DynamicOntologyState(..), learnFromObservations, updateContentSelectorWithLearned, learnFromContentSelector)
import QxFx0.Self.Field (Field(..))

-- | Initialize selector with all optimizations
initSelectorWithOptimizations 
  :: SemanticSpace 
  -> Map Text (Set Text) 
  -> Map Text [SemanticPredicate] 
  -> Map Text Text 
  -> Maybe Ontology 
  -> ContentSelectorState
initSelectorWithOptimizations space atoms predicates lemmaMap mOntology =
  let baseSelector = ContentSelector space atoms predicates lemmaMap mOntology
  in initContentSelectorState baseSelector

-- | Select predicates with caching optimization
selectPredicatesOptimized 
  :: ContentSelectorState
  -> Field
  -> Text
  -> Maybe SemanticNetwork
  -> (Maybe SelectedPredicate, ContentSelectorState)
selectPredicatesOptimized css field topic mNetwork =
  let (result, newCache) = selectPredicatesWithCache 
        (cssContentSelector css) field topic mNetwork 
        (cssScoreCache css)
      updatedCSS = css { cssScoreCache = newCache }
  in (result, updatedCSS)

-- | Select predicates with caching and learning
selectWithCaching 
  :: ContentSelectorState
  -> Field
  -> Text
  -> Maybe SemanticNetwork
  -> Int  -- Current timestamp
  -> (Maybe SelectedPredicate, ContentSelectorState)
selectWithCaching css field topic mNetwork timestamp =
  let (result, newCSS) = selectPredicatesOptimized css field topic mNetwork
      -- Optionally warm cache for this topic
      warmedCache = warmCacheForTopic (cssContentSelector newCSS) field topic mNetwork (cssScoreCache newCSS)
      finalCSS = newCSS { cssScoreCache = warmedCache }
  in (result, finalCSS)

-- | Process a learning cycle: observe, learn, update
processLearningCycle 
  :: ContentSelectorState
  -> Text  -- Current topic
  -> [SemanticPredicate]  -- Selected predicates
  -> Maybe SemanticNetwork  -- Activated network
  -> Int  -- Observation timestamp
  -> (ContentSelectorState, [LearningObservation])
processLearningCycle css currentTopic selectedPredicates mNetwork timestamp =
  let config = cssLearningConfig css
      state = cssLearningState css
      cs = cssContentSelector css
      (newState, observations) = learnFromContentSelector config cs currentTopic selectedPredicates mNetwork timestamp state
      updatedCSS = css { cssLearningState = newState }
  in (updatedCSS, observations)

-- | Update ContentSelectorState with learned ontology edges
updateWithObservations 
  :: ContentSelectorState
  -> [LearningObservation]
  -> (ContentSelectorState, [(Text, Text, RelationType)])
updateWithObservations css observations =
  let config = cssLearningConfig css
      mOntology = csOntology (cssContentSelector css)
      learningState = cssLearningState css
      ontology = fromMaybe emptyOntology mOntology
      (updatedOntology, newLearningState, learnedEdges) = learnFromObservations config ontology learningState observations
      updatedCS = css { cssLearningState = newLearningState }
      -- Update the ContentSelector with the new ontology
      -- learnedEdges is [(Text, Text, RelationType, Double)], we need to extract just the first 3 elements
      learnedEdges3 = map (\ (from, to, rel, _) -> (from, to, rel)) learnedEdges
      updatedContentSelector = case mOntology of
        Nothing -> cssContentSelector css
        Just ont -> updateContentSelectorWithLearned (cssContentSelector css) ont learnedEdges3
      finalCSS = updatedCS { cssContentSelector = updatedContentSelector }
  in (finalCSS, learnedEdges3)

-- | Get the base ContentSelector from state
getSelectorState :: ContentSelectorState -> ContentSelector
getSelectorState = cssContentSelector

-- | Update ContentSelector in state
updateSelectorState :: ContentSelectorState -> ContentSelector -> ContentSelectorState
updateSelectorState css newCS =
  css { cssContentSelector = newCS
      , cssPredicateIndex = buildTopicPredicateIndex newCS
      , cssAtomIndex = buildAtomTopicIndex newCS
      }