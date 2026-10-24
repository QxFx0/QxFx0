# Remaining Closure Checklist

Status: Active
Last status sync: 2026-10-24 (bootstrap-safety follow-up; B2/B3/M6 rows aligned with the execution records and `M6_FELT_GATE.md`; integration rerun after ENOSPC)
Purpose: compact list of the remaining public debt to the final anchor.

## Open fronts

| Front | Status | Exit |
|---|---|---|
| `DATALOG-ROLE-001` public role document | CLOSED 2026-09-19 | `docs/closure/DATALOG_ROLE.md` + enforced rules `[22]`/`[23]` in `scripts/check_architecture.sh` (both pass; negative-tested); prior `[23]`/`[25]` refs were phantom numbers, corrected |
| `M7` production evidence closure | OPEN (regenerative evidence/ops regime) | No closure evidence in the current tree. `docs/tz/ROADMAP-COHERENCE-001.md` reframes M7 as ongoing evidence/ops upkeep, not a terminal phase; the old exit list (corpus/replay, authority round-trip, Python contour, M6 reconciliation, tier split) remains a checklist, not a demonstrated closure. Do not claim M7 closed. |
| `SLICE-012` governed evidence admissibility | CLOSED (with pre-existing morphology blocker) | `EvidenceAdmissibility` type + `QXFX0_GOVERNED_EVIDENCE` fail-closed; `trcEvidenceAdmissibility` in every trace; CI extended contract governed; `ENV_CONTRACT.md` documents the contract; fast gate 0 new failures (8 errors + 2 failures pre-existing morphology, SLICE-010B); commits `b12cafb` + `6755b0e` on `origin/main` |
| `B3` semantic-core MVS gate | GREEN (mechanical) | content-quality pass/fail gates defined for definition, distinction, repair, commitment, non-fallback; 4 decisions resolved; tests wired and fast/unit green 2026-10-24; B3 mechanical gates 1–5 passing in the M6 bounded benchmark; `docs/closure/B3_SEMANTIC_CORE_MVS_GATE.md`; commit `b7e4ec3`. M6-FELT mechanical is proven, human leg is partial. |
| `B2` human-eval protocol (executed, partial) | PARTIAL EVIDENCE — formal claim withheld | paired blind discrimination protocol with structure-ablated fluency-matched control; rubric tied to B3 gates; pre-registered fail/pivot; `docs/closure/B2_HUMAN_EVAL_PROTOCOL.md`; EXEC-002 (single effective rater: D3 6-0, D1 5-5 confounded, overall 5-3-2 mixed) and EXEC-003 (D1 6-2-2 vs fully ablated control) are recorded. No second rater and no preset threshold, so M6-FELT is not formally proven. |

## Deferred feature gaps

| Front | Status | Exit |
|---|---|---|
| `SLICE-015` runtime summary observability gaps (50/51) | CLOSED 2026-09-19 | both summary lines existed; case 51 covered+green, case 50 closed with `testStateSummaryShowsTypedPreActorFailure` (envelope-aware injected trace; session-level trigger impossible by flag-off design, documented) |
| `BD1` Envelope/angst parameter calibration | DEFERRED | `emAngst*` and `sdt*` stay hand-set; ADR-0012 §15.2 requires a production trace corpus (synthetic cannot produce `RuleHolisticAdvantage`/`RuleFormalAdvantage` divergence); unit-guards pin the invariants (`0 < sdtScaling <= 1`, `0 <= sdtThreshold <= 1`, `sdtWindow >= 1`, healthy scalar above `emConatusStructuralFloor`); A-slice/C-slice closed on 2026-08-07 (commits `6362c57`, `5832fff`, `7861323`, `7eb759a`, `72fe9db`) |
| `M6-FELT` felt-evidence gate | MECHANICAL PROVEN (bounded); HUMAN PARTIAL | mechanical checker `QxFx0.Core.M6FeltGate` over `[TurnReplayTrace]`: governed-evidence precondition (SLICE-012) + B3 Gates 1–5, fail-closed conjunction, per-gate verdict; `Test.Suite.M6FeltGate` (13 cases); `docs/closure/M6_FELT_GATE.md`. **Bounded benchmark**: the 12-turn governed session (`Test.Suite.M6FeltBenchmark`) records `M6FeltProven` (`feTurnCount = 12`, `feDistinctFocuses = 5`, `feRepairTurns = 2`); the historical 2026-08-08 `[FeltGate5NonFallback]` blocker was closed by runtime fixes, not by weakening the gate. **Human leg**: B2 EXEC-002/003 are partial (single effective rater, no preset threshold); formal “M6-FELT proven” remains withheld. |

## Closed this cycle (2026-06-27)

| Front | Status | Exit |
|---|---|---|
| `P4` Option A — legacy structuredBody gate enforcement | IMPLEMENTED | `validatePredicate` + `filterAdmissiblePredicates` in GeneratedPredicateGate.hs; `selectPredicatesGated` wrapper in Dialogue.hs; all 4 call sites gated; `docs/closure/P4_LEGACY_PATH_AUDIT.md` updated; build verification deferred to non-timeout env |
| `C4` dead code removal | COMPLETE | Phase 0 removed 23 Python scripts + 1 Haskell module; all 407 remaining modules verified alive; no more safe mechanical removal possible |
| `B3` mechanical gates wiring | IMPLEMENTED (superseded 2026-10-23) | Tests wired into TestMainUnit + TestMain + TestMainFast; ContentQualityGate added to cabal; the historical “not verified due to 30s build timeout” note is stale — tests are verified green on 2026-10-23 (see the open-fronts B3 row) |

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

- Status source hierarchy: `M6_FELT_GATE.md` for the M6 verdict, `B3_SEMANTIC_CORE_MVS_GATE.md` for B3 gate definitions, and `B2_HUMAN_EVAL_PROTOCOL.md` + `B2_EXEC_*` for B2. This checklist is a compact index, not a claim upgrade.
- This checklist is intentionally smaller than `ROADMAP.md`.
- It names the fronts that still matter operationally; it does not duplicate the doctrine spine.
- A front is not closed until it has public evidence or an explicit deferred classification.
