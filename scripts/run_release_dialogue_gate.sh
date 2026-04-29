#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_BASE="${1:-release_$(date -u +%Y%m%dT%H%M%SZ)}"
MAIN_PROMPTS="${2:-$ROOT/reports/dialogue_eval_500_prompts.tsv}"
REG_PROMPTS="${3:-$ROOT/reports/dialogue_eval_regression_prompts.tsv}"
OUT_DIR="$ROOT/reports/release_readiness"
MAIN_RUN_ID="${RUN_BASE}_main"
REG_RUN_ID="${RUN_BASE}_reg"
MAIN_SUMMARY="$ROOT/reports/eval_runs/$MAIN_RUN_ID/summary.json"
REG_SUMMARY="$ROOT/reports/eval_runs/$REG_RUN_ID/summary.json"
GATE_JSON="$OUT_DIR/${RUN_BASE}_dialogue_gate.json"
GATE_MD="$OUT_DIR/${RUN_BASE}_dialogue_gate.md"

mkdir -p "$OUT_DIR"

echo "[1/3] Running main dialogue eval ($MAIN_RUN_ID) ..."
bash "$ROOT/scripts/run_dialogue_eval_200.sh" "$MAIN_RUN_ID" "$MAIN_PROMPTS"

echo "[2/3] Running regression dialogue eval ($REG_RUN_ID) ..."
bash "$ROOT/scripts/run_dialogue_eval_200.sh" "$REG_RUN_ID" "$REG_PROMPTS"

echo "[3/3] Checking release dialogue gates ..."
MAIN_SUMMARY="$MAIN_SUMMARY" REG_SUMMARY="$REG_SUMMARY" RUN_BASE="$RUN_BASE" GATE_JSON="$GATE_JSON" GATE_MD="$GATE_MD" \
python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

main_path = Path(os.environ["MAIN_SUMMARY"])
reg_path = Path(os.environ["REG_SUMMARY"])
run_base = os.environ["RUN_BASE"]
gate_json = Path(os.environ["GATE_JSON"])
gate_md = Path(os.environ["GATE_MD"])

main = json.loads(main_path.read_text(encoding="utf-8"))
reg = json.loads(reg_path.read_text(encoding="utf-8"))

def check(name, value, op, bound):
    if op == ">=":
        ok = value >= bound
    elif op == "<=":
        ok = value <= bound
    elif op == "==":
        ok = value == bound
    else:
        raise ValueError(op)
    return {"name": name, "value": value, "op": op, "bound": bound, "ok": ok}

checks = [
    check("main.intent_fit_rate", main["intent_fit_rate"], ">=", 0.85),
    check("main.fallback_drift_rate", main["fallback_drift_rate"], "<=", 0.05),
    check("main.reflect_escape_rate", main.get("reflect_escape_rate", 0.0), "<=", 0.10),
    check("main.critical_mismatch_rate", main["critical_mismatch_rate"], "<=", 0.05),
    check("main.morphology_defect_count", main["morphology_defect_count"], "==", 0),
    check("reg.intent_fit_rate", reg["intent_fit_rate"], ">=", 0.85),
    check("reg.fallback_drift_rate", reg["fallback_drift_rate"], "<=", 0.05),
    check("reg.reflect_escape_rate", reg.get("reflect_escape_rate", 0.0), "<=", 0.10),
    check("reg.critical_mismatch_rate", reg["critical_mismatch_rate"], "<=", 0.05),
    check("reg.morphology_defect_count", reg["morphology_defect_count"], "==", 0),
]

all_ok = all(c["ok"] for c in checks)
payload = {
    "run_base": run_base,
    "status": "PASS" if all_ok else "FAIL",
    "main_run": main.get("run_id"),
    "regression_run": reg.get("run_id"),
    "checks": checks,
    "main_summary_path": str(main_path),
    "regression_summary_path": str(reg_path),
}
gate_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

lines = [
    f"# Dialogue Release Gate: {run_base}",
    "",
    f"- Status: **{payload['status']}**",
    f"- Main run: `{payload['main_run']}`",
    f"- Regression run: `{payload['regression_run']}`",
    "",
    "## Checks",
]
for c in checks:
    verdict = "PASS" if c["ok"] else "FAIL"
    lines.append(f"- {c['name']}: {c['value']} {c['op']} {c['bound']} -> {verdict}")
lines.append("")
lines.append(f"- Main summary: `{main_path}`")
lines.append(f"- Regression summary: `{reg_path}`")
gate_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

print(json.dumps(payload, ensure_ascii=False, indent=2))
if not all_ok:
    sys.exit(1)
PY

echo "Dialogue release gate complete:"
echo "  - $GATE_JSON"
echo "  - $GATE_MD"
