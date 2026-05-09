# QxFx0 Canonical Evidence Index

**Branch:** `feature/glm-fixes-audit-round1`  
**Index SHA:** Target-specific canonical run  
**Last updated:** 2026-05-09  
**Purpose:** Single source of truth for which evidence files are canonical vs. historical/superseded.

---

## Canonical Core Contract Evidence (PROD_GO)

### Primary Contract Run (Target Repo)

| File | Path | Description | Commit Context |
|------|------|-------------|-------------|
| Contract summary (Markdown) | `reports/baseline_v2/final_gates/_gate_results_ci-20260509-201231_core.md` | Final target core gate verdict: **CONTRACT_VERDICT: PROD_GO**, 11 gates PASS, 0 FAIL | `7207a0e` |
| Contract summary (TSV) | `reports/baseline_v2/final_gates/_gate_results_ci-20260509-201231_core.tsv` | Machine-readable gate results | `7207a0e` |
| Full stdout log | `/tmp/ci_contract_target_final.log` | Complete `ci_gate_contract.sh` stdout (core profile) | captured 2026-05-09 20:28 |

### Per-Gate Logs (core, RUN_ID: `ci-20260509-201231`)

| Gate | Log File |
|------|----------|
| 01 cabal build all | `reports/baseline_v2/final_gates/01_cabal_build_ci-20260509-201231_core.log` |
| 02 cabal test | `reports/baseline_v2/final_gates/02_cabal_test_fast_ci-20260509-201231_core.log` |
| 03 check_architecture.sh | `reports/baseline_v2/final_gates/03_check_architecture_ci-20260509-201231_core.log` |
| 04 gf_quality_gate.sh | `reports/baseline_v2/final_gates/04_gf_quality_ci-20260509-201231_core.log` |
| 05 check_haddock.sh | `reports/baseline_v2/final_gates/05_check_haddock_ci-20260509-201231_core.log` |
| 09 check_generated_artifacts.sh | `reports/baseline_v2/final_gates/09_generated_artifacts_ci-20260509-201231_core.log` |
| 10 check_lexicon.sh | `reports/baseline_v2/final_gates/10_check_lexicon_ci-20260509-201231_core.log` |
| 11 release-smoke degraded-local | `reports/baseline_v2/final_gates/11_release_smoke_ci-20260509-201231_core.log` |

---

## Superseded / Historical Evidence

These logs are from prior attempts in this target repo and **must not** be used as primary evidence.

| File Pattern | Reason Superseded | Canonical Replacement |
|--------------|-------------------|----------------------|
| `reports/baseline_v2/final_gates/*_ci-20260509-194300_*` | Early core attempt; GF quality gate failed (missing PGF) | `_gate_results_ci-20260509-201231_core.md` |
| Source-repo evidence (`_gate_results_ci-20260509-183851_*`, `ci-20260509-161530_*`, etc.) | Belongs to `QxFx0_v2` (`stabilize-v2-gf`), not target repo | `_gate_results_ci-20260509-201231_core.md` |

---

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
# Core contract summary (target)
cat reports/baseline_v2/final_gates/_gate_results_ci-20260509-201231_core.md | grep "CONTRACT_VERDICT"
# Expected: CONTRACT_VERDICT: PROD_GO
```

---

*Index maintained by release/reliability engineer. Update this file whenever a new canonical run replaces a prior one.*
