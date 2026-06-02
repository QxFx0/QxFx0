# Learning Allowed Targets (QxFx0_v3)

- **Status**: Active (closure-phase follow-up F-03, Package 8
  invariant I1)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/BOUNDED_LEARNING_DESIGN.md` §1, I1
- **Related**: `docs/closure/LEARNING_ALLOWED_SOURCES.md` (F-04)

## 0. Why this file exists

The closure plan's Package 8 invariant I1 says: "a learning
update may only target an **authority-bearing** contour. The
closed list is in `LEARNING_ALLOWED_TARGETS.md`; CI rejects
updates to anything else."

This is that file. The list is **closed**: adding a new
target requires a phase-ADR (or closure-plan follow-up) and
a follow-up issue.

## 1. The closed list

Each entry has:

- `target` — the `LearningTarget` constructor.
- `owner-module` — the Haskell module that owns the value.
- `value-type` — the underlying type.
- `value-range` — the closed range the value must stay in.
- `rationale` — why this target is authority-bearing.
- `added-in` — the closure-plan PR / ADR that added it.
- `removal-criterion` — when this target should be removed.

### T-01: `TgtSalienceWeights !Text`

- **owner-module**: `QxFx0.Self.Salience`
- **value-type**: `Double`
- **value-range**: `[0, 1]` for the five weights; `[0, 0.5]`
  for `verdictThreshold`; `ConatusEnergy` codomain for
  `conatusGateThreshold`.
- **rationale**: `SalienceWeights` is the per-controller
  decision-rule knob. It is the canonical salience input
  (ADR-0010 §3). The controller decides per turn which
  hemisphere leads; the weights determine that decision.
  Without learning, the weights are hand-set; bounded
  learning tunes them.
- **added-in**: closure-plan P8.
- **removal-criterion**: if `SalienceWeights` is replaced by a
  learned model (e.g. a neural network), this target is
  retired.

### T-02: `TgtFieldHeuristics !Text`

- **owner-module**: `QxFx0.Self.Field`
- **value-type**: `Double`
- **value-range**: `[0, 1]` for the five component sourcing
  rules.
- **rationale**: `FieldHeuristics` was extracted from inline
  Phase-5.5d constants (AGENTS.md). It is the per-component
  sourcing for the right-hemispheric `Field`. Bounded
  learning tunes the sourcing.
- **added-in**: closure-plan P8.
- **removal-criterion**: if the `Field` decomposition changes
  (per ADR-0009 addendum 2026-05-17), the corresponding
  targets are removed and new ones added via a phase-ADR.

### T-03: `TgtEssenceModulation !Text`

- **owner-module**: `QxFx0.Self.Essence`
- **value-type**: `Double` (for the 5 modulation fields) and
  `Int` (for `emConatusFloorWindow` and `emTrajectoryCapacity`).
- **value-range**:
  - `emAngstCommitmentThreshold ∈ [0, 1]`
  - `emAngstAccrualRate ∈ [0, 1]`
  - `emAngstDecayRate ∈ [0, 1]`
  - `emAngstAccrualDivergenceFloor ∈ [0, 1]`
  - `emConatusStructuralFloor ∈ [~5, ~20+]` (production Conatus codomain; per ADR-0012 §15.1)
  - `emConatusFloorWindow ∈ [1, ∞)` (turns)
  - `emTrajectoryCapacity ∈ [1, ∞)` (witnesses)
- **rationale**: `EssenceModulation` is the tunable for the
  essence commitment layer (ADR-0012). The angst side is
  deferred per ADR-0012 §15.2; bounded learning will not
  tune it until the production-trace corpus is in place.
- **added-in**: closure-plan P8.
- **removal-criterion**: if `Essence` is removed (full
  demotion ADR), this target is retired.

### T-04: `TgtDeliberationModulation !Text`

- **owner-module**: `QxFx0.Self.Deliberation`
- **value-type**: `Double`
- **value-range**: `[0, 1]` for `dmToneArousalFloor`;
  `[-1, 1]` for `dmToneValenceNeutral`.
- **rationale**: `DeliberationModulation` centralises the
  tone arousal/valence thresholds (ADR-0011 §12 Package C).
  It is the per-tone decision knob for the holistic
  proposal's `planNarrativeTone`. Bounded learning tunes
  the thresholds.
- **added-in**: closure-plan P8.
- **removal-criterion**: if `Deliberation` is removed, this
  target is retired.

### T-05: `TgtSemanticCommitmentThreshold !Text`

- **owner-module**: `QxFx0.Semantic.Commitment` (post-Package 2)
- **value-type**: `Double` (for the parser confidence
  threshold and the auto-commit threshold).
- **value-range**: `[0, 1]`.
- **rationale**: the parser confidence threshold determines
  which typed observations are committed. The auto-commit
  threshold (if added) determines which committed
  observations are auto-committed without orchestrator
  veto. Both are authority-bearing because they affect
  what enters the `SemanticCommitmentStore`.
- **added-in**: closure-plan P2.
- **removal-criterion**: if the parser is replaced, the
  threshold is retired.

### T-06: `TgtEpisodicThreshold !Text`

- **owner-module**: `QxFx0.Memory.Episodic` (post-Package 7)
- **value-type**: `Int` (for `episodicCapacity`,
  `episodicWindow`); `Double` (for any future importance
  threshold).
- **value-range**: `episodicCapacity ∈ [1, ∞)`;
  `episodicWindow ∈ [1, ∞)`; importance in `[0, 1]`.
- **rationale**: the forgetting policy is authority-bearing
  (Package 7 §2.3). The thresholds determine what is
  forgotten.
- **added-in**: closure-plan P7.
- **removal-criterion**: if episodic memory is removed, the
  threshold is retired.

### T-07: `TgtMetacognitionThreshold !Text`

- **owner-module**: `QxFx0.Policy.Metacognition` (post-Package 9)
- **value-type**: `Double`
- **value-range**: `[0, 1]` for confidence thresholds;
  `[0, ∞)` for the calibration interval.
- **rationale**: the metacognitive loop's confidence
  thresholds determine when the system reports
  `EvaluationAmbiguous` vs `EvaluationAligned` /
  `EvaluationMisaligned`. The calibration interval
  determines how often the calibration gate runs.
- **added-in**: closure-plan P9.
- **removal-criterion**: if metacognition is removed, the
  threshold is retired.

## 2. The CI gate (extension of `check_architecture.sh`)

The invariant I1 enforcement at CI time is:

```bash
# Find every constructor of LearningTarget in src/ and tests/.
# Verify each appears in this file (LEARNING_ALLOWED_TARGETS.md).
grep -rh "Tgt" src/QxFx0/Learning/ test/Test/Suite/LearningContour/ \
  | grep -oE "Tgt[A-Z][a-zA-Z]+" \
  | sort -u \
  > /tmp/learning_targets_used.txt
grep -oE "Tgt[A-Z][a-zA-Z]+" docs/closure/LEARNING_ALLOWED_TARGETS.md \
  | sort -u \
  > /tmp/learning_targets_allowed.txt
diff /tmp/learning_targets_used.txt /tmp/learning_targets_allowed.txt \
  && echo "OK: all learning targets are allowlisted" \
  || (echo "FAIL: unknown learning target"; exit 1)
```

The check is: every `Tgt*` constructor used in code is in
this file.

## 3. The discipline

The discipline of this list is:

- **Closed by default.** A new target is added by editing
  this file, with a follow-up ADR, in the same PR as the
  code that introduces the target.
- **Authority-bearing by construction.** A target on this
  list is, by definition, an authority-bearing contour
  (per Package 1's classification). It is subject to the
  replay gate (Package 3).
- **Calibration is the late stage.** Tuning the values of
  these targets is Package 11's work. The list itself is
  Package 8's work.
- **Removal is not deletion.** A retired target is kept in
  this file with a `removed-in` field and a `removal-criterion`
  filled in. The discipline is audit-trail-friendly.

## 4. Acceptance criteria for F-03

F-03 is closed when:

- [ ] This file is merged with T-01 through T-07 as the
      initial closed list.
- [ ] The CI gate of §2 is in place; CI is green.
- [ ] Every `Tgt*` constructor in `src/QxFx0/Learning/` and
      `test/Test/Suite/LearningContour/` is in this file.
- [ ] Future additions to the list follow the discipline of §3.
