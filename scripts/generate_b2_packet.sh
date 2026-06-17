#!/usr/bin/env bash
set -euo pipefail

# B2-EXEC-001: Evaluation packet generation harness.
#
# Generates paired transcripts (System vs Control-A) from the fixed
# corpus, randomizes labels, and produces an answer key.
#
# PREREQUISITES (intended env):
# - GHC 9.6.6, cabal 3.10+
# - GF C runtime configured (QXFX0_GF_RUNTIME=1)
# - Morphology resources (paradigms.json + exceptions.json)
# - nix-instantiate on PATH (for governed evidence)
# - QXFX0_GOVERNED_EVIDENCE=1
# - QXFX0_CONCEPTS_PATH=semantics/concepts.nix
#
# USAGE:
#   bash scripts/generate_b2_packet.sh [output-dir]
#
# DEFAULT output: test/fixtures/b2-eval/generated/

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="$ROOT/test/fixtures/b2-eval/corpus.jsonl"
RUBRIC="$ROOT/test/fixtures/b2-eval/rubric-form.md"
PREREG="$ROOT/test/fixtures/b2-eval/pre-registration.md"
CONTROL_CONFIG="$ROOT/test/fixtures/b2-eval/control-a-config.json"
OUTPUT="${1:-$ROOT/test/fixtures/b2-eval/generated}"

mkdir -p "$OUTPUT/system" "$OUTPUT/control-a" "$OUTPUT/blind-pairs"

echo "[1/6] Verifying prerequisites..."
for req in "$CORPUS" "$RUBRIC" "$PREREG" "$CONTROL_CONFIG"; do
  if [ ! -f "$req" ]; then
    echo "FAIL: missing $req"
    exit 1
  fi
done
echo "  corpus: $(wc -l < "$CORPUS") turns"

echo "[2/6] Verifying governed-evidence conditions..."
if [ "${QXFX0_GOVERNED_EVIDENCE:-}" != "1" ]; then
  echo "WARN: QXFX0_GOVERNED_EVIDENCE not set to 1"
  echo "  Transcripts will be EvidenceDegradedGuardUnavailable, not admissible."
  echo "  Set QXFX0_GOVERNED_EVIDENCE=1 for admissible evidence."
  echo "  Continuing anyway for dev/testing..."
fi

echo "[3/6] Generating System transcripts..."
# System: run the full pipeline with all features enabled.
# Each task_id is a multi-turn session; turns within a task are sequential.
 cabal run -v0 qxfx0-main -- --serve-http 0 2>/dev/null &
HTTP_PID=$!
sleep 2

SYSTEM_ARGS=""
TASK_IDS=$(grep -o '"task_id":"[^"]*"' "$CORPUS" | sort -u | sed 's/"task_id":"//;s/"//')

for task_id in $TASK_IDS; do
  echo "  System: $task_id"
  # Extract turns for this task
  grep "\"$task_id\"" "$CORPUS" | while IFS= read -r line; do
    user_text=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_text'])" 2>/dev/null || echo "")
    if [ -n "$user_text" ]; then
      response=$(curl -s -X POST http://localhost:0/turn \
        -H "Content-Type: application/json" \
        -d "{\"session_id\":\"$task_id\",\"input\":\"$user_text\"}" 2>/dev/null || echo "ERROR")
      echo "{\"task_id\":\"$task_id\",\"user\":\"$user_text\",\"system\":\"$response\"}" \
        >> "$OUTPUT/system/${task_id}.jsonl"
    fi
  done
done

kill $HTTP_PID 2>/dev/null || true

echo "[4/6] Generating Control-A transcripts..."
# Control-A: same system with structure-ablated env vars.
export QXFX0_CONTROL_A_DISABLE_ESSENCE=1
export QXFX0_CONTROL_A_DISABLE_ADMISSION=1
export QXFX0_CONTROL_A_DISABLE_REPAIR=1
export QXFX0_CONTROL_A_DISABLE_CONTENT=1

 cabal run -v0 qxfx0-main -- --serve-http 0 2>/dev/null &
HTTP_PID=$!
sleep 2

for task_id in $TASK_IDS; do
  echo "  Control-A: $task_id"
  grep "\"$task_id\"" "$CORPUS" | while IFS= read -r line; do
    user_text=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_text'])" 2>/dev/null || echo "")
    if [ -n "$user_text" ]; then
      response=$(curl -s -X POST http://localhost:0/turn \
        -H "Content-Type: application/json" \
        -d "{\"session_id\":\"ctrl-${task_id}\",\"input\":\"$user_text\"}" 2>/dev/null || echo "ERROR")
      echo "{\"task_id\":\"$task_id\",\"user\":\"$user_text\",\"control_a\":\"$response\"}" \
        >> "$OUTPUT/control-a/${task_id}.jsonl"
    fi
  done
done

kill $HTTP_PID 2>/dev/null || true

echo "[5/6] Creating blind pairs + answer key..."
# For each task, create a blind pair with randomized labels.
python3 - "$OUTPUT" "$TASK_IDS" <<'PYEOF'
import json, os, random, sys, hashlib

output = sys.argv[1]
task_ids = sys.argv[2].split()

random.seed(42)  # reproducible blinding

answer_key = {}
blind_dir = os.path.join(output, "blind-pairs")
os.makedirs(blind_dir, exist_ok=True)

for task_id in task_ids:
    sys_file = os.path.join(output, "system", f"{task_id}.jsonl")
    ctrl_file = os.path.join(output, "control-a", f"{task_id}.jsonl")
    if not os.path.exists(sys_file) or not os.path.exists(ctrl_file):
        print(f"  SKIP {task_id}: missing transcripts")
        continue

    with open(sys_file) as f:
        sys_turns = [json.loads(l) for l in f if l.strip()]
    with open(ctrl_file) as f:
        ctrl_turns = [json.loads(l) for l in f if l.strip()]

    # Randomize: which label gets system, which gets control
    if random.random() < 0.5:
        label_a, label_b = "system", "control_a"
        turns_a, turns_b = sys_turns, ctrl_turns
    else:
        label_a, label_b = "control_a", "system"
        turns_a, turns_b = ctrl_turns, sys_turns

    answer_key[task_id] = {"A": label_a, "B": label_b}

    # Write blind pair
    pair = {
        "task_id": task_id,
        "turns": [
            {
                "turn": i + 1,
                "user": t.get("user", ""),
                "response_A": turns_a[i].get(list(turns_a[i].keys())[-1], "") if i < len(turns_a) else "",
                "response_B": turns_b[i].get(list(turns_b[i].keys())[-1], "") if i < len(turns_b) else "",
            }
            for i, t in enumerate(sys_turns)
        ]
    }
    with open(os.path.join(blind_dir, f"{task_id}.json"), "w") as f:
        json.dump(pair, f, ensure_ascii=False, indent=2)

# Write answer key (separate file, not in blind-pairs)
with open(os.path.join(output, "answer-key.json"), "w") as f:
    json.dump(answer_key, f, ensure_ascii=False, indent=2)

# Hash answer key for integrity
with open(os.path.join(output, "answer-key.json"), "rb") as f:
    h = hashlib.sha256(f.read()).hexdigest()
print(f"  Answer key hash: {h}")
with open(os.path.join(output, "answer-key.sha256"), "w") as f:
    f.write(h)
PYEOF

echo "[6/6] Recording metadata..."
python3 - "$OUTPUT" <<'PYEOF'
import json, os, datetime, hashlib

output = sys.argv[1]
metadata = {
    "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
    "governed_evidence_mode": os.environ.get("QXFX0_GOVERNED_EVIDENCE", "not_set"),
    "concepts_path": os.environ.get("QXFX0_CONCEPTS_PATH", "not_set"),
    "corpus_file": "test/fixtures/b2-eval/corpus.jsonl",
    "rubric_file": "test/fixtures/b2-eval/rubric-form.md",
    "pre_registration_file": "test/fixtures/b2-eval/pre-registration.md",
    "control_a_config": "test/fixtures/b2-eval/control-a-config.json",
    "b3_gate_verdict": "PASS (conjunction Gates 1-5, commit d2e0182)",
    "evidence_admissibility": "all transcripts must carry EvidenceGoverned; see pre-registration.md",
    "m6_felt_status": "NOT PROVEN",
}
with open(os.path.join(output, "packet-metadata.json"), "w") as f:
    json.dump(metadata, f, ensure_ascii=False, indent=2)
print("  metadata written")
PYEOF

echo ""
echo "Done. Output: $OUTPUT"
echo "  system/        — System transcripts (unblinded)"
echo "  control-a/     — Control-A transcripts (unblinded)"
echo "  blind-pairs/   — Blind pairs for raters (randomized labels)"
echo "  answer-key.json — Answer key (KEEP SEPARATE from raters)"
echo "  answer-key.sha256 — Answer key hash"
echo "  packet-metadata.json — Generation metadata + admissibility"
echo ""
echo "Next: copy rubric-form.md + blind-pairs/ to raters."
echo "      DO NOT share answer-key.json with raters."
