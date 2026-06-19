{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-| Bounded set with FIFO eviction.

This module provides a set data structure that maintains a maximum capacity
by evicting the oldest elements when full. Combines the fast lookup of 'Set'
with the ordering of 'Seq' to implement FIFO eviction policy.

== Use Cases

* Tracking evidence atoms in stance defense (max 50)
* Maintaining bounded history collections
* Any scenario requiring set semantics with size limits

== Complexity

* 'insertBounded': O(log n) for set operations + O(1) for seq operations
* 'memberBounded': O(log n)
* 'toListBounded': O(n)
-}
module QxFx0.Types.Collection.BoundedSet
  ( BoundedSet(..)
  , emptyBoundedSet
  , insertBounded
  , memberBounded
  , toListBounded
  , fromListBounded
  , sizeBounded
  , capacityBounded
  , nullBounded
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Sequence (Seq, empty, viewl, (|>))
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)

-- | Bounded set with FIFO eviction.
--
-- Maintains both a 'Seq' for ordering and a 'Set' for fast lookup.
-- When capacity is exceeded, the oldest element (head of seq) is evicted.
data BoundedSet a = BoundedSet
  { bsSeq :: !(Seq a)
    -- ^ Ordered sequence for FIFO eviction.
  , bsSet :: !(Set a)
    -- ^ Set for O(log n) membership testing.
  , bsCapacity :: !Int
    -- ^ Maximum capacity. Must be positive.
  } deriving stock (Eq, Show, Generic)

instance (Ord a, NFData a) => NFData (BoundedSet a)
instance (Ord a, ToJSON a) => ToJSON (BoundedSet a)
instance (Ord a, FromJSON a) => FromJSON (BoundedSet a)

-- | Create an empty bounded set with given capacity.
--
-- >>> emptyBoundedSet 50
-- BoundedSet {bsSeq = fromList [], bsSet = fromList [], bsCapacity = 50}
emptyBoundedSet :: Int -> BoundedSet a
emptyBoundedSet cap = BoundedSet
  { bsSeq = empty
  , bsSet = Set.empty
  , bsCapacity = max 1 cap  -- Ensure capacity is at least 1
  }

-- | Insert an element into the bounded set.
--
-- If the element already exists, the set is unchanged.
-- If the set is at capacity, the oldest element is evicted (FIFO).
--
-- >>> insertBounded "a" (emptyBoundedSet 2)
-- BoundedSet {bsSeq = fromList ["a"], bsSet = fromList ["a"], bsCapacity = 2}
--
-- >>> insertBounded "b" $ insertBounded "a" $ insertBounded "c" (emptyBoundedSet 2)
-- BoundedSet {bsSeq = fromList ["b","a"], bsSet = fromList ["a","b"], bsCapacity = 2}
insertBounded :: Ord a => a -> BoundedSet a -> BoundedSet a
insertBounded x bs
  -- Element already exists, no change
  | Set.member x (bsSet bs) = bs
  -- At capacity, evict oldest element
  | Seq.length (bsSeq bs) >= bsCapacity bs =
      case viewl (bsSeq bs) of
        Seq.EmptyL -> bs  -- Should not happen if capacity > 0
        oldest Seq.:< rest ->
          BoundedSet
            { bsSeq = rest |> x
            , bsSet = Set.insert x (Set.delete oldest (bsSet bs))
            , bsCapacity = bsCapacity bs
            }
  -- Below capacity, just insert
  | otherwise =
      BoundedSet
        { bsSeq = bsSeq bs |> x
        , bsSet = Set.insert x (bsSet bs)
        , bsCapacity = bsCapacity bs
        }

-- | Check if an element is a member of the bounded set.
--
-- >>> memberBounded "a" $ insertBounded "a" (emptyBoundedSet 10)
-- True
--
-- >>> memberBounded "b" $ insertBounded "a" (emptyBoundedSet 10)
-- False
memberBounded :: Ord a => a -> BoundedSet a -> Bool
memberBounded x bs = Set.member x (bsSet bs)

-- | Convert bounded set to list (in insertion order).
--
-- >>> toListBounded $ insertBounded "b" $ insertBounded "a" (emptyBoundedSet 10)
-- ["a","b"]
toListBounded :: BoundedSet a -> [a]
toListBounded = foldr (:) [] . bsSeq

-- | Create bounded set from list (respects capacity).
--
-- Elements are inserted in order; oldest are evicted if list exceeds capacity.
--
-- >>> fromListBounded 2 ["a", "b", "c"]
-- BoundedSet {bsSeq = fromList ["b","c"], bsSet = fromList ["b","c"], bsCapacity = 2}
fromListBounded :: Ord a => Int -> [a] -> BoundedSet a
fromListBounded cap = foldr insertBounded (emptyBoundedSet cap)

-- | Get the current size of the bounded set.
--
-- >>> sizeBounded $ insertBounded "a" $ insertBounded "b" (emptyBoundedSet 10)
-- 2
sizeBounded :: BoundedSet a -> Int
sizeBounded = Seq.length . bsSeq

-- | Get the capacity of the bounded set.
--
-- >>> capacityBounded (emptyBoundedSet 50)
-- 50
capacityBounded :: BoundedSet a -> Int
capacityBounded = bsCapacity

-- | Check if the bounded set is empty.
--
-- >>> nullBounded (emptyBoundedSet 10)
-- True
--
-- >>> nullBounded $ insertBounded "a" (emptyBoundedSet 10)
-- False
nullBounded :: BoundedSet a -> Bool
nullBounded = Seq.null . bsSeq
