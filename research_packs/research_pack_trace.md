# QxFx0 Trace Research Pack

## Goal

Reconstruct the actual turn lifecycle from code and tests, then identify where observability and replay guarantees are still insufficient.

## Curated files

- `src/QxFx0/Core/TurnPipeline/Protocol.hs`
- `src/QxFx0/Core/TurnPipeline/Types.hs`
- `src/QxFx0/Core/TurnPipeline/Prepare.hs`
- `src/QxFx0/Core/TurnPipeline/Prepare/Build.hs`
- `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs`
- `src/QxFx0/Core/TurnPipeline/Route.hs`
- `src/QxFx0/Core/TurnPipeline/Route/Render.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs`
- `test/Test/Suite/TurnPipelineProtocol.hs`
- `scripts/verify.sh`
- `scripts/release-smoke.sh`

## Key excerpt: orchestrated lifecycle

From `src/QxFx0/Core/TurnPipeline/Protocol.hs`:

```haskell
prepareTurn pio ss input sessionId requestId = do
  let prepareEffects = buildPrepareEffectPlan ss input
  prepareResults <- Prepare.resolvePrepareEffects pio prepareEffects
  let ti' = Prepare.buildTurnInput ss requestId sessionId prepareEffects prepareResults
      ts = Prepare.buildTurnSignals prepareResults
  pure (PreparedTurn ti' ts)

planTurn pio ss (PreparedTurn ti ts) = do
  let routeEffects = Route.planRouteEffects ss ti ts
  routeResults <- Route.resolveRouteEffects pio routeEffects
  let tp = Route.buildRouteTurnPlan (pipelineShadowPolicy pio) ss ti ts routeEffects routeResults
  pure (PlannedTurn ti ts tp)

renderTurn pio ss (PlannedTurn ti ts tp) = do
  let renderEffects = Route.planRenderEffects (pipelineLLMFallbackPolicy pio) ss ti ts tp
  renderResults <- Route.resolveRenderEffects pio renderEffects
  let ta = Route.buildTurnArtifacts ss ti ts tp renderEffects renderResults
  pure (RenderedTurn ti ts tp ta)
```

This confirms a real staged pipeline with explicit prepare -> plan -> render -> finalize sequencing.

## What is already real

- staged protocol types exist
- route phase is isolated from render/finalize
- finalize has precommit/commit split
- tests exist for `TurnPipelineProtocol`

## What should be investigated

1. Which turn decisions are reconstructable from logs alone?
2. Are candidate routes and suppressed reasons visible anywhere durable?
3. Is there a deterministic replay story for same input + same state?
4. Do finalize and persist reflect the same decision artifacts that route/render saw?
5. Which parts of turn state are ephemeral and therefore hard to audit after the fact?

## Expected output from research

- actual turn state machine
- illegal transitions
- missing diagnostics inventory
- replay/non-determinism risk assessment
- exact logging additions
- exact scenario tests

## External prompt

```text
Use this pack to reconstruct the actual turn lifecycle of QxFx0 from code structure.

Do not redesign the pipeline.
Map what already exists.

You must produce:
1. actual phase-by-phase state machine,
2. call graph of major decision points,
3. list of data entering and leaving each phase,
4. observability gaps,
5. replay determinism gaps,
6. concrete new tests and logs.

Treat the pipeline as real only where there are explicit states, call edges and downstream artifacts.
```
