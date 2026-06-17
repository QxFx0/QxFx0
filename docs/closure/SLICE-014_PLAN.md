# SLICE-014 Plan — Runtime Persistence Residuals

Status: Closed
Purpose: triage and fix the regression failures among the 4 deferred `RuntimeInfrastructure` failures left by SLICE-013; leave summary-observability gaps as documented feature gaps.

## Origin

SLICE-013 closed the persistence behavior hardening front with the policy
**"strict rejects corruption, not compatibility"**. After landing the
`slice-013-truthcontract-fix` branch into `main` and running the relevant gates:

- `state` group: 36/36 ✅
- `runtime` group: 93/93 tried, 4 failures — cases 40, 45, 50, 51
- `unit` group: 1216/1217 tried, 1 failure — GF compile gate (`CoreBehavior.hs:1155`), pre-existing and out of scope

## Outcome

| Case | Classification | Resolution |
|---|---|---|
| 40 | Code regression | **Fixed** — switched `testBootstrapSessionCorruptStateFailsClosed` to `withStrictRuntimeEnv` so the strict-mode corrupt-state bootstrap path is exercised; strict mode already throws `RuntimeInitError` `STATE_CORRUPT`. |
| 45 | Code regression / detail mismatch | **Fixed** — `Commit.hs` now emits `PersistenceError` with code `PERSISTENCE_CONFLICT` when `saveStateWithProjectionExpected` returns `PdStateRevisionConflict`; previously it was folded into generic `PERSISTENCE_SAVE_FAILED`. |
| 50 | Known non-regression / feature gap | **Deferred** — typed pre-actor failure event is not emitted into the summary. Moved to SLICE-015. |
| 51 | Known non-regression / feature gap | **Deferred** — `restart_capped_non_authoritative` status is not surfaced in the summary. Moved to SLICE-015. |

## Final gate results

- `state` group: 36/36 ✅
- `runtime` group: 93/93 tried, 2 failures — cases 50, 51 only ✅
- `unit` group: 1216/1217 tried, 1 pre-existing GF compile failure (unchanged)

## Constraints

- Do **not** reopen the SLICE-013 policy: strict rejects corruption, not compatibility.
- Do **not** touch `forms_by_surface.json` / SLICE-010B artifacts.
- Do **not** delete `origin/feat/cts-44-promotion`.
- Do **not** start ROADMAP/public-docs coherence work until merge/gates are stable.

## Evidence

- Gate logs: `/home/liskil/slice014-fix-runtime.log` (runtime), `/home/liskil/slice013-merge-state3.log` (state), `/home/liskil/slice014-fix-unit.log` (unit).
- Merge commit: `1cc5752` on `main`.
- SLICE-013 plan: `docs/closure/SLICE-013_PLAN.md`.
- SLICE-015 plan: `docs/closure/SLICE-015_PLAN.md`.
