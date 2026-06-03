# Metacognitive Correction Loop Design

- **Status**: Active (closure-phase work product, Package 9)
- **Date**: 2026-06-02
- **Refines**: AGENTS.md ("weak acknowledgement phrases are
  observational and must not trigger strong mutation"),
  `docs/adr/0011-deliberation-framework.md` §6.1 (M1), `docs/adr/0009-right-hemisphere-field.md`
- **Related**:
  - `docs/closure/SEMANTIC_CORE_MIN_SLICE.md` (Package 2)
  - `docs/closure/REPLAY_GATE_SPEC.md` (Package 3)
  - `docs/closure/COGNITIVE_MEMORY_DESIGN.md` (Package 7)
  - `docs/closure/BOUNDED_LEARNING_DESIGN.md` (Package 8)
  - `docs/adr/proposed/0034-self-core-role-split.md` (Package 1)

## 0. Why this design exists

The closure plan's Package 9 says: "metacognition must not be
theatre; it must be a closed correction loop:
`decision → outcome → evaluation → bounded correction`. The
internal self-evaluation must be **calibrated**, not merely
added. It must correlate with external evaluation."

This document specifies the metacognitive correction loop. The
design is **deliberately post-decision**: metacognition does
not affect the current turn; it affects future turns. The loop
is:

```
Turn N:
  decision  = reconcile(...)
  outcome   = observeResponse(...)
  evaluation = selfEvaluate(decision, outcome)   -- on Turn N+1
  correction = boundedCorrection(evaluation)     -- into LearningContour
```

The current `observeOwnResponse` in
`QxFx0.Core.ConsciousnessLoop` is keyword-conditional
(ADR-0010 §6.1 footnote). The closure plan's Package 9 replaces
it with a typed, calibrated, replay-traced discipline.

## 1. The four-stage loop

### 1.1 Stage 1: Decision capture

Every decision the runtime makes is recorded in
`TurnReplayTrace`. This is already the case (AGENTS.md
"replay envelope fields aligned with runtime contracts"). The
metacognitive loop **consumes** this trace; it does not add
a new decision-capture channel.

Specifically, the metacognitive loop reads:

- `trcDeliberationRule` (ADR-0011)
- `trcDeliberationAgreement`
- `trcDeliberationDivergence`
- `trcDeliberationNarrativeTone`
- `trcRecoveryCause`, `trcRecoveryStrategy`
- `trcSalienceDriver` (ADR-0010)
- `trcEssenceMode`, `trcEssenceAngstLevel` (ADR-0012)
- `trcCommitmentRetrieval` (Package 2)
- `trcEpisodicRetrieval` (Package 7)
- `trcLearningUpdate` (Package 8)

These are the **inputs** to Stage 2 (outcome observation).

### 1.2 Stage 2: Outcome observation

`observeResponse :: TurnOutput -> Outcome` is a pure function
that maps a rendered turn output to a typed `Outcome`:

```haskell
data Outcome
  = OutcomeAccepted        -- user accepted the response
  | OutcomeRefined         -- user refined the response
  | OutcomeRejected        -- user rejected the response
  | OutcomeContradicted    -- user contradicted the system
  | OutcomeIgnored         -- user moved on
  | OutcomeNoFeedback      -- no signal yet
  deriving stock (Eq, Show, Generic)
```

The mapping is **not** keyword-conditional. It is a typed
event from the parser / dialogue state:

- If the user says "yes" / "ok" / "согласен" → `OutcomeAccepted`.
- If the user says "no" / "I disagree" / "нет" → `OutcomeRejected`
  (or `OutcomeContradicted` if the user provides an explicit
  alternative).
- If the user refines → `OutcomeRefined`.
- If the user moves on to a new topic → `OutcomeIgnored`.
- If the next turn is unrelated → `OutcomeNoFeedback`.

The discipline is the same as Package 4: a closed enum, parser-
typed, no keyword heuristics.

The `Outcome` is part of the **next turn's** `TurnInput` (not
the current turn's). This is the "outcome is post-hoc" stage of
the loop.

### 1.3 Stage 3: Self-evaluation

`selfEvaluate :: TurnDecision -> Outcome -> Evaluation` is a
pure function that produces a typed `Evaluation`:

```haskell
data Evaluation
  = EvaluationAligned       -- decision was correct, outcome confirms
  | EvaluationMisaligned    -- decision was wrong, outcome contradicts
  | EvaluationAmbiguous     -- outcome is too weak to decide
  | EvaluationUncalibrated  -- self-evaluation itself is uncertain
  deriving stock (Eq, Show, Generic)
```

The mapping is **calibrated**, not heuristic. Calibration here
means:

- `EvaluationAligned` correlates with **external** evaluation
  (e.g. a held-out test set labelled by humans) at a measurable
  rate (target: precision ≥ 0.85, recall ≥ 0.70).
- `EvaluationMisaligned` correlates with external evaluation of
  "decision was wrong" at the same rate.
- `EvaluationAmbiguous` is the residual; it is a confidence
  signal, not a verdict.
- `EvaluationUncalibrated` is the meta-signal: the system
  recognises when it does not know.

The calibration is **measured**, not claimed. The closure
plan's Package 9 ships a `Test.Suite.MetacognitionCalibration`
suite that:

1. Holds out a corpus of (decision, outcome, external_label)
   triples.
2. Runs `selfEvaluate` on each.
3. Computes precision, recall, and the confusion matrix.
4. Fails CI if the targets are not met.

This is the closure plan's "calibrated, not merely added".

### 1.4 Stage 4: Bounded correction

`boundedCorrection :: Evaluation -> Maybe LearningUpdate` is a
pure function that maps a self-evaluation to a (possibly empty)
learning update. It is **bounded** in three senses:

1. **Targeted**: the update targets a `LearningTarget` (per
   Package 8). The `Evaluation` enum maps to a target:
   - `EvaluationAligned` → no update (positive feedback is
     already captured by the absence of retraction).
   - `EvaluationMisaligned` → a `Decrement` of the relevant
     `SalienceWeights` or `FieldHeuristics` field.
   - `EvaluationAmbiguous` → no update.
   - `EvaluationUncalibrated` → a `Clip` of the `Metacognition
     Threshold` (the system becomes more conservative).
2. **Routed through Package 8**: the update goes through
   `applyLearningUpdate` and is subject to the four invariants.
3. **Replay-visible**: every update is in `trcLearningUpdate`
   (per Package 8).

The metacognitive loop is **not** a new write channel; it is
a **client** of Package 8's bounded learning contour. This is
the closure plan's "bounded correction" discipline.

## 2. The integration point

The metacognitive loop runs **once per turn, in the Finalize
stage**, AFTER the Outcome of the previous turn is available:

```text
Turn N:
  TurnInput (carries Outcome of Turn N-1)
  TurnDecision (reconcile, recovery, salience, essence, etc.)
  Outcome (from Turn N-1's response, observed at Turn N's input)
        │
        ▼
selfEvaluate(TurnDecision of Turn N-1, Outcome of Turn N-1)
        │
        ▼
boundedCorrection(Evaluation)
        │
        ▼
applyLearningUpdate(...)
        │
        ▼
LearningContour', trcLearningUpdate
```

Note the time-arrow: the metacognitive evaluation of turn N-1
happens at turn N. This is the "post-hoc" discipline; the
runtime cannot metacognitively evaluate a turn whose outcome
is not yet observed.

## 3. The `MetacognitionContour` (optional state)

For some sessions, it is useful to retain a running summary of
the metacognitive state (e.g. "how many misalignments have I
seen recently?"). This is optional and lives in
`SystemState.ssMetacognition :: Maybe MetacognitionContour`:

```haskell
data MetacognitionContour = MetacognitionContour
  { mcRecentEvaluations :: !(Seq Evaluation)   -- bounded window
  , mcMisalignCount     :: !Int
  , mcCalibrationBucket :: !Int                 -- for periodic recalibration
  , mcLastCalibration   :: !(Maybe TurnSeq)
  } deriving stock (Eq, Show, Generic)
```

The contour is **observability-only** by default. It does not
drive runtime decisions. It is consumed by:

- The trace renderer (for `trcMetacognition` field).
- The `Metacognition.Statistics` module (for offline analysis
  and recalibration).
- Future metacognition-aware consumers (an ADR-level decision).

## 4. The calibration discipline

The closure plan's "calibrated, not merely added" is operationalised
as:

1. **External evaluation source.** The closure plan picks a
   held-out corpus with **external** labels (human-rated
   alignment of decision and outcome). The corpus is part of
   the closure-plan's `docs/closure/METACOGNITION_CORPUS.md`
   (follow-up).
2. **Calibration intervals.** The metacognitive loop runs
   `selfEvaluate` every turn, but the **calibration** (the
   measurement of precision and recall against the external
   corpus) runs at intervals (default: every 100 turns, or at
   the end of the session).
3. **Calibration gates.** A `cabal test qxfx0-test-metacognition-calibration`
   suite runs on a held-out corpus. CI fails if precision or
   recall falls below the targets.
4. **Re-calibration trigger.** If the calibration gate fails
   three times in a row, the metacognition contour is marked
   as `Uncalibrated` in the trace, and the bounded correction
   becomes more conservative (per Stage 4's
   `EvaluationUncalibrated` branch).

The discipline is **honest about uncertainty**: the system
recognises when it does not know, and that recognition is part
of the trace.

## 5. Replay gate (handoff to Package 3)

Metacognition is subject to the replay gate:

- **P1 (Serializable)**: `MetacognitionContour` is
  `ToJSON / FromJSON`; roundtrip is identity.
- **P2 (Replayable)**: given a snapshot + the
  `mcRecentEvaluations` log, the contour is reconstructable.
- **P3 (Reconstructable)**: snapshot byte budget 32 KB; event-
  trail byte budget per evaluation 64 B.
- **P4 (Trace-explainable)**: every `Evaluation` is associated
  with a `trcMetacognition` field on `TurnReplayTrace`. Every
  bounded correction is in `trcLearningUpdate` (per Package 8).

## 6. What is NOT in this design

- **Real-time metacognition.** Out of scope. The loop is
  post-hoc.
- **Metacognition of the metacognition (meta-meta-cognition).**
  The `EvaluationUncalibrated` branch is a single level of
  meta; further levels are a research problem.
- **Cross-session metacognition.** Deferred per
  `docs/adr/proposed/0041-cross-session-essence-persistence.md`.
- **LLM-driven metacognition.** The LLM is supplier-flag-off
  (per `AUTHORITY_MAP.md`). The metacognitive loop is pure
  Haskell; it does not consult the LLM.
- **Auto-recalibration.** Calibration is offline; the loop
  measures but does not auto-adjust. Auto-adjustment is a
  follow-up.
- **Per-domain metacognition.** The loop is general. Domain-
  specific metacognition (e.g. "am I good at legal questions?")
  is a follow-up.

## 7. Acceptance criteria for Package 9 closure

- [ ] `QxFx0.Policy.Metacognition` module (new) exposes
      `Outcome`, `Evaluation`, `observeResponse`,
      `selfEvaluate`, `boundedCorrection`.
- [ ] `SystemState.ssMetacognition :: Maybe MetacognitionContour`
      is added; `Nothing` in `emptySystemState`.
- [ ] `trcMetacognition` field on `TurnReplayTrace` carries
      every `Evaluation` and the associated `LearningUpdate` (if
      any).
- [ ] `Test.Suite.Metacognition` (new) ships with:
      - `observeResponse` is total and parser-typed (no keyword
        heuristics);
      - `selfEvaluate` is total and pure;
      - `boundedCorrection` is total and produces a
        `LearningUpdate` only when the four invariants are met.
- [ ] `Test.Suite.MetacognitionCalibration` (new) ships with:
      - precision ≥ 0.85, recall ≥ 0.70 on a held-out corpus;
      - the calibration gate fails CI when targets are not met;
      - the re-calibration trigger fires after 3 consecutive
        failures.
- [ ] `cabal test qxfx0-test-metacognition-calibration` is part
      of the canonical regression lock.
- [ ] `scripts/check_architecture.sh` enforces that
      `observeResponse` does not contain keyword heuristics
      (a `grep` for the legacy keyword lists returns zero
      matches in the new module).
- [ ] Documentation: a single end-to-end example in
      `docs/closure/METACOGNITION_EXAMPLE.md` walks through
      one decision, one outcome, one evaluation, one bounded
      correction, and the resulting trace.

## 8. Honest limits

- The calibration targets (precision ≥ 0.85, recall ≥ 0.70) are
  initial estimates. Real calibration may require different
  targets; the closure plan defers this to Package 11.
- The `Outcome` enum is small. A real metacognitive loop needs
  finer-grained outcomes (e.g. partial acceptance, partial
  rejection, ambiguous acceptance). The closure plan ships
  the initial enum; expansion is an ADR-level decision.
- The `boundedCorrection` mapping is hand-set. A learned
  mapping (e.g. "if `EvaluationMisaligned` and the divergence
  was high, decrement the Field weight by 0.05") is a
  research problem.
- The metacognition loop is **post-hoc**. It cannot affect the
  current turn; only future turns. This is by design, but it
  means real-time self-correction is impossible within this
  design.
- The design assumes Package 8 (bounded learning) is in place.
  Without it, the `boundedCorrection` has nowhere to send the
  update.

## 9. Why this is the right loop

The closure plan rejects "metacognition as keyword-match" and
rejects "metacognition as a thesis". The minimal loop has:

- **One Outcome enum** (six constructors) that is parser-typed.
- **One Evaluation enum** (four constructors) that is calibrated.
- **One BoundedCorrection** that routes through Package 8.
- **One replay-visible trace** that records every decision.

If the loop is too small to be useful in production, the
follow-up (finer-grained Outcomes, learned Correction, real-time
metacognition) each have a small, well-defined scope. If the
loop is too large, it is rejected at review and trimmed.
