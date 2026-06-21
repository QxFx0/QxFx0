# ADR-0022 (proposed): Promote Adaptive Mutation

- **Status**: Proposed (closure-phase follow-up F-14, Package 10
  acceptance criteria §5)
- **Date**: 2026-06-02
- **Refines**:
  - AGENTS.md "weak acknowledgement phrases are
    observational and must not trigger strong mutation
    without a shared `AdaptiveMutationRecord` in the
    bounded `ssAdaptiveMutationLog`"
  - [ADR-0034 — Self/Core role split](./0034-self-core-role-split.md)
- **Related**:
  - `docs/closure/SYSTEM_STATE_AUTHORITY.md` (`ssAdaptiveMutationLog` row)
  - `docs/closure/AUTHORITY_MAP.md §6` (Adaptive mutation row)
  - `docs/closure/REPLAY_GATE_TRIAGE.md §2.9` (Learning
    contour; `ssAdaptiveMutationLog` interaction)

## 1. Context

`ssAdaptiveMutationLog` is a bounded log of
`AdaptiveMutationRecord`s. The log is **gated**: per
AGENTS.md, a weak acknowledgement phrase is observational
and must not trigger strong mutation without a shared
`AdaptiveMutationRecord` in the log. The flag
(`QXFX0_ADAPTIVE_MUTATION` or similar) is **off** by
default; the runtime's mutation path is the local-first
explicit one (via the adjunction's modulated-mode, the
field's components, etc.).

The adaptive-mutation path is **distinct** from the
learning path (per Package 8 / `BOUNDED_LEARNING_DESIGN.md`):

- **Learning** modulates `SalienceWeights`,
  `DeliberationWeights`, etc. over multiple turns.
- **Adaptive mutation** is a per-turn, per-record
  adjustment that the system makes in response to a
  weak acknowledgement phrase (e.g. "I see", "ok",
  "got it"). The mutation is recorded in
  `ssAdaptiveMutationLog` and is **bounded** (the log
  has a fixed capacity; old records are dropped).

This ADR commits to the promotion criteria for the
adaptive-mutation flag.

## 2. Decision

### 2.1 The promotion gate

The flag flips from `off` to `on` only when **all four**
of the following hold:

- **G1 — record shape**: the `AdaptiveMutationRecord`
  Σ-type is fully defined; the record carries the
  trigger phrase, the mutation vector, the timestamp
  (deterministic, per AGENTS.md), and the trace
  reference. The record is serializable; the round-trip
  is total.
- **G2 — bounded log**: the `ssAdaptiveMutationLog` has
  a fixed capacity (default 100 records, per
  `SYSTEM_STATE_AUTHORITY.md`); the log's `forgettingPolicy`
  is the same as the episodic memory's (per Package 7).
- **G3 — replay parity**: a fixed-fixture replay under
  `adaptiveMutationEnabled = True` produces trace JSON
  that is **byte-identical** to the `off` baseline on
  the cases where the mutation does not fire (i.e. on
  inputs without a weak acknowledgement phrase).
- **G4 — observability**: the trace records the mutation
  via `trcAdaptiveMutation` (new field); the field is
  present iff the log is non-empty; the field is
  present **at most once per turn** (the log is
  per-turn, not per-phrase).

### 2.2 The release event

When G1–G4 are met, the next release:

1. Changes the default in
   `QxFx0.Core.TurnPipeline.PrepareStatic` (or equivalent)
   from `off` to `on`.
2. Adds a changelog entry under the "Flag flips" section.
3. Updates `docs/closure/SELF_LAYER_STATUS.md` and
   `docs/closure/AUTHORITY_MAP.md` accordingly.

### 2.3 The operational discipline

- **The mutation is bounded.** The log has a fixed
  capacity; old records are dropped. The
  `forgettingPolicy` is the same as the episodic
  memory's.
- **The mutation is observable.** Every mutation is in
  the trace; the trace is replay-visible.
- **The mutation is not a learning event.** The mutation
  is per-turn and per-record; it is not a
  `SalienceWeights` adjustment. The two paths are
  distinct (per `BOUNDED_LEARNING_DESIGN.md §2`).

### 2.4 The interaction with the learning contour

The `ssAdaptiveMutationLog` is read by the learning
contour (per `REPLAY_GATE_TRIAGE.md §2.3`); the
`trcLearningUpdate` field may carry a
`UpdateKindAdaptiveMutation` variant (per
`BOUNDED_LEARNING_DESIGN.md §3`). The interaction is
**gated** by the learning contour's own flags (Package 8
flags); a flag-on adaptive mutation does not imply a
flag-on learning contour.

## 3. Consequences

### 3.1 Positive

- The system gains an opt-in **adaptive mutation** path
  that responds to weak acknowledgement phrases; the
  local-first path is unchanged.
- The bounded log and the trace record make the mutation
  observable; a misfire is detectable from the trace
  alone.

### 3.2 Negative / risks

- A misconfigured trigger (e.g. false-positive on a
  non-acknowledgement phrase) can produce spurious
  mutations. The G3 gate mitigates this on fixed
  fixtures but not on production traffic.
- The interaction with the learning contour
  (per §2.4) is a non-trivial surface; a misfire in
  the mutation can cascade to the contour.

### 3.3 Mitigations

- The replay parity (G3) is a strong gate on fixed
  fixtures.
- The bounded log (G2) is the safety net: the log
  cannot grow unboundedly, and the
  `forgettingPolicy` is the same as the episodic
  memory's.

## 4. Alternatives considered

- **A1: Per-phrase opt-in.** Rejected. The flag is
  already a single bool; per-phrase is over-engineering.
- **A2: Demote the adaptive mutation entirely.** Out of
  scope. The mutation is part of the
  `AdaptiveMutationRecord` contract; demoting it is a
  sister ADR (F-15, conditional).

## 5. Acceptance criteria for this ADR

This ADR is **closed** when:

- [ ] G1, G2, G3, G4 are met and recorded.
- [ ] The default is flipped (per §2.2).
- [ ] The release notes include the "Flag flips" entry.
- [ ] `docs/closure/SELF_LAYER_STATUS.md` and
      `docs/closure/AUTHORITY_MAP.md` are updated.

The ADR is **deferred** until all four criteria are met.
