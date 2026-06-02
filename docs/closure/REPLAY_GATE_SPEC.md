# Replay Gate Specification

- **Status**: Active (closure-phase work product, Package 3)
- **Date**: 2026-06-02
- **Refines**: ADR-0005 (turn-replay-trace), AGENTS.md ("replay envelope
  fields aligned with runtime contracts"), `docs/interop/README.md`
- **Related**:
  - `docs/closure/SEMANTIC_CORE_MIN_SLICE.md` (Package 2)
  - `docs/closure/GF_AUTHORITY_SUBSET.md` (Package 4)
  - `docs/closure/COGNITIVE_MEMORY_DESIGN.md` (Package 7)
  - `docs/closure/BOUNDED_LEARNING_DESIGN.md` (Package 8)
  - `docs/closure/METACOGNITION_LOOP_DESIGN.md` (Package 9)
  - `docs/closure/adr-0013-role-split.md` (Package 1)

## 0. Why this specification exists

The closure plan's Package 3 says: "after the discussion, this must
be a project-wide law, not a nice-to-have. Any authority-bearing
contour must be serializable, replayable, reconstructable from
snapshot + event history, and trace-explainable."

This document codifies that law. It is the gate every new
authority-bearing contour must pass before merge. It is also
the gate every existing authority-bearing contour must pass
before being labelled `canonical` per the closure plan's Package
1.

## 1. The four properties

Every authority-bearing contour must satisfy:

| Property | Definition | How to check |
|---|---|---|
| **P1. Serializable** | The contour's full state is encodable to a stable wire format (JSON, with a schema-versioned envelope). | `toJSON . roundtrip ≡ id` (property test). |
| **P2. Replayable** | Given a snapshot and an event trail, the contour can be reconstructed deterministically. | `replay snapshot events ≡ live` (property test on a non-trivial trace). |
| **P3. Reconstructable from snapshot + event trail** | The snapshot is small enough to persist, the event trail is small enough to transport, and the reconstruction is total. | Snapshot + event trail byte-budget; reconstruction completeness proof. |
| **P4. Trace-explainable** | Every decision the contour made is associated with a trace field; the trace field is rendered to a stable `Text` and is part of the JSON wire format. | `traceDecisionId -> traceDecisionText` total function; trace field present in every event. |

If a contour fails any of P1–P4, it is not authority-bearing. The
closure plan's Package 1 reclassification moves such contours
to `supplier` or `observer` until the missing property is added.

## 2. What is in scope

The closure plan lists five contour classes that must pass the
replay gate. This specification covers all of them:

| Contour | Owner | Where it lives | Already replay-visible? |
|---|---|---|---|
| **Semantic commitments** | `QxFx0.Semantic.Commitment` (Package 2) | `SystemState.ssSemanticCommitments` | **Yes**, by design (Package 2 §4). |
| **Memory** | `QxFx0.Memory.*` (Package 7) | `SystemState.ssHistory` + new `ssEpisodic` | **Partial** (`ssHistory` is a list; episodic not yet designed). |
| **Learning** | `QxFx0.Learning.*` (Package 8) | `ssCalibrationLog`, `ssAdaptiveMutationLog`, `ssDialogueOutcomeLearning` | **Partial** (logs exist; not replay-traced). |
| **Calibration evidence** | `QxFx0.Self.Salience`, `QxFx0.Self.Field`, `QxFx0.Self.Essence` (Package 11) | `SalienceWeights`, `FieldHeuristics`, `EssenceModulation` snapshots | **Partial** (parameter snapshots exist; not yet replay-traced to corpus). |
| **Metacognitive evaluation** | `QxFx0.Policy.Consciousness` + new module (Package 9) | `ResponseObservation`, future `ssMetacognition` | **No** (current implementation is keyword-conditional in `observeOwnResponse`). |

## 3. The replay envelope (wire format)

### 3.1 Existing envelope

Per `docs/interop/README.md` and AGENTS.md, the project already
commits to a replay envelope at the wire level. The envelope
carries:

- `sessionId :: Text`
- `turnSeq :: Int`
- `inputText :: Text` (raw)
- `deliberation :: Object` (`Self.Deliberation` rendered)
- `recovery :: Object` (LocalRecoveryPlan rendered)
- `renderArtifacts :: Object` (turn artifacts rendered)
- `finalState :: Object` (post-commit `SystemState` snapshot)
- `replayTrace :: Object` (`TurnReplayTrace` rendered, including
  deliberation, essence, salience fields per ADRs 0010-0012)
- `commitments :: Object` (Package 2)
- `envelopeVersion :: Int` (bumped on breaking change)

### 3.2 The closure-plan additions

Package 3 extends the envelope with three new fields, gated on
the corresponding Package landing:

| Field | Owner | Type | When present |
|---|---|---|---|
| `envelopeVersion` | interop | `Int` | always |
| `commitmentLineage` | Package 2 | `Array` of `LineageEvent` | when commitments are enabled |
| `episodicRetrieval` | Package 7 | `Object` | when episodic memory is enabled |
| `learningUpdate` | Package 8 | `Object` | when bounded learning is enabled |
| `calibrationProvenance` | Package 11 | `Object` | when empirical calibration is enabled |
| `metacognition` | Package 9 | `Object` | when metacognitive loop is enabled |

A new contour must declare which envelope fields it populates
and at what version. The `envelopeVersion` bumps when the field
shape changes.

## 4. The event trail

The event trail is the **ordered, typed log of all writes** to a
contour. It is distinct from the snapshot (which is the contour's
state at a point in time) and the trace (which is the contour's
observations about itself and the world).

For each contour:

| Contour | Event type | Source |
|---|---|---|
| Semantic commitments | `LineageEvent` (commit, revise, retract) | `QxFx0.Semantic.Commitment` |
| Semantic commitments | `ContradictionEvent` | `QxFx0.Semantic.Commitment` |
| Memory | `EpisodicEvent` (encode, retrieve, forget) | `QxFx0.Memory.*` (Package 7) |
| Learning | `LearningEvent` (calibration update, adaptive mutation, dialogue outcome) | `QxFx0.Learning.*` (Package 8) |
| Calibration | `CalibrationEvent` (parameter snapshot, corpus pass) | `QxFx0.Self.*` (Package 11) |
| Metacognition | `MetacognitionEvent` (self-observation, self-evaluation, correction) | new module (Package 9) |

The event trail is **append-only** within a session. Cross-
session persistence is a separate concern (deferred per
`docs/adr/proposed/0013-cross-session-essence-persistence.md`).

## 5. Replay discipline

### 5.1 Replay types

Two replay levels are defined:

- **Level 1: state replay.** Given a snapshot of the contour's
  state, reconstruct the state. This is the trivial case (the
  state is the state).
- **Level 2: decision replay.** Given a snapshot + an event trail
  + a decision point, reconstruct the **decision** the contour
  would have made at that point. This is the non-trivial case:
  the decision is the result of the contour's state at the
  decision point, which is a function of the events leading up
  to it.

Level 2 is what the closure plan requires. The property test
`replay snapshot events decisionPoint ≡ liveContour decisionPoint`
must hold for every contour.

### 5.2 Determinism requirement

The contour must be **deterministic over its inputs**. No IO,
no wall-clock, no random, no `IORef`. The closure plan's Package
1's `canonical` class already requires this; the replay gate
re-states it as a hard property.

If a contour cannot be made deterministic (e.g. it integrates an
LLM), the LLM call must be recorded as a typed event in the
trail, and the replay must use the **recorded** LLM response,
not re-invoke the LLM. This is the only way to preserve
replay-trace honesty in the presence of non-deterministic
suppliers.

### 5.3 Snapshot size budget

The snapshot of a contour must fit in a defined byte budget:

| Contour | Budget | Notes |
|---|---|---|
| Semantic commitments | 64 KB per session | 100 commitments × 640 B each (generous). |
| Memory | 256 KB per session | 1k episodic events × 256 B each. |
| Learning | 64 KB per session | 1k updates × 64 B each. |
| Calibration | 16 KB per session | parameter snapshots. |
| Metacognition | 32 KB per session | self-evaluations. |

If a contour exceeds its budget, the closure plan's Package 7
(forgetting policy) and Package 11 (calibration scope) are the
right places to address the overflow, **not** the replay gate
itself.

## 6. The replay gate as CI

The closure plan's Package 3 turns the four properties into CI
gates:

1. **P1 test**: `toJSON . roundtrip ≡ id` property test. Fails
   if the JSON roundtrip is not identity.
2. **P2 test**: `replay snapshot events ≡ live` property test on
   a non-trivial trace (≥ 100 events). Fails if the contour's
   state at the end of the trail differs from the live state.
3. **P3 test**: byte-budget assertion. Fails if the snapshot
   exceeds the budget.
4. **P4 test**: `traceDecisionId -> traceDecisionText` total
   function test. Fails if any decision lacks a trace field.

The CI gate runs on every merge to `main` and on every PR that
touches a contour. A contour that fails any property is **not
merged** until the property holds.

## 7. Replay gate as documentation law

Beyond CI, the replay gate is a **documentation law**. Any ADR
that proposes a new contour must include a "Replay Gate" section
that explicitly:

1. Names the four properties (P1–P4) and the test names.
2. Names the event type and the event-trail source.
3. Names the snapshot byte budget.
4. Names the envelope field that carries the contour's replay
   data, with version.

This is enforced at ADR review; an ADR without a Replay Gate
section is incomplete.

## 8. Migration of existing contours

The five contours in §2 are at different stages of replay
readiness. The migration order is:

1. **Semantic commitments** (Package 2) — landed by design.
2. **Memory** (Package 7) — design + implementation together.
3. **Learning** (Package 8) — design + bounded updates only.
4. **Calibration** (Package 11) — empirical calibration is the
   trigger; before that, parameters are hand-set and the
   provenance is the ADR that pinned them.
5. **Metacognition** (Package 9) — full design, including the
   self-evaluation correlation with external evaluation.

The closure plan's Package 6 (test audit) is where the existing
contour's replay-readiness is audited; a contour that fails P1–P4
is moved to `supplier` or `observer` until the gap is closed.

## 9. Acceptance criteria for Package 3 closure

- [ ] `docs/closure/REPLAY_GATE_SPEC.md` (this file) is merged.
- [ ] `docs/interop/README.md` is updated with the new envelope
      fields from §3.2.
- [ ] `scripts/check_architecture.sh` (or a new
      `scripts/check_replay_gate.sh`) enforces P1–P4 CI gates for
      every existing canonical contour. Initial state: a triage
      list of which contours fail and what the fix is.
- [ ] Every existing ADR that introduces a contour has a "Replay
      Gate" section. A one-pass sweep + addendum process; no
      retroactive rewrite of ADRs is required.
- [ ] Package 2 (`SEMANTIC_CORE_MIN_SLICE.md`) lands the first
      contour that passes the replay gate end-to-end.
- [ ] The remaining four contours (memory, learning, calibration,
      metacognition) have **explicit P1–P4 closure criteria** in
      their respective closure-phase design docs (Packages 7, 8,
      9, 11).

## 10. Honest limits

- The replay gate is a **discipline**, not a tool. There is no
  single "replay tool"; each contour ships its own property
  tests. The closure plan's CI integration (§6) is the
  enforcement mechanism.
- The byte budgets in §5.3 are initial estimates. A real
  session corpus may exceed them; the right response is to
  revisit the budget at Package 7 closure, not to silently
  increase it.
- Level 2 replay (decision replay) is hard to test exhaustively.
  The closure plan commits to a **non-trivial** test (≥ 100
  events), not an exhaustive one. Exhaustive testing is a
  research problem.
- Non-deterministic suppliers (LLMs) are accommodated via
  recorded-event replay (§5.2). This is the right shape, but it
  means LLM-driven contours are not "replayable" in the strict
  sense — they are "replay-recordable". The distinction matters
  for honesty in trace claims.
