# Metacognition — End-to-End Example

- **Status**: Active (closure-phase follow-up F-08, Package 9
  acceptance criteria §7)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/METACOGNITION_LOOP_DESIGN.md` §1
- **Related**:
  - `docs/closure/LEARNING_EXAMPLE.md` (F-07)
  - `docs/closure/METACOGNITION_CORPUS.md` (F-09)

## 0. What this example is

A single end-to-end walkthrough of one **decision**, one
**outcome**, one **evaluation**, and one **bounded
correction** in the metacognitive loop from Package 9 §1.

The example continues the scenario from
`SEMANTIC_CORE_EXAMPLE.md` (F-05),
`EPISTEMIC_MEMORY_EXAMPLE.md` (F-06), and
`LEARNING_EXAMPLE.md` (F-07): the same 4-turn dialogue.
The metacognitive evaluation of turn N-1 happens at turn N.

## 1. The scenario

A 4-turn dialogue. The metacognitive loop observes the
outcome of turn N-1 at turn N.

| Turn | Decision at turn N | Outcome at turn N (observed) | Evaluation at turn N | Bounded correction |
|---|---|---|---|---|
| 1 | family: CMContact, style: Direct, tone: Warm | (turn 1's outcome observed at turn 2) | — | — |
| 2 | family: CMDeepen, style: Direct, tone: Neutral | (turn 2's outcome observed at turn 3) | — | — |
| 3 | family: CMRepair, style: Direct, tone: Warm | (turn 3's outcome observed at turn 4) | — | — |
| 4 | family: CMContact, style: Direct, tone: Warm | `OutcomeRejected` (user retracts the developer fact) | `EvaluationMisaligned` (turn 4's decision assumed the developer fact was true; outcome contradicts) | `UpdateDecrement` on `weightResonance` |
| 5 | family: CMContact, style: Direct, tone: Neutral | `OutcomeAccepted` | `EvaluationAligned` (turn 5's decision is consistent with the retraction; outcome confirms) | none |

The metacognitive evaluation of turn N happens at turn N+1.
The bounded correction of turn N+1's evaluation is the
**input** to turn N+1's decision (per the closure plan's
"post-hoc" discipline, the correction affects future turns,
not the current one).

## 2. Turn 2: observe turn 1's outcome

### 2.1 The outcome

```haskell
outcome1 :: Outcome
outcome1 = OutcomeAccepted
-- The user accepts turn 1's response: "I am a software developer."
-- The user's turn 2 is "I work in Haskell.", which confirms turn 1.
```

### 2.2 The self-evaluation

```haskell
decision1 :: TurnDecision
decision1 = TurnDecision
  { tdFamily  = CMContact
  , tdStyle   = Direct
  , tdTone    = Warm
  , tdTurnSeq = TurnSeq 1
  }

evaluation1 :: Evaluation
evaluation1 = selfEvaluate decision1 outcome1
-- = EvaluationAligned
```

The self-evaluation is **pure** and **replay-visible**. The
`trcMetacognition` field on `TurnReplayTrace` records:

```haskell
trcMetacognition = Just MetacognitionTrace
  { mtDecisionTurn  = TurnSeq 1
  , mtOutcome       = OutcomeAccepted
  , mtEvaluation    = EvaluationAligned
  , mtCalibration   = Calibrated
  }
```

### 2.3 The bounded correction

```haskell
correction1 :: Maybe LearningUpdate
correction1 = boundedCorrection evaluation1
-- = Nothing
-- (EvaluationAligned produces no update; positive feedback
-- is captured by the absence of retraction.)
```

`correction1` is `Nothing`; no `LearningContour` update is
produced.

## 3. Turn 3: observe turn 2's outcome

```haskell
outcome2 :: Outcome
outcome2 = OutcomeAccepted
-- The user accepts turn 2's response about Haskell.

evaluation2 :: Evaluation
evaluation2 = selfEvaluate decision2 outcome2
-- = EvaluationAligned

correction2 :: Maybe LearningUpdate
correction2 = boundedCorrection evaluation2
-- = Nothing
```

## 4. Turn 4: observe turn 3's outcome

```haskell
outcome3 :: Outcome
outcome3 = OutcomeRefined
-- The user refines: "Actually I work in OCaml, not Haskell."
-- (refinement is a soft form of rejection.)

evaluation3 :: Evaluation
evaluation3 = selfEvaluate decision3 outcome3
-- = EvaluationMisaligned
-- (turn 3's response committed to Haskell; outcome
-- contradicts; the decision was wrong.)

correction3 :: Maybe LearningUpdate
correction3 = boundedCorrection evaluation3
-- = Just proposedU1' :: LearningUpdate
-- (a decrement on weightResonance, similar to F-07 §2)
```

The bounded correction is **routed through Package 8**: it
goes through `applyLearningUpdate`, which checks the four
invariants and applies or rejects it.

```haskell
contour3' :: LearningContour
contour3' = applyLearningUpdate (lc contour2) correction3' systemState
-- = contour2' (with the new weightResonance)
```

The `trcLearningUpdate` trace field records the applied
update (per Package 8).

## 5. Turn 5: observe turn 4's outcome

```haskell
outcome4 :: Outcome
outcome4 = OutcomeRejected
-- The user rejects turn 4's response: "I lied, I am not a developer at all."
-- (this is the same event as F-05's retraction.)

evaluation4 :: Evaluation
evaluation4 = selfEvaluate decision4 outcome4
-- = EvaluationMisaligned
-- (turn 4's decision assumed the developer fact was true;
-- outcome contradicts; the decision was wrong.)

correction4 :: Maybe LearningUpdate
correction4 = boundedCorrection evaluation4
-- = Just proposedU1'' :: LearningUpdate
-- (another decrement on weightResonance, or possibly a
-- larger one; the discipline is bounded by I3 = closed enum.)
```

## 6. Turn 6: observe turn 5's outcome

```haskell
outcome5 :: Outcome
outcome5 = OutcomeAccepted
-- The user accepts turn 5's response (which is now consistent
-- with the retraction; the decision is post-correction).

evaluation5 :: Evaluation
evaluation5 = selfEvaluate decision5 outcome5
-- = EvaluationAligned

correction5 :: Maybe LearningUpdate
correction5 = boundedCorrection evaluation5
-- = Nothing
```

## 7. The calibration discipline

The `trcMetacognition` field carries a `mtCalibration` tag
that tracks the system's calibration state:

- `Calibrated` — precision and recall are within targets.
- `Drifting` — at least one of the targets is off, but the
  re-calibration trigger has not fired.
- `Uncalibrated` — three consecutive calibration failures;
  the system becomes more conservative (per Package 9 §4).

In the example, the metacognitive loop is well-calibrated
(evaluations match outcomes). The `mtCalibration = Calibrated`
throughout.

A `cabal test qxfx0-test-metacognition-calibration` suite
verifies the calibration on a held-out corpus (per Package 9
§1.3). The example does not show the corpus; the corpus
spec is in `METACOGNITION_CORPUS.md` (F-09).

## 8. Replay verification

The replay gate (Package 3) requires:

```haskell
replay :: MetacognitionContour -> [TurnSeq] -> [Evaluation]
replay contour _ = toList (mcRecentEvaluations contour)
```

For the example, `replay contour _` returns the 5 evaluations
in turn order:

```
[EvaluationAligned (turn 1 → 2),
 EvaluationAligned (turn 2 → 3),
 EvaluationMisaligned (turn 3 → 4),
 EvaluationMisaligned (turn 4 → 5),
 EvaluationAligned (turn 5 → 6)]
```

The reconstruction is total and deterministic; a property
test verifies `replay finalContour _` equals the expected
evaluation stream for a given input.

## 9. What this example does not show

- The **calibration corpus** that the calibration gate
  uses. F-09 specifies the corpus.
- The **external labels** that ground the calibration.
  The example uses self-reported `Evaluation`s; a real
  session has external human ratings to compare against.
- The **re-calibration trigger** after 3 consecutive
  failures. The example is well-calibrated; the trigger is
  not exercised.
- The **automatic correction** of the system's
  `weightResonance` (the bounded correction is **routed
  through Package 8**, not applied directly).
- The **LLM-driven metacognition** that the closure plan
  rejects. The example is pure Haskell.

## 10. Acceptance criteria for F-08

F-08 is closed when:

- [ ] This file is merged.
- [ ] The example compiles against
      `QxFx0.Policy.Metacognition` (post-Package 9) without
      modification.
- [ ] The four stages of the loop are part of
      `Test.Suite.Metacognition` (new) as unit tests.
- [ ] The calibration discipline is part of
      `Test.Suite.MetacognitionCalibration` (new) as
      property tests.
- [ ] The replay verification is part of
      `Test.Suite.Metacognition` as a property test.
- [ ] The `check_architecture.sh` extension enforces that
      `observeResponse` does not contain keyword heuristics.
