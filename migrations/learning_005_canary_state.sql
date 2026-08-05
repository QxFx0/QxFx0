PRAGMA journal_mode=WAL;

-- Module-owned migration for JobQueue learning schema v4 -> v5.
-- ensureLearningJobSchema performs the equivalent idempotent column/table
-- checks at startup. This file is the explicit offline migration for v4.

BEGIN IMMEDIATE;

ALTER TABLE learning_topic_cooldowns
ADD COLUMN reason TEXT NOT NULL DEFAULT 'successful_apply';

ALTER TABLE learning_topic_cooldowns
ADD COLUMN negative INTEGER NOT NULL DEFAULT 0 CHECK(negative IN (0, 1));

CREATE TABLE learning_scheduler_state (
  owner TEXT PRIMARY KEY,
  topic_cursor INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

INSERT INTO learning_schema_versions(owner, version, updated_at)
VALUES('job_queue', 5, CAST((julianday('now') - 2440587.5) * 86400000000 AS INTEGER))
ON CONFLICT(owner) DO UPDATE SET
  version = excluded.version,
  updated_at = excluded.updated_at;

COMMIT;
