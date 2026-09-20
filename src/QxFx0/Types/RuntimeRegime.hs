{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical — Machine-visible runtime regime version markers for M5 governance.

A 'RuntimeRegime' captures which mathematical constants, constitution
layers, and feature flags were active during a turn. Including it in
'TurnReplayTrace' (as @trcRegimeVersion@) makes math-change governance
machine-visible rather than purely doctrinal.

== Regime versioning rule

When any of the following changes, bump 'currentMathVersion':
- Conatus weight coefficients (@ConatusWeights@)
- Salience weight defaults (@defaultSalienceWeights@)
- Essence modulation parameters (@EssenceModulation@)
- Field heuristic sourcing rules (@FieldHeuristics@)
- CTS admission thresholds

Schema-version changes (persistence shape) bump @currentSystemStateSchemaVersion@
in @Types.State.System@, not @currentMathVersion@.

== Relationship to MATH_CHANGE_PROTOCOL.md

See @docs\/closure\/MATH_CHANGE_PROTOCOL.md@ for the full change-type →
evidence requirement table.
-}
module QxFx0.Types.RuntimeRegime
  ( RuntimeRegime (..)
  , defaultRuntimeRegime
  , currentMathVersion
  , currentConstitutionVersion
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import Control.DeepSeq (NFData)

-- | Captures the mathematical and feature-flag regime active during a turn.
-- Persisted in 'TurnReplayTrace' as @trcRegimeVersion@ so that replay can
-- reconstruct which thresholds and laws were in effect.
data RuntimeRegime = RuntimeRegime
  { rrMathVersion :: !Int
    -- ^ Bumped when any mathematical constant (weights, thresholds, update
    --   laws) changes. Governs which calibration corpus applies.
  , rrConstitutionVersion :: !Int
    -- ^ Bumped when the CTS admission chain changes (new seam added,
    --   admission threshold changed). Governs which CTS proof package applies.
  , rrFamilyDivergenceActive :: !Bool
    -- ^ True when @familyDivergenceEnabled = True@ (ADR-0019 promoted).
    --   Replay needs this to know whether holistic-formal modulation fired.
  , rrEssenceActive :: !Bool
    -- ^ True when essence commitment is enabled (ADR-0036 promoted).
  , rrRglMorphologyActive :: !Bool
    -- ^ True when RGL-backed morphology is enabled (paradigms.json loaded).
    --   Replay needs this to distinguish RGL vs JSON morphology path.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | Current math version. Bump when any calibration-relevant constant changes.
-- Initial value 1 = post-ADR-0012 correction (emConatusStructuralFloor 0.5 → 7.0).
-- Version 2 = A-slice self-divergence contour landed (predict → witness →
-- diff → allergen → Conatus): new Conatus component channel
-- @ccSelfDivergence@, new tunables @sdtScaling@/@sdtThreshold@/@sdtWindow@,
-- and the one-turn-delayed energy-fraction penalty enter the runtime math.
-- Version 3 = concept v3 two-protocol regime landed: frozen v1 user-side
-- R5 encoder (@QxFx0.User.R5@), the linear user viability contour
-- (@UserConatusWeights@/@ViabilityContour@ incl. EMA personalization),
-- the hard crisis gate + Protocol A/B resolution
-- (@QxFx0.Safety.CrisisGuard@), the ontological-axis classifier
-- (@QxFx0.Semantic.Ontological@), the ontological move graph
-- (@QxFx0.Semantic.MoveGraph@: effect matrix, connected-calm target
-- S*, deterministic search, move-conditioned transition model), and
-- receiver-conditioned decompression (@QxFx0.User.Decompress@).
-- All constants are hand-set v1 and frozen on release; replacing
-- them with fitted values is an offline, governed bump of this
-- version.
currentMathVersion :: Int
-- v4 (2026-09-20): move-layer tightening after the pre-registered
-- move probe measured F1 = 0.00 as a degradation predictor
-- ('moveDriftMargin' 0.10 -> 0.20; bare negative acts no longer fire
-- without affirm-gate passage or earned drift).
currentMathVersion = 4

-- | Current CTS constitution version.
-- Initial value 44 = CTS-44 (commitment promotion).
currentConstitutionVersion :: Int
currentConstitutionVersion = 46

-- | Default regime for new sessions, reflecting current code state.
defaultRuntimeRegime :: RuntimeRegime
defaultRuntimeRegime = RuntimeRegime
  { rrMathVersion          = currentMathVersion
  , rrConstitutionVersion  = currentConstitutionVersion
  , rrFamilyDivergenceActive = True   -- ADR-0019 promoted 2026-06-02
  , rrEssenceActive          = True   -- ADR-0036 promoted 2026-06-04
  , rrRglMorphologyActive    = True   -- RGL morphology promoted 2026-06-08 (L3c evidence: parity=0, sweep + live A/B)
  }
