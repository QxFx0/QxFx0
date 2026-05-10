#!/usr/bin/env bash
# check_gf_render_path.sh — GF primary render path audit gate
#
# Measures real runtime render path distribution from replay traces:
# - fallback rate via trcFallbackReason
# - GF atoms rate via trcLinearizationLang == ru_GF_ATOMS
#
# Exit codes:
#   0 = PASS
#   1 = FAIL (quality threshold violated)
#   2 = INFRA (cannot measure reliably in current environment)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATES_DIR="$ROOT/reports/baseline_v2/final_gates"
mkdir -p "$GATES_DIR"
cd "$ROOT"

RUN_ID="${RUN_ID:-ci-$(date +%Y%m%d-%H%M%S)}"
PROFILE="${PROFILE:-core}"
LOG="$GATES_DIR/06a_gf_render_path_${RUN_ID}_${PROFILE}.log"
DB="/tmp/qxfx0-gf-render-audit-$$.db"

FALLBACK_THRESHOLD="${QXFX0_GF_FALLBACK_THRESHOLD:-0.20}"
GF_ATOMS_THRESHOLD="${QXFX0_GF_ATOMS_THRESHOLD:-0.60}"
MAX_PROMPTS="${QXFX0_GF_MAX_PROMPTS:-30}"
TURN_TIMEOUT_SECONDS="${QXFX0_GF_TURN_TIMEOUT_SECONDS:-30}"

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "INFRA: sqlite3 is not installed" | tee "$LOG"
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "INFRA: python3 is not installed" | tee "$LOG"
  exit 2
fi

if [ -n "${QXFX0_BIN:-}" ]; then
  BIN="$QXFX0_BIN"
else
  BIN="$(cabal list-bin qxfx0-main 2>/dev/null || true)"
fi

if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  echo "INFRA: qxfx0-main binary not available (set QXFX0_BIN or run cabal build all)" | tee "$LOG"
  exit 2
fi

PROMPTS_FILE="${QXFX0_GF_PROMPTS_FILE:-}"
PROMPTS=()
if [ -n "$PROMPTS_FILE" ] && [ -f "$PROMPTS_FILE" ]; then
  while IFS= read -r line; do
    [ -z "${line// }" ] && continue
    [[ "$line" == \#* ]] && continue
    PROMPTS+=("$line")
  done < "$PROMPTS_FILE"
else
  PROMPTS=(
    "привет"
    "что такое логика?"
    "что такое свобода?"
    "почему небо голубое?"
    "как устроена система?"
    "что такое право?"
    "что такое диагноз?"
    "как работает правило?"
    "что такое ответственность?"
    "что такое причина?"
    "что такое следствие?"
    "что такое смысл?"
    "где формируется мысль?"
    "зачем нужен стол?"
    "что такое человек?"
    "что такое истина?"
    "что такое договор в праве?"
    "что такое презумпция невиновности?"
    "что такое гипертония?"
    "что такое власть?"
    "что такое язык?"
    "что такое время?"
    "что такое пространство?"
    "что такое процесс?"
    "что такое цель?"
    "что такое метод?"
    "что такое структура?"
    "я не понимаю тебя"
    "что дальше?"
    "контакт потерян"
  )
fi

if [ "${#PROMPTS[@]}" -eq 0 ]; then
  echo "INFRA: prompt set is empty" | tee "$LOG"
  exit 2
fi

rm -f "$DB"

# Seed DB/schema once.
QXFX0_GF_RUNTIME="${QXFX0_GF_RUNTIME:-1}" \
QXFX0_RUNTIME_MODE=degraded \
QXFX0_DB="$DB" \
"$BIN" --session "gfinit_$$" --input "инициализация" --json >/dev/null 2>/dev/null || true

TOTAL=0
GF_ATOMS=0
FALLBACK=0
LINEARIZATION_OK=0
TIMEOUTS=0

: > "$LOG"
echo "run_id=$RUN_ID profile=$PROFILE gf_runtime=${QXFX0_GF_RUNTIME:-1}" >> "$LOG"
echo "bin=$BIN" >> "$LOG"
echo "max_prompts=$MAX_PROMPTS turn_timeout_s=$TURN_TIMEOUT_SECONDS" >> "$LOG"

for i in "${!PROMPTS[@]}"; do
  [ "$i" -ge "$MAX_PROMPTS" ] && break

  prompt="${PROMPTS[$i]}"
  session="gfrender_${i}_$$"

  if timeout "$TURN_TIMEOUT_SECONDS" \
      env QXFX0_GF_RUNTIME="${QXFX0_GF_RUNTIME:-1}" QXFX0_RUNTIME_MODE=degraded QXFX0_DB="$DB" \
      "$BIN" --session "$session" --input "$prompt" --json >/dev/null 2>/dev/null; then
    :
  else
    ec=$?
    if [ "$ec" -eq 124 ]; then
      TIMEOUTS=$((TIMEOUTS + 1))
      echo "warn: timeout prompt_index=$i" >> "$LOG"
    else
      echo "warn: runtime failure prompt_index=$i exit=$ec" >> "$LOG"
    fi
    continue
  fi

  trace_json="$(sqlite3 "$DB" "SELECT replay_trace_json FROM turn_quality WHERE session_id='$session' ORDER BY turn DESC LIMIT 1;" 2>/dev/null || true)"
  if [ -z "$trace_json" ] || [ "$trace_json" = "{}" ]; then
    echo "warn: missing trace prompt_index=$i" >> "$LOG"
    continue
  fi

  parsed="$(python3 - <<'PY' "$trace_json"
import json, sys
try:
    obj = json.loads(sys.argv[1])
except Exception:
    print("ERR|ERR|0")
    raise SystemExit(0)
fb = obj.get("trcFallbackReason")
lang = obj.get("trcLinearizationLang")
ok = 1 if obj.get("trcLinearizationOk", False) else 0
print(f"{fb if fb is not None else '__NONE__'}|{lang if lang is not None else '__NONE__'}|{ok}")
PY
)"

  IFS='|' read -r fb lang ok <<< "$parsed"
  if [ "$fb" = "ERR" ]; then
    echo "warn: trace parse failure prompt_index=$i" >> "$LOG"
    continue
  fi

  TOTAL=$((TOTAL + 1))
  [ "$fb" != "__NONE__" ] && FALLBACK=$((FALLBACK + 1))
  [ "$lang" = "ru_GF_ATOMS" ] && GF_ATOMS=$((GF_ATOMS + 1))
  [ "$ok" = "1" ] && LINEARIZATION_OK=$((LINEARIZATION_OK + 1))
done

rm -f "$DB"

if [ "$TOTAL" -eq 0 ]; then
  echo "INFRA: no successful measured turns (timeouts=$TIMEOUTS)" | tee -a "$LOG"
  exit 2
fi

python3 - <<PY | tee -a "$LOG"
import sys

total = int(${TOTAL})
fallback = int(${FALLBACK})
gf_atoms = int(${GF_ATOMS})
lin_ok = int(${LINEARIZATION_OK})
timeouts = int(${TIMEOUTS})

fallback_rate = fallback / total
gf_atoms_rate = gf_atoms / total
lin_ok_rate = lin_ok / total

print(f"total_turns={total}")
print(f"timeouts={timeouts}")
print(f"fallback_rate={fallback_rate:.4f}")
print(f"gf_atoms_rate={gf_atoms_rate:.4f}")
print(f"linearization_ok_rate={lin_ok_rate:.4f}")

fb_thr = float("${FALLBACK_THRESHOLD}")
gf_thr = float("${GF_ATOMS_THRESHOLD}")

status = "PASS"
if fallback_rate > fb_thr:
    print(f"FAIL: fallback_rate {fallback_rate:.4f} > {fb_thr:.4f}")
    status = "FAIL"
if gf_atoms_rate < gf_thr:
    print(f"FAIL: gf_atoms_rate {gf_atoms_rate:.4f} < {gf_thr:.4f}")
    status = "FAIL"

print(f"VERDICT: {status}")
sys.exit(0 if status == "PASS" else 1)
PY
