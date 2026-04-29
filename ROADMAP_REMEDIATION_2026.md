# QxFx0 Remediation Roadmap 2026-04

## Goal

Close the remaining architectural debt identified by the audits without destabilizing the runtime:

1. make Datalog shadow real and executable end-to-end
2. remove misleading formal-proof signals from Agda artifacts
3. centralize thresholds, depth mode, and clamp helpers
4. reduce SQL surface to what runtime actually persists and queries
5. add unit tests around pure core logic that currently has no direct regression fence

## Delivery Strategy

The work is sequenced so that each phase leaves the repo in a releasable state.

### Phase 0: Reality Gates

Purpose:
- stop relying on fake or misleading guarantees

Tasks:
- replace the current Datalog placeholder path with a real Souffle pipeline that:
  - loads the canonical rules from `spec/datalog/semantic_rules.dl`
  - injects runtime facts for the current turn
  - runs Souffle in an isolated temp directory
  - parses `R5Verdict` output and propagates diagnostics
- remove unused `postulate contradiction` from `spec/R5Core.agda`
- explicitly label `spec/Sovereignty.agda` as a specification sketch rather than a completed proof

Acceptance:
- `runDatalogShadow` returns a real `srDatalogVerdict`
- no Souffle output lands in the current working directory
- Agda files still type-check under `QXFX0_REQUIRE_AGDA=1`

### Phase 1: Shared Decision Primitives

Purpose:
- remove duplicated semantics from routing/rendering/legitimacy code

Tasks:
- add shared `DepthMode`
- add shared `clamp01`
- add a shared thresholds module for the most reused routing / legitimacy / intuition cutoffs
- migrate the main call sites:
  - `TurnPlanning`
  - `TurnRender`
  - `TurnModulation`
  - `Legitimacy`
  - `Intuition`
  - `R5Dynamics`
  - `BackgroundProcess`

Acceptance:
- `rmpDepthMode` is typed, not raw `Text`
- local `clamp01` duplicates are removed
- critical thresholds are named and imported from one place

### Phase 2: SQL Surface Cleanup

Purpose:
- make the schema match real runtime behavior

Tasks:
- remove dead tables and indexes from:
  - `spec/sql/schema.sql`
  - `migrations/001_initial_schema.sql`
- regenerate `src/QxFx0/Bridge/EmbeddedSQL.hs`
- keep `schema_version` because migrations still use it

Acceptance:
- fresh bootstrap uses only live tables
- `EmbeddedSQL.hs` stays in sync with `spec/sql`
- spec SQL seed compatibility tests still pass

### Phase 3: Unit-Test Fence Expansion

Purpose:
- protect pure logic that currently only fails indirectly through end-to-end smoke

Tasks:
- add deterministic unit tests for:
  - `Core.DreamDynamics`
  - `Core.Intuition`
  - `Core.Consciousness`
  - selected `Core.BackgroundProcess` and `Core.Legitimacy` edges
- add tests for Datalog shadow execution and diagnostics

Acceptance:
- new tests exercise pure logic directly
- `cabal test qxfx0-test` passes
- strict `release-smoke.sh` remains green

## Execution Notes

- Prefer honest contracts over aspirational abstractions.
- If a component is still a sketch, document it as a sketch.
- If a gate is optional at runtime, diagnostics must still tell the truth.
- Do not keep dead schema or fake shadow checks for narrative symmetry.
