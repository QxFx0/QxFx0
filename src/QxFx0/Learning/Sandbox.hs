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
  , SandboxConfig(..)
  , defaultSandboxConfig
  , runSandboxGate
  , runSandboxGateWithConfig
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
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Configurable sandbox parameters.
-- Low-RAM safe: small window, tight timeout budget, strict floor.
data SandboxConfig = SandboxConfig
  { scWindowSize        :: !Int
    -- ^ History window for trend projection (default 5).
  , scSafetyFloor       :: !Double
    -- ^ Minimum acceptable projected conatus trend (default -0.3).
  , scMinNetScore       :: !Double
    -- ^ Minimum weighted composite for non-regression (default -0.05).
  , scMaxUncertaintyIncrease :: !Double
    -- ^ Maximum allowed projected uncertainty increase over the current
    --   baseline (default 0.20).
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

defaultSandboxConfig :: SandboxConfig
defaultSandboxConfig = SandboxConfig
  { scWindowSize        = 5
  , scSafetyFloor       = -0.3
  , scMinNetScore       = -0.05
  , scMaxUncertaintyIncrease = 0.20
  }

-- | Safety floor for projected conatus trend.
conatusSafetyFloor :: Double
conatusSafetyFloor = -0.3

-- | Minimum net score for non-regression acceptance.
minNetScore :: Double
minNetScore = -0.05

-- | Simulated replay window size.
windowSize :: Int
windowSize = 5

-- | Run the sandbox gate with default configuration.
runSandboxGate :: SystemState -> KnowledgeFruitPayload -> SandboxResult
runSandboxGate = runSandboxGateWithConfig defaultSandboxConfig

-- | Run the sandbox gate with explicit configuration.
--
-- Acceptance policy (fail-closed):
-- 1. Strict non-regression: projected conatus >= safetyFloor AND netScore >= minNetScore.
-- 2. Improvement bonus: if both conatusDelta and predictiveDelta are > 0,
--    the netScore threshold is relaxed slightly.
-- 3. Bounded uncertainty increase: if the projected uncertainty rises too far
--    above the current baseline, reject with 'SbrRisingUncertainty'.
runSandboxGateWithConfig :: SandboxConfig -> SystemState -> KnowledgeFruitPayload -> SandboxResult
runSandboxGateWithConfig cfg ss payload =
  let needState = ssLearningNeedState ss
      -- Current conatus trend from the last 3 history points (or 0 if insufficient)
      currentConatusTrend = conatusTrendFromHistory (lnsHistory needState)
      -- Current uncertainty proxy: amplitude of history oscillation
      currentUncertainty  = historyOscillationWithWindow (scWindowSize cfg) (lnsHistory needState)
      -- Projected values after applying the fruit deltas
      projectedConatus  = currentConatusTrend + kfpConatusDelta payload
      projectedUncertainty = max 0 (currentUncertainty - kfpPredictiveDelta payload)
      -- Repair-loop frequency proxy: how often history levels exceed a soft threshold
      loopFreq            = repairLoopProxyWithWindow (scWindowSize cfg) (lnsHistory needState)
      -- Net score: weighted composite with improvement bonus
      rawNetScore         = 0.5 * kfpConatusDelta payload + 0.5 * kfpPredictiveDelta payload
      -- Improvement bonus: both deltas positive -> relax threshold by 0.05
      improvementBonus    = if kfpConatusDelta payload > 0 && kfpPredictiveDelta payload > 0 then 0.05 else 0.0
      netScore            = rawNetScore + improvementBonus

      metrics = SandboxMetrics
        { sbConatusTrend     = projectedConatus
        , sbUncertaintyTrend = projectedUncertainty
        , sbRepairLoopFreq   = loopFreq
        , sbNetScore         = netScore
        , sbWindowSize       = scWindowSize cfg
        }

      effectiveMinScore = scMinNetScore cfg

  in if projectedConatus < scSafetyFloor cfg
       then SandboxReject metrics SbrDegradingConatus
      else if projectedUncertainty > currentUncertainty + scMaxUncertaintyIncrease cfg
        then SandboxReject metrics SbrRisingUncertainty
      else if netScore < effectiveMinScore
        then SandboxReject metrics SbrNegativeNetScore
      else if loopFreq > 0.8
        then SandboxReject metrics SbrHighRepairLoopRisk
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
historyOscillationWithWindow :: Int -> [(Int, Double)] -> Double
historyOscillationWithWindow configuredWindow hist =
  let recent = take (max 1 configuredWindow) (map snd (reverse hist))
  in if null recent then 0.0 else maximum recent - minimum recent

-- | Proxy for repair-loop frequency: fraction of recent points above 0.6.
repairLoopProxyWithWindow :: Int -> [(Int, Double)] -> Double
repairLoopProxyWithWindow configuredWindow hist =
  let recent = take (max 1 configuredWindow) (map snd (reverse hist))
      count  = fromIntegral (length (filter (> 0.6) recent))
      total  = fromIntegral (max 1 (length recent))
  in count / total

renderSandboxRejectReason :: SandboxRejectReason -> Text
renderSandboxRejectReason SbrDegradingConatus     = "degrading_conatus"
renderSandboxRejectReason SbrRisingUncertainty    = "rising_uncertainty"
renderSandboxRejectReason SbrHighRepairLoopRisk   = "high_repair_loop_risk"
renderSandboxRejectReason SbrNegativeNetScore     = "negative_net_score"
