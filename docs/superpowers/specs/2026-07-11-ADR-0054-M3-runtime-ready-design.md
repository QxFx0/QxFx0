# ADR-0054 M3 Runtime-Ready Design

## Goal

Close the autonomous-learning runtime loop so that a queued `NetworkUpdateEvent` is applied to `ssSemanticNetwork` at the turn boundary without manual test helpers, the worker processes one task at a time, the queue is actually bounded, and the quota does not off-by-one block the first request.

M4 (safety, rollback, circuit breaker, observability) is out of scope for this design and will be specified separately once M3 is merged.

## Non-Goals

- Snapshot/rollback hardening (M4).
- Provenance-aware authority policy and real quarantine store (M4).
- Circuit breaker and metrics wiring (M4).
- Persisting the learning queue itself across restarts.

## Constraints

- The pure turn pipeline (`prepareTurn`, `planTurn`, `renderTurn`, `finalizeTurn`) must not be contaminated with autonomous-learning state.
- All autonomous-learning side effects live in the IO boundary around `runTurnInSession` / `runTurnBody`.
- `AutonomousHandles` must not create an import cycle with `Bootstrap.hs`.
- Tests must be deterministic and must not rely on `threadDelay` races.

## Architecture

### 1. Session wiring

Move `AutonomousHandles` from `QxFx0.Runtime.Session.Bootstrap` to `QxFx0.Runtime.Session.Types` (or a new `QxFx0.Runtime.Session.Autonomous` module) and add it as a field of `Session`:

```haskell
data Session = Session
  { sessSystemState    :: !SystemState
  , sessOutputMode     :: !RuntimeOutputMode
  , sessSessionId      :: !Text
  , sessDbPath         :: !FilePath
  , sessStateOrigin    :: !StateOrigin
  , sessStateRevision  :: !Int
  , sessReadinessMode  :: !ReadinessMode
  , sessRuntime        :: !RuntimeContext
  , sessAutonomousHandles :: !AutonomousHandles
  }
```

`AutonomousHandles` keeps the existing shape:

```haskell
data AutonomousHandles = AutonomousHandles
  { ahQueue       :: !(Maybe LearningQueue)
  , ahUpdateQueue :: !(Maybe (TQueue NetworkUpdateEvent))
  , ahEnabled     :: !Bool
  }
```

`spawnAutonomousLearningHandles` remains in `Bootstrap.hs` and is called during `bootstrapSession`. The returned handles are stored in the `Session`. They live as long as the session; there is no explicit shutdown in M3 (documented as fire-and-forget for the worker; the audit thread is not spawned in M3).

### 2. Bounded learning queue

Replace the unbounded `newtype LearningQueue = LearningQueue (TQueue LearningTask)` with a record that tracks size:

```haskell
data LearningQueue = LearningQueue
  { lqQueue :: !(TQueue LearningTask)
  , lqSize  :: !(TVar Int)
  , lqCap   :: !Int
  }
```

- `newLearningQueue :: Int -> IO LearningQueue` takes the cap explicitly and initialises size to `0`. Bootstrap calls `newLearningQueue (awcQueueCap cfg)`; tests pass caps directly.
- `enqueueLearningTask :: LearningQueue -> LearningTask -> IO Bool` atomically checks `size < cap`; if true, writes the task and increments size, returning `True`; otherwise returns `False`.
- `dequeueLearningTask :: LearningQueue -> IO LearningTask` atomically reads one task and decrements size.
- `drainLearningQueue` is removed from the production path but may be kept as a test helper that also decrements size for each drained item.

Policy chosen: **reject-when-full**. Audit-spam cannot evict high-priority per-turn tasks because the caller receives `False` and can decide whether to drop or warn.

### 3. Worker loop

The worker loop processes exactly one task per iteration:

```haskell
spawnAutonomousWorker cfg store morph taskQ updateQ = do
  qsRef <- newIORef =<< newQuotaState <$> getCurrentTime
  void . forkIO . forever $ do
    if not (awcEnabled cfg)
      then threadDelay (60 * 1000000)
      else do
        mTask <- atomically $ tryReadOne taskQ
        case mTask of
          Nothing    -> threadDelay (5000000)  -- idle
          Just task  -> processOneTask cfg store morph qsRef taskQ updateQ task
```

`tryReadOne` is the STM transaction that dequeues and decrements size together.

### 4. Quota fix

Quota is split into a read-only check and a mutation:

```haskell
quotaAllows :: AutonomousWorkerConfig -> QuotaState -> Bool
quotaAllows cfg qs = qsRequests qs < awcMaxRequestsPerHour cfg

bumpQuota :: QuotaState -> UTCTime -> QuotaState
bumpQuota qs now
  | diffUTCTime now (qsResetAt qs) >= 3600 =
      QuotaState { qsResetAt = now, qsRequests = 1 }
  | otherwise =
      qs { qsRequests = qsRequests qs + 1 }
```

`processOneTask` now:

1. Reads current quota state and resets the window if an hour elapsed.
2. Checks `quotaAllows`.
3. If blocked, re-enqueues the task using `enqueueLearningTask`; if re-enqueue returns `False`, logs a warning and drops the task.
4. If allowed, calls `atomicModifyIORef'` with `bumpQuota`, then performs the LLM request.

With `maxReq=1`, the first request bumps to `1` and is allowed; the next sees `qsRequests = 1 >= max` and is blocked.

### 5. Turn-boundary hooks (IO boundary)

`runTurnInSession` passes the handles down through a wrapper, `runTurnWithRevisionWithAutonomous`, so the existing `runTurnWithRevision` signature is unchanged for other callers. Pending updates are applied **inside** `withRuntimeSession`, after the `maxInputLength` guard and before `runTurnBody`:

```haskell
runTurnWithRevision :: RuntimeContext -> SystemState -> Text -> Text -> Int -> IO (SystemState, Text)
runTurnWithRevision ctx = runTurnWithRevisionWithAutonomous ctx Nothing

runTurnWithRevisionWithAutonomous
  :: RuntimeContext -> Maybe AutonomousHandles -> SystemState -> Text -> Text -> Int -> IO (SystemState, Text)
runTurnWithRevisionWithAutonomous ctx mbHandles ss input sessionId expectedRevision
  | T.length input > maxInputLength = ...
  | otherwise = withRuntimeSession ctx sessionId $ do
      ss0 <- applyPendingUpdatesForSession mbHandles ss
      runTurnBody ctx ss0 input sessionId expectedRevision mbHandles
```

`applyPendingUpdatesForSession` drains `ahUpdateQueue` and calls `applyPendingNetworkUpdates` only when the queue exists.

`runTurnBody` receives an optional `AutonomousHandles` argument:

```haskell
runTurnBody :: RuntimeContext -> SystemState -> Text -> Text -> Int -> Maybe AutonomousHandles -> IO (SystemState, Text)
```

Inside `runTurnBody`:

```haskell
planned@(PlannedTurn ti _ _) <- planTurn pio ss prepared
case mbHandles of
  Just handles -> forM_ (ahQueue handles) $ \q ->
    maybeEnqueueStarvingTopic q lemmaMap densityCfg (tiBestTopic ti) (ssSemanticNetwork ss)
  Nothing -> pure ()
rendered <- renderTurn pio ss planned
...
```

This keeps the pipeline pure and performs the enqueue in the IO boundary.

### 6. ContentSelector rebuild

`finalizeTurn` already rebuilds `ssSemanticNetwork`, `ssSemanticSpace`, and `ssContentSelector` from the merged meaning graph. Because `applyPendingNetworkUpdates` runs before `runTurnBody`, the updated `ssSemanticNetwork` is the one used by `finalizeTurn`. The next turn therefore sees the learned edges.

### 7. Known M3 limitation accepted

If pending updates are drained at the start of a turn but the turn later fails and is not persisted, the events are lost. This is acceptable for M3; durable rollback and snapshot recovery are M4 work.

## Testing

### Unit tests in `Test.Suite.Autonomous`

1. **Quota maxReq=1**: configure `AutonomousWorkerConfig { awcEnabled = True, awcMaxRequestsPerHour = 1, ... }`, call `runWorkerStepForTest` twice with a mock transport. First call emits an event; second call is blocked and re-enqueues.
2. **Quota block + full queue drops task**: configure `maxReq=1` and `queueCap=1`, enqueue one task, run the worker step (consumes the task and exhausts quota), then enqueue a second task and run the worker step. The second task is blocked by quota and re-enqueue returns `False`; assert the task is dropped and the queue size stays at `0`.
3. **Worker does not drop second task**: enqueue two tasks, run `runWorkerStepForTest` twice, assert both are processed and the queue is empty.
4. **Bounded queue reject-when-full**: create a queue with `cap = 1`, enqueue one task (returns `True`), enqueue a second (returns `False`), assert size stays at `1`.

### Integration tests in `Test.Suite.AutonomousLoop`

1. **Fix existing test**: remove the manual `readTQueue` before `applyPendingNetworkUpdates`; instead write a `NetworkUpdateEvent` to the queue, call `applyPendingNetworkUpdates`, and assert the edge appears.
2. **Runtime integration test**: use `withBootstrappedSession` with `QXFX0_AUTONOMOUS_LEARNING=1` and `QXFX0_LLM_TRANSPORT=mock`. Pre-seed the update queue with a synthetic event. Run `runTurnInSession` with a query whose topic is known. Assert that the returned session’s `ssSemanticNetwork` contains the learned edge without any manual queue manipulation. Use a scoped `withEnv`/`bracket`-style helper to set and restore environment variables so they do not leak to neighbouring tests.

### Deterministic worker stepping

Export a narrow helper from `QxFx0.Learning.Autonomous` for tests:

```haskell
runWorkerStepForTest
  :: AutonomousWorkerConfig
  -> Map AtomId Atom
  -> MorphologyData
  -> IORef QuotaState
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> (LearningTask -> IO (Maybe ExternalQueryResponse))
  -> IO Bool
```

The helper takes the shared `IORef QuotaState` so multiple steps observe the same quota window. It bypasses the background thread and the real LLM transport, making tests deterministic.

## Definition of Done for M3

- `runTurnInSession` applies queued `NetworkUpdateEvent`s before running the turn pipeline.
- The worker processes exactly one task per iteration and does not drop remaining tasks.
- `enqueueLearningTask` returns `Bool` and rejects when the queue is full.
- Quota `maxReq=1` allows the first request and blocks the second.
- `AutonomousHandles` are stored in `Session` and survive past bootstrap.
- All new and updated tests pass; no `threadDelay` races in tests.
- M4 safety work is explicitly deferred and not partially implemented.
