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
  , rootStressSignal
  , graftFruit
  , quarantineFruit
  , promoteFromQuarantine
  , pruneBranches
  , pruneFruits
  , branchHealthTrend
  , treeCounters
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Foldable (foldl')
import qualified Data.List as L
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Origin of a piece of knowledge.
data KnowledgeSource
  = SourceInternal
  | SourceLLM
  | SourceHuman
  | SourceScript
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | A single unit of learned knowledge.
data KnowledgeFruit = KnowledgeFruit
  { kfProposition     :: !Text
    -- ^ The learned statement / rule / concept.
  , kfSource          :: !KnowledgeSource
    -- ^ Where it came from.
  , kfValidated       :: !Bool
    -- ^ Passed basic syntactic / range verification.
  , kfConatusDelta    :: !Double
    -- ^ Estimated impact on Conatus energy.  Positive = strengthening.
  , kfPredictiveDelta :: !Double
    -- ^ Estimated impact on repair-loop / uncertainty reduction.
    --   Positive = improves prediction quality.
  , kfGraftedTurn     :: !(Maybe Int)
    -- ^ Turn when grafted into a branch (Nothing if still quarantined).
  , kfObservedTurn    :: !Int
    -- ^ Turn when the fruit was first observed / proposed.
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON KnowledgeFruit where
  toJSON f = object
    [ "proposition"     .= kfProposition f
    , "source"          .= kfSource f
    , "validated"       .= kfValidated f
    , "conatusDelta"    .= kfConatusDelta f
    , "predictiveDelta" .= kfPredictiveDelta f
    , "graftedTurn"     .= kfGraftedTurn f
    , "observedTurn"    .= kfObservedTurn f
    ]

instance FromJSON KnowledgeFruit where
  parseJSON = withObject "KnowledgeFruit" $ \o ->
    KnowledgeFruit
      <$> o .:  "proposition"
      <*> o .:  "source"
      <*> o .:? "validated" .!= False
      <*> o .:? "conatusDelta" .!= 0.0
      <*> o .:? "predictiveDelta" .!= 0.0
      <*> o .:? "graftedTurn" .!= Nothing
      <*> o .:? "observedTurn" .!= 0

-- | A branch holds fruit aligned with a particular reconcile rule.
data Branch = Branch
  { brRule        :: !Text
    -- ^ Rendered reconcile-rule name (e.g. "agreement").
  , brFruits      :: ![KnowledgeFruit]
    -- ^ Grafted fruits.
  , brHealth      :: !Double
    -- ^ Structural health in [-1, 1].  Negative = decaying.
  , brCreatedTurn :: !Int
    -- ^ Turn when the branch was created.
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON Branch where
  toJSON b = object
    [ "rule"        .= brRule b
    , "fruits"      .= brFruits b
    , "health"      .= brHealth b
    , "createdTurn" .= brCreatedTurn b
    ]

instance FromJSON Branch where
  parseJSON = withObject "Branch" $ \o ->
    Branch
      <$> o .:  "rule"
      <*> o .:? "fruits" .!= []
      <*> o .:? "health" .!= 0.0
      <*> o .:? "createdTurn" .!= 0

-- | The rooted knowledge tree.
data KnowledgeTree = KnowledgeTree
  { ktRootMode       :: !Text
    -- ^ 'renderEssenceMode' of the committed essence serving as root.
  , ktRootTrigger    :: !Text
    -- ^ 'renderCommitmentTrigger' of the committed essence.
  , ktBranches       :: !(M.Map Text [Branch])
    -- ^ Branches keyed by reconcile-rule name.
  , ktQuarantine     :: ![KnowledgeFruit]
    -- ^ Valid but marginal fruits awaiting promotion or pruning.
  , ktPrunedCount    :: !Int
    -- ^ Lifetime count of pruned fruits (telemetry).
  , ktGraftedCount   :: !Int
    -- ^ Lifetime count of grafted fruits (telemetry).
  , ktQuarantinedCount :: !Int
    -- ^ Lifetime count of quarantined fruits (telemetry).
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON KnowledgeTree where
  toJSON t = object
    [ "rootMode"         .= ktRootMode t
    , "rootTrigger"      .= ktRootTrigger t
    , "branches"         .= ktBranches t
    , "quarantine"       .= ktQuarantine t
    , "prunedCount"      .= ktPrunedCount t
    , "graftedCount"     .= ktGraftedCount t
    , "quarantinedCount" .= ktQuarantinedCount t
    ]

instance FromJSON KnowledgeTree where
  parseJSON = withObject "KnowledgeTree" $ \o ->
    KnowledgeTree
      <$> o .:? "rootMode" .!= ""
      <*> o .:? "rootTrigger" .!= ""
      <*> o .:? "branches" .!= M.empty
      <*> o .:? "quarantine" .!= []
      <*> o .:? "prunedCount" .!= 0
      <*> o .:? "graftedCount" .!= 0
      <*> o .:? "quarantinedCount" .!= 0

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
quarantineFruit :: KnowledgeFruit -> KnowledgeTree -> KnowledgeTree
quarantineFruit fruit t =
  t { ktQuarantine = fruit : ktQuarantine t
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
      -- Only promote validated fruits with non-negative net delta
      (promotable, reject) =
        span (\f -> kfValidated f && netDelta f >= 0.0) ripe
      netDelta f = kfConatusDelta f + kfPredictiveDelta f
      t' = foldl' (\acc f -> graftFruit rule f acc)
              (t { ktQuarantine = stillQuarantined ++ reject
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
  let pred b = brHealth b >= threshold
            || currentTurn - brCreatedTurn b < minAge
  in L.partition pred bs

-- | Prune individual fruits that are unvalidated or have persistently
-- negative deltas.  Also cleans quarantine of unvalidated items.
pruneFruits :: Int -> KnowledgeTree -> (KnowledgeTree, Int)
pruneFruits _currentTurn t =
  let pruneBranch b =
        let kept = filter (\f -> kfValidated f && netDelta f >= (-0.3)) (brFruits b)
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
  where
    netDelta f = kfConatusDelta f + kfPredictiveDelta f

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

-- | Clamp to [0, 1].
clampUnit :: Double -> Double
clampUnit x = max 0.0 (min 1.0 x)
