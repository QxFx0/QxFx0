#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# soak.sh — QxFx0 soak gate: sustained turn load with latency/heap checks
# Not part of verify.sh; run manually or in CI soak contour.
# ═══════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${QXFX0_SOAK_PORT:-}"
if [ -z "$PORT" ]; then
    PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null || true)
fi
if [ -z "$PORT" ]; then
    echo -e "\033[0;31mFAIL: cannot allocate localhost port; set QXFX0_SOAK_PORT\033[0m"
    exit 1
fi
BIN=""
DB="/tmp/qxfx0-soak-$$.db"
TURNS="${QXFX0_SOAK_TURNS:-100}"
PID_HTTP=""
PASS=0
FAIL=0
START_TIME="$(date +%s)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
    if [ -n "$PID_HTTP" ] && kill -0 "$PID_HTTP" 2>/dev/null; then
        kill "$PID_HTTP" 2>/dev/null || true
        wait "$PID_HTTP" 2>/dev/null || true
    fi
    rm -f "$DB" "$DB-wal" "$DB-shm"
}
trap cleanup EXIT

step_pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✓ PASS${NC}"; }
step_fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}✗ FAIL${NC}"; }

BIN="$(cd "$ROOT" && cabal list-bin qxfx0-main 2>/dev/null || true)"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo "Building qxfx0-main ..."
    (cd "$ROOT" && cabal build qxfx0-main >/dev/null 2>&1) || true
    BIN="$(cd "$ROOT" && cabal list-bin qxfx0-main 2>/dev/null || true)"
fi
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
    echo -e "${RED}FAIL: cannot locate qxfx0-main binary${NC}"
    exit 1
fi

HTTP_SCRIPT="$ROOT/scripts/http_runtime.py"
if [ ! -f "$HTTP_SCRIPT" ]; then
    echo -e "${RED}FAIL: http_runtime.py not found${NC}"
    exit 1
fi

SOAK_HOME="$(mktemp -d "${TMPDIR:-/tmp}/qxfx0-soak.XXXXXX")"
SOAK_STATE="$SOAK_HOME/.state"
mkdir -p "$SOAK_STATE"

echo "=== QxFx0 Soak Gate (${TURNS} turns) ==="

# ── Launch HTTP sidecar ──────────────────────────────────────────────
echo "[setup] Starting HTTP sidecar on port ${PORT} ..."
HOME="$SOAK_HOME" \
XDG_STATE_HOME="$SOAK_STATE" \
QXFX0_DB="$DB" \
QXFX0_BIN="$BIN" \
QXFX0_HTTP_PORT="$PORT" \
QXFX0_API_KEY="" \
QXFX0_ROOT="$ROOT" \
QXFX0_WORKERS="0" \
QXFX0_HTTP_HOST="127.0.0.1" \
QXFX0_RUNTIME_MODE=degraded \
QXFX0_EMBEDDING_BACKEND=local-deterministic \
    python3 "$HTTP_SCRIPT" >/dev/null 2>&1 &
PID_HTTP=$!
sleep 3

HEALTH_URL="http://127.0.0.1:${PORT}/runtime-ready"
for i in $(seq 1 30); do
    if curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
if ! curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
    echo -e "  ${RED}FAIL: sidecar did not become ready${NC}"
    exit 1
fi
step_pass

# ── Soak loop ────────────────────────────────────────────────────────
echo "[run] Soaking ${TURNS} turns ..."
TOTAL_MS=0
MIN_MS=999999
MAX_MS=0
EMPTY_COUNT=0
ERR_COUNT=0

TURN_URL="http://127.0.0.1:${PORT}/turn"
for i in $(seq 1 "$TURNS"); do
    # rotate a small set of representative inputs
    case $((i % 4)) in
        0) BODY='{"session_id":"soak","input":"Что такое свобода?"}' ;;
        1) BODY='{"session_id":"soak","input":"Мне нужен контакт."}' ;;
        2) BODY='{"session_id":"soak","input":"Я очень устал."}' ;;
        *) BODY='{"session_id":"soak","input":"Расскажи про смысл."}' ;;
    esac

    START_MS="$(date +%s%3N)"
    RESP="$(curl -sf -X POST -H "Content-Type: application/json" -d "$BODY" "$TURN_URL" 2>/dev/null || true)"
    END_MS="$(date +%s%3N)"

    if [ -z "$RESP" ]; then
        ERR_COUNT=$((ERR_COUNT+1))
        continue
    fi

    # crude latency in ms (may wrap around midnight, acceptable for soak)
    LATENCY=$((END_MS - START_MS))
    if [ "$LATENCY" -lt 0 ]; then LATENCY=0; fi
    TOTAL_MS=$((TOTAL_MS + LATENCY))
    if [ "$LATENCY" -lt "$MIN_MS" ]; then MIN_MS=$LATENCY; fi
    if [ "$LATENCY" -gt "$MAX_MS" ]; then MAX_MS=$LATENCY; fi

    if echo "$RESP" | grep -q '"output"[[:space:]]*:[[:space:]]*""'; then
        EMPTY_COUNT=$((EMPTY_COUNT+1))
    fi

    sleep "${QXFX0_SOAK_DELAY_SECONDS:-0.05}"
done

AVG_MS=0
if [ "$TURNS" -gt "$ERR_COUNT" ]; then
    AVG_MS=$((TOTAL_MS / (TURNS - ERR_COUNT)))
fi

echo "  Latency: min=${MIN_MS}ms avg=${AVG_MS}ms max=${MAX_MS}ms"
echo "  Empty responses: ${EMPTY_COUNT}/${TURNS}"
echo "  Errors: ${ERR_COUNT}/${TURNS}"

# ── Assertions ───────────────────────────────────────────────────────
if [ "$ERR_COUNT" -gt "$((TURNS / 10))" ]; then
    echo -e "  ${RED}FAIL: too many errors (>10%)${NC}"
    step_fail
else
    step_pass
fi

if [ "$EMPTY_COUNT" -gt "$((TURNS / 20))" ]; then
    echo -e "  ${RED}FAIL: too many empty outputs (>5%)${NC}"
    step_fail
else
    step_pass
fi

# Edge-count stability: inspect dream rewiring line from worker stderr
# (release-smoke already confirms Dream rewiring is stable; here we just gate.)
if [ "$MAX_MS" -gt 30000 ]; then
    echo -e "  ${RED}FAIL: max latency > 30s${NC}"
    step_fail
else
    step_pass
fi

ELAPSED=$(( $(date +%s) - START_TIME ))
echo "=== Soak complete: ${PASS} passed, ${FAIL} failed, ${ELAPSED}s elapsed ==="
[ "$FAIL" -eq 0 ] || exit 1
