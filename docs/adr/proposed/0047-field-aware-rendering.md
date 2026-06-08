# ADR-0047 (proposed): Field-Aware Rendering (P6')

**Status**: Proposed  
**Date**: 2026-06-04  
**Context**: Track-I Closure (P6')

## Context

Field (5 components: Resonance, Atmosphere, FieldConfidence, Consolidation, Counterfactual) is computed each turn, traced in `TurnReplayTrace`, but **does not influence surface realisation**. The system computes rich affective and epistemic signals, then ignores them during text generation.

Track-I closure (P6') requires Field integration into the GF rendering pipeline so that:
- Low confidence → epistemic hedges ("maybe", "I think")
- Negative valence → softer modals ("could", "might")
- High consolidation → discourse connectors ("also", "furthermore")
- High counterfactual → alternative markers ("alternatively", "however")

## Decision

### R-P6.1: Add `fieldAwareRenderingActive` flag

**Location**: `src/QxFx0/Self/Field.hs:370`  
**Status**: ✅ Already exists, default `False`

```haskell
fieldAwareRenderingActive :: Bool
fieldAwareRenderingActive = False
```

### R-P6.2: Thread Field through rendering pipeline

**Files to modify**:

1. **`src/QxFx0/Core/TurnRender/Strategy.hs`**
   - Add `Field` parameter to `selectRenderStrategy`
   - Compute modulation signals from Field components

2. **`src/QxFx0/Core/TurnRender.hs`**
   - Thread `Field` from `TurnInput` to `Strategy`
   - Pass to GF rendering functions

3. **`src/QxFx0/Render/Text.hs`** (if exists)
   - Implement hedge insertion logic
   - Implement modal softening logic

### R-P6.3: Field → Surface Realisation Mapping

| Field Component | Surface Effect | Implementation |
|-----------------|----------------|----------------|
| **fieldConfidence** | Epistemic hedges | Low (<0.4) → insert "maybe", "I think", "perhaps" before assertion |
| **atmosphereValence** | Modal softening | Negative (<-0.3) → replace "will" with "might", "can" with "could" |
| **atmosphereArousal** | Sentence length | High (>0.7) → prefer shorter sentences, fewer subordinate clauses |
| **fieldConsolidation** | Discourse connectors | High (>0.6) → insert "also", "furthermore", "as mentioned" |
| **fieldCounterfactual** | Alternative markers | High (>0.5) → insert "alternatively", "another way", "however" |

### R-P6.4: GF Integration Strategy

**Option A: Pre-GF modulation** (recommended)
- Modify `ResponseMeaningPlan` before GF linearization
- Insert hedge/modal/connector tokens into semantic structure
- GF linearizes modified structure naturally

**Option B: Post-GF modulation**
- GF linearizes normally
- Post-process output text to insert hedges/modals
- Risk: may break grammatical agreement

**Decision**: Use Option A (pre-GF) for grammatical correctness.

### R-P6.5: Flag-off behavior

When `fieldAwareRenderingActive = False`:
- Field is computed and traced (unchanged)
- No modulation applied to rendering
- Output identical to current behavior

### R-P6.6: Anti-rot tests

**Test suite**: `Test.Suite.FieldAwareRendering`

Property tests for each Field component:
1. **Confidence test**: Low confidence (0.2) → output contains hedge marker
2. **Valence test**: Negative valence (-0.5) → output uses soft modal
3. **Arousal test**: High arousal (0.8) → output sentence count > baseline
4. **Consolidation test**: High consolidation (0.7) → output contains connector
5. **Counterfactual test**: High counterfactual (0.6) → output contains alternative marker

Each test runs with flag ON and OFF, verifying:
- Flag OFF → no modulation (baseline output)
- Flag ON → expected modulation present

## Consequences

### Positive
- **Field becomes behaviorally active**: Computed signals actually influence output
- **Richer expressiveness**: System can modulate tone, confidence, discourse structure
- **Track-I closure**: Eliminates "computed but ignored" gap

### Negative
- **GF complexity**: Requires deep understanding of GF linearization
- **Calibration needed**: Thresholds (0.4, -0.3, 0.7, etc.) are initial guesses
- **Grammatical risk**: Incorrect modulation may break agreement/coherence

### Mitigations
- **Pre-GF approach**: Preserves grammatical correctness
- **Flag-off default**: Can revert if issues arise
- **Anti-rot tests**: Catch regressions in modulation logic

## Implementation Plan

### Phase 1: Infrastructure (2-3 hours)
1. Add `Field` parameter to `selectRenderStrategy`
2. Thread `Field` through `TurnRender.hs`
3. Create stub modulation functions (no-op when flag off)
4. Verify build + existing tests pass

### Phase 2: Confidence modulation (1-2 hours)
1. Implement `applyConfidenceHedge :: FieldConfidence -> ResponseMeaningPlan -> ResponseMeaningPlan`
2. Insert hedge tokens when confidence < 0.4
3. Add anti-rot test for confidence
4. Verify output diff on test corpus

### Phase 3: Atmosphere modulation (2-3 hours)
1. Implement `applySoftModals :: Atmosphere -> ResponseMeaningPlan -> ResponseMeaningPlan`
2. Replace strong modals with soft when valence < -0.3
3. Implement sentence splitting when arousal > 0.7
4. Add anti-rot tests for valence + arousal

### Phase 4: Discourse modulation (1-2 hours)
1. Implement `applyDiscourseConnectors :: Consolidation -> Counterfactual -> ResponseMeaningPlan -> ResponseMeaningPlan`
2. Insert connectors/alternative markers based on thresholds
3. Add anti-rot tests
4. Full integration test

### Phase 5: Calibration (deferred to Phase II)
1. Run on production corpus
2. Tune thresholds for natural output
3. A/B test modulated vs baseline

**Total estimate**: 6-10 hours of focused work

## Acceptance Criteria

- [ ] `Field` threaded through rendering pipeline
- [ ] All 5 Field components influence surface realisation
- [ ] Flag-off behavior identical to baseline
- [ ] 5 anti-rot tests pass (one per component)
- [ ] Build + full test suite green
- [ ] Manual review of 20 modulated outputs (naturalness check)

## Related

- **ADR-0009**: Right-hemispheric Field (defines Field structure)
- **ADR-0010**: Salience controller (computes Field)
- **Track-I spec**: `docs/specs/track-I-closure-remaining-p1-p8-p0-p6-p4.md` (P6' requirements)

---

**Status**: Proposed (implementation pending)  
**Next step**: Phase 1 infrastructure work