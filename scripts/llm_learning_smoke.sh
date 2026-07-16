#!/usr/bin/env bash
set -euo pipefail

# QxFx0 LLM self-learning smoke test
# Runs the full autonomous-learning cycle end-to-end with a real LLM:
#   suggest -> discover -> autonomous-smoke -> contradictions -> resolve -> replay
# Prints before/after metrics and exits non-zero on failure.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${QXFX0_LLM_ENV:-$HOME/.config/qxfx0/cerebras.env}"
DB_PATH="${QXFX0_DB_PATH:-$HOME/.local/state/qxfx0/qxfx0.db}"

AUTONOMOUS_TOPICS="${QXFX0_AUTONOMOUS_TOPICS:-свобода ответственность справедливость}"

info() { echo "[llm-learning-smoke] $*"; }
warn() { echo "[llm-learning-smoke] WARN: $*" >&2; }
fail() { echo "[llm-learning-smoke] FAIL: $*" >&2; exit 1; }

if [ ! -f "$ENV_FILE" ]; then
  fail "LLM env file not found: $ENV_FILE"
fi

# shellcheck source=/dev/null
set -a
. "$ENV_FILE"
set +a

cd "$ROOT"

info "building executable..."
cabal build exe:qxfx0-main >/dev/null 2>&1 || fail "failed to build exe:qxfx0-main"

QXFX0="cabal run exe:qxfx0-main --"

# Helper: count rows in a SQLite table.
db_count() {
  local table="$1"
  sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM $table;" 2>/dev/null
}

info "baseline metrics"
BEFORE_EDGES=$(db_count semantic_edges_runtime)
BEFORE_EVENTS=$(db_count learning_events)
info "  runtime edges: $BEFORE_EDGES"
info "  learning events: $BEFORE_EVENTS"

info "1/5 coverage-gap driven discovery"
SUGGEST_OUT=$($QXFX0 --suggest-discoveries 5 2>/dev/null)
TOPIC=$(echo "$SUGGEST_OUT" | awk -F'|' '/^[^-[:space:]]/ && NF>=4 && $0 !~ /From \| To \| Score \| Reason/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1; exit}')
if [ -z "$TOPIC" ]; then
  fail "could not parse top suggestion"
fi
info "  top suggested concept: $TOPIC"

$QXFX0 --discover "$TOPIC" >/dev/null 2>&1 || fail "--discover $TOPIC failed"

info "2/5 autonomous smoke tests"
for topic in $AUTONOMOUS_TOPICS; do
  $QXFX0 --autonomous-smoke "$topic" >/dev/null 2>&1 || fail "--autonomous-smoke $topic failed"
  info "  --autonomous-smoke $topic: ok"
done

info "3/5 contradiction lifecycle"
# Inject a human correction that is likely to contradict an existing LLM edge.
$QXFX0 --human-correction test свобода долг >/dev/null 2>&1 || fail "--human-correction failed"
$QXFX0 --contradictions >/dev/null 2>&1 || fail "--contradictions failed"
$QXFX0 --resolve-contradictions >/dev/null 2>&1 || fail "--resolve-contradictions failed"

info "4/5 replay determinism"
$QXFX0 --replay-learning-projection >/dev/null 2>&1 || fail "--replay-learning-projection failed"

info "5/5 final metrics"
AFTER_EDGES=$(db_count semantic_edges_runtime)
AFTER_EVENTS=$(db_count learning_events)
info "  runtime edges: $AFTER_EDGES (delta: $((AFTER_EDGES - BEFORE_EDGES)))"
info "  learning events: $AFTER_EVENTS (delta: $((AFTER_EVENTS - BEFORE_EVENTS)))"

if [ "$AFTER_EDGES" -le "$BEFORE_EDGES" ] && [ "$AFTER_EVENTS" -le "$BEFORE_EVENTS" ]; then
  warn "no new edges or events were produced"
fi

info "LLM self-learning smoke test completed successfully"
