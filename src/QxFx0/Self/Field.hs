{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Field
Description : Phase-4 right-hemispheric observation summary.

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
  , recordFieldOnto
  , summariseFrom
  , unFieldHistory
  ) where

-- ---------------------------------------------------------------------------
-- Component newtypes
-- ---------------------------------------------------------------------------

-- | Maximum cosine similarity between the current turn's semantic
-- embedding and any of the previous @k@ turn embeddings in the
-- conversational window. Range @[0, 1]@: 0 = topic shift,
-- 1 = exact echo. @k@ is a Phase-5 tunable.
newtype Resonance = Resonance { unResonance :: Double }
  deriving stock (Eq, Show)

-- | Two-dimensional affective summary on the valence\/arousal axis.
--
-- * 'atmosphereValence' in @[-1, 1]@: @-1@ negative … @1@ positive.
-- * 'atmosphereArousal' in @[0, 1]@: @0@ calm … @1@ urgent\/intense.
data Atmosphere = Atmosphere
  { atmosphereValence :: !Double
  , atmosphereArousal :: !Double
  } deriving stock (Eq, Show)

-- | Internal-coherence score in @[0, 1]@: @1@ = all signals agree,
-- @0@ = signals are mutually contradictory and any decision drawn
-- from this 'Field' is suspect.
newtype FieldConfidence = FieldConfidence { unFieldConfidence :: Double }
  deriving stock (Eq, Show)

-- | Narrative-integration scalar in @[0, 1]@: how much of the
-- recent conversation has been digested into the system's running
-- model. Genuinely temporal — its value at turn @n@ depends on
-- the trajectory through turns @1..n@, not just the current turn.
newtype Consolidation = Consolidation { unConsolidation :: Double }
  deriving stock (Eq, Show)

-- | Diversity of plausible alternative interpretations of the
-- current turn, normalised to @[0, 1]@. High = posterior was
-- spread; low = posterior was peaked.
newtype Counterfactual = Counterfactual { unCounterfactual :: Double }
  deriving stock (Eq, Show)

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
  } deriving stock (Eq, Show)

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

-- | Prepend a new 'Field' onto the history, dropping older entries
-- to keep the buffer at most 32 deep.
recordFieldOnto :: Field -> FieldHistory -> FieldHistory
recordFieldOnto f (FieldHistory xs) = FieldHistory (f : take 31 xs)

-- | Summarise a 'FieldHistory' to a single 'Field'. Phase-4 stub:
-- returns the most-recent snapshot, or 'emptyField' if the history
-- is empty. Phase 5 replaces this with a windowed summary.
summariseFrom :: FieldHistory -> Field
summariseFrom (FieldHistory []     ) = emptyField
summariseFrom (FieldHistory (f : _)) = f

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

clamp :: Ord a => a -> a -> a -> a
clamp lo hi = max lo . min hi

clampUnit :: Double -> Double
clampUnit = clamp 0.0 1.0
