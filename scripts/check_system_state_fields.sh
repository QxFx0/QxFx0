#!/usr/bin/env bash
# Moratorium gate: SystemState field count must not increase.
# Current baseline: 45 fields (as of 2026-06-26, actual record definition count).
# The audit reported "130 fields" but that counted all ss-prefixed references
# (exports, lenses, accessors). The actual record has 45 fields.
# Goal: decompose SystemState into layer-specific records (Concept 2).
# This gate FAILS if count exceeds baseline, preventing new debt.
set -euo pipefail

BASELINE=45
STATE_FILE="src/QxFx0/Types/State/System.hs"

if [ ! -f "$STATE_FILE" ]; then
  echo "SKIP: $STATE_FILE not found"
  exit 0
fi

# Count fields in the SystemState record definition only
COUNT=$(awk '/^data SystemState/,/^  }/' "$STATE_FILE" | grep -c 'ss[A-Z]')

echo "SystemState fields: $COUNT (baseline: $BASELINE)"

if [ "$COUNT" -gt "$BASELINE" ]; then
  echo "FAIL: SystemState field count increased from $BASELINE to $COUNT"
  echo "Moratorium violated. Do not add new fields to SystemState."
  echo "Instead, create a layer-specific record (see Concept 2: Surgical Decomposition)."
  echo "If absolutely necessary, update BASELINE with explicit justification."
  exit 1
fi

echo "OK: SystemState field count within baseline"
