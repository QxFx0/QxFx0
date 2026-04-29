#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# fuzz.sh — QxFx0 lightweight fuzz gate for exposed surface functions
# Not part of verify.sh; run manually or in nightly CI.
# Targets: parseProposition, NixGuard.nixStringLiteral,
#          MeaningAtoms.collectAtoms (covers KeywordMatch), JSON state decode
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

step_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✓ PASS${NC}"; }
step_fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}✗ FAIL${NC}"; }

echo "=== QxFx0 Fuzz Gate ==="

# Ensure library is built so ghci can load the package
(cd "$ROOT" && cabal build lib:qxfx0 >/dev/null 2>&1) || true

FUZZ_BIN="/tmp/qxfx0-fuzz-$$"

echo "[build] Compiling fuzz harness ..."
if ! (cd "$ROOT" && cabal exec -- ghc -v0 -o "$FUZZ_BIN" "$ROOT/scripts/fuzz_harness.hs") >/dev/null 2>&1; then
    echo -e "  ${RED}FAIL: could not compile fuzz harness${NC}"
    exit 1
fi

echo "[run] Running fuzz rounds (3 x 200 iterations per target) ..."
FUZZ_OUT="$($FUZZ_BIN 2>&1 || true)"
rm -f "$FUZZ_BIN"

if echo "$FUZZ_OUT" | grep -q "ALL_FUZZ_OK"; then
    step_pass
else
    step_fail
    echo "$FUZZ_OUT" | tail -20
fi

echo "=== Fuzz complete: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] || exit 1
