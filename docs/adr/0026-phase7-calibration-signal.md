# ADR-0026: Phase 7 Calibration Signal

- **Status**: Accepted
- **Date**: 2026-05-20
- **Refines**:
  - [ADR-0010 — Salience Controller](./0010-salience-controller.md)
  - [ADR-0025 — Rooted Knowledge Tree](./0025-rooted-knowledge-tree.md)
- **Related**:
  - `QxFx0.Learning.Signal`
  - `QxFx0.Core.TurnPipeline.Finalize.State.buildNextSystemState`

## 1. Context

After Phase 1 (WP1–WP5) and Phase 2 (persistence), the learning
architecture could detect deficits, select tools, propose calibrations,
and persist their lifecycle, but the actual *adaptation pressure*
sent to `adaptSalienceWeights` and `adaptFieldHeuristics` was a
hardcoded `signal = 0.0`.  This meant the system never adjusted its own
weights or heuristics based on empirical evidence.

We needed a bounded, explainable composite signal that:
1. Reflects empirical structural drift (not human-tuned heuristics).
2. Is clamped to a safe range so adaptation cannot run away.
3. Decomposes into independently inspectable components for debugging.

## 2. Decision

### 2.1 `CalibrationSignal` newtype

```haskell
newtype CalibrationSignal = CalibrationSignal { unCalibrationSignal :: Double }
  -- ^ Guaranteed clamped to [-1, 1] by construction.
```

The constructor is exposed, but all production call sites go through
`computeCalibrationSignal`, which enforces the clamp.

### 2.2 Four fixed-weight components

| Component | Weight | Source | Interpretation |
|-----------|--------|--------|----------------|
| Conatus trend | 30 % | `LearningNeedState` history slope | Deficit worsening → positive signal |
| Uncertainty trend | 30 % | Field counterfactual magnitude | Higher ambiguity → positive signal |
| Loop risk | 20 % | Repair-loop frequency over window | Frequent recovery → positive signal |
| Branch health (inverted) | 20 % | `KnowledgeTree` average health | Decaying tree → positive signal |

Formula:

```haskell
rawSignal = 0.30 * conatusTrend
          + 0.30 * uncertaintyTrend
          + 0.20 * loopRisk
          + 0.20 * (-branchHealthTrend)
signal    = clampRange (-1.0) 1.0 rawSignal
```

Each component is independently normalised to `[-1, 1]` before
weighting, so the formula remains dimensionless and interpretable.

### 2.3 Integration in `buildNextSystemState`

The hardcoded `signal = 0.0` is replaced with:

```haskell
let (calSignal, _comps) =
      computeCalibrationSignal
        needState
        counterfactual
        repairLoopCount
        windowSize
        knowledgeTree
    signal = unCalibrationSignal calSignal
```

The components tuple is discarded in production but available for
telemetry/debugging; a future observability extension can log
`SignalComponents` per turn.

### 2.4 Tool reliability overlay

`updateToolReliability` maintains a runtime `Map Text Double`:

- Acceptance → +0.05 (capped at 1.0)
- Rejection → −0.10 (floored at 0.0)

Three consecutive rejections drop a perfectly reliable tool from 1.0 to
0.70, making it less attractive than a fresh alternative.

`selectToolWithReliability` overlays the dynamic map onto static
`etReliability` before running `selectTool`.  The static profile is not
mutated; only the overlay map changes.

## 3. Consequences

- **Adaptation is now empirical**: weights and heuristics receive a
  non-zero, bounded signal when the system observes structural drift.
- **Interpretability**: the four components can be logged independently
  to diagnose why adaptation pressure rose or fell.
- **Safety**: clamping to `[-1, 1]` prevents runaway feedback.
- **Tool accountability**: dynamic reliability means tools that
  consistently produce bad proposals are naturally deprioritised.
- **No weakening of gates**: the signal is computed in pure code inside
  `Finalize.State`; no runtime thresholds are altered.

## 4. Acceptance Criteria

- [x] `CalibrationSignal` and `SignalComponents` defined with
  `computeCalibrationSignal`.
- [x] Signal is clamped to `[-1, 1]`; extreme inputs do not escape bounds.
- [x] `buildNextSystemState` uses computed signal instead of hardcoded
  `0.0`.
- [x] Tool reliability rises on accept (+0.05) and falls on reject
  (−0.10), with dynamic selection using `selectToolWithReliability`.
- [x] Architecture gate 12/12 PASS.
- [x] Fast suite: 527/527 PASS; full suite: 654/654 PASS.
