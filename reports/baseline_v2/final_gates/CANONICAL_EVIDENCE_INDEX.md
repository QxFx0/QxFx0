# QxFx0 Canonical Evidence Index

**Branch:** `feat/wp123-20260510`  
**Index SHA:** Post-WP1–WP3 recovery canonical run  
**Last updated:** 2026-05-11  
**Purpose:** Single source of truth for which evidence files are canonical vs. historical/superseded.

---

## Canonical Core Contract Evidence (PROD_GO)

### Primary Contract Run — Post-GF Path Contract Enforcement

**RUN_ID:** `ci-20260511-022550`  
**Commit:** `d79c4a71` (merged release commit; includes core contract Gate 4a `check_gf_render_path.sh`)  
**Verdict:** **CONTRACT_VERDICT: PROD_GO**  
**All core gates PASS:** build, tests, architecture, GF quality, GF render-path gate, haddock, SQL sync, schema consistency, schema contract, generated artifacts, lexicon, release-smoke degraded-local (ACCEPT_WITH_SKIPS, 0 FAIL).

| File | Path | Description |
|------|------|-------------|
| Contract summary (Markdown) | `reports/baseline_v2/final_gates/_gate_results_ci-20260511-022550_core.md` | PROD_GO, all core gates PASS |
| Contract summary (TSV) | `reports/baseline_v2/final_gates/_gate_results_ci-20260511-022550_core.tsv` | Machine-readable gate results |

### Per-Gate Logs (core, RUN_ID: `ci-20260511-022550`)

| Gate | Log File |
|------|----------|
| 01 cabal build all | `reports/baseline_v2/final_gates/01_cabal_build_ci-20260511-022550_core.log` |
| 02 cabal test | `reports/baseline_v2/final_gates/02_cabal_test_fast_ci-20260511-022550_core.log` |
| 03 check_architecture.sh | `reports/baseline_v2/final_gates/03_check_architecture_ci-20260511-022550_core.log` |
| 04 gf_quality_gate.sh | `reports/baseline_v2/final_gates/04_gf_quality_ci-20260511-022550_core.log` |
| 04a check_gf_render_path.sh | `reports/baseline_v2/final_gates/06a_gf_render_path_ci-20260511-022550_core.log` |
| 05 check_haddock.sh | `reports/baseline_v2/final_gates/05_check_haddock_ci-20260511-022550_core.log` |
| 09 check_generated_artifacts.sh | `reports/baseline_v2/final_gates/09_generated_artifacts_ci-20260511-022550_core.log` |
| 10 check_lexicon.sh | `reports/baseline_v2/final_gates/10_check_lexicon_ci-20260511-022550_core.log` |
| 11 release-smoke degraded-local | `reports/baseline_v2/final_gates/11_release_smoke_ci-20260511-022550_core.log` |

---

## Superseded / Historical Evidence

These logs are from prior attempts in this target repo and **must not** be used as primary evidence.

| File Pattern | Reason Superseded | Canonical Replacement |
|--------------|-------------------|----------------------|
| `reports/baseline_v2/final_gates/*_ci-20260509-194300_*` | Early core attempt; GF quality gate failed (missing PGF) | `_gate_results_ci-20260511-022550_core.md` |
| `reports/baseline_v2/final_gates/*_ci-20260509-201231_*` | Package A target closure (PROD_GO), pre-WP1–WP3 | `_gate_results_ci-20260511-022550_core.md` |
| `reports/baseline_v2/final_gates/*_ci-20260509-234041_*` | Pre-WP3 canonical core run (PROD_GO). Superseded by GF-path-enforced run `ci-20260511-022550`. | `_gate_results_ci-20260511-022550_core.md` |
| `reports/baseline_v2/final_gates/*_ci-20260510-214705_*` | Post-WP3 attempt; Gate 11 REJECT due to INFRA (smoke strict semantics not yet fixed) | `_gate_results_ci-20260511-022550_core.md` |
| `reports/baseline_v2/final_gates/*_ci-20260510-225652_*` | Intermediate core attempt during WP-B fixes | `_gate_results_ci-20260511-022550_core.md` |
| `reports/baseline_v2/final_gates/*_ci-20260510-233024_*` | Intermediate core attempt during WP-B fixes | `_gate_results_ci-20260511-022550_core.md` |
| `reports/baseline_v2/final_gates/*_ci-20260511-000108_*` | Pre-GF-path-gate canonical run (before Gate 4a integration) | `_gate_results_ci-20260511-022550_core.md` |
| Source-repo evidence (`_gate_results_ci-20260509-183851_*`, `ci-20260509-161530_*`, etc.) | Belongs to `QxFx0_v2` (`stabilize-v2-gf`), not target repo | `_gate_results_ci-20260511-022550_core.md` |

---

## Extended-LowRAM Contract Evidence (Honest INFRA-Skipped)

**RUN_ID:** `ci-20260510-031314`  
**Profile:** `extended-lowram`  
**Verdict:** `EXTENDED_LOWRAM_ACCEPT_WITH_INFRA` — all non-INFRA gates PASS.  
**Archive path:** `reports/baseline_v2/final_gates_lowram/`  
**Summary:** `reports/baseline_v2/final_gates_lowram/_gate_results_ci-20260510-031314_extended_lowram_summary.md`

| Gate | Verdict | Notes |
|------|---------|-------|
| 01–10 | PASS | same as core |
| 11 (fast proxy) | PASS | 426 tests, 0 errors, 0 failures |
| 12 (coverage) | INFRA | `vector-0.13.2.0` internal-library + coverage incompatibility; known Cabal limitation on this runner |
| 13 (release-smoke strict) | INFRA | exceeds timeout on low-RAM runner |

## Extended Contract Evidence (FULL_SCIENTIFIC_GO)

**Status:** DEFERRED — no high-mem runner executed yet on target repo.

When available, the canonical extended run will use:
- `QXFX0_CONTRACT_PROFILE=extended`
- Runner: >=32 GB RAM, >=45 min timeout
- Expected artifact paths:
  - `reports/baseline_v2/final_gates/_gate_results_<RUN_ID>_extended.md`
  - `reports/baseline_v2/final_gates/_gate_results_<RUN_ID>_extended.tsv`
  - `reports/baseline_v2/final_gates/11_cabal_test_slow_<RUN_ID>_extended.log`
  - `reports/baseline_v2/final_gates/12_test_coverage_<RUN_ID>_extended.log`
  - `reports/baseline_v2/final_gates/13_release_smoke_<RUN_ID>_extended.log`

See `docs/EXTENDED_CONTRACT_RUNBOOK.md` for execution checklist.

---

## How to Verify Canonical Evidence

```bash
# Canonical core contract summary (PROD_GO)
cat reports/baseline_v2/final_gates/_gate_results_ci-20260511-022550_core.md | grep "CONTRACT_VERDICT"
# Expected: CONTRACT_VERDICT: PROD_GO
```

---

*Index maintained by release/reliability engineer. Update this file whenever a new canonical run replaces a prior one.*
