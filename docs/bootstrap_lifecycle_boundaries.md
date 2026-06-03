# Bootstrap Lifecycle Boundaries
Status: Verified
Front: `bootstrap lifecycle boundaries`

---

## 1. Purpose

This artifact makes the current bootstrap lifecycle explicit enough that:

- authoritative restore
- rebuild / replay
- substrate backfill
- validation
- runtime hydration
- session materialization

are no longer read as one implicit "initialize" blur.

This is a bounded H2 boundary-clarification front. It is not a broad bootstrap refactor.

---

## 2. Current Lifecycle Trace

The current execution order in `bootstrapSession` is:

1. Resolve runtime prerequisites
   - `resolveDbPath`
   - `resolveRuntimeMode`
   - `createDirectoryIfMissing`
   - `assessResourceReadiness`
   - `computeReadinessMode`
   - `evaluateBootstrapReadiness`
   - evidence: `src/QxFx0/Runtime/Session/Bootstrap.hs:74-87`

2. Initialize schema and session row substrate
   - `ensureSchemaMigrations`
   - `INSERT OR IGNORE INTO runtime_sessions`
   - evidence: `Bootstrap.hs:88-103`

3. Load resource/runtime substrate
   - `loadMorphologyData`
   - `initRuntimeContext`
   - `checkHealth`
   - `evaluateStrictHealth`
   - evidence: `Bootstrap.hs:104-116`

4. Load DB-backed substrate backfills
   - `queryIdentityClaimsByFocus`
   - `loadClusters`
   - `loadScenes`
   - evidence: `Bootstrap.hs:118-123`

5. Construct fresh baseline
   - assemble `freshState` from empty state + first scene + morphology + identity claims + clusters + live session id
   - evidence: `Bootstrap.hs:124-133`

6. Read persistence control metadata and attempt state load
   - `loadStateRevision`
   - `loadState`
   - evidence: `Bootstrap.hs:134-149`

7. Perform persistence-layer restore admission
   - inside `loadState`:
     - decode blob
     - rebuild/demote via `rebuildDerivedViewsAfterLoad`
   - authoritative contours: `rebuildGovernedSystemState`
   - non-authoritative contours: `demoteNonAuthoritativeRestartCarry`
   - evidence: `src/QxFx0/Bridge/StatePersistence.hs:198-221,379-394`

8. Perform bootstrap overlay/backfill on restored state
   - overwrite `activeScene`
   - merge morphology
   - backfill `identityClaims` if empty
   - backfill `clusters` if empty
   - rewrite live `sessionId`
   - evidence: `Bootstrap.hs:149-163`

9. Re-run governance rebuild after overlay
   - if authoritative contour, call `rebuildGovernedSystemState` again on `restored0`
   - evidence: `Bootstrap.hs:164-168`

10. Validate restored/overlaid state
    - `checkInitialBlanket (computeSelfBlanket restored)`
    - evidence: `Bootstrap.hs:169-176`

11. Hydrate runtime-only state
    - `hydrateRuntimeTurnState runtime restored`
    - seeds runtime turn MVar:
      - `clDialogueTurn = ssTurnCount ss`
      - `rtsIntuition = ssIntuitionState` or default
    - evidence: `Bootstrap.hs:177`, `src/QxFx0/Runtime/Wiring/Context.hs:215-223`

12. Materialize session shell
    - build `Session { ... }`
    - evidence: `Bootstrap.hs:178-187`

---

## 3. Target Phases

The current code should be read against these explicit phases:

1. prerequisites
2. state load
3. authoritative restore admission
4. rebuild / replay / substrate backfill
5. validation
6. runtime hydration
7. session materialization

The implementation does not yet isolate these perfectly. This document maps the current interleaving honestly.

---

## 4. Step-to-Phase Authority Map

| step | code location | primary role | reads canonical persisted truth? | mutates loaded state? | rebuilds derived state? | validates? | hydrates runtime-only? | materializes shell only? | notes |
|---|---|---|---|---|---|---|---|---|---|
| readiness gating | `Bootstrap.hs:74-87` | prerequisite only | no | no | no | gate only | no | no | operational admission, not semantic authority |
| schema/session row init | `Bootstrap.hs:88-103` | prerequisite only | no | no | no | no | no | no | substrate/DB precondition |
| resource/runtime substrate load | `Bootstrap.hs:104-116` | prerequisite only | no | no | no | health gate | no | no | morphology + runtime context + health |
| DB substrate backfills | `Bootstrap.hs:118-123` | substrate backfill | no | not yet | no | no | no | no | scenes/claims/clusters sources |
| fresh baseline build | `Bootstrap.hs:124-133` | substrate backfill | no | constructs baseline | no | no | no | no | fallback shell for fresh/missing state |
| revision read | `Bootstrap.hs:134` | prerequisite only | metadata only | no | no | no | no | no | concurrency/control state only |
| persisted blob load | `StatePersistence.hs:198-209` | authoritative load | yes | yes via returned value | no | decode only | no | no | pure load admission entrypoint |
| restore admission rebuild/demotion | `StatePersistence.hs:210-221,379-394` | authoritative restore admission | yes | yes | yes / demote | indirect via rebuild outcome | no | no | separates authoritative rebuild from non-authoritative demotion |
| bootstrap overlay/backfill | `Bootstrap.hs:149-163` | substrate backfill | yes, on already restored state | yes | no | no | no | no | mixes restore result with substrate/runtime-local adjustments |
| second governance rebuild | `Bootstrap.hs:164-168` | rebuild / replay | yes | yes | yes | no | no | no | rebuild after overlay |
| blanket validation | `Bootstrap.hs:169-176` | validation | yes, via current state | no | no | yes | no | no | structural coherence gate |
| runtime turn-state hydrate | `Bootstrap.hs:177`, `Context.hs:215-223` | runtime-hydrate-only | yes, via restored state | no | no | no | yes | no | hydration does not confer authority |
| `Session` construction | `Bootstrap.hs:178-187` | session materialization | yes, via restored state | no | no | no | no | yes | wraps state + runtime handles + metadata |

---

## 5. Restore / Rebuild / Hydrate / Materialize Map

### 5.1 Restored as authoritative truth

Loaded as restart truth, subject to taxonomy rules:

- canonicalized persisted `SystemState` blob
- authoritative fields from `docs/system_state_taxonomy.md`
- `ssTruthContractStatus` as primary restart gate
- `ssGovernanceHistory` as canonical governance history

Evidence:
- `src/QxFx0/Bridge/StatePersistence.hs:198-221`
- `docs/system_state_taxonomy.md:183-230`

### 5.2 Restored then demoted

Restored but explicitly denied restart authority on non-authoritative contours:

- `semSemanticAnchor`
- `semLastTurnDecision`

Evidence:
- `src/QxFx0/Bridge/StatePersistence.hs:386-394`
- `docs/system_state_taxonomy.md:243-245`

### 5.3 Rebuilt from canonical source

Rebuilt from stronger canonical history rather than raw blob continuity:

- `ssPerspectiveRegistry`
- `ssGovernanceProjection`

Evidence:
- `src/QxFx0/Governance/Replay.hs:82-91`
- `docs/system_state_taxonomy.md:227-229`

### 5.4 Substrate-backfilled / merged

Not pure restore truth; bootstrapped from resource or DB substrate:

- `activeScene` overridden from loaded/restored scene set
- `ssMorphology` merged with resource morphology
- `idsIdentityClaims` backfilled if empty
- `semClusters` backfilled if empty
- `ssSessionId` rewritten to live session id

Evidence:
- `Bootstrap.hs:149-163,189-198`
- `docs/system_state_taxonomy.md:188,190,197,204,206`

### 5.5 Runtime-hydrate-only

Hydrated into runtime convenience/continuity, not durable truth:

- `rtsConsciousLoop` seeded from `ssTurnCount`
- `rtsIntuition` seeded from `ssIntuitionState` or default

Evidence:
- `src/QxFx0/Runtime/Wiring/Context.hs:215-223`
- `docs/system_state_taxonomy.md:199,250-251`

### 5.6 Session/runtime shell only

Materialized for the local session shell, not semantic reconstruction:

- `sessOutputMode`
- `sessDbPath`
- `sessStateOrigin`
- `sessStateRevision`
- `sessReadinessMode`
- `sessRuntime`

Evidence:
- `Bootstrap.hs:178-187`
- `src/QxFx0/Runtime/Session/Types.hs:48-57`

---

## 6. Mixed-Phase Ambiguity List

### 6.1 `loadState` mixes authoritative load with restore admission rebuild/demotion

Location:
- `src/QxFx0/Bridge/StatePersistence.hs:198-221,379-394`

Why mixed:
- raw persisted load and restart-authority admission are not separate functions
- decode/load and rebuild/demotion occur in one persistence-layer contour

Why risky:
- later lifecycle work could accidentally treat `loadState` as “just load”, overlooking authority gating already happening there

Safe for now:
- yes, because the authority rule is explicit and already tested

Future owner:
- `bootstrap lifecycle boundaries` extraction follow-up or later persistence contract consolidation

### 6.2 Bootstrap overlay block mixes restored truth with substrate backfill

Location:
- `Bootstrap.hs:149-163`

Why mixed:
- authoritative restored state is immediately combined with:
  - `activeScene` overwrite
  - morphology merge
  - identity-claim backfill
  - cluster backfill
  - live session-id rewrite

Why risky:
- readers can mistake substrate-enriched state for pure restored truth

Safe for now:
- mostly, because taxonomy explicitly names these as bootstrap/backfill overlays

Future owner:
- bounded bootstrap extraction / lifecycle helper split

### 6.3 Bootstrap performs a second authoritative governance rebuild after overlay

Location:
- `Bootstrap.hs:164-168`

Why mixed:
- rebuild has already potentially happened in `loadState`
- bootstrap re-runs authoritative rebuild after overlays

Why risky:
- ownership of rebuild is split across persistence and bootstrap layers

Safe for now:
- yes, but it is phase-blurring

Future owner:
- later helper split between restore admission and post-overlay canonical rebuild

### 6.4 Validation happens after overlay and rebuild, not after pure restore only

Location:
- `Bootstrap.hs:169-176`

Why mixed:
- the validation gate validates the final overlaid/rebuilt state, not just raw restored truth

Why risky:
- failure semantics can be read as restore failure when it is actually restore+overlay+rebuild failure

Safe for now:
- yes, because the gate is structural, not authority-creating

Future owner:
- lifecycle extraction if later fronts need finer-grained failure semantics

### 6.5 Runtime hydration sits adjacent to session materialization

Location:
- `Bootstrap.hs:177-187`

Why mixed:
- runtime-only carry hydration and session shell construction happen back-to-back in one tail block

Why risky:
- future readers can conflate hydrated runtime continuity with session truth materialization

Safe for now:
- yes, because hydration scope is already explicit in the taxonomy

Future owner:
- future tiny helper extraction if runtime-shell clarity becomes necessary

### 6.6 Corrupt persisted state vs `RecoveredCorruptOrigin`

Location:
- `Bootstrap.hs:143-148`
- `src/QxFx0/Runtime/Session/Types.hs:29-33`

Why mixed:
- the enum exposes `RecoveredCorruptOrigin`, but current bootstrap fails closed on corrupt state instead of materializing that contour

Why risky:
- lifecycle readers could infer a degraded recovery path that does not currently exist

Safe for now:
- yes, after the new inline note in `Session.Types`

Future owner:
- bounded degraded-recovery contour if such a path is ever introduced

---

## 7. Phase-Boundary Rules

1. Prerequisites do not confer semantic authority.
   - readiness, schema bootstrap, and health gates admit the runtime to bootstrap but do not themselves create restart truth.

2. Authoritative restore is distinct from substrate backfill.
   - resource scenes, morphology, claims, and clusters must not be described as pure persisted truth when they enter via overlay/backfill.

3. Rebuild from canonical history is not raw restore.
   - governance view reconstruction is derived from `ssGovernanceHistory`, not replay of the blob surface.

4. Validation does not create authority.
   - it only confirms whether the current restored/rebuilt/overlaid state is structurally admissible.

5. Hydration does not confer authority.
   - runtime turn-state hydration seeds convenience/continuity carries only.

6. Session materialization is not semantic reconstruction.
   - building `Session` packages state + runtime handles + metadata; it does not create new semantic truth.

7. Compatibility/default decode must not be described as authoritative restore.
   - tolerated read shapes and default-heavy decode paths remain lifecycle-visible but not self-legitimating.

---

## 8. Future Extraction Candidates

These are future cleanup candidates, not work for this front.

| candidate | mixed phase isolated | why helpful | why not now |
|---|---|---|---|
| `loadRestoredState` / `admitRestoredState` split | authoritative load vs restore admission rebuild/demotion | makes it impossible to overlook authority gating inside load path | would start persistence/bootstrap restructuring beyond this bounded mapping front |
| `applyBootstrapOverlays` helper | restored truth vs substrate backfill | isolates `activeScene`/morphology/claims/clusters/sessionId overlay semantics | not necessary to classify lifecycle honestly |
| `rebuildBootstrapViews` helper | overlay vs authoritative rebuild | gives single named owner to second governance rebuild | current code is still readable once the phase is documented |
| `validateBootstrappedState` helper | rebuilt/overlaid state vs validation | clarifies failure semantics | no behavior ambiguity remains after documentation |
| `hydrateBootstrapRuntime` helper | validation vs runtime hydration | isolates runtime-only carry seeding | not required yet because hydration scope is narrow and explicit |
| `materializeSessionShell` helper | runtime hydration vs session shell creation | clarifies shell-only metadata creation | documentation is currently sufficient |

---

## 9. Existing Validation Alignment

Lifecycle claims align with existing tests:

- authoritative semantic carry survives bootstrap restore
  - `testBootstrapSessionPreservesAuthorityRetainedSemanticFields`
- non-authoritative semantic carry is restored but denied restart authority
  - `testBootstrapSessionPreservesAuthorityRetainedSemanticFieldsForNonAuthoritativeState`
  - `testBootstrapSessionStrictRestoresNonAuthoritativePersistedState`
  - `testBootstrapSessionDegradedRestoresNonAuthoritativePersistedState`
- governance-derived views rebuild from canonical history after bootstrap restore
  - `testBootstrapSessionRestoresCanonicalGovernanceViews`
  - `testBootstrapSessionRestoresAssembledGovernanceViews`
- corrupt persisted state fails closed
  - `testBootstrapSessionCorruptStateFailsClosed`
- substrate/bootstrap seeding is visible and tested
  - `testRuntimeBootstrapUsesCanonicalSpecSeeds`
- strict readiness/prerequisite gates are already exercised
  - `testProbeRuntimeReadinessStrictRequiresWitness`
  - `testProbeRuntimeReadinessStrictAcceptsWitnessedLocalBackend`
  - related readiness tests

No new tests were required for this front because the phase claims are code-read backed and already aligned with existing runtime/bootstrap coverage.

---

## 10. Closure Statement

This front is closable because:

- current bootstrap phases are explicit
- authoritative restore is separated conceptually from substrate backfill, rebuild, validation, runtime hydration, and session materialization
- mixed phases are named and bounded
- runtime hydration is explicitly non-authoritative
- later H2 work no longer needs to infer lifecycle boundaries from raw code shape alone
- no broad bootstrap decomposition was smuggled into the front

Bounded next front enabled by this artifact:
- `sidecar control-plane decomposition map`

---

## 11. Evidence References

Primary code:
- `src/QxFx0/Runtime/Session/Bootstrap.hs`
- `src/QxFx0/Bridge/StatePersistence.hs`
- `src/QxFx0/Runtime/Wiring/Context.hs`
- `src/QxFx0/Governance/Replay.hs`
- `src/QxFx0/Bridge/SQLite/Bootstrap.hs`
- `src/QxFx0/Runtime/Session/Types.hs`

Prerequisite artifacts:
- `docs/system_state_taxonomy.md`
- `docs/commit_restore_state_machine.md`
- `docs/results/SLICE-NA-001.md`

Existing tests used as alignment evidence:
- `test/Test/Suite/RuntimeInfrastructure.hs`
- `test/Test/Suite/SemanticSlices.hs`
