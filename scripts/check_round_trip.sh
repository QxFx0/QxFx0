#!/usr/bin/env bash
# check_round_trip.sh — Gate 3d: Round-trip serialization coverage
#
# Detects types that have ToJSON but lack FromJSON (write-only types).
# These types can produce JSON that cannot be read back — a data-loss defect.
#
# Exit codes:
#   0 = PASS (no write-only types found, or all are in allowlist)
#   1 = FAIL (write-only types detected)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT/src"

# Allowlist: types that are intentionally write-only.
ALLOWLIST_FILE="$ROOT/scripts/round_trip_allowlist.txt"

WRITE_ONLY=""

# ── Check 1: deriving anyclass (..., ToJSON, ...) without FromJSON on same line ──
# For each such line, search backwards for the data/newtype declaration
# to extract the actual type name, then check if a hand-written
# instance FromJSON exists for that type anywhere in src/.
while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  lineno=$(echo "$match" | cut -d: -f2)

  # Search backwards from lineno for 'data TypeName' or 'newtype TypeName'
  typename=""
  for ((i=lineno; i>=1; i--)); do
    line=$(sed -n "${i}p" "$file")
    if echo "$line" | grep -qE '^\s*(data|newtype)\s+[A-Z]'; then
      typename=$(echo "$line" | grep -oE '(data|newtype)\s+[A-Z][A-Za-z0-9_]*' | awk '{print $2}')
      break
    fi
  done

  if [ -n "$typename" ]; then
    # Check if a hand-written 'instance FromJSON TypeName' exists anywhere
    if ! grep -rq "instance FromJSON ${typename}\b" --include='*.hs' "$SRC_DIR" 2>/dev/null; then
      WRITE_ONLY="$WRITE_ONLY${file##*/src/}:${typename}\n"
    fi
  fi
done < <(grep -rn 'deriving.*ToJSON' --include='*.hs' "$SRC_DIR" | grep -v 'FromJSON')

# ── Check 2: instance ToJSON TypeName without instance FromJSON TypeName ──
# For hand-written ToJSON instances, check if a corresponding FromJSON
# instance exists for the same type name anywhere in src/.
while IFS= read -r match; do
  file=$(echo "$match" | cut -d: -f1)
  # Extract type name: 'instance ToJSON TypeName where' or 'instance ToJSON TypeName'
  typename=$(echo "$match" | grep -oE 'instance ToJSON [A-Z][A-Za-z0-9_]*' | awk '{print $3}')
  if [ -n "$typename" ]; then
    [ "$typename" = "where" ] && continue
    # Check if FromJSON instance exists for this type anywhere
    if ! grep -rq "instance FromJSON ${typename}\b" --include='*.hs' "$SRC_DIR" 2>/dev/null; then
      WRITE_ONLY="$WRITE_ONLY${file##*/src/}:${typename}\n"
    fi
  fi
done < <(grep -rn 'instance ToJSON ' --include='*.hs' "$SRC_DIR" | grep -v 'ToJSONKey' | grep -v 'ToJSON (' | grep -v 'import')

# Deduplicate
UNIQUE=$(echo -e "$WRITE_ONLY" | sort -u | grep -v '^$' || true)

# Filter against allowlist
FILTERED=""
if [ -f "$ALLOWLIST_FILE" ]; then
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    if ! grep -qF "$entry" "$ALLOWLIST_FILE" 2>/dev/null; then
      FILTERED="$FILTERED$entry\n"
    fi
  done <<< "$UNIQUE"
else
  FILTERED="$UNIQUE"
fi

# Report
if [ -z "$(echo -e "$FILTERED" | tr -d '[:space:]')" ]; then
  echo "Gate 3d (round-trip): PASS — no write-only types detected"
  exit 0
else
  echo "Gate 3d (round-trip): FAIL — write-only types found (ToJSON without FromJSON):"
  echo -e "$FILTERED" | sed 's/^/  /'
  echo ""
  echo "Each type must have FromJSON or be added to scripts/round_trip_allowlist.txt with justification."
  exit 1
fi
