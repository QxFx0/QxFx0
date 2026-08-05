PRAGMA journal_mode=WAL;

-- Module-owned migration for promotion snapshot evidence ownership.
-- Legacy snapshot rows are global observations; future rows must copy scope
-- from semantic_edges_runtime and learning_events.

BEGIN IMMEDIATE;

CREATE TABLE IF NOT EXISTS learning_schema_versions (
  owner TEXT PRIMARY KEY,
  version INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

ALTER TABLE promotion_snapshot_edges ADD COLUMN namespace TEXT;
ALTER TABLE promotion_snapshot_edges ADD COLUMN session_id TEXT;
ALTER TABLE promotion_snapshot_edges ADD COLUMN owner TEXT;

ALTER TABLE promotion_snapshot_edge_lineage ADD COLUMN namespace TEXT;
ALTER TABLE promotion_snapshot_edge_lineage ADD COLUMN session_id TEXT;
ALTER TABLE promotion_snapshot_edge_lineage ADD COLUMN owner TEXT;

UPDATE promotion_snapshot_edges
SET namespace = 'global', session_id = NULL, owner = 'legacy_global'
WHERE owner IS NULL OR owner = '';

UPDATE promotion_snapshot_edge_lineage
SET namespace = 'global', session_id = NULL, owner = 'legacy_global'
WHERE owner IS NULL OR owner = '';

INSERT INTO learning_schema_versions(owner, version, updated_at)
VALUES('promotion_scope', 1, CAST((julianday('now') - 2440587.5) * 86400000000 AS INTEGER))
ON CONFLICT(owner) DO UPDATE SET
  version = excluded.version,
  updated_at = excluded.updated_at;

COMMIT;
