{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.KnowledgeTree
Description : WP1 — Rooted knowledge tree with grafting, pruning,
              and anti-dogmatism quarantine.

A 'KnowledgeTree' grows from a single root ('EssenceCommitment').
Every 'Branch' is keyed by a 'ReconcileRule' (as rendered text) and
holds 'KnowledgeFruit' that have passed root-connection, validation,
and simulation gates.

Fruits that are valid but marginal (weak simulation deltas) enter
a quarantine bucket rather than being grafted immediately — the
anti-dogmatism mechanism.  After a monitoring window they are either
promoted to the tree or pruned.
-}
module QxFx0.Learning.KnowledgeTree
  ( KnowledgeSource(..)
  , KnowledgeFruit(..)
  , Branch(..)
  , KnowledgeTree(..)
  , emptyKnowledgeTree
  , defaultRootStressThreshold
  , maxKnowledgeQuarantineSize
  , rootStressSignal
  , graftFruit
  , quarantineFruit
  , promoteFromQuarantine
  , authoritativeNetDelta
  , pruneBranches
  , pruneFruits
  , branchHealthTrend
  , treeCounters
  , isTermKnownInKnowledgeTree
  ) where

import Data.Foldable (foldl')
import qualified Data.List as L
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Types.Learning.KnowledgeTree

emptyKnowledgeTree :: KnowledgeTree
emptyKnowledgeTree = KnowledgeTree
  { ktRootMode       = ""
  , ktRootTrigger    = ""
  , ktBranches       = M.empty
  , ktQuarantine     = []
  , ktPrunedCount    = 0
  , ktGraftedCount   = 0
  , ktQuarantinedCount = 0
  }

-- | Threshold for root stress signal.
defaultRootStressThreshold :: Double
defaultRootStressThreshold = 0.7

-- | Maximum number of fruits in quarantine (bounded memory).
maxKnowledgeQuarantineSize :: Int
maxKnowledgeQuarantineSize = 200

-- | Compute a root stress signal in [0, 1].
-- High stress means many valid fruits are sitting in quarantine
-- (not grafting) or branches are systemically unhealthy — a signal
-- that the root may be under tension without auto-switching it.
rootStressSignal :: KnowledgeTree -> Double
rootStressSignal t =
  let totalFruits = ktGraftedCount t + ktQuarantinedCount t
      quarantineRatio =
        if totalFruits == 0
           then 0.0
           else fromIntegral (ktQuarantinedCount t) / fromIntegral totalFruits
      -- Average branch health (0 if no branches)
      allBranches = concat (M.elems (ktBranches t))
      avgHealth =
        if null allBranches
           then 0.0
           else sum (map brHealth allBranches) / fromIntegral (length allBranches)
      -- Health inversion: negative health → high stress
      healthStress = max 0.0 (-avgHealth)
  in clampUnit (0.5 * quarantineRatio + 0.5 * healthStress)

-- | Graft a validated + simulated fruit into a branch.
-- If the branch for the rule does not exist, it is created.
graftFruit :: Text -> KnowledgeFruit -> KnowledgeTree -> KnowledgeTree
graftFruit rule fruit t =
  let fruit' = fruit { kfGraftedTurn = Just (kfObservedTurn fruit) }
      newBranch = Branch
        { brRule = rule
        , brFruits = [fruit']
        , brHealth = 0.0
        , brCreatedTurn = kfObservedTurn fruit
        }
      updateBranches [] = [newBranch]
      updateBranches (b:bs)
        | brRule b == rule =
            b { brFruits = fruit' : brFruits b
              , brHealth = min 1.0 (brHealth b + 0.1)
              } : bs
        | otherwise = b : updateBranches bs
      branches' = M.insertWith (\_ old -> updateBranches old) rule (updateBranches []) (ktBranches t)
  in t
       { ktBranches = branches'
       , ktGraftedCount = ktGraftedCount t + 1
       }

-- | Place a fruit into quarantine (anti-dogmatism).
-- Enforces bounded quarantine size with newest-first retention (LRU eviction).
quarantineFruit :: KnowledgeFruit -> KnowledgeTree -> KnowledgeTree
quarantineFruit fruit t =
  let quarantine' = take maxKnowledgeQuarantineSize (fruit : ktQuarantine t)
  in t { ktQuarantine = quarantine'
       , ktQuarantinedCount = ktQuarantinedCount t + 1
       }

-- | Promote quarantined fruits that have aged enough and show
-- positive deltas.  Returns (updated tree, promoted count, remaining
-- quarantined).
promoteFromQuarantine
  :: Int        -- ^ current turn
  -> Int        -- ^ minimum quarantine age (turns)
  -> Text       -- ^ rule to graft under
  -> KnowledgeTree
  -> (KnowledgeTree, Int, Int)
promoteFromQuarantine currentTurn minAge rule t =
  let (ripe, stillQuarantined) =
        partitionQuarantine currentTurn minAge (ktQuarantine t)
      -- Only promote validated fruits with non-negative authoritative net delta.
      (promotable, reject) =
        span (\f -> kfValidated f && authoritativeNetDelta f >= 0.0) ripe
      -- Enforce bounded quarantine: keep only newest entries if size exceeds limit
      quarantine' = take maxKnowledgeQuarantineSize (stillQuarantined ++ reject)
      t' = foldl' (\acc f -> graftFruit rule f acc)
              (t { ktQuarantine = quarantine'
                 , ktQuarantinedCount = max 0 (ktQuarantinedCount t - length promotable)
                 })
              promotable
      promoted = length promotable
      rejected = length reject
  in (t', promoted, rejected)

partitionQuarantine :: Int -> Int -> [KnowledgeFruit] -> ([KnowledgeFruit], [KnowledgeFruit])
partitionQuarantine currentTurn minAge = go []
  where
    go acc [] = (acc, [])
    go acc (f:fs)
      | currentTurn - kfObservedTurn f >= minAge =
          go (f : acc) fs
      | otherwise =
          (acc, f : fs)

-- | Prune branches that have been unhealthy for K consecutive turns.
-- Returns (updated tree, pruned branch count).
pruneBranches :: Int -> Double -> Int -> KnowledgeTree -> (KnowledgeTree, Int)
pruneBranches currentTurn healthThreshold minUnhealthyTurns t =
  let allBranches = concat (M.elems (ktBranches t))
      -- A branch is pruned if its health has been below threshold
      -- and it has existed long enough
      (survivors, pruned) =
        partitionBranches currentTurn healthThreshold minUnhealthyTurns allBranches
      survivorsMap = foldl' insertBranch M.empty survivors
      insertBranch m b = M.insertWith (++) (brRule b) [b] m
      prunedFruitCount = sum (map (length . brFruits) pruned)
  in ( t { ktBranches = survivorsMap
         , ktPrunedCount = ktPrunedCount t + prunedFruitCount
         }
     , length pruned
     )

partitionBranches
  :: Int -> Double -> Int -> [Branch] -> ([Branch], [Branch])
partitionBranches currentTurn threshold minAge bs =
  let predicate b = brHealth b >= threshold
                 || currentTurn - brCreatedTurn b < minAge
  in L.partition predicate bs

-- | Prune individual fruits that are unvalidated or have persistently
-- negative deltas.  Also cleans quarantine of unvalidated items.
pruneFruits :: Int -> KnowledgeTree -> (KnowledgeTree, Int)
pruneFruits _currentTurn t =
  let pruneBranch b =
        let kept = filter (\f -> kfValidated f && authoritativeNetDelta f >= (-0.3)) (brFruits b)
            dropped = length (brFruits b) - length kept
            health' = brHealth b - 0.05 * fromIntegral dropped
        in (b { brFruits = kept, brHealth = max (-1.0) health' }, dropped)
      allBranches = concat (M.elems (ktBranches t))
      prunedBranches = map pruneBranch allBranches
      newMap = foldl' (\m (b, _) -> M.insertWith (++) (brRule b) [b] m) M.empty prunedBranches
      totalDropped = sum (map snd prunedBranches)
      -- Clean unvalidated quarantine items
      cleanQuarantine = filter kfValidated (ktQuarantine t)
      quarantineDropped = length (ktQuarantine t) - length cleanQuarantine
  in ( t { ktBranches = newMap
         , ktQuarantine = cleanQuarantine
         , ktPrunedCount = ktPrunedCount t + totalDropped + quarantineDropped
         }
      , totalDropped + quarantineDropped
      )

authoritativeNetDelta :: KnowledgeFruit -> Double
authoritativeNetDelta f = kfConatusDelta f + kfPredictiveDelta f

-- | Trend of average branch health over the tree.
branchHealthTrend :: KnowledgeTree -> Double
branchHealthTrend t =
  let allBranches = concat (M.elems (ktBranches t))
  in if null allBranches
        then 0.0
        else sum (map brHealth allBranches) / fromIntegral (length allBranches)

-- | Telemetry counters.
treeCounters :: KnowledgeTree -> (Int, Int, Int, Int)
treeCounters t =
  ( sum (map length (map brFruits (concat (M.elems (ktBranches t)))))
  , length (ktQuarantine t)
  , ktPrunedCount t
  , ktGraftedCount t
  )

-- | Check whether a surface term is already represented by a validated,
-- grafted fruit in any branch.  Searches by kfWord (if present) and falls
-- back to substring match on kfProposition for backward compatibility.
isTermKnownInKnowledgeTree :: Text -> KnowledgeTree -> Bool
isTermKnownInKnowledgeTree term tree =
  let lower = T.toLower term
      allFruits = concatMap brFruits (concat (M.elems (ktBranches tree)))
      matchesWord f = not (T.null (kfWord f)) && T.toLower (kfWord f) == lower
      matchesProp f = T.isInfixOf lower (T.toLower (kfProposition f))
  in any (\f -> kfValidated f && (matchesWord f || matchesProp f)) allFruits

-- | Clamp to [0, 1].  NaN inputs collapse to the lower bound so that
-- 'rootStressSignal' (and any other consumer) cannot leak non-finite
-- doubles into the calibration signal pipeline.  See regression G1.
clampUnit :: Double -> Double
clampUnit x
  | isNaN x   = 0.0
  | otherwise = max 0.0 (min 1.0 x)
