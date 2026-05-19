# ADR-0017: Post-Commitment Bounded Self-Tuning

- **Status**: Accepted
- **Date**: 2026-05-20
- **Refines**:
  - [ADR-0010 — Salience Controller](./0010-salience-controller.md)
  - [ADR-0012 — Essence Commitment](./0012-essence-commitment.md)
- **Related**:
  - `QxFx0.Self.Salience.adaptSalienceWeights`
  - `QxFx0.Self.Field.adaptFieldHeuristics`
  - `QxFx0.Types.State.System` (mutable `ssSalienceWeights`, `ssFieldHeuristics`)

## 1. Context

ADR-0010 shipped the salience controller with compile-time constants
`defaultSalienceWeights` and `defaultFieldHeuristics`. ADR-0012 shipped
essence commitment: once the system commits to an `EssenceMode`, it
becomes structurally bound by admissible-family / tone / style guardrails.

Between these two layers there is a missing bridge: *after* commitment, the
system should be able to tune its own perceptual weights and heuristic
parameters based on turn outcomes, but only within strict guardrails that
prevent runaway drift, catastrophic forgetting, or adversarial exploitation.

This ADR commits the bounded adaptation mechanics. The empirical signal
generation (which weight to nudge and by how much) remains Phase-7 work;
what we commit here is the *infrastructure* — mutable fields, bounded
update rules, anti-drift guardrails, and the commitment gate.

## 2. Decision

We add two adaptation functions and two mutable fields.

### 2.1 Mutable fields on `SystemState`

`SystemState` gains:

```haskell
, ssSalienceWeights :: !SalienceWeights
  -- ^ Current runtime weights. Initialised to 'defaultSalienceWeights'.
  --   Updated only post-commitment by 'adaptSalienceWeights'.
, ssFieldHeuristics :: !FieldHeuristics
  -- ^ Current runtime heuristics. Initialised to 'defaultFieldHeuristics'.
  --   Updated only post-commitment by 'adaptFieldHeuristics'.
```

JSON round-trip uses `.!= defaultSalienceWeights` / `.!= defaultFieldHeuristics`
so old persisted states load safely.

### 2.2 Bounded update rule for `SalienceWeights`

```haskell
adaptSalienceWeights :: Double -> SalienceWeights -> SalienceWeights
```

Parameters:
- `signal` ∈ [-1, 1]: positive reinforces Holistic-bias weights,
  negative reinforces Formal-bias weights.
- Learning-rate cap: `lr = 0.02` per turn.
- Clamp: all adapted weights restricted to [0.0, 2.0].
- Anti-drift: total deviation from `defaultSalienceWeights` per weight
  cannot exceed ±1.0.
- Identity preservation: when `signal = 0.0`, the function is strict
  identity (verified by property test).

### 2.3 Bounded update rule for `FieldHeuristics`

```haskell
adaptFieldHeuristics :: Double -> FieldHeuristics -> FieldHeuristics
```

Same `signal` domain and `lr = 0.02`. Only the `Double` fields are adapted;
`Int` fields (`fhNarrativeWindowSize`) are left unchanged to avoid brittle
integer drift. Each adapted field is clamped to [0.0, 1.0] and further
constrained to ±0.5 of its default.

### 2.4 Commitment gate

The update is injected in `buildNextSystemState` and fires **only** when
the pre-turn essence is `EssenceCommitted`:

```haskell
(adaptedWeights, adaptedHeuristics) =
  case nextEssence of
    EssenceCommitted _ _ ->
      let signal = 0.0  -- empirical calibration deferred to Phase 7
      in ( adaptSalienceWeights signal (ssSalienceWeights ss)
         , adaptFieldHeuristics    signal (ssFieldHeuristics ss)
         )
    _ -> (ssSalienceWeights ss, ssFieldHeuristics ss)
```

Uncommitted trajectories keep the defaults exactly, guaranteeing that
pre-commitment behaviour is reproducible and calibration-free.

## 3. Consequences

- **Determinism**: identical `(SystemState, signal)` inputs produce identical
  outputs. The signal is currently fixed at `0.0`, so the system is still
  fully deterministic.
- **Backward compatibility**: old persisted states load with defaults;
  the new fields are invisible to downstream stages until Phase 7
  starts using non-zero signals.
- **Testability**: QuickCheck properties verify clamping, anti-drift,
  and identity-at-zero-signal.
- **No runtime drift risk**: with signal=0.0 the only possible change is
  anti-drift pulling weights back into band, which is safe. When Phase 7
  introduces non-zero signals, the same guardrails apply.

## 4. Acceptance Criteria

- [x] `SystemState` round-trips through JSON with the new fields.
- [x] `adaptSalienceWeights` property tests: identity at 0, clamp [0,2],
  anti-drift ±1.0.
- [x] `adaptFieldHeuristics` property tests: identity at 0, clamp [0,1],
  anti-drift ±0.5.
- [x] `buildNextSystemState` only adapts when `EssenceCommitted`.
- [x] `cabal test qxfx0-test-fast` passes (469 tests including new ones).
