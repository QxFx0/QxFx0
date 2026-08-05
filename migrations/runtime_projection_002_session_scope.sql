PRAGMA journal_mode=WAL;

-- Module-owned migration for semantic_edges_runtime v1 -> v2.
-- RuntimeProjection.ensureRuntimeProjectionSchema applies the equivalent
-- column checks idempotently and records owner='runtime_projection', version=2
-- in learning_schema_versions. This SQL is the explicit offline form for an
-- operator migrating a known v1 table exactly once.
--
-- Legacy policy: unowned rows are historical shared observations. They become
-- global/legacy_global; they are never assigned to the session performing the
-- migration.

BEGIN IMMEDIATE;

ALTER TABLE semantic_edges_runtime ADD COLUMN session_id TEXT;
ALTER TABLE semantic_edges_runtime ADD COLUMN owner TEXT;

UPDATE semantic_edges_runtime
SET namespace = 'global', session_id = NULL, owner = 'legacy_global'
WHERE owner IS NULL OR owner = '';

CREATE TABLE IF NOT EXISTS learning_schema_versions (
  owner TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

INSERT INTO learning_schema_versions(owner, version, updated_at)
VALUES('runtime_projection', 2, CAST((julianday('now') - 2440587.5) * 86400000000 AS INTEGER))
ON CONFLICT(owner) DO UPDATE SET
  version = excluded.version,
  updated_at = excluded.updated_at;

DROP INDEX IF EXISTS idx_runtime_edge;
CREATE INDEX idx_runtime_edge
ON semantic_edges_runtime(namespace, session_id, owner, edge_from, edge_to);

COMMIT;
