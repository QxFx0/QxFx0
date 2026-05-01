#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TARGETS="${QXFX0_HADDOCK_TARGETS:-src/QxFx0/Types.hs src/QxFx0/Core.hs src/QxFx0/Semantic/Proposition.hs src/QxFx0/Render/Dialogue.hs src/QxFx0/Runtime/PGF.hs}"

missing=0
for rel in $TARGETS; do
  if [ ! -f "$rel" ]; then
    echo "haddock check: missing file $rel" >&2
    missing=1
    continue
  fi
  if ! rg -n --max-count 1 '^\{-\|' "$rel" >/dev/null; then
    echo "haddock check: missing module header in $rel" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "haddock check: OK"
