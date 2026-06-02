# Closure Plan Import — Final Status

**Date**: 2026-06-02
**Branch**: `feature/closure-plan-import`
**Base**: `f2b30d3` (QxFx0 canonical HEAD)
**Status**: 5 of 5 phases **port complete**; ready for next-contributor review + commit

---

## What was ported (and how)

### Phase 1 — Pure additions (DONE)
- **docs/closure/**: 32 files copied from `QxFx0_v3/docs/closure/`
  - Plus this IMPORT_LOG.md (1 added)
  - **Total in QxFx0/docs/closure/**: 33 files
- **docs/adr/proposed/**: 9 new ADR files copied
  - 0019-0022 (4 promotion ADRs) + 0023 (1 demotion ADR) + 0034/0035/0036/0041 (4 renumbered)
- **data/calibration/ranges.json**: 1 file (Package 11)
- **src/QxFx0/Render/Authority.hs**: 1 file (F-11 stub)
- **test/Test/Suite/**: 6 files (5 wired + 1 unwired stub)
  - `ReplayGate.hs`, `ObserverDiscipline.hs`, `TraceSchema.hs`,
    `RegenerableDerived.hs`, `PromotionFlagDiscipline.hs` (wired in TestMain.hs + TestMainUnit.hs)
  - `RenderAuthorityStub.hs` (tasty, **unwired** — kept as future-work)
- **scripts/check_replay_gate.sh**: 1 file (Package 3)
- **scripts/check_calibration_codomain.sh**: 1 file (Package 11)

### Phase 2 — ADR renumbering (DONE)
- 2 ADRs renumbered in QxFx0/docs/adr/proposed/:
  - `0013-cross-session-essence-persistence.md` → **deleted** (replaced by `0041-`...)
  - `0017-domain-reasoning-packs.md` → **deleted** (replaced by `0035-`...)
- 12 ADRs total in proposed/ (was 5; +9 new, -2 old)

### Phase 3 — Script augmentations (DONE, with care)
- **check_architecture.sh** (331 → 673 lines):
  - Added rules [13]-[20] (R1-R7 of ADR-0034 §3) after rule [12]
  - **Preserved** user's pre-existing modifications (QXFX0_EMBEDDING_BACKEND checks)
  - bash -n: 1 pre-existing false positive (line 408, here-doc-in-if) — runtime OK
- **ci_gate_contract.sh** (547 → 565 lines):
  - Inserted Gate 3b (Calibration Codomain) + Gate 3c (Replay Gate) after Gate 3
  - **Preserved** user's pre-existing Gate 8b (Runtime/deployment contract)
- **verify.sh** (513 → 551 lines):
  - Inserted [10b/10] (Calibration codomain) + [10c/10] (Replay gate) after [10/10]
  - **Preserved** user's pre-existing `lib/cabal_env.sh` source line and Python setup

### Phase 4 — Test infrastructure (DONE)
- **test/TestMain.hs** (48 → 53 lines):
  - Added 5 imports: ObserverDiscipline, TraceSchema, RegenerableDerived, PromotionFlagDiscipline, ReplayGate
  - Added 5 test list entries after `renderDialogueCoverageTests`
  - **Preserved** QxFx0's `statePersistenceTests` (which QxFx0_v3 lacks)
- **test/TestMainUnit.hs** (65 → 73 lines):
  - Added 4 imports: ReplayGate, TraceSchema, RegenerableDerived, PromotionFlagDiscipline
  - Added 4 test list entries
  - **Did NOT add** `DreamPressure` (not in QxFx0; closure plan doesn't include it)
- **qxfx0.cabal** test-common (33 → 39 test modules):
  - Added: RenderAuthorityStub, ObserverDiscipline, TraceSchema, RegenerableDerived, PromotionFlagDiscipline, ReplayGate
  - **Preserved** all 33 pre-existing modules

### Phase 5 — Documentation (DONE)
- **IMPORT_LOG.md** (this file, in docs/closure/)
- **IMPORT_LOG_OLD.md** (earlier draft, deprecated; see git log)

---

## What was NOT ported (out of scope per user directive)

- Python replacement work (Python P5-1, in residual backlog)
- Real GF Haskell parser (in residual backlog)
- Calibration data harvesting (needs production traces, F-09)
- Family Divergence flag flip (ADR-0019 landing, separate step)
- 3 trace schema GAP closures (separate step)
- The 4 remaining promotion landings (separate step)
- Demotion activation (separate step)

---

## Working tree state summary

- **Branch**: `feature/closure-plan-import`
- **Total files in working tree**: ~180 (was 157 pre-modifications)
- **Untracked new files**: ~52 (32 closure docs + 9 ADRs + 6 test suites + 1 source + 2 scripts + 1 ranges.json + 1 IMPORT_LOG)
- **Modified (closure plan)**: 4 (check_architecture.sh, ci_gate_contract.sh, verify.sh, TestMain.hs, TestMainUnit.hs, qxfx0.cabal — 6 files)
- **Modified (user pre-existing)**: ~155 (unchanged, just preserved)

---

## What's needed from the next contributor

To complete the "renumber landing" + Tier 1 closure:

1. **Review this import**:
   - Spot-check `check_architecture.sh` rules [13]-[20] are correct
   - Spot-check `test/TestMain.hs` + `test/TestMainUnit.hs` test runs
   - Verify the closure docs (FOLLOWUPS, ENFORCEMENT_MATRIX, etc.) reference 0034/0035/0036/0041

2. **`git add` the changes**:
   - `git add docs/closure/`
   - `git add docs/adr/proposed/{0014,0015,0016,0019,0020,0021,0022,0023,0034,0035,0036,0041}-*.md`
   - `git rm docs/adr/proposed/0013-cross-session-essence-persistence.md`
   - `git rm docs/adr/proposed/0017-domain-reasoning-packs.md`
   - `git add scripts/{check_replay_gate,check_calibration_codomain}.sh`
   - `git add scripts/check_architecture.sh scripts/ci_gate_contract.sh scripts/verify.sh`
   - `git add src/QxFx0/Render/Authority.hs`
   - `git add test/Test/Suite/{ReplayGate,ObserverDiscipline,TraceSchema,RegenerableDerived,PromotionFlagDiscipline,RenderAuthorityStub}.hs`
   - `git add test/TestMain.hs test/TestMainUnit.hs`
   - `git add qxfx0.cabal`
   - `git add data/calibration/ranges.json`

3. **Run cabal build + test** (requires cabal permission):
   - `cabal build all` — verify the 6 new test suites compile
   - `cabal test` — verify the 5 wired tests pass
   - `bash scripts/check_architecture.sh` — verify rules [13]-[20] pass on the canonical QxFx0 codebase
   - `bash scripts/check_replay_gate.sh` — verify 0 violations, 3 GAPs
   - `bash scripts/check_calibration_codomain.sh` — verify 0 violations, 17 GAPs
   - `bash scripts/ci_gate_contract.sh` — verify Gates 3, 3b, 3c, 8b all pass

4. **Commit** (single commit for the import):
   - Message: `feat(closure-plan): port closure-plan artifacts from side workspace to canonical repo`
   - Body: list the 5 phases, the 7 test modules added, the rule additions

5. **PR** to main (or merge directly if working on a feature branch workflow)

---

## Status mapping (per FOLLOWUPS §15 3-state)

| Item | Before this import | After this import | Reason |
|------|-------------------|-------------------|--------|
| docs/closure/* | not-imported | ready-for-landing | files in working tree, not in git history |
| ADR renumber set (0034/35/36/41) | not-imported | ready-for-landing | same |
| 5 promotion ADRs (0019-0022) | not-imported | ready-for-landing | same |
| 1 demotion ADR (0023) | not-imported | ready-for-landing | same |
| src/Render/Authority.hs (F-11) | not-imported | ready-for-landing | same |
| 6 new test suites | not-imported | ready-for-landing | TestMain wired; cabal/test not run |
| scripts/check_replay_gate.sh | not-imported | ready-for-landing | same |
| scripts/check_calibration_codomain.sh | not-imported | ready-for-landing | same |
| check_architecture.sh rules [13]-[20] | not-imported | ready-for-landing | surgical insert, user work preserved |
| ci_gate_contract.sh Gates 3b/3c | not-imported | ready-for-landing | same |
| verify.sh [10b/10] [10c/10] | not-imported | ready-for-landing | same |
| qxfx0.cabal 6 new test modules | not-imported | ready-for-landing | same |

**`landed` (per strict §15)** requires cabal build/test/CI pass + commit. **Not yet achieved** because:
- This session has no-cabal constraint
- Next contributor must complete the cabal/test step

**Tier 1 closure** is therefore:
- R6: **green** (verified earlier; rule [20] works)
- renumber landing: **ready-for-landing** (this import prepared it; cabal/test pending)
- ADR-0019 landing: **not started** (separate step; flag flip at `Cascade.hs:74`)

---

## Residual backlog (UNCHANGED from user directive, after this import)

1. **renumber landing (commit step)** — `git add` + cabal/test/CI pass + commit
2. **ADR-0019 landing** — flip `familyDivergenceEnabled = False` to `True` at `Cascade.hs:74`
3. **trace gap closure** — add 3 missing trace fields (Conatus, Field, Identity)
4. **F-09 / F-10 data + calibration** — production traces + first calibration
5. **Python P5-1** — replace 3 critical Python scripts with Haskell
6. **remaining 4 promotion landings** — ADR-0020, 0021, 0022, 0036
7. **demotion activation** — ADR-0023 procedure in use
8. **real GF parser** — Haskell implementation
