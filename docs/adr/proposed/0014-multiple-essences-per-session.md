# ADR-0014 (proposed): Multiple Essences per Session

- **Status**: Proposed (triage stub, not yet a full ADR)
- **Date**: 2026-05-19
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)

## 1. Problem statement

ADR-0012 §8 (fork #8) chose a singular essence: "Exactly one `Essence` per
`Session`."  The `Essence` Σ-type (`src/QxFx0/Self/Essence.hs:98-102`)
allows only `EssenceUncommitted` or `EssenceCommitted` with a single
`EssenceCommitment`.  This reflects the architectural position that
multiple simultaneous essences would be dissociation, not selfhood.

However, real dialogue systems may serve multiple users or contexts within
a single runtime process (e.g. multi-tenant deployment, or a single user
switching between unrelated domains).  A user may want the system to adopt
a `EssenceContemplative` stance for technical analysis and a
`EssenceDialogical` stance for emotional support, without these modes
being averaged into a single `extractMode` output.  The singular design
forces every witnessed turn into one trajectory, which collapses
incommensurable contexts into a single mode histogram.

The question is not merely technical but philosophical: is the system's
"self" unitary by definition (as ADR-0012 asserts), or should the
architecture admit a session-layer multiplexer that maintains one
`EssenceTrajectory` per context, each independently committing?

## 2. Current architecture (what would change)

- `src/QxFx0/Self/Essence.hs:98-102` — The `Essence` sum type would need a
  third constructor or a replacement by a map-like structure:
  `EssenceMulti (Map ContextId (EssenceTrajectory, Maybe EssenceCommitment))`.
- `src/QxFx0/Core/TurnPipeline/Types.hs:115` — `tiEssence :: !Essence`
  would need to know which context's essence to thread into the turn
  pipeline.
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:88-136` — The
  `buildNextSystemState` witness ingestion logic would need to select
  (or create) the correct trajectory bucket based on a `ContextId`
  derived from user input, session metadata, or an explicit operator
  signal.
- `src/QxFx0/Core/TurnPipeline/Route/Effects.hs:55-57` — The reconcile
  courtesy predicate (`Just c`) would need to disambiguate *which*
  commitment is active when multiple commitments coexist.
- `src/QxFx0/Runtime/Session.hs` — `sessSystemState` would carry a
  `Map` instead of a single `Essence`, and bootstrap would initialise
  an empty map rather than `emptyEssence`.

## 3. Open design questions

1. What is the identity of a "context"?  Is it user-scoped, topic-scoped,
   time-window-scoped, or explicitly operator-declared?
2. How does `extractMode` behave when two trajectories independently
   commit to different `EssenceMode`s?  Should the runtime refuse to
   serve both simultaneously, or should it context-switch?
3. Can trajectories merge?  If a user shifts from technical to emotional
   discourse mid-session, should the two trajectories be combined, or
   should one be sealed and a new one started?
4. What is the cardinality bound?  Is there a maximum number of concurrent
   essences per session, or is it unbounded (with GC of dormant trajectories)?
5. Does `validatePlan` check against *all* active commitments, or only
   the commitment of the current context?  A plan that violates one
   context's essence might be admissible in another.
6. How does the trace schema (`trcEssenceMode`, `trcEssenceCommitted`)
  accommodate multiple essences?  One row per context per turn, or a
   JSON array in a single row?
7. Is this feature actually desirable for the QxFx0 research programme,
   or does it belong to a multi-tenant fork with different philosophical
   commitments?

## 4. Estimated complexity

**XL** — dissociation vs. selfhood is a philosophical question with
engineering consequences.  Changing the `Essence` carrier from a sum to
a map ripples through every pipeline phase (prepare, route, render,
finalize) and breaks the current property-test invariants that assume a
single trajectory.  The trace schema, SQLite persistence, and operator
UI all require redesign.  Estimated 2–3 months for a single researcher,
with significant risk of architectural drift from the original
ADR-0012 design intent.

## 5. Why this is not in scope yet

Phase 10 must be production-validated first, and the singular-essence
hypothesis must be empirically tested.  If production traces show that
a single `EssenceTrajectory` consistently produces wrong-mode
commitments in mixed-context sessions, that evidence would justify
reopening fork #8.  Until then, the singular design is a deliberate
simplification that keeps the test surface finite and the architecture
comprehensible.  Multi-tenancy is a deployment concern, not a
selfhood-model concern, and should be addressed at the runtime layer
above `SystemState` rather than inside the `Essence` carrier.

— end of proposed ADR-0014 —
