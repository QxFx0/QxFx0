# Bounded Learning Design

- **Status**: Active (closure-phase work product, Package 8)
- **Date**: 2026-06-02
- **Refines**: ADR-0011 §6.1 (Package B), AGENTS.md ("weak
  acknowledgement phrases are observational and must not trigger
  strong mutation without a shared `AdaptiveMutationRecord`"),
  `docs/adr/0027-phase8-external-learning-loop.md`
- **Related**:
  - `docs/closure/SEMANTIC_CORE_MIN_SLICE.md` (Package 2)
  - `docs/closure/REPLAY_GATE_SPEC.md` (Package 3)
  - `docs/closure/COGNITIVE_MEMORY_DESIGN.md` (Package 7)
  - `docs/closure/METACOGNITION_LOOP_DESIGN.md` (Package 9)
  - `docs/closure/CALIBRATION_BACKLOG.md` (Package 11)
  - `docs/adr/proposed/0034-self-core-role-split.md` (Package 1)

## 0. Why this design exists

The closure plan's Package 8 says: "learning cannot be added in
general. It must be enabled only around already-defined
authority carriers. Define what can adapt, remove zero / stub
signals, link adaptation to dialogue outcomes, semantic revision
quality, retrieval quality, commitment stability. Make learning
bounded, replay-visible, fail-closed."

This document specifies the bounded learning contour. The
discipline is **enablement around authority carriers, not
addition of new learning**: every adaptation must be tied to an
authority-bearing contour (Packages 2, 7, 9), must be
replay-visible (Package 3), and must be bounded by a closed
enum of allowed update kinds.

## 1. The four invariants

The design rests on four invariants that every learning update
must satisfy:

1. **I1. Authority-carrier-only.** A learning update may only
   target an **authority-bearing** contour. The current set:
   - `Self.Salience.SalienceWeights` (canonical)
   - `Self.Field.FieldHeuristics` (canonical)
   - `Self.Essence.EssenceModulation` (canonical-flag-off)
   - `Self.Deliberation.DeliberationModulation` (canonical)
   - `Semantic.Commitment.*` thresholds (Package 2, when landed)
   - `Memory.Episodic.*` thresholds (Package 7, when landed)
   - `Metacognition.*` thresholds (Package 9, when landed)
   The closed list is in `LEARNING_ALLOWED_TARGETS.md` (follow-
   up); CI rejects updates to anything else.
2. **I2. Source-of-signal-only.** A learning update may only
   consume signals from **authority-bearing** sources:
   - `DialogueOutcomeLearning` (existing; replay-traced)
   - `SemanticCommitmentRetraction` (Package 2)
   - `SemanticCommitmentContradiction` (Package 2)
   - `EpisodicRetrievalOutcome` (Package 7)
   - `MetacognitiveEvaluation` (Package 9)
   The closed list is in `LEARNING_ALLOWED_SOURCES.md`; CI
   rejects consumption of any other signal.
3. **I3. Bounded-by-enum.** A learning update is one of a
   closed set of `UpdateKind`s. New kinds require an ADR. The
   initial set:
   - `UpdateKind.Increment` (a scalar in `[0, 1]` is incremented
     by `ε`)
   - `UpdateKind.Decrement` (mirrors Increment)
   - `UpdateKind.Rebind` (a scalar is replaced by a corpus mean)
   - `UpdateKind.Clip` (a scalar is clipped to a closed range)
4. **I4. Replay-visible-and-fail-closed.** Every learning update
   is recorded in the trace. A learning update that would
   violate a hard invariant (e.g. a target outside the closed
   list) **fails closed** (no update is applied; the failure is
   logged to trace with full context).

These four invariants are the closure plan's "bounded, replay-
visible, fail-closed".

## 2. The learning contour

```haskell
data LearningContour = LearningContour
  { lcUpdates :: ![LearningUpdate]     -- append-only log
  , lcLastApplied :: !(Maybe LearningUpdate)
  , lcState :: !LearningState          -- aggregated current values
  , lcSessionId :: !SessionId
  } deriving stock (Eq, Show, Generic)

data LearningUpdate = LearningUpdate
  { luId         :: !LearningUpdateId
  , luTurnSeq    :: !TurnSeq
  , luSource     :: !LearningSource        -- closed enum
  , luTarget     :: !LearningTarget        -- which authority carrier
  , luKind       :: !UpdateKind
  , luDelta      :: !Double                -- in [-1, 1]; clipped if outside
  , luRationale  :: !LearningRationale     -- a small structured description
  , luStatus     :: !UpdateStatus          -- Applied, Rejected, Pending
  } deriving stock (Eq, Show, Generic)

data LearningSource
  = SrcDialogueOutcome !DialogueOutcomeTag
  | SrcCommitmentRetraction !CommitmentId
  | SrcCommitmentContradiction !(CommitmentId, CommitmentId)
  | SrcEpisodicRetrievalOutcome !RetrievalOutcomeTag
  | SrcMetacognitiveEvaluation !EvaluationTag
  deriving stock (Eq, Show, Generic)

data LearningTarget
  = TgtSalienceWeights !Text                -- field name within SalienceWeights
  | TgtFieldHeuristics !Text                -- field name within FieldHeuristics
  | TgtEssenceModulation !Text              -- field name within EssenceModulation
  | TgtDeliberationModulation !Text         -- field name within DeliberationModulation
  | TgtSemanticCommitmentThreshold !Text
  | TgtEpisodicThreshold !Text
  | TgtMetacognitionThreshold !Text
  deriving stock (Eq, Show, Generic)

data UpdateKind
  = UpdateIncrement
  | UpdateDecrement
  | UpdateRebind
  | UpdateClip
  deriving stock (Eq, Show, Generic, Bounded, Enum)

data UpdateStatus
  = UpdateApplied
  | UpdateRejected !Text
  | UpdatePending
  deriving stock (Eq, Show, Generic)
```

The `LearningContour` is the **only** state that learning
operations read or write. It is in `SystemState.ssLearning ::
Maybe LearningContour`; `Nothing` in `emptySystemState`.

## 3. The pure update morphism

```haskell
-- Pure morphism: given the current state, a proposed update,
-- and the current system state, return the updated contour.
-- Total: every input combination has a defined output. The
-- update is applied only if it passes the four invariants;
-- otherwise it is recorded as Rejected.
applyLearningUpdate
  :: LearningContour
  -> LearningUpdate
  -> SystemState
  -> LearningContour
```

`applyLearningUpdate` is **pure**, **total**, and
**replay-visible**. The four invariants are checked in order:

1. **I1**: the target is in `LEARNING_ALLOWED_TARGETS.md`.
2. **I2**: the source is in `LEARNING_ALLOWED_SOURCES.md`.
3. **I3**: the `UpdateKind` is in the closed enum.
4. **I4**: the resulting state is in the closed range for the
   target (e.g. `weightResonance ∈ [0, 1]`).

A failure on any invariant records the update with status
`UpdateRejected` and a human-readable reason. The state is
**unchanged**.

## 4. The integration point

The integration is in the **Finalize** stage, after all Package
2 (commitments) and Package 7 (episodic) writes:

```text
TurnInput, TurnDecision, Commitments, EpisodicEvents, MetacognitionEval
        │
        ▼
proposeLearningUpdate   ← reads from above
        │
        ▼
applyLearningUpdate     ← pure, total, checks 4 invariants
        │
        ▼
LearningContour'        ← applied or rejected (with reason)
        │
        ▼
trcLearningUpdate       ← trace field, both Applied and Rejected
```

The proposal step is **deterministic** for a given
`(commitments, episodic, metacognition, dialogue-outcome)`. The
applied step is `applyLearningUpdate`. The result is recorded
in `trcLearningUpdate` regardless of Applied or Rejected status.

## 5. Replay gate (handoff to Package 3)

Learning is subject to the replay gate:

- **P1 (Serializable)**: `LearningContour` is `ToJSON / FromJSON`;
  the roundtrip is identity (property test).
- **P2 (Replayable)**: given a snapshot + the append-only
  `lcUpdates` log, the state is reconstructable. This is the
  point: learning **is** the event trail; without it, the
  state is not replayable.
- **P3 (Reconstructable)**: snapshot byte budget 64 KB; event-
  trail byte budget per update 256 B; reconstruction is total.
- **P4 (Trace-explainable)**: every applied update is associated
  with a `trcLearningUpdate` field on `TurnReplayTrace`. Every
  **rejected** update is also trace-visible; rejection is part
  of the audit story.

## 6. The bounded-update discipline

The closure plan's "bounded" is operationalised as:

1. **Per-target range.** Each `LearningTarget` has a hard range
   (e.g. `weightResonance ∈ [0, 1]`). The `Clip` update kind
   enforces the range; `Increment` and `Decrement` are clipped
   to the range.
2. **Per-turn rate limit.** A target may receive at most N
   updates per turn (default N=1). The second update in the
   same turn is `UpdateRejected` with reason "rate-limit".
3. **Per-session rate limit.** A target may receive at most M
   updates per session (default M=10). The 11th update is
   `UpdateRejected`.
4. **Rollback.** If a `Rebind` is followed by 3 consecutive
   `UpdateRejected` for the same target, the contour rolls back
   to the last `Applied` value. This is a self-healing
   mechanism.

The rate limits and rollback are **calibration knobs** (Package
11). The initial values are hand-set; the closure plan defers
empirical tuning.

## 7. What is NOT in this design

- **Online gradient descent / backprop.** Out of scope. The
  closure plan's bounded learning is a **discrete-update**
  discipline, not a continuous optimisation. The four
  `UpdateKind`s are the only operations.
- **LLM-driven learning.** The LLM transport is supplier-flag-
  off (per `AUTHORITY_MAP.md`). Learning does not consume LLM
  outputs; this is the "fail-closed" part of the discipline.
- **Cross-session learning.** Deferred per
  `docs/adr/proposed/0041-cross-session-essence-persistence.md`.
  In-session only.
- **Multi-target atomic updates.** A single `LearningUpdate`
  targets one `LearningTarget`. Atomic multi-target updates are
  a follow-up; the design assumes one-target-per-update.
- **Learning of new commitment classes.** The semantic contour
  (Package 2) ships one class; learning cannot add new classes.
  New classes are an ADR-level decision.
- **Auto-proposal.** A learning update is proposed by the
  orchestrator at Finalize time; there is no auto-proposal
  loop. The orchestrator is the only proposer.

## 8. Acceptance criteria for Package 8 closure

- [ ] `QxFx0.Learning.Contour` module (new) exposes
      `LearningContour`, `LearningUpdate`, `applyLearningUpdate`,
      the four invariants, and the four `UpdateKind`s.
- [ ] `SystemState.ssLearning :: Maybe LearningContour` is
      added; `Nothing` in `emptySystemState`.
- [ ] `trcLearningUpdate` field on `TurnReplayTrace` carries
      every Applied and Rejected update.
- [ ] `LEARNING_ALLOWED_TARGETS.md` and `LEARNING_ALLOWED_SOURCES.md`
      are checked into `docs/closure/` with the closed lists.
- [ ] `Test.Suite.LearningContour` (new, replacing
      `Test.Suite.LearningLoop`) ships with:
      - the four invariants are checked (one test per invariant);
      - `applyLearningUpdate` is total and pure;
      - the rate limits are enforced;
      - rollback triggers after 3 consecutive rejections;
      - rejected updates are still trace-visible.
- [ ] `scripts/check_architecture.sh` enforces I1–I4.
- [ ] The existing `ssAdaptiveMutationLog`,
      `ssCalibrationLog`, `ssDialogueOutcomeLearning` are
      reclassified as `LearningContour`-derived (per
      `AUTHORITY_MAP.md §8`).
- [ ] Documentation: a single end-to-end example in
      `docs/closure/LEARNING_EXAMPLE.md` walks through one
      proposed update, one applied update, one rejected update
      (with reason), and the resulting `LearningContour`.

## 9. Honest limits

- The design is **one** learning contour. A real bounded-
  learning system needs separate contours for fast (per-turn)
  and slow (per-session) learning. The closure plan ships
  one; the per-turn / per-session split is a follow-up.
- The four `UpdateKind`s are **discrete**. They cannot express
  "move 0.7 of the way toward the corpus mean". A `Rebind` is
  all-or-nothing. Continuous learning is a research problem.
- The rate limits (per-turn, per-session) are hand-set. The
  closure plan's Package 11 (calibration) tunes them against
  the production trace corpus.
- The rollback rule is **simple**. A real rollback would
  maintain a history of the last K applied values and select
  the one with the best held-out performance. The closure
  plan's rollback is "last applied".
- The design assumes the semantic contour (Package 2), the
  episodic contour (Package 7), and the metacognitive contour
  (Package 9) are in place. Without any of them, the
  `LearningSource` enum is half-empty.
