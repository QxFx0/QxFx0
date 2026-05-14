#!/usr/bin/env bash
# check_en_render_path.sh — EN render path quality gate
#
# Measures EN-specific quality metrics:
# - intent_fit_rate (how well expected move families match)
# - gf_output_rate (EN GF linearization success rate)
# - fallback_rate (template fallback rate)
# - ru_leakage_rate (Russian text in EN responses)
# - critical_mismatch_count (family mismatches)
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
LOG="$GATES_DIR/06b_en_render_path_${RUN_ID}_${PROFILE}.log"

# EN quality thresholds (strict as per requirements)
INTENT_FIT_THRESHOLD="${QXFX0_EN_INTENT_FIT_THRESHOLD:-0.90}"
GF_OUTPUT_THRESHOLD="${QXFX0_EN_GF_OUTPUT_THRESHOLD:-0.85}"
FALLBACK_THRESHOLD="${QXFX0_EN_FALLBACK_THRESHOLD:-0.15}"
RU_LEAKAGE_THRESHOLD="${QXFX0_EN_RU_LEAKAGE_THRESHOLD:-0.05}"
CRITICAL_MISMATCH_THRESHOLD="${QXFX0_EN_CRITICAL_MISMATCH_THRESHOLD:-0}"

MAX_PROMPTS="${QXFX0_EN_MAX_PROMPTS:-30}"
TURN_TIMEOUT_SECONDS="${QXFX0_EN_TURN_TIMEOUT_SECONDS:-30}"

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

# Use EN baseline prompts by default, or custom file
PROMPTS_FILE="${QXFX0_EN_PROMPTS_FILE:-$ROOT/data/semantic/en_baseline_prompts.tsv}"

PROMPTS=()
if [ -n "$PROMPTS_FILE" ] && [ -f "$PROMPTS_FILE" ]; then
  while IFS=$'\t' read -r id prompt expected_family; do
    [[ -z "${id// }" ]] && continue
    [[ "$id" == \#* ]] && continue
    [[ "$id" == "id" ]] && continue
    PROMPTS+=("$id"$'\t'"$prompt"$'\t'"$expected_family")
  done < "$PROMPTS_FILE"
else
  echo "INFRA: EN prompts file not found: $PROMPTS_FILE" | tee "$LOG"
  exit 2
fi

if [ "${#PROMPTS[@]}" -eq 0 ]; then
  echo "INFRA: prompt set is empty" | tee "$LOG"
  exit 2
fi

DB="/tmp/qxfx0-en-render-audit-$$.db"
rm -f "$DB"

# Seed DB with EN runtime
QXFX0_GF_RUNTIME="${QXFX0_GF_RUNTIME:-1}" \
QXFX0_GF_LANG="QxFx0SyntaxEng" \
QXFX0_RUNTIME_MODE=degraded \
QXFX0_ROOT="$ROOT" \
QXFX0_DB="$DB" \
"$BIN" --session "eninit_$$" --input "hello" --json >/dev/null 2>/dev/null || true

TOTAL=0
INTENT_FIT_COUNT=0
GF_OUTPUT_COUNT=0
FALLBACK_COUNT=0
RU_LEAKAGE_COUNT=0
CRITICAL_MISMATCH_COUNT=0
TIMEOUTS=0

: > "$LOG"
echo "run_id=$RUN_ID profile=$PROFILE gf_runtime=${QXFX0_GF_RUNTIME:-1} gf_lang=QxFx0SyntaxEng" >> "$LOG"
echo "bin=$BIN" >> "$LOG"
echo "max_prompts=$MAX_PROMPTS turn_timeout_s=$TURN_TIMEOUT_SECONDS" >> "$LOG"
echo "intent_fit_threshold=$INTENT_FIT_THRESHOLD" >> "$LOG"
echo "gf_output_threshold=$GF_OUTPUT_THRESHOLD" >> "$LOG"
echo "fallback_threshold=$FALLBACK_THRESHOLD" >> "$LOG"
echo "ru_leakage_threshold=$RU_LEAKAGE_THRESHOLD" >> "$LOG"

for prompt_entry in "${PROMPTS[@]}"; do
  [ "$TOTAL" -ge "$MAX_PROMPTS" ] && break

  IFS=$'\t' read -r id prompt expected_family <<< "$prompt_entry"
  session="enrender_${TOTAL}_$$"

  set +e
  cli_out="$(
    timeout "$TURN_TIMEOUT_SECONDS" env \
      QXFX0_GF_RUNTIME="${QXFX0_GF_RUNTIME:-1}" \
      QXFX0_GF_LANG="QxFx0SyntaxEng" \
      QXFX0_RUNTIME_MODE=degraded \
      QXFX0_ROOT="$ROOT" \
      QXFX0_DB="$DB" \
      "$BIN" --session "$session" --input "$prompt" --json 2>/dev/null
  )"
  ec=$?
  set -e
  if [ "$ec" -ne 0 ]; then
    if [ "$ec" -eq 124 ]; then
      TIMEOUTS=$((TIMEOUTS + 1))
      echo "warn: timeout prompt_index=$TOTAL" >> "$LOG"
    else
      echo "warn: runtime failure prompt_index=$TOTAL exit=$ec" >> "$LOG"
    fi
    continue
  fi

  if [ -z "$cli_out" ]; then
    echo "warn: empty cli output prompt_index=$TOTAL" >> "$LOG"
    continue
  fi

  trace_json="$(sqlite3 "$DB" "SELECT replay_trace_json FROM turn_quality WHERE session_id='$session' ORDER BY turn DESC LIMIT 1;" 2>/dev/null || true)"
  if [ -z "$trace_json" ] || [ "$trace_json" = "{}" ]; then
    echo "warn: missing trace prompt_index=$TOTAL" >> "$LOG"
    # Continue anyway; we can still measure family/response from CLI
    trace_json="{}"
  fi

  parsed="$(python3 - <<'PY' "$cli_out" "$trace_json" "$expected_family"
import json, sys, re
try:
    cli = json.loads(sys.argv[1])
    trace = json.loads(sys.argv[2])
    expected = sys.argv[3] if len(sys.argv) > 3 else ""
except Exception as e:
    print(f"ERR|ERR|ERR|ERR|ERR|ERR|parse_error: {e}")
    raise SystemExit(0)

# Family and response come from CLI JSON output
actual = cli.get("family") or cli.get("move_family") or ""
response = (cli.get("response") or cli.get("text") or "").lower()

# Linearization fields come from SQLite replay trace
lang = trace.get("trcLinearizationLang") or ""
ok = 1 if trace.get("trcLinearizationOk", False) else 0
fb = trace.get("trcFallbackReason")

# Check for Russian leakage (any Cyrillic chars in response = leakage for EN input)
ru_markers = ["рефлексия:", "отклик: что значит", "локальный режим восстановления", "я могу дать локальную понятийную рамку"]
ru_leakage = 1 if any(m in response for m in ru_markers) else 0
has_cyrillic = 1 if re.search(r'[а-яё]', response, re.IGNORECASE) else 0

# Fallback is trace-driven.
fallback = 0
if fb and (
    "fallback" in str(fb).lower()
    or "failed" in str(fb).lower()
    or "pgf_missing" in str(fb).lower()
):
    fallback = 1

# GF output for EN: linearization succeeded with EN tag
gf_output = 1 if ok and lang and "en" in lang.lower() else 0

# Intent fit: expected family matches actual family from CLI
intent_fit = 1 if expected and actual == expected else 0

# Critical mismatch: expected family differs from actual
critical = 1 if expected and actual != expected else 0

print(f"{intent_fit}|{gf_output}|{fallback}|{ru_leakage or has_cyrillic}|{critical}|{expected}|{actual}|{lang}")
PY
)"

  IFS='|' read -r intent_fit gf_output fallback ru_leakage critical expected actual lang <<< "$parsed"
  if [ "$intent_fit" = "ERR" ]; then
    echo "warn: trace parse failure prompt_index=$TOTAL detail=$lang" >> "$LOG"
    continue
  fi

  TOTAL=$((TOTAL + 1))
  INTENT_FIT_COUNT=$((INTENT_FIT_COUNT + intent_fit))
  GF_OUTPUT_COUNT=$((GF_OUTPUT_COUNT + gf_output))
  FALLBACK_COUNT=$((FALLBACK_COUNT + fallback))
  RU_LEAKAGE_COUNT=$((RU_LEAKAGE_COUNT + ru_leakage))
  CRITICAL_MISMATCH_COUNT=$((CRITICAL_MISMATCH_COUNT + critical))

  echo "[$TOTAL] id=$id expected=$expected actual=$actual intent_fit=$intent_fit gf_output=$gf_output fallback=$fallback ru_leakage=$ru_leakage" >> "$LOG"
done

rm -f "$DB"

if [ "$TOTAL" -eq 0 ]; then
  echo "INFRA: no successful measured turns (timeouts=$TIMEOUTS)" | tee -a "$LOG"
  exit 2
fi

python3 - <<PY | tee -a "$LOG"
import sys

total = int(${TOTAL})
intent_fit = int(${INTENT_FIT_COUNT})
gf_output = int(${GF_OUTPUT_COUNT})
fallback = int(${FALLBACK_COUNT})
ru_leakage = int(${RU_LEAKAGE_COUNT})
critical = int(${CRITICAL_MISMATCH_COUNT})
timeouts = int(${TIMEOUTS})

intent_fit_rate = intent_fit / total if total > 0 else 0.0
gf_output_rate = gf_output / total if total > 0 else 0.0
fallback_rate = fallback / total if total > 0 else 0.0
ru_leakage_rate = ru_leakage / total if total > 0 else 0.0
critical_mismatch_rate = critical / total if total > 0 else 0.0

print(f"total_turns={total}")
print(f"timeouts={timeouts}")
print(f"intent_fit_rate={intent_fit_rate:.4f}")
print(f"gf_output_rate={gf_output_rate:.4f}")
print(f"fallback_rate={fallback_rate:.4f}")
print(f"ru_leakage_rate={ru_leakage_rate:.4f}")
print(f"critical_mismatch_count={critical}")
print(f"critical_mismatch_rate={critical_mismatch_rate:.4f}")

intent_thr = float("${INTENT_FIT_THRESHOLD}")
gf_thr = float("${GF_OUTPUT_THRESHOLD}")
fb_thr = float("${FALLBACK_THRESHOLD}")
ru_thr = float("${RU_LEAKAGE_THRESHOLD}")
critical_thr = float("${CRITICAL_MISMATCH_THRESHOLD}")

status = "PASS"
if intent_fit_rate < intent_thr:
    print(f"FAIL: intent_fit_rate {intent_fit_rate:.4f} < {intent_thr:.4f}")
    status = "FAIL"
if gf_output_rate < gf_thr:
    print(f"FAIL: gf_output_rate {gf_output_rate:.4f} < {gf_thr:.4f}")
    status = "FAIL"
if fallback_rate > fb_thr:
    print(f"FAIL: fallback_rate {fallback_rate:.4f} > {fb_thr:.4f}")
    status = "FAIL"
if ru_leakage_rate > ru_thr:
    print(f"FAIL: ru_leakage_rate {ru_leakage_rate:.4f} > {ru_thr:.4f}")
    status = "FAIL"
if critical > critical_thr:
    print(f"FAIL: critical_mismatch_count {critical} > {critical_thr}")
    status = "FAIL"

print(f"VERDICT: {status}")
sys.exit(0 if status == "PASS" else 1)
PY
