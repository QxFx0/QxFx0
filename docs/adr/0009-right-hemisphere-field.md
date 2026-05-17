# ADR-0009: Right-Hemisphere Field Components

- **Status**: Proposed (Phase-4 design, not yet implemented)
- **Date**: 2026-05-17
- **Refines**:
  - [ADR-0007 — Dual-mode conatus-aware architecture](./0007-dual-mode-conatus.md)
  - [ADR-0008 — Left ⊣ Right adjunction as dual-mode backbone](./0008-left-right-adjunction.md)
- **Related**:
  - [`docs/THEORY.md`](../THEORY.md) §3.2 (the dual-mode thesis)
  - Phase 3 (`Self.Adjunction`), shipped in commit `20d5611`.

## 1. Context

ADR-0008 fixed the algebraic spine of the dual-mode runtime as the
adjunction `Holistic ⊣ Formal` parameterised by an opaque type
`Field`. Phase 3 deliberately shipped `Field` as a one-Double stub:

```haskell
newtype Field = Field { fieldIntensity :: Double }
```

with the explicit promise (ADR-0008 §4.1) that the substantive
content of the right-hemispheric observation summary would be
filled in by Phase 4. ADR-0007 named the five components that
right-hemispheric mode is to expose:

> Resonance, Atmosphere, FieldConfidence, Consolidation,
> Counterfactual.

Phase 4 makes these names precise. The deliverable is a typed,
pure expansion of `Field` together with per-component combinators
and a /trivial/ sourcing function. As with Phases 1–3, Phase 4
deliberately stops short of integration: re-shaping the call sites
in `Core.Intuition`, `Core.ConsciousnessLoop`, and `RouteEffects`
so they actually emit and consume `Field` values is Phase 5 work.

The point of stopping short is the same as for Phases 1–3: the
algebra and its tests must compile and review in isolation, before
they are wired into the hot path. We are paying for that
discipline in the structure of the build (each phase is one
focused PR) and recouping it in the absence of merge-storm risk.

## 2. Decision

We replace the Phase-3 stub with a record of five typed components:

```haskell
data Field = Field
  { fieldResonance       :: !Resonance
  , fieldAtmosphere      :: !Atmosphere
  , fieldConfidence      :: !FieldConfidence
  , fieldConsolidation   :: !Consolidation
  , fieldCounterfactual  :: !Counterfactual
  } deriving stock (Eq, Show)
```

Each component is a `newtype` around a refined numeric value, with
a documented range and a documented operational meaning. The
record is strict in every field (`StrictData` discipline,
preserved from Phase 3).

### 2.1 The five components

#### Resonance — *how strongly the current turn echoes its recent past*

```haskell
newtype Resonance = Resonance { unResonance :: Double }
  deriving stock (Eq, Show)
-- Invariant: 0.0 ≤ unResonance ≤ 1.0
```

Operationally: the maximum cosine similarity between the current
turn's semantic embedding and any of the last *k* turn embeddings
in the conversational window. *k* is a Phase-5 tunable; Phase 4
commits only to the type and the [0, 1] range.

A high `Resonance` means "this turn rhymes with recent context";
a low `Resonance` means "this turn is a topic shift." This is
exactly the kind of signal the right hemisphere is theorised to
attend to (large-scale pattern, not focal detail).

#### Atmosphere — *the conversational weather*

```haskell
data Atmosphere = Atmosphere
  { atmosphereValence :: !Double  -- in [-1, 1]: −1 negative … 1 positive
  , atmosphereArousal :: !Double  -- in [0, 1]: 0 calm … 1 urgent/intense
  } deriving stock (Eq, Show)
```

A two-dimensional affective summary, mirroring the
valence–arousal axis used in psychological affect circumplex
literature. `Atmosphere` is the only component that is /not/ a
scalar; that is intentional — affect does not collapse cleanly to
one dimension, and forcing it to would propagate noise into
everything that consumes it.

#### FieldConfidence — *how much we trust the rest of the field*

```haskell
newtype FieldConfidence = FieldConfidence { unFieldConfidence :: Double }
  deriving stock (Eq, Show)
-- Invariant: 0.0 ≤ unFieldConfidence ≤ 1.0
```

A scalar measure of internal coherence: how well the four other
components agree with each other. `FieldConfidence = 1.0` means
"all signals point the same way"; `0.0` means "signals are
mutually contradictory and any decision drawn from this Field is
suspect."

`FieldConfidence` is a *derived* component — Phase 4 will provide
a default deriver `deriveFieldConfidence :: Field -> FieldConfidence`,
and the field constructor will fix `fieldConfidence` to the
result. The component is held as a stored value rather than
recomputed at each access for two reasons: (i) callers should not
need to know how to derive it; (ii) consumers may legitimately
override it (e.g. when an external diagnostic flags a channel
unreliable).

#### Consolidation — *how settled the running narrative is*

```haskell
newtype Consolidation = Consolidation { unConsolidation :: Double }
  deriving stock (Eq, Show)
-- Invariant: 0.0 ≤ unConsolidation ≤ 1.0
```

An integrated measure of how much of the recent conversation has
been *digested* into the system's running model. A turn's
Consolidation is high when the claims it introduces have been
echoed, refined, or built upon; low when the claims are still
freshly introduced and not yet absorbed.

This is the only component that is genuinely temporal —
its value at turn *n* depends on the trajectory through turns
1..*n*, not just the current turn. Phase 4's implementation
provides a stub that uses only intra-turn signals; Phase 5 will
wire it to the actual claim-graph evolution over the window.

#### Counterfactual — *how plausible the alternatives were*

```haskell
newtype Counterfactual = Counterfactual { unCounterfactual :: Double }
  deriving stock (Eq, Show)
-- Invariant: 0.0 ≤ unCounterfactual ≤ 1.0
```

The diversity of plausible alternative interpretations of the
current turn, normalised to [0, 1]. A high Counterfactual means
"this turn could plausibly have been many things"; a low value
means "the interpretation was forced."

Operationally, this is sourced from the spread of posterior mass
across competing parses / claim-graphs in `Core.Bayesian`. A
flat-ish posterior (many competing interpretations near each
other in posterior mass) yields high Counterfactual; a peaked
posterior yields low.

This component matters because it is the difference between
*genuine intuition* (acknowledging that the chosen interpretation
was not forced) and *deterministic compute* (taking the highest-
posterior parse without acknowledging alternatives). The right
hemisphere, in McGilchrist's reading, is precisely the side that
holds open the alternatives; the left hemisphere is the one that
collapses them. Counterfactual is the field-level summary of that
holding-open.

### 2.2 No global Monoid; per-component merge laws

A natural reflex would be to make `Field` a `Monoid` so two
observations could be combined as `f1 <> f2`. We are explicitly
*not* doing that, because the natural combination law differs by
component:

| Component        | Natural combine             | Why                                      |
|------------------|-----------------------------|------------------------------------------|
| Resonance        | `max`                       | Resonance is "the strongest echo found." |
| Atmosphere       | weighted average            | Affect drifts; combining two snapshots is interpolation. |
| FieldConfidence  | `min`                       | Combined confidence is at most each individual. |
| Consolidation    | additive (clipped at 1)     | Consolidation accumulates over a window. |
| Counterfactual   | `max`                       | Counterfactual is "the largest spread observed." |

Forcing these into a single `<>` would either pick a wrong law
for some component, or would require a partial/discriminating
`<>` whose laws would be context-dependent — defeating the
purpose of having a `Monoid` instance at all.

Instead, Phase 4 ships *named* combine functions, one per
component, that are total and explicitly documented:

```haskell
combineResonance       :: Resonance       -> Resonance       -> Resonance
combineAtmosphere      :: Double {- weight -} -> Atmosphere -> Atmosphere -> Atmosphere
combineFieldConfidence :: FieldConfidence -> FieldConfidence -> FieldConfidence
combineConsolidation   :: Consolidation   -> Consolidation   -> Consolidation
combineCounterfactual  :: Counterfactual  -> Counterfactual  -> Counterfactual
```

and a single `combineField` parameterised by an explicit
combination strategy:

```haskell
data CombineMode
  = CombineMaxima       -- pointwise: max wherever it makes sense
  | CombineAverage      -- pointwise: average wherever it makes sense
  | CombineAccumulate   -- additive on Consolidation, max on the rest

combineField :: CombineMode -> Field -> Field -> Field
```

If a future caller needs a combination law not in this list, it
is a one-line addition; we are not committing to a closed
taxonomy.

### 2.3 Field is a snapshot, not a history

`Field` represents the right-hemispheric observation summary *at
one moment in time*. It does **not** carry a window of past
observations; it does **not** know about timestamps or turn
indices. Histories — which Phase 5 will need for the actual
Consolidation derivation — live in a separate type, sketched but
not implemented in Phase 4:

```haskell
-- Phase-4 stub; lives in QxFx0.Self.Field (this ADR's module).
-- Phase 5 fills in the consumer side.
data FieldHistory  -- abstract; the Phase-5 PR commits the shape
emptyHistory    :: FieldHistory
recordFieldOnto :: Field -> FieldHistory -> FieldHistory
summariseFrom   :: FieldHistory -> Field
```

Keeping `Field` snapshot-shaped lets it stay small (six `Double`s
plus a record dictionary; cheap to copy and compare) and lets
`Holistic`/`Formal` from Phase 3 remain pointwise-pure.

## 3. Type-level realisation

The Phase-4 module replaces the Phase-3 `Field` stub /in place/:

```haskell
-- src/QxFx0/Self/Field.hs (new)
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
  ) where
```

`QxFx0.Self.Adjunction` is then **re-pointed** from its own stub
`Field` to this module's `Field`:

```haskell
-- src/QxFx0/Self/Adjunction.hs  (Phase-4 modification)
import QxFx0.Self.Field (Field)
-- (the local newtype Field is removed from Adjunction.hs)
```

`QxFx0.Self.Adjunction` continues to re-export `Field` for the
benefit of existing call sites. The substantive change is
internal: the type Adjunction is parameterised over is now richer.

The unit and counit equations from Phase 3 do **not** change;
they were stated polymorphically in the value type and merely
quote `Field` — they continue to compile against the new record
without modification. The Phase-3 property tests
(`Test.Suite.SelfAdjunction`) continue to pass, because they
exercise the adjunction's *form* using `formalFromSeeds`-style
generators that do not depend on Field's internal shape; the test
of `Field` arbitrariness changes from `arbitraryField = Field
<$> choose ...` to a proper composite generator, but the
properties themselves are untouched.

## 4. Open design questions

Resolved in the Phase-4 implementation PR; flagged here so the
reviewer can challenge the implementer rather than re-litigate
the design.

### 4.1 Smart constructors vs raw newtype constructors

We are exporting both the bare constructors (`Resonance`,
`Atmosphere`, …) /and/ smart constructors (`mkResonance`, …) that
clamp out-of-range inputs. Bare constructors are needed for
deserialisation and tests; smart constructors are the canonical
production path. We will document that any code path that has not
already validated its inputs **must** use the smart constructor.

### 4.2 Where does `deriveFieldConfidence` live, and what does it compute?

`deriveFieldConfidence :: Field -> FieldConfidence` reduces the
other four components to a single coherence score. Phase 4
commits to a simple, transparent default:

```haskell
deriveFieldConfidence f = FieldConfidence (1.0 - dispersion)
  where
    -- variance over the four scalarisable components,
    -- normalised so a flat field gives 1.0 and a maximally
    -- mixed field gives 0.0.
    ...
```

The exact formula is bikeshedding-eligible; what matters is that
the derivation is monotone (more agreement → higher confidence)
and total. The Phase-5 PR may override the default with a richer
derivation; we are not freezing the formula in this ADR.

### 4.3 Is `Atmosphere` constructed from a fixed signal, or pluggable?

For the Phase-4 implementation we ship a *stub* sourcing function
that derives `Atmosphere` from already-existing signals
(`Core.ConsciousnessLoop` narrative tone). A real, pluggable
`Atmosphere` source — one that consults sentiment lexica, prosody
markers, and the running interlocutor model — is Phase 5 work.

### 4.4 Default field — is `emptyField` a meaningful zero?

`emptyField` represents "no holistic observation yet." Its values
are: `Resonance 0`, `Atmosphere (Atmosphere 0 0)`,
`FieldConfidence 1` (we trust the absence of contradiction by
default), `Consolidation 0`, `Counterfactual 0`. The
`FieldConfidence 1` choice is the only non-obvious one: we want
"no observation" to *not* drag confidence down, because a system
that has not yet observed anything is not in a low-confidence
state — it is in an /uninformed/ state. Phase 5 may want to
distinguish these; for Phase 4 we elide.

## 5. Operational mapping (preview)

This section is descriptive of what Phase 5 will do; nothing in
this ADR's implementation reads from or writes to these sites.

| Component       | Source (Phase 5 wires it)                | Sink (Phase 5 wires it)                  |
|-----------------|------------------------------------------|------------------------------------------|
| Resonance       | `Semantic.Embedding` cosine over window  | Salience controller; render rhyme cues   |
| Atmosphere      | `Core.ConsciousnessLoop` + lexicon score | Render tone; `RouteEffects` style        |
| FieldConfidence | derived from the rest                    | Salience controller's override threshold |
| Consolidation   | `MeaningGraph` stability + claim echoes  | Render depth; recovery aggressiveness    |
| Counterfactual  | `Core.Bayesian` posterior diversity      | Salience controller; intuition gate      |

The salience controller (Phase 5) reads the whole `Field` and
decides which mode to favour for a given turn; that decision is
expressed as a choice between a `Holistic`-shaped path and a
`Formal`-shaped path through the adjunction shipped in Phase 3.

## 6. Phase-4 implementation plan

Order of operations for the Phase-4 PR:

1. **`src/QxFx0/Self/Field.hs`** (new) — five component newtypes
   with smart constructors; the `Field` record; `emptyField`;
   `deriveFieldConfidence`; per-component combinators;
   `combineField` over `CombineMode`; `FieldHistory` stub.
2. **`src/QxFx0/Self/Adjunction.hs`** (modified) — remove the
   stub `Field`, import the substantive one from
   `QxFx0.Self.Field`, re-export `Field` so external callers'
   imports do not move. The `Adjunction Holistic Formal`
   instance is unchanged in source.
3. **`test/Test/Suite/SelfField.hs`** (new) — well-formedness
   properties:
   - all smart constructors clamp to range,
   - per-component combinators respect their stated laws
     (`combineResonance` is commutative & associative since `max`
     is; `combineConsolidation` is commutative, associative, and
     bounded by 1.0; etc.),
   - `emptyField` is the identity of `combineField CombineMaxima`,
   - `deriveFieldConfidence` is monotone in component agreement,
   - `Field` round-trips through `Holistic`/`Formal` (smoke check
     that the Phase-3 adjunction continues to compose).
4. **`test/Test/Suite/SelfAdjunction.hs`** (modified) — replace
   the trivial `arbitraryField = Field <$> choose ...` with a
   composite generator drawing each component from its smart
   constructor, then re-confirm that all Phase-3 properties pass
   against the richer `Field`.
5. **Cabal + TestMain wiring**, exactly as we did for the three
   prior `Self.*` modules.
6. **Architecture-check**, no new boundary rules expected.

Phase 4 deliberately does **not** touch `Core.Intuition`,
`Core.ConsciousnessLoop`, `RouteEffects`, `Core.Bayesian`, or any
runtime call site. It does not introduce a `Field`-aware effect
in the effect system. Those are Phase-5 changes and will live in
their own PRs so each remains reviewable and recompilable in
isolation.

## 7. Consequences

### 7.1 Positive

- The right-hemispheric observation summary stops being a
  single-Double placeholder and acquires its true five-component
  shape, with documented ranges and documented operational
  meaning. Phase 5 has a stable target to wire against.
- Per-component combinators replace a phantom global `Monoid`;
  consumers ask for the law they need by name, and the laws
  themselves become test targets rather than typeclass folklore.
- The temporal split (`Field` is a snapshot;
  `FieldHistory` is the trajectory) gives Phase 5 a clean place
  to put windowed reasoning without polluting `Holistic` /
  `Formal`.
- The Phase-3 adjunction continues to hold without modification:
  the unit, counit, hom-set isomorphism, and triangle identities
  are all natural in `Field` and quote it abstractly. We get
  Phase-4 expressivity for free at the algebraic layer.

### 7.2 Negative

- The `Self.*` subtree grows by one substantial module
  (`QxFx0.Self.Field`). The Haddock burden grows correspondingly.
- `deriveFieldConfidence`'s default formula is necessarily a
  judgement call; we are committing to it for now and may revise
  it in Phase 5 once we see how downstream consumers actually use
  it.
- `Atmosphere` is the only non-scalar component, which marginally
  complicates per-component combinator code. We are accepting
  that cost rather than collapse affect to one dimension.

### 7.3 Neutral

- We are not adding any new external dependencies.
- We are not introducing any new effect type, monad, or
  type-class.
- The bare component constructors stay public (for tests and
  deserialisation); we document the smart-constructor discipline
  rather than enforce it through abstract types. This is
  consistent with how `Self.Conatus` already exposes
  `ConatusEnergy (..)` alongside `computeConatusEnergyWith`.

## 8. Alternatives considered

### 8.1 Make `Field` a `Monoid`

Rejected (§2.2). The natural combination laws differ by component;
forcing one global law would be wrong for at least three of the
five components.

### 8.2 Collapse `Atmosphere` to a single scalar

Rejected. Affect is well-known to be at least two-dimensional in
psychological literature (valence and arousal are independent and
both diagnostic). Forcing a scalar would propagate ambiguity
into every consumer.

### 8.3 Embed `FieldHistory` inside `Field`

Rejected (§2.3). It would force every `Holistic a` to carry a
trajectory, ballooning the size of the most-allocated value in
the dual-mode path. Snapshot + separate history is strictly more
compositional.

### 8.4 Defer `Counterfactual` to Phase 5

Tempting, because the Phase-4 source for Counterfactual is
necessarily a stub (Phase 5 wires it to `Core.Bayesian`). We are
keeping it in Phase 4 anyway, because the type itself is what
Phase 5 will write *against*; better to have the type committed
now than to retrofit it after Phase-5 code already shipped.

### 8.5 Stronger types — newtypes around refined types

Tempting, e.g. `Resonance :: UnitInterval`. We are not doing it
because no `UnitInterval` type exists in our dependency tree and
adding `refined` (or rolling our own) is more weight than the
property gives us. The smart constructors plus property tests
get us the same operational guarantee with less typeclass weight.

## 9. Relation to wider theory and ADRs

- ADR-0007 named the five components without committing their
  types or relations. ADR-0009 commits them.
- ADR-0008 fixed the algebra (`Holistic ⊣ Formal`) parameterised
  over `Field`. ADR-0009 fills `Field` in. The algebra is
  unchanged.
- `docs/THEORY.md` §3.2 argues that the dual-mode structure is
  not a metaphor for hemispheric asymmetry but a precise
  algebraic shape. ADR-0009 is the second concrete instantiation
  of that argument (ADR-0008 was the first).
- Phase 5 will use the `Field` from this ADR plus the adjunction
  from ADR-0008 to express the salience-controller decision as
  a choice of morphism through the adjunction. ADR-0010 will
  pin that decision when it lands.

## 10. Acceptance criteria for the Phase-4 PR

The Phase-4 implementation will be considered complete when:

1. `cabal build lib:qxfx0` is clean with the new module exposed
   and the modified `QxFx0.Self.Adjunction` continuing to type
   against the substantive `Field`.
2. `scripts/check_architecture.sh` passes.
3. `Test.Suite.SelfField` ships with at least one property for
   /each/ of the items listed in §6 step 3.
4. `Test.Suite.SelfAdjunction`, updated to use the composite
   `Field` generator, continues to pass all five Phase-3
   acceptance criteria from ADR-0008 §10.
5. `Test.Suite.SelfAdjunction` is unchanged in its assertions —
   only its generator definition changes. (Documentation
   discipline: a Phase-N+1 PR should not be allowed to weaken
   Phase-N tests.)
6. The new module exports exactly the surface listed in §3.
7. No call site outside `Self.*` and the new test modules imports
   the `Field` components; the integration into `Core.*` and
   `RouteEffects` is the explicit non-goal of P4 and is deferred
   to P5.

## 11. Honest limits

The five-component decomposition is a theoretical commitment, not
a derivation. McGilchrist's right-hemispheric profile lists more
than five attentional postures, and even within the five we
chose, there are defensible alternatives (e.g. swapping
`Counterfactual` for an explicit `Surprise` term). We picked
these five because:

- they collectively cover the failure modes the system has
  exhibited (`Resonance` and `Consolidation` for narrative drift;
  `Atmosphere` for tonal mismatch; `FieldConfidence` for false
  certainty; `Counterfactual` for over-collapse to the
  highest-posterior parse);
- each can be sourced from signals already present in the
  codebase by Phase 5;
- they are mutually distinct enough that combining them yields
  more than any single component does.

We do not claim this is *the* decomposition; we claim it is
*a* decomposition that admits a clean type, total combinators,
and test coverage. Future ADRs may revise the set without
disturbing the Phase-3 algebra above it, because the algebra
treats `Field` opaquely.

## Addendum (2026-05-17, Phase 5.5d) — runtime sourcing

The body above (Phase 4) deliberately deferred *where* each
Field component is sourced from at runtime: "This module is the
algebraic shape... Sourcing of values from runtime signals
(semantic embedding, consciousness-loop narrative tone,
Bayesian posterior diversity, etc.) is Phase-5 work and lives
outside this module."

This addendum records the concrete sourcing decisions for the
pre-turn `Field` carried by `psField` (in
`QxFx0.Core.TurnPipeline.Effects.PrepareStatic`), threaded
through `tiField` in `TurnInput`, and consumed by routing-side
salience in `QxFx0.Core.TurnRouting.routeFamily`. Four of the
five components are now populated from runtime signals; the
fifth (`FieldConfidence`) remains at the `emptyField` default
of `1.0` for the reasons documented at the end.

### Resonance ← atom-trace current load

```
fieldResonance = mkResonance resonance
  where resonance = atCurrentLoad newTrace
        newTrace = updateTrace (ssTrace ss) (ssTurnCount ss) atomSet
```

The atom-trace `currentLoad` already exists as
`QxFx0.Semantic.MeaningAtoms.atCurrentLoad`, in `[0, 1]`, and
measures recent meaning-atom activation density. This is
structurally what Resonance documents ("strongest echo found"
in §2.1 of this ADR's Phase 5 successor). No new signal source.

### Atmosphere ← Ego differential

```
atmosphereValence = egoAgency (ssEgo ss) - egoTension (ssEgo ss)
atmosphereArousal = egoTension (ssEgo ss)
fieldAtmosphere   = mkAtmosphere atmosphereValence atmosphereArousal
```

- *Arousal* maps directly to Ego tension. Both quantities
  measure activation/intensity level, so they are
  structurally the same signal; no additional sourcing.
- *Valence* maps to the agency-minus-tension differential.
  High agency + low tension reads as confident/positive;
  low agency + high tension reads as overwhelmed/negative.
  Both Ego components are clamped to `[0, 1]` by their
  smart constructors, so the difference naturally lies in
  `[-1, 1]`; `mkAtmosphere` clamps defensively.

### FieldConfidence ← `1.0` (deferred)

Stays at the `emptyField` default. Per §4.4: "a system that
has not yet observed anything is uninformed, not unconfident".
We could call `deriveFieldConfidence preparedFieldPartial`
once the other four components are populated, but with all
four sources still heuristic (per Phase 7 calibration debt),
a derived confidence would risk false precision. The
`deriveFieldConfidence` wiring is tracked as an explicit
follow-up in the project todo (`Optional-deriveFieldConfidence`)
and is gated on Phase 7 calibration data.

### Consolidation ← topic-stability heuristic

```
topicStability =
  if not (T.null bestTopic) && bestTopic == ssLastTopic ss
    then 0.8
    else 0.2
fieldConsolidation = mkConsolidation topicStability
```

Per §2.2: "Consolidation accumulates over a window". In a
1-turn window the natural minimum signal is whether the
focused topic carried over. The `0.8` / `0.2` levels (not
`1.0` / `0.0`) keep the contribution to Salience meaningful
without saturating the sigmoid. The empty-focus case
(`T.null bestTopic`) is treated as "topic changed" rather
than "topic same", to avoid spuriously consolidating on the
empty-string degenerate case.

### Counterfactual ← candidate-family ambiguity

```
counterfactualAmbiguity = case sortedLogic of
  (_, w1) : (_, w2) : _ | w1 > 0 -> w2 / w1
  _ -> 0.0
fieldCounterfactual = mkCounterfactual counterfactualAmbiguity
```

Per §2.5: "diversity of plausible alternative
interpretations… normalised to `[0, 1]`. High = posterior
was spread; low = posterior was peaked." The semantic-logic
ranking (`runSemanticLogic`) enumerates plausible
canonical-move families with weights; the ratio of the
runner-up weight to the leader captures the spread/peaked
dichotomy exactly. When `w1 > w2` (strictly peaked), the
ratio is `< 1`; when `w1 ≈ w2` (genuine ambiguity), the
ratio approaches `1`. The `w1 > 0` guard handles the all-zero
degenerate case; `mkCounterfactual` clamps defensively.

### Calibration debt (Phase 7)

All four sourcing formulas above are *heuristic*. The
specific constants (`0.8` / `0.2` for Consolidation;
`agency - tension` for Atmosphere valence; the linear
ratio for Counterfactual) are defensible but not calibrated
against production traces. They are tracked in the project
todo (`M7`) for tuning once labelled trace data is
available; until then, the SelfSalience monotonicity
properties guarantee that the directions of the
contributions are correct even if the magnitudes are
imprecise.
