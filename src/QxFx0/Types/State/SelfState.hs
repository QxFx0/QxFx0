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
  ) where

import Control.DeepSeq (NFData)
import GHC.Generics (Generic)

import QxFx0.Types.Self.Salience (SalienceWeights)
import QxFx0.Types.Self.Field (FieldHeuristics)
import QxFx0.Types.Self.Conatus (ConatusWeights)
import QxFx0.Types.Self.FamilyTargets (FamilyTarget)
import QxFx0.Types.Self.Field (Field)
import QxFx0.Types.Self.SelfDivergence (SelfDivergenceE)
import QxFx0.Types.State.Perspective (PerspectiveRegistry)
import QxFx0.Types.Self.Essence (Essence, EssenceResetEvent)

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
  , selfConatusWeights :: !ConatusWeights
    -- ^ Conatus functional coefficients captured at bootstrap and persisted
    --   so replay never consults ambient files.
  , selfFamilyTargets :: ![FamilyTarget]
    -- ^ FMAR target configuration captured at bootstrap and persisted.
  , selfPerspectiveRegistry :: !PerspectiveRegistry
    -- ^ P4/P5: derived versioned perspective lineage projection.
    --   P5 canonical truth is 'ssGovernanceHistory'; this registry is
    --   kept as a rebuildable runtime view. Initialised to
    --   'emptyPerspectiveRegistry'.
, selfEssence :: !Essence
    -- ^ Phase 9: essence-selection trajectory accumulator.
    --   Carries the uncommitted (or committed) 'Essence' across
    --   turns. Initialised to 'emptyEssence'.
  , selfLastFieldObservation :: !(Maybe Field)
    -- ^ Phase 11 (self-divergence): the 'Field' observed on the
    --   previous turn.  Used by @predictSelf@ / @measureDivergence@.
    --   @Nothing@ when no previous turn has finished (bootstrap).
  , selfLastDivergence :: !(Maybe SelfDivergenceE)
    -- ^ A-slice: the 'SelfDivergenceE' measured on the previous turn.
    --   Consumed by the Prepare stage (one-turn delayed Conatus
    --   penalty).  @Nothing@ when the previous turn had no
    --   prediction anchor yet.
  , selfDivergenceWindow :: ![Double]
    -- ^ A-slice: bounded sliding window of recent total divergence
    --   samples (most recent last).  Bounded by 'sdtWindow'.
  , selfLastEssenceResetEvent :: !(Maybe EssenceResetEvent)
    -- ^ B-slice: the 'EssenceResetEvent' of the previous runtime
    --   soft-rupture (BD2 single branch).  @Just@ only on the turn a
    --   collapse ran (SelfReferentialCollapse or pentagon collapse);
    --   @Nothing@ otherwise.  Surfaces the soft rupture on the replay
    --   trace (never dropped).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

