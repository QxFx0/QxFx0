# State / Persistence Seam Contract

This document is the canonical contract for the state/persistence seam.

## Source Of Truth

- canonical persisted session state lives in `dialogue_state`
- the key `__system_state__` is the authoritative serialized `SystemState`
- per-turn replay/audit data lives in `turn_quality.replay_trace_json`
- governance truth lives in canonical governance history embedded in persisted
  `SystemState`, not in derived projections

## Persistence Domains

- canonical truth domains:
  `PdCoreConversation`, `PdAdaptiveLearning`, `PdDialogueDevelopment`,
  `PdGovernanceCanonical`
- rebuildable projection domains:
  `PdGovernanceDerived`
- runtime-transient domains:
  `PdSessionTransient`
- the persistence write path materializes a canonical snapshot that clears
  rebuildable governance views and runtime-transient fields before writing the
  state blob
- the runtime continuation path keeps live projections/transients in worker
  memory; reload/bootstrap rehydrates rebuildable governance views from
  canonical governance history

## critical durable state

- `dialogue_state.__system_state__`
- `runtime_sessions`
- `turn_quality` rows required for replay envelope continuity
- `shadow_divergence_log` rows required by divergence/replay contracts

## Cache / Projection / Regenerable Contours

- `ssPerspectiveRegistry` is a rebuildable governance projection
- `ssGovernanceProjection` is a rebuildable governance projection
- runtime session internals held in worker memory are runtime cache, not durable
  truth
- HTTP session-token registry is transport/session-perimeter state, not semantic
  truth

## Atomicity Boundary

- `saveStateWithProjection` persists `dialogue_state.__system_state__` and any
  supplied turn projection inside a single immediate SQLite transaction
- `rollbackTurnProjections` removes projections above a stable turn boundary
  without rewriting authoritative state blobs

## Compatibility Rules

- persisted state must remain backward-compatible across schema-preserving
  hardening updates
- legacy-compatible decoders are required when persisted scalar representation
  changes do not justify a schema migration
- rebuildable projections may be recomputed on load when canonical truth is
  authoritative and internally consistent

## Failure Semantics

- corrupt or non-authoritative persisted state must fail closed in strict mode
- degraded mode may recover from corrupt persisted state only by surfacing an
  explicit recovered-corrupt origin/fault marker
