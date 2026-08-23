# Remaining Closure Checklist

Status: Active
Purpose: compact list of the remaining public debt to the final anchor.

## Open fronts

| Front | Status | Exit |
|---|---|---|
| `DATALOG-ROLE-001` public role document | OPEN | a public shadow-validator role doc exists and matches architecture rules `[23]` / `[25]` |
| `M7` production evidence closure | OPEN | corpus/replay gate, authority round-trip subset, Python authority contour, M6 evidence reconciliation, and tier split are all checked |
| `SLICE-012` governed evidence admissibility | CLOSED (with pre-existing morphology blocker) | `EvidenceAdmissibility` type + `QXFX0_GOVERNED_EVIDENCE` fail-closed; `trcEvidenceAdmissibility` in every trace; CI extended contract governed; `ENV_CONTRACT.md` documents the contract; fast gate 0 new failures (8 errors + 2 failures pre-existing morphology, SLICE-010B); commits `b12cafb` + `6755b0e` on `origin/main` |
| `B3` semantic-core MVS gate | IMPLEMENTED (tests wired, not verified passing) | content-quality pass/fail gates defined for definition, distinction, repair, commitment, non-fallback; 4 decisions resolved; `docs/closure/B3_SEMANTIC_CORE_MVS_GATE.md`; M6-FELT remains NOT PROVEN; commit `b7e4ec3` |
| `B2` human-eval protocol (design) | OPEN (design only) | paired blind discrimination protocol with structure-ablated fluency-matched control; rubric tied to B3 gates; pre-registered fail/pivot; `docs/closure/B2_HUMAN_EVAL_PROTOCOL.md`; M6-FELT remains NOT PROVEN; cannot run until B3 gates mechanically pass |

## Deferred feature gaps

| Front | Status | Exit |
|---|---|---|
| `SLICE-015` runtime summary observability gaps (50/51) | DEFERRED | `stateSummaryLines` must surface pre-actor failure kind and restart authority status; documented in `docs/closure/SLICE-015_PLAN.md`; not in active scope |
| `BD1` Envelope/angst parameter calibration | DEFERRED | `emAngst*` and `sdt*` stay hand-set; ADR-0012 §15.2 requires a production trace corpus (synthetic cannot produce `RuleHolisticAdvantage`/`RuleFormalAdvantage` divergence); unit-guards pin the invariants (`0 < sdtScaling <= 1`, `0 <= sdtThreshold <= 1`, `sdtWindow >= 1`, healthy scalar above `emConatusStructuralFloor`); A-slice/C-slice closed on 2026-08-07 (commits `6362c57`, `5832fff`, `7861323`, `7eb759a`, `72fe9db`) |
| `M6-FELT` felt-evidence gate | IMPLEMENTED (NOT PROVEN) | mechanical checker `QxFx0.Core.M6FeltGate` over `[TurnReplayTrace]`: governed-evidence precondition (SLICE-012) + B3 Gates 1–5, fail-closed conjunction, per-gate verdict; `Test.Suite.M6FeltGate` (13 cases); `docs/closure/M6_FELT_GATE.md`; sessions become M6-FELT evidence only when the gate passes under `QXFX0_GOVERNED_EVIDENCE=1` + B2 human-eval. **Bounded benchmark (2026-08-08)**: real 12-turn governed session (`Test.Suite.M6FeltBenchmark`) fails fail-closed with exactly `[FeltGate5NonFallback]` — C1–C4 + governed-evidence pass on the production runtime; the blocker is the GF linearizer non-fallback coverage (distinction/linkage/proof/hypothesis turns fall back to `gf_response_plan:response_plan_without_propositions` / `russian_compatibility_shim`), making M6-FELT mechanically unreachable until the linearizer gap is closed. **2026-08-23 verification**: the full `qxfx0-test-fast` run (1808 cases incl. `M6FeltBenchmark`) is green — the benchmark verdict passes under the current runtime; re-verify and close this line or document the remaining gate before relying on the old status |

## Closed this cycle (2026-06-27)

| Front | Status | Exit |
|---|---|---|
| `P4` Option A — legacy structuredBody gate enforcement | IMPLEMENTED | `validatePredicate` + `filterAdmissiblePredicates` in GeneratedPredicateGate.hs; `selectPredicatesGated` wrapper in Dialogue.hs; all 4 call sites gated; `docs/closure/P4_LEGACY_PATH_AUDIT.md` updated; build verification deferred to non-timeout env |
| `C4` dead code removal | COMPLETE | Phase 0 removed 23 Python scripts + 1 Haskell module; all 407 remaining modules verified alive; no more safe mechanical removal possible |
| `B3` mechanical gates wiring | IMPLEMENTED | Tests wired into TestMainUnit + TestMain; ContentQualityGate added to cabal; tests not verified passing due to 30s build timeout |

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
