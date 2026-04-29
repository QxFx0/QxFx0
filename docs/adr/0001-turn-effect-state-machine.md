# ADR 0001: Turn Effect State Machine

## Status

Accepted

## Context

`QxFx0` already exposes a staged turn pipeline:

- `PreparedTurn`
- `PlannedTurn`
- `RenderedTurn`

The public surface is cleaner than the old raw phase protocol, but the first stage still performs effectful work directly inside `Prepare`:

- embedding lookup
- nix guard lookup
- API health probing
- shell-owned consciousness mutation
- shell-owned intuition mutation

This keeps the core dependent on `PipelineIO` and makes turn determinism harder to reason about.

## Decision

The pipeline moves toward an explicit state machine with synchronous shell-resolved effects.

The first implemented slice is `Prepare`:

1. A pure planner builds `PrepareEffectPlan`.
2. The shell interprets explicit `PrepareEffectRequest` values.
3. Pure assemblers build `TurnInput` and `TurnSignals` from resolved results.

The initial protocol stays synchronous. The shell resolves requests immediately and feeds results back into the core within the same turn.

We intentionally do **not** add persisted suspended turns in this wave. Deferred effects such as `AwaitingLLM` or `AwaitingShadow` remain a later design step.

## Consequences

### Positive

- `Prepare` becomes mostly pure and testable.
- effect boundaries become explicit instead of being hidden inside `PipelineIO` callbacks
- future property-based tests can target planning and assembly logic without mocking IO
- the next refactor wave can apply the same pattern to `Route` and `Finalize`

### Negative

- the system temporarily contains both `PipelineIO` and effect-plan abstractions
- the shell interpreter is still synchronous, so long-running effects still block the turn
- the protocol is only complete for `Prepare`; the rest of the pipeline is not yet migrated

## Follow-up

1. Migrate `Route` to `EffectRequest/EffectResult`.
2. Migrate `Finalize` to `EffectRequest/EffectResult`.
3. Add property tests for deterministic stage planning and illegal transition prevention.
4. Design deferred, persisted suspended turns as a separate ADR.
