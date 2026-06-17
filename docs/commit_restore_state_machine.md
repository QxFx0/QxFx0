# Commit / Restore State Machine
Status: Verified
Front: `commit / restore state machine`

---

## 1. Purpose

This document makes the actual commit/restore machine explicit enough that:

- durable authoritative truth
- projection truth
- runtime-ephemeral commit
- rollback scope
- rebuild scope
- best-effort post-commit work

are no longer mixed by implication.

This is not a whole-system persistence redesign. It is a bounded truth-boundary artifact for the current machine.

---

## 2. Authoritative Truth Boundary

### 2.1 Durable authoritative truth

The durable authoritative turn truth is:

- `runtime_sessions.state_revision`
- canonicalized `SystemState` stored in `dialogue_state` under `__system_state__`

Evidence:
- `src/QxFx0/Bridge/StatePersistence.hs:96-130`
- `src/QxFx0/Bridge/StatePersistence.hs:186-196`

Authoritative commit is not complete until the `BEGIN IMMEDIATE ... COMMIT` transaction containing:

1. revision CAS
2. `runtime_sessions.last_active/status` touch
3. `__system_state__` write
4. `turn_quality` write if present
5. `shadow_divergence_log` write if present

has committed.

### 2.2 Projection truth

The persisted projection/audit truth is:

- `turn_quality`
- `shadow_divergence_log`
- `replay_trace_json` embedded in `turn_quality`

This is persisted truth, but not the winner for restart authority.

### 2.3 Runtime-only commit

The in-memory runtime commit is:

- consciousness loop MVar state
- intuition/runtime turn state hydration

This is live continuity state, not durable truth.

### 2.4 Best-effort post-commit work

Best-effort post-commit work is:

- checkpoint request
- metrics logging
- injected test tail exception contour

These do not determine whether the turn is committed.

---

## 3. Commit Phases

| phase | trigger | writes durable truth? | writes projection truth? | runtime only? | failure branch | truth status after phase |
|---|---|---|---|---|---|---|
| precommit build | finalize/orchestrate | no | no | no | precommit failure | previous truth remains authoritative |
| identity guard | `checkBlanketTransition` | no | no | no | `IdentityRupture` | previous truth remains authoritative |
| essence guard | `fcpEssenceValidation` | no | no | no | `EssenceRupture` | previous truth remains authoritative |
| atomic save | `TurnReqSaveState` | yes | yes | no | tx/CAS/save failure | previous truth remains authoritative |
| runtime commit | `TurnReqCommitRuntimeState` | no | no | yes | commit failure | saved durable truth already exists |
| runtime recovery | rehydrate from saved state | no | no | yes | recovery failure | saved durable truth still exists |
| projection rollback | `TurnReqRollbackTurnProjections` | modifies persisted projection truth only | yes | no | rollback failure | durable truth may remain newer than projections |
| state rollback | `TurnReqSaveState previousState` | yes | maybe no projection | no | rollback save failure | newer saved truth may remain authoritative |
| post-commit tail | checkpoint/metrics | no | no | yes / side-effect only | logged warning only | committed truth remains committed |

Evidence:
- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs:64-145`
- `src/QxFx0/Runtime/Wiring/Handlers.hs:135-141`
- `src/QxFx0/Bridge/StatePersistence.hs:96-130`

---

## 4. Atomic vs Best-Effort Boundary

| step | writes durable truth? | writes projection truth? | runtime only? | rollback required? | best effort? | notes |
|---|---|---|---|---|---|---|
| `checkBlanketTransition` | no | no | no | n/a | no | pre-save guard |
| `fcpEssenceValidation` | no | no | no | n/a | no | pre-save guard |
| `bumpStateRevisionCas` | yes | no | no | yes | no | primary stale-writer gate |
| `touchRuntimeSessionActivity` | yes, metadata | no | no | yes | no | same tx as authoritative save |
| `saveKV __system_state__` | yes | no | no | yes | no | canonical persisted truth |
| `persistTurnQuality` | no | yes | no | yes | no | authoritative projection truth, but not restart truth |
| `persistShadowDivergence` | no | yes | no | yes | no | divergence audit projection |
| `TurnReqCommitRuntimeState` | no | no | yes | recovery, not SQL rollback | no | runtime continuity only |
| `recoverRuntimeTurnState` | no | no | yes | failure escalates | no | runtime restore from persisted snapshot |
| `TurnReqRollbackTurnProjections` | no | yes | no | best-effort cleanup on double failure | no | trims projection rows above stable turn |
| rollback save of previous state | yes | maybe projection-less | no | yes | no | attempts to restore previous authoritative blob |
| checkpoint | no | no | yes/side effect | no | yes | post-commit housekeeping |
| metrics log | no | no | yes/side effect | no | yes | post-commit observability |

---

## 5. Failure / Rollback Matrix

| failure point | what remains truth | what must rollback | what may remain and be rebuilt | what must surface |
|---|---|---|---|---|
| before authoritative save | previous persisted state | nothing new | n/a | hard failure |
| authoritative save tx/CAS fails | previous persisted state | nothing new | n/a | hard failure / conflict diagnostics |
| after authoritative save, before runtime commit | new persisted state | no SQL rollback yet | runtime state may be recovered from persisted snapshot | warning or later failure |
| runtime commit fails, runtime recovery succeeds | new persisted state | no rollback | runtime state rehydrated from persisted snapshot | warning only |
| runtime commit fails, recovery fails, projection rollback succeeds, state rollback succeeds | previous persisted state restored | projection rows above stable turn and failed state blob | runtime state must be considered failed; next restore may rebuild | hard failure with rollback status |
| runtime commit fails, recovery fails, projection rollback fails, state rollback succeeds | previous persisted state restored | state blob only | projection residue may remain, but restart truth follows restored blob | hard failure with rollback status |
| runtime commit fails, recovery fails, state rollback fails | newer persisted blob remains authoritative | projection rollback may or may not have succeeded | runtime state not trusted; future restore still anchored on saved blob | hard failure with explicit rollback statuses |
| post-commit hook fails | committed state/projection truth remains | nothing | later observability/checkpoint can be retried | warning only |

Evidence:
- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs:102-138`
- `test/Test/Suite/TurnPipelineProtocol.hs:433-447`
- `test/Test/Suite/HttpRuntime.hs:398-463`

---

## 6. Restore Scope vs Rebuild Scope

### 6.1 Restore scope

Restore must load as durable truth:

- canonicalized `SystemState` blob
- authoritative fields/classes defined in `docs/system_state_taxonomy.md`
- `state_revision` as concurrency/control metadata

### 6.2 Rebuild scope

Rebuild may reconstruct from stronger canonical sources:

- `ssPerspectiveRegistry`
- `ssGovernanceProjection`

only when `ssTruthContractStatus` is authoritative.

Evidence:
- `src/QxFx0/Governance/Replay.hs:82-91`
- `src/QxFx0/Bridge/StatePersistence.hs:379-394`

### 6.3 Demotion scope

Restore must demote on non-authoritative contours:

- `semSemanticAnchor`
- `semLastTurnDecision`

Evidence:
- `src/QxFx0/Bridge/StatePersistence.hs:386-394`

**Doctrine (SLICE-013):** Persistence cleanup never manufactures truth-contract authority; truth-contract status is preserved verbatim unless earned by an explicit upstream authority step.

### 6.4 Runtime-hydrate-only scope

Hydrate-only runtime continuity:

- intuition MVar state
- consciousness-loop runtime commit

These do not become durable truth merely because they are recovered or hydrated.

Evidence:
- `src/QxFx0/Runtime/Wiring/Context.hs:215-223`
- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs:181-201`

---

## 7. Persistence Format Note Inside The Machine

Canonical write shape:
- raw canonicalized `SystemState`

Tolerated read shapes:
- `PersistenceEnvelope`
- raw `SystemState`

Truth relevance:
- this ambiguity is currently compatibility-only, not machine-defining truth drift
- commit semantics do not vary by stored format because write path is single-shape
- restore path still tolerates both, so full format consolidation remains deferred

Evidence:
- `src/QxFx0/Bridge/StatePersistence.hs:96-104`
- `src/QxFx0/Bridge/StatePersistence.hs:396-401`
- `docs/system_state_taxonomy.md:123-136`

---

## 8. Existing Validation Coverage

Validated with:

- `cabal test qxfx0-test-unit --disable-optimization --test-options='--match=/RuntimeInfrastructure|TurnPipelineProtocol|HttpRuntime/'`
- `cabal test qxfx0-test-semantic-slices`

Covered today:

- stale-writer CAS conflict and no silent overwrite
  - `test/Test/Suite/RuntimeInfrastructure.hs:1612-1671`
- projection insert rollback on persistence failure
  - `test/Test/Suite/RuntimeInfrastructure.hs:1595-1610`
- runtime commit failure + recovery/rollback status surfacing
  - `test/Test/Suite/TurnPipelineProtocol.hs:433-447`
- post-commit tail failure does not uncommit authoritative truth
  - `test/Test/Suite/HttpRuntime.hs:398-463`
- restore semantics stay aligned with taxonomy and `SLICE-NA-001`
  - `test/Test/Suite/RuntimeInfrastructure.hs`
  - `test/Test/Suite/SemanticSlices.hs`

Gap judgment:
- current machine claims are already backed strongly enough by existing tests
- no new code or tests are strictly required for this front unless we want tighter projection-residue assertions after double rollback failure

---

## 9. Open Follow-Ons

Bounded next fronts enabled by this artifact:

1. `bootstrap lifecycle boundaries`
2. `persistence contract consolidation`

Not part of this front:

- envelope migration
- sidecar/control-plane refactor
- broad finalize decomposition
- system-wide persistence redesign

---

## 10. Closure Readiness

This front is closable if:

- the machine is explicit
- authoritative truth boundary is explicit
- rollback scope is explicit
- projection truth vs runtime-ephemeral vs best-effort work is explicit
- persistence format ambiguity is classified inside the machine
- existing tests are sufficient for the claims

Current read:
- all of the above are now explicit in code + docs + tests
- a later front may still simplify the machine, but it is no longer ambiguous

---

## 11. Evidence References

- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/Orchestrate.hs`
- `src/QxFx0/Core/TurnPipeline/Protocol.hs`
- `src/QxFx0/Runtime/Wiring/Handlers.hs`
- `src/QxFx0/Runtime/Engine.hs`
- `src/QxFx0/Bridge/StatePersistence.hs`
- `src/QxFx0/Runtime/Session/Bootstrap.hs`
- `docs/system_state_taxonomy.md`
- `test/Test/Suite/RuntimeInfrastructure.hs`
- `test/Test/Suite/TurnPipelineProtocol.hs`
- `test/Test/Suite/HttpRuntime.hs`
