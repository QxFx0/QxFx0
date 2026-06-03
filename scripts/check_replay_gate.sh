#!/usr/bin/env bash
# check_replay_gate.sh — replay trace field gate for QxFx0_v3
#
# Verifies that every authority-bearing contour has a corresponding
# trace field in TurnReplayTrace.  This is a grep-level gate that
# checks field presence; the semantic correctness (P2–P4) is covered
# by Test.Suite.TraceSchema.
#
# Usage:
#   bash scripts/check_replay_gate.sh
#
# Exit code: 0 if all expected fields are present, 1 otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRACE_FILE="$ROOT/src/QxFx0/Types/TurnProjection.hs"

fail=0

check_field() {
  local field="$1"
  local contour="$2"
  if grep -q "^[[:space:]]*, $field ::" "$TRACE_FILE"; then
    echo "  [PASS] $contour — $field"
  else
    echo "  [FAIL] $contour — $field NOT FOUND in TurnReplayTrace"
    fail=1
  fi
}

echo "=== Replay trace field gate ==="
echo "Target: $TRACE_FILE"
echo ""

# ── Canonical contours ──────────────────────────────────────────
echo "--- Canonical contours ---"

# Conatus
check_field "trcConatusEnergy"    "Conatus"
check_field "trcConatusGateFired" "Conatus"

# Field
check_field "trcField" "Field"

# Salience (Phase 5.5e)
check_field "trcSalienceDriver"       "Salience"
check_field "trcSalienceHolisticBias" "Salience"
check_field "trcSalienceConfidence"   "Salience"

# Deliberation (Phase 8 Package B)
check_field "trcDeliberationRule"         "Deliberation"
check_field "trcDeliberationAgreement"    "Deliberation"
check_field "trcDeliberationDivergence"   "Deliberation"
check_field "trcDeliberationNarrativeTone" "Deliberation"

# Essence (Phase 9-10, flag-off)
check_field "trcEssenceMode"      "Essence"
check_field "trcEssenceCommitted" "Essence"
check_field "trcEssenceAngstLevel" "Essence"
check_field "trcEssenceTrigger"   "Essence"

# Identity
check_field "trcIdentityClaims" "Identity"

# Episodic memory (P7)
check_field "trcEpisodicEncoding"  "Episodic"
check_field "trcEpisodicRetrieval" "Episodic"
check_field "trcEpisodicForgetting" "Episodic"

# M5 regime governance
check_field "trcRegimeVersion"          "Regime"
check_field "trcFamilyDivergenceActive" "Regime"

# C3 semantic commitment accountability (Package 2)
check_field "trcSemanticCommitmentCount" "SemanticCommitment"

# ── Canonical-flag-off contours ─────────────────────────────────
echo "--- Flag-off contours ---"

# Perspective (P4)
check_field "trcPerspectiveProjection"  "Perspective"
check_field "trcPerspectiveProjections" "Perspective"

# Learning (Phase 8)
check_field "trcLearningQueryType"        "Learning"
check_field "trcLearningValidationStatus" "Learning"

# ── Recovery / provenance ──────────────────────────────────────
echo "--- Support contours ---"

check_field "trcRecoveryCause"   "Recovery"
check_field "trcRecoveryStrategy" "Recovery"
check_field "trcRecoveryEvidence" "Recovery"

# ── Summary ─────────────────────────────────────────────────────
echo ""
if [ "$fail" -eq 0 ]; then
  echo "RESULT: ALL EXPECTED FIELDS PRESENT"
else
  echo "RESULT: SOME FIELDS MISSING"
fi
exit "$fail"
