#!/usr/bin/env bash
# scripts/gf_quality_gate.sh — GF quality gate for QxFx0_v2
# Verifies that the compiled PGF grammar supports the required surface
# variants and does not silently collapse to template fallback.
#
# Checks:
#   1. PGF file exists and is non-empty.
#   2. No hardcoded template strings in GF concrete syntax.
#   3. Core-family lexicon entries present in GF lexicon.
#   4. (Optional) PGF language count via Runtime.PGF binary if available.
#   5. (Optional) Round-trip sanity via cabal test when QXFX0_GF_FAST_TEST=1.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PGF="$ROOT/spec/gf/QxFx0Syntax.pgf"
OUT_DIR="$ROOT/reports/gf_quality"
mkdir -p "$OUT_DIR"

ERRORS=0
WARNINGS=0

fail() {
  echo "GF_QUALITY_FAIL: $1" >&2
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo "GF_QUALITY_WARN: $1" >&2
  WARNINGS=$((WARNINGS + 1))
}

# ── Check 1: PGF artifact ──────────────────────────────────────────────
echo "[1/4] PGF artifact ..."
if [ ! -f "$PGF" ]; then
  fail "missing $PGF"
  exit 1
fi
if [ ! -s "$PGF" ]; then
  fail "empty $PGF"
  exit 1
fi
SIZE="$(stat -c%s "$PGF" 2>/dev/null || stat -f%z "$PGF" 2>/dev/null || echo 0)"
if [ "$SIZE" -lt 1000 ]; then
  fail "PGF too small (${SIZE} bytes)"
fi
echo "  OK: ${SIZE} bytes"

# ── Check 2: No template strings in GF concrete ───────────────────────
echo "[2/4] No template collapse strings in GF concrete ..."
TEMPLATE_MARKERS=(
  "что значит"
  "ответ по шаблону"
  "template"
  "шаблон"
)
FOUND_TEMPLATE=0
for marker in "${TEMPLATE_MARKERS[@]}"; do
  if rg -iF "$marker" "$ROOT/spec/gf/QxFx0SyntaxRus.gf" "$ROOT/spec/gf/QxFx0SyntaxRusColloquial.gf" "$ROOT/spec/gf/QxFx0SyntaxEng.gf" >/dev/null 2>&1; then
    FOUND_TEMPLATE=1
    fail "template marker '$marker' found in GF concrete"
  fi
done
if [ "$FOUND_TEMPLATE" -eq 0 ]; then
  echo "  OK: no template markers in concrete syntax"
fi

# ── Check 3: Lexicon completeness for core families ──────────────────
echo "[3/4] Core-family lexicon coverage in GF ..."
CORE_TOPICS=(
  agentnost_N smysl_N logika_N svoboda_N istina_N
  absurd_N vina_N vremya_N kontakt_N
)
MISSING_LEX=0
for topic in "${CORE_TOPICS[@]}"; do
  if ! rg -q "$topic" "$ROOT/spec/gf/QxFx0Lexicon.gf" "$ROOT/spec/gf/QxFx0LexiconRus.gf"; then
    warn "core topic '$topic' missing from GF lexicon"
    MISSING_LEX=1
  fi
done
if [ "$MISSING_LEX" -eq 0 ]; then
  echo "  OK: all core topics present"
fi

# ── Check 4: Optional fast test integration ────────────────────────────
if [ "${QXFX0_GF_FAST_TEST:-0}" = "1" ]; then
  echo "[4/4] GF round-trip via fast test suite ..."
  FAST_LOG="$OUT_DIR/gf_fast_test.log"
  if (cd "$ROOT" && LD_LIBRARY_PATH=/tmp/gf-install/usr/lib cabal test qxfx0-test-fast --test-options='-j1 GF' 2>&1) > "$FAST_LOG" 2>&1; then
    if grep -q 'Errors: 0  Failures: 0' "$FAST_LOG"; then
      echo "  OK: fast suite PASS (0 errors, 0 failures)"
    else
      fail "fast suite reported errors/failures (see $FAST_LOG)"
    fi
  else
    fail "fast suite exited non-zero (see $FAST_LOG)"
  fi
else
  echo "[4/4] GF round-trip via fast test suite ... SKIP (set QXFX0_GF_FAST_TEST=1 to enable)"
fi

# ── Summary ────────────────────────────────────────────────────────────
echo ""
echo "=== GF Quality Gate Summary ==="
echo "  Errors:   $ERRORS"
echo "  Warnings: $WARNINGS"
if [ "$ERRORS" -gt 0 ]; then
  echo "  VERDICT: FAIL"
  exit 1
fi
if [ "$WARNINGS" -gt 0 ]; then
  echo "  VERDICT: PASS_WITH_WARNINGS"
  exit 0
fi
echo "  VERDICT: PASS"
exit 0
