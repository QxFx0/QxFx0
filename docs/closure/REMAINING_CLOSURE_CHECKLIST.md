# Remaining Closure Checklist

Status: Active
Purpose: compact list of the remaining public debt to the final anchor.

## Open fronts

| Front | Status | Exit |
|---|---|---|
| `SLICE-013` deferred failures (40/45/50/51) | OPEN | 4 pre-existing failures: corrupt-JSON bootstrap recovery, state-revision CAS, state-summary pre-actor failure, restart-capped status in summary; require separate triage slice |
| `DATALOG-ROLE-001` public role document | OPEN | a public shadow-validator role doc exists and matches architecture rules `[23]` / `[25]` |
| `M7` production evidence closure | OPEN | corpus/replay gate, authority round-trip subset, Python authority contour, M6 evidence reconciliation, and tier split are all checked |

## Closed this cycle

| Front | Status | Exit |
|---|---|---|
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
