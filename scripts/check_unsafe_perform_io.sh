#!/usr/bin/env bash
# Moratorium gate: unsafePerformIO module count must not increase.
# Current baseline: 12 modules (as of 2026-06-26 audit).
# Goal: reduce to 0 (or all justified with NOINLINE + comment).
# This gate FAILS if count exceeds baseline, preventing new debt.
set -euo pipefail

BASELINE=12

# Count unique source files containing unsafePerformIO (excluding test files)
COUNT=$(grep -rn 'unsafePerformIO' src/ --include='*.hs' \
  | grep -v '/test/' \
  | cut -d: -f1 | sort -u | wc -l)

echo "unsafePerformIO modules: $COUNT (baseline: $BASELINE)"

if [ "$COUNT" -gt "$BASELINE" ]; then
  echo "FAIL: unsafePerformIO module count increased from $BASELINE to $COUNT"
  echo "Moratorium violated. Either remove the new unsafePerformIO or justify with NOINLINE + comment"
  echo "and update BASELINE in this script with explicit justification."
  exit 1
fi

echo "OK: unsafePerformIO count within baseline"
