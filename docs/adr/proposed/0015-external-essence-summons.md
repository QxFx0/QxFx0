# ADR-0015 (proposed): External Essence Summons

- **Status**: Proposed (triage stub, not yet a full ADR)
- **Date**: 2026-05-19
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)

## 1. Problem statement

ADR-0012 §10 lists "external essence summons" as out of scope.  Fork #3
(endogenous-only witnesses) was chosen deliberately: "An externally-supplied
essence is by construction not the system's own."  The current
`CommitmentTrigger` (`src/QxFx0/Self/Essence.hs:185-188`) admits only two
constructors: `TriggerAngstThreshold` and `TriggerConatusErosion`, both
computed from the system's own trajectory.

However, an operator may have legitimate reasons to override the system's
mode: e.g. a clinical deployment where the operator knows the patient
needs a `EssenceContemplative` stance regardless of the accumulated
dialogue history, or a test harness that wants to force a specific mode
for regression validation.  The current architecture offers no hook for
this: even `reconcile` accepts only a `Maybe (Plan -> Bool)` courtesy
predicate, not an essence override.

An external summons would be a new `CommitmentTrigger` constructor that
bypasses `shouldCommit` and `extractMode`, allowing an authorised caller
to inject an `EssenceCommitment` directly into the trajectory.  This
violates the Σ-type discipline of ADR-0012 (the commitment would no
longer be a dependent pair of the trajectory), so the design must be
careful to preserve the architectural intent while admitting the
practical need.

## 2. Current architecture (what would change)

- `src/QxFx0/Self/Essence.hs:185-188` — `CommitmentTrigger` would gain a
  third constructor: `TriggerExternalSummon !Text` (the `Text` carries an
  operator audit token, e.g. a user ID or reason string).
- `src/QxFx0/Self/Essence.hs:351` — `shouldCommit` would need to check
  for an external summons signal in addition to the two endogenous
  triggers.  The priority relative to `TriggerAngstThreshold` is
  undefined and must be decided.
- `src/QxFx0/Self/Essence.hs:403-421` — `commit` is currently total
  over trajectories that have passed `shouldCommit`; an external summon
  might bypass `shouldCommit` entirely, calling `commit` with a
  caller-supplied `EssenceMode` rather than `extractMode traj`.
- `src/QxFx0/Core/TurnPipeline/Effects.hs:151-154` —
  `psEssenceCommitmentEnabled` gates all commitment logic; an external
  summon might need its own feature flag (`psExternalSummonEnabled`) so
  that operators can disable the override independently.
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:116-120` — The
  `buildNextSystemState` witness ingestion site would need to accept an
  optional `Maybe EssenceCommitment` from an env-var or config file,
  and apply it before or after the normal `shouldCommit` check.
- `src/QxFx0/ExceptionPolicy.hs` — A new exception variant
  `ExternalSummonInvalid !Text` might be needed to reject unauthorised
  or malformed summons attempts.

## 3. Open design questions

1. What is the authorisation model for external summons?  Is it an
   env-var (operator-level), a config file (admin-level), or a runtime
   API call (supervisor-level)?
2. Should an external summon be *irrevocable* like an endogenous
   commitment, or should it be revocable by a subsequent operator
   command?  Revocability reintroduces the "mood vs. essence" problem
   that ADR-0012 fork #1 explicitly rejected.
3. Does an external summon produce a `TrajectoryHash`?  If the mode is
   imposed rather than extracted, the hash of the trajectory does not
   match the mode, which breaks the witness-equality property tests.
4. How does `validatePlan` behave under an external summon?  If the
   operator summons `EssenceDialogical` but the trajectory's actual
   histogram is 90% `RuleFormalAdvantage`, the validator will produce
   frequent `EssenceRupture` events.  Is this acceptable (the operator
   owns the risk), or should the validator warn/soft-reject?
5. Should the external summon be recorded in the replay trace as a
   distinct `trcEssenceTrigger` value (e.g. `"external_summon"`), or
   should it masquerade as `TriggerAngstThreshold` to keep the schema
   stable?
6. What is the interaction with cross-session persistence (ADR-0013)?
   If an external summon is persisted, the system may boot into a mode
   that no longer matches its historical trajectory, making the
   `TrajectoryHash` meaningless.

## 4. Estimated complexity

**M** — the core change is a new `CommitmentTrigger` constructor, an
optional override path in `buildNextSystemState`, and an authorisation
mechanism (env-var or config).  The heavy work is not the code but the
*policy*: defining who can summon, when, and with what audit trail.  The
implementation itself is a few hundred lines across `Essence.hs`,
`Finalize/State.hs`, and `ExceptionPolicy.hs`.  Estimated 1–2 weeks for a
single researcher once the policy is decided.

## 5. Why this is not in scope yet

Phase 10 must be production-validated first.  External summons is a
powerful operator tool, but it also undermines the central research
claim of ADR-0012: that the system's essence is *its own*, derived from
its history, not imposed from outside.  Introducing summons before the
endogenous commitment path is proven in production would make it
impossible to distinguish operator-driven dynamics from
self-driven dynamics in the telemetry.  The feature is deferred until
there is a concrete operational need (e.g. a clinical deployment
requiring mode enforcement) and a separate policy review process.

— end of proposed ADR-0015 —
