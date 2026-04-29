PRAGMA journal_mode=WAL;

-- Migration 003: shadow_divergence_log trace columns.
-- Current 001_initial_schema.sql already creates these columns for fresh DBs.
-- The Haskell bootstrap migration runner performs the idempotent repair for
-- older v2 databases that lack them.

INSERT OR IGNORE INTO schema_version (version, description)
VALUES (3, 'Added shadow_divergence_log trace columns: shadow_snapshot_id, shadow_divergence_kind');
