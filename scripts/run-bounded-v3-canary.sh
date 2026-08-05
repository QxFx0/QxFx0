#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${QXFX0_STATE_DIR:-$HOME/.local/state/qxfx0}"
DB="${QXFX0_CANARY_DB:-$STATE_DIR/qxfx0.db}"
BACKUP_DIR="$STATE_DIR/backups"
PROVIDER_ENV="${QXFX0_PROVIDER_ENV:-$HOME/.config/qxfx0/cerebras.env}"
MONITOR_SCRIPT="$ROOT_DIR/scripts/autonomous-canary-monitor.sh"
CYCLES="${QXFX0_CANARY_CYCLES:-4}"
CYCLE_SECONDS="${QXFX0_CANARY_CYCLE_SECONDS:-90}"
INTERVAL_SEC="${QXFX0_CANARY_MONITOR_INTERVAL_SEC:-1800}"

die() {
  printf 'canary launch refused: %s\n' "$*" >&2
  exit 1
}

processes_matching() {
  local exact_name="$1"
  local anchored_pattern="$2"
  local exact_pids pattern_pids
  exact_pids="$(pgrep -x "$exact_name" 2>/dev/null || true)"
  pattern_pids="$(pgrep -f "$anchored_pattern" 2>/dev/null || true)"
  {
    [[ -z "$exact_pids" ]] || printf '%s\n' "$exact_pids"
    [[ -z "$pattern_pids" ]] || printf '%s\n' "$pattern_pids"
  } | sort -nu
}

worker_supervisor() {
  local run_dir="$1"
  local binary="$2"
  local child_pid=""

  terminate_child() {
    if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
      kill -TERM "$child_pid" 2>/dev/null || true
      wait "$child_pid" 2>/dev/null || true
    fi
  }
  terminate_supervisor() {
    trap - TERM INT
    terminate_child
    exit 143
  }
  trap terminate_supervisor TERM INT
  trap terminate_child EXIT

  # shellcheck disable=SC1090
  set -a
  source "$PROVIDER_ENV"
  set +a
  for ((cycle = 1; cycle <= CYCLES; cycle++)); do
    request_limit=$((cycle * 2))
    token_limit=$((cycle * 20000))
    printf 'cycle=%s start=%s request_limits=%s/%s/%s\n' \
      "$cycle" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "$request_limit" "$request_limit" "$request_limit" >>"$run_dir/worker.log"
    env \
      QXFX0_DB="$DB" \
      QXFX0_AUTONOMOUS_LEARNING=1 \
      QXFX0_AUTONOMOUS_MODE=full \
      QXFX0_LEARNING_AUDIT_INTERVAL_SEC=3600 \
      QXFX0_LEARNING_MAX_REQ_PER_MINUTE="$request_limit" \
      QXFX0_LEARNING_MAX_REQ_PER_HOUR="$request_limit" \
      QXFX0_LEARNING_MAX_REQ_PER_DAY="$request_limit" \
      QXFX0_LEARNING_MAX_TOKENS_PER_MINUTE="$token_limit" \
      QXFX0_LEARNING_MAX_TOKENS_PER_HOUR="$token_limit" \
      QXFX0_LEARNING_MAX_TOKENS_PER_DAY="$token_limit" \
      QXFX0_LEARNING_RESERVED_COMPLETION_TOKENS=512 \
      QXFX0_LEARNING_MAX_EDGES_PER_BATCH=1 \
      QXFX0_LEARNING_QUEUE_CAP=1 \
      QXFX0_LLM_MAX_RETRIES=1 \
      "$binary" --session-id "autonomous-canary-v3-$cycle" \
        --autonomous-run "$CYCLE_SECONDS" >>"$run_dir/worker.log" 2>&1 &
    child_pid=$!
    set +e
    wait "$child_pid"
    rc=$?
    set -e
    child_pid=""
    printf 'cycle=%s end=%s exit=%s\n' \
      "$cycle" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rc" >>"$run_dir/worker.log"
    [[ "$rc" -eq 0 ]] || exit "$rc"

    if ((cycle < CYCLES)); then
      sleep_seconds=$((INTERVAL_SEC - CYCLE_SECONDS))
      sleep "$((sleep_seconds > 0 ? sleep_seconds : 1))"
    fi
  done

  # Keep the supervised process alive through the monitor's final checkpoint.
  sleep "$INTERVAL_SEC"
}

if [[ "${1:-}" == "--worker-supervisor" ]]; then
  [[ "$#" -eq 3 ]] || die "invalid worker supervisor arguments"
  worker_supervisor "$2" "$3"
  exit 0
fi

[[ "$#" -eq 0 ]] || die "unexpected arguments"
[[ "$CYCLES" =~ ^[1-9][0-9]*$ ]] || die "QXFX0_CANARY_CYCLES must be positive"
[[ "$CYCLE_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "QXFX0_CANARY_CYCLE_SECONDS must be positive"
[[ "$INTERVAL_SEC" =~ ^[1-9][0-9]*$ ]] || die "QXFX0_CANARY_MONITOR_INTERVAL_SEC must be positive"
[[ -f "$DB" ]] || die "database not found: $DB"
[[ -f "$PROVIDER_ENV" ]] || die "provider environment not found: $PROVIDER_ENV"
[[ -x "$MONITOR_SCRIPT" ]] || die "monitor is not executable: $MONITOR_SCRIPT"
[[ -d "$STATE_DIR" ]] || die "state directory not found: $STATE_DIR"
[[ -d "$BACKUP_DIR" ]] || die "backup directory not found: $BACKUP_DIR"

active="$(processes_matching qxfx0-main '^bash (.*/)?scripts/(run-bounded-v3-canary\.sh --worker-supervisor|autonomous-canary-monitor\.sh)( |$)')"
[[ -z "$active" ]] || die "autonomous processes already active: ${active//$'\n'/,}"

quick_check="$(sqlite3 -cmd '.timeout 5000' "file:$DB?mode=ro" 'PRAGMA quick_check;')"
integrity_check="$(sqlite3 -cmd '.timeout 5000' "file:$DB?mode=ro" 'PRAGMA integrity_check;')"
[[ "$quick_check" == "ok" && "$integrity_check" == "ok" ]] || die "production database integrity check failed"

binary="$(cd "$ROOT_DIR" && cabal list-bin qxfx0-main)"
[[ -x "$binary" ]] || die "qxfx0-main binary not found"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$STATE_DIR/autonomous-canary-$stamp"
backup="$BACKUP_DIR/qxfx0-pre-v3-canary-$stamp.db"
mkdir "$run_dir"
sqlite3 -cmd '.timeout 5000' "$DB" ".backup '$backup'"
chmod 600 "$backup"
backup_integrity="$(sqlite3 "file:$backup?mode=ro" 'PRAGMA integrity_check;')"
[[ "$backup_integrity" == "ok" ]] || die "rollback backup integrity check failed"

sqlite3 -cmd '.timeout 5000' "file:$DB?mode=ro" \
  "SELECT 'runtime_edges', COUNT(*) FROM semantic_edges_runtime;
   SELECT 'learning_events', COUNT(*) FROM learning_events;
   SELECT 'active_overlays', COUNT(*) FROM promotion_overlays WHERE status='active';" \
  >"$run_dir/baseline.txt"
printf 'backup=%s\n' "$backup" >>"$run_dir/baseline.txt"

nohup bash "$0" --worker-supervisor "$run_dir" "$binary" \
  >"$run_dir/worker-supervisor.log" 2>&1 &
worker_pid=$!
printf '%s\n' "$worker_pid" >"$run_dir/worker.pid"

QXFX0_CANARY_DB="$DB" \
QXFX0_CANARY_WORKER_PID_FILE="$run_dir/worker.pid" \
QXFX0_CANARY_MONITOR_LOG="$run_dir/monitor.log" \
QXFX0_CANARY_CHECKPOINTS="$CYCLES" \
QXFX0_CANARY_MONITOR_INTERVAL_SEC="$INTERVAL_SEC" \
  nohup "$MONITOR_SCRIPT" >"$run_dir/monitor-supervisor.log" 2>&1 &
monitor_pid=$!
printf '%s\n' "$monitor_pid" >"$run_dir/monitor.pid"

printf 'run_dir=%s\nbackup=%s\nworker_pid=%s\nmonitor_pid=%s\n' \
  "$run_dir" "$backup" "$worker_pid" "$monitor_pid"
