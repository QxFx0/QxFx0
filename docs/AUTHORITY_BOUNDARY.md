# Authority Boundary

Date: 2026-05-26
Status: Active
Scope: Canonical Haskell-first contour authority map

## Purpose

This document separates what is authoritative from what is merely a supplier,
derived emitter, or legacy observer. The distinction is mandatory during the
Python retirement and persistence/provenance redesign phases.

## Boundary Classes

### 1. Authority

A component is authority if it can decide or validate canonical runtime,
release, governance, replay, or persistence behavior.

### 2. Supplier

A component is supplier if it can provide raw material, source data, or helper
transforms, but is not allowed to decide canonical validity on its own.

### 3. Derived

A component is derived if it is generated from authoritative sources and must
stay in sync with them.

### 4. Legacy Observer

A component is legacy observer if it exists for compatibility, comparison, or
historical evidence, but is not part of the canonical path.

## Current Freeze-0 Authority Map

### Canonical runtime authority

Authority:
- `qxfx0-main --serve-http`
- `app/CLI/Http.hs`
- `app/CLI/Http/Runtime.hs`
- `src/QxFx0/Core/TurnPipeline/Protocol.hs`
- `src/QxFx0/Bridge/StatePersistence.hs`
- `src/QxFx0/Runtime/Session/Bootstrap.hs`
- canonical replay trace contract documented in `docs/interop/README.md`

Supplier:
- none required in the live runtime path

Legacy observer:
- `scripts/http_runtime.py` (retired from canonical runtime path)

### Governance / release authority

Authority:
- `bash scripts/check_architecture.sh`
- `cabal test qxfx0-test-fast`
- `cabal test qxfx0-test-slow`
- `cabal test qxfx0-test`
- `bash scripts/release-smoke.sh`
- `bash scripts/verify.sh`

Mixed authority still present:
- `python3 scripts/check_schema_consistency.py`
- `python3 scripts/check_schema_contract.py`
- `python3 scripts/sync_embedded_sql.py --check`

Interpretation:
- Haskell owns runtime authority.
- Python still participates in release-critical governance authority and must be
  migrated or formally bounded in later phases.

### Artifact authority

Authority now:
- schema contract sources in `spec/sql/**`
- Haskell runtime interpretation of replay/persistence/state
- Haskell HTTP perimeter behavior

Supplier now:
- Python scripts that ingest or transform raw lexicon/morphology source data
- Python schema-sync/check helpers until Phase 3/4 migration completes

Derived now:
- generated Haskell/SQL/GF artifacts emitted from canonical sources

### Persisted `SystemState` authority map

Authority-retained in persisted canonical state:
- `truthContractStatus` as the authoritative/non-authoritative rebuild gate
- `governanceHistory` as the canonical source for governance restoration
- semantic carry-forward field `semanticAnchor` until a dedicated semantic
  rebuild source exists
- `lastTurnDecision` is still persisted, but whole-field authority is NOT PROVEN
  and is under active false-authority review in `SLICE-TD-001`

Current semantic retention rule:
- `semanticAnchor` remains persisted for compatibility/observability, but is
  demoted on non-authoritative restore paths before it can regain restart
  authority
- `lastTurnDecision` remains persisted, but is also demoted on
  non-authoritative restore paths and must not be read as restart-safe
  whole-field authority
- no semantic post-load rebuild is defined yet; authoritative restore may
  preserve these carries, while non-authoritative restore now explicitly
  demotes them rather than treating retention as proof of authority
- round-trip coverage exists for authoritative and non-authoritative restore
  contours across both `loadState` and `bootstrapSession`

Derived and rebuilt after authoritative load:
- `perspectiveRegistry`
- `governanceProjection`

Compatibility-only and cleared before persistence:
- `lastGuardReport`

Current rebuild rule:
- authoritative persisted states (`CanonicalSurfacePreserved`,
  `AssembledSurfacePreserved`) must rebuild derived governance views from
  canonical history on load
- non-authoritative persisted states restore as-is and do not trigger rebuild

Wire-shape rule:
- persisted `__system_state__` stays the current raw top-level `SystemState`
  JSON shape until an explicit contract bump

### Explicitly non-authoritative Python (current state)

Non-authoritative in live runtime path:
- `scripts/http_runtime.py`

Potentially still authoritative in release/governance path:
- schema consistency/contract helpers
- SQL sync helper
- some artifact verification helpers

## Freeze-0 Rules

1. No new Python entrypoint may be introduced into canonical runtime path.
2. No new authority may be assigned to Python in runtime/governance path without
   explicit phase decision.
3. New env parsing must move toward typed config-layer, not expand ad hoc.
4. New cross-layer shortcuts around canonical Haskell runtime boundaries are
   forbidden.
5. Any component not explicitly classified here is NOT PROVEN to be canonical.

## Phase Intent

### Phase 1
- strengthen Haskell core
- reduce config/runtime debt
- keep authority boundary explicit

### Phase 2
- retire Python from runtime perimeter completely
- keep only legacy observer traces until deletion

### Phase 3
- move release-critical Python governance checks into Haskell commands or
  Haskell-owned authority contour

### Phase 4
- move artifact authority path to Haskell typed IR / validation / emitters
- Python may remain supplier-only where justified

## Required Companion Document

For every Python component, see `docs/PYTHON_STATUS_LEDGER.md`.
That ledger tracks whether the component is canonical, what replaces it, and
when it can be removed.
