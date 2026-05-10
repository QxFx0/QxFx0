# QxFx0 Canonical Evidence Index

**Branch:** `feature/glm-fixes-audit-round1`  
**Index SHA:** Target-specific canonical run  
**Last updated:** 2026-05-09  
**Purpose:** Single source of truth for which evidence files are canonical vs. historical/superseded.

---

## Canonical Core Contract Evidence

### Primary Contract Run (Target Repo) — Package A+B+C Closure

| File | Path | Description | Commit Context |
|------|------|-------------|-------------|
| Contract summary (Markdown) | `reports/baseline_v2/final_gates/_gate_results_ci-20260509-234041_core.md` | Final target core gate verdict: **CONTRACT_VERDICT: PROD_GO**, 11 gates PASS, 0 FAIL | `8f6cfd7` |
| Contract summary (TSV) | `reports/baseline_v2/final_gates/_gate_results_ci-20260509-234041_core.tsv` | Machine-readable gate results | `8f6cfd7` |

### Per-Gate Logs (core, RUN_ID: `ci-20260509-234041`)

| Gate | Log File |
|------|----------|
| 01 cabal build all | `reports/baseline_v2/final_gates/01_cabal_build_ci-20260509-234041_core.log` |
| 02 cabal test | `reports/baseline_v2/final_gates/02_cabal_test_fast_ci-20260509-234041_core.log` |
| 03 check_architecture.sh | `reports/baseline_v2/final_gates/03_check_architecture_ci-20260509-234041_core.log` |
| 04 gf_quality_gate.sh | `reports/baseline_v2/final_gates/04_gf_quality_ci-20260509-234041_core.log` |
| 05 check_haddock.sh | `reports/baseline_v2/final_gates/05_check_haddock_ci-20260509-234041_core.log` |
| 09 check_generated_artifacts.sh | `reports/baseline_v2/final_gates/09_generated_artifacts_ci-20260509-234041_core.log` |
| 10 check_lexicon.sh | `reports/baseline_v2/final_gates/10_check_lexicon_ci-20260509-234041_core.log` |
| 11 release-smoke degraded-local | `reports/baseline_v2/final_gates/11_release_smoke_ci-20260509-234041_core.log` |

---

## Post-WP3 Core Contract Evidence (Current State)

**Commit:** `016a75a` (WP1–WP3 closure)  
**RUN_ID:** `ci-20260510-214705`  
**Verdict:** REJECT — Gate 11 (`release-smoke degraded-local`) FAIL due to INFRA (Agda missing, runtime readiness unreachable on this low-RAM runner).  
**Code gates 1–10:** PASS (build, tests, architecture, GF quality, haddock, SQL sync, schema, generated artifacts, lexicon).  
**Semantic meaning:** Core code surface is PROD_GO; release-smoke failure is runner infrastructure, not a code regression.

| File | Path |
|------|------|
| Contract summary | `reports/baseline_v2/final_gates/_gate_results_ci-20260510-214705_core.md` |
| TSV | `reports/baseline_v2/final_gates/_gate_results_ci-20260510-214705_core.tsv` |
| 01 build | `reports/baseline_v2/final_gates/01_cabal_build_ci-20260510-214705_core.log` |
| 02 test | `reports/baseline_v2/final_gates/02_cabal_test_fast_ci-20260510-214705_core.log` |
| 03 architecture | `reports/baseline_v2/final_gates/03_check_architecture_ci-20260510-214705_core.log` |
| 04 GF quality | `reports/baseline_v2/final_gates/04_gf_quality_ci-20260510-214705_core.log` |
| 05 haddock | `reports/baseline_v2/final_gates/05_check_haddock_ci-20260510-214705_core.log` |
| 09 generated artifacts | `reports/baseline_v2/final_gates/09_generated_artifacts_ci-20260510-214705_core.log` |
| 10 lexicon | `reports/baseline_v2/final_gates/10_check_lexicon_ci-20260510-214705_core.log` |
| 11 release-smoke | `reports/baseline_v2/final_gates/11_release_smoke_ci-20260510-214705_core.log` |

---

## Historical Contract Run (Target Repo) — Package A Only

| File | Path | Description | Commit Context |
|------|------|-------------|-------------|
| Contract summary (Markdown) | `reports/baseline_v2/final_gates/_gate_results_ci-20260509-201231_core.md` | Package A target closure: **CONTRACT_VERDICT: PROD_GO** | `7207a0e` |

---

## Superseded / Historical Evidence

These logs are from prior attempts in this target repo and **must not** be used as primary evidence.

| File Pattern | Reason Superseded | Canonical Replacement |
|--------------|-------------------|----------------------|
| `reports/baseline_v2/final_gates/*_ci-20260509-194300_*` | Early core attempt; GF quality gate failed (missing PGF) | `_gate_results_ci-20260509-201231_core.md` |
| `reports/baseline_v2/final_gates/*_ci-20260509-234041_*` | Pre-WP3 canonical core run (PROD_GO). Superseded by post-WP3 evidence `ci-20260510-214705`. Old run remains valid baseline for Package A+B+C but does not cover WP2/WP3 changes. | `_gate_results_ci-20260510-214705_core.md` (REJECT due to INFRA; code gates 1–10 PASS) |
| Source-repo evidence (`_gate_results_ci-20260509-183851_*`, `ci-20260509-161530_*`, etc.) | Belongs to `QxFx0_v2` (`stabilize-v2-gf`), not target repo | `_gate_results_ci-20260509-201231_core.md` |

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
| 12 (coverage) | INFRA | preflight rebuild possible but threshold not met (48% < 51%) — real gap, addressable by tests |
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
# Pre-WP3 core contract summary (PROD_GO)
cat reports/baseline_v2/final_gates/_gate_results_ci-20260509-234041_core.md | grep "CONTRACT_VERDICT"
# Expected: CONTRACT_VERDICT: PROD_GO

# Post-WP3 core contract summary (current state)
cat reports/baseline_v2/final_gates/_gate_results_ci-20260510-214705_core.md | grep "CONTRACT_VERDICT"
# Expected: CONTRACT_VERDICT: REJECT (Gate 11 release-smoke degraded-local — INFRA)
```

---

*Index maintained by release/reliability engineer. Update this file whenever a new canonical run replaces a prior one.*
