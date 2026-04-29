#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${1:-run_001}"
PROMPTS_FILE="${2:-$ROOT/reports/dialogue_eval_200_prompts.tsv}"
RUNTIME_MODE="${QXFX0_RUNTIME_MODE:-degraded}"
SESSION_ID="${QXFX0_EVAL_SESSION_ID:-eval-${RUN_ID}}"
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
} >"$OUT_DIR/meta.env"

echo "Running dialogue eval: $RUN_ID"
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

  start_ms=$(date +%s%3N)
  cmd_out="$(QXFX0_RUNTIME_MODE="$RUNTIME_MODE" cabal run -v0 qxfx0-main -- --session "$row_session_id" --input "$prompt" --json 2>&1 || true)"
  end_ms=$(date +%s%3N)
  latency_ms=$((end_ms - start_ms))

  printf '%s\n' "$cmd_out" >"$raw_file"

  RAW_FILE="$raw_file" ID="$id" PROMPT="$prompt" EXPECTED_FAMILY="$expected_family" LATENCY_MS="$latency_ms" ROW_SESSION_ID="$row_session_id" \
  python3 - <<'PY' >>"$RESULTS_JSONL"
import json
import os
import re
from pathlib import Path

raw_path = Path(os.environ["RAW_FILE"])
rid = os.environ["ID"]
prompt = os.environ["PROMPT"]
expected = os.environ.get("EXPECTED_FAMILY", "").strip()
latency_ms = int(os.environ["LATENCY_MS"])
row_session_id = os.environ["ROW_SESSION_ID"]

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
if isinstance(payload, dict):
    status = str(payload.get("status", "ok"))
    actual = str(payload.get("family") or payload.get("move_family") or "")
    response = str(payload.get("response") or payload.get("text") or "")

text = response.lower()
fallback_markers = [
    "рефлексия:",
    "отклик: что значит",
    "я могу дать локальную понятийную рамку",
    "назначение смысла раскрывается через устойчивую роль",
]
mismatch_prone_direct_families = {
    "CMContact",
    "CMDescribe",
    "CMDefine",
    "CMPurpose",
    "CMClarify",
    "CMGround",
    "CMDistinguish",
}
morphology_bad_patterns = [
    r"\bрукиа\b",
    r"\bбыти\b",
    r"\bфункции тута\b",
]

fallback_drift = any(m in text for m in fallback_markers)
morphology_defect = any(re.search(p, text) for p in morphology_bad_patterns)
intent_fit = None if not expected else (actual == expected)
critical_mismatch = bool(expected) and (actual != expected)
reflect_escape = bool(expected) and (expected in mismatch_prone_direct_families) and actual == "CMReflect"

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
    "reflect_escape": reflect_escape,
    "morphology_defect": morphology_defect,
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
reflect_escape_count = sum(1 for r in rows if r.get("reflect_escape"))
critical_count = sum(1 for r in rows if r.get("critical_mismatch"))
morph_count = sum(1 for r in rows if r.get("morphology_defect"))
error_count = sum(1 for r in rows if r.get("status") != "ok")
avg_latency = (sum(r.get("latency_ms", 0) for r in rows) / total) if total else 0.0

def safe_rate(num, den):
    return (float(num) / float(den)) if den else 0.0

summary = {
    "run_id": run_id,
    "total_prompts": total,
    "with_expected_family": len(with_expected),
    "intent_fit_count": fit_count,
    "intent_fit_rate": safe_rate(fit_count, len(with_expected)),
    "fallback_drift_count": fallback_count,
    "fallback_drift_rate": safe_rate(fallback_count, total),
    "reflect_escape_count": reflect_escape_count,
    "reflect_escape_rate": safe_rate(reflect_escape_count, total),
    "critical_mismatch_count": critical_count,
    "critical_mismatch_rate": safe_rate(critical_count, total),
    "morphology_defect_count": morph_count,
    "runtime_or_parse_error_count": error_count,
    "avg_latency_ms": avg_latency,
}
summary_json.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

md = [
    f"# Dialogue Eval Summary: {run_id}",
    "",
    f"- Total prompts: {total}",
    f"- With expected family: {len(with_expected)}",
    f"- Intent fit: {fit_count} ({summary['intent_fit_rate']:.3f})",
    f"- Fallback/template drift: {fallback_count} ({summary['fallback_drift_rate']:.3f})",
    f"- Reflective escape drift: {reflect_escape_count} ({summary['reflect_escape_rate']:.3f})",
    f"- Critical mismatch: {critical_count} ({summary['critical_mismatch_rate']:.3f})",
    f"- Morphology defects: {morph_count}",
    f"- Runtime/parse errors: {error_count}",
    f"- Average latency ms: {avg_latency:.2f}",
    "",
    "## Go/No-Go Threshold Check",
    f"- intent_fit_rate >= 0.85: {'PASS' if summary['intent_fit_rate'] >= 0.85 else 'FAIL'}",
    f"- fallback_drift_rate <= 0.05: {'PASS' if summary['fallback_drift_rate'] <= 0.05 else 'FAIL'}",
    f"- reflect_escape_rate <= 0.10: {'PASS' if summary['reflect_escape_rate'] <= 0.10 else 'FAIL'}",
    f"- critical_mismatch_rate <= 0.05: {'PASS' if summary['critical_mismatch_rate'] <= 0.05 else 'FAIL'}",
    f"- morphology_defect_count == 0: {'PASS' if morph_count == 0 else 'FAIL'}",
]
summary_md.write_text("\n".join(md) + "\n", encoding="utf-8")

print(json.dumps(summary, ensure_ascii=False, indent=2))
PY

echo "Done. Outputs:"
echo "  - $RESULTS_JSONL"
echo "  - $SUMMARY_JSON"
echo "  - $SUMMARY_MD"
