PRAGMA journal_mode=WAL;

-- Module-owned migration for JobQueue learning schema v5 -> v6.
-- Active unowned jobs are retired fail-closed: attributing a durable provider
-- payload to the first session that restarts would leak session-local evidence.

BEGIN IMMEDIATE;

ALTER TABLE learning_jobs ADD COLUMN session_id TEXT;
ALTER TABLE learning_jobs ADD COLUMN owner TEXT;

UPDATE learning_jobs
SET state = 'failed',
    last_error = 'legacy_job_missing_session_owner',
    active_key = NULL,
    lease_until = NULL,
    lease_token = NULL
WHERE (owner IS NULL OR owner = '')
  AND state IN ('pending', 'leased', 'retry_scheduled', 'response_ready');

INSERT INTO learning_schema_versions(owner, version, updated_at)
VALUES('job_queue', 6, CAST((julianday('now') - 2440587.5) * 86400000000 AS INTEGER))
ON CONFLICT(owner) DO UPDATE SET
  version = excluded.version,
  updated_at = excluded.updated_at;

COMMIT;
