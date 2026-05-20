{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Signal
Description : WP4 — Bounded Phase-7 calibration signal.

Replaces the hardcoded @signal = 0.0@ in
'buildNextSystemState' with an explainable, bounded composite
computed from:

1. Conatus trend (from 'LearningNeedState' history slope),
2. Field uncertainty trend (counterfactual trajectory),
3. Repair-loop risk (frequency of recovery over a window),
4. Branch health trend (from 'KnowledgeTree').

The signal is clamped to [-1, 1].  Positive = empirical evidence
suggests the current weights/heuristics should shift in the direction
of the observed deficit.  Negative = evidence is contradictory or
improving; adaptation should be conservative.
-}
module QxFx0.Learning.Signal
  ( CalibrationSignal(..)
  , SignalComponents(..)
  , computeCalibrationSignal
  , emptySignalComponents
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Learning.Need (LearningNeedState(..), NeedTrend(..), lnsHistory)
import QxFx0.Learning.KnowledgeTree (KnowledgeTree, branchHealthTrend)

-- | Bounded calibration signal in [-1, 1].
newtype CalibrationSignal = CalibrationSignal { unCalibrationSignal :: Double }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Raw components that feed into the composite signal.
-- Each component is independently normalised to [-1, 1] before
-- weighting so the formula remains explainable.
data SignalComponents = SignalComponents
  { scConatusTrend      :: !Double
    -- ^ Slope of need level over the recent 3 history points.
    --   Positive = deficit worsening.
  , scUncertaintyTrend  :: !Double
    -- ^ Normalised counterfactual magnitude.  Positive = higher
    --   ambiguity / more alternative parses.
  , scLoopRisk          :: !Double
    -- ^ Normalised repair-loop frequency.  Positive = frequent
    --   recovery-driven turns.
  , scBranchHealthTrend :: !Double
    -- ^ Average branch health from the knowledge tree.
    --   Negative = tree is decaying.
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

emptySignalComponents :: SignalComponents
emptySignalComponents = SignalComponents
  { scConatusTrend = 0.0
  , scUncertaintyTrend = 0.0
  , scLoopRisk = 0.0
  , scBranchHealthTrend = 0.0
  }

-- | Compute the bounded calibration signal.
--
-- Formula (fixed weights for interpretability):
--
-- @
-- signal = clamp [-1,1] (
--     0.30 * conatusTrend
--   + 0.30 * uncertaintyTrend
--   + 0.20 * loopRisk
--   + 0.20 * (-branchHealthTrend)   -- decaying tree pushes signal up
-- )
-- @
--
-- Rationale:
-- * Conatus and uncertainty each get 30 % because they are the most
--   direct indicators of structural drift.
-- * Loop risk gets 20 % as a lagging but robust proxy.
-- * Branch health gets 20 % with inverted sign: a decaying
--   knowledge tree means the current calibration is failing to
--   retain useful structure, so adaptation pressure rises.
computeCalibrationSignal
  :: LearningNeedState
  -> Double       -- ^ current field counterfactual (raw [0,1])
  -> Int          -- ^ repair-loop count in recent window
  -> Int          -- ^ window size for loop normalisation
  -> KnowledgeTree
  -> (CalibrationSignal, SignalComponents)
computeCalibrationSignal needState counterfactual loopCount windowSize tree =
  let       -- 1. Conatus trend: slope over recent 3 points
      conatusTrend = case lnsHistory needState of
        (_, y2) : (_, y1) : (_, y0) : _ ->
          let avgSlope = ((y2 - y1) + (y1 - y0)) / 2.0
          in clampUnit (avgSlope * 5.0)  -- scale: 0.2 level diff -> 1.0
        _ -> 0.0

      -- 2. Uncertainty trend: raw counterfactual scaled to [-1,1]
      -- centred at 0.5; >0.5 positive, <0.5 negative
      uncertaintyTrend = clampUnit ((counterfactual - 0.5) * 4.0)

      -- 3. Loop risk: normalised by window size
      loopRisk =
        if windowSize <= 0
           then 0.0
           else clampUnit (fromIntegral loopCount / fromIntegral windowSize * 2.0 - 1.0)

      -- 4. Branch health trend: inverted so decay -> positive signal
      avgHealth = branchHealthTrend tree
      branchHealthTrend' = clampUnit (-avgHealth * 2.0)

      comps = SignalComponents
        { scConatusTrend = conatusTrend
        , scUncertaintyTrend = uncertaintyTrend
        , scLoopRisk = loopRisk
        , scBranchHealthTrend = branchHealthTrend'
        }

      rawSignal =
          0.30 * conatusTrend
        + 0.30 * uncertaintyTrend
        + 0.20 * loopRisk
        + 0.20 * branchHealthTrend'

      signal = CalibrationSignal (clampRange (-1.0) 1.0 rawSignal)

  in (signal, comps)

clampUnit :: Double -> Double
clampUnit x = max (-1.0) (min 1.0 x)

clampRange :: Double -> Double -> Double -> Double
clampRange lo hi x = max lo (min hi x)
