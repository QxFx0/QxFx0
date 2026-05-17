{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Salience
Description : Phase-5 salience controller (pure).

A typed, pure realisation of the salience controller pinned by
@docs\/adr\/0010-salience-controller.md@.

== What this module is

The salience controller is the runtime component that decides,
per turn, which of the two adjoint modes — 'Holistic' (right-
hemispheric, generative) or 'Formal' (left-hemispheric,
constraint-respecting) — should /lead/. Concretely it is a pure
morphism

@
'Field' \\(\\times\\) 'ConatusEnergy' -> 'Salience'
@

producing a structured verdict that carries:

* a continuous bias on @[0, 1]@ ('salienceHolisticBias'),
* a confidence score on @[0, 1]@ ('salienceConfidence'),
* a closed driver tag ('SalienceDriver') for trace.

The verdict is then dispatched through the Phase-3 adjunction
('chooseBranch') to select which of two caller-supplied morphisms
('Holistic a -> b' or 'a -> Formal b') is actually evaluated.

== What this module is /not/

This module is the algebraic /shape/ of salience-driven dispatch.
It does /not/ wire into the turn pipeline, does /not/ touch
@Core.Intuition@ \/ @Core.ConsciousnessLoop@ \/ @RouteEffects@ \/
@RenderStyle@ \/ @Recovery@. Those re-shapings are Phase-5.5 work
and live in their own future PRs.

== Decision rule (overview)

@
raw =
    weightResonance       * fieldResonance      f
  + weightAtmosphere      * atmosphereArousal (fieldAtmosphere f)
  - weightConsolidation   * fieldConsolidation  f      -- inverse
  + weightCounterfactual  * fieldCounterfactual f
  - weightFieldConfidence * fieldConfidence    f      -- inverse
@

Conatus gate: if @ceScalar < conatusGateThreshold@, the controller
short-circuits to a 'PreferFormal' verdict with confidence @1.0@
and driver 'DrivenByConatusGate'. Otherwise the raw score is
squashed to @[0, 1]@ by a logistic and the dominant driver is
the input whose absolute contribution to @raw@ was largest.

The exact functional forms (sigmoid temperature, dispersion-based
confidence) are implementation choices; the algebraic shape and
its laws (totality, range, monotonicity, Conatus-gate priority,
determinism) are the contract.

== Anti-correlation discipline

ADR-0007 mandates that "the non-leading mode listens but does not
emit." This module enforces that operationally through three
invariants:

* 'chooseBranch' returns a single morphism, not a pair. Whichever
  branch the controller selects is the one whose value reaches the
  caller; the other branch is well-typed and may be evaluated for
  diagnostics, but its value does not flow into the output.
* 'salienceVerdict' produces 'Tied' inside a small dead band
  around @0.5@, dispatched deterministically to the documented
  default ('PreferFormal' fallback) so that near-tied fields do
  not cause the system to flap between modes under noise.
* The Conatus gate has uncontested priority: when
  @ceScalar < conatusGateThreshold@, no Field-derived signal
  contributes to the verdict.

== Honest scope

The default weights ('defaultSalienceWeights') are pinned to make
the property tests pass and the operational mapping plausible.
We do not claim they are calibrated. Calibration is Phase-7
(lifeness gates) work.
-}
module QxFx0.Self.Salience
  ( -- * Verdict
    Salience (..)
  , SalienceDriver (..)
  , SalienceVerdict (..)
    -- * Tunable weights
  , SalienceWeights (..)
  , defaultSalienceWeights
    -- * Controller
  , computeSalience
  , salienceVerdict
    -- * Adjunction-aware dispatch
  , chooseBranch
  ) where

import QxFx0.Self.Adjunction (Formal, Holistic, rightAdjunct)
import QxFx0.Self.Conatus    (ConatusEnergy (..))
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Consolidation (..)
  , Counterfactual (..)
  , Field (..)
  , FieldConfidence (..)
  , Resonance (..)
  )

-- ---------------------------------------------------------------------------
-- Verdict types
-- ---------------------------------------------------------------------------

-- | Closed enumeration of which input dominated the controller's
-- decision. Used in trace records and diagnostics.
data SalienceDriver
  = DrivenByResonance
  | DrivenByAtmosphere
  | DrivenByConsolidation
  | DrivenByCounterfactual
  | DrivenByFieldConfidence
  | DrivenByConatusGate
  | DrivenByDefault
  deriving stock (Eq, Show)

-- | The controller's verdict for a single turn.
--
-- Invariants (verified by 'Test.Suite.SelfSalience'):
--
-- * @0 \\<= salienceHolisticBias \\<= 1@
-- * @0 \\<= salienceConfidence   \\<= 1@
-- * Identical @(SalienceWeights, ConatusEnergy, Field)@ inputs
--   produce identical 'Salience' values, including the discrete
--   'salienceDriver' tag.
data Salience = Salience
  { salienceHolisticBias :: !Double
    -- ^ In @[0, 1]@: @0@ = pure formal, @1@ = pure holistic.
  , salienceConfidence   :: !Double
    -- ^ In @[0, 1]@: @1@ = one driver decisively dominates,
    --   @0@ = contributions cancel.
  , salienceDriver       :: !SalienceDriver
    -- ^ Which input dominated the decision. Closed enum so it
    --   fits a trace record without further serialisation.
  }
  deriving stock (Eq, Show)

-- | The dispatched form of a 'Salience' value.
--
-- 'Tied' falls inside the dead band defined by
-- 'verdictThreshold'. Downstream code dispatches @Tied@ to the
-- documented default ('PreferFormal' fallback in 'chooseBranch').
data SalienceVerdict
  = PreferHolistic !Double  -- ^ Magnitude in @(0, 1]@.
  | PreferFormal   !Double  -- ^ Magnitude in @(0, 1]@.
  | Tied
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Tunable weights
-- ---------------------------------------------------------------------------

-- | Tunable coefficients of the decision rule. Phase 5 ships
-- 'defaultSalienceWeights'; Phase 7 (lifeness gates) is the
-- calibration step.
data SalienceWeights = SalienceWeights
  { weightResonance       :: !Double
    -- ^ Multiplier on 'fieldResonance'. Direction: positive
    --   (more resonance ⇒ more bias toward Holistic).
  , weightAtmosphere      :: !Double
    -- ^ Multiplier on @atmosphereArousal (fieldAtmosphere f)@.
    --   Direction: positive.
  , weightConsolidation   :: !Double
    -- ^ Multiplier on 'fieldConsolidation'. Direction: inverse
    --   (more consolidation ⇒ more bias toward Formal).
  , weightCounterfactual  :: !Double
    -- ^ Multiplier on 'fieldCounterfactual'. Direction: positive.
  , weightFieldConfidence :: !Double
    -- ^ Multiplier on 'fieldConfidence'. Direction: inverse
    --   (lower field confidence ⇒ more bias toward Formal, in
    --   keeping with \"the system can\'t trust holistic signals;
    --   fall back to formal contracts\").
  , conatusGateThreshold  :: !Double
    -- ^ If @ceScalar < this@, force 'PreferFormal' with full
    --   confidence and 'DrivenByConatusGate' driver.
  , verdictThreshold      :: !Double
    -- ^ Half-width of the dead band around @0.5@ within which
    --   the verdict is 'Tied'. In @[0, 0.5]@.
  , sigmoidTemperature    :: !Double
    -- ^ Slope parameter for the @sigmoid (raw \/ temperature)@
    --   squash. @1.0@ is the textbook default.
  }
  deriving stock (Eq, Show)

-- | The Phase-5 default weights.
--
-- These are pinned to make the property tests pass and to make
-- the operational mapping (ADR-0010 §6) plausible. They are
-- explicitly /not/ calibrated against empirical ground truth;
-- Phase 7 will replace them.
defaultSalienceWeights :: SalienceWeights
defaultSalienceWeights = SalienceWeights
  { weightResonance       = 1.0
  , weightAtmosphere      = 0.5
  , weightConsolidation   = 0.75
  , weightCounterfactual  = 0.75
  , weightFieldConfidence = 0.5
  , conatusGateThreshold  = 0.0  -- @ceScalar@ can be negative under heavy violation; gate trips at 0
  , verdictThreshold      = 0.05 -- 5% dead band each side of 0.5
  , sigmoidTemperature    = 1.0
  }

-- ---------------------------------------------------------------------------
-- Controller
-- ---------------------------------------------------------------------------

-- | Compute the salience verdict for a single turn.
--
-- Total, deterministic, pure. Identical inputs produce identical
-- 'Salience' values, including the discrete 'salienceDriver' tag.
--
-- The Conatus gate fires unconditionally when
-- @ceScalar c \\< conatusGateThreshold w@, returning a
-- 'PreferFormal'-shaped verdict with full confidence and
-- 'DrivenByConatusGate'. Otherwise the rule of ADR-0010 §3 is
-- applied.
computeSalience :: SalienceWeights -> ConatusEnergy -> Field -> Salience
computeSalience w ce f
  | ceScalar ce < conatusGateThreshold w =
      Salience
        { salienceHolisticBias = 0.0
        , salienceConfidence   = 1.0
        , salienceDriver       = DrivenByConatusGate
        }
  | otherwise =
      let cs = contributions w f
          raw =
            contribResonance      cs
            + contribAtmosphere     cs
            - contribConsolidation  cs
            + contribCounterfactual cs
            - contribFieldConfidence cs
          bias = sigmoid (raw / sigmoidTemperature w)
       in Salience
            { salienceHolisticBias = bias
            , salienceConfidence   = computeConfidence cs
            , salienceDriver       = dominantDriver cs
            }

-- | Dispatch a 'Salience' to a 'SalienceVerdict' using the
-- @verdictThreshold@ from the weights as the dead-band half-width.
salienceVerdict :: SalienceWeights -> Salience -> SalienceVerdict
salienceVerdict w s
  | bias > 0.5 + t = PreferHolistic bias
  | bias < 0.5 - t = PreferFormal   (1.0 - bias)
  | otherwise      = Tied
  where
    bias = salienceHolisticBias s
    t    = verdictThreshold w

-- ---------------------------------------------------------------------------
-- Adjunction-aware dispatch
-- ---------------------------------------------------------------------------

-- | Dispatch a precomputed 'SalienceVerdict' to one of two
-- caller-supplied branches through the Phase-3 adjunction.
--
-- Both branches are always provided by the caller (the adjunction
-- guarantees they are inter-translatable, see ADR-0008). The
-- controller picks which one to /use/; the other remains a
-- well-typed value the caller may evaluate for tracing.
--
-- 'Tied' is dispatched to the formal-first branch (the
-- contract-driven mode is the safe default). This is the
-- single-output-channel half of the anti-correlation discipline
-- (ADR-0010 §5).
chooseBranch
  :: SalienceVerdict
  -> (Holistic a -> b)   -- ^ Holistic-first branch.
  -> (a -> Formal b)     -- ^ Formal-first branch.
  -> (Holistic a -> b)
chooseBranch v holistic formal = case v of
  PreferHolistic _ -> holistic
  PreferFormal   _ -> rightAdjunct formal
  Tied             -> rightAdjunct formal

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

-- | Per-driver signed contributions to the raw score.
--
-- The sign of each contribution matches the rule direction
-- (ADR-0010 §3): positive contributions push toward Holistic,
-- negative toward Formal. Confidence and driver attribution use
-- the absolute values.
data Contributions = Contributions
  { contribResonance       :: !Double
  , contribAtmosphere      :: !Double
  , contribConsolidation   :: !Double
  , contribCounterfactual  :: !Double
  , contribFieldConfidence :: !Double
  }

contributions :: SalienceWeights -> Field -> Contributions
contributions w f = Contributions
  { contribResonance       = weightResonance       w * unResonance       (fieldResonance      f)
  , contribAtmosphere      = weightAtmosphere      w * atmosphereArousal (fieldAtmosphere     f)
  , contribConsolidation   = weightConsolidation   w * unConsolidation   (fieldConsolidation  f)
  , contribCounterfactual  = weightCounterfactual  w * unCounterfactual  (fieldCounterfactual f)
  , contribFieldConfidence = weightFieldConfidence w * unFieldConfidence (fieldConfidence     f)
  }

-- | Closed-form logistic squash.
sigmoid :: Double -> Double
sigmoid x = 1.0 / (1.0 + exp (negate x))

-- | The driver with the largest absolute contribution.
--
-- All-zero contributions return 'DrivenByDefault' (no signal
-- exceeded the threshold of any kind).
dominantDriver :: Contributions -> SalienceDriver
dominantDriver cs
  | totalMagnitude == 0.0 = DrivenByDefault
  | otherwise             = fst (foldr1 pickLarger cs')
  where
    cs' =
      [ (DrivenByResonance      , abs (contribResonance       cs))
      , (DrivenByAtmosphere     , abs (contribAtmosphere      cs))
      , (DrivenByConsolidation  , abs (contribConsolidation   cs))
      , (DrivenByCounterfactual , abs (contribCounterfactual  cs))
      , (DrivenByFieldConfidence, abs (contribFieldConfidence cs))
      ]
    totalMagnitude = sum (map snd cs')
    pickLarger a@(_, va) b@(_, vb) = if va >= vb then a else b

-- | Confidence as 1 minus normalised dispersion of the
-- contributions.
--
-- Concretely: let @dominant = max |c_i|@ and
-- @other = sum |c_i| − dominant@; with @n = 5@ contributions,
-- @confidence = max 0 (1 − other / ((n−1) × dominant))@. This
-- yields @1.0@ when one contribution dominates and the others
-- are zero, and @0.0@ when all five contributions are equal in
-- magnitude. All-zero contributions return @1.0@ (no signal to
-- disagree on).
computeConfidence :: Contributions -> Double
computeConfidence cs
  | dominant == 0.0 = 1.0
  | otherwise       = max 0.0 (1.0 - other / (4.0 * dominant))
  where
    magnitudes =
      [ abs (contribResonance       cs)
      , abs (contribAtmosphere      cs)
      , abs (contribConsolidation   cs)
      , abs (contribCounterfactual  cs)
      , abs (contribFieldConfidence cs)
      ]
    dominant = maximum magnitudes
    other    = sum magnitudes - dominant
