PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS lex_languages (
  code TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  default_script TEXT NOT NULL DEFAULT 'Cyrl'
);

CREATE TABLE IF NOT EXISTS lexicon_sources (
  source_name TEXT PRIMARY KEY,
  version TEXT NOT NULL DEFAULT '',
  import_date TEXT NOT NULL DEFAULT '',
  license TEXT NOT NULL DEFAULT '',
  checksum TEXT NOT NULL DEFAULT '',
  import_script TEXT NOT NULL DEFAULT '',
  tier TEXT NOT NULL DEFAULT 'curated'
    CHECK (tier IN ('curated', 'brain-kb-reviewed', 'auto-verified', 'auto-coverage'))
);

INSERT OR IGNORE INTO lexicon_sources (source_name, tier) VALUES
  ('curated', 'curated'),
  ('brain-kb-reviewed', 'brain-kb-reviewed'),
  ('auto-verified', 'auto-verified'),
  ('auto-coverage', 'auto-coverage');

CREATE TABLE IF NOT EXISTS lexicon_entries (
  language_code TEXT NOT NULL DEFAULT 'ru',
  lemma TEXT NOT NULL,
  pos TEXT NOT NULL DEFAULT 'noun',
  nominative TEXT NOT NULL,
  genitive TEXT NOT NULL,
  prepositional TEXT NOT NULL,
  accusative TEXT NOT NULL DEFAULT '',
  instrumental TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL DEFAULT 'curated',
  tier TEXT NOT NULL DEFAULT 'curated'
    CHECK (tier IN ('curated', 'brain-kb-reviewed', 'auto-verified', 'auto-coverage')),
  quality REAL NOT NULL DEFAULT 1.0 CHECK (quality >= 0.0 AND quality <= 1.0),
  PRIMARY KEY (language_code, lemma, pos),
  FOREIGN KEY (language_code) REFERENCES lex_languages(code)
);

CREATE INDEX IF NOT EXISTS idx_lexicon_entries_lemma ON lexicon_entries(lemma);
CREATE INDEX IF NOT EXISTS idx_lexicon_entries_source ON lexicon_entries(source);
CREATE INDEX IF NOT EXISTS idx_lexicon_entries_tier ON lexicon_entries(tier);
CREATE INDEX IF NOT EXISTS idx_lexicon_entries_lang ON lexicon_entries(language_code);

CREATE TABLE IF NOT EXISTS lexicon_forms (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_code TEXT NOT NULL DEFAULT 'ru',
  surface TEXT NOT NULL,
  lemma TEXT NOT NULL,
  pos TEXT NOT NULL DEFAULT 'noun',
  case_tag TEXT NOT NULL DEFAULT 'nominative'
    CHECK (case_tag IN ('nominative', 'genitive', 'dative', 'accusative', 'instrumental', 'prepositional')),
  number_tag TEXT NOT NULL DEFAULT 'singular'
    CHECK (number_tag IN ('singular', 'plural')),
  source TEXT NOT NULL DEFAULT 'curated',
  tier TEXT NOT NULL DEFAULT 'curated'
    CHECK (tier IN ('curated', 'brain-kb-reviewed', 'auto-verified', 'auto-coverage')),
  quality REAL NOT NULL DEFAULT 1.0 CHECK (quality >= 0.0 AND quality <= 1.0),
  UNIQUE(language_code, surface, lemma, pos, case_tag, number_tag, source),
  FOREIGN KEY (language_code) REFERENCES lex_languages(code)
);

CREATE INDEX IF NOT EXISTS idx_lexicon_forms_surface ON lexicon_forms(surface);
CREATE INDEX IF NOT EXISTS idx_lexicon_forms_lemma ON lexicon_forms(lemma);
CREATE INDEX IF NOT EXISTS idx_lexicon_forms_tier ON lexicon_forms(tier);

CREATE TABLE IF NOT EXISTS brain_kb_units_raw (
  id TEXT PRIMARY KEY,
  layer TEXT NOT NULL DEFAULT '',
  kind TEXT NOT NULL DEFAULT '',
  text TEXT NOT NULL DEFAULT '',
  topic_json TEXT NOT NULL DEFAULT '[]',
  triggers_json TEXT NOT NULL DEFAULT '[]',
  source_kind TEXT NOT NULL DEFAULT '',
  weight REAL NOT NULL DEFAULT 0.0
);

CREATE TABLE IF NOT EXISTS brain_kb_lexeme_candidates (
  lemma TEXT PRIMARY KEY,
  mention_count INTEGER NOT NULL DEFAULT 0,
  weighted_score REAL NOT NULL DEFAULT 0.0,
  layers_json TEXT NOT NULL DEFAULT '[]',
  topics_json TEXT NOT NULL DEFAULT '[]',
  triggers_json TEXT NOT NULL DEFAULT '[]',
  selected INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_brain_kb_candidates_score
  ON brain_kb_lexeme_candidates(weighted_score DESC);

CREATE TABLE IF NOT EXISTS lex_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_code TEXT NOT NULL DEFAULT 'ru',
  template_id TEXT NOT NULL,
  family TEXT NOT NULL,
  move TEXT NOT NULL,
  style TEXT NOT NULL DEFAULT 'formal',
  surface_template TEXT NOT NULL,
  UNIQUE(language_code, template_id),
  FOREIGN KEY (language_code) REFERENCES lex_languages(code)
);

CREATE TABLE IF NOT EXISTS lex_template_slots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id INTEGER NOT NULL,
  slot_kind TEXT NOT NULL,
  slot_position INTEGER NOT NULL DEFAULT 0,
  required INTEGER NOT NULL DEFAULT 1,
  FOREIGN KEY (template_id) REFERENCES lex_templates(id)
);

CREATE TABLE IF NOT EXISTS lex_cue_rules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_code TEXT NOT NULL DEFAULT 'ru',
  cue_pattern TEXT NOT NULL,
  target_family TEXT NOT NULL,
  target_force TEXT NOT NULL DEFAULT 'IFAsk',
  confidence REAL NOT NULL DEFAULT 0.8 CHECK (confidence >= 0.0 AND confidence <= 1.0),
  UNIQUE(language_code, cue_pattern),
  FOREIGN KEY (language_code) REFERENCES lex_languages(code)
);

CREATE TABLE IF NOT EXISTS lex_style_variants (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  language_code TEXT NOT NULL DEFAULT 'ru',
  style TEXT NOT NULL,
  prefix TEXT NOT NULL DEFAULT '',
  delimiter TEXT NOT NULL DEFAULT ' — ',
  UNIQUE(language_code, style),
  FOREIGN KEY (language_code) REFERENCES lex_languages(code)
);

INSERT OR IGNORE INTO lex_languages (code, label, default_script) VALUES ('ru', 'Русский', 'Cyrl');

INSERT OR IGNORE INTO lex_style_variants (language_code, style, prefix, delimiter) VALUES
  ('ru', 'formal', 'Системно:', ' — '),
  ('ru', 'warm', 'Бережно:', ' — '),
  ('ru', 'direct', 'Прямо:', '. '),
  ('ru', 'poetic', 'Образно:', ' • '),
  ('ru', 'clinical', 'Точно:', ' — '),
  ('ru', 'cautious', 'Осторожно:', ' — '),
  ('ru', 'recovery', 'Восстановление:', ' ');
