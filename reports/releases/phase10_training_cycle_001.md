# Phase 10 Training Cycle 001 Report

**Date:** 2026-05-21  
**Scope:** First offline training cycle: trace extraction → candidate generation → proxy evaluation → promotion/rollback  
**Commit range:** `3f0f09f..179bd99` (inclusive)  
**Parent:** `3f0f09f` (Phase 9 MVP)

---

## Executive Verdict

| Gate | Verdict |
|------|---------|
| TRAINING_CYCLE_001 | **PASS** |
| CANDIDATE_GENERATION | **PASS** |
| PROXY_EVALUATION | **PASS** |
| PROMOTION_ROLLBACK | **PASS** |
| CORE_HEALTH | **PASS** |

---

## What Changed

### New module: `QxFx0.Learning.TrainingCycle`

A pure, offline pipeline that turns `SystemState` history into calibration decisions without live-turn mutation.

**Dataset extraction** (`extractTrainingDataset`):
- Consumes `ssCalibrationSnapshots` from `SystemState`
- Produces `TrainingDataset` with 70/30 train/eval split
- Computes `DatasetStats`: total turns, accepted/rejected proposals, transport errors, fallback-heavy sessions

**Candidate generation** (`generateCandidates`):
- Uses existing `adaptSalienceWeights` / `adaptFieldHeuristics` with a fixed signal grid
- 6 signals × 2 parameter types = **12 candidates** (bounded, well under 30)
- Each candidate is versioned (`CalibrationId`), typed (`CandidateSalience` / `CandidateField`), and provenanced (source run ID, timestamp)

**Proxy evaluation** (`evaluateCandidate`):
- Computes conservatism factor from parameter deltas
- Adjusts historical need levels asymmetrically (damp high > 0.5, slightly boost low < 0.5)
- Measures 4 delta metrics: conatus trend, uncertainty, repair-loop frequency, reject rate
- Net score: weighted composite (0.35/0.25/0.25/0.15)
- Strict fail-closed acceptance: all deltas ≤ 0.05, no significant regression, |net score| ≥ 0.001
- Typed reject reasons: `TrRegressionConatus`, `TrRegressionUncertainty`, `TrRegressionRepair`, `TrRegressionRejectRate`, `TrUnstableVariance`, `TrInsufficientSignal`

**Promotion/rollback** (`promoteCandidate` / `rollbackTrainingCycle`):
- `promoteCandidate` wraps the winner in an `Accepted` `CalibrationEntry` with `prevId` linkage
- `rollbackTrainingCycle` marks `RolledBack`, updates decided turn, and returns the previous `CalibrationId`

**Outcome telemetry** (`TrainingCycleOutcome`):
- `tcoCycleId` — human-readable identifier
- `tcoDatasetStats` — extracted statistics
- `tcoCandidates` — full evaluation table sorted by net score
- `tcoPromotedCandidate` — single winner or `Nothing`
- `tcoPreviousVersion` — version before promotion
- `tcoRollbackEntry` — rollback simulation result (test-only)

### New tests: `Test.Suite.TrainingCycle`

10 tests covering:
1. Dataset extractor deterministic on fixed input
2. Candidate generation bounded and reproducible (12 candidates)
3. Sandbox evaluation rejects regressing candidates
4. Sandbox evaluation accepts non-regressing improving candidates
5. Promotion updates version pointers correctly
6. Rollback restores previous version
7. Telemetry carries cycle/candidate/outcome fields
8. Full end-to-end cycle with explicit dataset
9. Dataset stats accuracy
10. Typed reject reasons render correctly

---

## Dataset Stats (from test fixture)

The test fixtures simulate a dataset of 5–10 historical traces. On a real `SystemState` with calibration snapshot history, the extractor produces actual statistics. Example from the `testTelemetryFieldsPresent` test:

| Stat | Value |
|------|-------|
| Total turns | 5 |
| Accepted proposals | 2 |
| Rejected proposals | 2 |
| Transport errors | 1 (proxy: near-zero signal with non-NoNeed decision) |
| Fallback-heavy sessions | 0 |

---

## Candidate Table (from test fixture)

| Candidate # | Type | Signal | Verdict | Reject Reason (if any) |
|-------------|------|--------|---------|--------------------------|
| 1–12 | Salience / Field | ±0.30, ±0.20, ±0.10 | Varies | `TrInsufficientSignal` if eval < 3 traces; otherwise depends on proxy deltas |

On the `testRunFullCycleEndToEnd` fixture (10 traces, mixed levels, improving trend), **multiple candidates are accepted** and the best (highest net score) is promoted.

---

## Before/After Metrics

The proxy evaluation compares baseline vs candidate-adjusted metrics on the eval subset. On the acceptance test fixture:

| Metric | Baseline | Adjusted (conservative candidate) | Delta | Direction |
|--------|----------|-----------------------------------|-------|-----------|
| Conatus trend | -0.05 | -0.05 | 0.00 | neutral |
| Uncertainty (oscillation) | 0.30 | 0.255 | -0.045 | improved |
| Repair-loop freq | 0.00 | 0.00 | 0.00 | neutral |
| Reject rate | 1.00 | 1.00 | 0.00 | neutral |
| **Net score** | — | **0.0034** | — | positive, accepted |

---

## Gate Verification

| # | Command | Exit | Verdict | Evidence |
|---|---------|------|---------|----------|
| 1 | `cabal build all` | 0 | **PASS** | 0 compilation errors |
| 2 | `cabal test qxfx0-test-fast` | 0 | **PASS** | 574/574 cases, 0 errors, 0 failures |
| 3 | `cabal test qxfx0-test` | 0 | **PASS** | 701/701 cases, 0 errors, 0 failures |
| 4 | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 5 | `bash scripts/gf_quality_gate.sh` | 0 | **PASS** | 0 errors, 0 warnings, PGF 312662 bytes |

---

## Files Changed

| File | Lines | Nature |
|------|-------|--------|
| `src/QxFx0/Learning/TrainingCycle.hs` | +567 | New module: dataset extraction, candidate generation, proxy evaluation, promotion/rollback |
| `test/Test/Suite/TrainingCycle.hs` | +267 | 10 test cases for the training cycle |
| `test/TestMainUnit.hs` | +2 | Import + wire `trainingCycleTests` |
| `test/TestMainFast.hs` | +2 | Import + wire `trainingCycleTests` |
| `test/TestMain.hs` | +2 | Import + wire `trainingCycleTests` |
| `qxfx0.cabal` | +2 | Expose `QxFx0.Learning.TrainingCycle`, add `Test.Suite.TrainingCycle` to test other-modules |
| `docs/adr/0031-phase10-offline-training-cycle.md` | +143 | ADR: architecture, proxy evaluation, acceptance policy, residual risks |

---

## Regression Status

| Regression | Status |
|------------|--------|
| Fast suite (baseline 564) | **PASS** — now 574/574 |
| Full suite (baseline 691) | **PASS** — now 701/701 |
| Architecture gate | **PASS** — 12/12 invariants |
| GF quality gate | **PASS** — 0 errors, 0 warnings |
| Commitment law / refused_commitment | **PASS** — no changes to Essence or commitment logic |
| Exploratory learning path (Phase 9) | **PASS** — no changes to existing exploratory code |

---

## Residual Risks

1. **Proxy fidelity**: the lightweight proxy does not replay full turns. A candidate scoring well on proxy metrics might regress under real routing. Mitigation: strict non-regression policy (all deltas ≤ 0.05) and small bounded perturbations. Future: full N-turn replay on high-RAM runner.

2. **Signal grid coarseness**: only 6 perturbation signals. The true optimal may lie between grid points. Mitigation: grid is intentionally coarse to limit compute. Future: finer grid or gradient-based search.

3. **Fixed integer parameters**: `adaptFieldHeuristics` only adapts `Double` fields; window-size `Int` fields are fixed. Future: integer-grid search if window-size tuning becomes critical.

4. **Positional 70/30 split**: not randomised; small trace counts (< 20) may produce biased splits. Mitigation: `tccMinEvalTraces = 3` provides a floor. Future: stratified sampling by decision type.

5. **No candidate applied to live state yet**: `runTrainingCycle` returns an outcome but does not automatically mutate `ssSalienceWeights` or `ssFieldHeuristics`. The caller must explicitly promote. This is by design (offline-only) but means the cycle is currently observational.

---

## How to Reproduce

```bash
# Build
cabal build all

# Fast suite
cabal test qxfx0-test-fast --ghc-options="-O0" +RTS -M8G
# Expected: Cases: 574  Tried: 574  Errors: 0  Failures: 0

# Full suite
cabal test qxfx0-test --ghc-options="-O0" +RTS -M8G
# Expected: Cases: 701  Tried: 701  Errors: 0  Failures: 0

# Architecture gate
bash scripts/check_architecture.sh
# Expected: Architecture check passed.

# GF quality gate
bash scripts/gf_quality_gate.sh
# Expected: VERDICT: PASS
```

---

*Report generated by release pipeline. Commit `179bd99` on branch `main`.*
