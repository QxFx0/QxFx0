# ADR-0045: Conatus Gate Integration (P1)

- **Status**: Accepted
- **Date**: 2026-06-04
- **Refines**:
  - [ADR-0007 — Dual-mode conatus-aware architecture](./0007-dual-mode-conatus.md)
  - [ADR-0010 — Salience Controller](./0010-salience-controller.md)
- **Related**:
  - `QxFx0.Self.Conatus` (Phase 2, scalar functional)
  - `QxFx0.Core.TurnRouting.Cascade` (routing cascade)
  - `Test.Suite.ConatusGate` (anti-rot tests)

## 1. Context

ADR-0007 introduced the Conatus functional as a scalar measure of structural
self-identity, computed from the `SelfBlanket` and violation list. Phase 5
wired Conatus into the Salience controller, which produces a `DrivenByConatusGate`
driver when energy is critically low.

However, the integration was incomplete: `ConatusEnergy` was computed, traced
(`trcConatusEnergy`), and influenced the salience verdict, but **did not
directly restrict family selection**. The `DrivenByConatusGate` flag existed
in the trace but was only checked in `applyPrincipledFamilyModulated` and
`applyGuardGatingModulated` to force the formal path — it did not prohibit
high-risk families.

The gap: rhetoric promised "self-preservation routing" when energy is low;
implementation computed a number and mostly ignored it. A system with
`ceScalar = 0.5` (critically low) could still select `CMConfront` or
`CMHypothesis`, violating the self-preservation contract.

## 2. Decision

We close the gap by wiring `ConatusEnergy` directly into the routing cascade
with an explicit threshold check and family restriction:

### 2.1. Threshold Constant

Add `lowEnergyThreshold :: Double` to `QxFx0.Self.Conatus`:

```haskell
-- | Threshold below which Conatus energy is considered "low" and
-- triggers self-preservation routing restrictions.
lowEnergyThreshold :: Double
lowEnergyThreshold = 3.0
```

**Calibration rationale**: A healthy blanket with moderate morphology (20
entries), some identity claims (5), and a few turns (10) yields:

```
C = 1.0 * log(21) + 0.5 * log(6) + 0.25 * log(11) ≈ 4.5
```

A blanket below 3.0 has either suffered violations (penalty term) or has
minimal structural substance, warranting conservative routing.

### 2.2. Cascade Integration

Modify `runFamilyCascade` in `QxFx0.Core.TurnRouting.Cascade`:

1. Accept `ConatusEnergy` as a parameter (threaded from `routeFamily` via
   `routeFamilyWithSelfVerdict`).
2. Add a new cascade stage `familyAfterConatusGate` between
   `familyAfterGuard` and `familyAfterDoubt`.
3. When `ceScalar conatusEnergy < lowEnergyThreshold`, apply
   `applyConatusGateRestriction` to map high-risk families to restorative
   alternatives.

### 2.3. Family Restriction Mapping

```haskell
applyConatusGateRestriction :: CanonicalMoveFamily -> CanonicalMoveFamily
applyConatusGateRestriction family =
  case family of
    CMConfront    -> CMContact     -- restorative engagement
    CMHypothesis  -> CMAnchor      -- grounding in established facts
    CMDistinguish -> CMRepair      -- structural recovery
    _             -> family        -- already safe or restorative
```

**Prohibited families** (high-risk, require structural integrity):
- `CMConfront` — adversarial stance, requires agency
- `CMHypothesis` — speculative reasoning, requires cognitive capacity
- `CMDistinguish` — fine-grained differentiation, requires stable identity

**Restorative families** (always allowed, rebuild structural integrity):
- `CMContact` — basic engagement, minimal cognitive load
- `CMAnchor` — grounding in established facts, stabilizing
- `CMRepair` — explicit structural recovery

**Safe families** (neither high-risk nor explicitly restorative):
- `CMClarify` — information-seeking, low risk
- `CMGround` — assertion of established facts, stable
- `CMDeepen` — elaboration, moderate risk but not prohibited

### 2.4. Anti-Rot Tests

`Test.Suite.ConatusGate` provides 11 property tests:

1. **Mapping tests**: Verify each high-risk family maps to the correct
   restorative alternative.
2. **Preservation tests**: Verify restorative and safe families are unchanged.
3. **Property tests**:
   - All high-risk families map to restorative families.
   - Low-energy blanket is below threshold.
   - High-energy blanket is above threshold.
   - Restriction is idempotent.
   - Threshold is in sensible range [1, 10].
4. **Anti-rot**: Function is total on all families.

If the wire is disconnected (e.g., `applyConatusGateRestriction` is removed
or not called), these tests fail.

## 3. Consequences

### 3.1. Positive

- **Gap closed**: Conatus computation now influences routing behaviour, not
  just trace observability.
- **Self-preservation**: Low-energy states trigger conservative routing,
  preventing further structural degradation.
- **Testable**: Property tests verify the restriction is applied correctly
  and fail if disconnected.
- **Deterministic**: Threshold check is pure, no wallclock or random.
- **Calibratable**: `lowEnergyThreshold` is a single tunable constant.

### 3.2. Negative

- **Threshold uncalibrated**: Default value of 3.0 is editorial judgement,
  not corpus-driven. Phase 7 calibration work (deferred) will tune this
  against production trace corpora.
- **Mapping is fixed**: The high-risk → restorative mapping is hardcoded.
  Future work may make this configurable or learnable.

### 3.3. Neutral

- **Baseline unchanged**: The restriction only applies when
  `ceScalar < lowEnergyThreshold`. Healthy blankets (the common case) are
  unaffected.
- **Trace visibility**: `trcConatusEnergy` already exists; no new trace
  fields needed for P1.

## 4. Implementation Notes

### 4.1. Signature Changes

```haskell
-- Before:
runFamilyCascade :: RoutingPhase -> SystemState -> UserState
                 -> InputPropositionFrame -> AtomSet -> [Text] -> Text
                 -> Maybe ConsciousnessNarrative -> Double -> Bool
                 -> Salience -> Double -> [EpisodicEvent]
                 -> FamilyCascade

-- After:
runFamilyCascade :: RoutingPhase -> SystemState -> UserState
                 -> InputPropositionFrame -> AtomSet -> [Text] -> Text
                 -> Maybe ConsciousnessNarrative -> Double -> Bool
                 -> Salience -> ConatusEnergy -> Double -> [EpisodicEvent]
                 -> FamilyCascade
```

`ConatusEnergy` is inserted between `Salience` and `Double` (doubt score).

### 4.2. Cascade Order

The new stage is positioned **after** guard gating but **before** doubt-driven
override:

1. Parser-locked family (if high confidence)
2. Identity signal hint
3. Narrative hint
4. Intuition hint
5. Principled mode (with salience modulation)
6. Guard gating (with salience modulation)
7. **Conatus gate restriction** ← NEW
8. Doubt-driven CMClarify override (WP-D)
9. Anti-stuck recovery
10. Nix-blocked CMRepair fallback

This order ensures that self-preservation takes precedence over doubt-driven
clarification but respects parser-locked families and guard-driven repairs.

### 4.3. Test Coverage

- **Unit tests**: 11 tests in `Test.Suite.ConatusGate`
- **Integration**: Existing routing tests cover the cascade; no new
  integration tests needed for P1.
- **Baseline**: 1024 existing test cases remain green (14 baseline failures
  unchanged).

## 5. Future Work

### 5.1. Phase 7 Calibration (Deferred)

Tune `lowEnergyThreshold` against production trace corpora:
- Collect `(ceScalar, family, outcome)` triples from live sessions.
- Identify threshold that maximizes recovery success rate.
- Update `lowEnergyThreshold` and document in calibration report.

### 5.2. Learnable Mapping (Deferred)

Replace fixed `applyConatusGateRestriction` with a learned policy:
- Train a classifier: `(ConatusEnergy, CanonicalMoveFamily) → Bool` (allow/prohibit).
- Use outcome markers (acceptance, rejection, recovery) as supervision signal.
- Requires Phase 8 external learning loop (ADR-0027).

### 5.3. Trace Visibility (P8)

P8 (Audit Trail Visibility) will add trace fields for all active WP signals.
For Conatus gate, consider adding:
- `trcConatusGateTriggered :: Bool` — whether restriction was applied
- `trcConatusGateOriginalFamily :: Maybe CanonicalMoveFamily` — family before restriction

## 6. References

- **Spec**: `docs/specs/track-I-closure-remaining-p1-p8-p0-p6-p4.md` §P1
- **Theory**: `docs/THEORY.md` §4.2 (Conatus functional)
- **Implementation**:
  - `src/QxFx0/Self/Conatus.hs` — threshold constant
  - `src/QxFx0/Core/TurnRouting/Cascade.hs` — cascade integration
  - `test/Test/Suite/ConatusGate.hs` — anti-rot tests
- **Related ADRs**:
  - ADR-0007 — Conatus functional definition
  - ADR-0010 — Salience controller (Conatus gate driver)
  - ADR-0042 — Anti-rot standard (test discipline)