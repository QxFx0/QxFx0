#!/usr/bin/env bash
set -euo pipefail

# QxFx0 verification gate — must pass before any merge
# Exit codes: 0 = PASS, 1 = FAIL, 2 = PASS_WITH_WARNINGS

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
REQUIRE_STRICT_RUNTIME="${QXFX0_REQUIRE_STRICT_RUNTIME:-0}"
STRICT_EMBEDDING_BACKEND="${QXFX0_STRICT_EMBEDDING_BACKEND:-local-deterministic}"
ENFORCE_STRICT_GF_GATE="${QXFX0_ENFORCE_STRICT_GF_GATE:-0}"
ENFORCE_HADDOCK_GATE="${QXFX0_ENFORCE_HADDOCK_GATE:-1}"
ENABLE_COVERAGE_GATE="${QXFX0_ENABLE_COVERAGE_GATE:-1}"
VERIFY_HOME="$(mktemp -d "${TMPDIR:-/tmp}/qxfx0-verify.XXXXXX")"
VERIFY_CACHE="$VERIFY_HOME/.cache"
VERIFY_CONFIG="$VERIFY_HOME/.config"
VERIFY_STATE="$VERIFY_HOME/.state"
VERIFY_CABAL_DIR="$VERIFY_HOME/.cabal"

mkdir -p "$VERIFY_CACHE" "$VERIFY_CONFIG" "$VERIFY_STATE" "$VERIFY_CABAL_DIR" "$SHARED_CABAL_STORE" "$SHARED_CABAL_LOGS" "$(dirname "$CABAL_LOCK_FILE")"

seed_verify_cabal_home() {
  local host_config="$HOST_CABAL_CONFIG"
  local host_packages="$HOST_CABAL_DIR/packages"

  if [ ! -f "$host_config" ]; then
    host_config="$HOST_XDG_CONFIG_HOME/cabal/config"
  fi

  if [ -f "$host_config" ] && [ ! -f "$VERIFY_CABAL_DIR/config" ]; then
    cp "$host_config" "$VERIFY_CABAL_DIR/config"
  fi
  if [ ! -f "$VERIFY_CABAL_DIR/config" ]; then
    : >"$VERIFY_CABAL_DIR/config"
  fi
  {
    printf '\nstore-dir: %s\n' "$SHARED_CABAL_STORE"
    printf 'logs-dir: %s\n' "$SHARED_CABAL_LOGS"
    printf 'build-summary: %s/build.log\n' "$SHARED_CABAL_LOGS"
    if [ -d "$host_packages" ]; then
      printf 'remote-repo-cache: %s\n' "$host_packages"
    fi
  } >>"$VERIFY_CABAL_DIR/config"
  if [ -d "$host_packages" ] && [ ! -e "$VERIFY_CABAL_DIR/packages" ]; then
    ln -s "$host_packages" "$VERIFY_CABAL_DIR/packages"
  fi
}

seed_verify_cabal_home

cleanup_verify_home() {
  rm -rf "$VERIFY_HOME"
}

trap cleanup_verify_home EXIT

run_nix_flake() {
  nix --option warn-dirty false --extra-experimental-features "nix-command flakes" "$@"
}

run_local() {
  (
    flock -w 1800 9 || exit 1
    HOME="$VERIFY_HOME" \
    XDG_CACHE_HOME="$VERIFY_CACHE" \
    XDG_CONFIG_HOME="$VERIFY_CONFIG" \
    XDG_STATE_HOME="$VERIFY_STATE" \
    CABAL_DIR="$VERIFY_CABAL_DIR" \
    bash -c "cd \"$ROOT\" && $*"
  ) 9>"$CABAL_LOCK_FILE"
}

run_in_dev() {
  (
    flock -w 1800 9 || exit 1
    HOME="$VERIFY_HOME" \
    XDG_CACHE_HOME="$VERIFY_CACHE" \
    XDG_CONFIG_HOME="$VERIFY_CONFIG" \
    XDG_STATE_HOME="$VERIFY_STATE" \
    CABAL_DIR="$VERIFY_CABAL_DIR" \
    run_nix_flake develop "$ROOT" --command bash -c "cd \"$ROOT\" && $*"
  ) 9>"$CABAL_LOCK_FILE"
}

run_nix_app() {
  HOME="$VERIFY_HOME" \
  XDG_CACHE_HOME="$VERIFY_CACHE" \
  XDG_CONFIG_HOME="$VERIFY_CONFIG" \
  XDG_STATE_HOME="$VERIFY_STATE" \
  CABAL_DIR="$VERIFY_CABAL_DIR" \
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
  elif command -v nix >/dev/null 2>&1; then
    run_nix_app "typecheck-agda" >/dev/null 2>&1
  else
    return 127
  fi
}

write_agda_witness() {
  run_cabal_check "cabal run -v0 qxfx0-main -- --write-agda-witness 2>&1"
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
if BUILD_OUT="$(run_cabal_check "cabal build all 2>&1")"; then
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

echo "[2/9] Cabal test ..."
if TEST_OUT="$(run_cabal_check "cabal test qxfx0-test 2>&1")"; then
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
  echo "  FAIL (cabal test exited non-zero)"
  echo "$TEST_OUT" | tail -20
  exit 1
fi

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

echo "[2c/9] Coverage gate ..."
if [ "$ENABLE_COVERAGE_GATE" = "1" ]; then
  if [ -x "$ROOT/scripts/test_coverage.sh" ]; then
    if "$ROOT/scripts/test_coverage.sh" >/dev/null 2>&1; then
      echo "  OK"
    else
      echo "  FAIL (coverage thresholds were not met)"
      exit 1
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
if [ "$REQUIRE_STRICT_RUNTIME" = "1" ]; then
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
  echo "  SKIP (QXFX0_REQUIRE_STRICT_RUNTIME=0)"
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
if ! command -v python3 &>/dev/null; then
  echo "  FAIL (python3 is required for SQL sync verification)"
  exit 1
elif [ ! -f "$ROOT/scripts/sync_embedded_sql.py" ]; then
  echo "  FAIL (scripts/sync_embedded_sql.py is missing)"
  exit 1
elif python3 "$ROOT/scripts/sync_embedded_sql.py" --check >/dev/null 2>&1; then
  echo "  OK"
else
  echo "  FAIL (EmbeddedSQL.hs or migration drifted from spec/sql)"
  exit 1
fi

echo "[8/10] Migration cumulative schema consistency ..."
if ! command -v python3 &>/dev/null; then
  echo "  FAIL (python3 is required for schema consistency verification)"
  exit 1
elif [ ! -f "$ROOT/scripts/check_schema_consistency.py" ]; then
  echo "  FAIL (scripts/check_schema_consistency.py is missing)"
  exit 1
elif python3 "$ROOT/scripts/check_schema_consistency.py" >/dev/null 2>&1; then
  echo "  OK"
else
  echo "  FAIL (cumulative migrations do not match canonical schema.sql)"
  exit 1
fi

echo "[8b/10] Runtime schema contract manifest ..."
if ! command -v python3 &>/dev/null; then
  echo "  FAIL (python3 is required for runtime schema contract verification)"
  exit 1
elif [ ! -f "$ROOT/scripts/check_schema_contract.py" ]; then
  echo "  FAIL (scripts/check_schema_contract.py is missing)"
  exit 1
elif python3 "$ROOT/scripts/check_schema_contract.py" >/dev/null 2>&1; then
  echo "  OK"
else
  echo "  FAIL (runtime schema contract manifest drifted from schema.sql or SchemaContract.hs)"
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
    if TRACE_CHECK_OUT="$(python3 - "$REPLAY_DB" <<'PY' 2>&1
import json
import sqlite3
import sys

db_path = sys.argv[1]
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
trace = json.loads(row[0])
required_fields = [
    "trcRequestId",
    "trcShadowSnapshotId",
    "trcRuntimeMode",
    "trcShadowPolicy",
    "trcLocalRecoveryPolicy",
    "trcRecoveryCause",
    "trcRecoveryStrategy",
    "trcRecoveryEvidence",
    "trcSemanticIntrospectionEnabled",
    "trcWarnMorphologyFallbackEnabled",
]
missing = [name for name in required_fields if name not in trace]
if missing:
    print("missing replay envelope fields:", ",".join(missing))
    raise SystemExit(1)
for text_field in ("trcRuntimeMode", "trcShadowPolicy", "trcLocalRecoveryPolicy"):
    value = trace.get(text_field)
    if not isinstance(value, str) or not value:
        print(f"invalid replay envelope text field: {text_field}")
        raise SystemExit(1)
for optional_text_field in ("trcRecoveryCause", "trcRecoveryStrategy"):
    value = trace.get(optional_text_field)
    if value is not None and not isinstance(value, str):
        print(f"invalid replay envelope optional text field: {optional_text_field}")
        raise SystemExit(1)
recovery_evidence = trace.get("trcRecoveryEvidence")
if not isinstance(recovery_evidence, list) or not all(isinstance(item, str) for item in recovery_evidence):
    print("invalid replay envelope evidence field: trcRecoveryEvidence")
    raise SystemExit(1)
for bool_field in ("trcSemanticIntrospectionEnabled", "trcWarnMorphologyFallbackEnabled"):
    if not isinstance(trace.get(bool_field), bool):
        print(f"invalid replay envelope bool field: {bool_field}")
        raise SystemExit(1)
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
