{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.FamilyTargets
Description : FMAR Phase-3 — per-family target Fields and Field-distance selection.

Each 'CanonicalMoveFamily' is paired with a 'Field' signature describing
the system state in which executing that family is most authentic — its
equilibrium. The 14 targets here are EDITORIAL HYPOTHESES drawn from the
move-family semantics in @AGENTS.md@ and the Conatus-threshold semantics
in @docs\/THEORY.md@ §9–10. They are initial guesses, to be replaced by
empirical per-family averages once an F-09/F-10 production-trace corpus
exists.

'fieldDistance' measures how far the current 'AdaptivePosition' is from a
target 'Field' in the 8D space (five Field components + three spectral
components). The Field components dominate; spectral contributes a minor
nudge (total spectral weight is 0.3 of the Field weight sum).

This module is pure. It performs no IO and reads no runtime state.
-}
module QxFx0.Self.FamilyTargets
  ( FamilyTarget (..)
  , familyTargets
  , familyTargetFor
  , mkTargetField
  , fieldDistance
  , fmarDistanceThreshold
  , closestFamilyByField
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (foldl')
import GHC.Generics (Generic)

import QxFx0.Self.ConfigLoad (loadConfigOrBuiltin)
import QxFx0.Self.AdaptivePosition (AdaptivePosition (..), SpectralEncoding (..))
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Field (..)
  , FieldConfidence (..)
  , Consolidation (..)
  , Counterfactual (..)
  , Resonance (..)
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  )
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily (..))

-- | A move family together with the Field state characteristic of it and
-- the Conatus/counterfactual admissibility bounds used during selection.
data FamilyTarget = FamilyTarget
  { ftFamily            :: !CanonicalMoveFamily
  , ftTargetField       :: !Field
    -- ^ The equilibrium Field for this family.
  , ftMinConatus        :: !Double
    -- ^ Minimum @ceScalar@ for this family to be permitted.
  , ftMaxCounterfactual :: !Double
    -- ^ Maximum current counterfactual tolerated before this family is
    -- excluded as a fallback target.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Build a target Field from raw component values, routing each through
-- its smart constructor so the result is always in range.
mkTargetField :: Double -> Double -> Double -> Double -> Double -> Double -> Field
mkTargetField resonance valence arousal confidence consolidation counterfactual =
  Field
    { fieldResonance      = mkResonance resonance
    , fieldAtmosphere     = mkAtmosphere valence arousal
    , fieldConfidence     = mkFieldConfidence confidence
    , fieldConsolidation  = mkConsolidation consolidation
    , fieldCounterfactual = mkCounterfactual counterfactual
    }

-- | The 14 builtin per-family target Fields. Editorial hypotheses; see module note.
--
-- Columns: resonance, valence, arousal, confidence, consolidation, counterfactual.
builtinFamilyTargets :: [FamilyTarget]
builtinFamilyTargets =
  [ FamilyTarget CMGround
      (mkTargetField 0.70 0.20 0.30 0.85 0.70 0.15) 2.0 0.5
  , FamilyTarget CMDefine
      (mkTargetField 0.60 0.20 0.40 0.85 0.70 0.15) 3.0 0.4
  , FamilyTarget CMDistinguish
      (mkTargetField 0.50 0.00 0.50 0.70 0.60 0.40) 3.0 0.7
  , FamilyTarget CMReflect
      (mkTargetField 0.90 0.10 0.15 0.80 0.75 0.20) 2.5 0.5
  , FamilyTarget CMDescribe
      (mkTargetField 0.65 0.15 0.35 0.80 0.70 0.20) 2.5 0.5
  , FamilyTarget CMPurpose
      (mkTargetField 0.60 0.20 0.40 0.75 0.65 0.30) 3.0 0.5
  , FamilyTarget CMHypothesis
      (mkTargetField 0.50 0.00 0.50 0.60 0.50 0.50) 3.0 0.8
  , FamilyTarget CMRepair
      (mkTargetField 0.30 (-0.10) 0.30 0.30 0.20 0.30) 0.0 0.9
  , FamilyTarget CMContact
      (mkTargetField 0.70 0.30 0.20 0.90 0.80 0.10) 0.0 0.9
  , FamilyTarget CMAnchor
      (mkTargetField 0.80 0.40 0.10 0.90 0.90 0.05) 0.0 0.7
  , FamilyTarget CMClarify
      (mkTargetField 0.55 0.00 0.45 0.55 0.50 0.55) 2.0 0.9
  , FamilyTarget CMDeepen
      (mkTargetField 0.75 0.10 0.35 0.75 0.70 0.35) 3.0 0.6
  , FamilyTarget CMConfront
      (mkTargetField 0.40 (-0.20) 0.70 0.50 0.40 0.50) 3.0 0.6
  , FamilyTarget CMNextStep
      (mkTargetField 0.60 0.30 0.45 0.80 0.70 0.20) 2.5 0.5
  ]

-- | The 14 per-family target Fields, loaded from
-- 'resources/config/family_targets.json' if present, otherwise
-- falling back to 'builtinFamilyTargets'.
--
-- The NOINLINE pragma is required to prevent GHC from inlining
-- the 'unsafePerformIO' call and potentially evaluating it
-- multiple times.
familyTargets :: [FamilyTarget]
familyTargets =
  loadConfigOrBuiltin "resources/config/family_targets.json" builtinFamilyTargets
{-# NOINLINE familyTargets #-}

-- | Look up the 'FamilyTarget' for a family. Total over all 14 families,
-- since 'familyTargets' covers every 'CanonicalMoveFamily' constructor.
-- The empty case is unreachable (the list is total) but is handled without
-- a bare 'head' to satisfy the partial-function architecture rule: it
-- returns a neutral CMContact target.
familyTargetFor :: CanonicalMoveFamily -> FamilyTarget
familyTargetFor fam =
  case filter ((== fam) . ftFamily) familyTargets of
    (t : _) -> t
    []      -> neutralContactTarget

-- | Neutral fallback target (unreachable in practice). Mirrors the
-- CMContact hypothesis so any degenerate lookup lands on the safest,
-- always-admissible family.
neutralContactTarget :: FamilyTarget
neutralContactTarget =
  FamilyTarget CMContact
    (mkTargetField 0.70 0.30 0.20 0.90 0.80 0.10) 0.0 0.9

-- | Distance threshold in the 8D normalized space. If the current position
-- is farther than this from the recommended family's target, FMAR searches
-- for a closer family; otherwise it keeps the detector's recommendation.
--
-- The value @0.3@ is a deliberate /conservative, affective-only/ profile,
-- not a placeholder. The 14 target Fields are tightly packed: pairwise
-- nearest-neighbour distances are mostly 0.04–0.15, and the content cluster
-- (CMDefine\/CMDescribe\/CMGround\/CMNextStep\/CMPurpose) is 0.04–0.07
-- across — nearly coincident. At @0.3@, FMAR therefore overrides only when
-- the system's phenomenological 'Field' state is /affectively extreme/
-- relative to the recommendation: distress → CMRepair, tension → CMConfront,
-- settledness → CMAnchor. It does NOT try to distinguish content families
-- (CMDefine vs CMDescribe) — that is the keyword detector's job, not the
-- Field's.
--
-- Rationale: when FMAR overrides, it should be an /event, not noise/ — the
-- system observing that it cannot authentically execute the recommended
-- move from its current state. A threshold tight enough to fire on content
-- distinctions would make FMAR a redundant, noisy re-classifier. Revisit
-- only if a shadow-mode corpus (≥500 turns) shows the override rate is too
-- low to be useful; do not tighten pre-corpus.
fmarDistanceThreshold :: Double
fmarDistanceThreshold = 0.3

-- | Weighted Euclidean distance between the current position and a target
-- Field. The five Field components carry weights summing to 5.5
-- (confidence ×2.0, resonance ×1.5, valence/arousal/consolidation/
-- counterfactual ×1.0 across the remaining four — see below); the three
-- spectral components share a total weight of 0.3, making them a minor
-- contributor. The result is normalized by the total weight so it lands
-- in a comparable @[0, ~1]@ band.
fieldDistance :: AdaptivePosition -> Field -> Double
fieldDistance pos target =
  let cur = apField pos
      spec = apSpectral pos

      -- Field component deltas
      dResonance     = unResonance (fieldResonance cur) - unResonance (fieldResonance target)
      dValence       = atmosphereValence (fieldAtmosphere cur) - atmosphereValence (fieldAtmosphere target)
      dArousal       = atmosphereArousal (fieldAtmosphere cur) - atmosphereArousal (fieldAtmosphere target)
      dConfidence    = unFieldConfidence (fieldConfidence cur) - unFieldConfidence (fieldConfidence target)
      dConsolidation = unConsolidation (fieldConsolidation cur) - unConsolidation (fieldConsolidation target)
      dCounterfact   = unCounterfactual (fieldCounterfactual cur) - unCounterfactual (fieldCounterfactual target)

      -- Spectral deltas: target spectral position is the spectral encoding
      -- implied by the target Field's resonance band proxy. We have no
      -- band for the target, so spectral contributes its own magnitude as a
      -- soft regulariser toward the spectral origin (minor by design).
      sResonance = seResonance spec
      sPressure  = sePressure spec
      sDepth     = seDepth spec

      -- Weights
      wConfidence    = 2.0
      wResonance     = 1.5
      wValence       = 1.0
      wArousal       = 1.0
      wConsolidation = 1.0
      wCounterfact   = 1.0
      wSpectralEach  = 0.1   -- 3 × 0.1 = 0.3 total spectral weight

      fieldSq =
        wConfidence    * dConfidence    * dConfidence
          + wResonance     * dResonance     * dResonance
          + wValence       * dValence       * dValence
          + wArousal       * dArousal       * dArousal
          + wConsolidation * dConsolidation * dConsolidation
          + wCounterfact   * dCounterfact   * dCounterfact

      spectralSq =
        wSpectralEach * sResonance * sResonance
          + wSpectralEach * sPressure  * sPressure
          + wSpectralEach * sDepth     * sDepth

      totalWeight =
        wConfidence + wResonance + wValence + wArousal
          + wConsolidation + wCounterfact + 3 * wSpectralEach
   in sqrt ((fieldSq + spectralSq) / totalWeight)

-- | Select the family whose target Field is closest to the current
-- position, over the supplied target list. Total on every input: an empty
-- list yields 'CMContact' (the safest always-admissible family), so this
-- never calls a partial function.
closestFamilyByField :: AdaptivePosition -> [FamilyTarget] -> CanonicalMoveFamily
closestFamilyByField pos targets =
  case targets of
    []       -> CMContact
    (t0 : ts) ->
      let dist t = fieldDistance pos (ftTargetField t)
          pick best cand = if dist cand < dist best then cand else best
       in ftFamily (foldl' pick t0 ts)

-- | Rescue selection: choose the closest family from the Conatus-permitted
-- subset (those whose @ftMinConatus <= apConatusEnergy@). Falls back to
-- 'CMContact' when no family is permitted — @CMContact@'s @ftMinConatus@ is
-- @0.0@, so it is always admissible and is the safest restorative move.
fmarSelectFamilyRescue :: AdaptivePosition -> [FamilyTarget] -> CanonicalMoveFamily
fmarSelectFamilyRescue pos targets =
  let permitted = filter (\t -> ftMinConatus t <= apConatusEnergy pos) targets
   in case permitted of
        [] -> CMContact
        ts -> closestFamilyByField pos ts
