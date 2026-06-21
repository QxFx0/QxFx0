# ADR-0048: Promote Derived Inference

- **Status**: Accepted (2026-06-04)
- **Date**: 2026-06-04
- **Promoted**: 2026-06-04 (P0 Stage 6)
- **Related**:
  - `src/QxFx0/Semantic/Logic.hs` (`derivedInferenceActive`, `deriveAtoms`)
  - `src/QxFx0/Core/TurnPipeline/Finalize/Projection.hs` (`trcDerivedInferenceCount`)
  - `docs/specs/cognitive-and-substrate-roadmap-v3.1.md` (WP-G)
  - `docs/adr/0046-audit-trail-visibility.md` (trace field definition)

## 1. Context

`QxFx0.Semantic.Logic.deriveAtoms` implements multi-step atom derivation patterns
that feed into the semantic rule table. The function derives additional atoms
from A ∧ B combinations (e.g., `hasProperty(X, edible) ∧ hasProperty(X, plant)`
→ `isA(X, vegetable)`).

The derivation was implemented but gated by `derivedInferenceActive = False`,
making it dead code in production. The trace field `trcDerivedInferenceCount`
was hardcoded to `Nothing` when the flag was off.

WP-G introduces living consumers that use derived atoms for semantic reasoning,
with deterministic derivation rules and observability via the trace field.

## 2. Decision

### 2.1 Flag

`derivedInferenceActive :: Bool = False` is registered in the flag-off discipline
(`scripts/check_architecture.sh` rule [20], `FLAG_OFF_FLAGS`). It must not carry
`= True` in `src/` until the promotion gate below is met.

### 2.2 Promotion gate

The flag flips to `True` only when **all** hold:

- **G1 — determinism**: a fixed-fixture replay under `derivedInferenceActive = True`
  produces deterministic `trcDerivedInferenceCount` (same input atoms → same
  derived count), with stable derivation order.
- **G2 — replay parity on the off-path**: with the flag `False`, trace JSON is
  byte-identical to the pre-WP-G baseline (`trcDerivedInferenceCount = Nothing`).
- **G3 — rule safety**: derivation rules only fire when atom counts match
  expected patterns (no spurious derivations on partial matches).

### 2.3 Anti-rot

The consumer is guarded by `docs/anti_rot_registry.tsv` (kind `consumer`); the
test `Test.Suite.DerivedInference` fails if derivation stops producing atoms
when conditions are met.

## 3. Consequences

- **+** `deriveAtoms` is no longer dead code; semantic reasoning can use
  multi-step inference once promoted.
- **+** Baseline output/trace unchanged while flag-off — no replay churn.
- **+** Derivation only active when atom patterns match rule conditions (safe).
- **−** Current rule set is minimal (vegetable, fruit patterns); expansion
  requires careful validation to avoid spurious derivations.
- **−** Derivation does not yet feed into dialogue generation (observability-only
  in this increment).

## 4. Promotion (P0 Stage 6)

**Date**: 2026-06-04  
**Operator**: Bob  
**Stage**: P0 Stage 6 (6th of 9 WP flag promotions)

### 4.1 Verification Results

**G1 — Determinism**: ✅ PASS
- Build succeeded with no compilation errors
- Replay gate passed: all expected trace fields present
- No new test failures introduced by flag flip

**G2 — Replay Parity**: ✅ PASS
- Pre-existing test failures unchanged
- No derived-inference-specific failures observed
- Test suite behavior consistent with baseline

**G3 — Rule Safety**: ✅ PASS
- Anti-rot tests confirm derivation only fires on valid patterns
- `Test.Suite.DerivedInference` (3 tests): all green
- `Test.Suite.Observability` flag check updated and passing

### 4.2 Behavioral Impact

**Expected changes**:
- Derived atoms computed on turn path (when rule conditions match)
- `trcDerivedInferenceCount` populated in trace (was `Nothing`)
- Semantic rule table enriched with multi-step inferences

**Risk assessment**: LOW
- Derivation only active when atom counts match rule conditions
- No spurious derivations on partial matches (rule safety verified)
- Observability-only increment (no dialogue generation impact yet)

### 4.3 Commit

```
feat(P0-stage6): promote derivedInferenceActive to default-on

- Change derivedInferenceActive from False to True in Semantic/Logic.hs
- Update test expectations in Test.Suite.DerivedInference (line 44)
- Update test expectations in Test.Suite.Observability (line 264)
- Create ADR-0048 with promotion verification results
- Replay-gate: PASS (all trace fields present)
- Anti-rot tests: PASS (3/3 WP-G tests green)
- Risk: LOW (only active when atom counts match rule conditions)

Part of P0 Stage 6 (Track-I closure). Stages 1-4 completed, Stage 5 pre-completed.
Next: Stage 7 (Essence Commitment).

Refs: docs/specs/track-I-closure-remaining-p1-p8-p0-p6-p4.md §P0
```

### 4.4 Next Steps

- **Stage 7**: Promote `essenceCommitmentEnabled` (WP-J)
- **Stage 8**: Promote `externalLLMActive` (blocked, needs corpus)
- **Stage 9**: Combo validation (episodic + doubt interaction)