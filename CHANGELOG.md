# Changelog

All notable changes are documented in this file.

## [Unreleased]

### Added

- Phase 2.5 (M2d) — runtime Conatus integrated into the recovery
  decision as a primary, priority-overriding driver:
  - `psConatusEnergy :: !ConatusEnergy` and
    `psBlanketViolationCount :: !Int` carried by
    `PrepareStatic` (single source of truth per turn).
  - `tiConatusEnergy` / `tiBlanketViolationCount` / `tiField`
    threaded through `TurnInput` for downstream read-only
    consumers.
  - `buildLocalRecoveryPlan` now reads the precomputed
    `ConatusEnergy` from `TurnInput` and fires the
    `conatusGateFires` guard before all other guards
    (shadow / parser / legitimacy / runtime-mode).
- New `LocalRecoveryCause` variant `RecoveryConatusGate`
  with snake_case JSON tag `"conatus_gate"`. Distinct from
  `RecoveryRuntimeDegraded` (which keeps its environmental
  meaning).
- Phase 5.5e — Salience controller verdict emitted in
  `TurnReplayTrace` for audit observability:
  - `trcSalienceDriver :: !Text` (snake_case tag from
    `renderSalienceDriver`).
  - `trcSalienceHolisticBias :: !Double` in `[0, 1]`.
  - `trcSalienceConfidence :: !Double` in `[0, 1]`.
- Phase 5.5d — canonical pre-turn `Field` (`psField`) with
  four runtime-sourced components:
  - `fieldResonance` from atom-trace current load.
  - `fieldConsolidation` from topic-stability heuristic
    (0.8 when same focused topic as previous turn,
    0.2 otherwise).
  - `fieldCounterfactual` from semantic-logic candidate-
    family ambiguity (`w2 / w1` ratio of top two weights).
  - `fieldAtmosphere` from Ego differential
    (`valence = agency - tension`, `arousal = tension`).
  - `fieldConfidence` stays at 1.0 (the `emptyField`
    default, per ADR-0009 §4.4).
- New `Self.Salience.renderSalienceDriver :: SalienceDriver -> Text`
  for stable snake_case `SalienceDriver` tag rendering
  used in `trcSalienceDriver` and JSON trace payloads.
- New test suite `Test.Suite.PhaseM2d` (8 unit tests)
  covering `renderSalienceDriver` exhaustive coverage,
  `RecoveryConatusGate` text + JSON rendering, the
  `psConatusEnergy` invariant in `buildPrepareEffectPlan`,
  and the M2d plumbing through `PrepareReqConsciousness` /
  `PrepareReqIntuition`. Wired into all five test-suite
  variants (fast / unit / property / integration / slow /
  full).
- New pipeline-level integration test
  `testConatusGateFiresRecoveryConatusGate` in
  `Test.Suite.TurnPipelineProtocol` verifying that the
  `RecoveryConatusGate` cause is emitted by
  `planRenderEffectsForRuntime` when the Conatus gate
  fires, with `StrategySafeRecovery` and the canonical
  evidence lines.

### Changed

- Phase 6 — single-source-of-truth Conatus refactor:
  eliminated three duplicate `computeSelfBlanket` +
  `checkInitialBlanket` + `computeConatusEnergy` triples
  in `TurnRouting.routeFamily`,
  `Route/Render.buildLocalRecoveryPlan`, and
  `Effects.buildPrepareEffectPlan` (only the Prepare-stage
  computation remains; downstream consumers read from
  `TurnInput`).
- `routeFamily` signature gains two trailing parameters:
  `ConatusEnergy` and `Field`, supplied by the caller
  from `tiConatusEnergy ti` and `tiField ti`.
- Routing salience inside `routeFamily` now consumes the
  real pre-turn `Field` instead of `emptyField`, so
  Resonance / Consolidation / Counterfactual / Atmosphere
  contribute to the Salience controller's verdict (per
  SelfSalience monotonicity properties).
- `Self.Salience.chooseBranch` documented as dead API
  with explicit doc-status note (no current consumer
  outside tests; left in place for ADR-0010 §6 contract
  compliance).

### Fixed

- Recovery-trace tag overload: previously the Conatus
  gate path emitted `RecoveryRuntimeDegraded`, conflating
  structural-Conatus events with environmental
  runtime-degraded events. Now correctly distinguished
  via the dedicated `RecoveryConatusGate` cause.
- Two `TurnReplayTrace` fixture record literals in
  `Test.Suite.RuntimeInfrastructure` extended with the
  three new Salience trace fields, matching the new
  `TurnReplayTrace` constructor.

## [Pre-2026-05-17 Unreleased]

### Added

- Repository governance baseline:
  - `CONTRIBUTING.md`
  - `CODE_OF_CONDUCT.md`
  - `SECURITY.md`
  - `GOVERNANCE.md`
  - `ROADMAP.md`
  - `THIRD_PARTY_NOTICES.md`
  - `requirements.txt`

### Changed

- CI workflow cleanup:
  - removed dev-only push trigger branch
  - removed redundant legacy `build-test` job

### Fixed

- Removed binary script artifacts from repository working tree:
  - `scripts/fuzz_harness.hi`
  - `scripts/fuzz_harness.o`
- Removed deprecated `warnMorphFallback` path from
  `Semantic/Syntax/Combinators`.
- Removed test-only `testRuntimeParadigms` global from public runtime paradigms
  surface.
