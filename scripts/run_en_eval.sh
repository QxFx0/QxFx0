#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${1:-en_run_$(date +%Y%m%d-%H%M%S)}"
PROMPTS_FILE="${2:-$ROOT/data/semantic/en_baseline_prompts.tsv}"
RUNTIME_MODE="${QXFX0_RUNTIME_MODE:-degraded}"
SESSION_ID="${QXFX0_EVAL_SESSION_ID:-en-eval-${RUN_ID}}"
SESSION_MODE="${QXFX0_EVAL_SESSION_MODE:-isolated}"
OUT_DIR="$ROOT/reports/eval_runs/$RUN_ID"
RESULTS_JSONL="$OUT_DIR/results.jsonl"
SUMMARY_JSON="$OUT_DIR/summary.json"
SUMMARY_MD="$OUT_DIR/summary.md"
RAW_DIR="$OUT_DIR/raw"

if [[ ! -f "$PROMPTS_FILE" ]]; then
  echo "prompts file not found: $PROMPTS_FILE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR" "$RAW_DIR"
rm -f "$RESULTS_JSONL" "$SUMMARY_JSON" "$SUMMARY_MD"

{
  echo "run_id=$RUN_ID"
  echo "started_at=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "runtime_mode=$RUNTIME_MODE"
  echo "session_id=$SESSION_ID"
  echo "session_mode=$SESSION_MODE"
  echo "prompts_file=$PROMPTS_FILE"
  echo "evaluation_language=en"
} >"$OUT_DIR/meta.env"

echo "Running EN eval: $RUN_ID"
echo "Prompts: $PROMPTS_FILE"
echo "Runtime mode: $RUNTIME_MODE"
echo "Session mode: $SESSION_MODE"

row_index=0
while IFS=$'\t' read -r id prompt expected_family; do
  [[ -z "${id// }" ]] && continue
  [[ "$id" == \#* ]] && continue
  [[ "$id" == "id" ]] && continue

  row_index=$((row_index + 1))
  raw_file="$RAW_DIR/${id}.log"

  if [[ "$SESSION_MODE" == "isolated" ]]; then
    row_session_id="${SESSION_ID}-${id}"
  else
    row_session_id="$SESSION_ID"
  fi

  # Force EN GF language for this eval
  # Use a temp DB per prompt to query replay trace for linearization fields
  db_path="/tmp/qxfx0-en-eval-${row_session_id}.db"
  rm -f "$db_path"

  start_ms=$(date +%s%3N)
  cmd_out="$(QXFX0_RUNTIME_MODE="$RUNTIME_MODE" QXFX0_GF_LANG=QxFx0SyntaxEng QXFX0_DB="$db_path" cabal run -v0 qxfx0-main -- --session "$row_session_id" --input "$prompt" --json 2>&1 || true)"
  end_ms=$(date +%s%3N)
  latency_ms=$((end_ms - start_ms))

  printf '%s\n' "$cmd_out" >"$raw_file"

  RAW_FILE="$raw_file" ID="$id" PROMPT="$prompt" EXPECTED_FAMILY="$expected_family" LATENCY_MS="$latency_ms" ROW_SESSION_ID="$row_session_id" DB_PATH="$db_path" \
  python3 - <<'PY' >>"$RESULTS_JSONL"
import json
import os
import re
import sqlite3
from pathlib import Path

raw_path = Path(os.environ["RAW_FILE"])
rid = os.environ["ID"]
prompt = os.environ["PROMPT"]
expected = os.environ.get("EXPECTED_FAMILY", "").strip()
latency_ms = int(os.environ["LATENCY_MS"])
row_session_id = os.environ["ROW_SESSION_ID"]
db_path = os.environ["DB_PATH"]

raw = raw_path.read_text(encoding="utf-8", errors="replace")
payload = None
for line in reversed(raw.splitlines()):
    line = line.strip()
    if not line or not line.startswith("{"):
        continue
    try:
        payload = json.loads(line)
        break
    except json.JSONDecodeError:
        continue

actual = ""
response = ""
status = "parse_error"
linearization_lang = None
linearization_ok = False
fallback_reason = None
if isinstance(payload, dict):
    status = str(payload.get("status", "ok"))
    actual = str(payload.get("family") or payload.get("move_family") or "")
    response = str(payload.get("response") or payload.get("text") or "")

# Query SQLite replay trace for linearization fields
try:
    conn = sqlite3.connect(db_path)
    cur = conn.execute(
        "SELECT replay_trace_json FROM turn_quality WHERE session_id=? ORDER BY turn DESC LIMIT 1",
        (row_session_id,)
    )
    row = cur.fetchone()
    conn.close()
    if row and row[0]:
        trace = json.loads(row[0])
        linearization_lang = trace.get("trcLinearizationLang")
        linearization_ok = bool(trace.get("trcLinearizationOk", False))
        fallback_reason = trace.get("trcFallbackReason")
except Exception:
    pass

text = response.lower()
# EN-specific fallback markers (Russian template fallback)
ru_fallback_markers = [
    "рефлексия:",
    "отклик: что значит",
    "я могу дать локальную понятийную рамку",
    "назначение смысла раскрывается через устойчивую роль",
    "локальный режим восстановления",
]
# EN fallback markers (template fallback)
en_fallback_markers = [
    "i ground meaning",
    "i have meaning",
    "i criticize meaning",
]

ru_leakage = False
for marker in ru_fallback_markers:
    if marker in text:
        ru_leakage = True
        break

# Check for Cyrillic characters in response
has_cyrillic = bool(re.search(r'[а-яё]', text, re.IGNORECASE))

fallback_drift = any(m in text for m in en_fallback_markers)
# Also mark fallback if trace shows fallback reason
if fallback_reason and ("fallback" in str(fallback_reason).lower() or "failed" in str(fallback_reason).lower()):
    fallback_drift = True

gf_output = linearization_ok and linearization_lang and "en" in linearization_lang.lower()
intent_fit = None if not expected else (actual == expected)
critical_mismatch = bool(expected) and (actual != expected)

row = {
    "id": rid,
    "prompt": prompt,
    "expected_family": expected,
    "actual_family": actual,
    "status": status,
    "latency_ms": latency_ms,
    "intent_fit": intent_fit,
    "critical_mismatch": critical_mismatch,
    "fallback_drift": fallback_drift,
    "ru_leakage": ru_leakage,
    "has_cyrillic": has_cyrillic,
    "gf_output": gf_output,
    "linearization_lang": linearization_lang,
    "linearization_ok": linearization_ok,
    "fallback_reason": fallback_reason,
    "row_session_id": row_session_id,
    "raw_file": str(raw_path),
}
print(json.dumps(row, ensure_ascii=False))
PY

  echo "[$row_index] $id done (${latency_ms} ms)"
done <"$PROMPTS_FILE"

RESULTS_JSONL="$RESULTS_JSONL" SUMMARY_JSON="$SUMMARY_JSON" SUMMARY_MD="$SUMMARY_MD" RUN_ID="$RUN_ID" \
python3 - <<'PY'
import json
import os
from pathlib import Path

results_path = Path(os.environ["RESULTS_JSONL"])
summary_json = Path(os.environ["SUMMARY_JSON"])
summary_md = Path(os.environ["SUMMARY_MD"])
run_id = os.environ["RUN_ID"]

rows = []
for line in results_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    rows.append(json.loads(line))

total = len(rows)
with_expected = [r for r in rows if r.get("expected_family")]
fit_count = sum(1 for r in with_expected if r.get("intent_fit") is True)
fallback_count = sum(1 for r in rows if r.get("fallback_drift"))
critical_count = sum(1 for r in rows if r.get("critical_mismatch"))
ru_leakage_count = sum(1 for r in rows if r.get("ru_leakage"))
has_cyrillic_count = sum(1 for r in rows if r.get("has_cyrillic"))
gf_output_count = sum(1 for r in rows if r.get("gf_output"))
error_count = sum(1 for r in rows if r.get("status") != "ok")
avg_latency = (sum(r.get("latency_ms", 0) for r in rows) / total) if total else 0.0

def safe_rate(num, den):
    return (float(num) / float(den)) if den else 0.0

summary = {
    "run_id": run_id,
    "evaluation_language": "en",
    "total_prompts": total,
    "with_expected_family": len(with_expected),
    "intent_fit_count": fit_count,
    "intent_fit_rate": safe_rate(fit_count, len(with_expected)),
    "fallback_drift_count": fallback_count,
    "fallback_rate": safe_rate(fallback_count, total),
    "critical_mismatch_count": critical_count,
    "critical_mismatch_rate": safe_rate(critical_count, total),
    "ru_leakage_count": ru_leakage_count,
    "ru_leakage_rate": safe_rate(ru_leakage_count, total),
    "has_cyrillic_count": has_cyrillic_count,
    "has_cyrillic_rate": safe_rate(has_cyrillic_count, total),
    "gf_output_count": gf_output_count,
    "gf_output_rate": safe_rate(gf_output_count, total),
    "runtime_or_parse_error_count": error_count,
    "avg_latency_ms": avg_latency,
}
summary_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

md = [
    f"# EN Eval Summary: {run_id}",
    "",
    f"- Total prompts: {total}",
    f"- With expected family: {len(with_expected)}",
    f"- Intent fit: {fit_count} ({summary['intent_fit_rate']:.3f})",
    f"- Fallback/template drift: {fallback_count} ({summary['fallback_rate']:.3f})",
    f"- Critical mismatch: {critical_count} ({summary['critical_mismatch_rate']:.3f})",
    f"- RU leakage (Russian markers): {ru_leakage_count} ({summary['ru_leakage_rate']:.3f})",
    f"- Cyrillic characters in response: {has_cyrillic_count} ({summary['has_cyrillic_rate']:.3f})",
    f"- GF output (EN linearization): {gf_output_count} ({summary['gf_output_rate']:.3f})",
    f"- Runtime/parse errors: {error_count}",
    f"- Average latency ms: {avg_latency:.2f}",
    "",
    "## EN Quality Threshold Check",
    f"- intent_fit_rate >= 0.90: {'PASS' if summary['intent_fit_rate'] >= 0.90 else 'FAIL'}",
    f"- gf_output_rate >= 0.85: {'PASS' if summary['gf_output_rate'] >= 0.85 else 'FAIL'}",
    f"- fallback_rate <= 0.15: {'PASS' if summary['fallback_rate'] <= 0.15 else 'FAIL'}",
    f"- ru_leakage_rate <= 0.05: {'PASS' if summary['ru_leakage_rate'] <= 0.05 else 'FAIL'}",
    f"- critical_mismatch_count == 0: {'PASS' if critical_count == 0 else 'FAIL'}",
]
summary_md.write_text("\n".join(md) + "\n", encoding="utf-8")

print(json.dumps(summary, ensure_ascii=False, indent=2))
PY

echo "Done. Outputs:"
echo "  - $RESULTS_JSONL"
echo "  - $SUMMARY_JSON"
echo "  - $SUMMARY_MD"
