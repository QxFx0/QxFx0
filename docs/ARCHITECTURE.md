# QxFx0 — Architecture

> **Status**: Living document. Reflects the current code reality (May 2026)
> and the modernization path established in `docs/adr/0007-dual-mode-conatus.md`.
> The theoretical underpinning is in `docs/THEORY.md`.

This document describes the QxFx0 runtime architecture: its layered structure,
inter-layer dependency rules, and the planned dual-mode extension. It is the
map a new contributor should read **first**, after `README.md`.

## 1. Layered architecture

QxFx0 is organized into eight horizontal layers. Dependencies flow **downward
only**, with one exception (`Runtime.GF.Morphology` is accessible from upper
layers as a pure utility). Cross-layer rules are mechanically enforced by
`scripts/check_architecture.sh` (eleven numbered rules; rule [12] reserved
for the future Left/Right adjunction split, see §5).

```
┌────────────────────────────────────────────────────────────────┐
│  App / CLI                                                     │  app/CLI/*
├────────────────────────────────────────────────────────────────┤
│  Runtime           composition, sessions, gates, health        │  src/QxFx0/Runtime/*
├────────────────────────────────────────────────────────────────┤
│  Core              consciousness loop, turn pipeline, guard    │  src/QxFx0/Core/*
├────────────────────────────────────────────────────────────────┤
│  Self (new)        SelfBlanket invariants, conatus functional  │  src/QxFx0/Self/*
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
- **Self** *(introduced by Phase 1 modernization)* — types and pure functions
  that describe *what makes this system this system*. Importable by Core,
  Bridge, Runtime. Imports only Types.
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

A seventh suite (`qxfx0-test-lifeness`) is planned in Phase 7 for adversarial
and indicator-property tests.

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

Future:

| ID    | Rule (planned)                                                           |
|-------|--------------------------------------------------------------------------|
| [12]  | `Left.*` and `Right.*` namespaces communicate only through `QxFx0.Adjunction` (Phase 3) |

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

## 5. Dual-mode (Left ⊣ Right) — planned

The modernization roadmap (`docs/adr/0007-dual-mode-conatus.md`) introduces
a formal split of the processing surface into two adjoint modes:

```
                    ┌────────────────────────┐
                    │  Salience Controller   │  src/QxFx0/Salience/*
                    │  (mode arbitration)    │
                    └───────┬────────┬───────┘
                            │        │
                  ┌─────────▼───┐  ┌─▼────────────┐
                  │  Left mode  │  │  Right mode  │
                  │  formal,    │  │  holistic,   │
                  │  narrow,    │  │  resonant,   │
                  │  spec-based │  │  field-based │
                  └─────────┬───┘  └─┬────────────┘
                            │        │
                    ┌───────▼────────▼───────┐
                    │  Adjunction (unit /    │  src/QxFx0/Adjunction.hs
                    │  counit / triangle)    │
                    └───────────┬────────────┘
                                │
                    ┌───────────▼────────────┐
                    │  Self layer            │  src/QxFx0/Self/*
                    │  (SelfBlanket,         │
                    │   Conatus functional)  │
                    └────────────────────────┘
```

- **Left mode** inherits the majority of current pipeline modules
  (`Semantic.Syntax.*`, `Core.TurnRender.*`, `Lexicon.Resolver`, etc.).
  These will be reorganized under `QxFx0.Left.*` via reexport shims so that
  existing call-sites continue to compile during the transition (Phase 3).
- **Right mode** is new (Phase 4). Five submodules:
  `Right.Resonance` (analogical lookup), `Right.Atmosphere` (latent mood),
  `Right.FieldConfidence` (distribution-based uncertainty),
  `Right.Consolidation` (off-line MeaningGraph rewire, extends Dream),
  `Right.Counterfactual` (replay-based "what-if").
- **Salience controller** (Phase 5) decides which mode leads per turn,
  based on ambiguity / novelty / formal-failure / time-pressure signals.
  Antikorrelyation is enforced: the non-leading mode listens but does not
  emit.
- **Adjunction** typing (Phase 3) makes the relationship between the modes
  formal: `unit : Id ⇒ Right ∘ Left`, `counit : Left ∘ Right ⇒ Id`, triangle
  identities checked by property tests.

## 6. Module structure (current)

Top-level src/QxFx0/ directories:

```
src/QxFx0/
├── Bridge/            SQLite, NativeSQLite, Datalog, Agda witnesses, persistence
├── CLI/               Parser
├── Core/              consciousness, turn pipeline, guard, identity, intuition, …
├── Internal/          FilePath utilities
├── Legal/             narrow legal-fact adapter (bounded stub)
├── Lexicon/           paradigms, surface forms, generated entries (canonical sync from spec/sql/)
├── Policy/            scoring, thresholds, contracts
├── Render/            Dialogue, Semantic, Text
├── Resources/         data file paths, readiness assessment, morphology loading
├── Runtime/           sessions, gates, health, wiring, GF/PGF, paths
├── Self/              [planned] SelfBlanket, Conatus, invariants
├── Semantic/          parsing, meaning atoms/assembly/decomposition, embeddings
└── Types/             pure data definitions (decision, domain, state, thresholds, …)
```

For module count and dependency fan-in/out, see the audit findings in
`reports/audit/2026-05-17-architecture.md` (TBD; current canonical: 250
internal modules, Types as graph sink with fan-in 79).

## 7. Build and release contour

- Library: `lib:qxfx0` — single library exposing ~100 modules.
- Executables: `qxfx0` (interactive CLI), `qxfx0-http` (HTTP sidecar).
- Test suites: six (see §1.2); seventh planned (Phase 7).
- Release gates: two-tier contract via `scripts/ci_gate_contract.sh`:
  - **Core profile** (16 GB runner): build, tests, architecture, GF quality,
    artifacts, lexicon, degraded-local smoke. Required for `PROD_GO`.
  - **Extended profile** (≥32 GB runner): full scientific contour including
    `Core.GameTheory`, `Core.Spectral`, `Core.Bayesian` (these are in
    `other-modules`, opt-in).
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
