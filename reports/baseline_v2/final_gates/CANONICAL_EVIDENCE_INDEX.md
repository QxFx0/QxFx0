# QxFx0 Canonical Evidence Index

**Branch:** `main`  
**Index SHA:** `d4563391aadd9e7cc206e7e29750cdda4549b831`  
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
| 2 | `cabal test qxfx0-test-fast` | `cabal test qxfx0-test-fast --test-options="+RTS -M8G -RTS"` | 0 | **PASS** | 469/469 cases, 0 errors, 0 failures |
| 3 | `cabal test qxfx0-test` (meta) | `cabal test qxfx0-test --test-options="+RTS -M8G -RTS"` | 0 | **PASS** | 596/596 cases, 0 errors, 0 failures |
| 4 | `check_architecture.sh` | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 5 | `gf_quality_gate.sh` | `bash scripts/gf_quality_gate.sh` | 0 | **PASS** | 0 errors, 0 warnings, all core topics present |
| 6 | `check_gf_render_path.sh` | `bash scripts/check_gf_render_path.sh` | 0 | **PASS** | 30 turns, 0 timeouts, fallback_rate=0.0000 |
| 7 | `check_en_render_path.sh` | `bash scripts/check_en_render_path.sh` | 0 | **PASS** | 30 turns, 0 timeouts, intent_fit=1.0000, fallback=0.0000 |
| 8 | `check_generated_artifacts.sh` | `bash scripts/check_generated_artifacts.sh` | 0 | **PASS** | PGF present, GF compile skipped (infra) |
| 9 | `check_lexicon.sh` | `bash scripts/check_lexicon.sh` | 0 | **PASS** | score=10.00, lemmas=3756, all quality metrics OK |
| 10 | `nix run .#typecheck-agda` | `nix run .#typecheck-agda` | 0 | **PASS** | 6/6 modules: R5Core, Sovereignty, Legitimacy, LexiconData, LexiconProof, EssenceFormalization |
| 11 | `nix flake check` | `nix flake check` | 0 | **PASS** | with pre-existing pgf2 broken warning (non-blocking) |

---

## INFRA-DEFERRED Gates (Low-RAM Aggregate Timeout)

These gates exceed local RAM/time envelope and are deferred to a
high-mem runner or CI environment:

| Gate | Reason |
|------|--------|
| `ci_gate_contract.sh` (aggregate) | Multi-suite orchestration exceeds 10–11 GB / 300 s on local runner |
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
# Expected: Cases: 469  Tried: 469  Errors: 0  Failures: 0

# Meta suite (low-RAM safe, longer):
cabal test qxfx0-test --test-options="+RTS -M8G -RTS"
# Expected: Cases: 596  Tried: 596  Errors: 0  Failures: 0

# Individual gates:
bash scripts/check_architecture.sh      # -> "Architecture check passed."
bash scripts/gf_quality_gate.sh         # -> "VERDICT: PASS"
bash scripts/check_gf_render_path.sh    # -> "VERDICT: PASS"
bash scripts/check_en_render_path.sh    # -> "VERDICT: PASS"
bash scripts/check_generated_artifacts.sh # -> "generated-artifact gate passed"
bash scripts/check_lexicon.sh           # -> "lexicon check passed"
```

---

*Index maintained by release/reliability engineer. Update this file whenever a new canonical run replaces a prior one.*
