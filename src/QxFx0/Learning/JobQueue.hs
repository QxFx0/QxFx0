{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Durable state, fencing, replay handoff, and database-global quotas for
-- autonomous learning. Provider output is opaque here; its owner encodes and
-- validates the bounded payload before governed application.
module QxFx0.Learning.JobQueue
  ( LearningJobState(..)
  , LearningJob(..)
  , LearningJobClaim(..)
  , LearningReadyPayload(..)
  , LearningQuotaLimits(..)
  , learningJobStateText
  , currentLearningPolicyVersion
  , maxLearningReadyPayloadBytes
  , ensureLearningJobSchema
  , enqueueLearningJob
  , enqueueLearningJobForSession
  , loadRunnableLearningJobs
  , loadRunnableLearningJobsForSession
  , claimLearningJob
  , releaseLearningJobClaim
  , markLearningJobsApplied
  , markLearningJobsAppliedOnConnection
  , authorizeLearningJobsApplyOnConnection
  , markLearningJobClaimFailed
  , markLearningJobClaimFailedOnConnection
  , recordLearningJobResponseReady
  , claimLearningReadyPayloads
  , claimLearningReadyPayloadsForSession
  , releaseLearningReadyPayloads
  , rejectLearningReadyPayload
  , reserveLearningQuota
  , recordLearningTopicCooldown
  , recordLearningTopicCooldownOnConnection
  , advanceLearningTopicCursor
  , recordLearningResponse
  , recordLearningResponseOnConnection
  ) where

import Control.Exception (mask_, onException)
import Control.Monad (forM, forM_, unless, when)
import qualified Data.ByteString as BS
import Data.Int (Int64)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime, addUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)

import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement
  ( bindDoubleOrFail
  , bindInt64OrFail
  , bindTextOrFail
  , prepareTx
  , stepOrFail
  )
import QxFx0.Learning.Events (LearningEvent, insertLearningEventsOnConnection)
import QxFx0.ExceptionPolicy (mkSQLiteError, throwQxFx0)

data LearningJobState
  = JobPending
  | JobLeased
  | JobRetryScheduled
  | JobResponseReady
  | JobSucceeded
  | JobFailed
  deriving stock (Eq, Ord, Show, Read)

data LearningJob = LearningJob
  { ljRequestId   :: !Text
  , ljTopic       :: !Text
  , ljPriority    :: !Double
  , ljState       :: !LearningJobState
  , ljAttempts    :: !Int
  , ljMaxAttempts :: !Int
  , ljAvailableAt :: !UTCTime
  , ljLeaseUntil  :: !(Maybe UTCTime)
  , ljLastError   :: !(Maybe Text)
  , ljPolicy      :: !Text
  }
  deriving stock (Eq, Show)

data LearningJobClaim = LearningJobClaim
  { ljcJob :: !LearningJob
  , ljcLeaseToken :: !Text
  }
  deriving stock (Eq, Show)

data LearningReadyPayload = LearningReadyPayload
  { lrpRequestId :: !Text
  , lrpTopic :: !Text
  , lrpPayload :: !Text
  , lrpApplyToken :: !Text
  }
  deriving stock (Eq, Show)

data LearningQuotaLimits = LearningQuotaLimits
  { lqlRequestsPerMinute :: !Int
  , lqlRequestsPerHour :: !Int
  , lqlRequestsPerDay :: !Int
  , lqlTokensPerMinute :: !Int
  , lqlTokensPerHour :: !Int
  , lqlTokensPerDay :: !Int
  }
  deriving stock (Eq, Show)

learningJobStateText :: LearningJobState -> Text
learningJobStateText JobPending = "pending"
learningJobStateText JobLeased = "leased"
learningJobStateText JobRetryScheduled = "retry_scheduled"
learningJobStateText JobResponseReady = "response_ready"
learningJobStateText JobSucceeded = "succeeded"
learningJobStateText JobFailed = "failed"

stateFromText :: Text -> Maybe LearningJobState
stateFromText "pending" = Just JobPending
stateFromText "leased" = Just JobLeased
stateFromText "retry_scheduled" = Just JobRetryScheduled
stateFromText "response_ready" = Just JobResponseReady
stateFromText "succeeded" = Just JobSucceeded
stateFromText "failed" = Just JobFailed
stateFromText _ = Nothing

currentLearningPolicyVersion :: Text
currentLearningPolicyVersion = "autonomous-learning-v4-session-owned"

learningSchemaVersion :: Int
learningSchemaVersion = 6

maxLearningReadyPayloadBytes :: Int
maxLearningReadyPayloadBytes = 262144

-- | Create fresh learning tables and add every column introduced after the
-- original autonomous schema. Existing data is never copied or dropped.
ensureLearningJobSchema :: QxFx0DB -> IO ()
ensureLearningJobSchema db = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    exec conn "CREATE TABLE IF NOT EXISTS learning_schema_versions (owner TEXT PRIMARY KEY, version INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    version <- readSchemaVersion conn
    when (version > learningSchemaVersion) $
      throwJobQueueError ("learning schema is newer than this runtime: " <> T.pack (show version))
    exec conn "CREATE TABLE IF NOT EXISTS learning_jobs (request_id TEXT PRIMARY KEY, topic TEXT NOT NULL, priority REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 3, available_at INTEGER NOT NULL, lease_until INTEGER, lease_token TEXT, lease_generation INTEGER NOT NULL DEFAULT 0, last_error TEXT, policy TEXT NOT NULL DEFAULT 'autonomous-learning-v1', active_key TEXT UNIQUE, session_id TEXT, owner TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    ensureColumn conn "learning_jobs" "lease_token" "TEXT"
    ensureColumn conn "learning_jobs" "lease_generation" "INTEGER NOT NULL DEFAULT 0"
    ensureColumn conn "learning_jobs" "session_id" "TEXT"
    ensureColumn conn "learning_jobs" "owner" "TEXT"
    exec conn "CREATE TABLE IF NOT EXISTS learning_topic_cooldowns (topic TEXT PRIMARY KEY, cooldown_until INTEGER NOT NULL, updated_at INTEGER NOT NULL, reason TEXT NOT NULL DEFAULT 'successful_apply', negative INTEGER NOT NULL DEFAULT 0 CHECK(negative IN (0,1)))"
    ensureColumn conn "learning_topic_cooldowns" "reason" "TEXT NOT NULL DEFAULT 'successful_apply'"
    ensureColumn conn "learning_topic_cooldowns" "negative" "INTEGER NOT NULL DEFAULT 0"
    exec conn "CREATE TABLE IF NOT EXISTS learning_scheduler_state (owner TEXT PRIMARY KEY, topic_cursor INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    exec conn "CREATE TABLE IF NOT EXISTS learning_responses (request_id TEXT PRIMARY KEY, prompt_hash TEXT NOT NULL, response_hash TEXT NOT NULL, response_body TEXT NOT NULL, created_at INTEGER NOT NULL)"
    exec conn "CREATE TABLE IF NOT EXISTS learning_ready_payloads (request_id TEXT PRIMARY KEY, payload_version INTEGER NOT NULL, payload TEXT NOT NULL, payload_bytes INTEGER NOT NULL, created_at INTEGER NOT NULL, FOREIGN KEY(request_id) REFERENCES learning_jobs(request_id))"
    exec conn "CREATE TABLE IF NOT EXISTS learning_apply_proofs (source_kind TEXT NOT NULL, request_id TEXT NOT NULL, policy TEXT NOT NULL, dispatch_token TEXT NOT NULL, applied_at INTEGER NOT NULL, PRIMARY KEY(source_kind, request_id))"
    exec conn "CREATE TABLE IF NOT EXISTS learning_quota_windows (window_name TEXT PRIMARY KEY, window_start INTEGER NOT NULL, requests INTEGER NOT NULL, tokens INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    -- Corroboration predates module-owned schema versions. Ensure its additive
    -- dispatch columns even when a legacy table already exists.
    exec conn "CREATE TABLE IF NOT EXISTS learning_corroboration_tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, topic TEXT NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, relation_type TEXT NOT NULL, namespace TEXT NOT NULL, session_id TEXT, owner TEXT, source_request_id TEXT NOT NULL, source_response_hash TEXT NOT NULL, competitive_audit TEXT NOT NULL, priority REAL NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, max_attempts INTEGER NOT NULL DEFAULT 3, available_at INTEGER NOT NULL, lease_until INTEGER, lease_token TEXT, confirmation_request_id TEXT UNIQUE, prompt_hash TEXT, response_hash TEXT, model TEXT, result_kind TEXT, last_error TEXT, policy TEXT NOT NULL DEFAULT 'targeted-corroboration-v1', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    mapM_ (\(name, declaration) -> ensureColumn conn "learning_corroboration_tasks" name declaration)
      [ ("max_attempts", "INTEGER NOT NULL DEFAULT 3")
      , ("available_at", "INTEGER NOT NULL DEFAULT 0")
      , ("lease_until", "INTEGER")
      , ("lease_token", "TEXT")
      , ("confirmation_request_id", "TEXT")
      , ("prompt_hash", "TEXT")
      , ("response_hash", "TEXT")
      , ("model", "TEXT")
      , ("result_kind", "TEXT")
      , ("last_error", "TEXT")
      , ("policy", "TEXT NOT NULL DEFAULT 'targeted-corroboration-v0'")
      , ("session_id", "TEXT")
      , ("owner", "TEXT")
      ]
    validateColumns conn "learning_jobs"
      ["request_id", "topic", "priority", "state", "attempts", "max_attempts", "available_at", "lease_until", "lease_token", "lease_generation", "last_error", "policy", "active_key", "session_id", "owner", "created_at", "updated_at"]
    validateColumns conn "learning_responses"
      ["request_id", "prompt_hash", "response_hash", "response_body", "created_at"]
    validateColumns conn "learning_corroboration_tasks"
      ["id", "topic", "edge_from", "edge_to", "relation_type", "namespace", "session_id", "owner", "source_request_id", "source_response_hash", "competitive_audit", "priority", "state", "attempts", "max_attempts", "available_at", "lease_until", "lease_token", "confirmation_request_id", "policy"]
    retireSupersededJobs conn
    exec conn "UPDATE learning_jobs SET state='failed', last_error='legacy_job_missing_session_owner', active_key=NULL, lease_until=NULL, lease_token=NULL WHERE (owner IS NULL OR owner='') AND state IN ('pending','leased','retry_scheduled','response_ready')"
    assertNoRows conn "duplicate corroboration shapes require explicit reconciliation before schema migration"
      "SELECT 1 FROM learning_corroboration_tasks GROUP BY edge_from, edge_to, relation_type, namespace, owner HAVING COUNT(*)>1 LIMIT 1"
    assertNoRows conn "duplicate corroboration request ids require explicit reconciliation before schema migration"
      "SELECT 1 FROM learning_corroboration_tasks WHERE confirmation_request_id IS NOT NULL GROUP BY confirmation_request_id HAVING COUNT(*)>1 LIMIT 1"
    exec conn "CREATE INDEX IF NOT EXISTS idx_learning_jobs_runnable ON learning_jobs(state, available_at, priority DESC)"
    exec conn "CREATE INDEX IF NOT EXISTS idx_learning_jobs_ready ON learning_jobs(state, updated_at)"
    exec conn "CREATE INDEX IF NOT EXISTS idx_corroboration_tasks_dispatch ON learning_corroboration_tasks(state, available_at, priority DESC)"
    exec conn "CREATE UNIQUE INDEX IF NOT EXISTS uq_corroboration_shape ON learning_corroboration_tasks(edge_from, edge_to, relation_type, namespace, owner)"
    exec conn "CREATE UNIQUE INDEX IF NOT EXISTS uq_corroboration_confirmation_request ON learning_corroboration_tasks(confirmation_request_id) WHERE confirmation_request_id IS NOT NULL"
    now <- getCurrentTime
    stmt <- prepareTx conn "learning_schema_version_upsert"
      "INSERT INTO learning_schema_versions(owner, version, updated_at) VALUES('job_queue', ?, ?) ON CONFLICT(owner) DO UPDATE SET version=excluded.version, updated_at=excluded.updated_at"
    bindInt64OrFail stmt 1 (fromIntegral learningSchemaVersion)
    bindInt64OrFail stmt 2 (utcMicros now)
    stepOrFail stmt
  either throwJobQueueError pure result

enqueueLearningJob :: QxFx0DB -> Text -> Text -> Double -> Int -> IO Bool
enqueueLearningJob db = enqueueLearningJobForSession db "autonomous-default"

enqueueLearningJobForSession :: QxFx0DB -> Text -> Text -> Text -> Double -> Int -> IO Bool
enqueueLearningJobForSession db sessionId requestId topic priority maxAttempts = do
  when (T.null (T.strip sessionId)) (throwJobQueueError "learning job requires a session owner")
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    stmt <- prepareTx conn "learning_job_insert"
      "INSERT OR IGNORE INTO learning_jobs (request_id, topic, priority, state, attempts, max_attempts, available_at, lease_until, lease_token, lease_generation, last_error, policy, active_key, session_id, owner, created_at, updated_at) SELECT ?, ?, ?, 'pending', 0, ?, ?, NULL, NULL, 0, NULL, ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM learning_topic_cooldowns WHERE topic = ? AND cooldown_until > ?)"
    bindTextOrFail stmt 1 requestId
    bindTextOrFail stmt 2 topic
    bindDoubleOrFail stmt 3 priority
    bindInt64OrFail stmt 4 (fromIntegral (max 1 maxAttempts))
    bindInt64OrFail stmt 5 (utcMicros now)
    bindTextOrFail stmt 6 currentLearningPolicyVersion
    bindTextOrFail stmt 7 (T.toLower (T.strip topic) <> ":" <> currentLearningPolicyVersion <> ":" <> sessionId)
    bindTextOrFail stmt 8 sessionId
    bindTextOrFail stmt 9 sessionId
    bindInt64OrFail stmt 10 (utcMicros now)
    bindInt64OrFail stmt 11 (utcMicros now)
    bindTextOrFail stmt 12 topic
    bindInt64OrFail stmt 13 (utcMicros now)
    stepOrFail stmt
    (> 0) <$> readChanges conn
  either throwJobQueueError pure result

loadRunnableLearningJobs :: QxFx0DB -> Int -> IO [LearningJob]
loadRunnableLearningJobs db = loadRunnableLearningJobsForSession db "autonomous-default"

loadRunnableLearningJobsForSession :: QxFx0DB -> Text -> Int -> IO [LearningJob]
loadRunnableLearningJobsForSession db sessionId limit = do
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> do
    failExhaustedLearningLeases conn now
    prepared <- NSQL.prepare conn
      "SELECT request_id, topic, priority, state, attempts, max_attempts, available_at, lease_until, last_error, policy FROM learning_jobs WHERE policy=? AND session_id=? AND owner=? AND attempts < max_attempts AND ((state IN ('pending','retry_scheduled') AND available_at <= ?) OR (state='leased' AND lease_until IS NOT NULL AND lease_until <= ?)) ORDER BY priority DESC, created_at ASC LIMIT ?"
    case prepared of
      Left err -> throwJobQueueError err
      Right stmt -> do
        bindRawText stmt 1 currentLearningPolicyVersion
        bindRawText stmt 2 sessionId
        bindRawText stmt 3 sessionId
        bindRawInt stmt 4 (utcMicros now)
        bindRawInt stmt 5 (utcMicros now)
        bindRawInt stmt 6 (fromIntegral (max 0 limit))
        collectJobs stmt []
  either throwJobQueueError pure result

-- | Atomically acquire one execution lease. Exactly one caller can observe a
-- token, and an expired lease cannot be reclaimed after max_attempts.
claimLearningJob :: QxFx0DB -> Text -> Int -> IO (Maybe LearningJobClaim)
claimLearningJob db requestId leaseSeconds = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    failExhaustedLearningLeases conn now
    mJob <- selectJob conn requestId
    case mJob of
      Nothing -> pure Nothing
      Just (job, generation)
        | ljAttempts job >= ljMaxAttempts job -> pure Nothing
        | ljPolicy job /= currentLearningPolicyVersion -> pure Nothing
        | not (claimableAt now job) -> pure Nothing
        | otherwise -> do
            let nextGeneration = generation + 1
                token = "worker:" <> requestId <> ":" <> T.pack (show nextGeneration) <> ":" <> T.pack (show (utcMicros now))
                leaseUntil = addUTCTime (fromIntegral (max 1 leaseSeconds)) now
            stmt <- prepareTx conn "learning_job_claim"
              "UPDATE learning_jobs SET state='leased', attempts=attempts+1, lease_until=?, lease_token=?, lease_generation=?, updated_at=? WHERE request_id=? AND policy=? AND attempts < max_attempts AND ((state IN ('pending','retry_scheduled') AND available_at <= ?) OR (state='leased' AND lease_until IS NOT NULL AND lease_until <= ?))"
            bindInt64OrFail stmt 1 (utcMicros leaseUntil)
            bindTextOrFail stmt 2 token
            bindInt64OrFail stmt 3 (fromIntegral nextGeneration)
            bindInt64OrFail stmt 4 (utcMicros now)
            bindTextOrFail stmt 5 requestId
            bindTextOrFail stmt 6 currentLearningPolicyVersion
            bindInt64OrFail stmt 7 (utcMicros now)
            bindInt64OrFail stmt 8 (utcMicros now)
            stepOrFail stmt
            changed <- readChanges conn
            pure $ if changed == 1
              then Just (LearningJobClaim (job { ljState = JobLeased, ljAttempts = ljAttempts job + 1, ljLeaseUntil = Just leaseUntil }) token)
              else Nothing
  either throwJobQueueError pure result

releaseLearningJobClaim :: QxFx0DB -> LearningJobClaim -> IO Bool
releaseLearningJobClaim db claim = do
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> do
    stmt <- prepareTx conn "learning_job_claim_release"
      "UPDATE learning_jobs SET state='pending', attempts=MAX(0, attempts-1), available_at=?, lease_until=NULL, lease_token=NULL, updated_at=? WHERE request_id=? AND state='leased' AND lease_token=?"
    bindInt64OrFail stmt 1 (utcMicros now)
    bindInt64OrFail stmt 2 (utcMicros now)
    bindTextOrFail stmt 3 (ljRequestId (ljcJob claim))
    bindTextOrFail stmt 4 (ljcLeaseToken claim)
    stepOrFail stmt
    (== 1) <$> readChanges conn
  either throwJobQueueError pure result

markLearningJobsApplied :: QxFx0DB -> [(Text, Text, Text)] -> Int -> IO ()
markLearningJobsApplied _ [] _ = pure ()
markLearningJobsApplied db jobs cooldownSeconds = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $
    markLearningJobsAppliedOnConnection conn "autonomous-default" jobs cooldownSeconds
  either throwJobQueueError pure result

-- | Governed apply may complete only the exact response_ready dispatch lease
-- carried by its durable event. A stale queued delivery therefore rolls back
-- the graph mutation and cannot acknowledge a newer apply generation.
markLearningJobsAppliedOnConnection :: NSQL.Database -> Text -> [(Text, Text, Text)] -> Int -> IO ()
markLearningJobsAppliedOnConnection _ _ [] _ = pure ()
markLearningJobsAppliedOnConnection conn sessionId jobs cooldownSeconds = do
  now <- getCurrentTime
  let untilAt = addUTCTime (fromIntegral (max 0 cooldownSeconds)) now
  forM_ jobs $ \(requestId, topic, applyToken) -> do
    stmt <- prepareTx conn "learning_job_apply_success"
      "UPDATE learning_jobs SET state='succeeded', lease_until=NULL, lease_token=NULL, last_error=NULL, active_key=NULL, updated_at=? WHERE request_id=? AND topic=? AND policy=? AND session_id=? AND owner=? AND state='response_ready' AND lease_token=? AND lease_until IS NOT NULL AND lease_until>?"
    bindInt64OrFail stmt 1 (utcMicros now)
    bindTextOrFail stmt 2 requestId
    bindTextOrFail stmt 3 topic
    bindTextOrFail stmt 4 currentLearningPolicyVersion
    bindTextOrFail stmt 5 sessionId
    bindTextOrFail stmt 6 sessionId
    bindTextOrFail stmt 7 applyToken
    bindInt64OrFail stmt 8 (utcMicros now)
    stepOrFail stmt
    changed <- readChanges conn
    unless (changed == 1) (throwJobQueueError "learning apply rejected stale dispatch token or policy")
    proof <- prepareTx conn "learning_job_apply_proof"
      "INSERT INTO learning_apply_proofs(source_kind, request_id, policy, dispatch_token, applied_at) VALUES('broad', ?, ?, ?, ?) ON CONFLICT(source_kind, request_id) DO UPDATE SET policy=excluded.policy, dispatch_token=excluded.dispatch_token, applied_at=excluded.applied_at"
    bindTextOrFail proof 1 requestId
    bindTextOrFail proof 2 currentLearningPolicyVersion
    bindTextOrFail proof 3 applyToken
    bindInt64OrFail proof 4 (utcMicros now)
    stepOrFail proof
    when (changed == 1 && not (T.null (T.strip topic))) $ do
      cooldownStmt <- prepareTx conn "learning_job_apply_cooldown"
        "INSERT INTO learning_topic_cooldowns (topic, cooldown_until, updated_at, reason, negative) VALUES (?, ?, ?, 'successful_apply', 0) ON CONFLICT(topic) DO UPDATE SET cooldown_until=excluded.cooldown_until, updated_at=excluded.updated_at, reason=excluded.reason, negative=excluded.negative"
      bindTextOrFail cooldownStmt 1 (T.toLower (T.strip topic))
      bindInt64OrFail cooldownStmt 2 (utcMicros untilAt)
      bindInt64OrFail cooldownStmt 3 (utcMicros now)
      stepOrFail cooldownStmt

-- | Verify every broad event envelope before any projection or evidence write.
-- The success transition repeats the same predicate to close the TOCTOU window.
authorizeLearningJobsApplyOnConnection :: NSQL.Database -> Text -> [(Text, Text, Text)] -> IO ()
authorizeLearningJobsApplyOnConnection conn sessionId jobs = do
  now <- getCurrentTime
  forM_ jobs $ \(requestId, topic, applyToken) -> do
    prepared <- NSQL.prepare conn
      "SELECT 1 FROM learning_jobs WHERE request_id=? AND topic=? AND policy=? AND session_id=? AND owner=? AND state='response_ready' AND lease_token=? AND lease_until IS NOT NULL AND lease_until>? LIMIT 1"
    case prepared of
      Left err -> throwJobQueueError err
      Right stmt -> do
        bindRawText stmt 1 requestId
        bindRawText stmt 2 topic
        bindRawText stmt 3 currentLearningPolicyVersion
        bindRawText stmt 4 sessionId
        bindRawText stmt 5 sessionId
        bindRawText stmt 6 applyToken
        bindRawInt stmt 7 (utcMicros now)
        authorized <- NSQL.stepRow stmt
        NSQL.finalize stmt
        unless authorized (throwJobQueueError "learning apply is not authorized by a current-policy dispatch")

markLearningJobClaimFailed :: QxFx0DB -> LearningJobClaim -> Bool -> Int -> Text -> IO Bool
markLearningJobClaimFailed db claim retryable backoffSeconds message = do
  result <- mask_ $ withDB (qdbPath db) $ \conn ->
    markLearningJobClaimFailedOnConnection conn claim retryable backoffSeconds message
  either throwJobQueueError pure result

markLearningJobClaimFailedOnConnection :: NSQL.Database -> LearningJobClaim -> Bool -> Int -> Text -> IO Bool
markLearningJobClaimFailedOnConnection conn claim retryable backoffSeconds message = do
  now <- getCurrentTime
  let next = addUTCTime (fromIntegral (max 1 backoffSeconds)) now
      retryFlag = if retryable then (1 :: Int64) else 0
  stmt <- prepareTx conn "learning_job_claim_failure"
    "UPDATE learning_jobs SET state=CASE WHEN attempts >= max_attempts OR ?=0 THEN 'failed' ELSE 'retry_scheduled' END, available_at=?, lease_until=NULL, lease_token=NULL, last_error=?, active_key=CASE WHEN attempts >= max_attempts OR ?=0 THEN NULL ELSE active_key END, updated_at=? WHERE request_id=? AND state='leased' AND lease_token=?"
  bindInt64OrFail stmt 1 retryFlag
  bindInt64OrFail stmt 2 (utcMicros next)
  bindTextOrFail stmt 3 message
  bindInt64OrFail stmt 4 retryFlag
  bindInt64OrFail stmt 5 (utcMicros now)
  bindTextOrFail stmt 6 (ljRequestId (ljcJob claim))
  bindTextOrFail stmt 7 (ljcLeaseToken claim)
  stepOrFail stmt
  (== 1) <$> readChanges conn

-- | Commit response, audit events, replay payload, and response_ready state in
-- one transaction. The worker lease fences the entire handoff.
recordLearningJobResponseReady
  :: QxFx0DB
  -> LearningJobClaim
  -> Text
  -> Text
  -> Text
  -> Text
  -> [LearningEvent]
  -> IO ()
recordLearningJobResponseReady db claim promptHash responseHash responseBody payload events = do
  let payloadBytes = BS.length (TE.encodeUtf8 payload)
  when (payloadBytes <= 0 || payloadBytes > maxLearningReadyPayloadBytes) $
    throwJobQueueError "learning ready payload exceeds bounded contract"
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    let requestId = ljRequestId (ljcJob claim)
    recordLearningResponseOnConnection conn requestId promptHash responseHash responseBody
    insertLearningEventsOnConnection conn events
    now <- getCurrentTime
    payloadStmt <- prepareTx conn "learning_ready_payload_upsert"
      "INSERT INTO learning_ready_payloads(request_id, payload_version, payload, payload_bytes, created_at) VALUES(?, 1, ?, ?, ?) ON CONFLICT(request_id) DO UPDATE SET payload_version=excluded.payload_version, payload=excluded.payload, payload_bytes=excluded.payload_bytes, created_at=excluded.created_at"
    bindTextOrFail payloadStmt 1 requestId
    bindTextOrFail payloadStmt 2 payload
    bindInt64OrFail payloadStmt 3 (fromIntegral payloadBytes)
    bindInt64OrFail payloadStmt 4 (utcMicros now)
    stepOrFail payloadStmt
    jobStmt <- prepareTx conn "learning_job_response_ready"
      "UPDATE learning_jobs SET state='response_ready', lease_until=NULL, lease_token=NULL, last_error=NULL, updated_at=? WHERE request_id=? AND policy=? AND state='leased' AND lease_token=?"
    bindInt64OrFail jobStmt 1 (utcMicros now)
    bindTextOrFail jobStmt 2 requestId
    bindTextOrFail jobStmt 3 currentLearningPolicyVersion
    bindTextOrFail jobStmt 4 (ljcLeaseToken claim)
    stepOrFail jobStmt
    changed <- readChanges conn
    unless (changed == 1) (throwJobQueueError "learning response_ready rejected stale worker lease")
  either throwJobQueueError pure result

-- | Lease ready payloads for governed apply. No provider query is involved.
claimLearningReadyPayloads :: QxFx0DB -> Int -> Int -> IO [LearningReadyPayload]
claimLearningReadyPayloads db = claimLearningReadyPayloadsForSession db "autonomous-default"

claimLearningReadyPayloadsForSession :: QxFx0DB -> Text -> Int -> Int -> IO [LearningReadyPayload]
claimLearningReadyPayloadsForSession db sessionId limit leaseSeconds = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    stale <- prepareTx conn "learning_ready_superseded_policy"
      "UPDATE learning_jobs SET state='failed', last_error='superseded_learning_policy', active_key=NULL, lease_until=NULL, lease_token=NULL, updated_at=? WHERE state='response_ready' AND policy<>?"
    bindInt64OrFail stale 1 (utcMicros now)
    bindTextOrFail stale 2 currentLearningPolicyVersion
    stepOrFail stale
    missing <- prepareTx conn "learning_missing_ready_payload"
      "UPDATE learning_jobs SET state='failed', last_error='ready_payload_missing', active_key=NULL, lease_until=NULL, lease_token=NULL, updated_at=? WHERE state='response_ready' AND policy=? AND NOT EXISTS (SELECT 1 FROM learning_ready_payloads p WHERE p.request_id=learning_jobs.request_id)"
    bindInt64OrFail missing 1 (utcMicros now)
    bindTextOrFail missing 2 currentLearningPolicyVersion
    stepOrFail missing
    prepared <- NSQL.prepare conn
      "SELECT j.request_id, j.topic, p.payload, p.payload_bytes, p.payload_version, j.lease_generation FROM learning_jobs j JOIN learning_ready_payloads p ON p.request_id=j.request_id WHERE j.policy=? AND j.session_id=? AND j.owner=? AND j.state='response_ready' AND (j.lease_until IS NULL OR j.lease_until <= ?) ORDER BY j.updated_at ASC LIMIT ?"
    rows <- case prepared of
      Left err -> throwJobQueueError err
      Right stmt -> do
        bindRawText stmt 1 currentLearningPolicyVersion
        bindRawText stmt 2 sessionId
        bindRawText stmt 3 sessionId
        bindRawInt stmt 4 (utcMicros now)
        bindRawInt stmt 5 (fromIntegral (max 0 limit))
        collectReadyRows stmt []
    fmap concat $ forM rows $ \(requestId, topic, payload, payloadBytes, payloadVersion, generation) ->
      if payloadVersion /= 1 || payloadBytes <= 0 || payloadBytes > maxLearningReadyPayloadBytes || BS.length (TE.encodeUtf8 payload) /= payloadBytes
        then failReadyRow conn now requestId "invalid_ready_payload_bounds" >> pure []
        else do
          let nextGeneration = generation + 1
              token = "apply:" <> requestId <> ":" <> T.pack (show nextGeneration) <> ":" <> T.pack (show (utcMicros now))
              leaseUntil = addUTCTime (fromIntegral (max 1 leaseSeconds)) now
          stmt <- prepareTx conn "learning_ready_apply_claim"
            "UPDATE learning_jobs SET lease_until=?, lease_token=?, lease_generation=?, updated_at=? WHERE request_id=? AND policy=? AND state='response_ready' AND (lease_until IS NULL OR lease_until <= ?)"
          bindInt64OrFail stmt 1 (utcMicros leaseUntil)
          bindTextOrFail stmt 2 token
          bindInt64OrFail stmt 3 (fromIntegral nextGeneration)
          bindInt64OrFail stmt 4 (utcMicros now)
          bindTextOrFail stmt 5 requestId
          bindTextOrFail stmt 6 currentLearningPolicyVersion
          bindInt64OrFail stmt 7 (utcMicros now)
          stepOrFail stmt
          changed <- readChanges conn
          pure [LearningReadyPayload requestId topic payload token | changed == 1]
  either throwJobQueueError pure result

-- | Release exact governed-apply leases during worker cancellation. The ready
-- payload remains durable and can be dispatched again without provider I/O.
releaseLearningReadyPayloads :: QxFx0DB -> [LearningReadyPayload] -> IO ()
releaseLearningReadyPayloads _ [] = pure ()
releaseLearningReadyPayloads db ready = mask_ $ do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    forM_ ready $ \item -> do
      stmt <- prepareTx conn "learning_ready_apply_release"
        "UPDATE learning_jobs SET lease_until=NULL, lease_token=NULL, updated_at=? WHERE request_id=? AND state='response_ready' AND lease_token=?"
      bindInt64OrFail stmt 1 (utcMicros now)
      bindTextOrFail stmt 2 (lrpRequestId item)
      bindTextOrFail stmt 3 (lrpApplyToken item)
      stepOrFail stmt
  either throwJobQueueError pure result

rejectLearningReadyPayload :: QxFx0DB -> LearningReadyPayload -> Text -> IO Bool
rejectLearningReadyPayload db ready reason = do
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> do
    stmt <- prepareTx conn "learning_ready_payload_reject"
      "UPDATE learning_jobs SET state='failed', lease_until=NULL, lease_token=NULL, last_error=?, active_key=NULL, updated_at=? WHERE request_id=? AND state='response_ready' AND lease_token=?"
    bindTextOrFail stmt 1 reason
    bindInt64OrFail stmt 2 (utcMicros now)
    bindTextOrFail stmt 3 (lrpRequestId ready)
    bindTextOrFail stmt 4 (lrpApplyToken ready)
    stepOrFail stmt
    (== 1) <$> readChanges conn
  either throwJobQueueError pure result

-- | Reserve fixed minute/hour/day windows under one IMMEDIATE transaction.
-- Reservations are conservative and are never refunded after dispatch.
reserveLearningQuota :: QxFx0DB -> UTCTime -> LearningQuotaLimits -> Int -> Int -> IO Bool
reserveLearningQuota db now limits requests tokens = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    let req = fromIntegral (max 0 requests) :: Int64
        tok = fromIntegral (max 0 tokens) :: Int64
        windows =
          [ ("minute", 60, asLimit (lqlRequestsPerMinute limits), asLimit (lqlTokensPerMinute limits))
          , ("hour", 3600, asLimit (lqlRequestsPerHour limits), asLimit (lqlTokensPerHour limits))
          , ("day", 86400, asLimit (lqlRequestsPerDay limits), asLimit (lqlTokensPerDay limits))
          ]
    checked <- forM windows $ \(name, seconds, reqLimit, tokLimit) -> do
      let start = quotaWindowStart now seconds
      (usedReq, usedTok) <- readQuotaWindow conn name start
      pure (name, start, reqLimit, tokLimit, usedReq, usedTok)
    if any (\(_, _, reqLimit, tokLimit, usedReq, usedTok) -> wouldExceed usedReq req reqLimit || wouldExceed usedTok tok tokLimit) checked
      then pure False
      else do
        forM_ checked $ \(name, start, _, _, usedReq, usedTok) -> do
          stmt <- prepareTx conn "learning_quota_reserve"
            "INSERT INTO learning_quota_windows(window_name, window_start, requests, tokens, updated_at) VALUES(?, ?, ?, ?, ?) ON CONFLICT(window_name) DO UPDATE SET window_start=excluded.window_start, requests=excluded.requests, tokens=excluded.tokens, updated_at=excluded.updated_at"
          bindTextOrFail stmt 1 name
          bindInt64OrFail stmt 2 start
          bindInt64OrFail stmt 3 (saturatingAdd usedReq req)
          bindInt64OrFail stmt 4 (saturatingAdd usedTok tok)
          bindInt64OrFail stmt 5 (utcMicros now)
          stepOrFail stmt
        pure True
  either throwJobQueueError pure result
  where
    asLimit = fromIntegral . max 0
    saturatingAdd left right
      | left > maxBound - right = maxBound
      | otherwise = left + right
    wouldExceed used requested limit = requested > limit || used > limit - requested

recordLearningTopicCooldown :: QxFx0DB -> Text -> Int -> IO ()
recordLearningTopicCooldown db topic seconds = do
  result <- withDB (qdbPath db) $ \conn -> do
    recordLearningTopicCooldownOnConnection conn topic seconds "manual_cooldown" False
  either throwJobQueueError pure result

recordLearningTopicCooldownOnConnection :: NSQL.Database -> Text -> Int -> Text -> Bool -> IO ()
recordLearningTopicCooldownOnConnection conn topic seconds reason negative = do
  now <- getCurrentTime
  let untilAt = addUTCTime (fromIntegral (max 0 seconds)) now
  stmt <- prepareTx conn "learning_topic_cooldown"
    "INSERT INTO learning_topic_cooldowns (topic, cooldown_until, updated_at, reason, negative) VALUES (?, ?, ?, ?, ?) ON CONFLICT(topic) DO UPDATE SET cooldown_until=MAX(learning_topic_cooldowns.cooldown_until, excluded.cooldown_until), updated_at=excluded.updated_at, reason=excluded.reason, negative=excluded.negative"
  bindTextOrFail stmt 1 (T.toLower (T.strip topic))
  bindInt64OrFail stmt 2 (utcMicros untilAt)
  bindInt64OrFail stmt 3 (utcMicros now)
  bindTextOrFail stmt 4 reason
  bindInt64OrFail stmt 5 (if negative then 1 else 0)
  stepOrFail stmt

-- | Return the previous cursor and durably advance by one bounded queue window.
-- The update is transactional so a restarted audit continues the same cycle.
advanceLearningTopicCursor :: QxFx0DB -> Int -> IO Int
advanceLearningTopicCursor db amount = do
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    now <- getCurrentTime
    prepared <- NSQL.prepare conn
      "SELECT topic_cursor FROM learning_scheduler_state WHERE owner='density_audit'"
    current <- case prepared of
      Left err -> throwJobQueueError err
      Right stmt -> do
        found <- NSQL.stepRow stmt
        value <- if found then NSQL.columnInt64 stmt 0 else pure 0
        NSQL.finalize stmt
        pure value
    let next = if current > fromIntegral (maxBound :: Int) - fromIntegral (max 1 amount)
          then 0
          else current + fromIntegral (max 1 amount)
    stmt <- prepareTx conn "learning_topic_cursor_advance"
      "INSERT INTO learning_scheduler_state(owner, topic_cursor, updated_at) VALUES('density_audit', ?, ?) ON CONFLICT(owner) DO UPDATE SET topic_cursor=excluded.topic_cursor, updated_at=excluded.updated_at"
    bindInt64OrFail stmt 1 next
    bindInt64OrFail stmt 2 (utcMicros now)
    stepOrFail stmt
    pure (fromIntegral current)
  either throwJobQueueError pure result

recordLearningResponse :: QxFx0DB -> Text -> Text -> Text -> Text -> IO ()
recordLearningResponse db requestId promptHash responseHash responseBody = do
  result <- withDB (qdbPath db) $ \conn ->
    recordLearningResponseOnConnection conn requestId promptHash responseHash responseBody
  either throwJobQueueError pure result

recordLearningResponseOnConnection :: NSQL.Database -> Text -> Text -> Text -> Text -> IO ()
recordLearningResponseOnConnection conn requestId promptHash responseHash responseBody = do
  now <- getCurrentTime
  stmt <- prepareTx conn "learning_response_insert"
    "INSERT OR REPLACE INTO learning_responses (request_id, prompt_hash, response_hash, response_body, created_at) VALUES (?, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 requestId
  bindTextOrFail stmt 2 promptHash
  bindTextOrFail stmt 3 responseHash
  bindTextOrFail stmt 4 (T.take 65536 responseBody)
  bindInt64OrFail stmt 5 (utcMicros now)
  stepOrFail stmt

selectJob :: NSQL.Database -> Text -> IO (Maybe (LearningJob, Int))
selectJob conn requestId = do
  prepared <- NSQL.prepare conn
    "SELECT request_id, topic, priority, state, attempts, max_attempts, available_at, lease_until, last_error, policy, lease_generation FROM learning_jobs WHERE request_id=?"
  case prepared of
    Left err -> throwJobQueueError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 requestId
      hasRow <- NSQL.stepRow stmt
      value <- if not hasRow then pure Nothing else do
        job <- readJobColumns stmt
        generation <- NSQL.columnInt stmt 10
        pure (fmap (\value -> (value, generation)) job)
      NSQL.finalize stmt
      pure value

claimableAt :: UTCTime -> LearningJob -> Bool
claimableAt now job = case ljState job of
  JobPending -> ljAvailableAt job <= now
  JobRetryScheduled -> ljAvailableAt job <= now
  JobLeased -> maybe False (<= now) (ljLeaseUntil job)
  _ -> False

failExhaustedLearningLeases :: NSQL.Database -> UTCTime -> IO ()
failExhaustedLearningLeases conn now = do
  stmt <- prepareTx conn "learning_expired_lease_failure"
    "UPDATE learning_jobs SET state='failed', lease_until=NULL, lease_token=NULL, last_error='lease_attempts_exhausted', active_key=NULL, updated_at=? WHERE state='leased' AND lease_until IS NOT NULL AND lease_until <= ? AND attempts >= max_attempts"
  bindInt64OrFail stmt 1 (utcMicros now)
  bindInt64OrFail stmt 2 (utcMicros now)
  stepOrFail stmt

failReadyRow :: NSQL.Database -> UTCTime -> Text -> Text -> IO ()
failReadyRow conn now requestId reason = do
  stmt <- prepareTx conn "learning_invalid_ready_payload"
    "UPDATE learning_jobs SET state='failed', lease_until=NULL, lease_token=NULL, last_error=?, active_key=NULL, updated_at=? WHERE request_id=? AND state='response_ready'"
  bindTextOrFail stmt 1 reason
  bindInt64OrFail stmt 2 (utcMicros now)
  bindTextOrFail stmt 3 requestId
  stepOrFail stmt

readQuotaWindow :: NSQL.Database -> Text -> Int64 -> IO (Int64, Int64)
readQuotaWindow conn name start = do
  prepared <- NSQL.prepare conn "SELECT window_start, requests, tokens FROM learning_quota_windows WHERE window_name=?"
  case prepared of
    Left err -> throwJobQueueError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 name
      hasRow <- NSQL.stepRow stmt
      value <- if not hasRow then pure (0, 0) else do
        storedStart <- NSQL.columnInt64 stmt 0
        if storedStart /= start then pure (0, 0)
          else (,) <$> NSQL.columnInt64 stmt 1 <*> NSQL.columnInt64 stmt 2
      NSQL.finalize stmt
      pure value

quotaWindowStart :: UTCTime -> Int64 -> Int64
quotaWindowStart now seconds =
  let epoch = floor (realToFrac (utcTimeToPOSIXSeconds now) :: Double) :: Int64
  in (epoch `div` seconds) * seconds * 1000000

readSchemaVersion :: NSQL.Database -> IO Int
readSchemaVersion conn = do
  prepared <- NSQL.prepare conn "SELECT version FROM learning_schema_versions WHERE owner='job_queue'"
  case prepared of
    Left err -> throwJobQueueError err
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      version <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure version

ensureColumn :: NSQL.Database -> Text -> Text -> Text -> IO ()
ensureColumn conn tableName columnName declaration = do
  exists <- columnExists conn tableName columnName
  unless exists $ exec conn ("ALTER TABLE " <> tableName <> " ADD COLUMN " <> columnName <> " " <> declaration)

validateColumns :: NSQL.Database -> Text -> [Text] -> IO ()
validateColumns conn tableName columns = forM_ columns $ \columnName -> do
  exists <- columnExists conn tableName columnName
  unless exists $ throwJobQueueError ("learning schema validation failed: " <> tableName <> "." <> columnName <> " is missing")

columnExists :: NSQL.Database -> Text -> Text -> IO Bool
columnExists conn tableName columnName = do
  prepared <- NSQL.prepare conn ("SELECT 1 FROM pragma_table_info('" <> tableName <> "') WHERE name=? LIMIT 1")
  case prepared of
    Left err -> throwJobQueueError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 columnName
      exists <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure exists

exec :: NSQL.Database -> Text -> IO ()
exec conn sql = NSQL.execSql conn sql >>= either throwJobQueueError pure

assertNoRows :: NSQL.Database -> String -> Text -> IO ()
assertNoRows conn message sql = do
  prepared <- NSQL.prepare conn sql
  case prepared of
    Left err -> throwJobQueueError err
    Right stmt -> do
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      when found (throwJobQueueError (T.pack message))

retireSupersededJobs :: NSQL.Database -> IO ()
retireSupersededJobs conn = do
  now <- getCurrentTime
  stmt <- prepareTx conn "learning_job_retire_superseded_policy"
    "UPDATE learning_jobs SET state='failed', lease_until=NULL, lease_token=NULL, last_error='superseded_learning_policy', active_key=NULL, updated_at=? WHERE policy<>? AND state IN ('pending','retry_scheduled','leased','response_ready')"
  bindInt64OrFail stmt 1 (utcMicros now)
  bindTextOrFail stmt 2 currentLearningPolicyVersion
  stepOrFail stmt

readChanges :: NSQL.Database -> IO Int
readChanges conn = do
  prepared <- NSQL.prepare conn "SELECT changes()"
  case prepared of
    Left err -> throwJobQueueError err
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      changed <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure changed

collectJobs :: NSQL.Statement -> [LearningJob] -> IO [LearningJob]
collectJobs stmt acc = do
  hasRow <- NSQL.stepRow stmt
  if not hasRow
    then NSQL.finalize stmt >> pure (reverse acc)
    else do
      mJob <- readJobColumns stmt
      collectJobs stmt (maybe acc (: acc) mJob)

readJobColumns :: NSQL.Statement -> IO (Maybe LearningJob)
readJobColumns stmt = do
  requestId <- NSQL.columnText stmt 0
  topic <- NSQL.columnText stmt 1
  priority <- NSQL.columnDouble stmt 2
  stateText <- NSQL.columnText stmt 3
  attempts <- NSQL.columnInt stmt 4
  maxAttempts <- NSQL.columnInt stmt 5
  available <- NSQL.columnInt64 stmt 6
  lease <- ifM (NSQL.columnIsNull stmt 7) (pure Nothing) (Just . microsToUtc <$> NSQL.columnInt64 stmt 7)
  lastError <- ifM (NSQL.columnIsNull stmt 8) (pure Nothing) (Just <$> NSQL.columnText stmt 8)
  policy <- NSQL.columnText stmt 9
  pure $ (\state -> LearningJob requestId topic priority state attempts maxAttempts (microsToUtc available) lease lastError policy) <$> stateFromText stateText

collectReadyRows :: NSQL.Statement -> [(Text, Text, Text, Int, Int, Int)] -> IO [(Text, Text, Text, Int, Int, Int)]
collectReadyRows stmt acc = do
  hasRow <- NSQL.stepRow stmt
  if not hasRow
    then NSQL.finalize stmt >> pure (reverse acc)
    else do
      requestId <- NSQL.columnText stmt 0
      topic <- NSQL.columnText stmt 1
      payload <- NSQL.columnTextLenient stmt 2
      payloadBytes <- NSQL.columnInt stmt 3
      payloadVersion <- NSQL.columnInt stmt 4
      generation <- NSQL.columnInt stmt 5
      collectReadyRows stmt ((requestId, topic, payload, payloadBytes, payloadVersion, generation) : acc)

bindRawInt :: NSQL.Statement -> Int -> Int64 -> IO ()
bindRawInt stmt index value = NSQL.bindInt64 stmt (fromIntegral index) value >>= either throwJobQueueError pure

bindRawText :: NSQL.Statement -> Int -> Text -> IO ()
bindRawText stmt index value = NSQL.bindText stmt (fromIntegral index) value >>= either throwJobQueueError pure

withImmediateTransaction :: NSQL.Database -> IO a -> IO a
withImmediateTransaction conn action = mask_ $ do
  exec conn "BEGIN IMMEDIATE;"
  value <- action `onException` rollbackBestEffort conn
  committed <- NSQL.execSql conn "COMMIT;"
  case committed of
    Right () -> pure value
    Left err -> rollbackBestEffort conn >> throwJobQueueError err

rollbackBestEffort :: NSQL.Database -> IO ()
rollbackBestEffort conn = do
  _ <- NSQL.execSql conn "ROLLBACK;"
  pure ()

throwJobQueueError :: Text -> IO a
throwJobQueueError detail =
  throwQxFx0 (mkSQLiteError
    "learning_job_queue"
    "LEARNING_JOB_QUEUE_SQLITE_ERROR"
    (M.singleton "detail" detail))

ifM :: Monad m => m Bool -> m a -> m a -> m a
ifM action yes no = action >>= \value -> if value then yes else no

utcMicros :: UTCTime -> Int64
utcMicros = round . (* 1000000) . realToFrac . utcTimeToPOSIXSeconds

microsToUtc :: Int64 -> UTCTime
microsToUtc = posixSecondsToUTCTime . (/ 1000000) . fromIntegral
