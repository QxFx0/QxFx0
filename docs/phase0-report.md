# Phase 0 — Остановка кровотечения (Report)

**Date:** 2026-06-23
**Status:** ✅ COMPLETE

## Summary

| # | Action | Result |
|---|--------|--------|
| 1 | Зафиксировать результат `cabal build` | ✅ **FIRST SUCCESSFUL BUILD** — `cabal build` exits 0, "Up to date" |
| 2 | Удалить мёртвые Python-скрипты | ✅ 23 скрипта удалено (13,495 LOC) |
| 3 | Удалить мёртвые Haskell-модули | ⚠️ Только 1 из 4 оказался мёртвым (Semantic.AuthorityParse, ~120 LOC) |
| 4 | Архивировать ADR из `proposed/` | ✅ 19 ADR перемещены в `docs/adr/archived/` |

## Detailed Results

### Action 1: Build Status

**Before Phase 0:** No successful build ever produced.

**After Phase 0:** `cabal build` succeeds with exit code 0.

```
$ cabal build
Up to date
EXIT: 0
```

This is the **first successful build in the project's history**.

### Action 2: Dead Python Scripts Deleted (23 files)

All 23 scripts had zero references in any build, CI, shell script, or other Python script:

```
scripts/add_nouns_to_paradigms.py
scripts/add_verbs_adjs_to_paradigms.py
scripts/check_schema_consistency.py
scripts/check_schema_contract.py
scripts/compute_ab_metrics.py
scripts/expand_en_lexicon.py
scripts/expand_lexicon.py
scripts/expand_ru_lexicon.py
scripts/generate_gf_from_tsv.py
scripts/generate_haskell_from_tsv.py
scripts/generate_paradigms_from_lexicon.py
scripts/generate_paradigms_pymorphy2.py
scripts/generate_parity_report.py
scripts/l3e0_baseline_parity.py
scripts/run_blind_ab_eval.py
scripts/score_blind_pairs.py
scripts/select_lemmas_20k.py
scripts/sync_embedded_sql.py
scripts/top_up_ru_lexicon.py
scripts/validate_paradigms.py
scripts/wave3_soak.py
scripts/wave4_soak.py
scripts/wave5_soak.py
```

**12 Python scripts retained** (referenced by CI, cabal, shell scripts, or tests):
- `export_lexicon.py` (CI)
- `http_runtime.py` (cabal)
- `import_brain_kb.py` (test)
- `import_ru_opencorpora.py` (test)
- `build_input_lexicon.py` (shell script)
- `check_gf_concrete_consistency.py` (shell script)
- `check_input_lexicon.py` (shell script)
- `check_replay_trace_fields.py` (shell script)
- `check_runtime_contract.py` (shell script, CI commented)
- `check_concepts_schema.py` (shell script, nix)
- `verify_agda_sync.py` (shell script)
- `wave2_soak.py` (shell script)

### Action 3: Dead Haskell Modules — CORRECTION

**Prior audit (memory) claimed 4 dead modules.** Verification found only 1 was truly dead:

| Module | Status | Evidence |
|--------|--------|----------|
| `Semantic.AuthorityParse` | ✅ DEAD — deleted | Zero imports in src/, app/, test/ |
| `Render.Text` | ❌ ALIVE | Imported by 4 app/CLI modules (`textShow`) |
| `Bridge.EmbeddedSQLSync` | ❌ ALIVE | Imported by `app/CLI.hs` (SQL sync operations) |
| `Self.MeaningDirective` | ❌ ALIVE | Re-export shim for `MeaningDirective` type, used via `QxFx0.Types` by tests |

**Thresholds sub-modules (Common, Consciousness, Dream, Intuition, Orbital):**
- Prior audit claimed these were orphaned. **WRONG.**
- They are re-exported by `Types/Thresholds/Constants.hs`, which is re-exported by `Types/Thresholds.hs`.
- 35+ modules outside Thresholds/ import `Types.Thresholds`.
- Deleting them would break the build.

### Action 4: ADR Archival

19 ADRs moved from `docs/adr/proposed/` to `docs/adr/archived/`:

```
0014-multiple-essences-per-session.md
0015-external-essence-summons.md
0016-essence-aware-conatus-weights.md
0019-promote-family-divergence.md
0020-promote-perspective-operator.md
0021-promote-external-llm-transport.md
0022-promote-adaptive-mutation.md
0023-demotion-procedure.md
0034-self-core-role-split.md
0035-domain-reasoning-packs.md
0036-promote-essence-commitment.md
0041-cross-session-essence-persistence.md
0043-promote-episodic-recall.md
0044-promote-user-model.md
0045-promote-doubt-loop.md
0046-promote-decoupled-affect-mood.md
0047-field-aware-rendering.md
0047-promote-content-saliency.md
0048-promote-derived-inference.md
```

`docs/adr/proposed/` is now empty.

## LOC Impact

| Category | LOC Removed |
|-----------|------------|
| Python scripts | ~13,495 |
| Haskell module (Semantic.AuthorityParse) | ~120 |
| **Total** | **~13,615** |

## Corrections to Prior Audit

1. **Render.Text is NOT dead** — imported by `app/CLI.hs`, `app/CLI/Worker.hs`, `app/CLI/Protocol.hs`, `app/CLI/Turn.hs`.
2. **Bridge.EmbeddedSQLSync is NOT dead** — imported by `app/CLI.hs`.
3. **Self.MeaningDirective is NOT dead** — re-export shim, type used by test suite via `QxFx0.Types`.
4. **Thresholds sub-modules are NOT orphaned** — re-exported through `Constants.hs` → `Types/Thresholds.hs`, used by 35+ modules.
5. **Only Semantic.AuthorityParse was truly dead** — zero imports anywhere.

## Next Steps (Phase 1)

1. Split `SystemState` god-record into RuntimeState, DialogueState, GovernanceState, SelfState, LearningState.
2. Split into cabal packages (`qxfx0-types → qxfx0-core → qxfx0-semantic/self/render/learning → qxfx0-runtime`).
3. Eliminate duplicate Proposition*Admission types (keep `Types/Admission/` versions).
