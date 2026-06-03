# Math Change Protocol

**Status:** Active (M5 first pass, 2026-06-03)
**Governed by:** `REGIME_GOVERNANCE.md §7`
**Machine-visible via:** `QxFx0.Types.RuntimeRegime.currentMathVersion`

---

## 1. Purpose

This document is the **machine-readable** companion to `REGIME_GOVERNANCE.md §4`.
Every change to a mathematical constant in the runtime MUST produce a row in
the change log below, and MUST be validated against the evidence requirements.

The protocol prevents silent mathematical drift: if `rrMathVersion` is not bumped
when a constant changes, `check_architecture.sh` rule [20] (promotion discipline)
will not catch it — but the calibration tests will.

---

## 2. Change log

| Version | Date | Change | Evidence | Files |
|---------|------|--------|----------|-------|
| 1 | 2026-05-18 | `emConatusStructuralFloor` corrected from 0.5 to 7.0 (codomain: `[~5, ~20+]` in production) | ADR-0012 §15.1 | `src/QxFx0/Self/Essence.hs` |

*Version 1 is the baseline — the correction that prompted this protocol.*

---

## 3. Protocol for adding a new change

1. Identify the change class from `REGIME_GOVERNANCE.md §4`
2. Collect the required evidence (corpus, replay parity, codomain check)
3. Increment `currentMathVersion` in `QxFx0.Types.RuntimeRegime`
4. Add a row to the change log above
5. Add a `Test.Suite.Calibration*` test that fails if the parameter drifts outside calibrated range
6. Run `cabal test qxfx0-test-fast` to confirm no regressions
7. Update `CALIBRATION_BACKLOG.md` to mark the parameter as "empirically calibrated"

---

## 4. GAP — parameters not yet calibrated

The following parameters are in scope for `rrMathVersion` bumps but have not yet
had empirical calibration passes. They remain at hand-set defaults.
When the production-trace corpus (F-09) is collected, these should be calibrated
in order:

1. `conatusGateThreshold` (Salience, codomain: `[~5, ~20+]`)
2. `weightResonance`, `weightAtmosphere`, etc. (SalienceWeights, codomain: `[0, 1]`)
3. `emAngstCommitmentThreshold` (EssenceModulation, needs production trace)
4. Conatus formula coefficients `w_m`, `w_c`, `w_t`, `λ`

See `CALIBRATION_BACKLOG.md §2` for the full list.
