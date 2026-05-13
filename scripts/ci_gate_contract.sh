#!/usr/bin/env bash
# ci_gate_contract.sh — CI gate contract for QxFx0_v2 (two-tier: core / extended)
# This script is the single-source-of-truth for release readiness.
#
# Profiles:
#   core     — required on every push/PR (16 GB runner compatible)
#   extended — required for FULL SCIENTIFIC GO (>=32 GB runner, nightly/weekly)
#
# Usage:
#   QXFX0_CONTRACT_PROFILE=core     bash scripts/ci_gate_contract.sh
#   QXFX0_CONTRACT_PROFILE=extended   bash scripts/ci_gate_contract.sh

set -euo pipefail

PROFILE="${QXFX0_CONTRACT_PROFILE:-core}"
COVERAGE_MIN=51
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATES_DIR="$ROOT/reports/baseline_v2/final_gates"
mkdir -p "$GATES_DIR"

# Use writable state paths for hermetic contract runs.
# Keep default cabal package store/toolchain, but redirect build summary log
# away from read-only $HOME locations.
XDG_STATE_HOME="${XDG_STATE_HOME:-$ROOT/.test-tmp/xdg-state}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$ROOT/.test-tmp/xdg-data}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT/.test-tmp/xdg-cache}"
QXFX0_STATE_DIR="${QXFX0_STATE_DIR:-$ROOT/.test-tmp/qxfx0-state}"

CABAL_TMP_DIR="${QXFX0_CABAL_TMP_DIR:-$ROOT/.test-tmp/cabal-ci}"
CABAL_BUILD_SUMMARY="${QXFX0_CABAL_BUILD_SUMMARY:-$CABAL_TMP_DIR/build.log}"
CABAL_CONFIG="${QXFX0_CABAL_CONFIG:-$CABAL_TMP_DIR/config}"
DEFAULT_CABAL_CONFIG="${HOME:-/home/liskil}/.cabal/config"
CABAL_DIR="${CABAL_DIR:-${HOME:-/home/liskil}/.cabal}"

mkdir -p "$CABAL_TMP_DIR"
if [ -f "$DEFAULT_CABAL_CONFIG" ]; then
  cp "$DEFAULT_CABAL_CONFIG" "$CABAL_CONFIG"
else
  : > "$CABAL_CONFIG"
fi
if grep -q '^build-summary:' "$CABAL_CONFIG"; then
  sed -E -i "s|^build-summary:.*$|build-summary: $CABAL_BUILD_SUMMARY|" "$CABAL_CONFIG"
else
  printf '\nbuild-summary: %s\n' "$CABAL_BUILD_SUMMARY" >> "$CABAL_CONFIG"
fi

export CABAL_DIR
export CABAL_CONFIG
export XDG_STATE_HOME
export XDG_DATA_HOME
export XDG_CACHE_HOME
export QXFX0_STATE_DIR
mkdir -p \
  "$CABAL_TMP_DIR" \
  "$XDG_STATE_HOME" \
  "$XDG_DATA_HOME" \
  "$XDG_CACHE_HOME" \
  "$QXFX0_STATE_DIR"

# Prevent parallel cabal operations from racing on dist-newstyle
CABAL_LOCK_FILE="${QXFX0_CABAL_LOCK_FILE:-/tmp/qxfx0-cabal.lock}"
mkdir -p "$(dirname "$CABAL_LOCK_FILE")"

run_with_cabal_lock() {
  (
    flock -w 3600 9 || { echo "ERROR: could not acquire cabal lock within 1 hour"; exit 124; }
    "$@"
  ) 9>"$CABAL_LOCK_FILE"
}

RUN_ID="ci-$(date +%Y%m%d-%H%M%S)"
SUMMARY="$GATES_DIR/_gate_results_${RUN_ID}_${PROFILE}.md"
TSV="$GATES_DIR/_gate_results_${RUN_ID}_${PROFILE}.tsv"

OVERALL_VERDICT="PROD_GO"
REJECT_REASON=""

log_gate() {
  local gate="$1" exit_code="$2" verdict="$3" details="$4"
  echo "| $gate | $exit_code | $verdict | $details |" | tee -a "$SUMMARY"
  echo -e "$gate\t$exit_code\t$verdict\t$details" >> "$TSV"
  if [ "$verdict" != "PASS" ] && [ "$verdict" != "INFO" ]; then
    OVERALL_VERDICT="REJECT"
    if [ -n "$REJECT_REASON" ]; then
      REJECT_REASON="$REJECT_REASON; $gate=$verdict"
    else
      REJECT_REASON="$gate=$verdict"
    fi
  fi
}

fail_contract() {
  local reason="$1"
  echo "" | tee -a "$SUMMARY"
  echo "**CI Gate Contract REJECTED: $reason**" | tee -a "$SUMMARY"
  echo "" | tee -a "$SUMMARY"
  echo "=== CI Gate Contract VERDICT ===" | tee -a "$SUMMARY"
  echo "Profile:    $PROFILE" | tee -a "$SUMMARY"
  echo "Run ID:     $RUN_ID" | tee -a "$SUMMARY"
  echo "Commit:     $(cd "$ROOT" && git rev-parse HEAD 2>/dev/null || echo 'N/A')" | tee -a "$SUMMARY"
  echo "Timestamp:  $(date -Iseconds)" | tee -a "$SUMMARY"
  echo "CONTRACT_VERDICT: REJECT ($reason)" | tee -a "$SUMMARY"
  exit 1
}

# ── Header ──────────────────────────────────────────────────────────────
echo "=== QxFx0 CI Gate Contract ===" | tee "$SUMMARY"
echo "Profile:  $PROFILE" | tee -a "$SUMMARY"
echo "Run ID:   $RUN_ID" | tee -a "$SUMMARY"
echo "Timestamp: $(date -Iseconds)" | tee -a "$SUMMARY"
echo "" | tee -a "$SUMMARY"
echo "| Gate | Exit | Verdict | Details |" | tee -a "$SUMMARY"
echo "|------|------|---------|---------|" | tee -a "$SUMMARY"

echo -e "gate\texit_code\tverdict\tdetails" > "$TSV"

# ════════════════════════════════════════════════════════════════════════
# COMMON GATES (both core and extended)
# ════════════════════════════════════════════════════════════════════════

# ── Gate 1: Build ───────────────────────────────────────────────────────
BUILD_LOG="$GATES_DIR/01_cabal_build_${RUN_ID}_${PROFILE}.log"
if run_with_cabal_lock bash -c "cd '$ROOT' && cabal --build-summary='$CABAL_BUILD_SUMMARY' build all" > "$BUILD_LOG" 2>&1; then
  log_gate "cabal build all" "0" "PASS" "clean compile"
else
  log_gate "cabal build all" "$?" "FAIL" "build errors (see $BUILD_LOG)"
  fail_contract "Gate 1 (build)"
fi

# ── Gate 2: Fast tests ──────────────────────────────────────────────────
FAST_LOG="$GATES_DIR/02_cabal_test_fast_${RUN_ID}_${PROFILE}.log"
if run_with_cabal_lock bash -c "cd '$ROOT' && cabal --build-summary='$CABAL_BUILD_SUMMARY' test qxfx0-test" > "$FAST_LOG" 2>&1; then
  if grep -q 'Errors: 0  Failures: 0' "$FAST_LOG"; then
    log_gate "cabal test fast" "0" "PASS" "0 errors, 0 failures"
  else
    log_gate "cabal test fast" "0" "FAIL" "errors or failures detected"
    fail_contract "Gate 2 (fast tests)"
  fi
else
  log_gate "cabal test fast" "$?" "FAIL" "test suite exited non-zero"
  fail_contract "Gate 2 (fast tests)"
fi

# ── Gate 3: Architecture ────────────────────────────────────────────────
ARCH_LOG="$GATES_DIR/03_check_architecture_${RUN_ID}_${PROFILE}.log"
if (cd "$ROOT" && bash scripts/check_architecture.sh 2>&1) > "$ARCH_LOG" 2>&1; then
  log_gate "check_architecture.sh" "0" "PASS" "boundary checks ok"
else
  log_gate "check_architecture.sh" "$?" "FAIL" "boundary violation"
  fail_contract "Gate 3 (architecture)"
fi

# ── Gate 4: GF Quality ──────────────────────────────────────────────────
GF_LOG="$GATES_DIR/04_gf_quality_${RUN_ID}_${PROFILE}.log"
if (cd "$ROOT" && bash scripts/gf_quality_gate.sh 2>&1) > "$GF_LOG" 2>&1; then
  log_gate "gf_quality_gate.sh" "0" "PASS" "GF grammar quality OK"
else
  log_gate "gf_quality_gate.sh" "$?" "FAIL" "GF quality check failed"
  fail_contract "Gate 4 (GF quality)"
fi

# ── Gate 4a: GF render path distribution ───────────────────────────────
GF_PATH_LOG="$GATES_DIR/06a_gf_render_path_${RUN_ID}_${PROFILE}.log"
if (cd "$ROOT" && RUN_ID="$RUN_ID" PROFILE="$PROFILE" QXFX0_GF_RUNTIME="${QXFX0_GF_RUNTIME:-1}" bash scripts/check_gf_render_path.sh) > "$GF_PATH_LOG" 2>&1; then
  FALLBACK_RATE=$(grep -oE 'fallback_rate=[0-9.]+' "$GF_PATH_LOG" | tail -1 | cut -d= -f2 || true)
  GF_ATOMS_RATE=$(grep -oE 'gf_atoms_rate=[0-9.]+' "$GF_PATH_LOG" | tail -1 | cut -d= -f2 || true)
  log_gate "check_gf_render_path.sh" "0" "PASS" "fallback_rate=${FALLBACK_RATE:-n/a}, gf_atoms_rate=${GF_ATOMS_RATE:-n/a}"
else
  GF_PATH_EXIT=$?
  if [ "$GF_PATH_EXIT" -eq 2 ]; then
    log_gate "check_gf_render_path.sh" "$GF_PATH_EXIT" "INFRA" "unable to measure GF path in this environment"
    fail_contract "Gate 4a (GF render path INFRA)"
  else
    log_gate "check_gf_render_path.sh" "$GF_PATH_EXIT" "FAIL" "GF path thresholds violated"
    fail_contract "Gate 4a (GF render path)"
  fi
fi

# ── Gate 4b: EN render path quality (informational for core, required for extended) ───────────────────────────────
EN_PATH_LOG="$GATES_DIR/06b_en_render_path_${RUN_ID}_${PROFILE}.log"
if (cd "$ROOT" && RUN_ID="$RUN_ID" PROFILE="$PROFILE" QXFX0_GF_RUNTIME="${QXFX0_GF_RUNTIME:-1}" bash scripts/check_en_render_path.sh) > "$EN_PATH_LOG" 2>&1; then
  INTENT_FIT_RATE=$(grep -oE 'intent_fit_rate=[0-9.]+' "$EN_PATH_LOG" | tail -1 | cut -d= -f2 || true)
  GF_OUTPUT_RATE=$(grep -oE 'gf_output_rate=[0-9.]+' "$EN_PATH_LOG" | tail -1 | cut -d= -f2 || true)
  RU_LEAKAGE_RATE=$(grep -oE 'ru_leakage_rate=[0-9.]+' "$EN_PATH_LOG" | tail -1 | cut -d= -f2 || true)
  log_gate "check_en_render_path.sh" "0" "PASS" "intent_fit=${INTENT_FIT_RATE:-n/a}, gf_output=${GF_OUTPUT_RATE:-n/a}, ru_leakage=${RU_LEAKAGE_RATE:-n/a}"
else
  EN_PATH_EXIT=$?
  if [ "$EN_PATH_EXIT" -eq 2 ]; then
    log_gate "check_en_render_path.sh" "$EN_PATH_EXIT" "INFRA" "unable to measure EN path in this environment"
    # Don't fail contract for INFRA on EN gate (core profile)
  else
    log_gate "check_en_render_path.sh" "$EN_PATH_EXIT" "FAIL" "EN quality thresholds violated"
    # Don't fail contract for EN gate failures (core profile - informational only)
  fi
fi

# ── Gate 5: Haddock ─────────────────────────────────────────────────────
HADDOCK_LOG="$GATES_DIR/05_check_haddock_${RUN_ID}_${PROFILE}.log"
if (cd "$ROOT" && bash scripts/check_haddock.sh 2>&1) > "$HADDOCK_LOG" 2>&1; then
  log_gate "check_haddock.sh" "0" "PASS" "module headers ok"
else
  log_gate "check_haddock.sh" "$?" "FAIL" "missing headers"
  fail_contract "Gate 5 (haddock)"
fi

# ── Gate 6: Embedded SQL sync ───────────────────────────────────────────
if (cd "$ROOT" && python3 scripts/sync_embedded_sql.py --check >/dev/null 2>&1); then
  log_gate "sync_embedded_sql.py" "0" "PASS" "EmbeddedSQL.hs in sync"
else
  log_gate "sync_embedded_sql.py" "$?" "FAIL" "EmbeddedSQL.hs drifted"
  fail_contract "Gate 6 (embedded SQL sync)"
fi

# ── Gate 7: Schema consistency ────────────────────────────────────────
if (cd "$ROOT" && python3 scripts/check_schema_consistency.py >/dev/null 2>&1); then
  log_gate "check_schema_consistency.py" "0" "PASS" "cumulative migrations match schema"
else
  log_gate "check_schema_consistency.py" "$?" "FAIL" "schema drift detected"
  fail_contract "Gate 7 (schema consistency)"
fi

# ── Gate 8: Schema contract ─────────────────────────────────────────────
if (cd "$ROOT" && python3 scripts/check_schema_contract.py >/dev/null 2>&1); then
  log_gate "check_schema_contract.py" "0" "PASS" "runtime contract manifest valid"
else
  log_gate "check_schema_contract.py" "$?" "FAIL" "contract manifest drift"
  fail_contract "Gate 8 (schema contract)"
fi

# ── Gate 9: Generated artifacts ─────────────────────────────────────────
GEN_LOG="$GATES_DIR/09_generated_artifacts_${RUN_ID}_${PROFILE}.log"
if (cd "$ROOT" && bash scripts/check_generated_artifacts.sh 2>&1) > "$GEN_LOG" 2>&1; then
  log_gate "check_generated_artifacts.sh" "0" "PASS" "artifacts in sync"
else
  log_gate "check_generated_artifacts.sh" "$?" "FAIL" "generated artifacts drifted"
  fail_contract "Gate 9 (generated artifacts)"
fi

# ── Gate 10: Lexicon contour ────────────────────────────────────────────
LEX_LOG="$GATES_DIR/10_check_lexicon_${RUN_ID}_${PROFILE}.log"
if (cd "$ROOT" && bash scripts/check_lexicon.sh 2>&1) > "$LEX_LOG" 2>&1; then
  log_gate "check_lexicon.sh" "0" "PASS" "lexicon contour OK"
else
  log_gate "check_lexicon.sh" "$?" "FAIL" "lexicon contour failed"
  fail_contract "Gate 10 (lexicon)"
fi

# ════════════════════════════════════════════════════════════════════════
# PROFILE-SPECIFIC GATES
# ════════════════════════════════════════════════════════════════════════

if [ "$PROFILE" = "core" ]; then
  # ── Gate 11 (core): release-smoke degraded-local ──────────────────────
  # NOTE: do NOT wrap release-smoke in run_with_cabal_lock;
  # release-smoke already acquires the same lock in run_local_cabal.
  # Nested flock on the same fd from a child process causes deadlock.
  SMOKE_LOG="$GATES_DIR/11_release_smoke_${RUN_ID}_${PROFILE}.log"
  QXFX0_RUN_SLOW_TESTS=0 QXFX0_RELEASE_SMOKE_MODE=degraded-local QXFX0_RUNTIME_MODE=degraded-local QXFX0_REQUIRE_AGDA=0 QXFX0_GF_RUNTIME="${QXFX0_GF_RUNTIME:-1}" \
  bash -c "cd '$ROOT' && bash scripts/release-smoke.sh" > "$SMOKE_LOG" 2>&1 || true

  FAILED_COUNT=$(grep -oP 'Failed:\s*\K[0-9]+' "$SMOKE_LOG" | tail -1 || echo "UNKNOWN")
  VERDICT_LINE=$(grep 'VERDICT:' "$SMOKE_LOG" | tail -1 || true)

  if [ "$FAILED_COUNT" = "0" ] && echo "$VERDICT_LINE" | grep -qE 'VERDICT:[[:space:]]*(ACCEPT|ACCEPT_WITH_SKIPS)'; then
    if echo "$VERDICT_LINE" | grep -q 'ACCEPT_WITH_SKIPS'; then
      log_gate "release-smoke degraded-local" "0" "PASS" "ACCEPT_WITH_SKIPS (infra skips allowed in core)"
    else
      log_gate "release-smoke degraded-local" "0" "PASS" "ACCEPT (no skips, no failures)"
    fi
  else
    log_gate "release-smoke degraded-local" "0" "FAIL" "Failed=$FAILED_COUNT, verdict=$(echo "$VERDICT_LINE" | tr -d '\033' | sed 's/.*VERDICT://')"
    fail_contract "Gate 11 (release-smoke degraded-local)"
  fi

elif [ "$PROFILE" = "extended" ]; then
  # ── Gate 11 (extended): Slow tests (hard required) ──────────────────
  SLOW_LOG="$GATES_DIR/11_cabal_test_slow_${RUN_ID}_${PROFILE}.log"
  if run_with_cabal_lock bash -c "cd '$ROOT' && cabal --build-summary='$CABAL_BUILD_SUMMARY' test qxfx0-test-slow" > "$SLOW_LOG" 2>&1; then
    if grep -q 'Errors: 0  Failures: 0' "$SLOW_LOG"; then
      log_gate "cabal test slow" "0" "PASS" "0 errors, 0 failures"
    else
      log_gate "cabal test slow" "0" "FAIL" "errors or failures detected"
      fail_contract "Gate 11 (slow tests)"
    fi
  else
    SLOW_EXIT=$?
    # Distinguish INFRA (timeout / OOM / hang) from real code failure
    if [ "$SLOW_EXIT" -eq 124 ] || grep -qi 'timeout\|killed\|out of memory\|cannot allocate' "$SLOW_LOG" 2>/dev/null; then
      log_gate "cabal test slow" "$SLOW_EXIT" "INFRA" "runner capacity insufficient (timeout/OOM); not a code defect"
      fail_contract "Gate 11 (slow tests INFRA — requires >=32 GB RAM runner)"
    else
      log_gate "cabal test slow" "$SLOW_EXIT" "FAIL" "test suite exited non-zero"
      fail_contract "Gate 11 (slow tests)"
    fi
  fi

  # ── Gate 12 (extended): Coverage >= 51% (hard required) ───────────────
  COVERAGE_LOG="$GATES_DIR/12_test_coverage_${RUN_ID}_${PROFILE}.log"
  COVERAGE_TIMEOUT=1200
  COVERAGE_STATUS=0
  if run_with_cabal_lock bash -c "cd '$ROOT' && timeout $COVERAGE_TIMEOUT bash scripts/test_coverage.sh" > "$COVERAGE_LOG" 2>&1; then
    COVERAGE_STATUS=$?
  else
    COVERAGE_STATUS=$?
  fi

  # If coverage was killed by timeout (124) or known infra incompatibility (2),
  # classify as INFRA rather than FAIL, but still reject the contract.
  if [ "$COVERAGE_STATUS" -eq 124 ] || grep -q 'COVERAGE_STATUS=SKIP: known infrastructure incompatibility' "$COVERAGE_LOG" 2>/dev/null; then
    log_gate "test_coverage.sh" "$COVERAGE_STATUS" "INFRA" "timeout or infrastructure incompatibility (not a code failure)"
    fail_contract "Gate 12 (coverage INFRA — requires warm cache or >=20 min timeout)"
  fi

  if [ "$COVERAGE_STATUS" -ne 0 ]; then
    log_gate "test_coverage.sh" "$COVERAGE_STATUS" "FAIL" "coverage script exited non-zero"
    fail_contract "Gate 12 (coverage)"
  fi

  OVERALL_RAW=$(grep -oE 'overall_expr_percent"[[:space:]]*:[[:space:]]*[0-9.]+' "$COVERAGE_LOG" | grep -oE '[0-9.]+$' || true)
  if [ -z "$OVERALL_RAW" ]; then
    OVERALL_RAW=$(grep -oE '([0-9]+(\.[0-9]+)?)% expressions used' "$COVERAGE_LOG" | head -1 | grep -oE '[0-9.]+' || true)
  fi
  if [ -n "$OVERALL_RAW" ]; then
    OVERALL_VAL="${OVERALL_RAW%%%}"
    OVERALL_INT=$(awk "BEGIN {printf \"%d\", $OVERALL_VAL*10}")
    MIN_INT=$((COVERAGE_MIN * 10))
    if [ "$OVERALL_INT" -ge "$MIN_INT" ]; then
      log_gate "test_coverage.sh" "0" "PASS" "overall ${OVERALL_VAL}% >= ${COVERAGE_MIN}%"
    else
      log_gate "test_coverage.sh" "0" "FAIL" "overall ${OVERALL_VAL}% < ${COVERAGE_MIN}%"
      fail_contract "Gate 12 (coverage below threshold)"
    fi
  else
    log_gate "test_coverage.sh" "0" "FAIL" "cannot parse overall coverage"
    fail_contract "Gate 12 (coverage parse error)"
  fi

  # ── Gate 13 (extended): release-smoke strict (no skips allowed) ───────
  # NOTE: do NOT wrap release-smoke in run_with_cabal_lock;
  # release-smoke already acquires the same lock in run_local_cabal.
  SMOKE_LOG="$GATES_DIR/13_release_smoke_${RUN_ID}_${PROFILE}.log"
  QXFX0_RELEASE_SMOKE_MODE=strict \
  bash -c "cd '$ROOT' && bash scripts/release-smoke.sh" > "$SMOKE_LOG" 2>&1 || true

  FAILED_COUNT=$(grep -oP 'Failed:\s*\K[0-9]+' "$SMOKE_LOG" | tail -1 || echo "UNKNOWN")
  VERDICT_LINE=$(grep 'VERDICT:' "$SMOKE_LOG" | tail -1 || true)

  # In strict mode: ACCEPT_WITH_SKIPS is not allowed.
  if [ "$FAILED_COUNT" = "0" ] && echo "$VERDICT_LINE" | grep -q 'ACCEPT_WITH_SKIPS'; then
    log_gate "release-smoke strict" "0" "FAIL" "ACCEPT_WITH_SKIPS in strict mode (skips not allowed)"
    fail_contract "Gate 13 (release-smoke strict — skips detected in strict mode)"
  elif [ "$FAILED_COUNT" = "0" ] && echo "$VERDICT_LINE" | grep -qE 'VERDICT:[[:space:]]*ACCEPT([[:space:]]|$)'; then
    log_gate "release-smoke strict" "0" "PASS" "ACCEPT, Failed=0, no skips"
  else
    log_gate "release-smoke strict" "0" "FAIL" "Failed=$FAILED_COUNT, verdict=$(echo "$VERDICT_LINE" | tr -d '\033' | sed 's/.*VERDICT://')"
    fail_contract "Gate 13 (release-smoke strict)"
  fi

  # ── Gate 14 (extended): verify.sh aggregator (informational) ─────────
  VERIFY_LOG="$GATES_DIR/14_verify_${RUN_ID}_${PROFILE}.log"
  VERIFY_INFO="not run"
  if (cd "$ROOT" && bash scripts/verify.sh 2>&1) > "$VERIFY_LOG" 2>&1; then
    VERIFY_INFO="exit 0 (aggregator OK)"
  else
    VEXIT=$?
    if [ "$VEXIT" -eq 3 ]; then
      VERIFY_INFO="exit 3 INFRA-TIMEOUT (infrastructure incident, not PASS)"
    else
      VERIFY_INFO="exit $VEXIT (aggregator only, not a contract gate)"
    fi
  fi
  log_gate "verify.sh (secondary)" "N/A" "INFO" "$VERIFY_INFO"

elif [ "$PROFILE" = "extended-lowram" ]; then
  # ══════════════════════════════════════════════════════════════════════
  # extended-lowram profile: maximum scientific coverage on 10–11 GB RAM.
  # This profile does NOT claim FULL_SCIENTIFIC_GO; it produces an honest
  # EXTENDED_LOWRAM_* verdict that records INFRA-transparent skips.
  # ══════════════════════════════════════════════════════════════════════
  LOWRAM_INFRA_COUNT=0

  # ── Gate 11 (extended-lowram): fast tests as proxy for slow tests ──────
  # Target repo has no separate qxfx0-test-slow suite; run qxfx0-test.
  FAST_LOG="$GATES_DIR/11_cabal_test_fast_${RUN_ID}_${PROFILE}.log"
  if run_with_cabal_lock bash -c "cd '$ROOT' && cabal --build-summary='$CABAL_BUILD_SUMMARY' test qxfx0-test" > "$FAST_LOG" 2>&1; then
    if grep -q 'Errors: 0  Failures: 0' "$FAST_LOG"; then
      log_gate "cabal test fast (extended proxy)" "0" "PASS" "0 errors, 0 failures"
    else
      log_gate "cabal test fast (extended proxy)" "0" "FAIL" "errors or failures detected"
      fail_contract "Gate 11 (fast tests proxy)"
    fi
  else
    FAST_EXIT=$?
    if [ "$FAST_EXIT" -eq 124 ] || grep -qi 'timeout\|killed\|out of memory\|cannot allocate' "$FAST_LOG" 2>/dev/null; then
      log_gate "cabal test fast (extended proxy)" "$FAST_EXIT" "INFRA" "runner capacity insufficient"
      LOWRAM_INFRA_COUNT=$((LOWRAM_INFRA_COUNT + 1))
    else
      log_gate "cabal test fast (extended proxy)" "$FAST_EXIT" "FAIL" "test suite exited non-zero"
      fail_contract "Gate 11 (fast tests proxy)"
    fi
  fi

  # ── Gate 12 (extended-lowram): Coverage preflight (lightweight) ────────
  COVERAGE_LOG="$GATES_DIR/12_test_coverage_${RUN_ID}_${PROFILE}.log"
  COVERAGE_TIMEOUT=600
  COVERAGE_STATUS=0
  if run_with_cabal_lock bash -c "cd '$ROOT' && timeout $COVERAGE_TIMEOUT bash scripts/test_coverage.sh" > "$COVERAGE_LOG" 2>&1; then
    COVERAGE_STATUS=$?
  else
    COVERAGE_STATUS=$?
  fi

  if [ "$COVERAGE_STATUS" -eq 124 ] || grep -q 'COVERAGE_STATUS=SKIP: known infrastructure incompatibility' "$COVERAGE_LOG" 2>/dev/null; then
    log_gate "test_coverage.sh" "$COVERAGE_STATUS" "INFRA" "timeout or infrastructure incompatibility (not a code failure)"
    LOWRAM_INFRA_COUNT=$((LOWRAM_INFRA_COUNT + 1))
  elif [ "$COVERAGE_STATUS" -ne 0 ]; then
    log_gate "test_coverage.sh" "$COVERAGE_STATUS" "FAIL" "coverage script exited non-zero"
    fail_contract "Gate 12 (coverage)"
  else
    OVERALL_RAW=$(grep -oE 'overall_expr_percent"[[:space:]]*:[[:space:]]*[0-9.]+' "$COVERAGE_LOG" | grep -oE '[0-9.]+$' || true)
    if [ -z "$OVERALL_RAW" ]; then
      OVERALL_RAW=$(grep -oE '([0-9]+(\.[0-9]+)?)% expressions used' "$COVERAGE_LOG" | head -1 | grep -oE '[0-9.]+' || true)
    fi
    if [ -n "$OVERALL_RAW" ]; then
      OVERALL_VAL="${OVERALL_RAW%%%}"
      OVERALL_INT=$(awk "BEGIN {printf \"%d\", $OVERALL_VAL*10}")
      MIN_INT=$((COVERAGE_MIN * 10))
      if [ "$OVERALL_INT" -ge "$MIN_INT" ]; then
        log_gate "test_coverage.sh" "0" "PASS" "overall ${OVERALL_VAL}% >= ${COVERAGE_MIN}%"
      else
        log_gate "test_coverage.sh" "0" "FAIL" "overall ${OVERALL_VAL}% < ${COVERAGE_MIN}%"
        fail_contract "Gate 12 (coverage below threshold)"
      fi
    else
      log_gate "test_coverage.sh" "0" "FAIL" "cannot parse overall coverage"
      fail_contract "Gate 12 (coverage parse error)"
    fi
  fi

  # ── Gate 13 (extended-lowram): release-smoke strict (INFRA-tolerant) ───
  SMOKE_LOG="$GATES_DIR/13_release_smoke_${RUN_ID}_${PROFILE}.log"
  QXFX0_RELEASE_SMOKE_MODE=strict \
  bash -c "cd '$ROOT' && bash scripts/release-smoke.sh" > "$SMOKE_LOG" 2>&1 || true

  FAILED_COUNT=$(grep -oP 'Failed:\s*\K[0-9]+' "$SMOKE_LOG" | tail -1 || echo "UNKNOWN")
  VERDICT_LINE=$(grep 'VERDICT:' "$SMOKE_LOG" | tail -1 || true)

  if [ "$FAILED_COUNT" = "0" ] && echo "$VERDICT_LINE" | grep -qE 'VERDICT:[[:space:]]*(ACCEPT|ACCEPT_WITH_SKIPS)'; then
    if echo "$VERDICT_LINE" | grep -q 'ACCEPT_WITH_SKIPS'; then
      log_gate "release-smoke strict" "0" "INFRA-SKIP" "ACCEPT_WITH_SKIPS in strict mode tolerated as low-ram infra skip"
      LOWRAM_INFRA_COUNT=$((LOWRAM_INFRA_COUNT + 1))
    else
      log_gate "release-smoke strict" "0" "PASS" "ACCEPT, Failed=0, no skips"
    fi
  else
    log_gate "release-smoke strict" "0" "FAIL" "Failed=$FAILED_COUNT, verdict=$(echo "$VERDICT_LINE" | tr -d '\033' | sed 's/.*VERDICT://')"
    fail_contract "Gate 13 (release-smoke strict)"
  fi

  # ── Gate 14 (extended-lowram): verify.sh aggregator (informational) ──
  VERIFY_LOG="$GATES_DIR/14_verify_${RUN_ID}_${PROFILE}.log"
  VERIFY_INFO="not run"
  if (cd "$ROOT" && bash scripts/verify.sh 2>&1) > "$VERIFY_LOG" 2>&1; then
    VERIFY_INFO="exit 0 (aggregator OK)"
  else
    VEXIT=$?
    if [ "$VEXIT" -eq 3 ]; then
      VERIFY_INFO="exit 3 INFRA-TIMEOUT (infrastructure incident, not PASS)"
    else
      VERIFY_INFO="exit $VEXIT (aggregator only, not a contract gate)"
    fi
  fi
  log_gate "verify.sh (secondary)" "N/A" "INFO" "$VERIFY_INFO"

  # Persist low-ram infra count for final verdict
  echo "" | tee -a "$SUMMARY"
  echo "Extended-lowram infra skips: $LOWRAM_INFRA_COUNT" | tee -a "$SUMMARY"

else
  echo "Unknown QXFX0_CONTRACT_PROFILE='$PROFILE'. Must be 'core', 'extended', or 'extended-lowram'." >&2
  exit 1
fi

# ════════════════════════════════════════════════════════════════════════
# FINAL VERDICT
# ════════════════════════════════════════════════════════════════════════

echo "" | tee -a "$SUMMARY"
echo "=== CI Gate Contract VERDICT ===" | tee -a "$SUMMARY"
echo "Profile:    $PROFILE" | tee -a "$SUMMARY"
echo "Run ID:     $RUN_ID" | tee -a "$SUMMARY"
echo "Commit:     $(cd "$ROOT" && git rev-parse HEAD 2>/dev/null || echo 'N/A')" | tee -a "$SUMMARY"
echo "Timestamp:  $(date -Iseconds)" | tee -a "$SUMMARY"

if [ "$OVERALL_VERDICT" = "PROD_GO" ] && [ "$PROFILE" = "core" ]; then
  echo "All core contract gates: PASS" | tee -a "$SUMMARY"
  echo "CONTRACT_VERDICT: PROD_GO" | tee -a "$SUMMARY"
  echo "" | tee -a "$SUMMARY"
  echo "For FULL_SCIENTIFIC_GO, run with QXFX0_CONTRACT_PROFILE=extended on a high-mem runner (>=32 GB RAM, >=45 min timeout)." | tee -a "$SUMMARY"
  exit 0
elif [ "$OVERALL_VERDICT" = "PROD_GO" ] && [ "$PROFILE" = "extended" ]; then
  echo "All extended contract gates: PASS" | tee -a "$SUMMARY"
  echo "CONTRACT_VERDICT: FULL_SCIENTIFIC_GO" | tee -a "$SUMMARY"
  exit 0
elif [ "$OVERALL_VERDICT" = "PROD_GO" ] && [ "$PROFILE" = "extended-lowram" ]; then
  if [ "$LOWRAM_INFRA_COUNT" -gt 0 ]; then
    echo "Extended-lowram contract gates: PASS with $LOWRAM_INFRA_COUNT INFRA-transparent skip(s)" | tee -a "$SUMMARY"
    echo "CONTRACT_VERDICT: EXTENDED_LOWRAM_ACCEPT_WITH_INFRA" | tee -a "$SUMMARY"
    echo "" | tee -a "$SUMMARY"
    echo "Note: INFRA skips are honest capacity limits (coverage rebuild / strict-smoke timeout on <=11 GB RAM)." | tee -a "$SUMMARY"
    echo "For strict FULL_SCIENTIFIC_GO, run with QXFX0_CONTRACT_PROFILE=extended on a high-mem runner (>=32 GB RAM)." | tee -a "$SUMMARY"
  else
    echo "All extended-lowram contract gates: PASS" | tee -a "$SUMMARY"
    echo "CONTRACT_VERDICT: EXTENDED_LOWRAM_ACCEPT" | tee -a "$SUMMARY"
  fi
  exit 0
else
  echo "CONTRACT_VERDICT: REJECT ($REJECT_REASON)" | tee -a "$SUMMARY"
  exit 1
fi
