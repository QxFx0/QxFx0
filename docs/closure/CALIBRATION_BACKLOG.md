# Calibration Backlog (QxFx0_v3)

- **Status**: Active (closure-phase work product, Package 11)
- **Date**: 2026-06-02
- **Refines**: AGENTS.md (Phase 7 calibration infrastructure
  completed 2026-05-18; empirical tuning deferred),
  ADR-0010 §3.1, ADR-0012 §15.2 (angst calibration deferred)
- **Related**:
  - `docs/closure/SELF_LAYER_STATUS.md` (Package 10)
  - `docs/closure/BOUNDED_LEARNING_DESIGN.md` (Package 8)
  - `docs/closure/METACOGNITION_LOOP_DESIGN.md` (Package 9)
  - `docs/adr/proposed/0034-self-core-role-split.md` (Package 1)

## 0. Why this backlog exists

The closure plan's Package 11 says: "calibration is needed, but
not as a replacement for architectural rebuilding. Calibrate
only what is connected to observable outcomes, has survived
unification of paths, and participates in authority decisions.
Otherwise we get plausible weights for the wrong architecture."

This document is the **backlog of every parameter that needs
empirical calibration** in the post-closure QxFx0_v3, with:

1. The current value (hand-set or phase-7 default).
2. The codomain of the signal it gates (per ADR-0012 §15.3
   "methodology lesson").
3. The observable outcome it should be tied to.
4. The empirical evidence needed to justify a different value.
5. The promotion gate (when does this move from "hand-set" to
   "empirically calibrated" in the documentation?).

The backlog is **not** a "do calibration" list. It is a
**prerequisite** list: most entries cannot be calibrated until
the architecture they depend on is in place. The closure plan's
Packages 1–10 are the prerequisites; Package 11 is what
calibration looks like after they land.

## 1. The methodology lesson (from ADR-0012 §15.3)

> Phase 9 modulation defaults were validated against unit-test
> generators (`arbitraryUnitDouble`), not production runtime.
> This left two latent issues (one corrected here, one deferred).
> Future modulation parameters in `QxFx0.Self.*` must be sanity-
> checked against the actual codomain of the signals they gate.

This is the closure plan's standing rule. Every parameter in the
backlog below records its signal codomain explicitly, so the
calibration work cannot repeat the Phase 9 error.

## 2. The backlog

### 2.1 `Self.Salience.SalienceWeights`

Per ADR-0010 §3.1, the default weights are bikeshed-eligible;
"Phase 5 ships `defaultSalienceWeights` with values that make
the property tests pass and the operational mapping plausible.
We do not claim these are calibrated."

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|---|
| `weightResonance` | hand-set (Phase 5 default) | `Field.fieldResonance ∈ [0, 1]` | trace `trcSalienceDriver = "resonance"` rate | corpus of N≥1k turns with trace | driver distribution matches observed Field distribution; salience confidence calibrated against external eval |
| `weightAtmosphere` | hand-set | `Field.fieldAtmosphere ∈ [0, 1]` | trace driver rate | same | same |
| `weightConsolidation` | hand-set | `Field.fieldConsolidation ∈ [0, 1]` | trace driver rate | same | same |
| `weightCounterfactual` | hand-set | `Field.fieldCounterfactual ∈ [0, 1]` | trace driver rate | same | same |
| `weightFieldConfidence` | hand-set | `Field.fieldConfidence ∈ [0, 1]` | trace driver rate | same | same |
| `conatusGateThreshold` | hand-set | `ConatusEnergy.ceScalar ∈ [~5, ~20+]` (production) | trace `trcSalienceDriver = "conatus_gate"` rate | corpus of N≥1k turns | threshold matches observed Conatus drop pattern; gate fires at correct fraction |
| `verdictThreshold` | hand-set | `Double ∈ [0, 0.5]` | trace `salienceVerdict = Tied` rate | same | dead-band prevents pathological flapping; rate matches expected ties |

**Prerequisites**: Package 1 (canonical Self/* status), Package 8
(LearningContour exposes SalienceWeights as a `LearningTarget`),
a production-trace corpus.

### 2.2 `Self.Field.FieldHeuristics`

Per Phase 7 (AGENTS.md), `FieldHeuristics` was extracted from
inline constants; empirical tuning is deferred.

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|---|
| 5 component sourcing rules | hand-set | each `fieldXxx ∈ [0, 1]` | trace `trcField*` rate | corpus | sourcing matches observed right-hemisphere activity |

**Prerequisites**: Package 1, Package 8, corpus.

### 2.3 `Self.Essence.EssenceModulation`

Per ADR-0012 §15.1, `emConatusStructuralFloor` was corrected from
0.5 to 7.0 in Phase 10 (Conatus scalar codomain is `[~5, ~20+]`
in production, not `[0, 1]`). Per §15.2, the angst-side
parameters are deferred.

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|---|
| `emConatusStructuralFloor` | **7.0** (corrected) | `ConatusEnergy.ceScalar ∈ [~5, ~20+]` | trace `trcEssenceTrigger = "conatus_erosion"` rate | corpus | trigger fires at expected Conatus drop fraction |
| `emConatusFloorWindow` | hand-set | `Int` (turns) | same | corpus | window matches observed erosion duration |
| `emAngstCommitmentThreshold` | hand-set | `etAngstLevel ∈ [0, 1]` | trace `trcEssenceTrigger = "angst_threshold"` rate | **production trace required** (synthetic corpus cannot produce `RuleHolisticAdvantage`/`RuleFormalAdvantage` with sufficient divergence per §15.2) | trigger fires at expected angst rate |
| `emAngstAccrualRate` | hand-set | `Double` | `etAngstLevel` trajectory | same | accrual matches observed angst dynamics |
| `emAngstDecayRate` | hand-set | `Double` | same | same | decay matches observed recovery dynamics |
| `emAngstAccrualDivergenceFloor` | hand-set | `Double` | same | same | floor matches observed divergence distribution |
| `emTrajectoryCapacity` | hand-set | `Int` (ring buffer) | `etWitnesses.length` | corpus | capacity matches observed witness rate |

**Prerequisites**: Package 1, Package 8, **a production trace
corpus** (synthetic cannot suffice per ADR-0012 §15.2).

### 2.4 `Self.Deliberation.DeliberationModulation`

Per ADR-0011 §12 Package C, `DeliberationModulation` centralises
the tone arousal/valence thresholds that were hardcoded at 0.5
and 0.0 in `routeFamily`.

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|---|
| `dmToneArousalFloor` | 0.5 | `Field.fieldAtmosphere.arousal ∈ [0, 1]` | trace `trcDeliberationNarrativeTone = "warm"/"terse"` rate | corpus | tone distribution matches expected atmosphere profile |
| `dmToneValenceNeutral` | 0.0 | `Field.fieldAtmosphere.valence ∈ [-1, 1]` | same | corpus | same |

**Prerequisites**: Package 1, Package 8, corpus.

### 2.5 `Conatus.ConatusWeights` (the formula coefficients)

Per `Self.Conatus.computeConatusEnergy`, the formula is:
```
C(b,v) = w_m·log(1+m) + w_c·log(1+c) + w_t·log(1+t) − λ·|v|
```

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|---|
| `w_m` (morphology weight) | hand-set | `m ∈ ℕ` (morphology size) | `ConatusEnergy.ceScalar` distribution | corpus | weight matches observed morphology contribution |
| `w_c` (identity weight) | hand-set | `c ∈ ℕ` (identity claims) | same | corpus | same |
| `w_t` (turns weight) | hand-set | `t ∈ ℕ` (turn count) | same | corpus | same |
| `λ` (violation penalty) | hand-set | `v ∈ ℕ` (blanket violations) | same | corpus | penalty matches observed recovery dynamics |

**Prerequisites**: Package 1, Package 8, corpus.

### 2.6 `Memory.Episodic.*` thresholds (Package 7)

Per `COGNITIVE_MEMORY_DESIGN.md §3`, the episodic contour has
hand-set defaults for capacity and window.

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|---|
| `episodicCapacity` | 1000 (default) | `Seq.length` | trace `trcEpisodicForgetting` rate | corpus | capacity matches observed episodic event rate |
| `episodicWindow` | 50 (turns) | `TurnSeq` | same | corpus | window matches observed relevance half-life |

**Prerequisites**: Package 7, corpus.

### 2.7 `Learning.*` rate limits (Package 8)

Per `BOUNDED_LEARNING_DESIGN.md §6`, rate limits are hand-set.

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|---|
| Per-turn rate | 1 update/turn | `Int` | trace `trcLearningUpdate` rate | corpus | rate matches observed learning demand |
| Per-session rate | 10 updates/session | `Int` | same | corpus | same |
| Rollback window | 3 consecutive rejections | `Int` | trace `trcLearningRollback` rate | corpus | window matches observed adaptation stability |

**Prerequisites**: Package 8, corpus.

### 2.8 `Metacognition.*` thresholds (Package 9)

Per `METACOGNITION_LOOP_DESIGN.md §4`, calibration targets are
hand-set.

| Field | Current value | Signal codomain | Observable outcome | Empirical evidence needed | Promotion gate |
|---|---|---|---|---|
| Calibration precision target | 0.85 | `Double` | `Test.Suite.MetacognitionCalibration` | held-out corpus | target met consistently |
| Calibration recall target | 0.70 | `Double` | same | same | same |
| Calibration interval | 100 turns | `Int` | same | same | interval matches observed calibration drift |

**Prerequisites**: Package 9, **a labelled held-out corpus**
(specifically, a corpus with external human ratings of
decision-outcome alignment).

## 3. The production-trace corpus (the blocker)

Every entry in §2 depends on a **production-trace corpus** that
does not exist in quantity today. The closure plan's Package
11 makes the corpus its first deliverable.

The corpus is:

- A collection of `TurnReplayTrace` records from production
  sessions, with `trc*` fields populated.
- A subset of those records has **external labels** (human-rated
  decision-outcome alignment, decision quality, etc.).
- The corpus is regenerated periodically (default: every
  release).
- The corpus is stored in `data/calibration_corpus/` (path TBD).

**Building the corpus is the gating work of Package 11.** Without
it, every entry in §2 stays at "hand-set" status.

## 4. The empirical-calibration workflow

For each entry in §2, the workflow is:

1. **Codomain check.** Verify that the parameter's signal
   codomain matches the production codomain (per ADR-0012
   §15.3). This is the gate that prevents repeating the
   `emConatusStructuralFloor = 0.5` error.
2. **Corpus collection.** Collect N≥1k turns of production
   trace with the relevant `trc*` field populated.
3. **Empirical fit.** Tune the parameter to maximise (or
   minimise) a target metric on the held-out corpus.
4. **Cross-validation.** Hold out 20% of the corpus; verify the
   parameter generalises.
5. **Documentation.** Update the parameter's status from
   "hand-set" to "empirically calibrated" in
   `SELF_LAYER_STATUS.md` and the relevant ADR addendum.
6. **Regression lock.** Add a `Test.Suite.Calibration*` test
   that fails if the parameter drifts outside the calibrated
   range.

## 5. What Package 11 does NOT do

- **Online calibration.** Out of scope. The calibration is
  offline (corpus-driven); the online update path is Package 8
  (bounded learning).
- **Auto-calibration.** The orchestrator does not auto-adjust
  parameters at runtime. Calibration is a release-time activity.
- **Calibration of new parameters.** A new parameter introduced
  after Package 11 closes is hand-set by default; it is added
  to the backlog and calibrated in the next pass.
- **Cross-domain calibration.** The closure plan calibrates
  per-domain parameters separately. Cross-domain joint
  calibration is a research problem.

## 6. Acceptance criteria for Package 11 closure

- [ ] `data/calibration_corpus/` exists with at least 1k
      production-trace records and a labelled subset of at
      least 100 records with external human ratings.
- [ ] Every entry in §2 has a codomain check recorded in
      `SELF_LAYER_STATUS.md §5` or an equivalent table.
- [ ] At least 50% of the entries in §2 have an empirical
      calibration pass recorded (status: `empirically
      calibrated`).
- [ ] `Test.Suite.Calibration*` tests exist for every
      empirically-calibrated parameter and fail if the
      parameter drifts.
- [ ] `docs/closure/CALIBRATION_REPORT.md` summarises the
      calibration pass: which parameters moved, by how much,
      against what corpus, with what confidence intervals.
- [ ] The closure plan's Package 1 (`SELF_LAYER_STATUS.md`)
      reflects the new calibration status for each parameter.

## 7. Honest limits

- The corpus is **small at first**. 1k records is the minimum;
  10k or 100k is better. The closure plan ships the minimum.
- The empirical fit is **a release-time activity**, not a
  research paper. The closure plan commits to "good enough for
  the next release" calibration, not "best possible".
- The hand-set defaults are **not wrong**; they are
  **uncalibrated**. The system works with hand-set defaults;
  calibration improves it. The closure plan does not require
  the system to fail without calibration.
- The backlog is **open-ended**. New parameters appear with
  new features; the backlog grows. Package 11 is a recurring
  activity, not a one-shot project.
- The closure plan's Package 11 does not address **calibration
  of LLM-driven contours**. Per `AUTHORITY_MAP.md`,
  `Bridge.ExternalLLM` is supplier-flag-off; its calibration
  is a separate package.
