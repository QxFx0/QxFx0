# SLICE-013 Plan — Persistence Behavior Hardening

Status: Active
Purpose: classify and fix the 11 persistence failures deferred from SLICE-011.

## Origin

SLICE-011 closed the slow-suite infra/harness front. All 135 slow cases ran to a
clean final summary. The only remaining non-passing cases are persistence-behavior
failures and were intentionally kept out of the infra scope.

## Classification

### 1. Core state / persistence

#### RuntimeInfrastructure group (7 remaining)

| Case | Test | Failure |
|---|---|---|
| 18 | `RuntimeInfrastructure.hs:648` | non-authoritative state must stay non-authoritative on load (expected `LegacyIncompleteSurface`) |
| 19 | `RuntimeInfrastructure.hs:672` | non-authoritative persisted state should remain restorable (expected `LegacyIncompleteSurface`) |
| 26 | `RuntimeInfrastructure.hs:913` | non-authoritative bootstrap must preserve truth contract status (expected `LegacyIncompleteSurface`) |
| 40 | `RuntimeInfrastructure.hs:1465` | expected `RuntimeInitError` for corrupt persisted state bootstrap |
| 45 | `RuntimeInfrastructure.hs:1715` | second stale writer must fail with state revision conflict |
| 50 | `RuntimeInfrastructure.hs:1893` | state summary must surface pre-actor failure kind |
| 51 | `RuntimeInfrastructure.hs:1914` | state summary must surface restart-capped status for non-authoritative restore |

#### StatePersistence group (5) — FIXED

| Case | Test | Failure | Fix |
|---|---|---|---|
| 0 | `StatePersistence.hs:157` | non-authoritative persisted state accepted instead of rejected | `loadState` now returns `LoadStateCorrupt [PdNonAuthoritativeTruth]` when the persisted truth contract is not authoritative. |
| 3 | `StatePersistence.hs:245` | strict bootstrap did not fail closed on non-authoritative persisted state | `bootstrapSession` in strict mode throws `STATE_CORRUPT` for non-authoritative persisted state. |
| 4 | `StatePersistence.hs:??` | expected `RecoveredCorruptOrigin` after corrupt persisted state | `bootstrapSession` in degraded mode now recovers corrupt/non-authoritative load with `RecoveredCorruptOrigin` and `GrfRecoveredCorruptBootstrap`. |
| 8 | `StatePersistence.hs:??` | `RuntimeInitError` on corrupt bootstrap state instead of graceful recovery | Same degraded-mode recovery path. |
| 11 | `StatePersistence.hs:542` | persisted canonical state did not clear output mode (`SemanticIntrospectionOutput` vs `DialogueOutput`) | `canonicalizePersistedState` now clears `ssOutputMode` to `DialogueOutput`, upgrades `ssTruthContractStatus` to `AssembledSurfacePreserved`, and clears `ssGovernanceRuntimeFault`. |

### 2. Sidecar persistence / session-token ownership (1) — FIXED

| Case | Test | Failure | Fix |
|---|---|---|---|
| 7 | `HttpRuntime.hs:268` | `testTurnSessionTokenSurvivesRestart`: graceful sidecar restart should clear stale ownership and allow fresh claim | `scripts/http_runtime.py`: `SessionOwnershipStore.clear_store()` called in `graceful_shutdown()` so the session-token store is removed on sidecar shutdown; the next sidecar starts with no stale ownership. |

## Evidence

- `/home/liskil/slice011-runtime-fix2.log` — `runtimeInfrastructure` group result before SLICE-013 fixes
- `/home/liskil/slice011-http7.log` — `httpRuntime` group result before sidecar fix
- `/home/liskil/slice011-state2.log` — `statePersistence` group result before state fixes
- `/home/liskil/slice011-http8.log` — `httpRuntime` group after sidecar fix (22/22 ✅)
- `/home/liskil/slice013-state2.log` — `statePersistence` group after state fixes (20/20 ✅)
- `/home/liskil/slice013-runtime2.log` — `runtimeInfrastructure` group after state fixes (93/93, 7 failures)
- `/tmp/opencode/slice011-slow-rerun.txt` — combined SLICE-011 summary

## Progress

- 2026-06-16: `httpRuntime` group passes 22/22 after sidecar session-token store cleanup.
- 2026-06-16: `statePersistence` group passes 20/20 after non-authoritative/corrupt-state handling and canonicalization.
- 2026-06-16: `runtimeInfrastructure` group still has 7 failures. Three of them (18, 19, 26) are new regressions caused by the `saveState` canonicalization that upgrades `ssTruthContractStatus` to `AssembledSurfacePreserved`; the runtime tests expect `LegacyIncompleteSurface` to be preserved. This reveals a contract conflict between `statePersistence` and `runtimeInfrastructure` tests that must be resolved before the remaining 4 original failures (40, 45, 50, 51) can be targeted.

## Open question

- Should `saveState` canonicalize a non-authoritative truth contract (`LegacyIncompleteSurface` / `NonExpansiveRecoverySurface`) to `AssembledSurfacePreserved`, or should it preserve the original truth contract? `statePersistence` case 11 expects upgrade; `runtimeInfrastructure` cases 18, 19, 26 expect preservation. A targeted policy decision is needed.

## Exit criteria

- All `runtimeInfrastructure` failures pass.
- Full `cabal test qxfx0-test-slow` (or per-group run) shows 135/135 green.
- No new infra/harness regressions are introduced.
