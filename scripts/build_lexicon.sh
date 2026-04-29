#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIN_SCORE="${QXFX0_LEXICON_MIN_SCORE:-8.0}"

cd "$ROOT"

echo "Building lexicon artifacts from SQL sources..."
python3 scripts/export_lexicon.py --min-score "$MIN_SCORE"

mkdir -p resources/lexicon

echo "Exporting ru.lexicon.json..."
python3 -c "
import json, sqlite3, sys
from pathlib import Path

ROOT = Path('$ROOT')
schema = ROOT / 'spec' / 'sql' / 'lexicon' / 'schema.sql'
seed = ROOT / 'spec' / 'sql' / 'lexicon' / 'seed_ru_core.sql'

conn = sqlite3.connect(':memory:')
conn.executescript(schema.read_text(encoding='utf-8'))
conn.executescript(seed.read_text(encoding='utf-8'))

rows = conn.execute('SELECT lemma, pos, nominative, genitive, prepositional, source, quality FROM lexicon_entries ORDER BY lemma, pos').fetchall()
entries = []
for r in rows:
    entries.append({'lemma': r[0], 'pos': r[1], 'nominative': r[2], 'genitive': r[3], 'prepositional': r[4], 'source': r[5], 'quality': r[6]})

artifact = {'language': 'ru', 'lemma_count': len(entries), 'entries': entries}
out = ROOT / 'resources' / 'lexicon' / 'ru.lexicon.json'
out.write_text(json.dumps(artifact, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')
print(f'Exported {len(entries)} lemmas to {out.relative_to(ROOT)}')
conn.close()
"

echo "Lexicon build complete."
