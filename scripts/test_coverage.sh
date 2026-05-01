#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OVERALL_MIN="${QXFX0_COVERAGE_OVERALL_MIN:-50}"
CRITICAL_MIN="${QXFX0_COVERAGE_CRITICAL_MIN:-55}"
CRITICAL_MODULES="${QXFX0_COVERAGE_CRITICAL_MODULES:-QxFx0.Semantic.Input.Assemble,QxFx0.Semantic.Proposition,QxFx0.Render.Dialogue}"
OUT_DIR="$ROOT/reports/coverage"
mkdir -p "$OUT_DIR"

# 1) Generate fresh coverage artifacts.
cabal test -v0 --enable-coverage qxfx0-test

TIX_PATH="$(find "$ROOT/dist-newstyle" -path '*qxfx0-test/hpc/vanilla/tix/qxfx0-test.tix' | head -n 1)"
if [ -z "$TIX_PATH" ] || [ ! -f "$TIX_PATH" ]; then
  echo "coverage gate failed: missing qxfx0-test.tix" >&2
  exit 1
fi

mapfile -t MIX_DIRS < <(find "$ROOT/dist-newstyle" -type d -path '*hpc/vanilla/mix')
if [ "${#MIX_DIRS[@]}" -eq 0 ]; then
  echo "coverage gate failed: no hpc mix directories found" >&2
  exit 1
fi

HPC_ARGS=()
for mix in "${MIX_DIRS[@]}"; do
  HPC_ARGS+=("--hpcdir=$mix")
done

OVERALL_REPORT="$OUT_DIR/hpc_overall.txt"
PER_MODULE_REPORT="$OUT_DIR/hpc_per_module.txt"

hpc report "$TIX_PATH" "${HPC_ARGS[@]}" > "$OVERALL_REPORT"
hpc report "$TIX_PATH" "${HPC_ARGS[@]}" --per-module > "$PER_MODULE_REPORT"
hpc markup "$TIX_PATH" "${HPC_ARGS[@]}" --destdir="$OUT_DIR/markup" >/dev/null

python3 - "$OVERALL_REPORT" "$PER_MODULE_REPORT" "$OVERALL_MIN" "$CRITICAL_MIN" "$CRITICAL_MODULES" <<'PY'
import json
import re
import statistics
import sys
from pathlib import Path

overall_path = Path(sys.argv[1])
per_module_path = Path(sys.argv[2])
overall_min = float(sys.argv[3])
critical_min = float(sys.argv[4])
critical_modules = [m.strip() for m in sys.argv[5].split(',') if m.strip()]

overall_text = overall_path.read_text(encoding='utf-8', errors='replace')
per_module_text = per_module_path.read_text(encoding='utf-8', errors='replace')

m = re.search(r'([0-9]+(?:\.[0-9]+)?)% expressions used', overall_text)
if not m:
    print('coverage gate failed: cannot parse overall expressions coverage', file=sys.stderr)
    sys.exit(1)
overall_expr = float(m.group(1))

module_expr = {}
current_module = None
for line in per_module_text.splitlines():
    mm = re.match(r'-+<module\s+([^>]+)>-+', line)
    if mm:
        current_module = mm.group(1)
        continue
    em = re.match(r'\s*([0-9]+(?:\.[0-9]+)?)% expressions used', line)
    if em and current_module:
        module_expr[current_module] = float(em.group(1))
        current_module = None

critical_hits = {}
for wanted in critical_modules:
    hit = None
    for actual, score in module_expr.items():
        if actual.endswith('/' + wanted) or actual.endswith('.' + wanted) or actual.endswith(wanted):
            hit = score
            break
    if hit is not None:
        critical_hits[wanted] = hit

if not critical_hits:
    print('coverage gate failed: no critical module coverage entries were found', file=sys.stderr)
    sys.exit(1)

critical_avg = statistics.mean(critical_hits.values())

summary = {
    'overall_expr_percent': overall_expr,
    'overall_threshold': overall_min,
    'critical_expr_percent_by_module': critical_hits,
    'critical_avg_percent': critical_avg,
    'critical_threshold': critical_min,
}

print(json.dumps(summary, ensure_ascii=False, indent=2))

failed = False
if overall_expr < overall_min:
    print(f"coverage gate failed: overall expressions {overall_expr:.2f}% < {overall_min:.2f}%", file=sys.stderr)
    failed = True

for mod, score in critical_hits.items():
    if score < critical_min:
        print(f"coverage gate failed: {mod} expressions {score:.2f}% < {critical_min:.2f}%", file=sys.stderr)
        failed = True

if failed:
    sys.exit(1)
PY

