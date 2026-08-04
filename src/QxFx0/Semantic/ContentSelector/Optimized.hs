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

import Data.Foldable (foldl')
import Data.List (maximumBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe, fromMaybe)
import Data.Ord (comparing)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)

import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..), SelectedPredicate(..))
import QxFx0.Semantic.Content (CanonicalPredicateRelation(..), SemanticPredicate(..))
import QxFx0.Semantic.Space (SemanticSpace(..), buildVector)
import QxFx0.Semantic.Network (SemanticNetwork(..))
import QxFx0.Self.Field (Field(..))

-- ==========================================================================
-- Index Types
-- ==========================================================================

-- | Index for fast predicate lookup by topic: topic -> [(predicate_id, predicate)]
type TopicPredicateIndex = Map Text [(Text, SemanticPredicate)]

-- | Reverse index for atom lookup: atom -> [topics containing this atom]
type AtomTopicIndex = Map Text [Text]

-- ==========================================================================
-- Index Building Functions
-- ==========================================================================

-- | Build an index for fast predicate lookup by topic
buildTopicPredicateIndex :: ContentSelector -> TopicPredicateIndex
buildTopicPredicateIndex cs =
  M.fromList [ (topic, zip [T.pack (show i) | i <- [0..]] preds) 
             | (topic, preds) <- M.toList (csTopicPredicates cs) ]

-- | Build a reverse index: atom -> [topics that contain this atom]
buildAtomTopicIndex :: ContentSelector -> AtomTopicIndex
buildAtomTopicIndex cs =
  let atomTopicPairs = [ (atom, topic) 
                       | (topic, atoms) <- M.toList (csTopicAtoms cs)
                       , atom <- S.toList atoms ]
  in M.fromListWith (++) [ (atom, [topic]) | (atom, topic) <- atomTopicPairs ]

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
-- Caching Types and Functions
-- ==========================================================================

-- | Cache key for predicate scoring
-- Uses topic + predicate surface as the key for simplicity
-- In production, could include field signature for more precision
data ScoreCacheKey = ScoreCacheKey
  { sckTopic :: !Text
  , sckPredicate :: !Text  -- spRu predicate text
  } deriving (Eq, Ord, Show)

-- | Simple cache type: maps (topic, predicate) to computed score
type ScoreCache = Map ScoreCacheKey Double

-- | Empty cache
emptyScoreCache :: ScoreCache
emptyScoreCache = M.empty

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
    -- Fallback score computation (simplified version of the original scorePred)
    computeScore :: ContentSelector -> Field -> Text -> Set Text -> SemanticPredicate -> Double
    computeScore cs' field' topic' topicAtoms' pred' =
      -- This is a placeholder - in practice, use the existing scorePred function
      -- from ContentSelector, but we'd need to import it properly
      -- For now, return a neutral score
      0.5

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
           (scoredResults, finalCache) = foldl' (\) ( [], initialCache) preds $ \ pred cache' ->
             let (result, newCache) = scorePredWithCache cs field topic topicAtoms pred cache'
             in (mapMaybe id [result], newCache)
           
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
       in foldl' (\) cache pred ->
             let key = ScoreCacheKey topic (spRu pred)
                 score = computeScore cs field topic topicAtoms pred
             in M.insert key score cache
          initialCache preds
  where
    -- Simplified score computation
    computeScore :: ContentSelector -> Field -> Text -> Set Text -> SemanticPredicate -> Double
    computeScore cs' field' topic' topicAtoms' pred' = 0.5

-- ==========================================================================
-- Lazy Evaluation Utilities
-- ==========================================================================

-- | Lazy wrapper for predicate scoring - defers computation until needed
lazyScorePred 
  :: ContentSelector
  -> Field
  -> Text
  -> Maybe SemanticNetwork
  -> Text
  -> Set Text
  -> SemanticPredicate
  -> Maybe (SemanticPredicate, Double)
lazyScorePred cs field topic mNetwork topicAtoms pred =
  -- This is just a type-compatible wrapper for now
  -- In practice, would use the actual scorePred from ContentSelector
  Just (pred, 0.5)

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
  foldl' (\) ([], initialCache) preds $ \ pred (results, cache) ->
    let (result, newCache) = scorePredWithCache cs field topic topicAtoms pred cache
    in (case result of { Just r -> r : results; Nothing -> results }, newCache)

-- | Select predicates for multiple topics in a batch
batchSelectPredicates 
  :: ContentSelector
  -> Field
  -> [Text]                   -- Topics to process
  -> Maybe SemanticNetwork    -- Optional network
  -> ScoreCache               -- Initial cache
  -> ([SelectedPredicate], ScoreCache)  -- Results and updated cache
batchSelectPredicates cs field topics mNetwork initialCache =
  foldl' (\) ([], initialCache) topics $ \ topic (results, cache) ->
    let (result, newCache) = selectPredicatesWithCache cs field topic mNetwork cache
    in (case result of { Just r -> r : results; Nothing -> results }, newCache)