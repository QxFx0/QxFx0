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
    -- * Phase-5.5 transitional helpers
  , salienceFromField
  , salienceFromResonance
    -- * Phase-2.5 runtime-Conatus helpers
  , salienceFromConatusEnergy
  , salienceFromConatusResonance
  , salienceFromBlanket
  , conatusGateFires
    -- * Trace rendering (Phase 5.5e)
  , renderSalienceDriver
  ) where

import Data.Text (Text)

import QxFx0.Self.Adjunction (Formal, Holistic, rightAdjunct)
import QxFx0.Self.Conatus
  ( ConatusComponents (..)
  , ConatusEnergy (..)
  , computeConatusEnergy
  )
import QxFx0.Self.Types (BlanketViolation, SelfBlanket)
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Consolidation (..)
  , Counterfactual (..)
  , Field (..)
  , FieldConfidence (..)
  , Resonance (..)
  , emptyField
  , mkResonance
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
--
-- __Status (as of M2d):__ no runtime call site currently consumes
-- 'chooseBranch'. The 5.5a\/5.5b\/5.5c integrations use direct
-- @case salienceVerdict ... of@ post-processors because the
-- channels in question (intuition flash strength, 'RenderStyle',
-- narrative fragment text) do not naturally factor through the
-- 'Holistic'\/'Formal' adjoint pair — they are all
-- @Salience -> a -> a@ rewrites, not Field-parameterized
-- dispatches.
--
-- This API is retained as the typed realisation of ADR-0008's
-- adjunction-aware dispatch promise; wire-up is deferred to a
-- later phase that introduces a naturally Field-parameterized
-- dispatch point (candidate: Phase 5.5d Field broadening, where
-- a Field-dependent computation may emerge naturally). Until
-- then, property-test coverage in @Test.Suite.SelfSalience@
-- exercises the adjunction laws on the type level only.
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
-- Phase-5.5 transitional helpers
-- ---------------------------------------------------------------------------

-- | Compute a 'Salience' from a 'Field' alone, using a placeholder
-- positive 'ConatusEnergy' so the gate does not fire and
-- 'defaultSalienceWeights'.
--
-- This is the Phase-5.5 wiring helper. Call sites that already
-- have access to a runtime 'ConatusEnergy' should call
-- 'computeSalience' directly. Phase 2.5 (M2d) replaces every use
-- of this helper with a 'computeSalience' that consumes a
-- 'ConatusEnergy' computed from the runtime 'SelfBlanket'.
salienceFromField :: Field -> Salience
salienceFromField =
  computeSalience defaultSalienceWeights placeholderConatusEnergy
  where
    placeholderConatusEnergy = ConatusEnergy
      { ceScalar     = 1.0
      , ceComponents = ConatusComponents
          { ccMorphology = 0.0
          , ccIdentity   = 0.0
          , ccTurns      = 0.0
          , ccPenalty    = 0.0
          }
      }

-- | Build a 'Salience' from a single resonance signal, using
-- 'salienceFromField' on an otherwise-empty 'Field'.
--
-- This is the Phase-5.5 wiring primitive shared by all call
-- sites that still operate at the resonance-only level of Field
-- plumbing (currently: the intuition handler in
-- 'QxFx0.Runtime.Wiring.Handlers' and the consciousness-loop
-- dispatch in 'QxFx0.Core.ConsciousnessLoop'). Phase 5.5+ will
-- broaden these call sites to richer 'Field' values, at which
-- point this helper is replaced by direct 'salienceFromField'
-- (or 'computeSalience' once M2d threads runtime Conatus).
salienceFromResonance :: Double -> Salience
salienceFromResonance resonance =
  salienceFromField (emptyField { fieldResonance = mkResonance resonance })

-- ---------------------------------------------------------------------------
-- Phase-2.5 runtime-Conatus helpers (M2d)
-- ---------------------------------------------------------------------------

-- | Compute a 'Salience' from a precomputed 'ConatusEnergy' and a
-- 'Field'. Uses 'defaultSalienceWeights'.
--
-- This is the canonical entry point for the M2d wiring: every
-- runtime call site that has access to a real 'ConatusEnergy'
-- (either by computing it directly from a 'SelfBlanket' or by
-- receiving a precomputed one through 'PrepareStatic') goes
-- through this helper. The Conatus gate is now a real runtime
-- force; under structural risk ('ceScalar' below
-- 'conatusGateThreshold') the verdict 'salienceDriver' becomes
-- 'DrivenByConatusGate' and the 5.5b\/5.5c post-processors
-- automatically dispatch to 'StyleRecovery' and suppress the
-- narrative fragment, respectively.
salienceFromConatusEnergy :: ConatusEnergy -> Field -> Salience
salienceFromConatusEnergy = computeSalience defaultSalienceWeights

-- | Convenience: build a 'Salience' from a precomputed
-- 'ConatusEnergy' and a single resonance signal (otherwise-empty
-- 'Field'). Used by the runtime handlers that receive the Conatus
-- via the request constructor and have resonance in scope.
salienceFromConatusResonance :: ConatusEnergy -> Double -> Salience
salienceFromConatusResonance ce resonance =
  salienceFromConatusEnergy
    ce
    (emptyField { fieldResonance = mkResonance resonance })

-- | Compute a 'Salience' from a 'SelfBlanket', its current list
-- of 'BlanketViolation's, and a 'Field'.
--
-- The 'ConatusEnergy' is computed by 'computeConatusEnergy'
-- internally. Used by call sites that have direct access to the
-- runtime 'SystemState' (and hence to a 'SelfBlanket') without
-- needing to thread Conatus through a request shape.
salienceFromBlanket :: SelfBlanket -> [BlanketViolation] -> Field -> Salience
salienceFromBlanket b violations =
  salienceFromConatusEnergy (computeConatusEnergy b violations)

-- | Predicate: does the Conatus gate fire on this energy under
-- 'defaultSalienceWeights'?
--
-- This is the same boundary used by 'computeSalience' to decide
-- whether to short-circuit to 'DrivenByConatusGate'. Exposed so
-- that the recovery-decision call site in
-- 'QxFx0.Core.TurnPipeline.Route.Render' can priority-override
-- other recovery causes when the gate fires, keeping the
-- decision boundary single-sourced.
conatusGateFires :: ConatusEnergy -> Bool
conatusGateFires ce =
  ceScalar ce < conatusGateThreshold defaultSalienceWeights

-- ---------------------------------------------------------------------------
-- Trace rendering (Phase 5.5e)
-- ---------------------------------------------------------------------------

-- | Render a 'SalienceDriver' to a stable snake_case 'Text' tag
-- for inclusion in 'QxFx0.Types.TurnProjection.TurnReplayTrace'
-- and JSON-encoded turn projections.
--
-- The tags are closed-set and trace-stable: any change to a tag
-- is a breaking change to the replay-trace JSON schema.
renderSalienceDriver :: SalienceDriver -> Text
renderSalienceDriver DrivenByResonance       = "resonance"
renderSalienceDriver DrivenByAtmosphere      = "atmosphere"
renderSalienceDriver DrivenByConsolidation   = "consolidation"
renderSalienceDriver DrivenByCounterfactual  = "counterfactual"
renderSalienceDriver DrivenByFieldConfidence = "field_confidence"
renderSalienceDriver DrivenByConatusGate     = "conatus_gate"
renderSalienceDriver DrivenByDefault         = "default"

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
