{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Durable, candidate-targeted second-observation work.  This queue is
-- deliberately separate from topic discovery jobs: a task names exactly one
-- canonical runtime shape and never permits a free-form graph proposal.
module QxFx0.Learning.CorroborationQueue
  ( CorroborationTaskState(..)
  , CorroborationTask(..)
  , CorroborationTaskSeed(..)
  , CorroborationReadyResponse(..)
  , currentCorroborationPolicyVersion
  , ensureCorroborationTaskSchema
  , enqueueCorroborationTaskOnConnection
  , claimCorroborationBatch
  , claimCorroborationBatchForSession
  , loadCorroborationResponseReady
  , loadCorroborationResponseReadyForSession
  , releaseCorroborationReadyResponses
  , releaseCorroborationApplyProofs
  , recordCorroborationResponseReady
  , releaseCorroborationBatch
  , markCorroborationTaskTerminal
  , markCorroborationTaskTerminalOnConnection
  , authorizeCorroborationApplyOnConnection
  , markCorroborationTaskFailed
  ) where

import Control.Exception (mask_, onException)
import Control.Monad (forM, forM_, unless, when)
import Data.Int (Int64)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)

import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement
  ( TxStmt
  , bindDoubleOrFail
  , bindInt64OrFail
  , bindNullOrFail
  , bindTextOrFail
  , prepareTx
  , stepOrFail
  )
import QxFx0.Learning.JobQueue (recordLearningResponseOnConnection)
import QxFx0.ExceptionPolicy (mkSQLiteError, throwQxFx0)

data CorroborationTaskState
  = CtsPending
  | CtsLeased
  | CtsResponseReady
  | CtsSucceeded
  | CtsRejected
  | CtsConflicted
  | CtsFailed
  deriving stock (Eq, Ord, Show, Read)

data CorroborationTask = CorroborationTask
  { ctId :: !Int64
  , ctTopic :: !Text
  , ctEdgeFrom :: !Text
  , ctEdgeTo :: !Text
  , ctRelationType :: !Text
  , ctNamespace :: !Text
  , ctSessionId :: !(Maybe Text)
  , ctOwner :: !Text
  , ctSourceRequestId :: !Text
  , ctSourceResponseHash :: !Text
  , ctPriority :: !Double
  , ctState :: !CorroborationTaskState
  , ctAttempts :: !Int
  , ctMaxAttempts :: !Int
  , ctConfirmationRequestId :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

data CorroborationTaskSeed = CorroborationTaskSeed
  { ctsTopic :: !Text
  , ctsEdgeFrom :: !Text
  , ctsEdgeTo :: !Text
  , ctsRelationType :: !Text
  , ctsNamespace :: !Text
  , ctsSessionId :: !(Maybe Text)
  , ctsOwner :: !Text
  , ctsSourceRequestId :: !Text
  , ctsSourceResponseHash :: !Text
  , ctsPriority :: !Double
  , ctsAudit :: !Text
  }
  deriving stock (Eq, Show)

data CorroborationReadyResponse = CorroborationReadyResponse
  { crrTask :: !CorroborationTask
  , crrPromptHash :: !Text
  , crrResponseHash :: !Text
  , crrModel :: !Text
  , crrResponseBody :: !Text
  , crrApplyToken :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

currentCorroborationPolicyVersion :: Text
currentCorroborationPolicyVersion = "targeted-corroboration-v1"

stateText :: CorroborationTaskState -> Text
stateText CtsPending = "pending"
stateText CtsLeased = "leased"
stateText CtsResponseReady = "response_ready"
stateText CtsSucceeded = "succeeded"
stateText CtsRejected = "rejected"
stateText CtsConflicted = "conflicted"
stateText CtsFailed = "failed"

stateFromText :: Text -> Maybe CorroborationTaskState
stateFromText "pending" = Just CtsPending
stateFromText "leased" = Just CtsLeased
stateFromText "response_ready" = Just CtsResponseReady
stateFromText "succeeded" = Just CtsSucceeded
stateFromText "rejected" = Just CtsRejected
stateFromText "conflicted" = Just CtsConflicted
stateFromText "failed" = Just CtsFailed
stateFromText _ = Nothing

ensureCorroborationTaskSchema :: QxFx0DB -> IO ()
ensureCorroborationTaskSchema db = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    table <- NSQL.execSql conn
      "CREATE TABLE IF NOT EXISTS learning_corroboration_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, topic TEXT NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, relation_type TEXT NOT NULL, namespace TEXT NOT NULL, session_id TEXT, owner TEXT NOT NULL DEFAULT 'global', source_request_id TEXT NOT NULL, source_response_hash TEXT NOT NULL, competitive_audit TEXT NOT NULL, priority REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 3, available_at INTEGER NOT NULL, lease_until INTEGER, lease_token TEXT, confirmation_request_id TEXT UNIQUE, prompt_hash TEXT, response_hash TEXT, model TEXT, result_kind TEXT, last_error TEXT, policy TEXT NOT NULL DEFAULT 'targeted-corroboration-v1', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    either throwCorroborationError pure table
    ensurePolicyColumn conn
    ensureColumn conn "session_id" "TEXT"
    ensureColumn conn "owner" "TEXT"
    migrated <- NSQL.execSql conn
      "UPDATE learning_corroboration_tasks SET namespace='global', session_id=NULL, owner='legacy_global' WHERE owner IS NULL OR owner=''"
    either throwCorroborationError pure migrated
    migrateLegacyShapeConstraint conn
    proofTable <- NSQL.execSql conn
      "CREATE TABLE IF NOT EXISTS learning_apply_proofs (source_kind TEXT NOT NULL, request_id TEXT NOT NULL, policy TEXT NOT NULL, dispatch_token TEXT NOT NULL, applied_at INTEGER NOT NULL, PRIMARY KEY(source_kind, request_id))"
    either throwCorroborationError pure proofTable
    retireSupersededTasks conn
    rejectDuplicates conn
    index <- NSQL.execSql conn
      "CREATE INDEX IF NOT EXISTS idx_corroboration_tasks_dispatch ON learning_corroboration_tasks(state, available_at, priority DESC)"
    either throwCorroborationError pure index
    droppedShape <- NSQL.execSql conn "DROP INDEX IF EXISTS uq_corroboration_shape"
    either throwCorroborationError pure droppedShape
    uniqueShape <- NSQL.execSql conn
      "CREATE UNIQUE INDEX IF NOT EXISTS uq_corroboration_shape ON learning_corroboration_tasks(edge_from, edge_to, relation_type, namespace, owner)"
    either throwCorroborationError pure uniqueShape
    uniqueRequest <- NSQL.execSql conn
      "CREATE UNIQUE INDEX IF NOT EXISTS uq_corroboration_confirmation_request ON learning_corroboration_tasks(confirmation_request_id) WHERE confirmation_request_id IS NOT NULL"
    either throwCorroborationError pure uniqueRequest
  either throwCorroborationError pure result

rejectDuplicates :: NSQL.Database -> IO ()
rejectDuplicates conn = do
  shape <- hasRows
    "SELECT 1 FROM learning_corroboration_tasks GROUP BY edge_from, edge_to, relation_type, namespace, owner HAVING COUNT(*)>1 LIMIT 1"
  request <- hasRows
    "SELECT 1 FROM learning_corroboration_tasks WHERE confirmation_request_id IS NOT NULL GROUP BY confirmation_request_id HAVING COUNT(*)>1 LIMIT 1"
  when shape (throwCorroborationError "duplicate corroboration shapes require explicit reconciliation before schema migration")
  when request (throwCorroborationError "duplicate corroboration request ids require explicit reconciliation before schema migration")
  where
    hasRows sql = do
      prepared <- NSQL.prepare conn sql
      case prepared of
        Left err -> throwCorroborationError err
        Right stmt -> do
          found <- NSQL.stepRow stmt
          NSQL.finalize stmt
          pure found

enqueueCorroborationTaskOnConnection :: NSQL.Database -> CorroborationTaskSeed -> IO ()
enqueueCorroborationTaskOnConnection conn seed = do
  now <- getCurrentTime
  stmt <- prepareTx conn "corroboration_task_insert"
    "INSERT OR IGNORE INTO learning_corroboration_tasks (topic, edge_from, edge_to, relation_type, namespace, session_id, owner, source_request_id, source_response_hash, competitive_audit, priority, state, attempts, max_attempts, available_at, policy, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, 3, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 (ctsTopic seed)
  bindTextOrFail stmt 2 (ctsEdgeFrom seed)
  bindTextOrFail stmt 3 (ctsEdgeTo seed)
  bindTextOrFail stmt 4 (ctsRelationType seed)
  bindTextOrFail stmt 5 (ctsNamespace seed)
  bindMaybeText stmt 6 (ctsSessionId seed)
  bindTextOrFail stmt 7 (ctsOwner seed)
  bindTextOrFail stmt 8 (ctsSourceRequestId seed)
  bindTextOrFail stmt 9 (ctsSourceResponseHash seed)
  bindTextOrFail stmt 10 (ctsAudit seed)
  bindDoubleOrFail stmt 11 (ctsPriority seed)
  bindInt64OrFail stmt 12 (utcMicros now)
  bindTextOrFail stmt 13 currentCorroborationPolicyVersion
  bindInt64OrFail stmt 14 (utcMicros now)
  bindInt64OrFail stmt 15 (utcMicros now)
  stepOrFail stmt

-- | Claim no work until three independently useful hypotheses are pending.
-- The lease and threshold test share one immediate transaction.
claimCorroborationBatch :: QxFx0DB -> Int -> Int -> IO [CorroborationTask]
claimCorroborationBatch db = claimCorroborationBatchForSession db Nothing

claimCorroborationBatchForSession :: QxFx0DB -> Maybe Text -> Int -> Int -> IO [CorroborationTask]
claimCorroborationBatchForSession db sessionId minimumPending batchSize = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    retireSupersededTasks conn
    failExhaustedLeases conn now
    count <- pendingCount conn sessionId now
    if count < max 1 minimumPending
      then pure []
      else do
        tasks <- selectPending conn sessionId now (max 1 batchSize)
        forM tasks (leaseTask conn now)
  either throwCorroborationError pure result

-- | Restart recovery input. These responses are already durable and must be
-- sent only through governed application, never re-queried from the provider.
loadCorroborationResponseReady :: QxFx0DB -> Int -> IO [CorroborationReadyResponse]
loadCorroborationResponseReady db = loadCorroborationResponseReadyForSession db Nothing

loadCorroborationResponseReadyForSession :: QxFx0DB -> Maybe Text -> Int -> IO [CorroborationReadyResponse]
loadCorroborationResponseReadyForSession db sessionId limit = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    retireSupersededTasks conn
    prepared <- NSQL.prepare conn
      ("SELECT t.id, t.topic, t.edge_from, t.edge_to, t.relation_type, t.namespace, t.session_id, t.owner, t.source_request_id, t.source_response_hash, t.priority, t.state, t.attempts, t.max_attempts, t.confirmation_request_id, t.prompt_hash, t.response_hash, t.model, r.response_body FROM learning_corroboration_tasks t JOIN learning_responses r ON r.request_id=t.confirmation_request_id WHERE t.policy=? AND t.state='response_ready' AND (t.lease_until IS NULL OR t.lease_until <= ?)" <> scopeSql sessionId <> " ORDER BY t.updated_at ASC LIMIT ?")
    case prepared of
      Left err -> throwCorroborationError err
      Right stmt -> do
        _ <- NSQL.bindText stmt 1 currentCorroborationPolicyVersion
        _ <- NSQL.bindInt64 stmt 2 (utcMicros now)
        bindScope stmt 3 sessionId
        _ <- NSQL.bindInt64 stmt (if maybe False (const True) sessionId then 5 else 3) (fromIntegral (max 1 limit))
        ready <- collectReady stmt []
        forM ready $ \item -> do
          token <- leaseReadyResponse conn now (ctId (crrTask item))
          pure item { crrApplyToken = Just token }
  either throwCorroborationError pure result

-- | Release exact response-ready apply leases without discarding the durable
-- provider response.
releaseCorroborationReadyResponses :: QxFx0DB -> [CorroborationReadyResponse] -> IO ()
releaseCorroborationReadyResponses _ [] = pure ()
releaseCorroborationReadyResponses db ready = mask_ $ do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    forM_ ready $ \item -> case crrApplyToken item of
      Nothing -> pure ()
      Just token -> do
        stmt <- prepareTx conn "corroboration_ready_apply_release"
          "UPDATE learning_corroboration_tasks SET lease_until=NULL, lease_token=NULL, updated_at=? WHERE id=? AND policy=? AND state='response_ready' AND lease_token=?"
        bindInt64OrFail stmt 1 (utcMicros now)
        bindInt64OrFail stmt 2 (ctId (crrTask item))
        bindTextOrFail stmt 3 currentCorroborationPolicyVersion
        bindTextOrFail stmt 4 token
        stepOrFail stmt
  either throwCorroborationError pure result

releaseCorroborationApplyProofs :: QxFx0DB -> [(Int64, Text)] -> IO ()
releaseCorroborationApplyProofs _ [] = pure ()
releaseCorroborationApplyProofs db proofs = mask_ $ do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    forM_ proofs $ \(taskId, token) -> do
      stmt <- prepareTx conn "corroboration_apply_proof_release"
        "UPDATE learning_corroboration_tasks SET lease_until=NULL, lease_token=NULL, updated_at=? WHERE id=? AND policy=? AND state='response_ready' AND lease_token=?"
      bindInt64OrFail stmt 1 (utcMicros now)
      bindInt64OrFail stmt 2 taskId
      bindTextOrFail stmt 3 currentCorroborationPolicyVersion
      bindTextOrFail stmt 4 token
      stepOrFail stmt
  either throwCorroborationError pure result

-- | The provider response becomes durable before any graph application. A
-- crash can therefore resume only the governed application step.
recordCorroborationResponseReady
  :: QxFx0DB -> Int64 -> Text -> Text -> Text -> Text -> Text -> IO ()
recordCorroborationResponseReady db taskId requestId promptHash responseHash model responseBody = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    recordLearningResponseOnConnection conn requestId promptHash responseHash responseBody
    now <- getCurrentTime
    stmt <- prepareTx conn "corroboration_response_ready_with_body"
      "UPDATE learning_corroboration_tasks SET state='response_ready', confirmation_request_id=?, prompt_hash=?, response_hash=?, model=?, lease_until=NULL, lease_token=NULL, updated_at=? WHERE id=? AND policy=? AND state='leased' AND confirmation_request_id=? AND lease_token=?"
    bindTextOrFail stmt 1 requestId
    bindTextOrFail stmt 2 promptHash
    bindTextOrFail stmt 3 responseHash
    bindTextOrFail stmt 4 model
    bindInt64OrFail stmt 5 (utcMicros now)
    bindInt64OrFail stmt 6 taskId
    bindTextOrFail stmt 7 currentCorroborationPolicyVersion
    bindTextOrFail stmt 8 requestId
    bindTextOrFail stmt 9 requestId
    stepOrFail stmt
    changed <- readChanges conn
    if changed == 1
      then pure ()
      else throwCorroborationError "corroboration response task is not leased"
  either throwCorroborationError pure result

-- | Undo an undispatched lease when the whole confirmation batch cannot pass
-- the local quota gate. No provider request has occurred, so attempts are not
-- consumed.
releaseCorroborationBatch :: QxFx0DB -> [CorroborationTask] -> IO ()
releaseCorroborationBatch _ [] = pure ()
releaseCorroborationBatch db tasks = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    forM_ tasks $ \task -> do
      requestId <- maybe (throwCorroborationError "corroboration lease is missing its request token") pure
        (ctConfirmationRequestId task)
      stmt <- prepareTx conn "corroboration_task_release"
        "UPDATE learning_corroboration_tasks SET state='pending', attempts=MAX(0, attempts-1), available_at=?, lease_until=NULL, lease_token=NULL, confirmation_request_id=NULL, updated_at=? WHERE id=? AND policy=? AND state='leased' AND confirmation_request_id=? AND lease_token=?"
      bindInt64OrFail stmt 1 (utcMicros now)
      bindInt64OrFail stmt 2 (utcMicros now)
      bindInt64OrFail stmt 3 (ctId task)
      bindTextOrFail stmt 4 currentCorroborationPolicyVersion
      bindTextOrFail stmt 5 requestId
      bindTextOrFail stmt 6 requestId
      stepOrFail stmt
  either throwCorroborationError pure result

leaseReadyResponse :: NSQL.Database -> UTCTime -> Int64 -> IO Text
leaseReadyResponse conn now taskId = do
  let leaseUntil = addUTCTime 120 now
      token = "corroboration-apply:" <> T.pack (show taskId) <> ":" <> T.pack (show (utcMicros now))
  stmt <- prepareTx conn "corroboration_ready_apply_lease"
    "UPDATE learning_corroboration_tasks SET lease_until=?, lease_token=?, updated_at=? WHERE id=? AND policy=? AND state='response_ready' AND (lease_until IS NULL OR lease_until <= ?)"
  bindInt64OrFail stmt 1 (utcMicros leaseUntil)
  bindTextOrFail stmt 2 token
  bindInt64OrFail stmt 3 (utcMicros now)
  bindInt64OrFail stmt 4 taskId
  bindTextOrFail stmt 5 currentCorroborationPolicyVersion
  bindInt64OrFail stmt 6 (utcMicros now)
  stepOrFail stmt
  changed <- readChanges conn
  unless (changed == 1) (throwCorroborationError "corroboration ready apply lease was lost")
  pure token

markCorroborationTaskTerminalOnConnection :: NSQL.Database -> Int64 -> Text -> Text -> CorroborationTaskState -> Text -> IO ()
markCorroborationTaskTerminalOnConnection conn taskId requestId leaseToken state resultKind = do
  now <- getCurrentTime
  stmt <- prepareTx conn "corroboration_task_terminal"
    "UPDATE learning_corroboration_tasks SET state=?, result_kind=?, lease_until=NULL, lease_token=NULL, updated_at=? WHERE id=? AND policy=? AND confirmation_request_id=? AND lease_token=? AND state='response_ready' AND lease_until IS NOT NULL AND lease_until>?"
  bindTextOrFail stmt 1 (stateText state)
  bindTextOrFail stmt 2 resultKind
  bindInt64OrFail stmt 3 (utcMicros now)
  bindInt64OrFail stmt 4 taskId
  bindTextOrFail stmt 5 currentCorroborationPolicyVersion
  bindTextOrFail stmt 6 requestId
  bindTextOrFail stmt 7 leaseToken
  bindInt64OrFail stmt 8 (utcMicros now)
  stepOrFail stmt
  changed <- readChanges conn
  unless (changed == 1) (throwCorroborationError "corroboration terminal transition rejected stale request")
  proof <- prepareTx conn "corroboration_apply_proof"
    "INSERT INTO learning_apply_proofs(source_kind, request_id, policy, dispatch_token, applied_at) VALUES('corroboration', ?, ?, ?, ?) ON CONFLICT(source_kind, request_id) DO UPDATE SET policy=excluded.policy, dispatch_token=excluded.dispatch_token, applied_at=excluded.applied_at"
  bindTextOrFail proof 1 requestId
  bindTextOrFail proof 2 currentCorroborationPolicyVersion
  bindTextOrFail proof 3 leaseToken
  bindInt64OrFail proof 4 (utcMicros now)
  stepOrFail proof

authorizeCorroborationApplyOnConnection :: NSQL.Database -> [(Int64, Text, Text)] -> IO ()
authorizeCorroborationApplyOnConnection conn proofs = do
  now <- getCurrentTime
  forM_ proofs $ \(taskId, requestId, leaseToken) -> do
    prepared <- NSQL.prepare conn
      "SELECT 1 FROM learning_corroboration_tasks WHERE id=? AND policy=? AND confirmation_request_id=? AND lease_token=? AND state='response_ready' AND lease_until IS NOT NULL AND lease_until>? LIMIT 1"
    case prepared of
      Left err -> throwCorroborationError err
      Right stmt -> do
        _ <- NSQL.bindInt64 stmt 1 taskId
        _ <- NSQL.bindText stmt 2 currentCorroborationPolicyVersion
        _ <- NSQL.bindText stmt 3 requestId
        _ <- NSQL.bindText stmt 4 leaseToken
        _ <- NSQL.bindInt64 stmt 5 (utcMicros now)
        authorized <- NSQL.stepRow stmt
        NSQL.finalize stmt
        unless authorized (throwCorroborationError "corroboration apply is not authorized by a current-policy dispatch")

markCorroborationTaskTerminal :: QxFx0DB -> CorroborationTask -> Text -> CorroborationTaskState -> Text -> IO ()
markCorroborationTaskTerminal db task leaseToken state resultKind = do
  requestId <- maybe (throwCorroborationError "corroboration task is missing its request token") pure
    (ctConfirmationRequestId task)
  let expectedState = case ctState task of
        CtsResponseReady -> "response_ready"
        _ -> "leased"
  result <- withDB (qdbPath db) $ \conn -> do
    now <- getCurrentTime
    stmt <- prepareTx conn "corroboration_task_direct_terminal"
      "UPDATE learning_corroboration_tasks SET state=?, result_kind=?, lease_until=NULL, lease_token=NULL, updated_at=? WHERE id=? AND policy=? AND confirmation_request_id=? AND lease_token=? AND state=?"
    bindTextOrFail stmt 1 (stateText state)
    bindTextOrFail stmt 2 resultKind
    bindInt64OrFail stmt 3 (utcMicros now)
    bindInt64OrFail stmt 4 (ctId task)
    bindTextOrFail stmt 5 currentCorroborationPolicyVersion
    bindTextOrFail stmt 6 requestId
    bindTextOrFail stmt 7 leaseToken
    bindTextOrFail stmt 8 expectedState
    stepOrFail stmt
    changed <- readChanges conn
    unless (changed == 1) (throwCorroborationError "corroboration direct terminal transition rejected stale lease")
  either throwCorroborationError pure result

-- | Retry transient provider failures under the current fenced lease. The
-- canonical shape remains unique; only a terminal failure exhausts it.
markCorroborationTaskFailed :: QxFx0DB -> CorroborationTask -> Bool -> Int -> Text -> IO ()
markCorroborationTaskFailed db task retryable backoffSeconds reason = do
  requestId <- maybe (throwCorroborationError "corroboration task is missing its request token") pure
    (ctConfirmationRequestId task)
  now <- getCurrentTime
  let available = addUTCTime (fromIntegral (max 1 backoffSeconds)) now
      retryFlag = if retryable then (1 :: Int64) else 0
  result <- mask_ $ withDB (qdbPath db) $ \conn -> do
    stmt <- prepareTx conn "corroboration_task_failure"
      "UPDATE learning_corroboration_tasks SET state=CASE WHEN ?=1 AND attempts < max_attempts THEN 'pending' ELSE 'failed' END, available_at=?, lease_until=NULL, lease_token=NULL, confirmation_request_id=CASE WHEN ?=1 AND attempts < max_attempts THEN NULL ELSE confirmation_request_id END, result_kind=CASE WHEN ?=1 AND attempts < max_attempts THEN NULL ELSE 'provider_failure' END, last_error=?, updated_at=? WHERE id=? AND policy=? AND state='leased' AND confirmation_request_id=? AND lease_token=?"
    bindInt64OrFail stmt 1 retryFlag
    bindInt64OrFail stmt 2 (utcMicros available)
    bindInt64OrFail stmt 3 retryFlag
    bindInt64OrFail stmt 4 retryFlag
    bindTextOrFail stmt 5 reason
    bindInt64OrFail stmt 6 (utcMicros now)
    bindInt64OrFail stmt 7 (ctId task)
    bindTextOrFail stmt 8 currentCorroborationPolicyVersion
    bindTextOrFail stmt 9 requestId
    bindTextOrFail stmt 10 requestId
    stepOrFail stmt
    changed <- readChanges conn
    unless (changed == 1) (throwCorroborationError "corroboration failure rejected stale lease")
  either throwCorroborationError pure result

pendingCount :: NSQL.Database -> Maybe Text -> UTCTime -> IO Int
pendingCount conn sessionId now = do
  prepared <- NSQL.prepare conn
    ("SELECT COUNT(*) FROM learning_corroboration_tasks WHERE policy=? AND attempts < max_attempts AND ((state='pending' AND available_at <= ?) OR (state='leased' AND lease_until IS NOT NULL AND lease_until <= ?))" <> scopeSql sessionId)
  case prepared of
    Left err -> throwCorroborationError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 currentCorroborationPolicyVersion
      _ <- NSQL.bindInt64 stmt 2 (utcMicros now)
      _ <- NSQL.bindInt64 stmt 3 (utcMicros now)
      bindScope stmt 4 sessionId
      hasRow <- NSQL.stepRow stmt
      count <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure count

selectPending :: NSQL.Database -> Maybe Text -> UTCTime -> Int -> IO [CorroborationTask]
selectPending conn sessionId now limit = do
  prepared <- NSQL.prepare conn
    ("SELECT id, topic, edge_from, edge_to, relation_type, namespace, session_id, owner, source_request_id, source_response_hash, priority, state, attempts, max_attempts, confirmation_request_id FROM learning_corroboration_tasks WHERE policy=? AND attempts < max_attempts AND ((state='pending' AND available_at <= ?) OR (state='leased' AND lease_until IS NOT NULL AND lease_until <= ?))" <> scopeSql sessionId <> " ORDER BY priority DESC, created_at ASC LIMIT ?")
  case prepared of
    Left err -> throwCorroborationError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 currentCorroborationPolicyVersion
      _ <- NSQL.bindInt64 stmt 2 (utcMicros now)
      _ <- NSQL.bindInt64 stmt 3 (utcMicros now)
      bindScope stmt 4 sessionId
      _ <- NSQL.bindInt64 stmt (if maybe False (const True) sessionId then 6 else 4) (fromIntegral limit)
      collectTasks stmt []

scopeSql :: Maybe Text -> Text
scopeSql Nothing = ""
scopeSql (Just _) = " AND (namespace='global' OR (namespace='session_local' AND session_id=? AND owner=?))"

bindScope :: NSQL.Statement -> Int -> Maybe Text -> IO ()
bindScope _ _ Nothing = pure ()
bindScope stmt start (Just sessionId) = do
  _ <- NSQL.bindText stmt (fromIntegral start) sessionId
  _ <- NSQL.bindText stmt (fromIntegral (start + 1)) sessionId
  pure ()

leaseTask :: NSQL.Database -> UTCTime -> CorroborationTask -> IO CorroborationTask
leaseTask conn now task = do
  let leaseUntil = addUTCTime 120 now
      requestId = "corroborate-" <> T.pack (show (ctId task)) <> "-" <> T.pack (show (utcMicros now))
  stmt <- prepareTx conn "corroboration_task_lease"
    "UPDATE learning_corroboration_tasks SET state='leased', attempts=attempts+1, lease_until=?, lease_token=?, confirmation_request_id=?, updated_at=? WHERE id=? AND policy=? AND attempts < max_attempts AND (state='pending' OR (state='leased' AND lease_until IS NOT NULL AND lease_until <= ?))"
  bindInt64OrFail stmt 1 (utcMicros leaseUntil)
  bindTextOrFail stmt 2 requestId
  bindTextOrFail stmt 3 requestId
  bindInt64OrFail stmt 4 (utcMicros now)
  bindInt64OrFail stmt 5 (ctId task)
  bindTextOrFail stmt 6 currentCorroborationPolicyVersion
  bindInt64OrFail stmt 7 (utcMicros now)
  stepOrFail stmt
  pure task { ctState = CtsLeased, ctAttempts = ctAttempts task + 1, ctConfirmationRequestId = Just requestId }

collectTasks :: NSQL.Statement -> [CorroborationTask] -> IO [CorroborationTask]
collectTasks stmt acc = do
  hasRow <- NSQL.stepRow stmt
  if not hasRow
    then NSQL.finalize stmt >> pure (reverse acc)
    else do
      taskId <- NSQL.columnInt64 stmt 0
      topic <- NSQL.columnText stmt 1
      edgeFrom <- NSQL.columnText stmt 2
      edgeTo <- NSQL.columnText stmt 3
      relation <- NSQL.columnText stmt 4
      namespace <- NSQL.columnText stmt 5
      sessionId <- maybeText stmt 6
      owner <- NSQL.columnText stmt 7
      sourceRequest <- NSQL.columnText stmt 8
      sourceResponse <- NSQL.columnText stmt 9
      priority <- NSQL.columnDouble stmt 10
      stateRaw <- NSQL.columnText stmt 11
      attempts <- NSQL.columnInt stmt 12
      maxAttempts <- NSQL.columnInt stmt 13
      confirmation <- maybeText stmt 14
      case stateFromText stateRaw of
        Nothing -> collectTasks stmt acc
        Just state -> collectTasks stmt
          (CorroborationTask taskId topic edgeFrom edgeTo relation namespace sessionId owner sourceRequest sourceResponse priority state attempts maxAttempts confirmation : acc)

collectReady :: NSQL.Statement -> [CorroborationReadyResponse] -> IO [CorroborationReadyResponse]
collectReady stmt acc = do
  hasRow <- NSQL.stepRow stmt
  if not hasRow
    then NSQL.finalize stmt >> pure (reverse acc)
    else do
      taskId <- NSQL.columnInt64 stmt 0
      topic <- NSQL.columnText stmt 1
      edgeFrom <- NSQL.columnText stmt 2
      edgeTo <- NSQL.columnText stmt 3
      relation <- NSQL.columnText stmt 4
      namespace <- NSQL.columnText stmt 5
      sessionId <- maybeText stmt 6
      owner <- NSQL.columnText stmt 7
      sourceRequest <- NSQL.columnText stmt 8
      sourceResponse <- NSQL.columnText stmt 9
      priority <- NSQL.columnDouble stmt 10
      stateRaw <- NSQL.columnText stmt 11
      attempts <- NSQL.columnInt stmt 12
      maxAttempts <- NSQL.columnInt stmt 13
      confirmation <- maybeText stmt 14
      promptHash <- NSQL.columnText stmt 15
      responseHash <- NSQL.columnText stmt 16
      model <- NSQL.columnText stmt 17
      responseBody <- NSQL.columnTextLenient stmt 18
      case stateFromText stateRaw of
        Just CtsResponseReady ->
          let task = CorroborationTask taskId topic edgeFrom edgeTo relation namespace sessionId owner sourceRequest sourceResponse priority CtsResponseReady attempts maxAttempts confirmation
           in collectReady stmt (CorroborationReadyResponse task promptHash responseHash model responseBody Nothing : acc)
        _ -> collectReady stmt acc

failExhaustedLeases :: NSQL.Database -> UTCTime -> IO ()
failExhaustedLeases conn now = do
  stmt <- prepareTx conn "corroboration_expired_lease_failure"
    "UPDATE learning_corroboration_tasks SET state='failed', result_kind='lease_attempts_exhausted', lease_until=NULL, lease_token=NULL, updated_at=? WHERE state='leased' AND lease_until IS NOT NULL AND lease_until <= ? AND attempts >= max_attempts"
  bindInt64OrFail stmt 1 (utcMicros now)
  bindInt64OrFail stmt 2 (utcMicros now)
  stepOrFail stmt

ensurePolicyColumn :: NSQL.Database -> IO ()
ensurePolicyColumn conn = do
  prepared <- NSQL.prepare conn
    "SELECT 1 FROM pragma_table_info('learning_corroboration_tasks') WHERE name='policy' LIMIT 1"
  exists <- case prepared of
    Left err -> throwCorroborationError err
    Right stmt -> do
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found
  unless exists $ do
    added <- NSQL.execSql conn
      "ALTER TABLE learning_corroboration_tasks ADD COLUMN policy TEXT NOT NULL DEFAULT 'targeted-corroboration-v0'"
    either throwCorroborationError pure added

ensureColumn :: NSQL.Database -> Text -> Text -> IO ()
ensureColumn conn name declaration = do
  prepared <- NSQL.prepare conn
    "SELECT 1 FROM pragma_table_info('learning_corroboration_tasks') WHERE name=? LIMIT 1"
  exists <- case prepared of
    Left err -> throwCorroborationError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 name
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found
  unless exists $ do
    added <- NSQL.execSql conn
      ("ALTER TABLE learning_corroboration_tasks ADD COLUMN " <> name <> " " <> declaration)
    either throwCorroborationError pure added

migrateLegacyShapeConstraint :: NSQL.Database -> IO ()
migrateLegacyShapeConstraint conn = do
  prepared <- NSQL.prepare conn
    "SELECT lower(replace(sql, ' ', '')) FROM sqlite_master WHERE type='table' AND name='learning_corroboration_tasks'"
  schema <- case prepared of
    Left err -> throwCorroborationError err
    Right stmt -> do
      found <- NSQL.stepRow stmt
      value <- if found then NSQL.columnText stmt 0 else pure ""
      NSQL.finalize stmt
      pure value
  when ("unique(edge_from,edge_to,relation_type,namespace)" `T.isInfixOf` schema) $ do
    execOrFail conn "ALTER TABLE learning_corroboration_tasks RENAME TO learning_corroboration_tasks_scope_legacy"
    execOrFail conn
      "CREATE TABLE learning_corroboration_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, topic TEXT NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, relation_type TEXT NOT NULL, namespace TEXT NOT NULL, session_id TEXT, owner TEXT NOT NULL DEFAULT 'global', source_request_id TEXT NOT NULL, source_response_hash TEXT NOT NULL, competitive_audit TEXT NOT NULL, priority REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 3, available_at INTEGER NOT NULL, lease_until INTEGER, lease_token TEXT, confirmation_request_id TEXT UNIQUE, prompt_hash TEXT, response_hash TEXT, model TEXT, result_kind TEXT, last_error TEXT, policy TEXT NOT NULL DEFAULT 'targeted-corroboration-v1', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    execOrFail conn
      "INSERT INTO learning_corroboration_tasks(id, topic, edge_from, edge_to, relation_type, namespace, session_id, owner, source_request_id, source_response_hash, competitive_audit, priority, state, attempts, max_attempts, available_at, lease_until, lease_token, confirmation_request_id, prompt_hash, response_hash, model, result_kind, last_error, policy, created_at, updated_at) SELECT id, topic, edge_from, edge_to, relation_type, namespace, session_id, owner, source_request_id, source_response_hash, competitive_audit, priority, state, attempts, max_attempts, available_at, lease_until, lease_token, confirmation_request_id, prompt_hash, response_hash, model, result_kind, last_error, policy, created_at, updated_at FROM learning_corroboration_tasks_scope_legacy"
    execOrFail conn "DROP TABLE learning_corroboration_tasks_scope_legacy"

execOrFail :: NSQL.Database -> Text -> IO ()
execOrFail conn sql = NSQL.execSql conn sql >>= either throwCorroborationError pure

bindMaybeText :: TxStmt -> Int -> Maybe Text -> IO ()
bindMaybeText stmt ix = maybe
  (bindNullOrFail stmt (fromIntegral ix))
  (bindTextOrFail stmt (fromIntegral ix))

maybeText :: NSQL.Statement -> Int -> IO (Maybe Text)
maybeText stmt ix = ifM (NSQL.columnIsNull stmt (fromIntegral ix))
  (pure Nothing) (Just <$> NSQL.columnText stmt (fromIntegral ix))

retireSupersededTasks :: NSQL.Database -> IO ()
retireSupersededTasks conn = do
  now <- getCurrentTime
  stmt <- prepareTx conn "corroboration_retire_superseded_policy"
    "UPDATE learning_corroboration_tasks SET state='failed', result_kind='superseded_corroboration_policy', last_error='superseded_corroboration_policy', lease_until=NULL, lease_token=NULL, updated_at=? WHERE policy<>? AND state IN ('pending','leased','response_ready')"
  bindInt64OrFail stmt 1 (utcMicros now)
  bindTextOrFail stmt 2 currentCorroborationPolicyVersion
  stepOrFail stmt

readChanges :: NSQL.Database -> IO Int
readChanges conn = do
  prepared <- NSQL.prepare conn "SELECT changes()"
  case prepared of
    Left err -> throwCorroborationError err
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      changed <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure changed

withImmediateTransaction :: NSQL.Database -> IO a -> IO a
withImmediateTransaction conn action = mask_ $ do
  begun <- NSQL.execSql conn "BEGIN IMMEDIATE;"
  either throwCorroborationError pure begun
  value <- action `onException` rollbackBestEffort conn
  committed <- NSQL.execSql conn "COMMIT;"
  case committed of
    Right () -> pure value
    Left err -> rollbackBestEffort conn >> throwCorroborationError err

rollbackBestEffort :: NSQL.Database -> IO ()
rollbackBestEffort conn = do
  _ <- NSQL.execSql conn "ROLLBACK;"
  pure ()

throwCorroborationError :: Text -> IO a
throwCorroborationError detail =
  throwQxFx0 (mkSQLiteError
    "learning_corroboration_queue"
    "CORROBORATION_QUEUE_SQLITE_ERROR"
    (M.singleton "detail" detail))

ifM :: Monad m => m Bool -> m a -> m a -> m a
ifM action yes no = action >>= \value -> if value then yes else no

utcMicros :: UTCTime -> Int64
utcMicros = round . (* 1000000) . realToFrac . utcTimeToPOSIXSeconds

microsToUtc :: Int64 -> UTCTime
microsToUtc = posixSecondsToUTCTime . (/ 1000000) . fromIntegral
