# SLICE-014 Plan — Runtime Persistence Residuals

Status: Open
Purpose: triage and eventually fix the 4 deferred `RuntimeInfrastructure` failures left by SLICE-013.

## Origin

SLICE-013 closed the persistence behavior hardening front with the policy
**"strict rejects corruption, not compatibility"**. After landing the
`slice-013-truthcontract-fix` branch into `main` and running the relevant gates:

- `state` group: 36/36 ✅
- `runtime` group: 93/93 tried, 4 failures — cases 40, 45, 50, 51
- `unit` group: 1216/1217 tried, 1 failure — GF compile gate (`CoreBehavior.hs:1155`), pre-existing and out of scope

The 4 runtime failures are explicitly deferred to this slice.

## Deferred failures

| Case | Test | Location | Failure message | Initial classification |
|---|---|---|---|---|
| 40 | `testBootstrapSessionCorruptStateFailsClosed` | `RuntimeInfrastructure.hs:1491` | expected `RuntimeInitError` for corrupt persisted state bootstrap, got `Left/Right mismatch` | **Code regression (SLICE-013)** — degraded-mode bootstrap now recovers from corrupt JSON via `RecoveredCorruptOrigin`; test expects fail-closed behavior. |
| 45 | `testStateRevisionCasAllowsOnlyOneStaleWriter` | `RuntimeInfrastructure.hs:1743` | second stale writer must fail with state revision conflict | **Code regression or detail mismatch** — save conflict is detected (`state_revision_conflict` in log), but the thrown `PersistenceError` detail does not contain the expected string and instead reports `PERSISTENCE_SAVE_FAILED`. |
| 50 | `testStateSummaryShowsTypedPreActorFailure` | `RuntimeInfrastructure.hs:1921` | state summary must surface pre-actor failure kind | **Known non-regression / feature gap** — typed pre-actor failure event is not emitted into the summary. |
| 51 | `testStateSummaryShowsRestartAuthorityStatus` | `RuntimeInfrastructure.hs:1942` | state summary must surface restart-capped status for non-authoritative restore | **Known non-regression / feature gap** — `restart_capped_non_authoritative` status is not surfaced in the summary after a non-authoritative (or compatibility-marker) restore. |

## Constraints

- Do **not** reopen the SLICE-013 policy: strict rejects corruption, not compatibility.
- Do **not** touch `forms_by_surface.json` / SLICE-010B artifacts.
- Do **not** delete `origin/feat/cts-44-promotion`.
- Do **not** start ROADMAP/public-docs coherence work until merge/gates are stable.

## Next steps

1. Confirm the classification of each failure with a targeted test run or code trace.
2. For regressions (40, 45): identify the minimal change that restores the expected behavior without violating the SLICE-013 policy.
3. For non-regressions (50, 51): decide whether to implement the missing summary fields or mark them as long-term deferred.
4. Update this plan with the final classification and proposed fixes before implementation.

## Evidence

- Gate logs: `/home/liskil/slice013-merge-runtime2.log` (runtime), `/home/liskil/slice013-merge-state3.log` (state), `/home/liskil/slice013-merge-unit2.log` (unit).
- Merge commit: `1cc5752` on `main`.
- SLICE-013 plan: `docs/closure/SLICE-013_PLAN.md`.
