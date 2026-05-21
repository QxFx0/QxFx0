#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# run_wave2.sh — wrapper for Wave 2 A/B soak (live pilot + mock full)
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${QXFX0_WAVE2_RUN_ID:-wave2-2026-05-21}"
PYTHON="${PYTHON:-python3}"

if ! "$PYTHON" --version >/dev/null 2>&1; then
    echo "FAIL: python3 not found"
    exit 1
fi

export QXFX0_WAVE2_RUN_ID="$RUN_ID"

echo "=== QxFx0 Wave 2 Soak ==="
echo "Run ID: $RUN_ID"
echo ""

# Live pilot (small, real API)
echo "[1/3] Live pilot ..."
"$PYTHON" "$ROOT/scripts/wave2_soak.py" live-pilot

# Mock full simulation (deterministic, no API calls)
echo ""
echo "[2/3] Mock full simulation ..."
"$PYTHON" "$ROOT/scripts/wave2_soak.py" mock-full

# Analysis and report generation
echo ""
echo "[3/3] Analysis and report generation ..."
"$PYTHON" "$ROOT/scripts/wave2_soak.py" analyze

echo ""
echo "=== Wave 2 complete ==="
echo "Reports: $ROOT/reports/ab_runs/$RUN_ID/"
