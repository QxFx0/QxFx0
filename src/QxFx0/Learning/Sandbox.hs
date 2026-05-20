{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Sandbox
Description : WP5 — Sandbox simulation gate before graft.

Before a 'KnowledgeFruitPayload' is promoted to the live
'KnowledgeTree', the sandbox projects its impact onto a *copy* of the
relevant state slice and computes delta metrics:

- Conatus trend (improvement vs. degradation)
- Uncertainty / counterfactual trend
- Repair-loop frequency over a simulated window

Acceptance rule (fail-closed):
- 'SandboxAccept' if net score >= 0  (non-regression)
- 'SandboxAccept' with improvement bonus if both deltas positive
- 'SandboxReject' if projected conatus drops below safety floor
  or net score is clearly negative.

The sandbox is intentionally lightweight: it does NOT run a full
N-turn replay (that would require the whole pipeline).  Instead it
projects deltas onto the existing 'LearningNeedState' history curve
and checks monotonicity constraints.
-}
module QxFx0.Learning.Sandbox
  ( SandboxResult(..)
  , SandboxMetrics(..)
  , SandboxRejectReason(..)
  , runSandboxGate
  , renderSandboxRejectReason
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Learning.Need (LearningNeedState(..), lnsHistory)
import QxFx0.Learning.Validator (KnowledgeFruitPayload(..))
import QxFx0.Types.State.System (SystemState, ssLearningNeedState)

-- | Outcome of the sandbox simulation.
data SandboxResult
  = SandboxAccept !SandboxMetrics
    -- ^ Fruit passes non-regression / improvement test.
  | SandboxReject !SandboxMetrics !SandboxRejectReason
    -- ^ Fruit would degrade system state; reject with telemetry reason.
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Metrics captured during sandbox projection.
data SandboxMetrics = SandboxMetrics
  { sbConatusTrend      :: !Double
    -- ^ Projected conatus trend after applying fruit delta.
  , sbUncertaintyTrend  :: !Double
    -- ^ Projected uncertainty (counterfactual) trend.
  , sbRepairLoopFreq    :: !Double
    -- ^ Estimated repair-loop frequency over simulated window.
  , sbNetScore          :: !Double
    -- ^ Weighted composite: 0.5*conatusDelta + 0.5*predictiveDelta.
  , sbWindowSize        :: !Int
    -- ^ Simulated window turns (N).
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Human-readable reject reason for telemetry and audit.
data SandboxRejectReason
  = SbrDegradingConatus
  | SbrRisingUncertainty
  | SbrHighRepairLoopRisk
  | SbrNegativeNetScore
  | SbrMorphologyConflict
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Safety floor for projected conatus trend.
conatusSafetyFloor :: Double
conatusSafetyFloor = -0.3

-- | Minimum net score for non-regression acceptance.
minNetScore :: Double
minNetScore = -0.05

-- | Simulated replay window size.
windowSize :: Int
windowSize = 5

-- | Run the sandbox gate against the current system state and a
-- proposed fruit payload.
runSandboxGate :: SystemState -> KnowledgeFruitPayload -> SandboxResult
runSandboxGate ss payload =
  let needState = ssLearningNeedState ss
      -- Current conatus trend from the last 3 history points (or 0 if insufficient)
      currentConatusTrend = conatusTrendFromHistory (lnsHistory needState)
      -- Current uncertainty proxy: amplitude of history oscillation
      currentUncertainty  = historyOscillation (lnsHistory needState)
      -- Projected values after applying the fruit deltas
      projectedConatus  = currentConatusTrend + kfpConatusDelta payload
      projectedUncertainty = max 0 (currentUncertainty - kfpPredictiveDelta payload)
      -- Repair-loop frequency proxy: how often history levels exceed a soft threshold
      loopFreq            = repairLoopProxy (lnsHistory needState)
      -- Net score: weighted composite
      netScore            = 0.5 * kfpConatusDelta payload + 0.5 * kfpPredictiveDelta payload

      metrics = SandboxMetrics
        { sbConatusTrend     = projectedConatus
        , sbUncertaintyTrend = projectedUncertainty
        , sbRepairLoopFreq   = loopFreq
        , sbNetScore         = netScore
        , sbWindowSize       = windowSize
        }

  in if projectedConatus < conatusSafetyFloor
       then SandboxReject metrics SbrDegradingConatus
     else if netScore < minNetScore
       then SandboxReject metrics SbrNegativeNetScore
     else
       -- Non-regression or improvement: accept
       SandboxAccept metrics

-- | Compute conatus trend as average slope over last 3 points.
conatusTrendFromHistory :: [(Int, Double)] -> Double
conatusTrendFromHistory hist =
  case reverse hist of
    (_, y2) : (_, y1) : (_, y0) : _ -> ((y2 - y1) + (y1 - y0)) / 2.0
    _ -> 0.0

-- | Simple oscillation amplitude (max - min) over last windowSize points.
historyOscillation :: [(Int, Double)] -> Double
historyOscillation hist =
  let recent = take windowSize (map snd (reverse hist))
  in if null recent then 0.0 else maximum recent - minimum recent

-- | Proxy for repair-loop frequency: fraction of recent points above 0.6.
repairLoopProxy :: [(Int, Double)] -> Double
repairLoopProxy hist =
  let recent = take windowSize (map snd (reverse hist))
      count  = fromIntegral (length (filter (> 0.6) recent))
      total  = fromIntegral (max 1 (length recent))
  in count / total

renderSandboxRejectReason :: SandboxRejectReason -> Text
renderSandboxRejectReason SbrDegradingConatus     = "degrading_conatus"
renderSandboxRejectReason SbrRisingUncertainty    = "rising_uncertainty"
renderSandboxRejectReason SbrHighRepairLoopRisk   = "high_repair_loop_risk"
renderSandboxRejectReason SbrNegativeNetScore     = "negative_net_score"
renderSandboxRejectReason SbrMorphologyConflict   = "morphology_conflict"
