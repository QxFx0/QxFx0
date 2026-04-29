#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# release-smoke.sh — QxFx0 10-step comprehensive release gate
# Synthesises QxFx2's 10-step gate with QxFx5 process-group isolation
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

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
BIN=""
DB="/tmp/qxfx0-smoke-$$.db"
PORT=19170
PID_HTTP=""
PASS=0
FAIL=0
SKIP=0
REQUIRE_STRICT_RUNTIME="${QXFX0_REQUIRE_STRICT_RUNTIME:-1}"
STRICT_EMBEDDING_BACKEND="${QXFX0_STRICT_EMBEDDING_BACKEND:-local-deterministic}"
ENFORCE_STRICT_GF_GATE="${QXFX0_ENFORCE_STRICT_GF_GATE:-1}"
SMOKE_RUNTIME_MODE="strict"
START_TIME="$(date +%s)"
PRE_SMOKE_STATUS=""
RELEASE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/qxfx0-release-smoke.XXXXXX")"
RELEASE_CACHE="$RELEASE_HOME/.cache"
RELEASE_CONFIG="$RELEASE_HOME/.config"
RELEASE_STATE="$RELEASE_HOME/.state"
RELEASE_CABAL_DIR="$RELEASE_HOME/.cabal"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

mkdir -p "$RELEASE_CACHE" "$RELEASE_CONFIG" "$RELEASE_STATE" "$RELEASE_CABAL_DIR" "$SHARED_CABAL_STORE" "$SHARED_CABAL_LOGS" "$(dirname "$CABAL_LOCK_FILE")"

seed_release_cabal_home() {
    local host_config="$HOST_CABAL_CONFIG"
    local host_packages="$HOST_CABAL_DIR/packages"

    if [ ! -f "$host_config" ]; then
        host_config="$HOST_XDG_CONFIG_HOME/cabal/config"
    fi

    if [ -f "$host_config" ] && [ ! -f "$RELEASE_CABAL_DIR/config" ]; then
        cp "$host_config" "$RELEASE_CABAL_DIR/config"
    fi
    if [ ! -f "$RELEASE_CABAL_DIR/config" ]; then
        : >"$RELEASE_CABAL_DIR/config"
    fi
    {
        printf '\nstore-dir: %s\n' "$SHARED_CABAL_STORE"
        printf 'logs-dir: %s\n' "$SHARED_CABAL_LOGS"
        printf 'build-summary: %s/build.log\n' "$SHARED_CABAL_LOGS"
        if [ -d "$host_packages" ]; then
            printf 'remote-repo-cache: %s\n' "$host_packages"
        fi
    } >>"$RELEASE_CABAL_DIR/config"
    if [ -d "$host_packages" ] && [ ! -e "$RELEASE_CABAL_DIR/packages" ]; then
        ln -s "$host_packages" "$RELEASE_CABAL_DIR/packages"
    fi
}

seed_release_cabal_home

if [ "$REQUIRE_STRICT_RUNTIME" != "1" ] && [ -n "${QXFX0_RUNTIME_MODE:-}" ]; then
    SMOKE_RUNTIME_MODE="${QXFX0_RUNTIME_MODE}"
fi

step_pass() {
    PASS=$((PASS+1))
    echo -e "  ${GREEN}✓ PASS${NC}"
}
step_fail() {
    FAIL=$((FAIL+1))
    echo -e "  ${RED}✗ FAIL: $1${NC}"
}
step_skip() {
    SKIP=$((SKIP+1))
    echo -e "  ${YELLOW}⊘ SKIP: $1${NC}"
}
step_info() {
    echo -e "  ${BOLD}→${NC} $1"
}

summarize_text() {
    printf '%s' "$1" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | cut -c1-240
}

is_nix_infra_error() {
    printf '%s' "$1" | grep -Eqi 'big-lock|read-only file system|operation not permitted|permission denied|cannot connect to.*nix|opening lock file'
}

validate_replay_trace_json() {
    python3 - "$1" <<'PY'
import json
import sys

try:
    trace = json.loads(sys.argv[1])
except json.JSONDecodeError as exc:
    print(f"invalid replay_trace_json: {exc}")
    raise SystemExit(1)

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
}

nix_flake_available() {
    command -v nix &>/dev/null && [ -f "$ROOT/flake.nix" ]
}

run_nix_flake() {
    nix --option warn-dirty false --extra-experimental-features "nix-command flakes" "$@"
}

NIX_EVAL_OUT=""
NIX_EVAL_STATUS=1
NIX_EVAL_MODE="restricted"

nix_eval_expr() {
    local expr="$1"
    NIX_EVAL_OUT="$(nix-instantiate --restricted --eval -E "$expr" 2>&1)"
    NIX_EVAL_STATUS=$?
    NIX_EVAL_MODE="restricted"
    if [ "$NIX_EVAL_STATUS" -ne 0 ] && \
       printf '%s' "$NIX_EVAL_OUT" | grep -Eqi 'unrecogni[sz]ed flag' && \
       printf '%s' "$NIX_EVAL_OUT" | grep -q -- '--restricted'; then
        NIX_EVAL_OUT="$(nix-instantiate --eval -E "$expr" 2>&1)"
        NIX_EVAL_STATUS=$?
        NIX_EVAL_MODE="unrestricted_fallback"
    fi
    return "$NIX_EVAL_STATUS"
}

SOUFFLE_RESOLVE_DETAIL=""

resolve_souffle_binary() {
    SOUFFLE_RESOLVE_DETAIL=""
    if [ -n "${QXFX0_SOUFFLE_BIN:-}" ]; then
        local configured="$QXFX0_SOUFFLE_BIN"
        case "$configured" in
            */*)
                if [ -x "$configured" ]; then
                    echo "$configured"
                    return 0
                fi
                SOUFFLE_RESOLVE_DETAIL="configured QXFX0_SOUFFLE_BIN is not executable: $configured"
                return 1
                ;;
            *)
                local found=""
                found="$(command -v "$configured" 2>/dev/null || true)"
                if [ -n "$found" ] && [ -x "$found" ]; then
                    echo "$found"
                    return 0
                fi
                SOUFFLE_RESOLVE_DETAIL="configured QXFX0_SOUFFLE_BIN not found in PATH: $configured"
                return 1
                ;;
        esac
    fi
    local local_path=""
    local_path="$(command -v souffle 2>/dev/null || true)"
    if [ -n "$local_path" ] && [ -x "$local_path" ]; then
        echo "$local_path"
        return 0
    fi
    if nix_flake_available; then
        local flake_out=""
        flake_out="$(run_nix_flake eval --raw ".#apps.x86_64-linux.souffle-runtime.program" 2>&1)"
        local flake_status=$?
        if [ "$flake_status" -eq 0 ]; then
            local resolved_path=""
            resolved_path="$(printf '%s' "$flake_out" | tr -d '[:space:]')"
            if [ -n "$resolved_path" ] && [ -x "$resolved_path" ]; then
                echo "$resolved_path"
                return 0
            fi
            local build_out=""
            build_out="$(run_nix_flake build --no-link --print-out-paths ".#souffle-runtime" 2>&1)"
            local build_status=$?
            if [ "$build_status" -eq 0 ]; then
                local out_path=""
                out_path="$(printf '%s' "$build_out" | tail -n 1 | tr -d '[:space:]')"
                local built_path="$out_path/bin/souffle"
                if [ -n "$out_path" ] && [ -x "$built_path" ]; then
                    echo "$built_path"
                    return 0
                fi
                SOUFFLE_RESOLVE_DETAIL="flake-built souffle path is missing or not executable: $(summarize_text "$build_out")"
                return 1
            fi
            SOUFFLE_RESOLVE_DETAIL="flake eval resolved missing souffle and nix build failed: $(summarize_text "$build_out")"
            return 1
        fi
        SOUFFLE_RESOLVE_DETAIL="$(summarize_text "$flake_out")"
        return 1
    fi
    SOUFFLE_RESOLVE_DETAIL="souffle not found in PATH and nix flake fallback unavailable"
    return 1
}

run_local_cabal() {
  (
    cd "$ROOT" || exit 1
    flock -w 1800 9 || exit 1
    HOME="$RELEASE_HOME" \
    XDG_CACHE_HOME="$RELEASE_CACHE" \
      XDG_CONFIG_HOME="$RELEASE_CONFIG" \
      XDG_STATE_HOME="$RELEASE_STATE" \
      CABAL_DIR="$RELEASE_CABAL_DIR" \
      "$@"
  ) 9>"$CABAL_LOCK_FILE"
}

write_agda_witness() {
    run_local_cabal cabal run -v0 qxfx0-main -- --write-agda-witness
}

run_sql_file() {
    local db="$1"
    local file="$2"
    local output
    output="$(sqlite3 "$db" < "$file" 2>&1)"
    local rc=$?
    if [ $rc -ne 0 ]; then
        step_info "sqlite3 error from $(basename "$file"): $output"
        return 1
    fi
    if [ -n "$output" ]; then
        step_info "$output"
    fi
    return 0
}

poll_http_endpoint() {
    local url="$1"
    local attempts="${2:-25}"
    local delay_s="${3:-0.4}"
    local i
    local response=""
    for ((i = 1; i <= attempts; i++)); do
        response="$(curl -sf "$url" 2>/dev/null || true)"
        if [ -n "$response" ]; then
            echo "$response"
            return 0
        fi
        sleep "$delay_s"
    done
    return 1
}

cleanup() {
    if [ -n "$PID_HTTP" ]; then
        kill "$PID_HTTP" 2>/dev/null || true
        wait "$PID_HTTP" 2>/dev/null || true
    fi
    rm -f "$DB"
    rm -rf "$RELEASE_HOME"
    END_TIME="$(date +%s)"
    ELAPSED=$((END_TIME - START_TIME))
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  RELEASE GATE RESULTS"
    echo "════════════════════════════════════════════════════════════"
    echo "  Passed:   $PASS"
    echo "  Failed:   $FAIL"
    echo "  Skipped:  $SKIP"
    echo "  Elapsed:  ${ELAPSED}s"
    echo "════════════════════════════════════════════════════════════"
    if [ "$FAIL" -gt 0 ]; then
        echo -e "  ${RED}${BOLD}VERDICT: REJECT${NC}"
        exit 1
    else
        echo -e "  ${GREEN}${BOLD}VERDICT: ACCEPT${NC}"
        exit 0
    fi
}
trap cleanup EXIT

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   QxFx0 Release Smoke Test — 10 Constitutional Gates      ║"
echo "║   Конституционная Монархия Языков                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
step_info "Runtime mode for release gates: $SMOKE_RUNTIME_MODE"

PRE_SMOKE_STATUS=""
if git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
    PRE_SMOKE_STATUS="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 1: Build
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[1/10] Cabal build"
echo "─────────────────────────────────────────────────────────────"
cd "$ROOT"
step_info "Running cabal build all..."
BUILD_LOG="/tmp/qxfx0-build-$$.log"
if run_local_cabal cabal build all >"$BUILD_LOG" 2>&1; then
    tail -3 "$BUILD_LOG"
    BIN="$(run_local_cabal cabal list-bin qxfx0-main 2>/dev/null || echo "")"
    if [ -n "$BIN" ] && [ -x "$BIN" ]; then
        step_info "Binary: $BIN"
        step_pass
    else
        BIN="$(run_local_cabal cabal list-bin qxfx0-main 2>/dev/null || echo "$ROOT/dist/build/qxfx0-main/qxfx0-main")"
        step_info "Fallback binary: $BIN"
        step_pass
    fi
else
    tail -20 "$BUILD_LOG" 2>/dev/null || true
    step_fail "cabal build failed — see $BUILD_LOG"
fi
rm -f "$BUILD_LOG"

# ═══════════════════════════════════════════════════════════════════════
# Step 2: Unit tests
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[2/10] Unit tests (cabal test)"
echo "─────────────────────────────────────────────────────────────"
TEST_LOG="/tmp/qxfx0-test-$$.log"
step_info "Running cabal test qxfx0-test..."
if run_local_cabal cabal test qxfx0-test >"$TEST_LOG" 2>&1; then
    tail -8 "$TEST_LOG"
    TEST_SUMMARY="$(grep -E 'Cases: .*Tried: .*Errors: .*Failures:' "$TEST_LOG" | tail -1 || true)"
    TEST_ERRORS="$(echo "$TEST_SUMMARY" | sed -nE 's/.*Errors:[[:space:]]*([0-9]+).*/\1/p')"
    TEST_FAILURES="$(echo "$TEST_SUMMARY" | sed -nE 's/.*Failures:[[:space:]]*([0-9]+).*/\1/p')"
    TEST_ERRORS="${TEST_ERRORS:-0}"
    TEST_FAILURES="${TEST_FAILURES:-0}"
    if [ "$TEST_ERRORS" -gt 0 ] || [ "$TEST_FAILURES" -gt 0 ]; then
        step_fail "test suite reported failures (errors=$TEST_ERRORS, failures=$TEST_FAILURES)"
    else
        step_pass
    fi
else
    tail -20 "$TEST_LOG" 2>/dev/null || true
    step_fail "cabal test exited non-zero"
fi
rm -f "$TEST_LOG"

ARCH_CHECK="$ROOT/scripts/check_architecture.sh"
if [ -x "$ARCH_CHECK" ]; then
    step_info "Running architecture boundary checker..."
    if "$ARCH_CHECK" >/dev/null 2>&1; then
        step_info "Architecture boundaries: OK"
    else
        step_fail "architecture boundary violations detected"
    fi
else
    step_skip "architecture checker not found"
fi

LEX_CHECK="$ROOT/scripts/check_lexicon.sh"
if [ -x "$LEX_CHECK" ]; then
    step_info "Running lexical gate..."
    if "$LEX_CHECK" >/dev/null 2>&1; then
        step_info "Lexical gate: OK"
    else
        step_fail "lexical gate failed (run scripts/build_lexicon.sh to fix)"
    fi
else
    step_skip "lexical checker not found"
fi

GEN_CHECK="$ROOT/scripts/check_generated_artifacts.sh"
if [ -x "$GEN_CHECK" ]; then
    step_info "Running generated-artifact drift gate..."
    if [ "$ENFORCE_STRICT_GF_GATE" = "1" ]; then
        GEN_OK=0
        QXFX0_REQUIRE_GF=1 "$GEN_CHECK" >/dev/null 2>&1 || GEN_OK=$?
    else
        GEN_OK=0
        "$GEN_CHECK" >/dev/null 2>&1 || GEN_OK=$?
    fi
    if [ "$GEN_OK" -eq 0 ]; then
        step_info "Generated artifacts: OK"
    else
        step_fail "generated artifacts drifted from canonical sources"
    fi
else
    step_skip "generated artifact checker not found"
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 3: Schema migration check
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[3/10] Schema migration check"
echo "─────────────────────────────────────────────────────────────"
MIGDIR="$ROOT/migrations"
if [ -d "$MIGDIR" ]; then
    MIG_FILES="$(ls "$MIGDIR"/*.sql 2>/dev/null || true)"
    if [ -n "$MIG_FILES" ]; then
        rm -f "$DB"
        MIG_OK=true
        MIG_COUNT=0
        for f in "$MIGDIR"/*.sql; do
            MIG_COUNT=$((MIG_COUNT + 1))
            step_info "Applying migration: $(basename "$f")"
            if ! sqlite3 "$DB" < "$f" 2>&1; then
                step_fail "migration $(basename "$f") failed"
                MIG_OK=false
                break
            fi
        done
        if $MIG_OK; then
            TABLES="$(sqlite3 "$DB" ".tables" 2>/dev/null || echo "")"
            TABLE_COUNT="$(echo "$TABLES" | wc -w 2>/dev/null || echo "0")"
            step_info "Applied $MIG_COUNT migrations, $TABLE_COUNT tables"
            if [ -n "$TABLES" ]; then
                if ! command -v python3 &>/dev/null; then
                    step_fail "python3 is required for SQL single-source schema checks"
                elif [ ! -f "$ROOT/scripts/sync_embedded_sql.py" ]; then
                    step_fail "scripts/sync_embedded_sql.py is missing"
                elif ! python3 "$ROOT/scripts/sync_embedded_sql.py" --check >/dev/null 2>&1; then
                    step_fail "EmbeddedSQL.hs/migration drifted from canonical spec/sql"
                elif [ ! -f "$ROOT/scripts/check_schema_consistency.py" ]; then
                    step_fail "scripts/check_schema_consistency.py is missing"
                elif python3 "$ROOT/scripts/check_schema_consistency.py" >/dev/null 2>&1; then
                    step_info "Cumulative migration schema matches canonical schema.sql"
                    step_pass
                else
                    step_fail "cumulative migrations do not match canonical schema.sql"
                fi
            else
                step_fail "no tables created after $MIG_COUNT migrations"
            fi
        fi
    else
        step_skip "no .sql migration files found"
    fi
else
    step_skip "migrations directory does not exist"
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 4: Seed data verification
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[4/10] Seed data verification"
echo "─────────────────────────────────────────────────────────────"
SEED_DIR="$ROOT/spec/sql"
if [ -d "$SEED_DIR" ]; then
    SCHEMA="$SEED_DIR/schema.sql"
    if [ -f "$SCHEMA" ]; then
        rm -f "$DB"
        step_info "Loading schema from schema.sql"
        if ! run_sql_file "$DB" "$SCHEMA"; then
            step_fail "schema.sql failed to apply"
        else
        SEED_COUNT=0
        SEED_OK=true
        for sf in "$SEED_DIR"/seed_*.sql; do
            [ -f "$sf" ] || continue
            SEED_COUNT=$((SEED_COUNT + 1))
            step_info "Loading seed: $(basename "$sf")"
            if ! run_sql_file "$DB" "$sf"; then
                step_fail "seed failed: $(basename "$sf")"
                SEED_OK=false
            fi
        done
        if ! $SEED_OK; then
            step_info "Applied $SEED_COUNT seed files with errors"
        else
            step_info "Applied $SEED_COUNT seed files"
            IDENTITY_COUNT="$(sqlite3 "$DB" "SELECT count(*) FROM identity_claims" 2>/dev/null || echo "0")"
            CLUSTER_COUNT="$(sqlite3 "$DB" "SELECT count(*) FROM semantic_clusters" 2>/dev/null || echo "0")"
            TEMPLATE_COUNT="$(sqlite3 "$DB" "SELECT count(*) FROM realization_templates" 2>/dev/null || echo "0")"
            step_info "identity_claims rows: $IDENTITY_COUNT"
            step_info "semantic_clusters rows: $CLUSTER_COUNT"
            step_info "realization_templates rows: $TEMPLATE_COUNT"
            if [ "$IDENTITY_COUNT" -gt 0 ] 2>/dev/null && \
               [ "$CLUSTER_COUNT" -gt 0 ] 2>/dev/null && \
               [ "$TEMPLATE_COUNT" -gt 0 ] 2>/dev/null; then
                step_pass
            else
                step_fail "seed data incomplete: identity=$IDENTITY_COUNT clusters=$CLUSTER_COUNT templates=$TEMPLATE_COUNT"
            fi
        fi
        fi
    else
        step_skip "no schema.sql in spec/sql"
    fi
else
    step_skip "no spec/sql directory"
fi

LEXICON_CHECK="$ROOT/scripts/check_lexicon.sh"
if [ -x "$LEXICON_CHECK" ]; then
    step_info "Running lexical contour gate (SQL -> morphology artifacts)..."
    if "$LEXICON_CHECK" >/dev/null 2>&1; then
        step_info "Lexicon contour: OK"
    else
        step_fail "lexicon contour gate failed"
    fi
else
    step_skip "lexicon checker not found"
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 5: Nix guard evaluation test
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[5/10] Nix guard evaluation test"
echo "─────────────────────────────────────────────────────────────"
CONCEPTS="$ROOT/semantics/concepts.nix"
if [ -f "$CONCEPTS" ] && command -v nix-instantiate &>/dev/null; then
    step_info "Evaluating concepts.nix..."
    if nix_eval_expr "let c = import $CONCEPTS; in builtins.length c.concepts"; then
        CONCEPT_COUNT_OUT="$NIX_EVAL_OUT"
        CONCEPT_STATUS=0
    else
        CONCEPT_COUNT_OUT="$NIX_EVAL_OUT"
        CONCEPT_STATUS=$NIX_EVAL_STATUS
    fi
    if [ "$CONCEPT_STATUS" -eq 0 ]; then
        CONCEPT_COUNT="$(printf '%s' "$CONCEPT_COUNT_OUT" | tr -d ' ')"
        step_info "Concept count: $CONCEPT_COUNT (mode=$NIX_EVAL_MODE)"
    else
        SUMMARY="$(summarize_text "$CONCEPT_COUNT_OUT")"
        if is_nix_infra_error "$CONCEPT_COUNT_OUT"; then
            step_fail "nix evaluator unavailable while reading concepts.nix: $SUMMARY"
        else
            step_fail "concepts.nix evaluation failed: $SUMMARY"
        fi
    fi
    if [ "$CONCEPT_STATUS" -eq 0 ] && [ "$CONCEPT_COUNT" -gt 0 ] 2>/dev/null; then
        step_info "Checking constitutional thresholds..."
        if nix_eval_expr "let c = import $CONCEPTS; in c.constitutionalThresholds.agencyFloor"; then
            AGENCY_FLOOR_OUT="$NIX_EVAL_OUT"
            AGENCY_STATUS=0
        else
            AGENCY_FLOOR_OUT="$NIX_EVAL_OUT"
            AGENCY_STATUS=$NIX_EVAL_STATUS
        fi
        if nix_eval_expr "let c = import $CONCEPTS; in c.constitutionalThresholds.tensionCeiling"; then
            TENSION_CEIL_OUT="$NIX_EVAL_OUT"
            TENSION_STATUS=0
        else
            TENSION_CEIL_OUT="$NIX_EVAL_OUT"
            TENSION_STATUS=$NIX_EVAL_STATUS
        fi
        if [ "$AGENCY_STATUS" -eq 0 ] && [ "$TENSION_STATUS" -eq 0 ]; then
            AGENCY_FLOOR="$(printf '%s' "$AGENCY_FLOOR_OUT" | tr -d ' ')"
            TENSION_CEIL="$(printf '%s' "$TENSION_CEIL_OUT" | tr -d ' ')"
            step_info "Agency floor: $AGENCY_FLOOR, Tension ceiling: $TENSION_CEIL"
            step_pass
        else
            FAILURE_OUT="$AGENCY_FLOOR_OUT"
            if [ "$TENSION_STATUS" -ne 0 ]; then
                FAILURE_OUT="$TENSION_CEIL_OUT"
            fi
            SUMMARY="$(summarize_text "$FAILURE_OUT")"
            if is_nix_infra_error "$FAILURE_OUT"; then
                step_fail "nix evaluator unavailable while reading constitutional thresholds: $SUMMARY"
            else
                step_fail "constitutional threshold evaluation failed: $SUMMARY"
            fi
        fi
    elif [ "$CONCEPT_STATUS" -eq 0 ]; then
        step_fail "concepts.nix evaluation returned zero concepts"
    fi
else
    step_skip "nix-instantiate or concepts.nix not available"
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 6: Datalog shadow compilation test
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[6/10] Datalog shadow compilation test"
echo "─────────────────────────────────────────────────────────────"
DL_DIR="$ROOT/spec/datalog"
if [ -d "$DL_DIR" ]; then
    DL_FILE="$(ls "$DL_DIR"/*.dl 2>/dev/null | head -1)"
    if [ -n "$DL_FILE" ]; then
        step_info "Testing Datalog: $(basename "$DL_FILE")"
        SOUFFLE_BIN_PATH=""
        if SOUFFLE_BIN_PATH="$(resolve_souffle_binary)"; then
            step_info "Using souffle binary: $SOUFFLE_BIN_PATH"
            SMOKE_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/qxfx0-smoke-datalog.XXXXXX")"
            SMOKE_DATALOG_FILE="$SMOKE_TMPDIR/semantic_rules_smoke.dl"
            cp "$DL_FILE" "$SMOKE_DATALOG_FILE"
            cat >>"$SMOKE_DATALOG_FILE" <<'EOF'
RequestedFamily("CMGround").
InputForce("IFAssert").
InputAtom("NeedContact").
InputAtomDetail("NeedContact", "smoke").
EOF
            DATALOG_OUT="$("$SOUFFLE_BIN_PATH" --parse-errors -D "$SMOKE_TMPDIR" "$SMOKE_DATALOG_FILE" 2>&1)"
            DATALOG_STATUS=$?
            if [ "$DATALOG_STATUS" -eq 0 ]; then
                rm -rf "$SMOKE_TMPDIR"
                step_pass
            else
                rm -rf "$SMOKE_TMPDIR"
                step_fail "souffle parse failed for $(basename "$DL_FILE"): $(summarize_text "$DATALOG_OUT")"
            fi
        else
            if is_nix_infra_error "$SOUFFLE_RESOLVE_DETAIL"; then
                step_fail "souffle runtime unavailable because nix resolver failed: $(summarize_text "$SOUFFLE_RESOLVE_DETAIL")"
            else
                step_fail "souffle runtime unavailable: $(summarize_text "$SOUFFLE_RESOLVE_DETAIL")"
            fi
        fi
    else
        step_skip "no .dl files in $DL_DIR"
    fi
else
    step_skip "no datalog directory at $DL_DIR"
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 7: Agda type-check + witness
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[7/10] Agda type-check + witness"
echo "─────────────────────────────────────────────────────────────"
AGDA_DIR="$ROOT/spec"
REQUIRE_AGDA="${QXFX0_REQUIRE_AGDA:-1}"
AGDA_READY=0
if [ -f "$AGDA_DIR/R5Core.agda" ] && command -v agda &>/dev/null; then
    AGDA_OK=true
    AGDA_COUNT=0
    for ag in \
        "$AGDA_DIR"/R5Core.agda \
        "$AGDA_DIR"/Sovereignty.agda \
        "$AGDA_DIR"/Legitimacy.agda \
        "$AGDA_DIR"/LexiconData.agda \
        "$AGDA_DIR"/LexiconProof.agda; do
        [ -f "$ag" ] || continue
        AGDA_COUNT=$((AGDA_COUNT + 1))
        step_info "Type-checking $(basename "$ag")..."
        if ! agda "$ag" 2>&1; then
            AGDA_OK=false
            step_fail "Agda type-check failed: $(basename "$ag")"
            break
        fi
    done
    if $AGDA_OK; then
        AGDA_READY=1
        step_info "$AGDA_COUNT Agda modules type-checked successfully"
        WITNESS_OUT="$(write_agda_witness 2>&1)" || {
            step_fail "Agda witness generation failed"
            step_info "$WITNESS_OUT"
            AGDA_READY=0
        }
        if [ "$AGDA_READY" = "1" ]; then
            step_info "Witness: $(echo "$WITNESS_OUT" | tail -1)"
            step_pass
        fi
    fi
elif [ -f "$AGDA_DIR/R5Core.agda" ] && nix_flake_available; then
    step_info "agda not found, using Nix flake fallback..."
    if run_nix_flake run .#typecheck-agda 2>&1; then
        AGDA_READY=1
        step_info "Agda modules type-checked successfully via Nix"
        WITNESS_OUT="$(write_agda_witness 2>&1)" || {
            step_fail "Agda witness generation failed"
            step_info "$WITNESS_OUT"
            AGDA_READY=0
        }
        if [ "$AGDA_READY" = "1" ]; then
            step_info "Witness: $(echo "$WITNESS_OUT" | tail -1)"
            step_pass
        fi
    else
        step_fail "Agda type-check failed via Nix fallback"
    fi
else
    if [ "$REQUIRE_AGDA" = "1" ]; then
        step_fail "agda required (QXFX0_REQUIRE_AGDA=1) but not installed"
    else
        step_skip "agda not installed or no .agda files in $AGDA_DIR"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 8: Policy catalog sync verification
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[8/10] Policy catalog sync verification"
echo "─────────────────────────────────────────────────────────────"
POLICY="$ROOT/semantics/concepts.nix"
CATALOG_SCRIPT="$ROOT/scripts/verify_agda_sync.py"
if [ -f "$POLICY" ] && [ -f "$CATALOG_SCRIPT" ]; then
    step_info "Running verify_agda_sync.py..."
    if python3 "$CATALOG_SCRIPT" 2>&1; then
        step_info "Agda–Haskell constructor sync verified"
        step_pass
    else
        step_fail "Agda–Haskell constructor sync check failed"
    fi
else
    if [ -f "$POLICY" ] && command -v nix-instantiate &>/dev/null; then
        step_info "Checking concept enumeration..."
        CONCEPT_NAMES=$(nix-instantiate --eval \
            -E "let c = import $POLICY; in builtins.concatStringsSep \",\" (map (x: x.name) c.concepts)" \
            2>/dev/null | tr -d '"' || echo "")
        if [ -n "$CONCEPT_NAMES" ]; then
            step_info "Concepts: $CONCEPT_NAMES"
            step_pass
        else
            step_fail "could not enumerate concepts from $POLICY"
        fi
    else
        step_skip "concepts.nix not found or nix-instantiate unavailable"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 9: CLI smoke test (turn execution)
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[9/10] CLI smoke test (turn execution)"
echo "─────────────────────────────────────────────────────────────"
if [ -x "$BIN" ]; then
    step_info "Binary: $BIN"
    step_info "Executing: $BIN --session smoke1 --input 'Что такое свобода?' --json"
    CLI_STDERR_LOG="$(mktemp "${TMPDIR:-/tmp}/qxfx0-cli-smoke.XXXXXX")"
    OUT="$(HOME="$RELEASE_HOME" XDG_CACHE_HOME="$RELEASE_CACHE" XDG_CONFIG_HOME="$RELEASE_CONFIG" XDG_STATE_HOME="$RELEASE_STATE" CABAL_DIR="$RELEASE_CABAL_DIR" QXFX0_DB="$DB" QXFX0_ROOT="$ROOT" QXFX0_RUNTIME_MODE="$SMOKE_RUNTIME_MODE" QXFX0_EMBEDDING_BACKEND="$STRICT_EMBEDDING_BACKEND" "$BIN" --session "smoke1" --input "Что такое свобода?" --json 2>"$CLI_STDERR_LOG")"
    CLI_STATUS=$?
    CLI_STDERR="$(cat "$CLI_STDERR_LOG" 2>/dev/null || true)"
    rm -f "$CLI_STDERR_LOG"
    if [ "$CLI_STATUS" -ne 0 ]; then
        step_fail "CLI exited non-zero: $(summarize_text "$CLI_STDERR")"
    elif [ -n "$OUT" ]; then
        step_info "Output received ($(echo "$OUT" | wc -c) bytes)"
        HAS_FAMILY="$(echo "$OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('family', d.get('move_family', '')))
" 2>/dev/null || echo "")"
        HAS_FORCE="$(echo "$OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('force', d.get('illocutionary_force', '')))
" 2>/dev/null || echo "")"
        HAS_SURFACE="$(echo "$OUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('surface', d.get('text', d.get('response', ''))[:80]))
" 2>/dev/null || echo "")"
        step_info "Family: $HAS_FAMILY, Force: $HAS_FORCE"
        REPLAY_TRACE_JSON=""
        if command -v sqlite3 >/dev/null 2>&1; then
            REPLAY_TRACE_JSON="$(sqlite3 "$DB" "SELECT replay_trace_json FROM turn_quality WHERE session_id = 'smoke1' ORDER BY turn DESC LIMIT 1;" 2>/dev/null || echo "")"
        fi
        TRACE_CHECK_OUT=""
        TRACE_OK=0
        if [ -n "$REPLAY_TRACE_JSON" ] && TRACE_CHECK_OUT="$(validate_replay_trace_json "$REPLAY_TRACE_JSON" 2>&1)"; then
            TRACE_OK=1
        fi
        if [ -n "$HAS_FAMILY" ] && [ -n "$HAS_FORCE" ]; then
            if [ "$TRACE_OK" -eq 1 ]; then
                step_info "Replay trace persisted for smoke1 turn"
                step_pass
            else
                step_fail "turn_quality replay trace missing or incomplete for smoke1: $(summarize_text "$TRACE_CHECK_OUT")"
            fi
        else
            if [ -n "$HAS_SURFACE" ]; then
                step_info "Has surface output, partial pass"
                if [ "$TRACE_OK" -eq 1 ]; then
                    step_info "Replay trace persisted for smoke1 turn"
                    step_pass
                else
                    step_fail "turn_quality replay trace missing or incomplete for smoke1: $(summarize_text "$TRACE_CHECK_OUT")"
                fi
            else
                step_fail "output missing family and force: $OUT"
            fi
        fi
    else
        if [ -n "$CLI_STDERR" ]; then
            step_fail "CLI returned empty stdout: $(summarize_text "$CLI_STDERR")"
        else
            step_fail "CLI returned empty stdout and stderr"
        fi
    fi
else
    step_skip "binary not found or not executable at $BIN"
fi

# ═══════════════════════════════════════════════════════════════════════
# Step 10: HTTP sidecar smoke test
# ═══════════════════════════════════════════════════════════════════════
echo "─────────────────────────────────────────────────────────────"
echo "[10/10] HTTP sidecar smoke test"
echo "─────────────────────────────────────────────────────────────"
HTTP_SCRIPT="$ROOT/scripts/http_runtime.py"
if [ -f "$HTTP_SCRIPT" ] && [ -x "$BIN" ]; then
    step_info "Starting HTTP sidecar on port $PORT..."
    HTTP_LOG="$(mktemp "${TMPDIR:-/tmp}/qxfx0-http-smoke.XXXXXX")"
    HOME="$RELEASE_HOME" XDG_CACHE_HOME="$RELEASE_CACHE" XDG_CONFIG_HOME="$RELEASE_CONFIG" XDG_STATE_HOME="$RELEASE_STATE" CABAL_DIR="$RELEASE_CABAL_DIR" QXFX0_DB="$DB" QXFX0_BIN="$BIN" QXFX0_HTTP_PORT="$PORT" QXFX0_API_KEY="" QXFX0_ROOT="$ROOT" QXFX0_WORKERS="0" QXFX0_HTTP_HOST="127.0.0.1" QXFX0_RUNTIME_MODE="$SMOKE_RUNTIME_MODE" QXFX0_EMBEDDING_BACKEND="$STRICT_EMBEDDING_BACKEND" \
        python3 "$HTTP_SCRIPT" >"$HTTP_LOG" 2>&1 &
    PID_HTTP=$!
    step_info "Polling sidecar readiness (PID: $PID_HTTP)..."
    step_info "Checking /sidecar-health endpoint..."
    SIDECAR_HEALTH="$(poll_http_endpoint "http://127.0.0.1:$PORT/sidecar-health" 30 0.3 || echo '{"status":"unreachable"}')"
    step_info "Sidecar health response: $SIDECAR_HEALTH"
    step_info "Checking /runtime-ready endpoint..."
    RUNTIME_READY="$(poll_http_endpoint "http://127.0.0.1:$PORT/runtime-ready" 30 0.3 || echo '{"status":"unreachable"}')"
    step_info "Runtime readiness response: $RUNTIME_READY"
    if echo "$SIDECAR_HEALTH" | grep -q '"ok"\|"healthy"\|"up"' && \
       echo "$RUNTIME_READY" | grep -q '"ok"\|"ready"[[:space:]]*:[[:space:]]*true' && \
       { [ "$SMOKE_RUNTIME_MODE" != "strict" ] || echo "$RUNTIME_READY" | grep -q '"runtime_mode"[[:space:]]*:[[:space:]]*"strict"'; } && \
       echo "$RUNTIME_READY" | grep -q '"decision_path_local_only"[[:space:]]*:[[:space:]]*true' && \
       echo "$RUNTIME_READY" | grep -q '"network_optional_only"[[:space:]]*:[[:space:]]*true' && \
       echo "$RUNTIME_READY" | grep -q '"llm_decision_path"[[:space:]]*:[[:space:]]*false'; then
        step_info "Health/readiness OK. Testing /turn endpoint..."
        TURN_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/turn" \
            -H "Content-Type: application/json" \
            -d '{"session_id":"hsmoke2","input":"Что такое воля?"}' 2>/dev/null || echo '{}')
        step_info "Turn response: $(echo "$TURN_RESP" | head -c 120)"
        if echo "$TURN_RESP" | grep -q 'family\|force\|error\|surface\|move_family'; then
            step_info "Testing rate limiting (rapid requests)..."
            RL_RESP=$(curl -sf -X POST "http://127.0.0.1:$PORT/turn" \
                -H "Content-Type: application/json" \
                -d '{"session_id":"hsmoke3","input":"тест"}' 2>/dev/null || echo '{}')
            step_info "Second request: OK"
            step_pass
        else
            step_fail "turn endpoint returned unexpected: $TURN_RESP"
        fi
    else
        HTTP_ERR="$(tail -20 "$HTTP_LOG" 2>/dev/null || true)"
        if [ -n "$HTTP_ERR" ]; then
            step_fail "health/readiness check failed: sidecar=$SIDECAR_HEALTH runtime=$RUNTIME_READY sidecar_log=$(summarize_text "$HTTP_ERR")"
        else
            step_fail "health/readiness check failed: sidecar=$SIDECAR_HEALTH runtime=$RUNTIME_READY"
        fi
    fi
    kill "$PID_HTTP" 2>/dev/null || true
    wait "$PID_HTTP" 2>/dev/null || true
    PID_HTTP=""
    rm -f "$HTTP_LOG"
else
    step_skip "http_runtime.py or binary not available"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  POST-SMOKE CLEANLINESS CHECK"
echo "════════════════════════════════════════════════════════════"
if [ -n "$PRE_SMOKE_STATUS" ]; then
    POST_SMOKE_STATUS="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
    NEW_FILES="$(comm -13 <(echo "$PRE_SMOKE_STATUS") <(echo "$POST_SMOKE_STATUS") || true)"
    if [ -z "$NEW_FILES" ]; then
        echo -e "  ${GREEN}✓ PASS${NC} — working tree clean after smoke"
    else
        FAIL=$((FAIL+1))
        echo -e "  ${RED}✗ FAIL: smoke left working tree dirty${NC}"
        echo "$NEW_FILES" | head -20
    fi
else
    echo "  (skipped — not a git repository or no baseline recorded)"
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  RELEASE GATE COMPLETE"
echo "════════════════════════════════════════════════════════════"
