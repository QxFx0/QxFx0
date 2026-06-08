{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Salience
Description : canonical — Phase-5 salience controller (pure).

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
  , SelfVerdict(..)
    -- * Tunable weights
  , SalienceWeights (..)
  , defaultSalienceWeights
    -- * Tunable behavioural thresholds
  , SalienceModulation (..)
  , defaultSalienceModulation
    -- * Controller
  , computeSalience
  , computeSelfVerdict
  , salienceVerdict
    -- * Adjunction-aware dispatch
  , chooseBranch
    -- * Phase-2.5 runtime-Conatus helpers
  , salienceFromConatusEnergy
  , salienceFromConatusResonance
  , salienceFromBlanket
  , conatusGateFires
    -- * Trace rendering (Phase 5.5e)
  , renderSalienceDriver
    -- * Family classification (Holistic / Formal)
  , isHolisticFamily
    -- * Phase-B bounded post-commitment adaptation
  , adaptSalienceWeights
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Self.ConfigLoad (loadConfigOrBuiltin)
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
import QxFx0.Types.Domain (CanonicalMoveFamily(..))

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
  | DrivenByContentSaliency  -- ^ WP-C: top-down content signal from spectral clustering
  | DrivenByDefault
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

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

-- | Aggregated pre-turn self decision surface.
--
-- Keeps the continuous 'Salience' payload together with its discrete
-- dispatch verdict so pipeline stages can read one canonical self-layer
-- verdict instead of recomputing and reclassifying locally.
data SelfVerdict = SelfVerdict
  { svSalience :: !Salience
  , svVerdict  :: !SalienceVerdict
  }
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
    --   keeping with "the system can\'t trust holistic signals;
    --   fall back to formal contracts").
  , weightContentSaliency :: !Double
    -- ^ WP-C: Multiplier on content saliency from spectral clustering.
    --   Direction: positive (more distinct topic clusters ⇒ more bias
    --   toward Holistic, as rich content structure favors generative mode).
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
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | The Phase-5 builtin weights.
--
-- These are pinned to make the property tests pass and to make
-- the operational mapping (ADR-0010 §6) plausible. They are
-- explicitly /not/ calibrated against empirical ground truth;
-- Phase 7 will replace them.
builtinSalienceWeights :: SalienceWeights
builtinSalienceWeights = SalienceWeights
  { weightResonance       = 1.0
  , weightAtmosphere      = 0.5
  , weightConsolidation   = 0.75
  , weightCounterfactual  = 0.75
  , weightFieldConfidence = 0.5
  , weightContentSaliency = 0.6  -- WP-C: moderate weight, pending Phase II calibration
  , conatusGateThreshold  = 0.0  -- @ceScalar@ can be negative under heavy violation; gate trips at 0
  , verdictThreshold      = 0.05 -- 5% dead band each side of 0.5
  , sigmoidTemperature    = 1.0
  }

-- | The Phase-5 default weights, loaded from
-- 'resources/config/salience_weights.json' if present, otherwise
-- falling back to 'builtinSalienceWeights'.
--
-- The NOINLINE pragma is required to prevent GHC from inlining
-- the 'unsafePerformIO' call and potentially evaluating it
-- multiple times.
defaultSalienceWeights :: SalienceWeights
defaultSalienceWeights =
  loadConfigOrBuiltin "resources/config/salience_weights.json" builtinSalienceWeights
{-# NOINLINE defaultSalienceWeights #-}

-- ---------------------------------------------------------------------------
-- Tunable behavioural thresholds
-- ---------------------------------------------------------------------------

-- | Tunable thresholds of the /behavioural/ layer that consumes a
-- 'Salience' verdict — cascade modulation
-- ('QxFx0.Core.TurnRouting.Cascade.applyPrincipledFamilyModulated' \/
-- 'applyGuardGatingModulated') and soft family escalation
-- ('QxFx0.Core.TurnRouting.applySalienceEscalation').
--
-- Distinct from 'SalienceWeights' (which calibrates the
-- /computation/ of 'Salience'); this record calibrates how
-- downstream code /uses/ it. Like 'defaultSalienceWeights', the
-- defaults here are pinned to make the property and integration
-- tests pass; Phase 7 (lifeness gates) is the calibration step.
data SalienceModulation = SalienceModulation
  { smModulationHolisticBiasFloor :: !Double
    -- ^ Above this 'salienceHolisticBias', the principled-cascade
    --   and guard-gating modulation paths /relax/ (intuition and
    --   narrative hints retain more influence; only
    --   agency-collapse remains hard-blocked). Default: @0.6@.
  , smEscalationConfidenceFloor   :: !Double
    -- ^ Above this 'salienceConfidence', soft family escalation
    --   nudges the cascade family to its nearest Holistic \/ Formal
    --   counterpart when bias and family side disagree.
    --   Default: @0.7@.
  }
  deriving stock (Eq, Show)

-- | The Phase-5.5 default modulation thresholds.
--
-- Pinned to match the values previously embedded as magic
-- constants in 'QxFx0.Core.TurnRouting.applySalienceEscalation'
-- and 'QxFx0.Core.TurnRouting.Cascade.applyPrincipledFamilyModulated'
-- \/ 'applyGuardGatingModulated' before centralisation.
defaultSalienceModulation :: SalienceModulation
defaultSalienceModulation = SalienceModulation
  { smModulationHolisticBiasFloor = 0.6
  , smEscalationConfidenceFloor   = 0.7
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
-- | WP-C: Compute the salience verdict with optional content saliency.
--
-- The @contentSaliency@ parameter is the top-down signal from spectral
-- clustering of the meaning graph (range @[0,1]@, computed by
-- 'QxFx0.Core.ContentCluster.computeContentSaliency'). When
-- 'QxFx0.Core.ContentCluster.contentSalienceActive' is @False@, pass @0.0@.
computeSalience :: SalienceWeights -> ConatusEnergy -> Field -> Double -> Salience
computeSalience w ce f contentSaliency
  | ceScalar ce < conatusGateThreshold w =
      Salience
        { salienceHolisticBias = 0.0
        , salienceConfidence   = 1.0
        , salienceDriver       = DrivenByConatusGate
        }
  | otherwise =
      let cs = contributions w f contentSaliency
          raw =
            contribResonance      cs
            + contribAtmosphere     cs
            - contribConsolidation  cs
            + contribCounterfactual cs
            - contribFieldConfidence cs
            + contribContentSaliency cs  -- WP-C: top-down content signal
          bias = sigmoid (raw / sigmoidTemperature w)
       in Salience
             { salienceHolisticBias = bias
             , salienceConfidence   = computeConfidence cs
             , salienceDriver       = dominantDriver cs
             }

-- | Compute the aggregated self-layer verdict for a single turn.
-- | WP-C: Compute the aggregated self-layer verdict with content saliency.
computeSelfVerdict :: SalienceWeights -> ConatusEnergy -> Field -> Double -> SelfVerdict
computeSelfVerdict w ce f contentSaliency =
  let salience = computeSalience w ce f contentSaliency
  in SelfVerdict
       { svSalience = salience
       , svVerdict = salienceVerdict w salience
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
-- __Status (as of Phase 5.5e):__ 'chooseBranch' is now consumed by
-- 'QxFx0.Core.TurnRender.Strategy.applySalienceToStyle' (the
-- render-style dispatch point). This is the first production
-- call site that threads a real 'Field' into the adjunction.
-- Other channels (intuition flash strength, narrative fragment)
-- still use direct @case salienceVerdict ... of@ rewrites
-- because they are @Salience -> a -> a@ post-processors, not
-- Field-parameterized dispatches.
--
-- Property-test coverage in @Test.Suite.SelfSalience@ exercises
-- the adjunction laws on the type level; the runtime call site
-- exercises them on the value level.
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

-- | Compute a 'Salience' from a 'ConatusEnergy' and a 'Field'.
-- Uses 'defaultSalienceWeights'.  The Conatus gate is evaluated
-- with the real runtime energy; there is no placeholder.
--
-- This is the Phase-5.5 wiring helper.  Call sites that already
-- have access to a runtime 'ConatusEnergy' (e.g. from
-- 'PrepareStatic' or 'TurnInput') should pass it here.
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
-- | WP-C: Compute a 'Salience' from a precomputed 'ConatusEnergy', a 'Field',
-- and optional content saliency. Uses 'defaultSalienceWeights'.
salienceFromConatusEnergy :: ConatusEnergy -> Field -> Double -> Salience
salienceFromConatusEnergy ce f contentSaliency =
  computeSalience defaultSalienceWeights ce f contentSaliency

-- | Convenience: build a 'Salience' from a precomputed
-- 'ConatusEnergy' and a single resonance signal (otherwise-empty
-- 'Field'). Used by the runtime handlers that receive the Conatus
-- via the request constructor and have resonance in scope.
salienceFromConatusResonance :: ConatusEnergy -> Double -> Salience
salienceFromConatusResonance ce resonance =
  salienceFromConatusEnergy
    ce
    (emptyField { fieldResonance = mkResonance resonance })
    0.0  -- WP-C: no content saliency

-- | Compute a 'Salience' from a 'SelfBlanket', its current list
-- of 'BlanketViolation's, and a 'Field'.
--
-- The 'ConatusEnergy' is computed by 'computeConatusEnergy'
-- internally. Used by call sites that have direct access to the
-- runtime 'SystemState' (and hence to a 'SelfBlanket') without
-- needing to thread Conatus through a request shape.
-- | WP-C: Compute a 'Salience' from a 'SelfBlanket', violations, a 'Field',
-- and optional content saliency.
salienceFromBlanket :: SelfBlanket -> [BlanketViolation] -> Field -> Double -> Salience
salienceFromBlanket b violations f contentSaliency =
  salienceFromConatusEnergy (computeConatusEnergy b violations) f contentSaliency

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
renderSalienceDriver DrivenByContentSaliency = "content_saliency"  -- WP-C
renderSalienceDriver DrivenByDefault         = "default"

-- ---------------------------------------------------------------------------
-- Phase-B bounded post-commitment adaptation
-- ---------------------------------------------------------------------------

-- | Bounded adaptation of salience weights.
--
-- * @signal@ in @[-1, 1]@: positive reinforces Holistic-bias weights,
--   negative reinforces Formal-bias weights.
-- * Learning rate capped at @0.02@ per turn.
-- * All adapted weights clamped to @[0.0, 2.0]@.
-- * Anti-drift: total deviation from 'defaultSalienceWeights'
--   per weight cannot exceed @1.0@.
--
-- Empirical signal generation is deferred to Phase 7; this
-- function provides the bounded mechanics so that future
-- calibration only needs to change the caller-supplied signal.
adaptSalienceWeights :: Double -> SalienceWeights -> SalienceWeights
adaptSalienceWeights rawSignal w =
  let lr        = 0.02
      signal    = max (-1.0) (min 1.0 rawSignal)
      delta     = signal * lr
      def       = defaultSalienceWeights
      clamped x = max 0.0 (min 2.0 x)
      -- Anti-drift only applies when we are actually adapting;
      -- signal=0 must be identity to respect the gating contract.
      bounded target x =
        let adapted = clamped (x + delta)
        in if abs delta < 1e-12
             then x
             else max (target - 1.0) (min (target + 1.0) adapted)
  in w
       { weightResonance       = bounded (weightResonance       def) (weightResonance       w)
       , weightAtmosphere      = bounded (weightAtmosphere      def) (weightAtmosphere      w)
       , weightConsolidation   = bounded (weightConsolidation   def) (weightConsolidation   w)
       , weightCounterfactual  = bounded (weightCounterfactual  def) (weightCounterfactual  w)
       , weightFieldConfidence = bounded (weightFieldConfidence def) (weightFieldConfidence w)
       , weightContentSaliency = bounded (weightContentSaliency def) (weightContentSaliency w)  -- WP-C
       }

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
  , contribContentSaliency :: !Double  -- ^ WP-C: top-down content signal
  }

contributions :: SalienceWeights -> Field -> Double -> Contributions
contributions w f contentSaliency = Contributions
  { contribResonance       = weightResonance       w * unResonance       (fieldResonance      f)
  , contribAtmosphere      = weightAtmosphere      w * atmosphereArousal (fieldAtmosphere     f)
  , contribConsolidation   = weightConsolidation   w * unConsolidation   (fieldConsolidation  f)
  , contribCounterfactual  = weightCounterfactual  w * unCounterfactual  (fieldCounterfactual f)
  , contribFieldConfidence = weightFieldConfidence w * unFieldConfidence (fieldConfidence     f)
  , contribContentSaliency = weightContentSaliency w * contentSaliency  -- WP-C
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
      , (DrivenByContentSaliency, abs (contribContentSaliency cs))  -- WP-C
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
  | otherwise       = max 0.0 (1.0 - other / (5.0 * dominant))  -- WP-C: now 6 contributions, so n-1 = 5
  where
    magnitudes =
      [ abs (contribResonance       cs)
      , abs (contribAtmosphere      cs)
      , abs (contribConsolidation   cs)
      , abs (contribCounterfactual  cs)
      , abs (contribFieldConfidence cs)
      , abs (contribContentSaliency cs)  -- WP-C
      ]
    dominant = maximum magnitudes
    other    = sum magnitudes - dominant

-- | Classify a 'CanonicalMoveFamily' as holistic (right-hemispheric).
-- This is the single source of truth for the Holistic / Formal
-- partition used by the salience controller and the feedback loop.
isHolisticFamily :: CanonicalMoveFamily -> Bool
isHolisticFamily CMReflect    = True
isHolisticFamily CMDefine     = True
isHolisticFamily CMHypothesis = True
isHolisticFamily CMDeepen     = True
isHolisticFamily CMPurpose    = True
isHolisticFamily _            = False
