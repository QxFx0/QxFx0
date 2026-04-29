PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT (datetime('now')),
  description TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS identity_claims (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  concept TEXT NOT NULL,
  text TEXT NOT NULL,
  confidence REAL NOT NULL DEFAULT 0.5,
  source TEXT NOT NULL DEFAULT 'core',
  topic TEXT NOT NULL DEFAULT '',
  embedding BLOB,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(concept, text)
);

CREATE TABLE IF NOT EXISTS semantic_clusters (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  keywords TEXT NOT NULL,
  priority REAL NOT NULL DEFAULT 0.5
);

CREATE TABLE IF NOT EXISTS realization_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  move_kind TEXT NOT NULL,
  style TEXT NOT NULL DEFAULT 'standard',
  role TEXT NOT NULL DEFAULT 'opening',
  structure TEXT NOT NULL,
  slots TEXT NOT NULL DEFAULT '',
  priority REAL NOT NULL DEFAULT 0.5
);

CREATE TABLE IF NOT EXISTS runtime_sessions (
  id TEXT PRIMARY KEY,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_active TEXT NOT NULL DEFAULT (datetime('now')),
  agency REAL NOT NULL DEFAULT 0.5,
  tension REAL NOT NULL DEFAULT 0.3,
  status TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS dialogue_state (
  session_id TEXT NOT NULL,
  key TEXT NOT NULL,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (session_id, key),
  FOREIGN KEY (session_id) REFERENCES runtime_sessions(id)
);

CREATE TABLE IF NOT EXISTS turn_quality (
  session_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  parser_mode TEXT NOT NULL,
  parser_confidence REAL NOT NULL,
  parser_errors TEXT NOT NULL,
  planner_mode TEXT NOT NULL,
  planner_decision TEXT NOT NULL,
  atom_register TEXT NOT NULL DEFAULT 'Neutral',
  atom_load REAL NOT NULL DEFAULT 0.0,
  scene_pressure TEXT NOT NULL DEFAULT 'medium',
  scene_request TEXT NOT NULL DEFAULT '',
  scene_stance TEXT NOT NULL DEFAULT 'ContentLayer',
  render_lane TEXT NOT NULL DEFAULT 'ValidateMove',
  render_style TEXT NOT NULL DEFAULT 'standard',
  legitimacy_status TEXT NOT NULL DEFAULT 'pass',
  legitimacy_reason TEXT NOT NULL DEFAULT '',
  owner_family TEXT NOT NULL,
  owner_force TEXT NOT NULL,
  shadow_status TEXT NOT NULL,
  shadow_family TEXT,
  shadow_force TEXT,
  shadow_message TEXT NOT NULL,
  divergence INTEGER NOT NULL CHECK (divergence IN (0, 1)),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (session_id, turn),
  FOREIGN KEY (session_id) REFERENCES runtime_sessions(id)
);

CREATE TABLE IF NOT EXISTS shadow_divergence_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  owner_family TEXT NOT NULL,
  owner_force TEXT NOT NULL,
  shadow_status TEXT NOT NULL,
  shadow_snapshot_id TEXT NOT NULL DEFAULT '',
  shadow_divergence_kind TEXT NOT NULL DEFAULT 'none',
  shadow_family TEXT,
  shadow_force TEXT,
  shadow_message TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (session_id) REFERENCES runtime_sessions(id)
);

CREATE VIRTUAL TABLE IF NOT EXISTS identity_claims_fts USING fts5(
  concept, text, content=identity_claims, content_rowid=id
);

CREATE TRIGGER IF NOT EXISTS identity_claims_ai AFTER INSERT ON identity_claims BEGIN
  INSERT INTO identity_claims_fts(rowid, concept, text)
  VALUES (new.id, new.concept, new.text);
END;

CREATE TRIGGER IF NOT EXISTS identity_claims_ad AFTER DELETE ON identity_claims BEGIN
  INSERT INTO identity_claims_fts(identity_claims_fts, rowid, concept, text)
  VALUES ('delete', old.id, old.concept, old.text);
END;

CREATE INDEX IF NOT EXISTS idx_identity_concept ON identity_claims(concept);
CREATE INDEX IF NOT EXISTS idx_identity_topic ON identity_claims(topic);
CREATE INDEX IF NOT EXISTS idx_templates_move ON realization_templates(move_kind);
CREATE INDEX IF NOT EXISTS idx_clusters_name ON semantic_clusters(name);
CREATE INDEX IF NOT EXISTS idx_dialogue_state_session ON dialogue_state(session_id);
CREATE INDEX IF NOT EXISTS idx_turn_quality_session_turn ON turn_quality(session_id, turn DESC);
CREATE INDEX IF NOT EXISTS idx_turn_quality_divergence ON turn_quality(divergence);
CREATE INDEX IF NOT EXISTS idx_shadow_divergence_session_turn ON shadow_divergence_log(session_id, turn DESC);

INSERT OR IGNORE INTO schema_version (version, description)
VALUES (1, 'Initial runtime schema: identity, clusters, templates, sessions, state, projections, FTS5');
