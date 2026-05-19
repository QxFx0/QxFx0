# QxFx0 Canonical Evidence Index

**Branch:** `main`  
**Index SHA:** `7af61768775593616b0df887b980be15308097ae`  
**Last updated:** 2026-05-20  
**Purpose:** Single source of truth for which evidence files are canonical vs. historical/superseded.

---

## Status: CORE_HEALTH_CONFIRMED_BY_INDIVIDUAL_GATES

`ci_gate_contract.sh` aggregate runner **INFRA-DEFERRED** on the
low-RAM environment (~10–11 GB).  All constituent gates that can run
within RAM/time constraints were executed individually and passed.

---

## Individual Gate Evidence (Low-RAM Profile)

| # | Gate | Command | Exit | Verdict | Evidence |
|---|------|---------|------|---------|----------|
| 1 | `cabal build all` | `cabal build all` | 0 | **PASS** | build log (implicit in linked test suites) |
| 2 | `cabal test qxfx0-test-fast` | `cabal test qxfx0-test-fast --test-options="+RTS -M8G -RTS"` | 0 | **PASS** | 462/462 cases, 0 errors, 0 failures |
| 3 | `cabal test qxfx0-test` (meta) | `cabal test qxfx0-test --test-options="+RTS -M8G -RTS"` | 0 | **PASS** | 589/589 cases, 0 errors, 0 failures |
| 4 | `check_architecture.sh` | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 5 | `gf_quality_gate.sh` | `bash scripts/gf_quality_gate.sh` | 0 | **PASS** | 0 errors, 0 warnings, all core topics present |
| 6 | `check_gf_render_path.sh` | `bash scripts/check_gf_render_path.sh` | 0 | **PASS** | 30 turns, 0 timeouts, fallback_rate=0.0000 |
| 7 | `check_en_render_path.sh` | `bash scripts/check_en_render_path.sh` | 0 | **PASS** | 30 turns, 0 timeouts, critical_mismatch=0 |

---

## INFRA-DEFERRED Gates (Low-RAM Aggregate Timeout)

These gates exceed local RAM/time envelope and are deferred to a
high-mem runner or CI environment:

| Gate | Reason |
|------|--------|
| `ci_gate_contract.sh` (aggregate) | Multi-suite orchestration exceeds 10–11 GB / 120 s on local runner |
| `check_generated_artifacts.sh` | Artifact inventory scan times out under local memory pressure |
| `check_lexicon.sh` | Lexicon coverage scan times out under local memory pressure |
| `release-smoke.sh` | Extended corpus replay exceeds local envelope |

---

## Extended Contract Evidence (FULL_SCIENTIFIC_GO)

**Status:** DEFERRED_INFRA — requires >=32 GB RAM runner, >=45 min timeout.

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
# Fast suite (low-RAM safe):
cabal test qxfx0-test-fast --test-options="+RTS -M8G -RTS"
# Expected: Cases: 462  Tried: 462  Errors: 0  Failures: 0

# Meta suite (low-RAM safe, longer):
cabal test qxfx0-test --test-options="+RTS -M8G -RTS"
# Expected: Cases: 589  Tried: 589  Errors: 0  Failures: 0

# Individual gates:
bash scripts/check_architecture.sh   # -> "Architecture check passed."
bash scripts/gf_quality_gate.sh      # -> "VERDICT: PASS"
bash scripts/check_gf_render_path.sh # -> "VERDICT: PASS"
bash scripts/check_en_render_path.sh # -> "VERDICT: PASS"
```

---

*Index maintained by release/reliability engineer. Update this file whenever a new canonical run replaces a prior one.*
