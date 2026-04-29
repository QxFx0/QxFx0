# ADR 0004: Canonical Shadow Snapshot Parity

## Status

Accepted (2026-04-23).

## Context

`Datalog` shadow verification already existed, but parity inputs were assembled ad-hoc at runtime.
This made replay and postmortem analysis harder: it was possible to inspect divergence flags without a stable typed identity of the compared input.

## Decision

1. Introduce canonical snapshot contract in `QxFx0.Types.ShadowDivergence`:
   - `ShadowSnapshot`
   - `ShadowSnapshotId`
   - `ShadowDivergenceKind`
2. Compute `ShadowSnapshotId` from frozen snapshot content (`mkShadowSnapshotId`), and propagate it through:
   - `Bridge.Datalog.ShadowResult`
   - `Core.PipelineIO.ShadowResult`
   - `TurnPipeline` routing and finalize projection.
3. Persist snapshot identity and divergence taxonomy in SQL projection/logs:
   - `turn_quality.shadow_snapshot_id`
   - `turn_quality.shadow_divergence_kind`
   - `shadow_divergence_log.shadow_snapshot_id`
   - `shadow_divergence_log.shadow_divergence_kind`

## Consequences

- Every shadow verdict now has a deterministic replay key.
- Divergence is no longer only boolean; reason taxonomy is retained downstream.
- Operational audits can correlate runtime turns with exact shadow snapshot identity without parsing free-form diagnostics.

