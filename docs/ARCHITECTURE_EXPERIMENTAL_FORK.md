# QxFx0_v3 Experimental Architecture Overview

This document summarizes the architecture of `QxFx0_v3` as a working experimental fork.
It is not a replacement for `docs/ARCHITECTURE.md`; it is the shorter fork-oriented map for deciding where to experiment safely.

## 1. System Shape

`QxFx0_v3` is a layered Haskell dialogue runtime with a deterministic turn pipeline, typed routing, grammar-constrained rendering, persistent session state, and strong verification surfaces.

The fork currently preserves the baseline package and module layout:

- executable entrypoints in `app/`
- runtime composition in `src/QxFx0/Runtime/`
- turn pipeline and decision logic in `src/QxFx0/Core/`
- self-model and salience logic in `src/QxFx0/Self/`
- external and persistence boundaries in `src/QxFx0/Bridge/`
- meaning construction in `src/QxFx0/Semantic/`
- rendering in `src/QxFx0/Render/`
- lexicon and policy surfaces in `src/QxFx0/Lexicon/` and `src/QxFx0/Policy/`
- pure state and protocol types in `src/QxFx0/Types/`

## 2. Runtime Entry Surface

Primary executable:

- `app/Main.hs` delegates to `app/CLI.hs`

The CLI supports several operational modes:

- interactive dialogue session
- one-shot JSON turn execution
- runtime health and readiness checks
- HTTP sidecar mode
- worker-stdio mode
- database initialization and Agda witness output

This makes `app/CLI.hs` a useful top-level integration map when tracing behavior end-to-end.

## 3. Main Architectural Subsystems

### 3.1 Core turn pipeline

The system's central execution path lives in `src/QxFx0/Core/TurnPipeline/*` and is organized around four sequential phases:

1. `Prepare`
2. `Route`
3. `Render`
4. `Finalize`

This is the highest-value subsystem for experiments that affect externally visible dialogue behavior.

Relevant areas:

- `Core.TurnPipeline.Prepare.*`
- `Core.TurnPipeline.Route.*`
- `Core.TurnPipeline.Finalize.*`
- `Core.TurnRouting.*`
- `Core.TurnRender.*`
- `Core.TurnPlanning.*`

### 3.2 Self layer

The `Self` subtree contains the pure internal model that shapes higher-level runtime behavior:

- `Self.Blanket`
- `Self.Conatus`
- `Self.Field`
- `Self.Salience`
- `Self.Adjunction`
- `Self.Deliberation`
- `Self.Essence`
- `Self.Perspective`

This is the most natural zone for experimental work on mode selection, self-preservation logic, structural risk handling, and alternative deliberation behavior.

### 3.3 Semantic layer

The semantic subsystem converts raw input into typed meaning structures and planning signals.

Key areas:

- `Semantic.Input.*`
- `Semantic.Logic`
- `Semantic.Meaning*`
- `Semantic.Dialog*`
- `Semantic.Sense*`
- `Semantic.Embedding*`

This area is appropriate for experiments in parsing strategy, decomposition granularity, sense continuation, and input normalization.

### 3.4 Render layer

The render subsystem turns routed/planned meaning into user-visible output.

Key modules:

- `Render.Dialogue`
- `Render.Semantic`
- `Render.Text`
- `Core.TurnRender.*`

This zone is suitable for experiments in tone, structure, fallback presentation, and the coupling between planning and output surface realization.

### 3.5 Bridge and persistence layer

The bridge layer owns stable boundaries and side effects:

- SQLite access and schema contracts
- datalog shadow checks
- morphology bridge utilities
- Agda witness integration
- external LLM adapter surface
- governed state persistence

Key directories:

- `src/QxFx0/Bridge/`
- `migrations/`
- `spec/sql/`

This layer should usually be changed conservatively, because many tests, scripts, and contracts assume its current behavior.

### 3.6 Lexicon, policy, and resources

These subsystems provide the vocabulary, thresholds, scoring rules, and resource loading that support the runtime.

Key directories:

- `src/QxFx0/Lexicon/`
- `src/QxFx0/Policy/`
- `src/QxFx0/Resources/`
- `resources/`
- `spec/gf/`
- `spec/sql/lexicon/`

These are strong candidates for controlled experiments that need to preserve code structure while changing runtime behavior through data and policy.

## 4. What Is Stable vs Experimental

Recommended control surfaces to keep stable initially:

- package and module names
- schema and migration contracts
- generated artifact flow
- CLI entrypoints and test suite structure
- trace and observability fields relied on by scripts

Recommended zones for early experimentation:

- `Self/*`
- `Core/TurnRouting/*`
- `Core/TurnPlanning/*`
- `Semantic/Sense/*`
- `Render/*`

Higher-risk zones that affect many contracts at once:

- `Bridge/EmbeddedSQL.hs`
- `Bridge/SQLite*`
- persistence/state types under `Types/State*`
- lexicon generation chain and GF artifacts
- scripts that define release gates

## 5. Verification Surfaces

The fork inherits the baseline verification contour:

- build and test via `cabal`
- architecture invariants via `scripts/check_architecture.sh`
- GF and generated artifact checks via `scripts/check_generated_artifacts.sh` and `scripts/check_lexicon.sh`
- Python validation scripts in `test/` and `scripts/`

Because `QxFx0_v3` is meant for alternative development, experiments should ideally state which of these verification surfaces are expected to remain green and which are intentionally being challenged.

## 6. Practical Fork Strategy

Use this fork as a controlled lab:

1. choose one subsystem
2. document the intended divergence
3. implement the smallest viable change
4. compare behavior against `../QxFx0`
5. keep or revert the experiment based on observable evidence

## 7. Reference Documents

- Baseline architecture: `docs/ARCHITECTURE.md`
- Baseline theory: `docs/THEORY.md`
- Fork roadmap: `ROADMAP.md`
- Build definition: `qxfx0.cabal`
- CLI integration surface: `app/CLI.hs`
