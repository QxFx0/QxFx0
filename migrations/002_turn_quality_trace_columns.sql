PRAGMA journal_mode=WAL;

-- Migration 002: Add turn_quality trace columns for replay and shadow diagnostics.
-- These columns may already exist on DBs created with schema.sql v2 or later.
-- The Haskell migration runner handles duplicate-column errors gracefully.

ALTER TABLE turn_quality ADD COLUMN warranted_mode TEXT NOT NULL DEFAULT 'ConditionallyWarranted';
ALTER TABLE turn_quality ADD COLUMN decision_disposition TEXT NOT NULL DEFAULT 'advisory';
ALTER TABLE turn_quality ADD COLUMN shadow_snapshot_id TEXT NOT NULL DEFAULT '';
ALTER TABLE turn_quality ADD COLUMN shadow_divergence_kind TEXT NOT NULL DEFAULT 'none';
ALTER TABLE turn_quality ADD COLUMN replay_trace_json TEXT NOT NULL DEFAULT '{}';

INSERT OR IGNORE INTO schema_version (version, description)
VALUES (2, 'Added turn_quality trace columns: warranted_mode, decision_disposition, shadow_snapshot_id, shadow_divergence_kind, replay_trace_json');
