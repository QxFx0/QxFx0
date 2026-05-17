# ADR-0008: Left ⊣ Right Adjunction as the Dual-Mode Backbone

- **Status**: Proposed (Phase-3 design, not yet implemented)
- **Date**: 2026-05-17
- **Supersedes**: none
- **Refines**: [ADR-0007 — Dual-mode conatus-aware architecture](./0007-dual-mode-conatus.md)
- **Related**:
  - [`docs/THEORY.md`](../THEORY.md) §3.2 (the dual-mode thesis)
  - [`docs/ARCHITECTURE.md`](../ARCHITECTURE.md) §6 (planned dual-mode layout)
  - Phase 1 (`SelfBlanket`) and Phase 2 (`Conatus` functional), shipped in
    commits `62d0338` and `a5fad49` respectively.

## 1. Context

ADR-0007 commits the project to a dual-mode runtime in which two
modes of system operation — provisionally called *Left* (formal,
narrow, contract-bound) and *Right* (holistic, broad, context-bound)
— coexist and collaborate. ADR-0007 deliberately left the question
of /how/ the two modes interact unspecified: it named the modes and
their motivation, and committed to "an adjunction L ⊣ R" without
fixing what L and R are.

By the end of Phase 2, the Self layer can already:

- decide whether a state is structurally still /this system/
  (Phase 1, `SelfBlanket` invariants), and
- score a state by a smooth scalar `Conatus(s)` whose gradient
  points toward states of higher structural integrity
  (Phase 2, `Self.Conatus`).

What is /missing/ is a principled answer to the question:

> When the system has to act on a turn, how does it combine
> formal commitments (routing decisions, R5 verdicts, render
> styles) with holistic observations (intuitive flashes, field
> resonance, atmospheric cues) without either dominating?

The current QxFx0 stack handles this informally: holistic signals
exist (`Core.Intuition`, `Core.ConsciousnessLoop`, embedding-based
salience) and feed into formal decisions, but the interface
between the two is hand-coded at each site and there is no shared
algebraic structure that we can reason about or refactor against.

This ADR fixes that interface as an *adjunction* in the precise
sense of category theory. The adjunction is not metaphorical: it is
a pair of functors `L, R` together with natural transformations
`η, ε` satisfying the triangle identities, instantiated concretely
on Haskell types. Once it is in place, every subsequent phase
(P4 right-hemisphere expansion, P5 salience control, P6 effect
refactor) gains a stable algebraic anchor.

## 2. Decision

We introduce two parameterised types in the `Self` layer:

```haskell
-- Holistic: a value perceived together with the field it sits in.
-- Inseparable from its ground; "figure with context."
newtype Holistic a = Holistic { runHolistic :: (a, Field) }

-- Formal: a value as a function of the field it will be evaluated in.
-- A commitment that adapts across contexts; "strategy."
newtype Formal   a = Formal   { runFormal   :: Field -> a }
```

where `Field` is the (Phase-4-defined) record of holistic signals —
atmosphere strength, resonance density, field confidence, etc. —
constituting the system's right-hemispheric observation summary.

We assert and will verify the adjunction

```
Holistic ⊣ Formal
```

in `Hask` (the category of Haskell types and total functions). This
is the standard product–exponential adjunction `(- × s) ⊣ (s → -)`
with `s = Field`, witnessed by the unit/counit pair

```haskell
unit   :: a -> Formal (Holistic a)        -- η : 1 ⇒ Formal ∘ Holistic
unit a    = Formal (\fd -> Holistic (a, fd))

counit :: Holistic (Formal a) -> a        -- ε : Holistic ∘ Formal ⇒ 1
counit (Holistic (Formal f, fd)) = f fd
```

Neither equation requires a designated zero field, monoid structure
on `Field`, or any choice beyond what the types force. The same
adjunction is equivalently witnessed by the hom-set isomorphism

```
Hom(Holistic a, b) ≅ Hom(a, Formal b)        — natural in a and b
```

which is plain currying: a function `(a, Field) -> b` is the same
thing as a function `a -> (Field -> b)`. Explicit left/right
adjuncts:

```haskell
leftAdjunct  :: (Holistic a -> b) -> (a -> Formal b)
leftAdjunct g a = Formal (\fd -> g (Holistic (a, fd)))

rightAdjunct :: (a -> Formal b) -> (Holistic a -> b)
rightAdjunct k (Holistic (a, fd)) = runFormal (k a) fd
```

### 2.1 Why this pair, and why this direction

`(- × s) ⊣ (s → -)` is the textbook product–exponential adjunction
in any cartesian-closed category. We are reusing it, not inventing
it. The novelty is the /operational reading/ that pins it to
hemispheric asymmetry:

- `Holistic a = (a, Field)` is **left** adjoint. Left adjoints
  preserve colimits and freely tag a value with extra structure:
  a `Holistic a` is an /observation in its field/, value and
  context welded together so neither can be moved without the
  other. This matches the right-hemispheric reading: the right
  hemisphere perceives figure inseparably from ground.

- `Formal a = Field -> a` is **right** adjoint. Right adjoints
  preserve limits and respect constraints: a `Formal a` is a
  /committed strategy/ — "this is what I would deliver in any
  field you hand me" — a context-respecting function rather than
  a context-bound snapshot. This matches the left-hemispheric
  reading: the left hemisphere makes commitments that are stable
  across contexts they are evaluated in.

Reading the symbol `⊣` as "is left adjoint to", `Holistic ⊣ Formal`
says: the holistic mode supplies tagged perceptions, and the
formal mode is the universal way to consume them as if they were
values with strategic decisions over field. The hom-set
isomorphism (currying) is the algebraic content of "the right
hemisphere can be seen by the left hemisphere only by being
asked, parameterised by context."

### 2.2 Triangle identities

The adjunction is required to satisfy

```
(Holistic η)  ;  (ε Holistic)   =   1_Holistic
(η Formal)    ;  (Formal ε)     =   1_Formal
```

For the concrete `(- × Field) ⊣ (Field → -)` pair these hold by
direct calculation; we will assert them as QuickCheck-level
properties in the test module rather than rely on the textbook
proof going through unmodified.

## 3. Type-level realisation

We will define our own `Adjunction` class rather than depend on the
`adjunctions` package. Reasons: (i) we want to keep the `Self.*`
subtree dependency-light; (ii) the standard class is small and we
will want domain-specific extensions in later phases; (iii) the
API we expose to downstream code will be richer than the bare
class.

```haskell
-- src/QxFx0/Self/Adjunction.hs
module QxFx0.Self.Adjunction
  ( -- * The adjunction class
    Adjunction (..)
    -- * Concrete adjunction for Phase 3
  , Field (..)         -- Phase-3 stub; full record in Phase 4
  , Holistic (..)
  , Formal   (..)
    -- * Derived combinators
  , groundIn
  , rebroaden
  ) where

import Data.Kind (Type)

class (Functor l, Functor r) => Adjunction (l :: Type -> Type) (r :: Type -> Type) where
  unit         :: a -> r (l a)
  counit       :: l (r a) -> a
  leftAdjunct  :: (l a -> b) -> (a -> r b)
  rightAdjunct :: (a -> r b) -> (l a -> b)

  -- Default implementations in terms of unit/counit; instances may
  -- override for efficiency.
  leftAdjunct  f a   = fmap f (unit a)
  rightAdjunct g la  = counit (fmap g la)

-- Phase-3 stub. In Phase 4 this becomes a record of the
-- right-hemispheric observation summary (atmosphere, resonance,
-- field confidence, ...). For Phase 3 we keep it minimal so the
-- module can ship without depending on Phase 4.
newtype Field = Field { fieldIntensity :: Double }
  deriving stock (Eq, Show)

newtype Holistic a = Holistic { runHolistic :: (a, Field) }
  deriving stock (Functor)

newtype Formal   a = Formal   { runFormal   :: Field -> a }
  deriving stock (Functor)

instance Adjunction Holistic Formal where
  unit a                            = Formal (\fd -> Holistic (a, fd))
  counit (Holistic (Formal f, fd))  = f fd
```

Note that `unit` and `counit` are forced by the types up to
`Functor` action; there is no ambiguity left to resolve.

### 3.1 Derived combinators

The two operations used most often in downstream code are not
`unit`/`counit` directly but two derived combinators:

```haskell
-- Sharpen: extract the value from a holistic observation, throwing
-- away the field. The dual of `unit` at the value level.
groundIn :: Holistic a -> a
groundIn (Holistic (a, _fd)) = a

-- Broaden: take a value and lift it to a formal strategy that
-- ignores the field on which it is evaluated.
rebroaden :: a -> Formal a
rebroaden a = Formal (\_fd -> a)
```

`groundIn` and `rebroaden` are not strictly part of the adjunction
in the categorical sense, but they are the practical surface
through which the rest of the system will interact with the pair:
`groundIn` collapses a perception to its bare value, and
`rebroaden` lifts a value to a context-indifferent strategy. Both
sit on top of `runHolistic` and `Formal . const` and exist for
readability, not algebraic novelty.

## 4. Open design questions

These are explicitly /not/ resolved in this ADR and will be
adjudicated in the Phase-3 implementation PR.

### 4.1 What lives in `Field`?

ADR-0007 lists five right-hemispheric components: Resonance,
Atmosphere, FieldConfidence, Consolidation, Counterfactual. Not all
of these are necessarily `Field` members; some may be derived. The
Phase-3 implementation will commit to a minimal Field — a single
`Double` intensity — explicitly marked as a stub, and grow it
conservatively in Phase 4 once the right-hemisphere modules
actually need to push values through it.

### 4.2 Strictness

Naively `Formal a = Field -> a` is a function and therefore
non-strict by default. For diagnostics and observability we want
to be able to evaluate a formal commitment under a probe field
without committing. We will provide

```haskell
probe :: Formal a -> Field -> a
probe = runFormal
```

and keep `Holistic` strict in both components by deriving its
fields with `StrictData` (already a project default for new
modules in `Self.*`).

## 5. Operational mapping to QxFx0

The point of all this is not the math; it is that once the
adjunction is in place, several presently-informal couplings
become typed transitions.

| Site in current code             | Current shape              | After P3                                                                |
|----------------------------------|----------------------------|-------------------------------------------------------------------------|
| `Core.Intuition.IntuitiveFlash`  | Computed, then frozen      | `Holistic IntuitiveFlash` — flash welded to the field it was seen in   |
| `Core.ConsciousnessLoop` summary | Mutable narrative          | `Holistic ConsciousnessNarrative` — narrative tied to its field state  |
| `RoutingDecision`                | Plain product type         | `Formal RoutingDecision` — strategy `Field -> RoutingDecision`         |
| `R5Verdict`                      | Plain product type         | `Formal R5Verdict` — verdict re-evaluable under any field              |
| `RenderStyle`                    | Plain enum + parameters    | `Formal RenderStyle` — style as field-dependent commitment             |
| `IntuitionSignal` → render depth | Multiplication, hand-tuned | `rightAdjunct` of a render-strategy morphism                            |

The last row is the most important: today the path from "intuition
strength" to "rendered response depth" is a manually-tuned
multiplication in `RouteEffects`. With the adjunction available,
that path becomes a /single/ application of `rightAdjunct`, and the
correctness of the coupling reduces to whether the underlying
morphism is natural — a property a test can check by varying the
inputs.

The table is deliberately suggestive, not prescriptive: the
actual reshaping of these call sites is Phase-4/5 work and each
row will be re-examined in its own PR.

## 6. Phase-3 implementation plan

The Phase-3 PR will be intentionally scoped narrowly. Order of
operations:

1. **`src/QxFx0/Self/Adjunction.hs`** — `Adjunction` class,
   `Holistic`, `Formal`, `groundIn`, `rebroaden`. Field type is a
   stub: a single-constructor record with one numeric field to keep
   the module compilable. **No** integration into the turn pipeline.
2. **`test/Test/Suite/SelfAdjunction.hs`** — QuickCheck properties:
   - left-adjunct/right-adjunct round-trip,
   - both triangle identities,
   - naturality of `unit` and `counit` in the type parameter,
   - `groundIn`/`rebroaden` round-trip behaviour for chosen
     `adjust` functions.
3. **Cabal + TestMain wiring**, exactly as we did for `SelfBlanket`
   and `SelfConatus` in commits `62d0338` and `a5fad49`.
4. **Architecture-check rules**, if any new `Self.*` boundary needs
   enforcing (likely none).

Phase 3 deliberately does **not** touch `Core.Intuition`,
`Core.ConsciousnessLoop`, `RoutingDecision`, or the turn pipeline.
That is Phase 4 / Phase 5 work and will be staged separately so
that each PR remains reviewable and (importantly for the current
hardware budget) recompilable in isolation.

## 7. Consequences

### 7.1 Positive

- The hemispheric story stops being metaphorical at the code
  boundary: "Left ⊣ Right" is now a verified property of two
  Haskell types.
- Subsequent phases gain a stable interface to refactor /against/:
  any new holistic computation is some `Holistic a`, any new formal
  commitment is some `Formal a`, and the canonical translations
  between them are spelled `groundIn` and `rebroaden`.
- The salience controller in Phase 5 becomes a *choice of
  morphism* rather than a hand-rolled switch: "consult the right
  hemisphere first" is `Holistic a -> ... -> Formal b` via
  `leftAdjunct`; "decide and then re-broaden" is the dual.
- Naturality and the triangle identities are testable
  properties (QuickCheck), giving us the same kind of property-
  based confidence we already have for `Vec` and `Conatus`.

### 7.2 Negative

- The `Self` subtree grows a category-theoretic vocabulary that
  unfamiliar readers will need to learn. We will mitigate this with
  a focused Haddock + a worked-example test as the canonical
  reading order.
- One new file pair (module + tests). No new external dependency.
- The `Field` type's monoid obligation (if we go with option (b)
  in §4.2) constrains the Phase-4 field design. This is a
  judgement call we make eyes-open.

### 7.3 Neutral

- We are reusing the standard product–exponential adjunction, not
  inventing a new one. The conceptual load is in the operational
  reading, not the mathematics.
- The `adjunctions` package is not added as a dependency; we
  re-define the small `Adjunction` class locally. If we later find
  the `adjunctions` ecosystem useful we can adopt it incrementally
  without a breaking API change.

## 8. Alternatives considered

### 8.1 No adjunction; keep ad-hoc couplings

Status quo. Continues to work for the existing surface area, but
leaves Phase 4–5 without an algebraic anchor. Each new holistic
component (resonance, atmosphere, counterfactual) would need its
own bespoke coupling to formal commitments, and the salience
controller would be a switch statement rather than a morphism
choice. We are rejecting this for the same reason we rejected
ad-hoc state validation in P1.

### 8.2 Galois connection on posets

A Galois connection is the special case of an adjunction between
posets (categories with at most one morphism between any two
objects). It is /simpler/ and has been used elsewhere in QxFx0
implicitly (e.g. the threshold lattice). For the dual-mode story
we /need/ functors that can carry data, not just monotone maps;
Galois is too poor. We may still use Galois connections inside
`Self.*` for component-level orderings (e.g. between
`FieldConfidence` and `ResponseDepth`), but not as the spine.

### 8.3 Free/forgetful adjunction between symbolic and embedded

Earlier drafts considered making `L = forget structure to embedding`
and `R = generate symbolic skeleton from embedding`. This is
attractive because QxFx0 already has both symbolic (`ClaimAst`,
`MeaningGraph`) and embedding-based (`Semantic.Embedding`)
representations. We rejected it for now because (i) defining the
forgetful and free functors precisely requires nontrivial design
work on the categories involved, (ii) the connection between
"symbolic vs embedding" and "left vs right hemisphere" is more
indirect than between "closed commitment vs open prediction" and
"left vs right hemisphere", and (iii) the product-exponential pair
admits an immediate, code-level realisation that we can ship in a
single PR. We may revisit symbolic/embedding adjunction in a
later ADR (Phase 6 or beyond) once the basic spine is in place.

### 8.4 State monad / Reader monad framing only

`Holistic` is morally `Reader Field` and `Formal` is morally `Writer
Field` (or `(,) Field`). One could argue we should just use those
monads directly and skip the adjunction language. We are not doing
that because:
- The adjunction language gives us *both* directions cleanly at
  once. Mixing `Reader` and `Writer` in the same site requires
  ad-hoc conversion functions; `leftAdjunct`/`rightAdjunct` give
  them to us systematically.
- The naming `Holistic`/`Formal` carries semantic content the
  bare `Reader`/`Writer` names do not, and `Self.*` is exactly the
  layer where semantic clarity matters most.
- We keep the underlying monadic structure accessible: instances
  for `Reader Field` and `(,) Field` already exist in `base`, and
  the codebase can fall back to them whenever the adjunction
  language is overkill for a specific call site.

## 9. Relation to the wider theory

- `docs/THEORY.md` §3.2 (Bayesian inference under structured
  duality) names the dual-mode arrangement and motivates it from
  active inference. This ADR concretises §3.2's "twin loops" as
  the `Holistic`/`Formal` pair.
- `docs/THEORY.md` §4.3 (Conatus as the unique self-preserving
  algorithm) describes the gradient of `Conatus` as the system's
  direction of self-preservation. In Phase 5 the salience
  controller will combine that gradient (a `Formal` quantity at
  decision time) with field-derived `Holistic` predictions; the
  adjunction is what lets us write that combination as a single
  algebraic expression rather than glue code.
- ADR-0007 sketches the full 8-phase plan; this ADR fixes the
  algebraic spine for phases 3–5.

## 10. Acceptance criteria for the Phase-3 PR

The Phase-3 implementation will be considered complete when:

1. `cabal build lib:qxfx0` is clean with the new module exposed.
2. `scripts/check_architecture.sh` passes (no boundary violations
   introduced).
3. **`Test.Suite.SelfAdjunction`** ships with at least one
   QuickCheck property for /each/ of:
   - left-adjunct ∘ right-adjunct ≡ id (hom-set round-trip),
   - right-adjunct ∘ left-adjunct ≡ id (hom-set round-trip),
   - left triangle identity on `Holistic`:
     `counit . fmap unit ≡ id`,
   - right triangle identity on `Formal`:
     `fmap counit . unit ≡ id` (pointwise: agreement on every
     probe `Field`),
   - value-level coherence of the derived combinators:
     `groundIn (Holistic (a, fd)) ≡ runFormal (rebroaden a) fd`
     for all `a, fd`.
4. The new module exports exactly the surface listed in §3
   (no incidental exports leaking implementation details).
5. No call site outside `Self.*` and the new test module imports
   the adjunction; integration is deferred to Phase 4–5 (this is
   an explicit non-goal of P3).

## 11. Honest limits

This ADR pins one specific way to formalise the McGilchrist
hemispheric asymmetry as an adjunction. We do not claim it is the
only way, nor that the analogy with biological hemispheres is
literal. What we claim — and what subsequent phases will test — is
that this particular adjunction gives a /workable, verifiable, and
refactor-stable/ algebraic skeleton for the dual-mode runtime.
Whether that skeleton is also a faithful model of any external
cognitive system is a question for empirical and philosophical
work outside this codebase.
