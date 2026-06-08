# Changelog

All notable changes are documented in this file.

## [Unreleased] — Technical Debt Elimination — 2026-06-05

### Fixed

**P0 — Critical Safety Defects**
- **P0-1**: Replaced unsafe `error` calls with typed `StateInvariantViolation` exceptions in `buildNextSystemState` (2 locations)
- **P0-2**: Removed `unsafePerformIO` from pure function — moved `logTraceAnomalies` to IO boundary in `buildFinalizePrecommit`
- **P0-3**: Added `propositionTypeFromText` (`readMaybe`-based) typed dispatch at the render/diagnostic edge. NOTE: not compile-time typo safety (runtime `Nothing` on miss); behaviour-gating sites remain string compares

**Determinism — legitimacy-path apiHealthy (commits `a1dd66c`, `f0e229f`)**
- `legitimacyScore` consumed a live `apiHealthy` HTTP probe — the one ambient input breaking "same input+state → same output". Now recorded into `TurnReplayTrace` as `trcEffectSnapshot` and replayed via `mkReplayPipelineIO`, so determinism holds by construction. (`emaLoad` was already deterministic — pure EMA over state.)
- Proven by `Test.Suite.ReplayDeterminism` (replay reads trace not world; score reproduces recorded value; snapshot survives the DB-column `Aeson.encode`/decode).
- **Scope**: legitimacy path only, unit-proven. Production DB round-trip (load persisted trace → `FromJSON` → replay) is pending; global turn determinism not claimed.

**P1 — Dead Code Removal**
- **P1-2a**: Removed unused `fmarSelectFamilyRescue` function and its tests from `Self.FamilyTargets`
- **P1-2b**: Removed dead exports `renderTurnOutput` and `routeTurnPlan` from `TurnPipeline.Route`

**P3 — Code Quality**
- **P3-1**: Fixed orphan instance — moved `Hashable TurnSeq` to `Types.State.SemanticCommitment`
- **P3-2**: Added `{-# LANGUAGE DerivingStrategies #-}` and `deriving stock` to 5 files
- **P3-3**: Removed 7 unused imports from 6 files
- **P3-4**: Fixed 2 test failures for promoted flags (`episodicRecallActive`, `contentSalienceActive` now default-on)
- **P3-5**: Renamed `fieldDelta` to `maxFieldHeuristicsDelta` to resolve name collision

**P2 — Documentation & Consistency**
- **P2-1**: Synchronized AGENTS.md with code — updated 3 flag descriptions (family divergence split, promoted flags)
- **P2-2**: Resolved `familyDivergenceEnabled` name collision — split into `salienceGuardDivergenceEnabled` (Cascade.hs) and `reconcileFamilyDivergence` (TurnRouting.hs)

### Added

**P1-1 — Generic Admission (Core conversions complete)**
- Created `QxFx0.Core.GenericPropositionAdmission` (92 lines) + `PropositionAdmissionConfig`
- Converted all 18 three-guard/label admission modules to delegate to it, each under an equivalence lock (`Test.Suite.AdmissionEquivalence`); commits `eee9a42` + `b03cdf9`
- 4 two-guard + 2 non-label-predicate variants left as-is (would change behaviour)
- **Line impact**: ~neutral (net +30 across the Core modules). The ~1460-2120 line reduction is **Phase 2 only** (Types-module templates via TH), not started
- Plan: `docs/P1-1-REFACTORING-PLAN.md`

### Impact

- **Safety (partial)**: `error`→typed `throw` (still imprecise in pure code); 1 of 6 `unsafePerformIO` moved to IO
- **Type Safety (partial)**: typed enum at the render edge; gating dispatch still string-based
- **Code Quality**: -7 unused imports, -2 dead exports, -1 orphan instance, -2 name collisions
- **Test Stability**: 16 → 14 failures (2 flag-related tests fixed; 14 pre-existing remain)
- **Maintainability**: single-source-of-truth for admission logic (line-neutral; ~2000-line reduction is Phase-2-only)

## [v0.2.0-test-parity] — 2026-05-18

### Added

- Package A — Test parity restored:
  - F1 regression lock: `routeFamily_holisticField_keepsCMDeepen` and
    `routeFamily_emptyField_escalatesToCMDescribe` in
    `Test.Suite.CoreBehavior` (pins salience-escalation behaviour).
  - F2 regression lock: `conatusGateFlag_drivesLocalRecoveryPlan` and
    `conatusGateEnergyWithoutFlagDoesNotProduceConatusCause` in
    `Test.Suite.TurnPipelineProtocol` (pins M6 single-source-of-truth
    invariant: the flag, not the scalar, drives recovery).
  - F3 regression lock: `arbitraryField_smallestShrink_isWellFormed`
    in `Test.Suite.SelfAdjunction` (pins generator well-formedness).
  - Haddock status markers on `Self.Adjunction` dead API
    (`groundIn`, `rebroaden`, `probe`, `leftAdjunct`) —
    documentation-only pending Phase 8 deliberation framework.
  - Pending architectural work migrated from `progress.txt` to
    `ROADMAP.md` (Mid term / Long term).

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
