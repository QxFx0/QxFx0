{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.ContentSelector.Cache
  ( PredicateScoreCache
  , VectorCache
  , emptyPredicateScoreCache
  , emptyVectorCache
  , lookupPredicateScore
  , insertPredicateScore
  , lookupVector
  , insertVector
  , ScoreCacheKey(..)
  , VectorCacheKey(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Hashable (Hashable)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import GHC.Generics (Generic)
import Data.Vector (Vector)

-- | Cache key for predicate scoring: combines field hash, topic, and predicate identifier
-- We use a simplified key that captures the essential scoring parameters
data ScoreCacheKey = ScoreCacheKey
  { sckTopic :: !Text
  , sckPredicateId :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance Hashable ScoreCacheKey
instance Ord ScoreCacheKey where
  compare (ScoreCacheKey t1 p1) (ScoreCacheKey t2 p2) =
    compare (t1, p1) (t2, p2)

-- | Cache for predicate scores: maps (topic, predicate) pairs to their computed scores
-- This avoids recomputing expensive scoring operations for frequently accessed predicates
type PredicateScoreCache = Map ScoreCacheKey Double

emptyPredicateScoreCache :: PredicateScoreCache
emptyPredicateScoreCache = M.empty

-- | Lookup a cached predicate score
lookupPredicateScore :: ScoreCacheKey -> PredicateScoreCache -> Maybe Double
lookupPredicateScore key cache = M.lookup key cache

-- | Insert a computed predicate score into the cache
insertPredicateScore :: ScoreCacheKey -> Double -> PredicateScoreCache -> PredicateScoreCache
insertPredicateScore key score cache = M.insert key score cache

-- | Cache key for atom vectors: based on atom set hash
newtype VectorCacheKey = VectorCacheKey { unVectorCacheKey :: Text }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, Hashable)

instance Ord VectorCacheKey where
  compare (VectorCacheKey a) (VectorCacheKey b) = compare a b

-- | Cache for pre-computed atom vectors
-- Maps atom set identifiers to their vector representations
type VectorCache = Map VectorCacheKey (Vector Double)

emptyVectorCache :: VectorCache
emptyVectorCache = M.empty

-- | Lookup a cached vector
lookupVector :: VectorCacheKey -> VectorCache -> Maybe (Vector Double)
lookupVector key cache = M.lookup key cache

-- | Insert a computed vector into the cache
insertVector :: VectorCacheKey -> Vector Double -> VectorCache -> VectorCache
insertVector key vec cache = M.insert key vec cache
