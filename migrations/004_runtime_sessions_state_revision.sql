PRAGMA journal_mode=WAL;

-- Migration 004: runtime_sessions.state_revision for optimistic-concurrency
-- (the loadStateRevision SELECT + the state_revision CAS UPDATE in
-- StatePersistence.hs). The column was depended upon by the persistence layer
-- but never declared in any schema, so every save-with-revision threw
-- PersistenceTxError (no such column: state_revision).
--
-- Current 001_initial_schema.sql already creates this column for fresh DBs
-- (and canonical spec/sql/schema.sql carries it). The Haskell bootstrap
-- migration runner (EnsureColumn, idempotent) adds it for older DBs that
-- predate it. This file is therefore a version marker only — matching the 003
-- convention — so the cumulative-migration shape stays equal to the canonical
-- schema (no duplicate-column ALTER).

INSERT OR IGNORE INTO schema_version (version, description)
VALUES (4, 'Added runtime_sessions.state_revision for optimistic-concurrency revision tracking');
