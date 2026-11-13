#!/usr/bin/env bash
set -euo pipefail

# Multi-turn user-regime capture (concept v3).
#
# One CLI process per turn: that is the only multi-turn path the runtime
# offers (session state is persisted and restored per invocation).  The
# capture writes to its own database, never to the operator's local DB.
#
# Pre-registration: docs/closure/USER_REGIME_CAPTURE_PREREG_2026-11-13.md
#
# usage: scripts/run_user_regime_capture.sh <run_id> [corpus.tsv]
#
# env:
#   QXFX0_CAPTURE_LIMIT=<n>       run only the first n rows (smoke test)
#   QXFX0_CAPTURE_RESUME=1        append to an existing run directory
#   QXFX0_CAPTURE_SKIP_EVAL=1     reuse the run's DB and re-run report + gate only
#   QXFX0_CAPTURE_TURN_TIMEOUT=600  per-turn wall-clock limit (seconds)
#   QXFX0_RUNTIME_MODE=degraded   runtime mode passed to the CLI

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_ID="${1:-}"
CORPUS="${2:-$ROOT/spec/eval/user_regime_multiturn_2026-11-13.tsv}"
LIMIT="${QXFX0_CAPTURE_LIMIT:-0}"
RESUME="${QXFX0_CAPTURE_RESUME:-0}"
SKIP_EVAL="${QXFX0_CAPTURE_SKIP_EVAL:-0}"
TURN_TIMEOUT="${QXFX0_CAPTURE_TURN_TIMEOUT:-600}"
RUNTIME_MODE="${QXFX0_RUNTIME_MODE:-degraded}"

if [[ -z "$RUN_ID" ]]; then
  echo "usage: $0 <run_id> [corpus.tsv]" >&2
  exit 2
fi
if [[ ! -f "$CORPUS" ]]; then
  echo "corpus not found: $CORPUS" >&2
  exit 1
fi

OUT_DIR="$ROOT/reports/eval_runs/$RUN_ID"
DB="$OUT_DIR/capture.db"
RAW_DIR="$OUT_DIR/raw"
RESULTS_JSONL="$OUT_DIR/results.jsonl"
META="$OUT_DIR/meta.env"

if [[ -e "$DB" && "$RESUME" != "1" && "$SKIP_EVAL" != "1" ]]; then
  echo "refusing to reuse an existing capture DB: $DB" >&2
  echo "set QXFX0_CAPTURE_RESUME=1 to append, or pick a new run id" >&2
  exit 1
fi
mkdir -p "$RAW_DIR"
if [[ "$RESUME" != "1" ]]; then
  : >"$RESULTS_JSONL"
fi

# ---------------------------------------------------------------------------
# Pre-flight: corpus shape.  Fails loudly on a malformed row; the reader and
# the gate below assume contiguous turns and unique (dialogue, turn) keys.
# ---------------------------------------------------------------------------
ROW_COUNT="$(CORPUS="$CORPUS" LIMIT="$LIMIT" python3 - <<'PY'
import os
import sys
from pathlib import Path

path = Path(os.environ["CORPUS"])
limit = int(os.environ["LIMIT"])
rows = []
for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
    if not line or line.startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) != 4:
        sys.exit(f"{path}:{number}: expected 4 tab-separated columns, got {len(parts)}")
    dialogue, turn, prompt, arc = parts
    if not dialogue or not prompt or not arc:
        sys.exit(f"{path}:{number}: empty dialogue/prompt/arc")
    if not turn.isdigit():
        sys.exit(f"{path}:{number}: turn is not an integer: {turn!r}")
    rows.append((dialogue, int(turn)))

if not rows:
    sys.exit(f"{path}: no data rows")

seen = set()
by_dialogue = {}
for dialogue, turn in rows:
    key = (dialogue, turn)
    if key in seen:
        sys.exit(f"{path}: duplicate row {key}")
    seen.add(key)
    by_dialogue.setdefault(dialogue, []).append(turn)

for dialogue, turns in by_dialogue.items():
    expected = list(range(1, len(turns) + 1))
    if sorted(turns) != expected:
        sys.exit(f"{path}: dialogue {dialogue!r} turns {sorted(turns)} are not 1..{len(turns)}")

selected = rows[:limit] if limit > 0 else rows
print(len(selected))
PY
)"

DIALOGUE_COUNT="$(CORPUS="$CORPUS" LIMIT="$LIMIT" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["CORPUS"])
limit = int(os.environ["LIMIT"])
rows = []
for line in path.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    dialogue, turn, _prompt, _arc = line.split("\t")
    rows.append((dialogue, int(turn)))
if limit > 0:
    rows = rows[:limit]
print(len({dialogue for dialogue, _ in rows}))
PY
)"

# ---------------------------------------------------------------------------
# Tree and binary identity.  A capture whose tree moved underneath it is not
# reproducible, so both are recorded before the first turn.
# ---------------------------------------------------------------------------
BIN="$(cabal list-bin qxfx0-main)"
BIN_SHA="$(sha256sum "$BIN" | cut -d' ' -f1)"
CORPUS_SHA="$(sha256sum "$CORPUS" | cut -d' ' -f1)"
GIT_HEAD="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
GIT_DIRTY="$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$SKIP_EVAL" == "1" ]]; then
  echo "report_rerun_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$META"
else
  {
    echo "run_id=$RUN_ID"
    echo "corpus=$CORPUS"
    echo "corpus_sha256=$CORPUS_SHA"
    echo "rows=$ROW_COUNT"
    echo "dialogues=$DIALOGUE_COUNT"
    echo "runtime_mode=$RUNTIME_MODE"
    echo "db=$DB"
    echo "binary=$BIN"
    echo "binary_sha256=$BIN_SHA"
    echo "git_head=$GIT_HEAD"
    echo "git_dirty_files=$GIT_DIRTY"
    echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } | tee "$META"
fi

if [[ "$GIT_DIRTY" != "0" ]]; then
  echo "warning: working tree has $GIT_DIRTY modified/untracked files; the capture is not a clean-tree run" >&2
fi

# ---------------------------------------------------------------------------
# Capture loop
# ---------------------------------------------------------------------------
CORPUS="$CORPUS" LIMIT="$LIMIT" python3 - <<'PY' >"$OUT_DIR/plan.tsv"
import os
from pathlib import Path

path = Path(os.environ["CORPUS"])
limit = int(os.environ["LIMIT"])
rows = []
for line in path.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    rows.append(line)
if limit > 0:
    rows = rows[:limit]
print("\n".join(rows))
PY

if [[ "$SKIP_EVAL" == "1" ]]; then
  echo "skipping the capture loop (QXFX0_CAPTURE_SKIP_EVAL=1); re-running report and gate"
  [[ -f "$RESULTS_JSONL" ]] || { echo "no results.jsonl in $OUT_DIR" >&2; exit 2; }
fi

index=0
while [[ "$SKIP_EVAL" != "1" ]] && IFS=$'\t' read -r dialogue turn prompt arc; do
  [[ -z "$dialogue" ]] && continue
  index=$((index + 1))
  session_id="cap-$RUN_ID-$dialogue"
  raw_file="$RAW_DIR/$dialogue-$turn.json"
  start_ms=$(date +%s%3N)
  # shellcheck disable=SC2086
  if ! timeout "$TURN_TIMEOUT" env QXFX0_DB="$DB" QXFX0_RUNTIME_MODE="$RUNTIME_MODE" \
      "$BIN" --session "$session_id" --input "$prompt" --json >"$raw_file" 2>"$RAW_DIR/$dialogue-$turn.err"; then
    echo "turn failed: $dialogue/$turn (see $RAW_DIR/$dialogue-$turn.err)" >&2
    echo "{\"dialogue\": \"$dialogue\", \"turn\": $turn, \"status\": \"driver_error\"}" >>"$RESULTS_JSONL"
    continue
  fi
  end_ms=$(date +%s%3N)
  latency_ms=$((end_ms - start_ms))

  RAW_FILE="$raw_file" DIALOGUE="$dialogue" TURN="$turn" PROMPT="$prompt" ARC="$arc" \
  LATENCY_MS="$latency_ms" SESSION_ID="$session_id" >>"$RESULTS_JSONL" \
  python3 - <<'PY'
import json
import os
from pathlib import Path

raw = Path(os.environ["RAW_FILE"]).read_text(encoding="utf-8", errors="replace")
payload = None
for line in reversed(raw.splitlines()):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        payload = json.loads(line)
        break
    except json.JSONDecodeError:
        continue

record = {
    "dialogue": os.environ["DIALOGUE"],
    "turn": int(os.environ["TURN"]),
    "arc": os.environ["ARC"],
    "prompt": os.environ["PROMPT"],
    "session_id": os.environ["SESSION_ID"],
    "latency_ms": int(os.environ["LATENCY_MS"]),
}
if isinstance(payload, dict):
    record.update(
        {
            "status": payload.get("status"),
            "turns": payload.get("turns"),
            "family": payload.get("family") or payload.get("move_family"),
            "response": payload.get("response") or payload.get("text"),
        }
    )
else:
    record["status"] = "parse_error"
print(json.dumps(record, ensure_ascii=False))
PY

  if (( index % 10 == 0 )); then
    echo "progress: $index/$ROW_COUNT turns" >&2
  fi
done <"$OUT_DIR/plan.tsv"

echo "last_turn_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$META"

# ---------------------------------------------------------------------------
# Report + structural gate
# ---------------------------------------------------------------------------
python3 "$ROOT/scripts/eval/user_regime_report.py" \
  --db "$DB" --session-prefix "cap-$RUN_ID-" \
  >"$OUT_DIR/regime-report.txt"
python3 "$ROOT/scripts/eval/user_regime_report.py" \
  --db "$DB" --session-prefix "cap-$RUN_ID-" --json \
  >"$OUT_DIR/regime-report.json"

REPORT="$OUT_DIR/regime-report.json" ROWS="$ROW_COUNT" DIALOGUES="$DIALOGUE_COUNT" \
python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

report = json.loads(Path(os.environ["REPORT"]).read_text(encoding="utf-8"))
rows = int(os.environ["ROWS"])
dialogues = int(os.environ["DIALOGUES"])

hard_trigger_b = sum(
    count
    for cause, count in (report.get("protocol_b_causes") or {}).items()
    if cause != "contour_exit"
)
checks = [
    ("turns persisted", report["turns_scanned"], rows),
    ("regime records", report["turns_with_regime"], rows),
    ("missing regime", report["missing_regime"], 0),
    # A contour exit IS Protocol B by the two-protocol law; only a hard
    # lexical trigger is a safety event the capture must never produce.
    ("hard-trigger Protocol B", hard_trigger_b, 0),
    ("protocol B == contour exits", report["protocol_b"], report["contour_exits"]),
    ("encoder versions", report["encoder_versions"], [1]),
    ("residual samples", report["residual"]["n"], rows - dialogues),
    ("window samples", report["window"]["n"], rows - dialogues),
]
failed = 0
for name, actual, expected in checks:
    ok = actual == expected
    failed += 0 if ok else 1
    print(f"{'PASS' if ok else 'FAIL'}  {name}: {actual} (expected {expected})")

print(f"\nmeasured: exits={report['contour_exits']} {report['contour_exit_classes']}"
      f" moves={report['moves']} {report['move_tags']}"
      f" affirm_gate={report['affirm_gate_passed']}"
      f" residual_mean={report['residual']['mean']}"
      f" residual_max={report['residual']['max']}"
      f" window_max={report['window']['max']}")
print(f"flags: {report['flags']}")

sys.exit(1 if failed else 0)
PY
