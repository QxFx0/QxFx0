# Remaining Closure Checklist

Status: Active
Purpose: compact list of the remaining public debt to the final anchor.

## Open fronts

| Front | Status | Exit |
|---|---|---|
| `DATALOG-ROLE-001` public role document | OPEN | a public shadow-validator role doc exists and matches architecture rules `[23]` / `[25]` |
| `M7` production evidence closure | OPEN | corpus/replay gate, authority round-trip subset, Python authority contour, M6 evidence reconciliation, and tier split are all checked |
| `SLICE-012` governed evidence admissibility | CLOSED (with pre-existing morphology blocker) | `EvidenceAdmissibility` type + `QXFX0_GOVERNED_EVIDENCE` fail-closed; `trcEvidenceAdmissibility` in every trace; CI extended contract governed; `ENV_CONTRACT.md` documents the contract; fast gate 0 new failures (8 errors + 2 failures pre-existing morphology, SLICE-010B); commits `b12cafb` + `6755b0e` on `origin/main` |

## Deferred feature gaps

| Front | Status | Exit |
|---|---|---|
| `SLICE-015` runtime summary observability gaps (50/51) | DEFERRED | `stateSummaryLines` must surface pre-actor failure kind and restart authority status; documented in `docs/closure/SLICE-015_PLAN.md`; not in active scope |

## Closed this cycle

| Front | Status | Exit |
|---|---|---|
| `SLICE-010B` morphology resource contract | CLOSED | runtime morphology derives from `paradigms.json` + `exceptions.json`; no public `origin/main` dependency on `forms_by_surface.json`; code reviewed, Python simulation of real paradigms/exceptions passes; full fast gate not run due to environment blockers (GHC/base freeze mismatch + missing GF C runtime) |
| `SLICE-012` governed evidence admissibility | CLOSED (with pre-existing morphology blocker) | see open-fronts table above for exit summary; commits `b12cafb` + `6755b0e` |
| `SLICE-014` runtime persistence residuals | CLOSED | runtime 93/93 tried; 40/45 fixed; 50/51 moved to SLICE-015 as documented feature gaps; plan `docs/closure/SLICE-014_PLAN.md` |
| `SLICE-013` persistence behavior hardening | CLOSED | state 36/36, runtime 93/93 tried; Option 1 policy (verbatim preserve, no manufacture); 4 pre-existing failures deferred; commit `76fe6ba` on `slice-013-truthcontract-fix` |
| `SLICE-009` / `SLICE-011` slow-suite / HTTP runtime infra triage | CLOSED | 135 slow cases reach clean final summary; all infra/line-ending/hermetic/proxy/sidecar-hang issues fixed; 11 persistence failures explicitly deferred to `SLICE-013` |
| `GRID-COD-GAP-001` historical artifact matrix | CLOSED | dependency for `SLICE-013` satisfied; artifacts classified before any import |


## Already closed

- M6 public evidence reconciliation is public and bounded.
- ROADMAP public identity drift is corrected.
- Public/private boundary now excludes private `docs/results` from the public claim path.

## Notes

- This checklist is intentionally smaller than `ROADMAP.md`.
- It names the fronts that still matter operationally; it does not duplicate the doctrine spine.
- A front is not closed until it has public evidence or an explicit deferred classification.
