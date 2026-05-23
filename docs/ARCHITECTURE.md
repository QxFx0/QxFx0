# QxFx0 — Architecture

> **Status**: Living document. Reflects the current code reality (May 2026)
> and the modernization path established in `docs/adr/0007-dual-mode-conatus.md`.
> The theoretical underpinning is in `docs/THEORY.md`.

This document describes the QxFx0 runtime architecture: its layered structure,
inter-layer dependency rules, and the landed dual-mode/adaptive contours. It is the
map a new contributor should read **first**, after `README.md`.

## 1. Layered architecture

QxFx0 is organized into eight horizontal layers. Dependencies flow **downward
only**, with one exception (`Runtime.GF.Morphology` is accessible from upper
layers as a pure utility). Cross-layer rules are mechanically enforced by
`scripts/check_architecture.sh` (twelve numbered invariants, including the
Holistic/Formal adjunction access rule).

```
┌────────────────────────────────────────────────────────────────┐
│  App / CLI                                                     │  app/CLI/*
├────────────────────────────────────────────────────────────────┤
│  Runtime           composition, sessions, gates, health        │  src/QxFx0/Runtime/*
├────────────────────────────────────────────────────────────────┤
│  Core              consciousness loop, turn pipeline, guard    │  src/QxFx0/Core/*
├────────────────────────────────────────────────────────────────┤
│  Self              SelfBlanket, Conatus, Adjunction, Field     │  src/QxFx0/Self/*
├────────────────────────────────────────────────────────────────┤
│  Bridge            SQLite, Datalog, Agda witnesses, persist.   │  src/QxFx0/Bridge/*
├────────────────────────────────────────────────────────────────┤
│  Semantic + Render parsing, meaning, GF surface generation     │  src/QxFx0/Semantic/*, /Render/*
├────────────────────────────────────────────────────────────────┤
│  Lexicon + Policy  vocabulary, paradigms, scoring policies     │  src/QxFx0/Lexicon/*, /Policy/*
├────────────────────────────────────────────────────────────────┤
│  Types + ExceptionPolicy + Resources                           │  src/QxFx0/Types/*, /ExceptionPolicy.hs
└────────────────────────────────────────────────────────────────┘
```

### 1.1 Layer responsibilities (one-liners)

- **Types** — data definitions only; no IO, no policy, no decisions. The sink
  of the dependency graph: every layer imports Types, Types imports none of
  them. (Rule [1].)
- **ExceptionPolicy / Resources** — typed exceptions and resource readiness;
  the only sanctioned cross-layer error surface.
- **Lexicon + Policy** — vocabulary (paradigms, surface forms) and pure
  policies (scoring, thresholds). No IO.
- **Semantic + Render** — input → meaning, meaning → surface. Must not import
  Bridge / Core / Runtime (Rules [2], [2b]). Exception: pure morphology
  utility `Runtime.GF.Morphology` is allowed as a leaf utility.
- **Bridge** — persistent and external boundaries: SQLite pool, Datalog
  shadow, Agda witnesses. Must not import Core (Rule [4]).
- **Self** — types and pure functions that describe *what makes this system
  this system*. Importable by Core, Bridge, Runtime. Imports only lightweight
  dependencies by design. Landed modules include `Self.Blanket`,
  `Self.Conatus`, `Self.Adjunction`, `Self.Field`, `Self.Salience`,
  `Self.Deliberation`, and `Self.Essence`.
- **Core** — consciousness loop, turn pipeline (Prepare → Route → Render →
  Finalize), guard/recovery, identity. Must not import Bridge or Runtime
  (Rule [4]); reaches IO only via `PipelineIO` abstraction.
- **Runtime** — composes Bridge + Core into a running session; hosts gates,
  health, paths, wiring, session lock. Must not import the top-level
  `QxFx0.Core` aggregator (Rule [4b]); imports focused Core submodules.
- **App / CLI** — entry points (interactive CLI, HTTP sidecar).

### 1.2 Test layer

Tests live under `test/Test/Suite/*` and are split into six cabal
test-suites for CI-budget reasons:

| Suite                    | Purpose                                       |
|--------------------------|-----------------------------------------------|
| `qxfx0-test-fast`        | Sub-30s sanity gate, included in every PR     |
| `qxfx0-test-unit`        | Unit + property tests, no SQLite required     |
| `qxfx0-test-property`    | QuickCheck-only properties                    |
| `qxfx0-test-integration` | SQLite + GF + cross-layer integration         |
| `qxfx0-test-slow`        | Stress, paradigm coverage, long-running       |
| `qxfx0-test`             | Full battery (incl. HTTP, runtime infra)      |

Lifeness, structural calibration, and adaptive-contour properties are integrated
into the existing suites rather than split into a separate cabal suite.

## 2. Dependency invariants (enforced)

The following are checked by `scripts/check_architecture.sh` on every CI run
and are required for `PROD_GO` verdict.

| ID    | Rule                                                                     |
|-------|--------------------------------------------------------------------------|
| [1]   | Types modules must not import Core/Bridge/Semantic                       |
| [2]   | Semantic modules must not import Bridge/Core/Runtime (except `Runtime.GF.Morphology`) |
| [2b]  | Render modules must not import Core/Bridge/Runtime (same exception)      |
| [3]   | Bridge modules must not hardcode spec paths (use Resources.Paths)        |
| [4]   | Bridge → Core forbidden; Core → Bridge/Runtime forbidden                 |
| [4b]  | Runtime modules must not import top-level `QxFx0.Core` aggregator         |
| [5]   | No `SomeException` in Bridge/Semantic/Core/Resources/app source          |
| [6]   | No partial `read` in source (use `readMaybe` / `parseTimeM`)             |
| [7]   | No bare `head`/`tail`/`init`/`last` in source                            |
| [8]   | No bare `fail` in IO context (use `throwQxFx0`)                          |
| [8b]  | No raw `userError` (use `throwQxFx0`)                                    |
| [9]   | Runtime code imports operational templates from Policy, not Lexicon      |
| [10]  | `EmbeddedSQL.hs` stays in sync with `spec/sql/`                          |
| [10b] | HTTP perimeter invariants remain closed (loopback, auth, sanitization)   |
| [10c] | Acceptance gates and docs reflect local-recovery architecture            |
| [11]  | Exposed Core modules reachable from Runtime/TurnPipeline                 |
| [12]  | Pipeline call sites access `Holistic` / `Formal` only through `QxFx0.Self.Adjunction` |

## 3. Turn pipeline

A single conversational turn flows through four sequential phases, each
implemented as a focused module under `Core/TurnPipeline/*`:

```
input ──▶ Prepare ──▶ Route ──▶ Render ──▶ Finalize ──▶ output
            │           │         │           │
            │           │         │           ├─ Precommit  (canonical move family resolution)
            │           │         │           ├─ Commit     (persist state + projections)
            │           │         │           ├─ Dream      (off-line consolidation, edge rewire)
            │           │         │           └─ State      (post-commit metrics)
            │           │         │
            │           │         ├─ Strategy / Anchor / Prefix / Cache
            │           │
            │           ├─ Phase  (parser → meaning-graph hint → pressure → intuition flash)
            │           ├─ Cascade (guard, identity, threshold)
            │           └─ Render hint
            │
            ├─ Resolve (semantic input → SemanticInput)
            └─ Build   (turn signals: consciousness, intuition, narrative)
```

The pipeline is **deterministic** at the protocol level: identical input
plus identical persisted state yields identical decisions. Non-determinism
is confined to time, UUID generation, and process scheduling (acknowledged
in `docs/runtime_invariants.md`).

## 4. Recovery architecture (local-first)

QxFx0 recovers from operational faults **locally**, without LLM I/O or
external fallback. The recovery trace is a typed record consisting of:

- `trcLocalRecoveryPolicy` — which policy was selected
- `trcRecoveryCause` — what triggered the recovery
- `trcRecoveryStrategy` — what action was taken
- `trcRecoveryEvidence` — the artifact justifying the choice

This contract is enforced by rule [10c] (`check_architecture.sh`) and
appears in both `scripts/verify.sh` and `scripts/release-smoke.sh`.

In the post-Phase-2 architecture, **recovery action selection is driven by
conatus gradient** rather than by rule-based dispatch. The rule-based
cascade remains as a fallback ordering when multiple actions yield
comparable conatus deltas.

## 5. Dual-mode (`Holistic ⊣ Formal`)

> **Status (2026-05-22)**: the algebra, right-hemispheric `Field`, salience
> controller, deliberation framework, essence commitment guard, and
> observability wiring have landed. The default runtime remains conservative;
> P4 perspective cognition is implemented as a governed `PerspectiveOperator`
> over existing state, with canonical lineage in `PerspectiveRegistry` rather
> than an ungoverned raw store.

The modernization roadmap (`docs/adr/0007-dual-mode-conatus.md`,
ADR-0008, ADR-0009) introduces a formal split of the processing surface
into two adjoint modes:

```
                    ┌────────────────────────┐
                    │  Salience Controller   │  src/QxFx0/Self/Salience.hs
                    │  (mode arbitration)    │
                    └───────┬────────┬───────┘
                            │        │
                  ┌─────────▼───┐  ┌─▼────────────┐
                  │ Formal mode │  │Holistic mode │
                  │  formal,    │  │  holistic,   │
                  │  narrow,    │  │  resonant,   │
                  │  spec-based │  │  field-based │
                  └─────────┬───┘  └─┬────────────┘
                            │        │
                    ┌───────▼────────▼───────┐
                    │  Adjunction (unit /    │  src/QxFx0/Self/Adjunction.hs
                    │  counit / triangle)    │
                    └───────────┬────────────┘
                                │
                    ┌───────────▼────────────┐
                    │  Self layer            │  src/QxFx0/Self/*
                    │  (SelfBlanket,         │
                    │   Conatus functional)  │
                    └────────────────────────┘
```

- **Formal mode** (right adjoint, left-hemispheric) inherits the majority
  of current pipeline modules (`Semantic.*`, `Core.TurnPipeline.*`,
  `Render.*`, `Lexicon.*`, etc.). Pipeline call sites access the dual-mode
  surface through `QxFx0.Self.Adjunction`.
- **Holistic mode** (left adjoint, right-hemispheric) is shipped
  algebraically. The right-hemispheric observation summary is the
  five-component `Field` record in `QxFx0.Self.Field`:
  `Resonance` (peak echo of the current turn against its recent
  context), `Atmosphere` (two-dimensional valence–arousal affect),
  `FieldConfidence` (derived internal-coherence score),
  `Consolidation` (narrative-integration scalar over a window),
  `Counterfactual` (diversity of plausible alternative parses). Source
  wiring is present in the prepare/trace path.
- **Salience controller** (Phase 5, landed) decides which mode leads per turn,
  based on ambiguity / novelty / formal-failure / time-pressure signals
  reflected through `Field`. Trace fields expose the dispatch reason.
- **Adjunction** typing (Phase 3, ADR-0008, **shipped**) makes the
  relationship between the modes formal:
  `unit  : a → Formal (Holistic a)`,
  `counit : Holistic (Formal a) → a`,
  with both triangle identities and the hom-set isomorphism
  (`leftAdjunct` / `rightAdjunct`) verified as QuickCheck properties
  in `Test.Suite.SelfAdjunction`.

## 6. Module structure (current)

Top-level src/QxFx0/ directories:

```
src/QxFx0/
├── Bridge/            SQLite, NativeSQLite, Datalog, Agda witnesses, persistence
├── CLI/               Parser
├── Core/              consciousness, turn pipeline, guard, identity, intuition, …
├── Internal/          FilePath utilities
├── Legal/             narrow legal-fact adapter (bounded stub)
├── Learning/          knowledge tree, external-loop gates, calibration, dialogue development
├── Evaluation/        model comparison and offline evaluation helpers
├── Lexicon/           paradigms, surface forms, generated entries (canonical sync from spec/sql/)
├── Policy/            scoring, thresholds, contracts
├── Render/            Dialogue, Semantic, Text
├── Resources/         data file paths, readiness assessment, morphology loading
├── Runtime/           sessions, gates, health, wiring, GF/PGF, paths
├── Self/              SelfBlanket, Conatus, Adjunction, Field, Salience, Deliberation, Essence, Perspective
├── Semantic/          parsing, meaning atoms/assembly/decomposition, embeddings
└── Types/             pure data definitions (decision, domain, state, thresholds, …)
```

For module count and dependency fan-in/out, see the audit findings in
`reports/audit/2026-05-17-architecture.md` (TBD; current canonical: 250
internal modules, Types as graph sink with fan-in 79).

## 7. Build and release contour

- Library: `lib:qxfx0` — single library exposing the runtime modules.
- Executable: `qxfx0-main` — interactive CLI, one-shot mode, and HTTP sidecar via `--serve-http`.
- Test suites: six (see §1.2); lifeness/adaptive properties live inside them.
- Release gates: two-tier contract via `scripts/ci_gate_contract.sh`:
  - **Core profile** (16 GB runner): build, tests, architecture, GF quality,
    artifacts, lexicon, degraded-local smoke. Required for `PROD_GO`.
  - **Extended profile** (≥32 GB runner): full scientific and learning contour
    including spectral/Bayesian/game-theory modules, training cycle, and model
    comparison helpers.
- Reproducibility: `flake.nix`, `cabal.project.freeze`, GHC 9.6.6 pinned.
- Documentation source-of-truth: `docs/CI_PRODUCTION_PROFILE.md`,
  `docs/release_readiness.md`, `docs/runtime_invariants.md`.

## 8. Pointers

| For …                                | Read …                                            |
|--------------------------------------|---------------------------------------------------|
| Why this project exists              | `README.md` §"Why This Project Exists"            |
| Theoretical commitments              | `docs/THEORY.md`                                  |
| Modernization rationale              | `docs/adr/0007-dual-mode-conatus.md`              |
| CI profiles & gate contract          | `docs/CI_PRODUCTION_PROFILE.md`                   |
| Release Go/No-Go policy              | `docs/release_readiness.md`                       |
| Runtime invariants & recovery trace  | `docs/runtime_invariants.md`                      |
| HTTP perimeter contract              | `app/CLI/Http.hs`, `scripts/http_runtime.py`      |
| Schema sync contract                 | `docs/schema_contract_playbook.md`                |
