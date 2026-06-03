#!/usr/bin/env bash
set -euo pipefail

# QxFx0 verification gate — must pass before any merge
# Exit codes: 0 = PASS, 1 = FAIL, 2 = PASS_WITH_WARNINGS

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib/cabal_env.sh"
HOST_HOME="${HOME:-}"
HOST_CABAL_DIR="${CABAL_DIR:-${HOST_HOME}/.cabal}"
HOST_CABAL_CONFIG="${HOST_CABAL_DIR}/config"
HOST_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOST_HOME}/.config}"
DEFAULT_CABAL_STORE="${HOST_CABAL_DIR}/store"
DEFAULT_CABAL_LOGS="${HOST_CABAL_DIR}/logs"
SHARED_CABAL_STORE="${QXFX0_SHARED_CABAL_STORE:-$DEFAULT_CABAL_STORE}"
SHARED_CABAL_LOGS="${QXFX0_SHARED_CABAL_LOGS:-$DEFAULT_CABAL_LOGS}"
CABAL_LOCK_FILE="${QXFX0_CABAL_LOCK_FILE:-/tmp/qxfx0-cabal.lock}"
EXIT_CODE=0
HOST_PYTHON_SITE_PACKAGES=""
setup_shared_python_site_packages HOST_PYTHON_SITE_PACKAGES
REQUIRE_STRICT_RUNTIME="${QXFX0_REQUIRE_STRICT_RUNTIME:-0}"
VERIFY_STRICT_RUNTIME="${QXFX0_VERIFY_STRICT_RUNTIME:-1}"
STRICT_EMBEDDING_BACKEND="${QXFX0_STRICT_EMBEDDING_BACKEND:-local-deterministic}"
ENFORCE_STRICT_GF_GATE="${QXFX0_ENFORCE_STRICT_GF_GATE:-0}"
ENFORCE_HADDOCK_GATE="${QXFX0_ENFORCE_HADDOCK_GATE:-1}"
ENABLE_COVERAGE_GATE="${QXFX0_ENABLE_COVERAGE_GATE:-1}"
RUN_SLOW_TESTS="${QXFX0_RUN_SLOW_TESTS:-auto}"
VERIFY_HOME="$(mktemp -d "${TMPDIR:-/tmp}/qxfx0-verify.XXXXXX")"
VERIFY_CACHE="$VERIFY_HOME/.cache"
VERIFY_CONFIG="$VERIFY_HOME/.config"
VERIFY_STATE="$VERIFY_HOME/.state"
VERIFY_CABAL_DIR="$VERIFY_HOME/.cabal"

mkdir -p "$VERIFY_CACHE" "$VERIFY_CONFIG" "$VERIFY_STATE" "$VERIFY_CABAL_DIR" "$SHARED_CABAL_STORE" "$SHARED_CABAL_LOGS" "$(dirname "$CABAL_LOCK_FILE")"

seed_shared_cabal_home "$VERIFY_CABAL_DIR" "$SHARED_CABAL_STORE" "$SHARED_CABAL_LOGS" "$HOST_CABAL_DIR" "$HOST_XDG_CONFIG_HOME"

cleanup_verify_home() {
  rm -rf "$VERIFY_HOME"
}

trap cleanup_verify_home EXIT

run_nix_flake() {
  nix --option warn-dirty false --extra-experimental-features "nix-command flakes" "$@"
}

run_local() {
  run_locked_root_command "$ROOT" "$CABAL_LOCK_FILE" "$VERIFY_HOME" "$VERIFY_CACHE" "$VERIFY_CONFIG" "$VERIFY_STATE" "$VERIFY_CABAL_DIR" "$HOST_PYTHON_SITE_PACKAGES" "$*"
}

run_in_dev() {
  run_locked_command "$CABAL_LOCK_FILE" "$VERIFY_HOME" "$VERIFY_CACHE" "$VERIFY_CONFIG" "$VERIFY_STATE" "$VERIFY_CABAL_DIR" "$HOST_PYTHON_SITE_PACKAGES" \
    run_nix_flake develop "$ROOT" --command bash -c "cd \"$ROOT\" && $*"
}

run_nix_app() {
  HOME="$VERIFY_HOME" \
  XDG_CACHE_HOME="$VERIFY_CACHE" \
  XDG_CONFIG_HOME="$VERIFY_CONFIG" \
  XDG_STATE_HOME="$VERIFY_STATE" \
  CABAL_DIR="$VERIFY_CABAL_DIR" \
  PYTHONPATH="${HOST_PYTHON_SITE_PACKAGES}${PYTHONPATH:+:$PYTHONPATH}" \
  bash -c "cd \"$ROOT\" && nix --extra-experimental-features \"nix-command flakes\" run .#$1"
}

run_cabal_check() {
  if command -v cabal >/dev/null 2>&1; then
    run_local "$*"
  else
    run_in_dev "$*"
  fi
}

run_agda_check() {
  if command -v agda >/dev/null 2>&1; then
    run_local "agda spec/R5Core.agda >/dev/null 2>&1"
    run_local "agda spec/Sovereignty.agda >/dev/null 2>&1"
    run_local "agda spec/Legitimacy.agda >/dev/null 2>&1"
    run_local "agda spec/LexiconData.agda >/dev/null 2>&1"
    run_local "agda spec/LexiconProof.agda >/dev/null 2>&1"
    run_local "agda spec/BayesianCoverage.agda >/dev/null 2>&1"
    run_local "agda spec/FamilyCoverage.agda >/dev/null 2>&1"
    run_local "agda spec/ClusterInsightTotality.agda >/dev/null 2>&1"
    run_local "agda spec/GeodesicPlanTotality.agda >/dev/null 2>&1"
  elif command -v nix >/dev/null 2>&1; then
    run_nix_app "typecheck-agda" >/dev/null 2>&1
  else
    return 127
  fi
}

write_agda_witness() {
  local agda_path=""
  if command -v agda >/dev/null 2>&1; then
    agda_path="$(command -v agda)"
  elif command -v nix >/dev/null 2>&1; then
    agda_path="$(nix eval --impure --expr 'with import <nixpkgs> {}; "${agda}/bin/agda"' 2>/dev/null | tr -d '"')"
    if [ -z "$agda_path" ] || [ ! -x "$agda_path" ]; then
      echo "Agda not available for witness generation" >&2
      return 127
    fi
  else
    echo "Agda not available for witness generation" >&2
    return 127
  fi
  PATH="$(dirname "$agda_path"):$PATH" run_cabal_check "cabal run -v0 qxfx0-main -- --write-agda-witness 2>&1"
}

validate_runtime_ready_json() {
  python3 - "$1" <<'PY'
import json
import sys

raw = sys.argv[1]
lines = [line.strip() for line in raw.splitlines() if line.strip()]
if not lines:
    print("runtime-ready produced empty output")
    raise SystemExit(1)
try:
    payload = json.loads(lines[-1])
except json.JSONDecodeError as exc:
    print(f"runtime-ready output is not valid JSON: {exc}")
    raise SystemExit(1)

summary = {
    "runtime_mode": payload.get("runtime_mode"),
    "status": payload.get("status"),
    "ready": payload.get("ready"),
    "decision_path_local_only": payload.get("decision_path_local_only"),
    "network_optional_only": payload.get("network_optional_only"),
    "llm_decision_path": payload.get("llm_decision_path"),
    "nix_ok": payload.get("nix_ok"),
    "datalog_ok": payload.get("datalog_ok"),
    "agda_ok": payload.get("agda_ok"),
    "embed_ok": payload.get("embed_ok"),
    "schema_ok": payload.get("schema_ok"),
    "schema_reason": payload.get("schema_reason"),
    "nix_issues": payload.get("nix_issues"),
    "datalog_issues": payload.get("datalog_issues"),
    "agda_issues": payload.get("agda_issues"),
}

if payload.get("runtime_mode") != "strict" or payload.get("status") != "ok" or payload.get("ready") is not True \
   or payload.get("decision_path_local_only") is not True \
   or payload.get("network_optional_only") is not True \
   or payload.get("llm_decision_path") is not False:
    print("strict runtime-ready mismatch:")
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    raise SystemExit(1)
PY
}

echo "=== QxFx0 Verification Gate ==="

echo "[1/9] Cabal build ..."
if BUILD_OUT="$(run_cabal_check "cabal build all -j1 2>&1")"; then
  BUILD_ERRORS=$(echo "$BUILD_OUT" | grep -c 'error:' || true)
  if [ "$BUILD_ERRORS" -gt 0 ]; then
    echo "  FAIL ($BUILD_ERRORS errors)"
    echo "$BUILD_OUT" | grep 'error:' | head -10
    exit 1
  else
    echo "  OK"
  fi
else
  echo "  FAIL (cabal build exited non-zero)"
  echo "$BUILD_OUT" | tail -20
  exit 1
fi

echo "[2/9] Cabal test (fast profile) ..."
if TEST_OUT="$(run_cabal_check "cabal test qxfx0-test-fast 2>&1")"; then
  TEST_FAIL=$(echo "$TEST_OUT" | grep -c 'FAIL' || true)
  TEST_CASES_RAW=$(echo "$TEST_OUT" | grep -oP 'Cases: \K\d+' | tail -1 || true)
  TEST_TRIED_RAW=$(echo "$TEST_OUT" | grep -oP 'Tried: \K\d+' | tail -1 || true)
  TEST_ERRORS_RAW=$(echo "$TEST_OUT" | grep -oP 'Errors: \K\d+' | tail -1 || true)
  TEST_CASES=${TEST_CASES_RAW:-0}
  TEST_TRIED=${TEST_TRIED_RAW:-0}
  TEST_ERRORS=${TEST_ERRORS_RAW:-0}
  TEST_CASES=${TEST_CASES:-0}
  TEST_TRIED=${TEST_TRIED:-0}
  TEST_ERRORS=${TEST_ERRORS:-0}
  if [ "$TEST_FAIL" -gt 0 ] || [ "$TEST_ERRORS" -gt 0 ]; then
    echo "  FAIL ($TEST_ERRORS errors, $TEST_FAIL failures)"
    exit 1
  else
    if [ -n "${TEST_CASES_RAW:-}" ] && [ -n "${TEST_TRIED_RAW:-}" ]; then
      echo "  OK ($TEST_TRIED/$TEST_CASES passed)"
    else
      echo "  OK (pass count unavailable in cabal output)"
    fi
  fi
else
  echo "  FAIL (cabal test qxfx0-test-fast exited non-zero)"
  echo "$TEST_OUT" | tail -20
  exit 1
fi

echo "[2s/9] Cabal test (slow profile) ..."
case "$RUN_SLOW_TESTS" in
  0|false|FALSE|no|NO)
    echo "  SKIP (QXFX0_RUN_SLOW_TESTS=$RUN_SLOW_TESTS)"
    ;;
  1|true|TRUE|yes|YES)
    if SLOW_TEST_OUT="$(run_cabal_check "cabal test qxfx0-test-slow 2>&1")"; then
      SLOW_TEST_SUMMARY="$(echo "$SLOW_TEST_OUT" | grep -E 'Cases: .*Tried: .*Errors: .*Failures:' | tail -1 || true)"
      echo "  OK (${SLOW_TEST_SUMMARY:-slow suite passed})"
    else
      echo "  FAIL (cabal test qxfx0-test-slow exited non-zero)"
      echo "$SLOW_TEST_OUT" | tail -20
      exit 1
    fi
    ;;
  auto|AUTO|Auto|'')
    echo "  SKIP (QXFX0_RUN_SLOW_TESTS=auto keeps slow suite opt-in; set QXFX0_RUN_SLOW_TESTS=1 to force)"
    ;;
  *)
    echo "  FAIL (invalid QXFX0_RUN_SLOW_TESTS value: $RUN_SLOW_TESTS)"
    exit 1
    ;;
esac

echo "[2b/9] Haddock module headers ..."
if [ "$ENFORCE_HADDOCK_GATE" = "1" ]; then
  if [ -x "$ROOT/scripts/check_haddock.sh" ]; then
    if "$ROOT/scripts/check_haddock.sh" >/dev/null 2>&1; then
      echo "  OK"
    else
      echo "  FAIL (haddock module headers check failed)"
      exit 1
    fi
  else
    echo "  FAIL (scripts/check_haddock.sh is missing or not executable)"
    exit 1
  fi
else
  echo "  SKIP (QXFX0_ENFORCE_HADDOCK_GATE=0)"
fi

echo "[2ba/9] Concepts schema contract ..."
if python3 "$ROOT/scripts/check_concepts_schema.py" >/dev/null 2>&1; then
  echo "  OK"
else
  echo "  FAIL (concepts schema contract invalid)"
  exit 1
fi

echo "[2c/9] Coverage gate ..."
if [ "$ENABLE_COVERAGE_GATE" = "1" ]; then
  if [ -x "$ROOT/scripts/test_coverage.sh" ]; then
    COVERAGE_STATUS=0
    COVERAGE_OUT=""
    if COVERAGE_OUT="$("$ROOT/scripts/test_coverage.sh" 2>&1)"; then
      echo "  OK (COVERAGE_STATUS=PASS)"
    else
      COVERAGE_STATUS=$?
      if [ "$COVERAGE_STATUS" -eq 2 ]; then
        echo "  SKIP (COVERAGE_STATUS=SKIP: known infrastructure incompatibility)"
        echo "$COVERAGE_OUT" | tail -5
      else
        echo "  FAIL (COVERAGE_STATUS=FAIL: coverage thresholds not met or test failure)"
        echo "$COVERAGE_OUT" | tail -20
        exit 1
      fi
    fi
  else
    echo "  FAIL (scripts/test_coverage.sh is missing or not executable)"
    exit 1
  fi
else
  echo "  SKIP (QXFX0_ENABLE_COVERAGE_GATE=0)"
fi

echo "[3/10] Agda R5 typecheck ..."
AGDA_WITNESS_READY=0
if [ "${QXFX0_SKIP_AGDA:-0}" = "1" ]; then
  echo "  SKIP (QXFX0_SKIP_AGDA=1)"
elif run_agda_check; then
  echo "  OK"
  AGDA_WITNESS_READY=1
else
  AGDA_STATUS=$?
  if [ "$AGDA_STATUS" -eq 127 ]; then
    echo "  FAIL (Agda unavailable locally and via nix; install Agda or set QXFX0_SKIP_AGDA=1)"
    exit 1
  else
    echo "  FAIL (Agda typecheck failed)"
    exit 1
  fi
fi

echo "[4/10] Agda witness ..."
if [ "$AGDA_WITNESS_READY" = "1" ]; then
  if AGDA_WITNESS_OUT="$(write_agda_witness)"; then
    if [ -n "$AGDA_WITNESS_OUT" ]; then
      echo "  OK ($(echo "$AGDA_WITNESS_OUT" | tail -1))"
    else
      echo "  OK"
    fi
  else
    echo "  FAIL (Agda witness generation failed)"
    echo "$AGDA_WITNESS_OUT" | tail -20
    exit 1
  fi
else
  echo "  SKIP (Agda witness requires successful typecheck)"
fi

echo "[5/10] Strict runtime readiness ..."
if [ "$REQUIRE_STRICT_RUNTIME" = "1" ] || [ "$VERIFY_STRICT_RUNTIME" = "1" ]; then
  if STRICT_READY_OUT="$(QXFX0_DB="$VERIFY_HOME/strict-runtime.db" QXFX0_RUNTIME_MODE=strict QXFX0_EMBEDDING_BACKEND="$STRICT_EMBEDDING_BACKEND" run_cabal_check "cabal run -v0 qxfx0-main -- --runtime-ready 2>&1")"; then
    if READY_CHECK_OUT="$(validate_runtime_ready_json "$STRICT_READY_OUT" 2>&1)"; then
      echo "  OK"
    else
      echo "  FAIL (strict runtime readiness is mandatory for verification)"
      echo "$READY_CHECK_OUT"
      echo "$STRICT_READY_OUT" | tail -20
      exit 1
    fi
  else
    echo "  FAIL (strict runtime readiness command exited non-zero)"
    echo "$STRICT_READY_OUT" | tail -20
    exit 1
  fi
else
  echo "  SKIP (strict runtime verification explicitly disabled)"
fi

echo "[6/10] Compiler warnings ..."
SRC_WARNINGS=$(echo "$BUILD_OUT" | grep -c 'warning: \[-W' || true)
if [ "$SRC_WARNINGS" -gt 0 ]; then
  echo "  WARN ($SRC_WARNINGS project warnings)"
  EXIT_CODE=2
else
  echo "  OK (0 warnings)"
fi

echo "[7/10] Embedded SQL sync ..."
if (cd "$ROOT" && cabal run qxfx0-main -- --check-embedded-sql >/dev/null 2>&1); then
  echo "  OK"
else
  echo "  FAIL (EmbeddedSQL.hs or migration drifted from spec/sql)"
  exit 1
fi

echo "[8/10] Migration cumulative schema consistency ..."
if (cd "$ROOT" && cabal run qxfx0-main -- --check-schema-consistency >/dev/null 2>&1); then
  echo "  OK"
else
  echo "  FAIL (cumulative migrations do not match canonical schema.sql)"
  exit 1
fi

echo "[8b/10] Runtime schema contract manifest ..."
if (cd "$ROOT" && cabal run qxfx0-main -- --check-schema-contract >/dev/null 2>&1); then
  echo "  OK"
else
  echo "  FAIL (runtime schema contract manifest drifted from schema.sql or SchemaContract.hs)"
  exit 1
fi

echo "[8c/10] Runtime/deployment contract source ..."
if ! command -v python3 &>/dev/null; then
  echo "  FAIL (python3 is required for runtime/deployment contract verification)"
  exit 1
elif [ ! -f "$ROOT/scripts/check_runtime_contract.py" ]; then
  echo "  FAIL (scripts/check_runtime_contract.py is missing)"
  exit 1
elif python3 "$ROOT/scripts/check_runtime_contract.py" >/dev/null 2>&1; then
  echo "  OK"
else
  echo "  FAIL (runtime/deployment contract source drifted from docs/tests/workflow)"
  exit 1
fi

echo "[8/10] Generated artifacts ..."
if [ -x "$ROOT/scripts/check_generated_artifacts.sh" ]; then
  if [ "$ENFORCE_STRICT_GF_GATE" = "1" ]; then
    GEN_OK=0
    QXFX0_REQUIRE_GF=1 "$ROOT/scripts/check_generated_artifacts.sh" >/dev/null 2>&1 || GEN_OK=$?
  else
    GEN_OK=0
    QXFX0_REQUIRE_GF=0 "$ROOT/scripts/check_generated_artifacts.sh" >/dev/null 2>&1 || GEN_OK=$?
  fi
  if [ "$GEN_OK" -eq 0 ]; then
    if [ "$ENFORCE_STRICT_GF_GATE" = "1" ]; then
      echo "  OK (strict GF gate)"
    else
      echo "  OK (GF gate without strict compiler requirement)"
    fi
  else
    echo "  FAIL (generated artifacts drifted from canonical sources)"
    exit 1
  fi
else
  echo "  SKIP (check_generated_artifacts.sh not found)"
fi

echo "[9/10] Lexicon contour ..."
if [ -x "$ROOT/scripts/check_lexicon.sh" ]; then
  if "$ROOT/scripts/check_lexicon.sh" >/dev/null 2>&1; then
    echo "  OK"
  else
    echo "  FAIL (lexicon SQL->artifact gate failed)"
    exit 1
  fi
else
  echo "  SKIP (check_lexicon.sh not found)"
fi

echo "[10/10] Architecture boundaries ..."
if [ -x "$ROOT/scripts/check_architecture.sh" ]; then
  if "$ROOT/scripts/check_architecture.sh" >/dev/null 2>&1; then
    echo "  OK"
  else
    echo "  FAIL (architecture boundary violations detected)"
    exit 1
  fi
else
  echo "  SKIP (check_architecture.sh not found)"
fi

echo "[10b/10] Calibration codomain (Package 11) ..."
if [ -x "$ROOT/scripts/check_calibration_codomain.sh" ]; then
  if "$ROOT/scripts/check_calibration_codomain.sh" >/dev/null 2>&1; then
    echo "  OK"
  else
    echo "  FAIL (calibration parameter out of range)"
    exit 1
  fi
else
  echo "  SKIP (check_calibration_codomain.sh not found)"
fi

echo "[10c/10] Replay gate (Package 3) ..."
if [ -x "$ROOT/scripts/check_replay_gate.sh" ]; then
  if "$ROOT/scripts/check_replay_gate.sh" >/dev/null 2>&1; then
    echo "  OK"
  else
    echo "  FAIL (replay gate violation)"
    exit 1
  fi
else
  echo "  SKIP (check_replay_gate.sh not found)"
fi
echo "[11/11] Shadow snapshot trace schema ..."
if grep -q "shadow_snapshot_id" "$ROOT/spec/sql/schema.sql" && \
   grep -q "shadow_divergence_kind" "$ROOT/spec/sql/schema.sql" && \
   grep -q "replay_trace_json" "$ROOT/spec/sql/schema.sql" && \
   grep -Rqs "shadow_snapshot_id" "$ROOT/migrations" && \
   grep -Rqs "shadow_divergence_kind" "$ROOT/migrations" && \
   grep -Rqs "replay_trace_json" "$ROOT/migrations"; then
  echo "  OK"
else
  echo "  FAIL (shadow snapshot trace columns missing in SQL schema/migration)"
  exit 1
fi

echo "[12/12] Replay envelope trace fields ..."
if [ "$REQUIRE_STRICT_RUNTIME" != "1" ]; then
  echo "  SKIP (replay strict-envelope check requires QXFX0_REQUIRE_STRICT_RUNTIME=1)"
elif command -v python3 &>/dev/null; then
  REPLAY_DB="$VERIFY_HOME/replay-envelope.db"
  if REPLAY_TURN_OUT="$(QXFX0_DB="$REPLAY_DB" QXFX0_RUNTIME_MODE=strict QXFX0_EMBEDDING_BACKEND="$STRICT_EMBEDDING_BACKEND" run_cabal_check "cabal run -v0 qxfx0-main -- --session replay-gate --input 'Что такое свобода?' --json 2>&1")"; then
    if TRACE_CHECK_OUT="$(python3 - "$REPLAY_DB" "$ROOT/scripts/check_replay_trace_fields.py" <<'PY' 2>&1
import sqlite3
import subprocess
import sys

db_path = sys.argv[1]
checker = sys.argv[2]
conn = sqlite3.connect(db_path)
try:
    row = conn.execute(
        "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1",
        ("replay-gate",),
    ).fetchone()
finally:
    conn.close()
if row is None or not row[0]:
    print("missing replay_trace_json row for replay-gate")
    raise SystemExit(1)
# Canonical local-recovery replay envelope fields required here:
# trcLocalRecoveryPolicy, trcRecoveryCause,
# trcRecoveryStrategy, trcRecoveryEvidence.
subprocess.run([sys.executable, checker, "--json", row[0]], check=True)
PY
    )"; then
      echo "  OK"
    else
      echo "  FAIL (replay_trace_json is missing effective runtime envelope fields)"
      echo "$TRACE_CHECK_OUT"
      exit 1
    fi
  else
    echo "  FAIL (could not generate replay trace for envelope check)"
    echo "$REPLAY_TURN_OUT" | tail -20
    exit 1
  fi
else
  echo "  FAIL (python3 is required for replay envelope verification)"
  exit 1
fi

echo "[13] cabal.project.freeze present ..."
if [ -f "$ROOT/cabal.project.freeze" ]; then
  echo "  OK"
else
  echo "  FAIL (cabal.project.freeze missing — run 'cabal freeze')"
  exit 1
fi

echo "[post] Agda R5 constructor sync ..."
if command -v python3 &>/dev/null && [ -f "$ROOT/scripts/verify_agda_sync.py" ]; then
  if python3 "$ROOT/scripts/verify_agda_sync.py"; then
    echo "  OK"
  else
    echo "  FAIL (constructor sync mismatch — check Agda/Haskell alignment)"
    exit 1
  fi
else
  echo "  SKIP (script not found)"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "=== Verification PASS ==="
elif [ "$EXIT_CODE" -eq 2 ]; then
  echo "=== Verification PASS_WITH_WARNINGS ==="
else
  echo "=== Verification FAIL ==="
fi
exit $EXIT_CODE
