# QxFx0 Canonical Evidence Index

**Branch:** `main`  
**Index SHA:** `4191d1be7510cd6b5f8490c012dad4a54f78a71f`  
**Last updated:** 2026-05-19  
**Purpose:** Single source of truth for which evidence files are canonical vs. historical/superseded.

---

## Status: Awaiting Fresh Canonical Run

The `reports/baseline_v2/final_gates/` directory is **empty** as of
2026-05-19.  No canonical gate logs have been produced on the current
HEAD (`4191d1be7510cd6b5f8490c012dad4a54f78a71f`).  The previous index
referenced a run (`ci-20260516-042551`) and commit
(`1fb4ef21e90d6f49be5d7712faf0fd13d20ca0d3`) for which no log files
exist in the repository.

### Required canonical run (PROD_GO)

To populate this index, execute:

```bash
bash scripts/ci_gate_contract.sh
# Profile: core
# Expected artifact paths:
#   reports/baseline_v2/final_gates/_gate_results_<RUN_ID>_core.md
#   reports/baseline_v2/final_gates/_gate_results_<RUN_ID>_core.tsv
#   reports/baseline_v2/final_gates/01_cabal_build_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/02_cabal_test_fast_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/03_check_architecture_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/04_gf_quality_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/04a_gf_render_path_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/04b_en_render_path_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/05_check_haddock_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/09_generated_artifacts_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/10_check_lexicon_<RUN_ID>_core.log
#   reports/baseline_v2/final_gates/11_release_smoke_<RUN_ID>_core.log
```

---

## Superseded / Historical Evidence

No prior canonical run logs are present in this repository at
`reports/baseline_v2/final_gates/`.  Historical evidence from prior
development cycles (pre-Phase-10) may exist in:
- `reports/` (other subdirectories)
- CI artifact archives (if uploaded)
- Source-repo (`QxFx0_v2`) history

These **must not** be used as primary evidence for the current HEAD.

---

## Extended-LowRAM Contract Evidence

**Status:** NOT PRODUCED — no `extended-lowram` profile logs exist.

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
# After a canonical run is produced:
cat reports/baseline_v2/final_gates/_gate_results_<RUN_ID>_core.md | grep "CONTRACT_VERDICT"
# Expected: CONTRACT_VERDICT: PROD_GO
```

---

*Index maintained by release/reliability engineer. Update this file whenever a new canonical run replaces a prior one.*
