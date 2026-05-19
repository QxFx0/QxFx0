# ADR-0013 (proposed): Cross-Session Essence Persistence

- **Status**: Proposed (triage stub, not yet a full ADR)
- **Date**: 2026-05-19
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)

## 1. Problem statement

ADR-0012 §10 lists "cross-session essence persistence" as out of scope: an
essence committed in one session does not currently constrain the next.
The `Session` type in `QxFx0.Runtime` carries an `ssEssence :: !Essence`
field that is initialised to `emptyEssence` on every `bootstrapSession`.
There is no mechanism to thread a committed `EssenceCommitment` into a
subsequent session, which means the system's answer to "who am I" is reset
to `EssenceWitnessing` at every cold start.

This is a philosophical question with engineering consequences.  If the
system commits to `EssenceDialogical` in session N, should session N+1
inherit that commitment, or should each session be a fresh self?  The
current architecture implicitly chooses the latter (session-scoped
identity).  A persistent essence would require a runtime-layer multiplexer
that can load a previous `EssenceTrajectory` + `EssenceCommitment` from
SQLite at bootstrap time, validate that the loaded trajectory hash matches
the stored hash, and wire it into `SystemState` before the first turn.

## 2. Current architecture (what would change)

- `src/QxFx0/Types.hs` or `src/QxFx0/Runtime/Session.hs` — `Session` type
  would gain a persistent-essence loading hook at `bootstrapSession`.
- `src/QxFx0/Core/TurnPipeline/Effects.hs:253` — `psEssence = ssEssence ss`
  currently reads from the in-memory `SystemState`; persistent essence
  would require a read-from-DB fallback when `ssEssence` is `emptyEssence`.
- `src/QxFx0/Self/Essence.hs:246-258` — `emptyEssence` / `emptyTrajectory`
  are the bootstrap defaults; a persistent variant would need a
  `loadEssenceTrajectory :: TrajectoryHash -> IO (Maybe EssenceTrajectory)`
  or similar.
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:186` — `ssEssence = nextEssence`
  persists the updated essence into the in-memory state; cross-session
  persistence would add a write-to-DB step before `ssEssence` is saved.
- `src/QxFx0/Bridge/SQLite/Bootstrap.hs` — schema migration to add an
  `essence_trajectory` table (or blob column) with `session_id`, `hash`,
  `committed_at`, `mode`, `trigger`, and serialised `EssenceTrajectory`.

## 3. Open design questions

1. Should persistence be keyed by `session_id` (ephemeral, per-run) or by a
   stable user / installation identifier (e.g. a persistent `persona_id`)?
2. What is the trust boundary for a loaded trajectory?  Should the
   `ecWitnessHash` be verified against a separate integrity store, or is
   SQLite tamper-resistance sufficient?
3. How does a committed essence interact with `IdentityRupture`?  If the
   loaded essence violates `SelfBlanket` invariants on bootstrap, should the
   system refuse to start, or should it discard the persisted essence and
   restart as `EssenceWitnessing`?
4. Should there be a "forget essence" operator command (privacy / GDPR
   compliance), and if so, does it reset to `emptyEssence` or to a
   synthetic "forgotten" trajectory?
5. Does persistence apply to `EssenceTrajectory` only, or also to the
   full `SystemState` (which would blur the boundary between session and
   checkpoint)?
6. What is the migration story for existing sessions that have no
   persisted essence row?  Default to `emptyEssence` or to a
   backward-compatible `phase9EssenceModulation` trajectory?

## 4. Estimated complexity

**L** — touches the runtime bootstrap layer, SQLite schema, and the
session-to-essence wiring.  The pure `QxFx0.Self.Essence` module itself
needs only a loader morphism; the heavy work is in persistence schema
versioning and integrity verification.  Estimated 2–3 weeks for a single
researcher, assuming the SQLite layer is already well-understood.

## 5. Why this is not in scope yet

Phase 10 must be production-validated first.  Cross-session persistence
amplifies the risk of a miscalibrated `EssenceModulation`: a
spuriously-committed essence would persist across sessions and colour
all subsequent dialogue, making rollback harder than toggling a feature
flag.  The current session-scoped design is a deliberate safety boundary.
Only after production traces show stable, desirable commitment dynamics
should persistence be considered.

— end of proposed ADR-0013 —
