# SLICE-013 Plan — Persistence Behavior Hardening

Status: Active
Purpose: classify and fix the 11 persistence failures deferred from SLICE-011.

## Origin

SLICE-011 closed the slow-suite infra/harness front. All 135 slow cases ran to a
clean final summary. The only remaining non-passing cases are persistence-behavior
failures and were intentionally kept out of the infra scope.

## Classification

### 1. Core state / persistence (10 failures)

#### RuntimeInfrastructure group (5)

| Case | Test | Failure |
|---|---|---|
| 17 | `RuntimeInfrastructure.hs:621` | semanticAnchor must survive persisted load |
| 25 | `RuntimeInfrastructure.hs:885` | semanticAnchor must survive bootstrap restore |
| 45 | `RuntimeInfrastructure.hs:1706` | second stale writer must fail with state revision conflict |
| 50 | `RuntimeInfrastructure.hs:1884` | state summary must surface pre-actor failure kind |
| 51 | `RuntimeInfrastructure.hs:1905` | state summary must surface restart-capped status for non-authoritative restore |

#### StatePersistence group (5)

| Case | Test | Failure |
|---|---|---|
| 0 | `StatePersistence.hs:157` | non-authoritative persisted state accepted instead of rejected |
| 3 | `StatePersistence.hs:245` | strict bootstrap did not fail closed on non-authoritative persisted state |
| 4 | `StatePersistence.hs:??` | expected RecoveredCorruptOrigin after corrupt persisted state |
| 8 | `StatePersistence.hs:??` | RuntimeInitError on corrupt bootstrap state instead of graceful recovery |
| 11 | `StatePersistence.hs:542` | persisted canonical state did not clear output mode (SemanticIntrospectionOutput vs DialogueOutput) |

### 2. Sidecar persistence / session-token ownership (1 failure)

#### HttpRuntime group (1) — FIXED

| Case | Test | Failure | Fix |
|---|---|---|---|
| 7 | `HttpRuntime.hs:268` | `testTurnSessionTokenSurvivesRestart`: graceful sidecar restart should clear stale ownership and allow fresh claim | `scripts/http_runtime.py`: `SessionOwnershipStore.clear_store()` called in `graceful_shutdown()` so the session-token store is removed on sidecar shutdown; the next sidecar starts with no stale ownership. |

## Evidence

- `/home/liskil/slice011-runtime-fix2.log` — `runtimeInfrastructure` group result
- `/home/liskil/slice011-http7.log` — `httpRuntime` group result
- `/home/liskil/slice011-state2.log` — `statePersistence` group result
- `/tmp/opencode/slice011-slow-rerun.txt` — combined summary

## Progress

- 2026-06-16: `httpRuntime` group now passes 22/22 after sidecar session-token store
  cleanup on shutdown. Evidence: `/home/liskil/slice011-http8.log`.

## Exit criteria

- All 10 remaining core-state/persistence failures pass.
- Full `cabal test qxfx0-test-slow` (or per-group run) shows 135/135 green.
- No new infra/harness regressions are introduced.
