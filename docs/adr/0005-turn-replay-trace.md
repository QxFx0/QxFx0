# ADR 0005: Replay-Grade Turn Trace Envelope

## Status

Accepted (2026-04-23).

## Context

`turn_quality` already persisted scalar decision fields, but postmortem reconstruction still required combining logs and implicit pipeline knowledge.
This made disputed turns harder to reproduce deterministically.

## Decision

1. Introduce typed replay envelope `TurnReplayTrace` in `QxFx0.Types.TurnProjection`.
2. Build envelope in finalize (`buildTurnProjection`) from canonical pipeline artifacts:
   - request/session identifiers
   - requested, pre-shadow, resolved, and final families
   - narrative/intuition hints
   - shadow snapshot and divergence taxonomy
   - disposition and legitimacy reason
   - parser confidence and embedding quality.
3. Persist envelope in `turn_quality.replay_trace_json`.
4. Enforce minimal replay presence in release gate: smoke turn must persist replay JSON with core trace keys.

## Consequences

- Turn reconstruction no longer depends on best-effort log parsing.
- Replay payload remains versionable as one typed envelope instead of unbounded SQL column growth.
- Release smoke now validates trace persistence as a constitutional gate.

