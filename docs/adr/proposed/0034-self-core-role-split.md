# ADR-0034 (proposed): Self/Core Role Split

- **Status**: Proposed (closure-phase work product, Package 1)
- **Date**: 2026-06-02
- **Refines**:
  - [ADR-0007 — Dual-mode conatus-aware architecture](../0007-dual-mode-conatus.md)
  - [ADR-0008 — Left ⊣ Right adjunction](../0008-left-right-adjunction.md)
  - [ADR-0009 — Right-hemisphere Field](../0009-right-hemisphere-field.md)
  - [ADR-0010 — Salience Controller](../0010-salience-controller.md)
  - [ADR-0011 — Deliberation Framework](../0011-deliberation-framework.md)
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)
- **Related**:
  - `docs/closure/AUTHORITY_MAP.md`
  - `docs/closure/SELF_LAYER_STATUS.md`
  - `docs/AUTHORITY_BOUNDARY.md` (2026-05-26)

## 1. Context

`QxFx0_v3` has a strong **pure self-layer** (`QxFx0.Self.*`, Phases 1–10,
all landed) and a **narrative content supplier** (`QxFx0.Core/Consciousness/*`).
The freeze-0 `AUTHORITY_BOUNDARY.md` (2026-05-26) classifies paths
correctly but does not commit to a per-module role split inside
`Self/*` and `Core/*`.

The closure plan's Package 1 demands that this split be **explicit,
auditable, and CI-enforceable**. Currently the split is implicit:
the `Self/*` subtree is pure, the `Core/*` subtree has both suppliers
and canonical orchestrators, and a few modules (`Self.Essence`,
`Self.Perspective` family divergence) are **canonical-flag-off** —
landed, type-checked, tested, but not in the runtime path.

This ADR commits the per-module classification and the boundary rules
that make the role split enforceable.

## 2. Decision

We adopt the authority classes defined in `docs/closure/AUTHORITY_MAP.md §1`
and apply them per-module as follows:

### 2.1 Self-layer is canonical by construction

Every module under `src/QxFx0/Self/` is one of:

- **canonical** — runtime-authoritative (e.g. `Conatus`, `Field`, `Salience`, `Deliberation`, `Adjunction`, `Blanket`, `Invariants`, `Types`).
- **canonical-flag-off** — landed, fully tested, but gated by a feature flag defaulted to `False` (e.g. `Essence`, family divergence in `routeFamily`, `Perspective.Operator` per AGENTS.md P4).

`Self/*` modules are never supplier, derived, observer, or legacy.
This is consistent with AGENTS.md's "pure self-layer of the dual-mode
runtime" framing.

### 2.2 Core-layer splits into supplier, canonical-orchestrator, and observer

`Core/*` modules fall into three classes:

- **canonical-orchestrator** — drives the turn pipeline, owns
  `SystemState` writes through the orchestrator API. Examples:
  `Core.TurnPipeline.*`, `Core.Guard.*`, `Core.Legitimacy.*`,
  `Core.TurnModulation.*`, `Core.Ego.*`, `Core.Observability.*`.
- **supplier** — produces inputs the orchestrator consumes.
  Examples: `Core.Consciousness.*` (narrative content),
  `Core.MeaningGraph`, `Core.Atom*`, `Core.Proposition*`,
  `Core.IdentitySignal*`, `Core.FamilyAdmission*`, `Core.R5Dynamics`,
  `Core.Spectral*`, `Core.TopicTransition*`.
- **observer** — emits into trace only, no kernel writes. Examples:
  `Core.DreamDynamics`.

The role split is enforced by §3 below.

### 2.3 Conatus stays in Self/ as a canonical signal source

Per Package 1, the Conatus functional remains in `Self.Conatus` and
is **canonical**, not "demoted". Its `computeConatusEnergy` /
`computeConatusGradient` outputs feed the hard `ConatusGate` in
`Core/TurnPipeline/Route/Render.buildLocalRecoveryPlan`. The gate
has the dedicated `RecoveryConatusGate` cause (ADR-0010 addendum
2026-05-17) and is the highest-priority recovery driver.

This means `Self.Conatus` is the single most authority-bearing module
in the runtime. It is also pure. There is no architectural reason to
move it to `Core/*`, and doing so would create churn for no benefit.

### 2.4 Self.Perspective dual structure preserved

Per AGENTS.md P4, `Self.Perspective.hs` carries the `PerspectiveRegistry`
(canonical versioned lineage) and the `PerspectiveOperator` (mutation
logic). Replay/render must consume only `PerspectiveProjection`
(derived from the registry). The current `Self/Perspective.hs` already
separates these; this ADR requires the split to be visible in the
module Haddock.

## 3. Boundary rules (enforceable by `check_architecture.sh`)

The following rules become hard CI gates. They extend the freeze-0
rules in `AUTHORITY_BOUNDARY.md §4`.

1. **Self/* is canonical-only.** A new `Self/*` module must declare
   `canonical` or `canonical-flag-off` in its module Haddock. CI
   rejects `Self/*` modules that import `Core.TurnPipeline.*` or
   `Bridge.*` (no downward writes from the self-layer to the
   orchestrator).
2. **Core/* supplier modules must not import canonical-orchestrator
   writers.** A supplier module cannot import `Core.TurnPipeline.Effects`,
   `Core.TurnPipeline.Finalize.*`, or any module that writes to
   `SystemState` directly. Suppliers read `ss*` fields but only
   through read-only accessors.
3. **Core/* observer modules emit into trace only.** A module that
   imports `QxFx0.Core.Observability` is observer; it must not
   return any value that mutates `ss*` or `tp*`.
4. **Render/* is the only outbound text producer.** A new module
   under `Render/*` that produces text must route through
   `Route/Render.buildTurnArtifacts`. CI rejects Render modules
   that bypass this orchestrator.
5. **Bridge.ExternalLLM is the only authority-bearing supplier that
   is opt-in by feature flag.** Any future `Bridge.*` supplier that
   wants flag-on opt-in must follow the same pattern: feature
   flag, replay-trace discipline, and a closure-plan acceptance
   criterion in `docs/closure/`.
6. **canonical-flag-off modules are not in the authority path** until
   the flag is flipped. They have their own test suite
   (`Test.Suite.SelfEssence`, `Test.Suite.SelfEssenceCommit`,
   `Test.Suite.SelfPerspective`) but those tests are not part of
   the canonical regression lock until the flag is flipped.
7. **derived modules must remain regenerable.** A change to
   `Lexicon.Generated.hs` or any other derived module must come
   with a regeneration step (`scripts/build_lexicon.sh` or
   equivalent) that is part of CI.

## 4. Per-module map

The full per-module table is in `docs/closure/AUTHORITY_MAP.md §3–5`.
Highlights:

### 4.1 Canonical Self/* modules

`Adjunction`, `Blanket`, `Conatus`, `Deliberation`, `Field`,
`Invariants`, `Salience`, `Types`.

### 4.2 Canonical-flag-off Self/* modules

`Essence` (ADR-0012), `Perspective` (per AGENTS.md P4), the
`familyDivergenceEnabled` flag in `routeFamily` (ADR-0011 §5.3).

### 4.3 Canonical Core/* orchestrator modules

`TurnPipeline.*`, `Guard.*`, `Legitimacy.*`, `TurnModulation.*`,
`Ego.*`, `Observability.*`, `IdentityGuard`, `IdentitySignal`,
`SessionLock`, `PrincipledCore`, `R5Dynamics`.

### 4.4 Supplier Core/* modules

`Consciousness.*` (narrative content), `MeaningGraph`, `Atom*`,
`Proposition*`, `FamilyAdmission*`, `EarlyFamilyAdmission`,
`InterpretationAdmission`, `LexicalCluster*`, `SensePlan`,
`SenseVectorAdmission`, `SemanticContributionAdmission`,
`SemanticFrameAdmission`, `SemanticLogicAdmission`, `StructuralAtomAdmission`,
`RouteHintAdmission`, `DialogueThread`, `Spectral`, `TopicTransition`,
`PipelineIO`, `Bayesian`, `Intuition`.

### 4.5 Observer Core/* modules

`DreamDynamics`.

## 5. Consequences

### 5.1 Positive

- The role split is auditable. A reviewer can read
  `docs/closure/AUTHORITY_MAP.md` and know exactly which modules
  drive the runtime and which are suppliers.
- New contributors cannot silently introduce a "second writer" to
  the kernel/semantic state. CI catches the import.
- The `canonical-flag-off` class is **explicit**, not implicit. The
  project does not need to claim that Essence / Family Divergence
  / Perspective.Operator are "core" — they are clearly
  flag-gated, with promotion ADRs pending.
- The Conatus story is closed. `Self.Conatus` is canonical, the
  `ConatusGate` is the highest-priority recovery driver, and
  `tiConatusEnergy` is the single source of truth (M6 discipline).

### 5.2 Costs

- `scripts/check_architecture.sh` needs to be extended with
  per-module import rules. Estimated: 1 PR with 5 new grep
  rules.
- A few `Core/*` modules may need to be split (e.g. `AtomContributionAdmission`
  reads `ss*` and may need to be reorganised as a supplier vs an
  orchestrator). The closure plan's Package 6 (test audit) is
  the place to surface these.
- The `canonical-flag-off` class requires a promotion-or-demotion
  decision for each flag-off feature within the closure plan.
  This is the work of `docs/closure/SELF_LAYER_STATUS.md`.

## 6. Alternatives considered

### 6.1 Merge Self/* and Core/* into a single canonical layer

Rejected. The Self-layer's purity (no IO, no `Core.*` imports) is
the project's strongest invariant (AGENTS.md "local-first and
deterministic", ADRs 0007-0012 all use this discipline). Merging
would couple the algebraic self-layer to the IO orchestrator and
regress ADR-0007 §6 "calibration is an open problem" into
"calibration is impossible".

### 6.2 Demote Self.Conatus to a policy layer in Core/*

Rejected. Conatus is the precondition for the entire dual-mode
runtime (ADR-0007 §6, ADR-0010 §2.2, ADR-0011 §3, ADR-0012 §5.2).
Demoting it would break the `ConatusGate` semantics. The current
placement in `Self/*` is correct: pure module, hard-gate consumer
in `Core/*`.

### 6.3 Promote all canonical-flag-off modules to canonical immediately

Rejected. The flag-off features are landed but not validated
against production traces (ADR-0012 §15.2 angst calibration
deferred, `familyDivergenceEnabled` adjusted to `False` in
Package D). Promotion requires a corpus-replay pass with
defined success criteria (see `SELF_LAYER_STATUS.md`).

## 7. Acceptance criteria

ADR-0034 is closed when:

1. `docs/closure/AUTHORITY_MAP.md` is merged.
2. `docs/closure/SELF_LAYER_STATUS.md` is merged.
3. `scripts/check_architecture.sh` is extended with the seven
   boundary rules of §3.
4. CI runs the extended `check_architecture.sh` and reports
   `0 violations` against the current source tree.
5. Every `Self/*` and `Core/*` module's Haddock header declares
   its role (canonical / canonical-flag-off / supplier /
   observer / derived / legacy). A one-pass sweep is sufficient;
   no semantic changes are required.

## 8. Honest limits

- This ADR classifies modules; it does not fix behavioural issues
  in the supplier modules. The closure plan's Package 2
  (`SEMANTIC_CORE_MIN_SLICE.md`) and Package 7
  (`COGNITIVE_MEMORY_DESIGN.md`) are where supplier-side
  behavioural changes happen.
- The `canonical-flag-off` class is administrative. It does not
  change runtime behaviour. The runtime still does not run Essence
  / Family Divergence / Perspective.Operator; the class just makes
  that explicit.
- The boundary rules §3 are import-level heuristics. They will
  produce false positives (a supplier that legitimately imports a
  utility from `Core.TurnPipeline.Protocol` types but not from its
  writer API) and false negatives (a supplier that smuggles a
  write through a `Lens` or `State` monad). The first round of
  CI enforcement will produce a triage list of exceptions; the
  closure plan's Package 6 (test audit) processes the triage.

## 9. Addendum (post-closure)

TBD. To be filled after the seven boundary rules of §3 land in
`check_architecture.sh` and a triage pass resolves false positives.
