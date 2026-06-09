{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Field
Description : canonical — Phase-4 right-hemispheric observation summary.

A typed, pure realisation of the five-component @Field@ named in
@docs\/adr\/0007-dual-mode-conatus.md@ and pinned by
@docs\/adr\/0009-right-hemisphere-field.md@.

Phase 3 (commit @20d5611@, @QxFx0.Self.Adjunction@) shipped a
single-'Double' stub for 'Field'. This module replaces that stub
with the substantive five-component record:

* 'Resonance'       — peak similarity of the current turn to its
  recent context.
* 'Atmosphere'      — two-dimensional valence\/arousal affect.
* 'FieldConfidence' — internal-coherence score, derived from the
  rest.
* 'Consolidation'   — narrative-integration scalar over the
  recent window (genuinely temporal).
* 'Counterfactual'  — diversity of plausible alternative parses.

Each component is a 'newtype' around a refined numeric value,
with a documented range and a documented operational meaning.
The 'Field' record is strict in every field.

== What this module is /not/

This module is the algebraic /shape/ of the right-hemispheric
observation summary. It does /not/ source values from the runtime,
does /not/ touch the turn pipeline, and does /not/ know about
@Holistic@\/@Formal@ from @QxFx0.Self.Adjunction@ — that module
imports /this/ one, not the other way round.

Sourcing of values from runtime signals (semantic embedding,
consciousness-loop narrative tone, Bayesian posterior diversity,
etc.) is Phase-5 work and lives outside this module.

== Combination laws

Per ADR-0009 §2.2, 'Field' is /not/ a global 'Monoid'. The natural
combination law differs by component:

* 'combineResonance'       uses 'max'  — \"strongest echo found\".
* 'combineAtmosphere'      uses weighted average of valence and
  arousal — affect drifts; combining two snapshots is interpolation.
* 'combineFieldConfidence' uses 'min'  — combined confidence is at
  most each individual.
* 'combineConsolidation'   uses additive (clipped at @1.0@) —
  consolidation accumulates over a window.
* 'combineCounterfactual'  uses 'max'  — preserve highest
  counterfactual signal.

Field-level combination is exposed as 'combineField' parameterised
by an explicit 'CombineMode'.

== History stub

'FieldHistory' is a Phase-4 stub for the windowed trajectory that
Phase 5 will fill in. Phase 4 ships a trivial keep-the-last-32
buffer with a most-recent-wins summariser; this is enough to let
downstream modules import the type and the operations, and lets
Phase 5 grow the substantive sliding-window summary without
breaking imports.
-}
module QxFx0.Self.Field
  ( -- * The five components
    Resonance (..)
  , Atmosphere (..)
  , FieldConfidence (..)
  , Consolidation (..)
  , Counterfactual (..)
    -- * Smart constructors with range checking
  , mkResonance
  , mkAtmosphere
  , mkFieldConfidence
  , mkConsolidation
  , mkCounterfactual
    -- * The Field record
  , Field (..)
  , emptyField
  , deriveFieldConfidence
    -- * Phase-7 tunable heuristics (lifeness gates)
  , FieldHeuristics (..)
  , defaultFieldHeuristics
  , computeConsolidation
  , computeCounterfactual
  , computeAtmosphere
  , computeAtmosphereDecoupled
  , affectDecoupledActive
  , fieldAwareRenderingActive
  , updateMood
  , moodWindowTurns
    -- * Phase-B bounded post-commitment adaptation
  , adaptFieldHeuristics
    -- * Component combinators
  , combineResonance
  , combineAtmosphere
  , combineFieldConfidence
  , combineConsolidation
  , combineCounterfactual
    -- * Field-level combinators
  , CombineMode (..)
  , combineField
    -- * History stub (filled in Phase 5)
  , FieldHistory
  , emptyHistory
  , unFieldHistory
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Self.ConfigLoad (loadConfigOrBuiltin)

-- ---------------------------------------------------------------------------
-- Component newtypes
-- ---------------------------------------------------------------------------

-- | Maximum cosine similarity between the current turn's semantic
-- embedding and any of the previous @k@ turn embeddings in the
-- conversational window. Range @[0, 1]@: 0 = topic shift,
-- 1 = exact echo. @k@ is a Phase-5 tunable.
newtype Resonance = Resonance { unResonance :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Two-dimensional affective summary on the valence\/arousal axis.
--
-- * 'atmosphereValence' in @[-1, 1]@: @-1@ negative … @1@ positive.
-- * 'atmosphereArousal' in @[0, 1]@: @0@ calm … @1@ urgent\/intense.
data Atmosphere = Atmosphere
  { atmosphereValence :: !Double
  , atmosphereArousal :: !Double
  } deriving stock (Eq, Ord, Read, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Internal-coherence score in @[0, 1]@: @1@ = all signals agree,
-- @0@ = signals are mutually contradictory and any decision drawn
-- from this 'Field' is suspect.
newtype FieldConfidence = FieldConfidence { unFieldConfidence :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Narrative-integration scalar in @[0, 1]@: how much of the
-- recent conversation has been digested into the system's running
-- model. Genuinely temporal — its value at turn @n@ depends on
-- the trajectory through turns @1..n@, not just the current turn.
newtype Consolidation = Consolidation { unConsolidation :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Diversity of plausible alternative interpretations of the
-- current turn, normalised to @[0, 1]@. High = posterior was
-- spread; low = posterior was peaked.
newtype Counterfactual = Counterfactual { unCounterfactual :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- ---------------------------------------------------------------------------
-- Smart constructors
-- ---------------------------------------------------------------------------

-- | Construct a 'Resonance', clamping out-of-range inputs to
-- @[0, 1]@.
mkResonance :: Double -> Resonance
mkResonance = Resonance . clampUnit

-- | Construct an 'Atmosphere', clamping valence to @[-1, 1]@ and
-- arousal to @[0, 1]@.
mkAtmosphere :: Double -> Double -> Atmosphere
mkAtmosphere v a =
  Atmosphere
    { atmosphereValence = clamp (-1.0) 1.0 v
    , atmosphereArousal = clampUnit a
    }

-- | Construct a 'FieldConfidence', clamping to @[0, 1]@.
mkFieldConfidence :: Double -> FieldConfidence
mkFieldConfidence = FieldConfidence . clampUnit

-- | Construct a 'Consolidation', clamping to @[0, 1]@.
mkConsolidation :: Double -> Consolidation
mkConsolidation = Consolidation . clampUnit

-- | Construct a 'Counterfactual', clamping to @[0, 1]@.
mkCounterfactual :: Double -> Counterfactual
mkCounterfactual = Counterfactual . clampUnit

-- ---------------------------------------------------------------------------
-- The Field record
-- ---------------------------------------------------------------------------

-- | The right-hemispheric observation summary at one moment in
-- time. A snapshot, not a history; trajectories live in
-- 'FieldHistory'.
data Field = Field
  { fieldResonance      :: !Resonance
  , fieldAtmosphere     :: !Atmosphere
  , fieldConfidence     :: !FieldConfidence
  , fieldConsolidation  :: !Consolidation
  , fieldCounterfactual :: !Counterfactual
  } deriving stock (Eq, Ord, Read, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | The \"no observation yet\" zero. Per ADR-0009 §4.4,
-- 'fieldConfidence' is set to @1.0@: a system that has not yet
-- observed anything is uninformed, not unconfident.
emptyField :: Field
emptyField =
  Field
    { fieldResonance      = Resonance       0.0
    , fieldAtmosphere     = Atmosphere      0.0 0.0
    , fieldConfidence     = FieldConfidence 1.0
    , fieldConsolidation  = Consolidation   0.0
    , fieldCounterfactual = Counterfactual  0.0
    }

-- | Derive 'FieldConfidence' from the other four components.
--
-- The default formula reduces 'Atmosphere' to its arousal
-- magnitude (the @[0, 1]@-valued dimension) and computes
-- @1 - dispersion@, where dispersion is the variance of the four
-- scalarised components, normalised so a uniform field gives
-- @1.0@ and a maximally split field (two zeros, two ones) gives
-- @0.0@.
--
-- Phase 5 may override this default with a richer derivation; the
-- formula here is documented to be transparent and total, not
-- canonical.
deriveFieldConfidence :: Field -> FieldConfidence
deriveFieldConfidence f =
  FieldConfidence (1.0 - clampUnit normalised)
  where
    xs =
      [ unResonance       (fieldResonance      f)
      , atmosphereArousal (fieldAtmosphere     f)
      , unConsolidation   (fieldConsolidation  f)
      , unCounterfactual  (fieldCounterfactual f)
      ]
    n          = fromIntegral (length xs) :: Double
    mu         = sum xs / n
    var        = sum [(x - mu) * (x - mu) | x <- xs] / n
    -- Maximum variance for n=4 samples in [0,1] is 0.25
    -- (achieved when half are 0 and half are 1).
    normalised = var / 0.25

-- ---------------------------------------------------------------------------
-- Phase-7 tunable heuristics (lifeness gates / calibration)
-- ---------------------------------------------------------------------------

-- | Tunable parameters for the four Phase-5.5d heuristics that
-- populate a 'Field' from runtime signals.  Previously these were
-- magic constants embedded in 'buildPrepareEffectPlan'; Phase 7
-- extracts them into a single calibration record so that
-- property-based lifeness gates can vary the parameters and
-- verify boundary behaviour.
data FieldHeuristics = FieldHeuristics
  { fhNarrativeWindowSize     :: !Int
    -- ^ Window over 'ssRecentNarrativeSuccess' used for the
    --   consolidation narrative-rate computation. Default: 5.
  , fhDefaultNarrativeRate    :: !Double
    -- ^ Consolidation fallback when the window is empty.
    --   Default: 0.2.
  , fhTopicStabilityBoost     :: !Double
    -- ^ Floor applied to consolidation when the current topic
    --   matches the previous turn's topic. Default: 0.5.
  , fhEntropyEpsilon          :: !Double
    -- ^ Small additive guard against division-by-zero when
    --   normalising family weights for entropy. Default: 1e-9.
  , fhHolisticStreakBoostRate :: !Double
    -- ^ Increment added to counterfactual per unbroken holistic
    --   turn in the streak. Default: 0.05.
  , fhHolisticStreakBoostCap  :: !Double
    -- ^ Maximum total streak boost. Default: 0.2.
  , fhLegitimacyMidpoint      :: !Double
    -- ^ Legitimacy score treated as neutral for atmosphere
    --   valence modulation. Default: 0.5.
  , fhLegitimacyBonusScale    :: !Double
    -- ^ Multiplier on (legitimacy − midpoint) that is added
    --   to the ego-derived valence base. Default: 0.4.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Phase-7 builtin heuristic parameters.  These reproduce the
-- behaviour of the hardcoded constants that shipped in Phase 5.5d.
builtinFieldHeuristics :: FieldHeuristics
builtinFieldHeuristics = FieldHeuristics
  { fhNarrativeWindowSize     = 5
  , fhDefaultNarrativeRate    = 0.2
  , fhTopicStabilityBoost   = 0.5
  , fhEntropyEpsilon        = 1e-9
  , fhHolisticStreakBoostRate = 0.05
  , fhHolisticStreakBoostCap  = 0.2
  , fhLegitimacyMidpoint      = 0.5
  , fhLegitimacyBonusScale    = 0.4
  }

-- | Phase-7 default heuristic parameters, loaded from
-- 'resources/config/field_heuristics.json' if present, otherwise
-- falling back to 'builtinFieldHeuristics'.
--
-- The NOINLINE pragma is required to prevent GHC from inlining
-- the 'unsafePerformIO' call and potentially evaluating it
-- multiple times.
defaultFieldHeuristics :: FieldHeuristics
defaultFieldHeuristics =
  loadConfigOrBuiltin "resources/config/field_heuristics.json" builtinFieldHeuristics
{-# NOINLINE defaultFieldHeuristics #-}

-- | Compute 'Consolidation' from a window of recent narrative
-- success flags and a topic-stability indicator.
--
-- Lifeness gate: result is always in @[0, 1]@ because the raw
-- value is routed through 'mkConsolidation'.
computeConsolidation :: FieldHeuristics -> [Bool] -> Bool -> Consolidation
computeConsolidation fh recentSuccess sameTopic =
  let window = take (fhNarrativeWindowSize fh) recentSuccess
      rate   = if null window
                 then fhDefaultNarrativeRate fh
                 else fromIntegral (length (filter id window))
                      / fromIntegral (length window)
      raw    = if sameTopic then max (fhTopicStabilityBoost fh) rate else rate
  in mkConsolidation raw

-- | Compute 'Counterfactual' from a list of semantic-logic family
-- weights and the current holistic streak length.
--
-- Lifeness gate: result is always in @[0, 1]@ because the raw
-- value is routed through 'mkCounterfactual'.
computeCounterfactual :: FieldHeuristics -> [Double] -> Int -> Counterfactual
computeCounterfactual fh weights streak =
  let totalWeight  = sum weights
      epsilon      = fhEntropyEpsilon fh
      normWeights  = map (/ max epsilon totalWeight) weights
      entropy      = negate $ sum [ p * log (max epsilon p) | p <- normWeights ]
      maxEntropy   = log (fromIntegral (max 1 (length normWeights)))
      ambiguity    = if maxEntropy > 0 then entropy / maxEntropy else 0.0
      boost        = min (fromIntegral streak * fhHolisticStreakBoostRate fh)
                         (fhHolisticStreakBoostCap fh)
      raw          = min 1.0 (ambiguity + boost)
  in mkCounterfactual raw

-- | DEPRECATED (Phase 7): legacy coupled-affect model where arousal == egoTension.
-- Superseded by 'computeAtmosphereDecoupled', which is selected whenever
-- 'affectDecoupledActive' is True (the current default). This function is NOT
-- dead: it remains the @affectDecoupledActive = False@ branch in
-- 'Core.TurnPipeline.Effects' and provides the regression baseline that
-- @Test.Suite.AffectModel@ compares the decoupled model against. It will be
-- removed in P4 when the decoupled model is promoted unconditionally and the
-- comparison tests are retired. Do not add new callers.
--
-- Compute 'Atmosphere' from ego agency, ego tension, and the most recent
-- legitimacy score. Lifeness gate: the returned 'Atmosphere' is always well-formed because
-- 'mkAtmosphere' clamps both axes.
computeAtmosphere :: FieldHeuristics -> Double -> Double -> Double -> Atmosphere
computeAtmosphere fh egoAgency egoTension legitScore =
  let valenceBase = egoAgency - egoTension
      legitBonus  = (legitScore - fhLegitimacyMidpoint fh)
                    * fhLegitimacyBonusScale fh
      valence     = valenceBase + legitBonus
      arousal     = egoTension
  in mkAtmosphere valence arousal

-- | WP-E: default-on promotion flag selecting the decoupled affect model
-- ('computeAtmosphereDecoupled') over the legacy 'computeAtmosphere' where
-- arousal is identical to ego tension. Promoted to default-on (2026-06-04);
-- registered in the flag-off discipline (@scripts/check_architecture.sh@ rule [20]).
affectDecoupledActive :: Bool
affectDecoupledActive = True

-- | P6': default-off flag enabling Field-aware rendering modulation.
-- When @True@, the five Field components influence surface realisation:
--
-- * 'fieldConfidence' → epistemic hedges (\"maybe\", \"I think\")
-- * 'fieldAtmosphere' → lexical valence/arousal (soft modals, sentence length)
-- * 'fieldConsolidation' → discourse connectors (\"also\", \"furthermore\")
-- * 'fieldCounterfactual' → alternative markers (\"alternatively\", \"however\")
--
-- When @False@, rendering is Field-agnostic (current behaviour).
-- Registered in the flag-off discipline (@scripts/check_architecture.sh@ rule [20]).
-- Deliberate deferral: activation requires empirical tuning of Field-to-template
-- modulation parameters against an F-09/F-10 production corpus (Phase 7).
fieldAwareRenderingActive :: Bool
fieldAwareRenderingActive = False

-- | WP-E: arousal decoupled from valence. The legacy 'computeAtmosphere' sets
-- @arousal = egoTension@ and @valence = egoAgency - egoTension@, so the two
-- axes are not independent and calm-positive vs calm-negative cannot be
-- represented apart from agency. Here:
--
-- * arousal is driven by input /intensity/ (a salience/novelty signal in
--   @[0,1]@, e.g. resonance or counterfactual entropy), not by tension;
-- * valence is an appraisal (agency, legitimacy, and an outcome term),
--   independent of the arousal axis.
--
-- This lets the affect plane express, e.g., calm-positive (low arousal,
-- positive valence) distinctly from agitated-positive.
computeAtmosphereDecoupled
  :: FieldHeuristics
  -> Double  -- ^ ego agency
  -> Double  -- ^ ego tension
  -> Double  -- ^ most recent legitimacy score
  -> Double  -- ^ input intensity in [0,1] (arousal driver, e.g. resonance)
  -> Atmosphere
computeAtmosphereDecoupled fh egoAgency egoTension legitScore inputIntensity =
  let legitBonus = (legitScore - fhLegitimacyMidpoint fh) * fhLegitimacyBonusScale fh
      -- valence: appraisal from agency + legitimacy, lightly damped by tension
      valence    = egoAgency - 0.5 * egoTension + legitBonus
      -- arousal: input intensity blended with tension (tension still raises
      -- arousal, but no longer *defines* it)
      arousal    = 0.7 * clampUnit inputIntensity + 0.3 * clampUnit egoTension
  in mkAtmosphere valence arousal

-- | Number of turns the mood EMA integrates over (its effective window).
-- Used to derive the EMA smoothing factor; configurable per ADR-0046.
moodWindowTurns :: Int
moodWindowTurns = 12

-- | WP-E: update a slow mood baseline as an exponential moving average of
-- per-turn valence. Mood is the affective baseline that fast per-turn affect
-- rides on; a single extreme spike must not dominate it (the EMA factor is
-- @2 / (window + 1)@, so one sample contributes that fraction). Returns the
-- new mood in the valence range @[-1, 1]@.
updateMood :: Double -> Double -> Double
updateMood priorMood turnValence =
  let n     = fromIntegral moodWindowTurns :: Double
      alpha = 2.0 / (n + 1.0)
      mood' = (1.0 - alpha) * priorMood + alpha * clamp (-1.0) 1.0 turnValence
  in clamp (-1.0) 1.0 mood'

-- | Bounded adaptation of field-heuristic parameters.
--
-- Only the 'Double' fields are adapted; 'Int' fields (window size)
-- are left unchanged to avoid brittle integer drift.  Each adapted
-- value is clamped to @[0.0, 1.0]@ and further constrained to stay
-- within @±0.5@ of its default, providing an anti-drift guardrail.
--
-- Signal in @[-1, 1]@; learning rate capped at @0.02@ per turn.
-- Empirical signal generation is deferred to Phase 7; this function
-- wires the bounded mechanics.
adaptFieldHeuristics :: Double -> FieldHeuristics -> FieldHeuristics
adaptFieldHeuristics rawSignal fh =
  let lr        = 0.02
      signal    = max (-1.0) (min 1.0 rawSignal)
      delta     = signal * lr
      -- Anti-drift only applies when we are actually adapting;
      -- signal=0 must be identity to respect the gating contract.
      bounded target x =
        let adapted = max 0.0 (min 1.0 (x + delta))
        in if abs delta < 1e-12
             then x
             else max (target - 0.5) (min (target + 0.5) adapted)
      def       = defaultFieldHeuristics
  in fh
       { fhDefaultNarrativeRate    = bounded (fhDefaultNarrativeRate    def) (fhDefaultNarrativeRate    fh)
       , fhTopicStabilityBoost     = bounded (fhTopicStabilityBoost     def) (fhTopicStabilityBoost     fh)
       , fhHolisticStreakBoostRate = bounded (fhHolisticStreakBoostRate def) (fhHolisticStreakBoostRate fh)
       , fhHolisticStreakBoostCap  = bounded (fhHolisticStreakBoostCap  def) (fhHolisticStreakBoostCap  fh)
       , fhLegitimacyMidpoint      = bounded (fhLegitimacyMidpoint      def) (fhLegitimacyMidpoint      fh)
       , fhLegitimacyBonusScale    = bounded (fhLegitimacyBonusScale    def) (fhLegitimacyBonusScale    fh)
       }

-- ---------------------------------------------------------------------------
-- Per-component combinators
-- ---------------------------------------------------------------------------

-- | Combine two 'Resonance' values by 'max'.
-- Commutative, associative, idempotent.
combineResonance :: Resonance -> Resonance -> Resonance
combineResonance (Resonance a) (Resonance b) = Resonance (max a b)

-- | Combine two 'Atmosphere' values by weighted linear interpolation
-- on each axis. Weight is clamped to @[0, 1]@; a weight of @1@
-- returns the first argument unchanged, a weight of @0@ returns
-- the second.
combineAtmosphere :: Double -> Atmosphere -> Atmosphere -> Atmosphere
combineAtmosphere w a1 a2 =
  Atmosphere
    { atmosphereValence = w' * atmosphereValence a1 + (1 - w') * atmosphereValence a2
    , atmosphereArousal = w' * atmosphereArousal a1 + (1 - w') * atmosphereArousal a2
    }
  where
    w' = clampUnit w

-- | Combine two 'FieldConfidence' values by 'min'.
-- Commutative, associative, idempotent.
combineFieldConfidence :: FieldConfidence -> FieldConfidence -> FieldConfidence
combineFieldConfidence (FieldConfidence a) (FieldConfidence b) =
  FieldConfidence (min a b)

-- | Combine two 'Consolidation' values additively, clipped at
-- @1.0@. Commutative, associative; @Consolidation 0@ is the
-- identity.
combineConsolidation :: Consolidation -> Consolidation -> Consolidation
combineConsolidation (Consolidation a) (Consolidation b) =
  Consolidation (min 1.0 (a + b))

-- | Combine two 'Counterfactual' values by 'max'.
-- Commutative, associative, idempotent.
combineCounterfactual :: Counterfactual -> Counterfactual -> Counterfactual
combineCounterfactual (Counterfactual a) (Counterfactual b) =
  Counterfactual (max a b)

-- ---------------------------------------------------------------------------
-- Field-level combinators
-- ---------------------------------------------------------------------------

-- | Strategy for combining two 'Field' snapshots.
data CombineMode
  = CombineMaxima      -- ^ Per-component max where it makes sense;
                       --   atmosphere by 50\/50 average; confidence by 'min'.
  | CombineAverage     -- ^ Per-component arithmetic mean of every scalar.
  | CombineAccumulate  -- ^ Additive on consolidation, max on the other
                       --   non-confidence components, 'min' on confidence.
  deriving stock (Eq, Show)

-- | Combine two 'Field' snapshots according to a 'CombineMode'.
combineField :: CombineMode -> Field -> Field -> Field
combineField mode f1 f2 = case mode of
  CombineMaxima ->
    Field
      { fieldResonance      = combineResonance       (fieldResonance      f1) (fieldResonance      f2)
      , fieldAtmosphere     = combineAtmosphere 0.5  (fieldAtmosphere     f1) (fieldAtmosphere     f2)
      , fieldConfidence     = combineFieldConfidence (fieldConfidence     f1) (fieldConfidence     f2)
      , fieldConsolidation  =
          mkConsolidation
            (max
               (unConsolidation (fieldConsolidation f1))
               (unConsolidation (fieldConsolidation f2)))
      , fieldCounterfactual = combineCounterfactual  (fieldCounterfactual f1) (fieldCounterfactual f2)
      }
  CombineAverage ->
    Field
      { fieldResonance      = mkResonance       (avgUnit (fieldResonance      f1) (fieldResonance      f2) unResonance)
      , fieldAtmosphere     = combineAtmosphere 0.5  (fieldAtmosphere     f1) (fieldAtmosphere     f2)
      , fieldConfidence     = mkFieldConfidence (avgUnit (fieldConfidence     f1) (fieldConfidence     f2) unFieldConfidence)
      , fieldConsolidation  = mkConsolidation   (avgUnit (fieldConsolidation  f1) (fieldConsolidation  f2) unConsolidation)
      , fieldCounterfactual = mkCounterfactual  (avgUnit (fieldCounterfactual f1) (fieldCounterfactual f2) unCounterfactual)
      }
  CombineAccumulate ->
    Field
      { fieldResonance      = combineResonance       (fieldResonance      f1) (fieldResonance      f2)
      , fieldAtmosphere     = combineAtmosphere 0.5  (fieldAtmosphere     f1) (fieldAtmosphere     f2)
      , fieldConfidence     = combineFieldConfidence (fieldConfidence     f1) (fieldConfidence     f2)
      , fieldConsolidation  = combineConsolidation   (fieldConsolidation  f1) (fieldConsolidation  f2)
      , fieldCounterfactual = combineCounterfactual  (fieldCounterfactual f1) (fieldCounterfactual f2)
      }
  where
    avgUnit :: a -> a -> (a -> Double) -> Double
    avgUnit x y un = (un x + un y) / 2.0

-- ---------------------------------------------------------------------------
-- FieldHistory stub
-- ---------------------------------------------------------------------------

-- | A bounded buffer of recent 'Field' snapshots. Phase-4 stub;
-- Phase 5 commits the substantive shape (sliding window with
-- decay weights, etc.). The current capacity is fixed at 32 to
-- keep the type closed and the buffer cheap.
newtype FieldHistory = FieldHistory { unFieldHistory :: [Field] }
  deriving stock (Eq, Show)

-- | The empty history.
emptyHistory :: FieldHistory
emptyHistory = FieldHistory []

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

clamp :: Ord a => a -> a -> a -> a
clamp lo hi = max lo . min hi

clampUnit :: Double -> Double
clampUnit = clamp 0.0 1.0
