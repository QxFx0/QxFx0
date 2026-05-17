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

## Addendum (2026-05-17, Phase 5.5e + RecoveryConatusGate)

The trace envelope `TurnReplayTrace` gains three new strict
fields recording the post-turn Salience controller verdict:

```
trcSalienceDriver       :: !Text     -- closed enum, snake_case
trcSalienceHolisticBias :: !Double   -- in [0, 1]
trcSalienceConfidence   :: !Double   -- in [0, 1]
```

The `trcSalienceDriver` value comes from
`QxFx0.Self.Salience.renderSalienceDriver` which renders the
seven-variant `SalienceDriver` to a closed-set snake_case tag
(`resonance` / `atmosphere` / `consolidation` /
`counterfactual` / `field_confidence` / `conatus_gate` /
`default`). The tags are *trace-stable*: any future change to
a tag is a breaking change to the replay-trace JSON schema and
must be coordinated with the release gate.

The `trcRecoveryCause` field gains a new admissible value
`RecoveryConatusGate` (JSON tag `"conatus_gate"`) emitted when
the M2d Conatus gate fires. This is distinct from
`RecoveryRuntimeDegraded` (which retains its environmental
meaning); the split makes a structural-Conatus event
distinguishable from an environmental runtime-degraded event
in postmortem replay.

The Generic-derived `ToJSON` instance on `TurnReplayTrace`
picks up the new fields automatically; downstream readers
of the `replay_trace_json` SQL column see three new
top-level keys (`trcSalienceDriver`,
`trcSalienceHolisticBias`, `trcSalienceConfidence`) and one
new admissible value for the existing `trcRecoveryCause`
key. No schema migration is required for the SQL column
itself (the JSON blob is opaque to SQL).

See ADR-0010 addendum 2026-05-17 for the operational
context and ADR-0009 addendum 2026-05-17 for the Field
sourcing that drives the controller's verdict.
