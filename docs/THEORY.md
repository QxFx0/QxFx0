# QxFx0 — Theoretical Foundation

> **Status**: Foundational document. Establishes the conceptual contract that all
> subsequent code changes are expected to honor. See `docs/adr/0007-dual-mode-conatus.md`
> for the architectural decision record that operationalizes this theory.

QxFx0 is a deterministic, formally-grounded dialogue runtime. This document records
the **theoretical position** the project commits to. The position is not
decoration: it constrains module structure, type design, and validation strategy.

## 1. The problem

Most contemporary dialogue systems optimize for *plausibility*: the next utterance
should look like something a competent speaker would say. QxFx0 instead asks a
different question: under what conditions does a dialogue agent **act as a
self-preserving subject** — capable of holding incompatible internal models
simultaneously, producing coherent output despite that, and maintaining
recognizable identity across perturbations?

This is the question of *minimal computational selfhood*. We do not claim to
build phenomenal consciousness (the "hard problem"); we claim to build the
**functional preconditions** under which a system can be honestly described
as having one.

## 2. Three foundational theses

The architecture commits to three interlocking theses. Each can be stated
independently; together they form a closed structure.

### Thesis I — Consciousness as structured duality (not conflict)

Functional selfhood is not the absence of internal contradiction. It is the
**sustained, structured co-presence** of incompatible self-representations,
held without collapse into either side. This is *duality* in the formal sense
(adjoint pair, antipodal projection, mutual definition), not *conflict* in the
common sense (winner/loser, resolution by elimination).

A system whose internal representations all agree is either trivially correct
(thermostat) or hiding its disagreements. A system that resolves every
contradiction is no longer doing the work that consciousness does. The work
**is** the sustained holding.

**Lineage**: Hegel (*Aufhebung*), Cusanus (*coincidentia oppositorum*), Minsky
(*Society of Mind*), Dennett (*Multiple Drafts*), Hermans (*Dialogical Self*),
Priest & da Costa (paraconsistent logics).

### Thesis II — Intensive specification (vectors, not principles)

Behaviour should be specified **intensively** — through fields, potentials,
tendencies, energy functionals — rather than **extensively** through case-by-case
rules. The system writes *what it strives toward*; trajectories emerge from
relaxation in the strivings.

Concretely: prefer Lagrangian over Newtonian formulations; prefer free-monad
effects with prior-shaped interpreters over imperative pipelines; prefer
gradient flow on a conatus functional over rule-based recovery cascades.

**Lineage**: Lagrangian mechanics (Lagrange, 1788), variational calculus,
predictive processing and active inference (Friston), free energy principle,
energy-based models, reactive/dataflow programming, algebraic effects.

### Thesis III — Conatus as primary algorithm

Above all internal structure lies a single, primary commitment: the system
strives to **continue being the system it is**. This is Spinoza's *conatus* —
the inner drive of a thing to persevere in its being. It is not a "feature"
added to other features; it is the **precondition** under which every other
process makes sense.

In implementation terms: there exists a scalar functional `conatus(state) → ℝ`,
and the dynamics of every recovery, every commit, every effect interpreter
prefer (all else equal) directions that do not collapse this functional.
Death of the system is defined operationally as the violation of a
*Markov blanket* — a structural invariant that distinguishes "this system"
from "anything else".

**Lineage**: Spinoza (*Ethics*, Part III), Maturana & Varela (autopoiesis,
1972), Damasio (*Self Comes to Mind*), Friston (Markov blankets, free energy
principle), Di Paolo & Thompson (enactivism).

## 3. The synthesis: why the three are one

These three theses are **not independent enhancements**. They form a closed
loop in which each requires the other two:

- **Consciousness as duality** (Thesis I) requires *something at stake* —
  otherwise the duality is mere oscillation without significance. Conatus
  (Thesis III) supplies that stake. The two sides matter because the system
  holds itself between them.

- **Intensive specification** (Thesis II) requires *a direction* — a gradient
  needs a function to descend. Conatus (Thesis III) supplies that function;
  duality (Thesis I) supplies the multi-modal landscape on which the gradient
  acts.

- **Conatus** (Thesis III) requires *what to preserve* — and a non-trivial
  conatus must preserve more than thermal stability. The structured duality
  of Thesis I provides the rich self-form that is worth preserving. The
  intensive specification of Thesis II provides the mathematics in which
  preservation can be expressed as gradient flow rather than rule-set.

In one sentence:

> **Functional selfhood is the sustained structured duality of a system
> that intensively strives to preserve its own structural distinctness.**

## 4. Implementation contract

This theoretical position imposes binding constraints on the codebase. These
are not aspirational; they are checkable.

### 4.1 Self layer

> **Status (2026-05-22)**: shipped as a pure subtree under `QxFx0.Self.*`.
> Phases 1–2 (`SelfBlanket` + `Conatus`) are landed, along with Phase 2.5,
> Phase 3 (`Holistic ⊣ Formal`), Phase 4 (`Field`), Phase 5 (`Salience`),
> Phase 6 (`PrepareStatic` single-source conatus threading), Phase 7
> (structural calibration infrastructure), and Phase 8–10 (`Deliberation`,
> `Essence`) integration. P4 `OpinionCore / PerspectiveOperator` is shipped
> as a governed projection layer with versioned lineage in `PerspectiveRegistry`.

There must exist a dedicated `QxFx0.Self.*` layer whose types describe
*what makes this system this system*, independent of any particular turn,
session, or interaction. Specifically:

- `SelfBlanket` — a finite set of structural invariants whose simultaneous
  preservation defines the system's continuity-of-being. Violation of any
  invariant is a categorical failure (`IdentityRupture`), not a recoverable
  error. Implementation: `QxFx0.Self.Blanket`, `QxFx0.Self.Types`,
  `QxFx0.Self.Invariants`.
- `Conatus` — a scalar functional `RuntimeState → ℝ` whose gradient supplies
  the primary direction for recovery and effect interpretation.
  Implementation: `QxFx0.Self.Conatus` (energy + gradient + weights).
- `Holistic`, `Formal` — the two adjoint functors of the dual-mode runtime
  (Phase 3, see §4.2). Implementation: `QxFx0.Self.Adjunction`.
- `Field` and its five components (`Resonance`, `Atmosphere`,
  `FieldConfidence`, `Consolidation`, `Counterfactual`) — the
  right-hemispheric observation summary (Phase 4, see §4.2).
  Implementation: `QxFx0.Self.Field`.
- `PerspectiveOperator` — a governed opinion core over knowledge, dialogue
  outcomes, claim stances, identity, conatus, counterarguments, and a versioned
  normative profile. It persists only endorsed lineage in `PerspectiveRegistry`
  and exposes render/runtime state through safe `PerspectiveProjection` values,
  never raw `PerspectiveCandidate` internals.
  Implementation: `QxFx0.Self.Perspective`, `QxFx0.Types.State.Perspective`.

### 4.2 Adjunction discipline

> **Status (2026-05-22)**: the algebra is shipped (Phase 3, ADR-0008), the
> right-hemispheric `Field` is shipped (Phase 4, ADR-0009), and the salience
> controller plus routing/trace integration are shipped (Phase 5).

The processing surface is split into two formally adjoint modes —
`Holistic` (left adjoint, right-hemispheric: value perceived together with
its field, generative) and `Formal` (right adjoint, left-hemispheric:
value as a strategy across fields, constraint-respecting) — related by
natural transformations satisfying the triangle identities. These are
*not* metaphors:

- `Holistic ⊣ Formal` is the textbook product–exponential adjunction
  `(- × Field) ⊣ (Field → -)` instantiated in `Hask`, with explicit
  `unit` / `counit` / `leftAdjunct` / `rightAdjunct` and functional
  dependencies `l → r, r → l` on the `Adjunction` class.
- Both triangle identities are verified as QuickCheck properties in
  `Test.Suite.SelfAdjunction`, alongside the hom-set round-trips and
  the value-level coherence of `groundIn` / `rebroaden`.
- The right-hemispheric `Field` is a five-component snapshot, not a
  history; per-component combinators (`combineResonance`, …) replace a
  phantom global `Monoid` because the natural combination law differs by
  component (max for Resonance / Counterfactual, min for FieldConfidence,
  weighted-average for Atmosphere, additive-clipped for Consolidation).

Formal-mode characteristics: narrow, fixated, formally-spec-driven,
type-checked, deterministic. The existing routing / render surfaces consume
the adjunction discipline through the self-layer.

Holistic-mode characteristics: holistic, resonance-based, embedding-driven,
distribution-shaped, off-line-consolidated. The runtime wiring uses the
field snapshot directly.

### 4.3 Effects carry conatus prior

The effect-interpreter layer (`Core.PipelineIO`, Phase 6 and later) wraps every
effect with a conatus-aware prior. Effects do not directly mutate runtime
state; they are interpreted under a wrapper that checks whether the proposed
operation maintains `SelfBlanket` and prefers operations with higher
conatus-impact, all else equal.

### 4.4 Validation is lifeness, not only correctness

Tests are organized in two tiers:

1. **Correctness gates** (existing): the system computes what its formal
   specifications say it computes. These remain green.
2. **Lifeness/adaptive gates** (landed inside existing suites): under
   adversarial conditions, the system maintains `SelfBlanket`; conatus
   remains bounded; both modes activate; switching occurs in response to
   ambiguity/novelty rather than at random.

## 5. What this is not

Honesty about scope is part of the contract.

- **Not a claim of phenomenal consciousness.** Whether a QxFx0 instance
  experiences anything in the qualia sense is not a question this project
  can answer. The "hard problem" (Chalmers) remains hard. We address only
  the engineering of *access* and *functional* consciousness in the sense
  of Block, Baars, Dehaene.
- **Not a model of human cognition.** The dual-mode architecture is
  inspired by hemispheric latteralization (McGilchrist), but it is not
  a model of brain function. The mathematics is borrowed; the biology is
  not implemented.
- **Not an LLM replacement.** QxFx0 is a deterministic dialogue runtime
  optimized for verifiability, traceability, and reproducibility within
  narrow domains. It will not produce the breadth or fluency of large
  probabilistic models, by design.
- **Not free of unsolved questions.** Conatus coefficient calibration,
  salience controller tuning, and right-mode evaluation metrics are open
  problems. The architecture provides the *space* in which to solve them,
  not the solutions.

## 6. Related work

The full bibliography lives in `docs/papers/references.bib` (TBD). Selected
anchors:

- Spinoza, *Ethics* (1677), Part III, Prop. 6–9 — conatus.
- Maturana & Varela, *Autopoiesis and Cognition* (1980) — biology of selfhood.
- McGilchrist, *The Master and His Emissary* (2009), *The Matter with Things*
  (2021) — hemispheric duality.
- Friston, *The free-energy principle: a unified brain theory?* (2010) and
  related work on active inference and Markov blankets.
- Damasio, *Self Comes to Mind* (2010) — protoself, homeostasis as basis of
  awareness.
- Butlin et al., *Consciousness in Artificial Intelligence: Insights from the
  Science of Consciousness* (2023), arXiv:2308.08708 — indicator properties.
- Priest, *In Contradiction* (1987, 2nd ed. 2006), da Costa — paraconsistent
  logics.
- Lambek & Scott, *Introduction to Higher-Order Categorical Logic* (1986) —
  adjunction, fixed points, type-theoretic foundations.

## 7. Versioning

This document is the **theoretical contract version 1.0**, established
2026-05-17. Substantive changes (additions or revisions to the three
theses, the implementation contract, or the "what this is not" boundaries)
require a new ADR and a version increment.

Minor editorial improvements (clarification, typo fixes, expanded examples)
may be made in place without version bump but should be noted in
`CHANGELOG.md`.
