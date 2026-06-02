# Bounded Learning — End-to-End Example

- **Status**: Active (closure-phase follow-up F-07, Package 8
  acceptance criteria §8)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/BOUNDED_LEARNING_DESIGN.md` §3
- **Related**:
  - `docs/closure/LEARNING_ALLOWED_TARGETS.md` (F-03)
  - `docs/closure/LEARNING_ALLOWED_SOURCES.md` (F-04)
  - `docs/closure/METACOGNITION_EXAMPLE.md` (F-08)

## 0. What this example is

A single end-to-end walkthrough of one **proposed** learning
update, one **applied** learning update, and one **rejected**
learning update (with reason) against the `LearningContour`
from Package 8 §2. The example uses the four pure
invariants (I1–I4) and the four `UpdateKind`s.

The example continues the scenario from
`SEMANTIC_CORE_EXAMPLE.md` (F-05) and
`EPISTEMIC_MEMORY_EXAMPLE.md` (F-06): the same 4-turn
dialogue, with the system proposing a learning update based
on the commitment retraction at turn 4.

## 1. The scenario

A 4-turn dialogue. At turn 4, the system retracts commitment
1 (the developer fact, per F-05). The orchestrator proposes
a learning update based on this retraction.

| Update | Source | Target | Kind | Status |
|---|---|---|---|---|
| U-1 | `SrcCommitmentRetraction 1` | `TgtSalienceWeights "weightResonance"` | `UpdateDecrement` | applied |
| U-2 | `SrcCommitmentRetraction 1` | `TgtNonExistent "weightX"` | `UpdateDecrement` | rejected (I1) |
| U-3 | `SrcNonExistent "SrcWhatever"` | `TgtSalienceWeights "weightResonance"` | `UpdateDecrement` | rejected (I2) |

U-1 is the success case. U-2 violates invariant I1 (target
not in the allowlist). U-3 violates invariant I2 (source
not in the allowlist). Both are recorded as `UpdateRejected`
with reason; neither mutates the state.

## 2. The proposed update

### 2.1 The proposed update

```haskell
proposedU1 :: LearningUpdate
proposedU1 = LearningUpdate
  { luId        = LearningUpdateId 1
  , luTurnSeq   = TurnSeq 4
  , luSource    = SrcCommitmentRetraction (CommitmentId 1)
  , luTarget    = TgtSalienceWeights "weightResonance"
  , luKind      = UpdateDecrement
  , luDelta     = -0.05  -- decrement by 0.05
  , luRationale = LearningRationale
      { lrCommit = CommitmentId 1
      , lrReason  = "RetractionUserDenied; weightResonance likely too high"
      }
  , luStatus    = UpdatePending
  }
```

### 2.2 The four invariants

The pure morphism `applyLearningUpdate` checks:

1. **I1 (target allowlist)**: `TgtSalienceWeights
   "weightResonance"` is in
   `LEARNING_ALLOWED_TARGETS.md` (T-01). ✓
2. **I2 (source allowlist)**: `SrcCommitmentRetraction
   (CommitmentId 1)` is in
   `LEARNING_ALLOWED_SOURCES.md` (S-02). ✓
3. **I3 (closed enum)**: `UpdateDecrement` is in
   `{UpdateIncrement, UpdateDecrement, UpdateRebind,
   UpdateClip}`. ✓
4. **I4 (range check)**: the resulting `weightResonance` is
   in `[0, 1]`. Current value `0.4`, delta `-0.05`, new
   value `0.35` ∈ `[0, 1]`. ✓

All four invariants pass. The update is applied.

## 3. The applied update

```haskell
contour0 :: LearningContour
contour0 = emptyLearningContour (SessionId "sess-1")

currentSalience :: SalienceWeights
currentSalience = defaultSalienceWeights
  -- weightResonance = 0.4 (from defaultSalienceWeights)

contour1 :: LearningContour
contour1 = applyLearningUpdate contour0 proposedU1 undefined
  -- SystemState parameter is for trace cross-referencing;
  -- undefined is fine in this synthetic example.
```

`contour1` has:

- `lcUpdates = [proposedU1 { luStatus = UpdateApplied }]`
- `lcLastApplied = Just proposedU1`
- `lcState` updated to reflect the new `weightResonance =
  0.35`.

The `trcLearningUpdate` trace field on `TurnReplayTrace`
records the applied update with `UpdateApplied` status and
the new value.

## 4. The rejected update (I1 violation)

```haskell
proposedU2 :: LearningUpdate
proposedU2 = proposedU1
  { luId     = LearningUpdateId 2
  , luTarget = TgtNonExistent "weightX"  -- not in the allowlist
  }

contour2 :: LearningContour
contour2 = applyLearningUpdate contour1 proposedU2 undefined
```

`contour2` has:

- `lcUpdates = [proposedU1, proposedU2 { luStatus = UpdateRejected "I1: target not in allowlist" }]`
- `lcLastApplied = Just proposedU1` (unchanged)
- `lcState` unchanged.

The `trcLearningUpdate` trace field records the rejected
update with the I1 reason. The state is **fail-closed**: no
mutation.

## 5. The rejected update (I2 violation)

```haskell
proposedU3 :: LearningUpdate
proposedU3 = proposedU1
  { luId     = LearningUpdateId 3
  , luSource = SrcNonExistent "SrcWhatever"  -- not in the allowlist
  }

contour3 :: LearningContour
contour3 = applyLearningUpdate contour2 proposedU3 undefined
```

`contour3` has:

- `lcUpdates = [proposedU1, proposedU2, proposedU3 { luStatus = UpdateRejected "I2: source not in allowlist" }]`
- `lcState` unchanged.

The discipline is consistent: the rejected updates are
trace-visible but do not mutate state.

## 6. Rate limits

The per-turn rate limit (default: 1 update / turn) is also
enforced. If two updates are proposed in the same turn:

```haskell
proposedU4 :: LearningUpdate
proposedU4 = proposedU1 { luId = LearningUpdateId 4 }

contour4 :: LearningContour
contour4 = applyLearningUpdate contour3 proposedU4 undefined
-- contour4.lcUpdates[3] (proposedU4) has status UpdateRejected "rate-limit per-turn"
```

The second update in the same turn is rejected. The
rejection is recorded in the trace.

The per-session rate limit (default: 10 updates / session)
is similar: the 11th update is rejected.

## 7. Rollback

If 3 consecutive updates to the same target are rejected:

```haskell
proposedU5 :: LearningUpdate  -- also rejected
proposedU6 :: LearningUpdate  -- also rejected
proposedU7 :: LearningUpdate  -- also rejected

contour7 :: LearningContour
contour7 = applyLearningUpdate contour4 proposedU7 undefined
-- After 3 consecutive rejections, contour7 rolls back
-- weightResonance to the last applied value (0.35).
```

The rollback is **explicit and trace-visible**: a
`trcLearningRollback` field records the rollback.

## 8. Replay verification

The replay gate (Package 3) requires:

```haskell
replay :: LearningContour -> [TurnSeq] -> [LearningUpdate]
replay contour _ = lcUpdates contour
```

For the example, `replay contour4 _` returns the 4 updates
in order:

```
[proposedU1 (applied, decrement 0.4 → 0.35),
 proposedU2 (rejected, I1),
 proposedU3 (rejected, I2),
 proposedU4 (rejected, rate-limit)]
```

The reconstruction is total and deterministic; a property
test verifies `replay finalContour _` equals the expected
update stream for a given input.

## 9. What this example does not show

- The **commitment store** that the retraction comes from.
  The example uses commitment ids directly; a real session
  has the `SemanticCommitmentStore` from F-05.
- The **episodic memory** that the retrieval outcome comes
  from. The example uses `SrcCommitmentRetraction` only.
- The **metacognitive evaluation** that proposes updates
  based on `EvaluationMisaligned`. Package 9's example
  (F-08) shows this.
- The **rate-limit calibration** for `episodicCapacity` and
  `episodicWindow`. The example uses defaults; Package 11
  tunes them.
- The **rollback-to-last-applied** for non-rate-limit
  cases. The example uses rate-limit-triggered rollback.

## 10. Acceptance criteria for F-07

F-07 is closed when:

- [ ] This file is merged.
- [ ] The example compiles against `QxFx0.Learning.Contour`
      (post-Package 8) without modification.
- [ ] The four invariants are part of
      `Test.Suite.LearningContour` (new) as unit tests.
- [ ] The rate limits and rollback are part of
      `Test.Suite.LearningContour` as property tests.
- [ ] The replay verification is part of
      `Test.Suite.LearningContour` as a property test.
- [ ] The `check_architecture.sh` extension enforces I1–I4.
