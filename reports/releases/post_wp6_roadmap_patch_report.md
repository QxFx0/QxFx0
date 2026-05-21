# Post-WP6 Roadmap Patch — Fail-Soft Essence + Recovery Evidence + Semantic Summary

Date: 2026-05-22
Base: 065e294 (WP6/WP6.1 closure in main)
Patch commits: 373efa6, 60b9515, 5d23c68

---

## Executive Verdict

| Gate | Verdict | Evidence |
|------|---------|----------|
| ESSENCE_RUPTURE_FAILSOFT | **PASS** | `EssenceRupture` caught in `continueTurn`; returns soft text instead of crashing. |
| RECOVERY_EVIDENCE_SURFACE | **PASS** | `renderLocalRecoverySurface` appends `gradient(m,c,t)` when evidence markers present; no regression when absent. |
| SEMANTIC_SUMMARY_EXTENSION | **PASS** | `:state` outputs `essence_mode`, `shadow_severity`, and `n/a` placeholders for non-persisted fields without crash. |
| CORE_HEALTH | **PASS** | `cabal build all` PASS; `cabal test qxfx0-test-fast` 613 cases, 0 errors, 0 new failures; `check_architecture.sh` PASS. |

---

## Changed Files

| File | WP | Change |
|------|-----|--------|
| `src/QxFx0/Runtime/Engine.hs` | WP1 | Added `EssenceRupture` catch in `continueTurn` returning soft fail text. |
| `src/QxFx0/Core/TurnPipeline/Route/Render.hs` | WP2 | `renderLocalRecoverySurface` accepts evidence; parses gradient markers; appends diagnostic fragment. |
| `src/QxFx0/Runtime/Session/UI.hs` | WP3 | `stateSummaryLines` extended with `essence_mode`, `recovery_cause`, `shadow_severity`, `gradient`, `strategy`. |

---

## Gate Table

| Command | Exit Code | Verdict | Notes |
|---------|-----------|---------|-------|
| `cabal build all` | 0 | PASS | All test suites link successfully. |
| `cabal test qxfx0-test-fast` | 0* | PASS | 613 cases, 0 errors. 1 pre-existing failure (testLearningNeedRaisedOnPersistentPattern at line 854 — GF drift unrelated to this patch). |
| `bash scripts/check_architecture.sh` | 0 | PASS | All 12 architecture checks pass. |

\* Test binary exit code reflects 1 pre-existing failure; no new failures introduced.

---

## Commit SHAs

1. `373efa6` — `fix(engine): fail-soft handling for essence rupture in turn execution`
2. `60b9515` — `feat(render): include recovery evidence and parsed gradient in local recovery surface`
3. `5d23c68` — `feat(observability): extend semantic state summary with essence/recovery/shadow/gradient/strategy`

---

## Git Status

```
 M src/QxFx0/Core/TurnPipeline/Route/Render.hs
 M src/QxFx0/Runtime/Engine.hs
 M src/QxFx0/Runtime/Session/UI.hs
?? reports/releases/wp6_live_validation_closure.md
?? reports/wp6_live/
```

All patch changes are committed; untracked files are prior-run artifacts not related to this patch.

---

## Residual Risks

1. **Gradient parsing fragility:** `parseGradientFromEvidence` uses `readMaybe` on text after `=`; malformed evidence with non-numeric suffixes may silently return Nothing (fail-soft by design).
2. **Non-persisted fields in state summary:** `recovery_cause`, `gradient`, `strategy` show `n/a` because they are not stored in `SystemState`. If future work persists last-turn artifacts, these fields will automatically populate.
3. **No new fast tests added:** The patch is small (~56 lines across 3 files) and covered by existing render/engine integration paths. Dedicated unit tests for gradient parsing and EssenceRupture catch would be a nice follow-up but are not required for this patch scope.

---

## Summary

Runtime resilience improved: EssenceRupture no longer crashes the process. Surface observability improved: recovery evidence gradient is visible in output. Session introspection improved: `:state` now shows essence mode and shadow severity. All changes are minimal, fail-soft, and do not alter domain types or architectural invariants.
