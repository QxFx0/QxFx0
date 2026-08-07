{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

-- | Optimized ContentSelector functions with caching and indexing
module QxFx0.Semantic.ContentSelector.Optimized
  ( -- * Index-based lookup
    TopicPredicateIndex
    , AtomTopicIndex
    , buildTopicPredicateIndex
    , buildAtomTopicIndex
    , lookupPredicatesByIndex
    , lookupAtomsByIndex
    , lookupTopicsByAtom
    
    -- * Caching types and functions
    , ScoreCache
    , emptyScoreCache
    , ScoreCacheKey(..)
    , scorePredWithCache
    , selectPredicatesWithCache
    , warmCacheForTopic
    , clearScoreCache
    
    -- * Lazy evaluation utilities
    , lazyScorePred
    , lazyBuildVector
    
    -- * Batch processing
    , batchScorePredicates
    , batchSelectPredicates
    ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import Data.Foldable (foldl')
import Data.List (maximumBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)
import GHC.Generics (Generic)

import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..), SelectedPredicate(..))
import QxFx0.Types.Semantic.Content (CanonicalPredicateRelation(..), SemanticPredicate(..))
import QxFx0.Semantic.ContentSelector (scorePred, buildVector)
import QxFx0.Semantic.Space (SemanticSpace(..))
import QxFx0.Semantic.Network (SemanticNetwork(..))
import QxFx0.Self.Field (Field(..))
import QxFx0.Types.Semantic.ContentSelector
  ( TopicPredicateIndex, AtomTopicIndex, ScoreCache, ScoreCacheKey(..)
  , emptyScoreCache, buildTopicPredicateIndex, buildAtomTopicIndex
  )

-- ==========================================================================
-- Index Lookup Functions (index construction moved to Types layer)
-- ==========================================================================

-- | Fast lookup of predicates for a topic using the pre-built index
lookupPredicatesByIndex :: TopicPredicateIndex -> Text -> [(Text, SemanticPredicate)]
lookupPredicatesByIndex index topic = M.findWithDefault [] topic index

-- | Fast lookup of atoms for a topic
lookupAtomsByIndex :: Map Text (Set Text) -> Text -> Set Text
lookupAtomsByIndex atomsMap topic = M.findWithDefault S.empty topic atomsMap

-- | Fast lookup of topics containing a specific atom
lookupTopicsByAtom :: AtomTopicIndex -> Text -> [Text]
lookupTopicsByAtom atomIndex atom = M.findWithDefault [] atom atomIndex

-- ==========================================================================
-- Caching Functions
-- ==========================================================================

-- | Clear the cache
clearScoreCache :: ScoreCache -> ScoreCache
clearScoreCache _ = emptyScoreCache

-- | Compute predicate score with caching
scorePredWithCache 
  :: ContentSelector
  -> Field
  -> Text                     -- Current topic
  -> Set Text                 -- Topic atoms
  -> SemanticPredicate        -- Predicate to score
  -> ScoreCache               -- Current cache
  -> (Maybe (SemanticPredicate, Double), ScoreCache)  -- (Result, Updated cache)
scorePredWithCache cs field topic topicAtoms pred cache =
  let key = ScoreCacheKey topic (spRu pred)
      mCached = M.lookup key cache
      -- If cached, return it
      baseScore = fromMaybe (computeScore cs field topic topicAtoms pred) mCached
  in (Just (pred, baseScore), if mCached == Just baseScore then cache else M.insert key baseScore cache)
  where
    -- Use the real scorePred function from ContentSelector
    computeScore :: ContentSelector -> Field -> Text -> Set Text -> SemanticPredicate -> Double
    computeScore cs' field' _topic' _topicAtoms' pred' =
      case scorePred field' (csSpace cs') (csLemmaMap cs') Nothing pred' of
        Just (_, score) -> score
        Nothing -> 0.0

-- | Select predicates for a topic with caching
selectPredicatesWithCache 
  :: ContentSelector
  -> Field
  -> Text                     -- Topic
  -> Maybe SemanticNetwork    -- Optional network for activation bonus
  -> ScoreCache               -- Initial cache
  -> (Maybe SelectedPredicate, ScoreCache)  -- Result and updated cache
selectPredicatesWithCache cs field topic mNetwork initialCache =
  case M.lookup topic (csTopicPredicates cs) of
     Nothing -> (Nothing, initialCache)
     Just preds ->
       let topicAtoms = M.findWithDefault S.empty topic (csTopicAtoms cs)
           -- Score all predicates for this topic
           (scoredResults, finalCache) = foldl' step ([], initialCache) preds
           step (acc, cache) pred =
             let (mResult, newCache) = scorePredWithCache cs field topic topicAtoms pred cache
             in (acc ++ maybe [] (: []) mResult, newCache)
           
           -- Find the best scoring predicate
           best = case scoredResults of
                    [] -> Nothing
                    _ -> Just (maximumBy (comparing snd) scoredResults)
       in case best of
            Nothing -> (Nothing, finalCache)
            Just (bestPred, bestScore) -> 
              (Just (SelectedPredicate topic bestScore [bestPred]), finalCache)

-- | Pre-warm the cache for a specific topic
warmCacheForTopic 
  :: ContentSelector
  -> Field
  -> Text                     -- Topic to warm cache for
  -> Maybe SemanticNetwork    -- Optional network
  -> ScoreCache               -- Initial cache
  -> ScoreCache               -- Updated cache with all predicates for this topic scored
warmCacheForTopic cs field topic mNetwork initialCache =
  case M.lookup topic (csTopicPredicates cs) of
     Nothing -> initialCache
     Just preds ->
       let topicAtoms = M.findWithDefault S.empty topic (csTopicAtoms cs)
       in foldl' (\cache pred ->
             let key = ScoreCacheKey topic (spRu pred)
                 score = computeScore cs field topic topicAtoms pred
             in M.insert key score cache)
          initialCache preds
  where
    -- Use the real scorePred function from ContentSelector
    computeScore :: ContentSelector -> Field -> Text -> Set Text -> SemanticPredicate -> Double
    computeScore cs' field' _topic' _topicAtoms' pred' =
      case scorePred field' (csSpace cs') (csLemmaMap cs') Nothing pred' of
        Just (_, score) -> score
        Nothing -> 0.0

-- ==========================================================================
-- Lazy Evaluation Utilities
-- ==========================================================================

-- | Lazy wrapper for predicate scoring - defers computation until needed
lazyScorePred 
  :: ContentSelector
  -> Field
  -> Text
  -> Maybe SemanticNetwork
  -> Set Text
  -> SemanticPredicate
  -> Maybe (SemanticPredicate, Double)
lazyScorePred cs field _topic mNetwork _topicAtoms pred =
  -- Use the actual scorePred from ContentSelector
  scorePred field (csSpace cs) (csLemmaMap cs) mNetwork pred

-- | Lazy vector builder - defers vector computation until needed
lazyBuildVector 
  :: SemanticSpace
  -> Set Text
  -> Vector Double
lazyBuildVector space atoms = buildVector space atoms

-- ==========================================================================
-- Batch Processing Functions
-- ==========================================================================

-- | Score multiple predicates in a batch
batchScorePredicates 
  :: ContentSelector
  -> Field
  -> Text                     -- Topic
  -> Set Text                 -- Topic atoms
  -> [SemanticPredicate]      -- Predicates to score
  -> ScoreCache               -- Initial cache
  -> ([(SemanticPredicate, Double)], ScoreCache)  -- Results and updated cache
batchScorePredicates cs field topic topicAtoms preds initialCache =
  foldl' (\ (results, cache) pred ->
    let (result, newCache) = scorePredWithCache cs field topic topicAtoms pred cache
    in (case result of { Just r -> r : results; Nothing -> results }, newCache))
    ([], initialCache) preds

-- | Select predicates for multiple topics in a batch
batchSelectPredicates 
  :: ContentSelector
  -> Field
  -> [Text]                   -- Topics to process
  -> Maybe SemanticNetwork    -- Optional network
  -> ScoreCache               -- Initial cache
  -> ([SelectedPredicate], ScoreCache)  -- Results and updated cache
batchSelectPredicates cs field topics mNetwork initialCache =
  foldl' (\ (results, cache) topic ->
    let (result, newCache) = selectPredicatesWithCache cs field topic mNetwork cache
    in (case result of { Just r -> r : results; Nothing -> results }, newCache))
    ([], initialCache) topics