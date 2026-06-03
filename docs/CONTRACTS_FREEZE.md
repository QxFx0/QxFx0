# Contract Freeze-0

Date: 2026-05-26
Status: Active
Scope: Canonical Haskell-first runtime contour before typed persistence/provenance refactor

## Purpose

Freeze-0 captures the minimum contract surface that must stay stable while the
system completes the Haskell-first consolidation and prepares for the next
persistence/provenance redesign phase.

This is not a blanket freeze over the entire repository. It is a targeted
freeze over the authority path that currently decides runtime behavior,
readiness, persistence, replay semantics, and HTTP perimeter behavior.

If a behavior outside this surface changes, it does not automatically require a
Freeze-0 bump. If a behavior inside this surface changes, it must go through the
contract bump policy.

## Freeze-0 Contracts

### 1. Turn Protocol

Authority files:
- `src/QxFx0/Core/TurnPipeline/Protocol.hs`
- `app/CLI/Protocol.hs`
- `app/CLI/Turn.hs`
- `app/CLI/Worker.hs`

Frozen properties:
- worker turn command semantics
- turn JSON response envelope shape
- local recovery trace fields exposed through canonical runtime paths
- session/bootstrap/turn boundary expectations used by tests and operator tools

Evidence gates:
- `cabal test qxfx0-test-fast`
- `cabal test qxfx0-test-slow`
- `cabal test qxfx0-test`

### 2. Persisted State + Replay / Projection

Authority files:
- `src/QxFx0/Bridge/StatePersistence.hs`
- `src/QxFx0/Runtime/Session/Bootstrap.hs`
- `src/QxFx0/Bridge/SQLite/Bootstrap.hs`
- replay/projection canonical envelope in `turn_quality.replay_trace_json`
- canonical field reference in `docs/interop/README.md`

Frozen properties:
- fail-closed handling for corrupt persisted-state
- invalid UTF-8 classified as corrupt decode, not silent fallback
- schema/bootstrap diagnostics remain structured and specific
- replay/persist contract is deterministic under normalized output
- canonical governance history is authority; derived governance views are not
- compatibility-only persisted fields may be retained temporarily for wire-format
  stability, but must not be treated as authority

Evidence gates:
- `cabal test qxfx0-test-slow`
- `cabal test qxfx0-test`
- targeted corrupt-state / invalid UTF-8 / rebuild-failure checks

### 3. HTTP Contract (Canonical Haskell Path)

Authority files:
- `app/CLI/Http.hs`
- `app/CLI/Http/Runtime.hs`
- `test/Test/Suite/HttpRuntime.hs`

Frozen properties:
- `qxfx0-main --serve-http` is the canonical HTTP runtime path
- `/sidecar-health`, `/health`, `/runtime-ready`, `/turn` semantics
- loopback / non-loopback bind policy
- API key and session-token ownership behavior
- post-send unknown outcome and explicit worker error JSON mapping
- input validation must precede session ownership claim

Evidence gates:
- `cabal test qxfx0-test-slow`
- `cabal test qxfx0-test`
- `bash scripts/check_architecture.sh`
- `bash scripts/release-smoke.sh`

### 4. Generated Artifact Authority Contract (Freeze-0 subset)

Freeze-0 does not freeze the entire artifact pipeline. It freezes only the
artifact surfaces that currently influence canonical runtime or release gates.

Authority surfaces:
- schema contract and SQL sync inputs
- replay trace field contract
- runtime-critical generated artifacts that participate in release/gate
  authority

Deferred to later freeze stage:
- full lexicon ingest/source supplier pipeline
- full morphology ingest pipeline
- non-authority Python suppliers

## What Freeze-0 Does Not Freeze

The following are explicitly outside Freeze-0:
- exploratory or research-only scripts
- non-authority Python ingest/supplier steps
- extended scientific contour behavior that does not participate in canonical
  runtime/release decisions
- documentation wording that does not change canonical behavior

## Required Normalization Rules

Any golden or baseline evidence tied to Freeze-0 must normalize:
- timestamps
- request IDs
- session IDs when not semantically relevant
- absolute paths and tmp paths
- canonical JSON ordering
- stable map/set/list emission order where required
- environment-specific port or PID values

## Freeze-0 Gate Set

Required to claim Freeze-0 intact:
- `bash scripts/check_architecture.sh`
- `cabal test qxfx0-test-fast`
- `cabal test qxfx0-test-slow`
- `cabal test qxfx0-test`

Additional milestone evidence:
- `bash scripts/release-smoke.sh`
- no Python in live runtime path
- no runtime/CLI dependency on `http_runtime.py`

## Freeze-0 Exit Condition

Freeze-0 remains active until all of the following are true:
- Haskell-first runtime contour is stable
- Python-free runtime path gate is closed
- baseline trace/persist harness is recorded
- typed persistence/provenance refactor is ready to begin

After that, Freeze-1 may be introduced for a wider artifact authority contour.
