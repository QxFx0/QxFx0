#!/usr/bin/env bash
set -euo pipefail

# Thin M7 batch driver: dialogue eval -> golden gate -> slot realizability.
#
# Why this exists: runs `m7-gf-batch-20261108a..d` were produced by a harness
# that lived in /tmp and was lost, so the recorded numbers could not be
# reproduced from the tree.  The pieces were already committed separately
# (run_dialogue_eval_200.sh, m7_gate_check.py, gf_slot_realizability.py); this
# script only chains them, records the tree identity, and (optionally) runs a
# determinism replica.  It changes no runtime, GF, or prompt-file content.
#
# Usage:
#   scripts/run_m7_batch.sh <run_id> [prompts_file]
#
# Defaults: prompts_file = spec/gf/m7_gf_case_30.tsv, runtime mode = strict,
# session mode = isolated (one session per row).
#
# Environment:
#   QXFX0_EVAL_RTS_ARGS="+RTS -s -RTS"
#       per-turn RTS statistics appended to the runtime argv; the RTS report
#       lands in reports/eval_runs/<run_id>/raw/<id>.log (the JSON payload
#       parser skips it).  This is the instrumentation asked for by
#       docs/closure/TURN_STALL_DIAGNOSIS_2026-11-09.md §7.
#   QXFX0_M7_REPLICA=1
#       run a second pass into <run_id>-replica and diff predicate choice and
#       surface per row (bar 5 of the group-2 result, mechanized).
#   QXFX0_M7_SKIP_EVAL=1
#       reuse an existing reports/eval_runs/<run_id> and only re-run the gate
#       and realizability steps.
#   QXFX0_M7_DUMP=<path>
#       reuse an existing corpus dump instead of regenerating it.
#
# Exit codes: 0 = gate passed (and realizability passed, when run),
# 1 = gate or realizability failed, 2 = the run is not evaluable.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RUN_ID="${1:-}"
PROMPTS_FILE="${2:-$ROOT/spec/gf/m7_gf_case_30.tsv}"
if [[ -z "$RUN_ID" ]]; then
  echo "usage: $0 <run_id> [prompts_file]" >&2
  exit 2
fi

OUT_DIR="$ROOT/reports/eval_runs/$RUN_ID"
DUMP_PATH="${QXFX0_M7_DUMP:-$OUT_DIR/corpus-dump.tsv}"
RTS_ARGS="${QXFX0_EVAL_RTS_ARGS:-}"
REPLICA="${QXFX0_M7_REPLICA:-0}"
SKIP_EVAL="${QXFX0_M7_SKIP_EVAL:-0}"

[[ -f "$PROMPTS_FILE" ]] || { echo "prompts file not found: $PROMPTS_FILE" >&2; exit 2; }
mkdir -p "$OUT_DIR"

echo "[1/3] dialogue eval: $RUN_ID"
if [[ "$SKIP_EVAL" == "1" ]]; then
  echo "      skipped (QXFX0_M7_SKIP_EVAL=1); reusing $OUT_DIR"
  [[ -f "$OUT_DIR/results.jsonl" ]] || { echo "no results.jsonl in $OUT_DIR" >&2; exit 2; }
else
  QXFX0_RUNTIME_MODE=strict \
  QXFX0_EVAL_SESSION_MODE=isolated \
  QXFX0_EVAL_RTS_ARGS="$RTS_ARGS" \
  bash "$ROOT/scripts/run_dialogue_eval_200.sh" "$RUN_ID" "$PROMPTS_FILE"
fi

echo "[2/3] golden gate"
# Read the trace from the same database the eval wrote to (meta.env records the
# resolved path; the eval mirrors QxFx0.Runtime.Paths.resolveDbPath).
EVAL_DB_PATH="$(sed -n 's/^db_path=//p' "$OUT_DIR/meta.env" 2>/dev/null | tail -1 || true)"
GATE_ARGS=()
if [[ -n "$EVAL_DB_PATH" ]]; then
  GATE_ARGS=(--db "$EVAL_DB_PATH")
fi
GATE_RC=0
python3 "$ROOT/scripts/m7_gate_check.py" "$OUT_DIR" "${GATE_ARGS[@]}" >"$OUT_DIR/gate-check.txt" 2>&1 || GATE_RC=$?
tail -n 3 "$OUT_DIR/gate-check.txt" || true
[[ "$GATE_RC" -eq 0 ]] || echo "      gate exit=$GATE_RC (see gate-check.txt)" >&2

echo "[3/3] slot realizability"
if [[ -n "${QXFX0_M7_DUMP:-}" && -f "${QXFX0_M7_DUMP}" ]]; then
  echo "      using existing dump: $QXFX0_M7_DUMP"
else
  # Regenerate the runtime corpus dump; the measurement report is logged next
  # to it so the frozen-gap numbers stay auditable.
  python3 "$ROOT/scripts/eval/gf_slot_gap.py" --write-dump "$DUMP_PATH" \
    >"$OUT_DIR/corpus-dump.log" 2>&1 || {
      echo "corpus dump failed; see $OUT_DIR/corpus-dump.log" >&2
      exit 2
    }
  echo "      dump: $DUMP_PATH ($(wc -l <"$DUMP_PATH") lines)"
fi
REAL_RC=0
python3 "$ROOT/scripts/eval/gf_slot_realizability.py" --dump "$DUMP_PATH" \
  >"$OUT_DIR/slot-realizability.txt" 2>&1 || REAL_RC=$?
tail -n 5 "$OUT_DIR/slot-realizability.txt" || true
[[ "$REAL_RC" -eq 0 ]] || echo "      realizability exit=$REAL_RC (see slot-realizability.txt)" >&2

if [[ "$REPLICA" == "1" ]]; then
  echo "[replica] second pass: ${RUN_ID}-replica"
  QXFX0_RUNTIME_MODE=strict \
  QXFX0_EVAL_SESSION_MODE=isolated \
  QXFX0_EVAL_RTS_ARGS="$RTS_ARGS" \
  bash "$ROOT/scripts/run_dialogue_eval_200.sh" "${RUN_ID}-replica" "$PROMPTS_FILE"
  DET_RC=0
  python3 "$ROOT/scripts/eval/m7_compare.py" \
    "$OUT_DIR" "$ROOT/reports/eval_runs/${RUN_ID}-replica" \
    >"$OUT_DIR/determinism.txt" 2>&1 || DET_RC=$?
  [[ "$DET_RC" -eq 0 ]] || echo "      determinism exit=$DET_RC (see determinism.txt)" >&2
else
  DET_RC=""
fi

{
  echo "harness=scripts/run_m7_batch.sh"
  echo "harness_git_head=$(git rev-parse HEAD)"
  echo "harness_git_dirty=$(if [[ -n "$(git status --porcelain)" ]]; then echo 1; else echo 0; fi)"
  echo "prompts_sha256=$(sha256sum "$PROMPTS_FILE" | cut -d' ' -f1)"
  echo "dump_path=$DUMP_PATH"
  if [[ -f "$DUMP_PATH" ]]; then
    echo "dump_sha256=$(sha256sum "$DUMP_PATH" | cut -d' ' -f1)"
    echo "dump_lines=$(wc -l <"$DUMP_PATH")"
  fi
  echo "gate_exit=$GATE_RC"
  echo "realizability_exit=$REAL_RC"
  echo "replica=$REPLICA"
  echo "determinism_exit=${DET_RC:-not_run}"
} >>"$OUT_DIR/meta.env"

echo
echo "M7 batch complete: $OUT_DIR"
echo "  - gate:           $OUT_DIR/gate-check.txt (exit $GATE_RC)"
echo "  - realizability:  $OUT_DIR/slot-realizability.txt (exit $REAL_RC)"
echo "  - meta:           $OUT_DIR/meta.env"

if [[ "$GATE_RC" -ne 0 ]]; then
  exit "$GATE_RC"
fi
if [[ "$REAL_RC" -ne 0 ]]; then
  exit "$REAL_RC"
fi
if [[ -n "$DET_RC" && "$DET_RC" -ne 0 ]]; then
  exit "$DET_RC"
fi
exit 0
