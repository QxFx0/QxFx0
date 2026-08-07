{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical - typed self-prediction and self-divergence
measurement carriers for the deterministic self-model (A-slice).

Pure data only: no IO, no decisions. The prediction and measurement
morphisms live in @QxFx0.Self.SelfDivergence@; this module defines
their carriers so that the numeric regime is inspectable and
replay-safe across turns.

Design note (A1):
- Predictions are /continuous/ centers plus an /envelope/ derived
  from the Essence band prices (@emBandLowEdge@/@emBandHighEdge@/
  @emValenceLowEdge@/@emValenceHighEdge@).  Discrete band buckets
  (@FieldBand@/@ValenceBand@) are deliberately NOT used as the
  predicted expectation: quantised expectations would make the
  divergence measure flat on steady Fields and staircase on
  transitions, breaking monotonicity and clamp smoothness (A4
  property tests).
- The tolerance is applied inside @measureDivergence@: deviations
  inside the envelope contribute zero; only the excess distance is
  counted.  This is the "knowing one's own limits" reading of the
  A-slice: divergence is the distance of the actual state beyond the
  envelope the system expected for itself.
- 'SelfDivergenceTuning' defaults are the tunable regime.  Any change
  to these defaults bumps @currentMathVersion@ per the rule in
  @Types.RuntimeRegime@.
-}

module QxFx0.Types.Self.SelfDivergence
  ( SelfDivergenceTuning (..)
  , SelfPrediction (..)
  , SelfDivergenceE (..)
  , defaultSelfDivergenceTuning
  , emptySelfPrediction
  , emptySelfDivergenceE
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

-- | Tunables for the self-divergence contour (A3).
--
-- Invariant: @0 < sdtScaling <= 1@, @0 <= sdtThreshold <= 1@,
-- @sdtWindow >= 1@.
data SelfDivergenceTuning = SelfDivergenceTuning
  { sdtScaling :: !Double
    -- ^ Fraction of the current Conatus energy deducted per unit of
    --   out-of-envelope divergence: @penaltyShare = sdtScaling * total@.
    --   Absolute value is energy-scale dependent (~log-scale 14-15), so
    --   a fraction, not a flat constant (avoids the WP-F unit mismatch).
  , sdtThreshold :: !Double
    -- ^ 'sdeTotalDivergence' below this value contributes no penalty.
    --   Deltas measured inside the component envelopes are already zero;
    --   this adds an explicit whole-state gate: calm states pay nothing.
  , sdtWindow :: !Int
    -- ^ Sliding-window length for the window mean divergence.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

defaultSelfDivergenceTuning :: SelfDivergenceTuning
defaultSelfDivergenceTuning = SelfDivergenceTuning
  { sdtScaling   = 0.035
  , sdtThreshold = 0.35
  , sdtWindow    = 8
  }

-- | A deterministic textual prediction of the next turn's Field
-- state, computed from the previous observed 'Field' and the current
-- angst level. Continuous centers per component plus an envelope
-- half-width derived from the modulation band prices.
data SelfPrediction = SelfPrediction
  { spResonance      :: !Double
  , spValence        :: !Double
  , spArousal        :: !Double
  , spConfidence     :: !Double
  , spConsolidation  :: !Double
  , spCounterfactual :: !Double
  , spAngst          :: !Double
    -- ^ Expected next angst (deterministic decay trend).
  , spEnvelope       :: !Double
    -- ^ Half-width of the tolerance envelope (>= 0).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptySelfPrediction :: SelfPrediction
emptySelfPrediction = SelfPrediction
  { spResonance      = 0.5
  , spValence        = 0.0
  , spArousal        = 0.5
  , spConfidence     = 0.5
  , spConsolidation  = 0.5
  , spCounterfactual = 0.5
  , spAngst          = 0.0
  , spEnvelope       = 0.0
  }

-- | The six-axis divergence experience.
data SelfDivergenceE = SelfDivergenceE
  { sdeResonanceDelta   :: !Double
  , sdeAtmosphereDelta  :: !Double
  , sdeConfidenceDelta  :: !Double
  , sdeConsolidationDelta :: !Double
  , sdeCounterfactualDelta :: !Double
  , sdeAngstDelta       :: !Double
  , sdeTotalDivergence  :: !Double
    -- ^ Clamped unit sum of the axis deltas (L2, clamped to [0,1]).
  }  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptySelfDivergenceE :: SelfDivergenceE
emptySelfDivergenceE = SelfDivergenceE
  { sdeResonanceDelta   = 0.0
  , sdeAtmosphereDelta  = 0.0
  , sdeConfidenceDelta  = 0.0
  , sdeConsolidationDelta = 0.0
  , sdeCounterfactualDelta = 0.0
  , sdeAngstDelta       = 0.0
  , sdeTotalDivergence  = 0.0
  }