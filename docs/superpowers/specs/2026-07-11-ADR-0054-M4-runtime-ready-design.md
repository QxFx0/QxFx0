# ADR-0054 M4 Runtime-Ready Design

## Goal

Make autonomous LLM-driven semantic-network expansion safe and observable:
contradiction-gated merges, provenance-aware authority policy with no silent
overwrite of authoritative edges, real quarantine store, snapshot/rollback
for failed apply batches, a circuit breaker on parse failure, and
runtime-visible metrics. M3 closed the runtime loop; M4 closes the safety
loop.

## Non-Goals

- Disk-persisted snapshot versions (only in-memory per-apply snapshots in M4).
- LLM-call rate limiting beyond the existing `awcMaxRequestsPerHour` quota.
- Quarantine triage UI / operator workflow — only programmatic read API.
- Cross-session quarantine aggregation.
- Replacing `applyPendingNetworkUpdates` semantics for M2 feedback path —
  M4 only changes the M3 / autonomous path.

## Constraints

- All M4 safety logic lives in `QxFx0.Learning.*` and the IO-boundary
  helpers in `QxFx0.Runtime.Session.Autonomous`. Pure turn-pipeline
  functions stay untouched.
- Quarantine writes go through the existing `QxFx0.Bridge.SQLite` /
  `withDB` / `prepareTx` / `bindTextOrFail` / `stepOrFail` pattern.
  No raw SQL outside `QxFx0.Bridge.SQLite.hs`.
- No new external dependencies. `sha256` already available via
  `Crypto.Hash.SHA256` (already in dependency graph from `crypton`).
- M3 behaviour must not regress: `applyPendingUpdatesForSession`,
  bounded queue, single-task worker, quota, `runTurnWithRevisionWithAutonomous`
  all keep their contracts; M4 only adds safety layers around them.
- Tests deterministic; no `threadDelay` races.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Quarantine persistence | **SQLite** via `QxFx0.Bridge.SQLite` (new table `quarantine`). |
| Circuit-breaker requeue | **Side-queue** `pendingBreakerCloseQueue`: worker pushes to it when breaker is open; watcher re-enqueues into main queue when breaker closes. |
| Same-authority tie-break | **Composite score**: `score(e) = seConfidence e * (1 + log(1 + fromIntegral (seCoOccurrence e)))`. Incoming wins if `score(incoming) > score(existing) + 0.01`. Tie → keep existing. |

## Architecture

```
worker loop
  ├─ quota check (M3, unchanged)
  ├─ circuit-breaker check (M4 NEW)
  │     ├─ open → push task to pendingBreakerCloseQueue; continue idle
  │     └─ closed → continue
  ├─ LLM call
  ├─ parse → NetworkUpdateEvent (M4 EXTENDED schema)
  ├─ recordParseSuccess / recordParseFailure → CircuitBreakerState
  └─ write event to ahUpdateQueue

pendingBreakerCloseQueue watcher (new thread, spawned by spawnAutonomousWorker)
  forever (sleep 30s; if circuitBreakerOpen = False
              then drain pendingBreakerCloseQueue → main LearningQueue)

runTurnWithRevisionWithAutonomous (M3 wrapper)
  └─ applyPendingUpdatesForSession
       ├─ snapshot ssSemanticNetwork.edges in memory  (M4 NEW)
       ├─ for each NetworkUpdateEvent:
       │     ├─ for each incoming SemanticEdge:
       │     │     ├─ existing = M.lookup (from,to) snEdges
       │     │     ├─ if existing and isContradictory existing incoming
       │     │     │     ├─ authority(existing) ≥ authority(incoming)
       │     │     │     │     → drop incoming, quarantine with reason "lower_authority_contradiction"
       │     │     │     └─ authority(existing) < authority(incoming)
       │     │     │           → replace existing, record lineage
       │     │     ├─ if existing and authority(existing) == authority(incoming)
       │     │     │     → composite-score tie-break, winner applied, loser quarantined with reason "same_authority_replaced"
       │     │     └─ else → insert (or same-authority replace via score)
       ├─ if any exception → restore ssSemanticNetwork.edges from snapshot, record rollback
       ├─ trimQuarantine (cap 10 000 rows, oldest first)
       └─ emit batch metrics (LearningMetrics → Log.logInfo JSON + ssGuardrailState)

Quarantine writes use QxFx0.Bridge.SQLite (withDB / prepareTx / bindTextOrFail / stepOrFail).
SHA-256 of prompt and response body (not the full body — hashes only).
```

## Components

### 1. Provenance authority policy

New helper:

```haskell
-- | Authority rank: higher value = higher authority.
authorityRank :: EdgeProvenance -> Int
authorityRank ProvenanceCurated          = 4
authorityRank ProvenanceIngested         = 4   -- network ingest is authoritative
authorityRank ProvenanceSelfPlay         = 4
authorityRank ProvenanceDialogueFeedback = 2
authorityRank ProvenanceCorpus           = 2
authorityRank ProvenanceSubstrate        = 1
authorityRank ProvenanceIngested         = 4   -- (already above; runtime-LLM tagged Ingested gets rank 1)
```

Wait — `ProvenanceIngested` is overloaded: both authoritative ingest and
runtime-LLM responses use it. To disambiguate at M4, **runtime-LLM edges
get a new `ProvenanceRuntimeLLM`** constructor. Migrate
`autonomousApplyLLMResponse` to stamp `ProvenanceRuntimeLLM` (was
`ProvenanceIngested`). Existing curated/seed ingest keeps
`ProvenanceIngested`. This is a semantic change but only M3's new
edges are affected; pre-M3 network data uses `ProvenanceCorpus` /
`ProvenanceSelfPlay` / etc.

Final authority ranks:

```haskell
authorityRank :: EdgeProvenance -> Int
authorityRank ProvenanceCurated          = 4
authorityRank ProvenanceIngested         = 4
authorityRank ProvenanceSelfPlay         = 4
authorityRank ProvenanceDialogueFeedback = 2
authorityRank ProvenanceCorpus           = 2
authorityRank ProvenanceSubstrate        = 1
authorityRank ProvenanceRuntimeLLM       = 1
```

`isAuthoritative` (already in `Semantic/Network.hs`) returns `True` for
rank ≥ 4. M4 keeps that for `mergeSemanticNetworks` and
`mergeSemanticNetworksWithProvenance`. M4's apply path uses
`authorityRank` for the higher-rank comparison.

### 2. Composite-score tie-break

```haskell
edgeScore :: SemanticEdge -> Double
edgeScore e =
  seConfidence e * (1.0 + log (1.0 + fromIntegral (seCoOccurrence e)))

-- | Epsilon to avoid flapping on near-ties.
tieBreakEpsilon :: Double
tieBreakEpsilon = 0.01

-- | Returns 'True' if 'incoming' wins over 'existing'.
-- Pre-condition: authorityRank(incoming) == authorityRank(existing).
incomingWinsByScore :: SemanticEdge -> SemanticEdge -> Bool
incomingWinsByScore incoming existing =
  edgeScore incoming > edgeScore existing + tieBreakEpsilon
```

Tie (within epsilon) → keep existing for stability.

### 3. SQLite quarantine store

New module `src/QxFx0/Learning/Quarantine.hs`:

```haskell
data QuarantineReason
  = QRContradiction
  | QRLowerAuthorityConflict
  | QRSameAuthorityReplaced
  | QRParseFailure
  | QRCircuitOpenDrop
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON, NFData)

data QuarantineEntry = QuarantineEntry
  { qeTimestamp       :: !UTCTime
  , qeTurnSeq         :: !(Maybe Int)
  , qeRequestId       :: !Text
  , qeTopic           :: !Text
  , qeEdgeFrom        :: !Text
  , qeEdgeTo          :: !Text
  , qeEdgeProvenance  :: !EdgeProvenance
  , qeEdgeRelationType:: !(Maybe Text)
  , qeEdgeConfidence  :: !Double
  , qeConflictingFrom :: !(Maybe Text)
  , qeConflictingTo   :: !(Maybe Text)
  , qeConflictingProv :: !(Maybe Text)
  , qeReason          :: !QuarantineReason
  , qeSource          :: !Text  -- "apply" | "worker" | "parser"
  , qePromptHash      :: !(Maybe Text)
  , qeResponseHash    :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON, NFData)
```

Schema additions to `QxFx0.Bridge.SQLite.hs`:

```haskell
ensureQuarantineSchema :: DB -> IO ()
ensureQuarantineSchema db = withDB db $ \conn -> do
  ts <- prepareTx conn "ensure_quarantine_schema"
    "CREATE TABLE IF NOT EXISTS quarantine (
       id INTEGER PRIMARY KEY AUTOINCREMENT,
       ts INTEGER NOT NULL,
       turn_seq INTEGER,
       request_id TEXT NOT NULL,
       topic TEXT NOT NULL,
       edge_from TEXT NOT NULL, edge_to TEXT NOT NULL,
       edge_provenance TEXT NOT NULL,
       edge_relation_type TEXT,
       edge_confidence REAL NOT NULL,
       conflicting_from TEXT, conflicting_to TEXT,
       conflicting_provenance TEXT,
       reason TEXT NOT NULL,
       source TEXT NOT NULL,
       prompt_hash TEXT, response_hash TEXT
     )"
  stepOrFail ts
  i1 <- prepareTx conn "ensure_quarantine_idx_ts"
    "CREATE INDEX IF NOT EXISTS idx_quarantine_ts ON quarantine(ts)"
  stepOrFail i1
  i2 <- prepareTx conn "ensure_quarantine_idx_topic"
    "CREATE INDEX IF NOT EXISTS idx_quarantine_topic ON quarantine(topic)"
  stepOrFail i2
```

API:

```haskell
recordQuarantine :: DB -> QuarantineEntry -> IO ()
recordQuarantine db qe = withDB db $ \conn -> do
  -- INSERT INTO quarantine (...) VALUES (...)
  -- then trimQuarantine conn 10000
  ...

trimQuarantine :: DB -> Int -> IO ()
trimQuarantine db cap = withDB db $ \conn -> do
  -- DELETE FROM quarantine WHERE id IN (
  --   SELECT id FROM quarantine ORDER BY ts DESC, id DESC LIMIT -1 OFFSET cap)
  ...

listQuarantine :: DB -> Maybe Text -> Maybe UTCTime -> Int -> IO [QuarantineEntry]
listQuarantine db mTopic mSinceLimit cap = ...
```

Cap = 10 000 rows; older rows deleted FIFO.

### 4. Snapshot / rollback in `applyPendingUpdatesForSession`

Current signature:
```haskell
applyPendingUpdatesForSession :: AutonomousHandles -> SystemState -> IO SystemState
```

M4 keeps this signature but internals change:

```haskell
applyPendingUpdatesForSession handles ss = do
  case ahUpdateQueue handles of
    Nothing     -> pure ss
    Just updateQ -> do
      pending <- drainUpdateQueue updateQ
      let originalEdges = snEdges (ssSemanticNetwork ss)
          baseNet       = ssSemanticNetwork ss
      result <- try (applyBatchWithMetrics handles baseNet pending) :: IO (Either SomeException SemanticNetwork)
      case result of
        Left _ -> do
          -- Rollback: restore original edges
          let rolled = (ssSemanticNetwork ss) { snEdges = originalEdges }
          pure ss { ssSemanticNetwork = rolled }
        Right newNet ->
          pure ss { ssSemanticNetwork = newNet }
```

`applyBatchWithMetrics` does the per-edge contradiction + provenance check,
merges, increments metrics, writes quarantine. If it throws (e.g. SQLite
failure during `recordQuarantine`), the catch restores edges and the
caller still gets a consistent `SystemState`.

### 5. Circuit breaker integration

`processOneTask` becomes:

```haskell
processOneTask cfg store morph qsRef taskQ updateQ cbRef handles task = do
  now <- getCurrentTime
  qs0 <- readIORef qsRef
  let qs = if diffUTCTime now (qsResetAt qs0) >= 3600
             then QuotaState { qsResetAt = now, qsRequests = 0 }
             else qs0
  if not (quotaAllows cfg qs)
    then ...  -- M3 re-enqueue or drop
    else do
      atomicModifyIORef' qsRef (\q -> (bumpQuota q now, ()))
      cb <- readIORef cbRef
      now' <- getCurrentTime
      if isCircuitOpen cb now'
        then do
          -- Push task to pendingBreakerCloseQueue (bounded, like main queue)
          case ahPendingBreakerQueue handles of
            Just sq -> void (enqueueBreakerSideQueue sq task)
            Nothing -> pure ()  -- no side queue: drop with warning
          -- metrics: lmCircuitOpenDropped
        else do
          result <- ... -- LLM call (unchanged)
          case result of
            Left _ -> do
              newCb <- recordParseFailure cb
              writeIORef cbRef newCb
              -- metrics: lmParseFailures
            Right resp -> do
              let net = autonomousApplyLLMResponse store morph need resp
                  admitted = M.elems (snEdges net)
              if null admitted
                then do
                  newCb <- recordParseFailure cb  -- zero admitted = failure
                  writeIORef cbRef newCb
                else do
                  newCb <- recordParseSuccess cb
                  writeIORef cbRef newCb
              let edges = take (awcMaxEdgesPerBatch cfg) admitted
                  evt = NetworkUpdateEvent { ... nueParseStatus = ParseOk, ... }
              atomically (writeTQueue updateQ evt)
```

New types:

```haskell
-- | Bounded side queue of tasks deferred because the circuit breaker is open.
newtype PendingBreakerCloseQueue = PendingBreakerCloseQueue
  { pbqTQueue :: TQueue LearningTask
  , pbqSize  :: TVar Int
  , pbqCap   :: !Int
  }

newPendingBreakerCloseQueue :: Int -> IO PendingBreakerCloseQueue
enqueueBreakerSideQueue :: PendingBreakerCloseQueue -> LearningTask -> IO Bool
dequeueBreakerSideQueue :: PendingBreakerCloseQueue -> IO (Maybe LearningTask)
```

Watcher thread (spawned by `spawnAutonomousWorker`):

```haskell
spawnBreakerWatcher :: IORef CircuitBreakerState
                    -> PendingBreakerCloseQueue
                    -> LearningQueue
                    -> IO ()
spawnBreakerWatcher cbRef sq mainQ = void . forkIO . forever $ do
  threadDelay (30 * 1000 * 1000)  -- 30s
  cb <- readIORef cbRef
  now <- getCurrentTime
  if not (isCircuitOpen cb now)
    then drainAll sq mainQ
    else pure ()
  where
    drainAll sq mainQ = forever $ do
      mTask <- dequeueBreakerSideQueue sq
      case mTask of
        Nothing -> pure ()
        Just t  -> do
          ok <- enqueueLearningTask mainQ t
          when (not ok) $ -- main queue full: put it back
            void (enqueueBreakerSideQueue sq t)
```

`AutonomousHandles` gains `ahPendingBreakerQueue :: !(Maybe PendingBreakerCloseQueue)`.

### 6. LearningMetrics extension

```haskell
data ParseStatus
  = ParseOk
  | ParseEmpty
  | ParseFail !Text   -- reason
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON, NFData)

data LearningMetrics = LearningMetrics
  { lmQueueSize              :: !Int
  , lmPendingBreakerQueueSize:: !Int
  , lmRequestsTotal          :: !Int
  , lmRequestsFailed         :: !Int
  , lmParseFailures          :: !Int
  , lmEdgesAccepted          :: !Int
  , lmEdgesRejected          :: !Int
  , lmEdgesQuarantined       :: !Int
  , lmBatchesApplied         :: !Int
  , lmRollbacks              :: !Int
  , lmCircuitOpen            :: !Bool
  , lmCircuitOpens           :: !Int
  , lmLastBatchAt            :: !(Maybe UTCTime)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)
```

Default `emptyLearningMetrics`: all counters 0, `lmCircuitOpen = False`,
`lmLastBatchAt = Nothing`.

Per-batch log:
```haskell
logBatchMetrics :: LearningMetrics -> IO ()
logBatchMetrics m = Log.logInfo "autonomous.apply.batch"
  (Log.addContext "metrics" (encodeToText m) Log.emptyContext)
```

Also snapshot metrics into `ssGuardrailState` after every successful batch
so the next turn sees them.

### 7. NetworkUpdateEvent schema extension

```haskell
data NetworkUpdateEvent = NetworkUpdateEvent
  { nueTopic        :: !Text
  , nueRequestId    :: !Text
  , nueSourceTopic  :: !Text
  , nueEdges        :: ![SemanticEdge]
  , nueParseStatus  :: !ParseStatus
  , nueRawAccepted  :: !Int
  , nueRawRejected  :: !Int
  , nueProvenance   :: !EdgeProvenance
  , nuePromptHash   :: !(Maybe Text)   -- sha256 hex, or Nothing
  , nueResponseHash :: !(Maybe Text)   -- sha256 hex, or Nothing
  , nueTimestamp    :: !UTCTime
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON, NFData)
```

This is a **breaking change** for any code that constructs
`NetworkUpdateEvent` (M3 worker + tests). Migration: every constructor
call must provide `nueRequestId`, `nueSourceTopic`, `nueParseStatus`,
`nueRawAccepted`, `nueRawRejected`, `nueProvenance`, `nuePromptHash`,
`nueResponseHash`. `runWorkerStepForTest` (M3) and `processOneTask`
(M3) updated accordingly.

`EdgeProvenance` gains `ProvenanceRuntimeLLM`. Default JSON for
`ProvenanceRuntimeLLM` added to `FromJSON` enum coverage.

### 8. SHA-256 hashing

```haskell
import Crypto.Hash (hash, SHA256(..))
import qualified Data.ByteArray.Encoding (Base(Base16), convertToBase)

sha256Hex :: BS.ByteString -> Text
sha256Hex bs =
  let digest  = hash (SHA256) bs
      Base16 hex = convertToBase Base16 digest
  in TE.decodeUtf8 hex
```

Used in worker: `sha256Hex (TE.encodeUtf8 promptBody)` and same for
response body.

## File Structure

| File | Responsibility |
|------|----------------|
| `src/QxFx0/Learning/Quarantine.hs` (new) | `QuarantineReason`, `QuarantineEntry`, `recordQuarantine`, `trimQuarantine`, `listQuarantine` |
| `src/QxFx0/Learning/CircuitBreaker.hs` (extract or in Autonomous) | `PendingBreakerCloseQueue`, watcher, side-queue helpers |
| `src/QxFx0/Bridge/SQLite.hs` | Add `ensureQuarantineSchema` |
| `src/QxFx0/Semantic/Network/Types.hs` | Add `ProvenanceRuntimeLLM` constructor (extend FromJSON/ToJSON) |
| `src/QxFx0/Learning/Autonomous.hs` | Extend `LearningMetrics`, `NetworkUpdateEvent`, `processOneTask` (breaker + side-queue), `applyPendingUpdatesForSession` (contradiction + provenance + snapshot/rollback + quarantine writes), `spawnAutonomousWorker` (start watcher) |
| `src/QxFx0/Runtime/Session/Autonomous.hs` | `AutonomousHandles` gains `ahPendingBreakerQueue`, `ahQuarantineDB` |
| `src/QxFx0/Runtime/Session/Bootstrap.hs` | Spawn `ensureQuarantineSchema`, create `PendingBreakerCloseQueue`, pass into handles |
| `test/Test/Suite/AutonomousSafety.hs` (new) | 5 safety tests (contradiction quarantine, same-authority replacement, snapshot rollback, circuit breaker, observability) |
| `test/Test/Suite/Autonomous.hs` | Update for new `NetworkUpdateEvent` fields and `runWorkerStepForTest` signature |
| `test/Test/Suite/AutonomousLoop.hs` | Update for new `NetworkUpdateEvent` fields |
| `CHANGELOG.md` | M4 entry |
| `AGENTS.md` | M4 summary + deferred items note |

## Testing

### Unit tests in `Test.Suite.AutonomousSafety` (new)

1. **`testContradictionQuarantinesLowerAuthority`**: existing curated edge
   `(A, B, Presupposes)`. Incoming runtime-LLM edge `(A, B, Negates)`.
   Expect: existing unchanged, incoming edge in quarantine with reason
   `QRLowerAuthorityConflict`, `lmEdgesQuarantined += 1`.

2. **`testSameAuthorityReplacement`**: existing runtime-LLM edge
   `(A, B, RelatedTo, confidence=0.4, coOccurrence=1)`. Incoming runtime-LLM
   edge `(A, B, RelatedTo, confidence=0.7, coOccurrence=1)`. Expect: edge
   replaced (score 0.7 > 0.4 + ε).

3. **`testSnapshotRollback`**: pre-seed a working edge. Force
   `recordQuarantine` to throw (by closing the SQLite handle). Run
   `applyPendingUpdatesForSession`. Expect: original network restored
   unchanged, `lmRollbacks += 1`.

4. **`testCircuitBreaker`**: 3 `recordParseFailure` calls open breaker
   (threshold = 3). While open, enqueue task, run worker step. Expect:
   no LLM call (mock transport counter unchanged), task pushed to
   `PendingBreakerCloseQueue`. Sleep / signal breaker close, re-run step.
   Expect: task drained back to main queue, processed normally.

5. **`testObservabilityMetrics`**: run a batch with 1 accepted + 1
   quarantined edge. Expect: `lmEdgesAccepted == 1`,
   `lmEdgesQuarantined == 1`, `lmBatchesApplied == 1`, metrics JSON
   serialises with all expected fields.

### Regression updates

- `Test.Suite.Autonomous.testApplyPendingNetworkUpdates` — update
  `NetworkUpdateEvent` constructor call to include new fields.
- `Test.Suite.Autonomous.testWorkerProcessesTwoTasks`,
  `testQuotaMaxReqOneAllowsFirst`, `testQuotaMaxReqOneBlocksSecond`,
  `testQuotaBlockAndFullQueueDrops` — update
  `runWorkerStepForTest` calls to pass new args (or use default
  `ParseOk`, `nueRawAccepted=1`, etc.).
- `Test.Suite.AutonomousLoop.testEndToEndLoop`,
  `testApplyPendingUpdatesForSession`,
  `testEndToEndLoopWithMixedEndpoints` — update event construction.

### Determinism

All tests use `runWorkerStepForTest` with mock responder — no
`threadDelay` races. Side-queue watcher is not exercised in tests
directly; its public API (`enqueueBreakerSideQueue`,
`dequeueBreakerSideQueue`) is unit-tested.

## Risks / Migration Notes

- `ProvenanceIngested` is currently used for both authoritative ingest
  AND runtime-LLM edges. M4 splits them: `ProvenanceIngested` stays
  authoritative, runtime-LLM gets new `ProvenanceRuntimeLLM` (rank 1).
  `autonomousApplyLLMResponse` is updated to stamp the new
  constructor. This is a **behavioral change**: M3-stamped
  `ProvenanceIngested` LLM edges would have been rank 4 (treated as
  authoritative). After M4 they are rank 1, so they can no longer
  silently overwrite curated/selfplay/seed edges — which is exactly
  M4's "no silent overwrite" requirement. Documented in CHANGELOG.

- Existing persisted `semantic_network` edges in `runtime.db` (if any)
  were stamped under the old scheme. M4's apply path only reads
  `ssSemanticNetwork` (in-memory), so no DB migration is required
  for existing edges. New runtime-LLM edges get
  `ProvenanceRuntimeLLM`.

- `QuarantineEntry` is new; no schema migration needed beyond
  `CREATE TABLE IF NOT EXISTS`. Migration bump not required because
  the table is created idempotently by `ensureQuarantineSchema` on
  bootstrap.

## Definition of Done for M4

- `applyPendingUpdatesForSession` rejects runtime-LLM edges that
  contradict authoritative edges and writes them to the SQLite
  `quarantine` table.
- `applyPendingUpdatesForSession` uses composite-score tie-break for
  same-authority conflicts.
- Snapshot/rollback restores `ssSemanticNetwork` on apply exception
  and increments `lmRollbacks`.
- Circuit breaker opens after 3 consecutive parse failures; while
  open, worker pushes tasks to `PendingBreakerCloseQueue`; watcher
  re-enqueues when breaker closes.
- `LearningMetrics` is emitted as a structured log per batch and
  snapshotted into `ssGuardrailState` for the next turn.
- `NetworkUpdateEvent` carries `requestId`, `sourceTopic`,
  `parseStatus`, `rawAccepted`, `rawRejected`, `provenance`,
  `promptHash`, `responseHash`.
- All M3 tests still pass after schema extension.
- All 5 new safety tests pass.
- CHANGELOG and AGENTS.md updated.

## Self-Review Checklist

- [ ] Every M4 requirement in the original ADR-0054 §M4 text has a
  matching component above.
- [ ] No `TBD` / `TODO` / placeholders.
- [ ] Same-authority tie-break formula is unambiguous
  (`score = confidence * (1 + log(1+coOcc))`, incoming wins if
  `> +0.01`).
- [ ] Quarantine schema is fully specified (columns, indices, cap).
- [ ] Side-queue interaction with bounded main queue is bounded
  end-to-end.
- [ ] Snapshot is per-apply, in-memory; rollback on any exception.
- [ ] `ProvenanceRuntimeLLM` split from `ProvenanceIngested` is
  documented as a behavioral change.
- [ ] M3 contracts preserved.
