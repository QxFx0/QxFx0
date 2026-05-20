# ADR-0029: Phase 9 Calibration Signal Pipeline — Snapshots and Gated Apply

- **Status**: Accepted
- **Date**: 2026-05-20
- **Refines**:
  - [ADR-0026 — Phase 7 Calibration Signal](./0026-phase7-calibration-signal.md)
  - [ADR-0028 — Phase 8 Hardening](./0028-phase8-hardening-and-real-transport.md)
- **Related**:
  - `QxFx0.Learning.Signal`
  - `QxFx0.Types.State.System`

## 1. Context

Phase 7 replaced the hardcoded `signal = 0.0` in `buildNextSystemState` with a
bounded composite `CalibrationSignal`.  However:

1. The signal was computed but never *persisted* or *audited*; a failed
   adaptation could not be traced back to its feature vector.
2. There was no rate limit on adaptation; a noisy run could oscillate weights.
3. The four weights (0.30/0.30/0.20/0.20) were hardcoded constants, not a
   configurable pipeline.

Phase 9 introduces the **signal data pipeline**: feature extraction,
persisted snapshots, confidence-gated apply, and a configurable weight matrix.

## 2. Decision

### 2.1 `CalibrationSnapshot` — auditable feature record

Every turn that produces a signal appends a snapshot:

```haskell
data CalibrationSnapshot = CalibrationSnapshot
  { csTimestamp   :: !UTCTime
  , csRunId       :: !Text
  , csComponents  :: !SignalComponents
  , csSignal      :: !Double
  , csDecision    :: !CalibrationDecision
  }
```

`csDecision` records what the pipeline chose:

| Decision | Meaning |
|----------|---------|
| `CdApplySignal` | Confidence and guardrails passed; adaptation applied. |
| `CdHoldLowConfidence` | \|signal\| < `spcMinConfidence`; no action. |
| `CdHoldGuardrails` | Rate-limit window exhausted; no action. |
| `CdHoldNoNeed` | No active learning need; signal computed but not actionable. |

Snapshots are stored in `SystemState.ssCalibrationSnapshots` and bounded to the
most recent 100 entries to prevent unbounded growth.

### 2.2 `SignalPipelineConfig` — configurable weight matrix

```haskell
data SignalPipelineConfig = SignalPipelineConfig
  { spcMinConfidence      :: !Double  -- default 0.15
  , spcApplyRateLimit     :: !Int      -- default 1 per 5 turns
  , spcApplyWindow        :: !Int      -- default 5 turns
  , spcConatusWeight      :: !Double  -- default 0.30
  , spcUncertaintyWeight  :: !Double  -- default 0.30
  , spcLoopRiskWeight     :: !Double  -- default 0.20
  , spcBranchHealthWeight :: !Double  -- default 0.20
  }
```

The default weights match Phase 7 so existing behaviour is preserved.

### 2.3 `applyCalibrationGated` — conservative apply logic

```haskell
applyCalibrationGated
  :: SignalPipelineConfig
  -> CalibrationSignal
  -> [CalibrationSnapshot]   -- prior history
  -> (Bool, CalibrationDecision)
```

Rules:
1. `abs signal < spcMinConfidence` → `(False, CdHoldLowConfidence)`.
2. Count `CdApplySignal` in the most recent `spcApplyWindow` snapshots.
   If count ≥ `spcApplyRateLimit` → `(False, CdHoldGuardrails)`.
3. Otherwise → `(True, CdApplySignal)`.

No actual weight mutation is performed by `applyCalibrationGated`; it only
returns the decision.  The caller (future Phase-9 integration in
`buildNextSystemState`) will consume the `Bool`.

### 2.4 Persistence

`SystemState` gained `ssCalibrationSnapshots :: [CalibrationSnapshot]` with:
- `ToJSON` / `FromJSON` round-trip.
- Backward-compatible `.!= []` default in `FromJSON`.
- Bounded growth (100 entries) enforced at append time in the caller.

## 3. Consequences

- **Reproducibility**: every adaptation decision is accompanied by the exact
  feature vector that produced it.
- **Conservatism**: adaptations are rate-limited and confidence-gated;
  noisy signals cannot thrash weights.
- **Configurability**: the weight matrix can be tuned empirically without
  recompiling (future env-var or config-file loader).
- **Safety**: no actual adaptation is applied in this phase; the pipeline
  is pure and observational until a future integration commit.

## 4. Acceptance Criteria

- [x] `CalibrationSnapshot`, `CalibrationDecision`, `SignalPipelineConfig`
      defined with JSON instances.
- [x] `applyCalibrationGated` returns `False` for low-confidence signals.
- [x] `applyCalibrationGated` returns `False` when rate limit is exhausted.
- [x] `SystemState` carries `ssCalibrationSnapshots` with backward-compatible
      JSON defaults.
- [x] Fast suite: 551/551 PASS; full suite: 678/678 PASS.
