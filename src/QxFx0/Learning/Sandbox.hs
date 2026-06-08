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
- derive locally authoritative conatus / predictive deltas from
  validated content plus current learning-need state
- 'SandboxAccept' if the authoritative net score stays non-regressive
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
  , AdmissionAuthorityDeltas(..)
  , defaultSandboxConfig
  , deriveAdmissionAuthorityDeltas
  , runSandboxGate
  , runSandboxGateWithConfig
  , renderSandboxRejectReason
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Learning.Need (LearningNeed(..), LearningNeedState(..), lnsHistory)
import QxFx0.Learning.Validator (KnowledgeFruitPayload(..), MorphologyPayload(..), minDefinitionWords)
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
    -- ^ Weighted composite of locally authoritative conatus/predictive deltas.
  , sbWindowSize        :: !Int
    -- ^ Simulated window turns (N).
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Locally authoritative learning deltas derived from validated content
-- and current runtime need state. Remote self-reported benefit values are
-- parsed for compatibility, but they do not decide admission.
data AdmissionAuthorityDeltas = AdmissionAuthorityDeltas
  { aadConatusDelta :: !Double
  , aadPredictiveDelta :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

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
-- 2. Bounded uncertainty increase: if the projected uncertainty rises too far
--    above the current baseline, reject with 'SbrRisingUncertainty'.
runSandboxGateWithConfig :: SandboxConfig -> SystemState -> KnowledgeFruitPayload -> SandboxResult
runSandboxGateWithConfig cfg ss payload =
  let needState = ssLearningNeedState ss
      authorityDeltas = deriveAdmissionAuthorityDeltas ss payload
      -- Current conatus trend from the last 3 history points (or 0 if insufficient)
      currentConatusTrend = conatusTrendFromHistory (lnsHistory needState)
      -- Current uncertainty proxy: amplitude of history oscillation
      currentUncertainty  = historyOscillationWithWindow (scWindowSize cfg) (lnsHistory needState)
      -- Projected values after applying locally authoritative deltas.
      projectedConatus  = currentConatusTrend + aadConatusDelta authorityDeltas
      projectedUncertainty = max 0 (currentUncertainty - aadPredictiveDelta authorityDeltas)
      -- Repair-loop frequency proxy: how often history levels exceed a soft threshold
      loopFreq            = repairLoopProxyWithWindow (scWindowSize cfg) (lnsHistory needState)
      -- Net score: weighted composite of locally authoritative deltas.
      netScore            = 0.5 * aadConatusDelta authorityDeltas + 0.5 * aadPredictiveDelta authorityDeltas

      metrics = SandboxMetrics
        { sbConatusTrend     = projectedConatus
        , sbUncertaintyTrend = projectedUncertainty
        , sbRepairLoopFreq   = loopFreq
        , sbNetScore         = netScore
        , sbWindowSize       = scWindowSize cfg
        }

      effectiveMinScore = scMinNetScore cfg

  -- Reject if projected conatus is at or below safety floor (non-regression criterion)
  in if projectedConatus <= scSafetyFloor cfg
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

deriveAdmissionAuthorityDeltas :: SystemState -> KnowledgeFruitPayload -> AdmissionAuthorityDeltas
deriveAdmissionAuthorityDeltas ss payload =
  AdmissionAuthorityDeltas
    { aadConatusDelta = clampRange (-0.35) 0.40 conatusDelta
    , aadPredictiveDelta = clampRange (-0.40) 0.50 predictiveDelta
    }
  where
    definitionScore = definitionQualityScore (kfpDefinition payload)
    morphologyScore = morphologyCoverageScore (kfpMorphology payload)
    needAlignmentScore = learningNeedAlignmentScore (lnsCurrentNeed (ssLearningNeedState ss))
    weakDefinitionPenalty = if definitionScore < 0.25 then 1.0 else 0.0

    conatusDelta =
      0.20 * definitionScore
      + 0.05 * morphologyScore
      + 0.05 * needAlignmentScore
      - 0.35 * weakDefinitionPenalty

    predictiveDelta =
      0.25 * definitionScore
      + 0.10 * morphologyScore
      + 0.10 * needAlignmentScore
      - 0.45 * weakDefinitionPenalty

definitionQualityScore :: Text -> Double
definitionQualityScore definitionText =
  clampRange 0.0 1.0 ((fromIntegral wordCount - fromIntegral minDefinitionWords) / 5.0)
  where
    wordCount = length (T.words (T.strip definitionText))

morphologyCoverageScore :: Maybe MorphologyPayload -> Double
morphologyCoverageScore Nothing = 0.0
morphologyCoverageScore (Just mp) =
  clampRange 0.0 1.0 (genderScore + declensionScore + caseScore)
  where
    genderScore = maybe 0.0 (const 0.20) (mpGender mp)
    declensionScore = maybe 0.0 (const 0.20) (mpDeclension mp)
    caseScore =
      case mpCases mp of
        Nothing -> 0.0
        Just caseMap -> min 0.60 (0.10 * fromIntegral (length caseMap))

learningNeedAlignmentScore :: LearningNeed -> Double
learningNeedAlignmentScore need =
  case need of
    NeedLexiconExtension -> 1.0
    NeedKeywordEnrichment -> 0.5
    NeedSalienceCalibration -> 0.25
    NeedNone -> 0.0

clampRange :: Double -> Double -> Double -> Double
clampRange lo hi x
  | isNaN x || isInfinite x = 0.0
  | otherwise = max lo (min hi x)

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
