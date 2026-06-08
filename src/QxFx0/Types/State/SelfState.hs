{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-| Phase 4.1: Grouped Self-layer state (Phases 1-10 components).

This module groups the four Self-layer fields from SystemState into
a single SelfState record for better organization and maintainability.

== Migration Strategy

Phase 4.1.1 introduces this type in dual-write mode: both the new
'ssSelfState' field and the old individual fields coexist in
'SystemState'. JSON serialization supports both formats for backward
compatibility.

Future phases will migrate usage sites and eventually remove the
individual fields.
-}
module QxFx0.Types.State.SelfState
  ( SelfState(..)
  , emptySelfState
  , defaultSelfState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Self.Salience (SalienceWeights, defaultSalienceWeights)
import QxFx0.Self.Field (FieldHeuristics, defaultFieldHeuristics)
import QxFx0.Types.State.Perspective (PerspectiveRegistry, emptyPerspectiveRegistry)
import QxFx0.Self.Essence (Essence, emptyEssence)

-- | Grouped Self-layer state (Phase 1-10 components).
--
-- This record consolidates the four Self-layer fields that were
-- previously scattered in SystemState:
--
-- * 'selfSalienceWeights' — Phase B mutable salience weights
-- * 'selfFieldHeuristics' — Phase B mutable field heuristics
-- * 'selfPerspectiveRegistry' — P4/P5 versioned perspective lineage
-- * 'selfEssence' — Phase 9 essence-selection trajectory
data SelfState = SelfState
  { selfSalienceWeights :: !SalienceWeights
    -- ^ Phase B: mutable salience weights for post-commitment
    --   bounded self-tuning. Initialised to 'defaultSalienceWeights'.
  , selfFieldHeuristics :: !FieldHeuristics
    -- ^ Phase B: mutable field heuristics for post-commitment
    --   bounded self-tuning. Initialised to 'defaultFieldHeuristics'.
  , selfPerspectiveRegistry :: !PerspectiveRegistry
    -- ^ P4/P5: derived versioned perspective lineage projection.
    --   P5 canonical truth is 'ssGovernanceHistory'; this registry is
    --   kept as a rebuildable runtime view. Initialised to
    --   'emptyPerspectiveRegistry'.
  , selfEssence :: !Essence
    -- ^ Phase 9: essence-selection trajectory accumulator.
    --   Carries the uncommitted (or committed) 'Essence' across
    --   turns. Initialised to 'emptyEssence'.
  } deriving (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | Empty SelfState (for initialization).
--
-- All components are initialized to their respective empty/default values.
emptySelfState :: SelfState
emptySelfState = SelfState
  { selfSalienceWeights = defaultSalienceWeights
  , selfFieldHeuristics = defaultFieldHeuristics
  , selfPerspectiveRegistry = emptyPerspectiveRegistry
  , selfEssence = emptyEssence
  }

-- | Default SelfState (alias for emptySelfState).
--
-- Provided for consistency with other state modules.
defaultSelfState :: SelfState
defaultSelfState = emptySelfState

