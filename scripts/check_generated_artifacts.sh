#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIN_SCORE="${QXFX0_LEXICON_MIN_SCORE:-8.0}"

cd "$ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for generated-artifact gate" >&2
  exit 1
fi

# 1) Embedded SQL must be generated from canonical spec/sql.
python3 scripts/sync_embedded_sql.py --check >/dev/null

# 2) Lexicon-generated artifacts (JSON/GF/Agda/Haskell) must match SQL source.
python3 scripts/export_lexicon.py --check --min-score "$MIN_SCORE" >/dev/null

# 3) Generated modules must keep an explicit auto-generated marker.
for path in \
  "src/QxFx0/Lexicon/Generated.hs" \
  "spec/gf/QxFx0Lexicon.gf" \
  "spec/gf/QxFx0LexiconRus.gf" \
  "spec/gf/QxFx0Syntax.gf" \
  "spec/gf/QxFx0SyntaxRus.gf" \
  "spec/LexiconData.agda" \
  "spec/LexiconProof.agda"
do
  if ! rg -n "AUTO-GENERATED" "$path" >/dev/null 2>&1; then
    echo "generated-artifact gate failed: missing AUTO-GENERATED marker in $path" >&2
    exit 1
  fi
done

# 4) GF syntax must be compilable to PGF when gf is available.
# If gf is not installed and QXFX0_REQUIRE_GF=0, this step is skipped.
if [ -x "$ROOT/scripts/compile_gf_grammar.sh" ]; then
  if ! QXFX0_REQUIRE_GF=0 "$ROOT/scripts/compile_gf_grammar.sh" >/dev/null; then
    echo "generated-artifact gate failed: GF compile failed or infrastructure is unavailable; stale PGF is not authoritative." >&2
    exit 1
  fi
fi

# 5) Alternate concrete syntaxes must stay structurally aligned with the abstract.
python3 scripts/check_gf_concrete_consistency.py >/dev/null

echo "generated-artifact gate passed"
