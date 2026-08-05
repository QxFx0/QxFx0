#!/usr/bin/env bash
set -euo pipefail
umask 077

DB="${QXFX0_CANARY_DB:?QXFX0_CANARY_DB is required}"
WORKER_PID_FILE="${QXFX0_CANARY_WORKER_PID_FILE:?QXFX0_CANARY_WORKER_PID_FILE is required}"
LOG="${QXFX0_CANARY_MONITOR_LOG:?QXFX0_CANARY_MONITOR_LOG is required}"
CHECKPOINTS="${QXFX0_CANARY_CHECKPOINTS:-4}"
INTERVAL_SEC="${QXFX0_CANARY_MONITOR_INTERVAL_SEC:-1800}"

for ((checkpoint = 1; checkpoint <= CHECKPOINTS; checkpoint++)); do
  sleep "$INTERVAL_SEC"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  worker_pid="$(<"$WORKER_PID_FILE")"
  if kill -0 "$worker_pid" 2>/dev/null; then
    worker_alive=1
  else
    worker_alive=0
  fi

  quick_check="$(sqlite3 -cmd ".timeout 5000" "file:$DB?mode=ro" "PRAGMA quick_check;")"
  stale_ready="$(sqlite3 -cmd ".timeout 5000" "file:$DB?mode=ro" \
    "SELECT COUNT(*) FROM learning_jobs WHERE state='response_ready' AND updated_at < (strftime('%s','now')-600)*1000000 AND (lease_until IS NULL OR lease_until <= strftime('%s','now')*1000000);")"

  {
    printf 'checkpoint=%s timestamp=%s worker_alive=%s quick_check=%s stale_ready=%s\n' \
      "$checkpoint" "$timestamp" "$worker_alive" "$quick_check" "$stale_ready"
    sqlite3 -cmd ".timeout 5000" "file:$DB?mode=ro" \
      "SELECT 'jobs', state, COUNT(*) FROM learning_jobs GROUP BY state ORDER BY state;
       SELECT 'ready_payloads', COUNT(*) FROM learning_ready_payloads;
       SELECT 'quota', window_name, requests, tokens FROM learning_quota_windows ORDER BY window_name;
       SELECT 'runtime_edges', COUNT(*) FROM semantic_edges_runtime;
       SELECT 'learning_events', COUNT(*) FROM learning_events;
       SELECT 'corroboration', state, COUNT(*) FROM learning_corroboration_tasks GROUP BY state ORDER BY state;
       SELECT 'active_overlays', COUNT(*) FROM promotion_overlays WHERE status='active';"
    stat --format='db_size=%s' "$DB"
    if [[ -e "$DB-wal" ]]; then
      stat --format='wal_size=%s' "$DB-wal"
    else
      printf 'wal_size=0\n'
    fi
  } >>"$LOG" 2>&1

  if [[ "$worker_alive" -ne 1 || "$quick_check" != "ok" || ! "$stale_ready" =~ ^[0-9]+$ || "$stale_ready" -gt 0 ]]; then
    printf 'abort timestamp=%s reason=worker_integrity_or_stale_ready\n' "$timestamp" >>"$LOG"
    kill -TERM "$worker_pid" 2>/dev/null || true
    exit 1
  fi
done

sqlite3 -cmd ".timeout 5000" "file:$DB?mode=ro" "PRAGMA integrity_check;" >>"$LOG" 2>&1
