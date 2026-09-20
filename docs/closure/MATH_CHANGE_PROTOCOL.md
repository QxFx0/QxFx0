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
| 2 | 2026-08-07 | A-slice: `ConatusComponents` gains `ccSelfDivergence`, self-consistency penalty as energy fraction, `SelfDivergenceTuning` (0.035/0.35/8) | A-slice A3 + `Test.Suite.SelfDivergence` | `src/QxFx0/Self/SelfDivergence.hs`, `src/QxFx0/Types/Self/SelfDivergence.hs` |
| 3 | 2026-08-23 | Concept-v3: user-R5 encoder v1 (frozen), viability contour, move-graph effect matrix, `transitionUserR5` | concept-v3 regime + `Test.Suite.{CrisisGuard,UserR5,OntologicalAxis,MoveGraph}` | `src/QxFx0/User/R5.hs`, `src/QxFx0/Types/User/R5.hs`, `src/QxFx0/Semantic/MoveGraph.hs` |
| 4 | 2026-09-20 | Move-layer tightening (pre-registered probe F1 = 0.00): `moveDriftMargin` 0.10 → 0.20, bare negative acts no longer fire without affirm-gate passage or earned drift | `docs/closure/MOVE_PROBE_PREREG.md` + human-v1 labels (30 turns) + `Test.Suite.MoveGraph` v4 pins | `src/QxFx0/Semantic/MoveGraph.hs`, `src/QxFx0/Types/RuntimeRegime.hs` |

*Version 1 is the baseline — the correction that prompted this protocol.*

---

## 3. Protocol for adding a new change

1. Identify the change class from `REGIME_GOVERNANCE.md §4`
2. Collect the required evidence (corpus, replay parity, codomain check)
3. Increment `currentMathVersion` in `QxFx0.Types.RuntimeRegime`
4. Add a row to the change log above
5. Add a regression lock: `Test.Suite.Calibration*` once Package 11 lands; until then pin the parameter in its owning suite (all current bumps are pinned this way — e.g. sdt invariants in `Test.Suite.SelfDivergence`, lexicon/weight pins in `Test.Suite.{Composition,Assembly}`)
6. Run `cabal test qxfx0-test-fast` to confirm no regressions
7. Update `CALIBRATION_BACKLOG.md` to mark the parameter as "empirically calibrated"

---

## 4. GAP — parameters not yet calibrated

The following parameters are in scope for `rrMathVersion` bumps but have not yet
had empirical calibration passes. They remain at hand-set defaults.
When the production-trace corpus (F-09) is collected, these should be calibrated
in order:

1. `conatusGateThreshold` (Salience; trips at 0.0 — `ceScalar` can go negative under heavy violation per `Self/Salience.hs:190`, healthy band is `[~5, ~20+]`)
2. `weightResonance`, `weightAtmosphere`, etc. (SalienceWeights, codomain: `[0, 1]`)
3. `emAngstCommitmentThreshold` (EssenceModulation, needs production trace)
4. Conatus formula coefficients `w_m`, `w_c`, `w_t`, `λ`

See `CALIBRATION_BACKLOG.md §2` for the full list.
