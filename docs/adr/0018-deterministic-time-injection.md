# ADR-0018: Deterministic Time Injection in Prepare Stage

- **Status**: Accepted
- **Date**: 2026-05-20
- **Refines**:
  - [ADR-0001 — Turn Effect State Machine](./0001-turn-effect-state-machine.md)
- **Related**:
  - `QxFx0.Core.TurnPipeline.Effects.PrepareStatic`
  - `QxFx0.Core.TurnPipeline.Protocol.prepareTurn`
  - `QxFx0.Runtime.Wiring.Context.TimeSource`

## 1. Context

The runtime already abstracts time through `TimeSource = IO UTCTime` in
`RuntimeContext`, and the effect interpreter resolves `TurnReqCurrentTime`
through `rcTimeSource`. However, `buildPrepareEffectPlan` — the pure
plan-construction function — had no access to the resolved time, and
`buildTurnInput` took `tiStartTime` from the `PrepareTimeline`, whose
`ptlStartTime` is resolved non-deterministically during `IO` effect
execution.

This made unit tests of `buildTurnInput` and downstream pure functions
fragile: any test that asserted on `tiStartTime` or on metrics derived
from it could not be made fully deterministic without mocking the
entire effect interpreter.

## 2. Decision

### 2.1 Inject resolved time into `PrepareStatic`

`PrepareStatic` gains a new field:

```haskell
, psCurrentTime :: !UTCTime
  -- ^ Phase C: deterministic time injection point.
  --   Captured at prepare-stage entry so 'buildTurnInput' can
  --   set 'tiStartTime' without relying on the resolved timeline.
  --   Enables deterministic unit tests with a fixed time source.
```

`buildPrepareEffectPlan`'s signature changes to accept the time up-front:

```haskell
buildPrepareEffectPlan :: SystemState -> Text -> UTCTime -> PrepareEffectPlan
```

### 2.2 Resolve time before plan construction

`prepareTurn` now resolves `currentTime` via the runtime effect boundary
*before* calling `buildPrepareEffectPlan`, and passes it in:

```haskell
prepareTurn pio ss input sessionId requestId = do
  currentTime <- resolvePrepareCurrentTime pio
  let prepareEffects = buildPrepareEffectPlan ss input currentTime
  prepareResults <- Prepare.resolvePrepareEffects pio prepareEffects
  let ti' = Prepare.buildTurnInput ss requestId sessionId prepareEffects prepareResults
      ts = Prepare.buildTurnSignals prepareResults
  pure (PreparedTurn ti' ts)
```

`resolvePrepareCurrentTime` uses the same `TurnReqCurrentTime` effect
that backs the existing timeline resolution, so tests can still override
it via the `QXFX0_TEST_FIXED_TIME` environment variable.

### 2.3 `buildTurnInput` uses `psCurrentTime` for `tiStartTime`

```haskell
TurnInput
  { tiStartTime = psCurrentTime prepareStatic
  -- ^ was: ptlStartTime timeline
  , ...
  }
```

The timeline timestamps remain in `PrepareEffectResults` for observability
and phase-timing metrics, but the canonical turn-start time is now pinned
at plan-construction and is reproducible in pure tests.

## 3. Consequences

- **Determinism**: unit tests can pass a fixed `UTCTime` directly to
  `buildPrepareEffectPlan` / `planPrepareEffects` and get the same
  `TurnInput` every time, without mocking IO.
- **Backward compatibility**: the `PrepareEffectResults` timeline is
  untouched; metrics that use `ptlStartTime` still work.
- **Test migration**: all call sites of `planPrepareEffects` and
  `buildPrepareEffectPlan` in the test suite were updated to pass
  `testEpochZero = UTCTime (ModifiedJulianDay 0) 0`.
- **Low-RAM safety**: no additional allocations; the `UTCTime` value
  was already computed, only its usage site changed.

## 4. Acceptance Criteria

- [x] `buildPrepareEffectPlan` signature updated and all call sites migrated.
- [x] `buildTurnInput` uses `psCurrentTime` instead of `ptlStartTime`.
- [x] Deterministic unit test `testPrepareCurrentTimeDeterministicInjection`
  verifies that injected time reaches `psCurrentTime`.
- [x] `cabal test qxfx0-test-fast` passes (469 tests).
