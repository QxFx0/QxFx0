# ADR-0054 M3 Runtime-Ready Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the autonomous-learning runtime loop so queued `NetworkUpdateEvent`s are applied at the turn boundary, the worker processes one task at a time, the queue is actually bounded, and quota does not off-by-one block the first request.

**Architecture:** Move `AutonomousHandles` into `Session`, replace the unbounded learning queue with a size-tracked bounded queue, switch the worker to single-task `readTQueue`, fix quota check/bump ordering, and wire enqueue/apply hooks into the `runTurnInSession` IO boundary via a wrapper around `runTurnWithRevision`.

**Tech Stack:** Haskell, STM (TQueue/TVar/TBQueue), HUnit, existing QxFx0 runtime (`Runtime.Session`, `Runtime.Engine`, `Learning.Autonomous`, `Semantic.Network`).

---

## File Structure

| File | Responsibility |
|------|----------------|
| `src/QxFx0/Learning/Autonomous.hs` | `LearningQueue` (bounded), worker loop, quota helpers, test helper `runWorkerStepForTest`, exports. |
| `src/QxFx0/Runtime/Session/Types.hs` | `AutonomousHandles` definition + new `sessAutonomousHandles` field in `Session`. |
| `src/QxFx0/Runtime/Session/Bootstrap.hs` | Create handles, pass them into the `Session` constructor. |
| `src/QxFx0/Runtime/Engine.hs` | `runTurnWithRevisionWithAutonomous`, `applyPendingUpdatesForSession`, enqueue hook in `runTurnBody`. |
| `test/Test/Suite/Autonomous.hs` | Quota, bounded-queue, worker-step tests. |
| `test/Test/Suite/AutonomousLoop.hs` | Fixed integration test + runtime integration test. |

---

## Task 1: Move `AutonomousHandles` to `Runtime.Session.Types`

**Files:**
- Create: `src/QxFx0/Runtime/Session/Autonomous.hs` (tiny re-export wrapper to avoid cycles if needed)
- Modify: `src/QxFx0/Runtime/Session/Types.hs`
- Modify: `src/QxFx0/Runtime/Session/Bootstrap.hs`

- [ ] **Step 1.1: Create `src/QxFx0/Runtime/Session/Autonomous.hs`**

```haskell
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  ) where

import Control.Concurrent.STM (TQueue)
import QxFx0.Learning.Autonomous (LearningQueue, NetworkUpdateEvent)

data AutonomousHandles = AutonomousHandles
  { ahQueue       :: !(Maybe LearningQueue)
  , ahUpdateQueue :: !(Maybe (TQueue NetworkUpdateEvent))
  , ahEnabled     :: !Bool
  }
  deriving stock (Eq, Show)
```

- [ ] **Step 1.2: Add `sessAutonomousHandles` to `Session` in `src/QxFx0/Runtime/Session/Types.hs`**

```haskell
import QxFx0.Runtime.Session.Autonomous (AutonomousHandles)

data Session = Session
  { sessSystemState       :: !SystemState
  , sessOutputMode        :: !RuntimeOutputMode
  , sessSessionId         :: !Text
  , sessDbPath            :: !FilePath
  , sessStateOrigin       :: !StateOrigin
  , sessStateRevision     :: !Int
  , sessReadinessMode     :: !ReadinessMode
  , sessRuntime           :: !RuntimeContext
  , sessAutonomousHandles :: !AutonomousHandles
  }
```

- [ ] **Step 1.3: Remove `AutonomousHandles` from `Bootstrap.hs` and import it**

Delete the local `data AutonomousHandles = ...` definition and add:

```haskell
import QxFx0.Runtime.Session.Autonomous (AutonomousHandles)
```

- [ ] **Step 1.4: Update the `Session` constructor in `bootstrapSession`**

After `pure Session { ... }`, add `, sessAutonomousHandles = autonomousHandles`.

- [ ] **Step 1.5: Build and fix compile errors**

Run:

```bash
cd /home/liskil/my-haskell-project/QxFx0
cabal build lib:qxfx0 2>&1 | tail -40
```

Expected: build succeeds with no new warnings.

- [ ] **Step 1.6: Commit**

```bash
git add src/QxFx0/Runtime/Session/Autonomous.hs src/QxFx0/Runtime/Session/Types.hs src/QxFx0/Runtime/Session/Bootstrap.hs
git commit -m "refactor(session): move AutonomousHandles into Session record"
```

---

## Task 2: Implement bounded `LearningQueue`

**Files:**
- Modify: `src/QxFx0/Learning/Autonomous.hs`
- Test: `test/Test/Suite/Autonomous.hs`

- [ ] **Step 2.1: Write the failing bounded-queue test**

In `test/Test/Suite/Autonomous.hs` add:

```haskell
testBoundedQueueRejectWhenFull :: Test
testBoundedQueueRejectWhenFull = TestLabel "bounded queue rejects when full" $
  TestCase $ do
    q <- newLearningQueue 1
    let task1 = LearningTask { ltTopic = "свобода", ltPriority = 1.0, ltRequestId = "r1" }
        task2 = LearningTask { ltTopic = "истина",  ltPriority = 0.5, ltRequestId = "r2" }
    ok1 <- enqueueLearningTask q task1
    ok2 <- enqueueLearningTask q task2
    assertBool "first enqueue accepted" ok1
    assertBool "second enqueue rejected" (not ok2)
    drained <- drainLearningQueue q
    assertEqual "only one task remains" 1 (length drained)
```

Add `testBoundedQueueRejectWhenFull` to `autonomousTests`.

- [ ] **Step 2.2: Run the test to confirm it fails**

```bash
cabal test qxfx0-test --test-options="-t Autonomous" 2>&1 | tail -30
```

Expected: compile error or test failure because `newLearningQueue` does not accept an `Int`.

- [ ] **Step 2.3: Replace `LearningQueue` definition**

In `src/QxFx0/Learning/Autonomous.hs`:

```haskell
import Control.Concurrent.STM (TQueue, TVar, atomically, newTQueue, newTVarIO, readTVar, readTQueue, tryReadTQueue, writeTQueue, modifyTVar')

data LearningQueue = LearningQueue
  { lqQueue :: !(TQueue LearningTask)
  , lqSize  :: !(TVar Int)
  , lqCap   :: !Int
  }
  deriving stock (Eq)

instance Show LearningQueue where
  show q = "LearningQueue {cap=" ++ show (lqCap q) ++ ", size=<?>}"
```

- [ ] **Step 2.4: Update queue helpers**

```haskell
newLearningQueue :: Int -> IO LearningQueue
newLearningQueue cap = atomically $ do
  q <- newTQueue
  sz <- newTVar 0
  pure LearningQueue { lqQueue = q, lqSize = sz, lqCap = max 0 cap }

enqueueLearningTask :: LearningQueue -> LearningTask -> IO Bool
enqueueLearningTask q task = atomically $ do
  sz <- readTVar (lqSize q)
  if sz >= lqCap q
    then pure False
    else do
      writeTQueue (lqQueue q) task
      modifyTVar' (lqSize q) (+1)
      pure True

dequeueLearningTask :: LearningQueue -> IO (Maybe LearningTask)
dequeueLearningTask q = atomically $ do
  mt <- tryReadTQueue (lqQueue q)
  case mt of
    Just _  -> modifyTVar' (lqSize q) (subtract 1) >> pure mt
    Nothing -> pure Nothing

drainLearningQueue :: LearningQueue -> IO [LearningTask]
drainLearningQueue q = atomically $ loop []
  where
    loop acc = do
      mt <- tryReadTQueue (lqQueue q)
      case mt of
        Just t  -> do
          modifyTVar' (lqSize q) (subtract 1)
          loop (t : acc)
        Nothing -> pure (reverse acc)
```

- [ ] **Step 2.5: Update `spawnAutonomousLearningHandles` call**

In `Bootstrap.hs` change `queue <- newLearningQueue` to `queue <- newLearningQueue (awcQueueCap cfg)`.

- [ ] **Step 2.6: Run bounded-queue test**

```bash
cabal test qxfx0-test --test-options="-t Autonomous" 2>&1 | tail -30
```

Expected: `testBoundedQueueRejectWhenFull` passes.

- [ ] **Step 2.7: Commit**

```bash
git add src/QxFx0/Learning/Autonomous.hs src/QxFx0/Runtime/Session/Bootstrap.hs test/Test/Suite/Autonomous.hs
git commit -m "feat(learning): bounded learning queue with reject-when-full"
```

---

## Task 3: Fix worker loop to process one task at a time

**Files:**
- Modify: `src/QxFx0/Learning/Autonomous.hs`
- Test: `test/Test/Suite/Autonomous.hs`

- [ ] **Step 3.1: Write the worker-does-not-drop-second-task test**

In `test/Test/Suite/Autonomous.hs` add:

```haskell
testWorkerProcessesTwoTasks :: Test
testWorkerProcessesTwoTasks = TestLabel "worker step processes two tasks one at a time" $
  TestCase $ do
    q <- newLearningQueue 10
    updates <- atomically newTQueue
    let task1 = LearningTask { ltTopic = "свобода", ltPriority = 1.0, ltRequestId = "r1" }
        task2 = LearningTask { ltTopic = "истина",  ltPriority = 0.5, ltRequestId = "r2" }
        cfg = defaultAutonomousWorkerConfig { awcEnabled = True, awcMaxRequestsPerHour = 10 }
    _ <- enqueueLearningTask q task1
    _ <- enqueueLearningTask q task2
    qsRef <- newIORef (QuotaState (error "unused") 0)
    let responder _ = pure (Just (mkResp "свобода | связана | выбор | relatedto\n"))
    ok1 <- runWorkerStepForTest cfg atomStore (buildAtomMorphology atomStore) qsRef q updates responder
    ok2 <- runWorkerStepForTest cfg atomStore (buildAtomMorphology atomStore) qsRef q updates responder
    assertBool "first step succeeded" ok1
    assertBool "second step succeeded" ok2
    remaining <- drainLearningQueue q
    assertEqual "queue empty after two steps" 0 (length remaining)
```

Add imports as needed (`newIORef`, `QuotaState(..)`). Add to `autonomousTests`.

- [ ] **Step 3.2: Run the test to confirm it fails**

Expected: `runWorkerStepForTest` does not exist.

- [ ] **Step 3.3: Update worker loop in `Autonomous.hs`**

Replace `spawnAutonomousWorker` body with the single-task loop:

```haskell
spawnAutonomousWorker cfg store morph (LearningQueue taskQ _ _) updateQ = do
  qsRef <- newIORef =<< newQuotaState <$> getCurrentTime
  void . forkIO . forever $ do
    if not (awcEnabled cfg)
      then threadDelay (60 * 1000000)
      else do
        mTask <- atomically (dequeueOne taskQ)
        case mTask of
          Nothing   -> threadDelay (5 * 1000000)
          Just task -> processOneTask cfg store morph qsRef taskQ updateQ task
  where
    dequeueOne q = do
      mt <- tryReadTQueue q
      case mt of
        Just _  -> modifyTVar' (lqSize taskQ) (subtract 1) >> pure mt
        Nothing -> pure Nothing
```

(Note: `spawnAutonomousWorker` receives `LearningQueue`, so unwrap once for `taskQ` and `lqSize`.)

- [ ] **Step 3.4: Add `runWorkerStepForTest`**

Export it and implement at the bottom of `Autonomous.hs`:

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
runWorkerStepForTest cfg store morph qsRef taskQ updateQ responder = do
  mTask <- dequeueLearningTask taskQ
  case mTask of
    Nothing -> pure False
    Just task -> do
      mResp <- responder task
      case mResp of
        Nothing -> pure False
        Just resp -> do
          now <- getCurrentTime
          let net = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
              edges = take (awcMaxEdgesPerBatch cfg) (M.elems (snEdges net))
              evt = NetworkUpdateEvent
                { nueTopic     = ltTopic task
                , nueEdges     = edges
                , nueTimestamp = now
                }
          atomicModifyIORef' qsRef (\qs -> (bumpQuota qs now, ()))
          atomically (writeTQueue updateQ evt)
          pure True
```

- [ ] **Step 3.5: Run the test**

Expected: `testWorkerProcessesTwoTasks` passes.

- [ ] **Step 3.6: Commit**

```bash
git add src/QxFx0/Learning/Autonomous.hs test/Test/Suite/Autonomous.hs
git commit -m "fix(learning): worker processes one task at a time"
```

---

## Task 4: Fix quota off-by-one

**Files:**
- Modify: `src/QxFx0/Learning/Autonomous.hs`
- Test: `test/Test/Suite/Autonomous.hs`

- [ ] **Step 4.1: Write the quota regression tests**

Add to `test/Test/Suite/Autonomous.hs`:

```haskell
testQuotaMaxReqOneAllowsFirst :: Test
testQuotaMaxReqOneAllowsFirst = TestLabel "quota maxReq=1 allows first request" $
  TestCase $ do
    q <- newLearningQueue 10
    updates <- atomically newTQueue
    let cfg = defaultAutonomousWorkerConfig { awcEnabled = True, awcMaxRequestsPerHour = 1 }
        task = LearningTask { ltTopic = "свобода", ltPriority = 1.0, ltRequestId = "r1" }
    _ <- enqueueLearningTask q task
    qsRef <- newIORef (QuotaState (error "unused") 0)
    let responder _ = pure (Just (mkResp "свобода | связана | выбор | relatedto\n"))
    ok <- runWorkerStepForTest cfg atomStore (buildAtomMorphology atomStore) qsRef q updates responder
    assertBool "first request allowed" ok
    evts <- drainUpdateQueue updates
    assertEqual "one event emitted" 1 (length evts)

testQuotaMaxReqOneBlocksSecond :: Test
testQuotaMaxReqOneBlocksSecond = TestLabel "quota maxReq=1 blocks second request and re-enqueues" $
  TestCase $ do
    q <- newLearningQueue 10
    updates <- atomically newTQueue
    let cfg = defaultAutonomousWorkerConfig { awcEnabled = True, awcMaxRequestsPerHour = 1 }
        task = LearningTask { ltTopic = "свобода", ltPriority = 1.0, ltRequestId = "r1" }
    _ <- enqueueLearningTask q task
    qsRef <- newIORef (QuotaState (error "unused") 0)
    let responder _ = pure (Just (mkResp "свобода | связана | выбор | relatedto\n"))
    ok1 <- runWorkerStepForTest cfg atomStore (buildAtomMorphology atomStore) qsRef q updates responder
    assertBool "first request allowed" ok1
    -- second step: task was re-enqueued, but quota is exhausted
    ok2 <- runWorkerStepForTest cfg atomStore (buildAtomMorphology atomStore) qsRef q updates responder
    assertBool "second request blocked (no event)" (not ok2)
    remaining <- drainLearningQueue q
    assertEqual "re-enqueued task remains" 1 (length remaining)

testQuotaBlockAndFullQueueDrops :: Test
testQuotaBlockAndFullQueueDrops = TestLabel "quota block with full queue drops task" $
  TestCase $ do
    q <- newLearningQueue 1
    updates <- atomically newTQueue
    let cfg = defaultAutonomousWorkerConfig { awcEnabled = True, awcMaxRequestsPerHour = 1 }
        task = LearningTask { ltTopic = "свобода", ltPriority = 1.0, ltRequestId = "r1" }
    _ <- enqueueLearningTask q task
    qsRef <- newIORef (QuotaState (error "unused") 0)
    let responder _ = pure (Just (mkResp "свобода | связана | выбор | relatedto\n"))
    ok1 <- runWorkerStepForTest cfg atomStore (buildAtomMorphology atomStore) qsRef q updates responder
    assertBool "first request allowed" ok1
    -- q is now empty and quota is exhausted; a new task cannot be re-enqueued
    _ <- enqueueLearningTask q task
    ok2 <- runWorkerStepForTest cfg atomStore (buildAtomMorphology atomStore) qsRef q updates responder
    assertBool "second request dropped" (not ok2)
    remaining <- drainLearningQueue q
    assertEqual "queue stays empty" 0 (length remaining)
```

Add `drainUpdateQueue` helper in the test module if needed.

- [ ] **Step 4.2: Run the tests to confirm they fail**

Expected: tests fail because current `processOneTask` bumps quota before checking.

- [ ] **Step 4.3: Replace quota helpers in `Autonomous.hs`**

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

Update `processOneTask`:

```haskell
processOneTask cfg store morph qsRef taskQ updateQ task = do
  now <- getCurrentTime
  qs <- atomicModifyIORef' qsRef (\q ->
           let q' = if diffUTCTime now (qsResetAt q) >= 3600
                      then QuotaState { qsResetAt = now, qsRequests = 0 }
                      else q
           in (q', q'))
  if not (quotaAllows cfg qs)
    then do
      enqueued <- enqueueLearningTask (LearningQueue taskQ undefined (lqCap undefined)) task
      if enqueued
        then pure ()
        else hPutStrLn stderr $ "[autonomous] quota blocked + queue full; dropping task " <> T.unpack (ltRequestId task)
    else do
      atomicModifyIORef' qsRef (\q -> (bumpQuota q now, ()))
      -- existing LLM call / event emission
```

Wait — `processOneTask` receives `TQueue LearningTask`, not `LearningQueue`. Change its signature to accept `LearningQueue` so re-enqueue is type-safe and size-aware. Update the worker loop call site.

- [ ] **Step 4.4: Run the tests**

Expected: all three quota tests pass.

- [ ] **Step 4.5: Commit**

```bash
git add src/QxFx0/Learning/Autonomous.hs test/Test/Suite/Autonomous.hs
git commit -m "fix(learning): quota check-before-bump and full-queue drop"
```

---

## Task 5: Wire turn-boundary hooks into `Engine.hs`

**Files:**
- Modify: `src/QxFx0/Runtime/Engine.hs`
- Modify: `src/QxFx0/Learning/Autonomous.hs` (add `applyPendingUpdatesForSession` helper)
- Test: `test/Test/Suite/AutonomousLoop.hs`

- [ ] **Step 5.1: Add `applyPendingUpdatesForSession` to `Autonomous.hs`**

```haskell
applyPendingUpdatesForSession :: AutonomousHandles -> SystemState -> IO SystemState
applyPendingUpdatesForSession handles ss =
  case ahUpdateQueue handles of
    Nothing     -> pure ss
    Just updateQ -> applyPendingNetworkUpdates atomStore (buildAtomMorphology atomStore) updateQ ss
```

Export it.

- [ ] **Step 5.2: Update `runTurnWithRevision` and add wrapper in `Engine.hs`**

```haskell
runTurnWithRevision :: RuntimeContext -> SystemState -> Text -> Text -> Int -> IO (SystemState, Text)
runTurnWithRevision ctx = runTurnWithRevisionWithAutonomous ctx Nothing

runTurnWithRevisionWithAutonomous
  :: RuntimeContext -> Maybe AutonomousHandles -> SystemState -> Text -> Text -> Int -> IO (SystemState, Text)
runTurnWithRevisionWithAutonomous ctx mbHandles ss input sessionId expectedRevision
  | T.length input > maxInputLength = ...
  | otherwise = withRuntimeSession ctx sessionId $ do
      ss0 <- maybe (pure ss) (`applyPendingUpdatesForSession` ss) mbHandles
      runTurnBody ctx ss0 input sessionId expectedRevision mbHandles
```

- [ ] **Step 5.3: Update `runTurnBody` signature and add enqueue hook**

```haskell
runTurnBody :: RuntimeContext -> SystemState -> Text -> Text -> Int -> Maybe AutonomousHandles -> IO (SystemState, Text)
runTurnBody ctx ss input sessionId expectedRevision mbHandles = do
  let pio = toPipelineIO ctx
  reqId <- resolveRequestId pio
  prepared <- prepareTurn pio ss input sessionId reqId
  planned@(PlannedTurn ti _ _) <- planTurn pio ss prepared
  case mbHandles of
    Just handles -> forM_ (ahQueue handles) $ \q ->
      maybeEnqueueStarvingTopic q (ssLemmaMap ss) defaultDensityConfig (tiBestTopic ti) (ssSemanticNetwork ss)
    Nothing -> pure ()
  rendered <- renderTurn pio ss planned
  tr <- finalizeTurn pio ss sessionId expectedRevision reqId rendered
  pure (trNextSs tr, trOutput tr)
```

Add imports:

```haskell
import QxFx0.Runtime.Session.Autonomous (AutonomousHandles(..))
import QxFx0.Learning.Autonomous (applyPendingUpdatesForSession, maybeEnqueueStarvingTopic)
import QxFx0.Core.TurnPipeline.Protocol (PlannedTurn(..))
import QxFx0.Semantic.Network.Seed (defaultDensityConfig)
import Control.Monad (forM_)
```

- [ ] **Step 5.4: Update `runTurnInSession` to pass handles**

In `continueTurn`:

```haskell
turnResult <- try (runTurnWithRevisionWithAutonomous runtime (Just (sessAutonomousHandles s)) ss text sid expectedRevision)
```

Also update the direct `runTurn` export path if it needs to remain handle-less (it already calls `runTurnWithRevision`, which is now a wrapper, so no change needed).

- [ ] **Step 5.5: Build**

```bash
cabal build lib:qxfx0 2>&1 | tail -40
```

Expected: compiles cleanly.

- [ ] **Step 5.6: Commit**

```bash
git add src/QxFx0/Runtime/Engine.hs src/QxFx0/Learning/Autonomous.hs
git commit -m "feat(engine): wire autonomous enqueue and apply hooks at turn boundary"
```

---

## Task 6: Fix and extend integration tests

**Files:**
- Modify: `test/Test/Suite/AutonomousLoop.hs`
- Modify: `test/Test/Suite/Autonomous.hs` (add helpers if needed)

- [ ] **Step 6.1: Fix the existing integration test**

Replace `testEndToEndLoop` in `AutonomousLoop.hs`:

```haskell
testEndToEndLoop :: Test
testEndToEndLoop = TestLabel "end-to-end: event → update queue → apply → edge" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = mkResp "свобода | связана | выбор | relatedto\n"
        net   = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
        evt   = NetworkUpdateEvent
          { nueTopic     = "свобода"
          , nueEdges     = M.elems (snEdges net)
          , nueTimestamp = undefined
          }
        ss0   = emptySystemState
    updates <- atomically newTQueue
    atomically (writeTQueue updates evt)
    ss1 <- applyPendingNetworkUpdates store morph updates ss0
    let edges = M.size (snEdges (ssSemanticNetwork ss1))
    assertBool "at least one edge after apply" (edges >= 1)
```

- [ ] **Step 6.2: Add deterministic runtime integration test**

```haskell
testRuntimeIntegrationAppliesPendingUpdate :: Test
testRuntimeIntegrationAppliesPendingUpdate = TestLabel "runtime integration: pending update applied across turn" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = mkResp "свобода | связана | выбор | relatedto\n"
        net   = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
        evt   = NetworkUpdateEvent
          { nueTopic     = "свобода"
          , nueEdges     = M.elems (snEdges net)
          , nueTimestamp = undefined
          }
    withEnv [("QXFX0_AUTONOMOUS_LEARNING", "1"), ("QXFX0_LLM_TRANSPORT", "mock")] $ do
      withBootstrappedSession True "test-session-apply" $ \session -> do
        case ahUpdateQueue (sessAutonomousHandles session) of
          Nothing -> assertFailure "autonomous handles not initialised"
          Just updateQ -> atomically (writeTQueue updateQ evt)
        (session', _response) <- runTurnInSession session "что такое свобода?"
        let learnedEdges = M.size (snEdges (ssSemanticNetwork (sessSystemState session')))
        assertBool "learned edge present in next-turn network" (learnedEdges >= 1)
```

Add `withEnv` helper at the bottom of the test module:

```haskell
withEnv :: [(String, String)] -> IO a -> IO a
withEnv pairs action = bracket setup restore (const action)
  where
    setup = mapM (\(k, v) -> do old <- lookupEnv k; setEnv k v; pure (k, old)) pairs
    restore = mapM_ (\(k, old) -> maybe (unsetEnv k) (setEnv k) old)
```

- [ ] **Step 6.3: Run the integration tests**

```bash
cabal test qxfx0-test --test-options="-t AutonomousLoop" 2>&1 | tail -40
```

Expected: both tests pass.

- [ ] **Step 6.4: Run the full autonomous test suite**

```bash
cabal test qxfx0-test --test-options="-t Autonomous" 2>&1 | tail -40
```

Expected: all tests pass.

- [ ] **Step 6.5: Commit**

```bash
git add test/Test/Suite/AutonomousLoop.hs test/Test/Suite/Autonomous.hs
git commit -m "test(learning): deterministic runtime integration and fixed apply test"
```

---

## Task 7: Full build and test verification

- [ ] **Step 7.1: Build the library and tests**

```bash
cabal build qxfx0:test:qxfx0-test 2>&1 | tail -20
```

Expected: no compile errors.

- [ ] **Step 7.2: Run the autonomous tests**

```bash
cabal test qxfx0-test --test-options="-t Autonomous" 2>&1 | tail -30
```

Expected: all green.

- [ ] **Step 7.3: Run the full test suite**

```bash
cabal test qxfx0-test 2>&1 | tail -30
```

Expected: full suite green (or at least no new failures introduced by M3).

- [ ] **Step 7.4: Commit if not already committed**

```bash
git status --short
# If there are uncommitted changes:
git add -A
git commit -m "test(learning): full M3 verification"
```

---

## Self-Review Checklist

- [ ] Every spec requirement has a matching task.
- [ ] No `TBD`/`TODO`/placeholder text remains in code or plan.
- [ ] `LearningQueue` API is consistent across all call sites.
- [ ] `runTurnWithRevision` signature unchanged for existing callers.
- [ ] Pure pipeline functions (`prepareTurn`, `planTurn`, `renderTurn`, `finalizeTurn`) receive no autonomous state.
- [ ] All tests are deterministic (no `threadDelay` races).
- [ ] M4 features are not partially implemented.
