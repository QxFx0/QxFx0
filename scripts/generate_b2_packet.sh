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
# Rubric contract (2026-08-22 remediation): the EN form is the LOCKED
# pre-registration original; the RU form is its translation (anchors
# unchanged) and is what actually ships to raters.
RUBRIC_LOCKED_EN="$ROOT/test/fixtures/b2-eval/rubric-form.md"
RUBRIC_RATER_RU="$ROOT/test/fixtures/b2-eval/rubric-form-ru.md"
PREREG="$ROOT/test/fixtures/b2-eval/pre-registration.md"
CONTROL_CONFIG="$ROOT/test/fixtures/b2-eval/control-a-config.json"
OUTPUT="${1:-$ROOT/test/fixtures/b2-eval/generated}"

mkdir -p "$OUTPUT/system" "$OUTPUT/control-a" "$OUTPUT/blind-pairs"

echo "[1/7] Verifying prerequisites..."
for req in "$CORPUS" "$RUBRIC_LOCKED_EN" "$RUBRIC_RATER_RU" "$PREREG" "$CONTROL_CONFIG"; do
  if [ ! -f "$req" ]; then
    echo "FAIL: missing $req"
    exit 1
  fi
done
echo "  corpus: $(wc -l < "$CORPUS") turns"

echo "[2/7] Verifying governed-evidence conditions..."
if [ "${QXFX0_GOVERNED_EVIDENCE:-}" != "1" ]; then
  echo "WARN: QXFX0_GOVERNED_EVIDENCE not set to 1"
  echo "  Transcripts will be EvidenceDegradedGuardUnavailable, not admissible."
  echo "  Set QXFX0_GOVERNED_EVIDENCE=1 for admissible evidence."
  echo "  Continuing anyway for dev/testing..."
fi

echo "[3/7] Generating System transcripts..."
# System: run the full pipeline with all features enabled.
# Each task_id is a multi-turn session; turns within a task are sequential.
 cabal run -v0 qxfx0-main -- --serve-http 9180 2>/dev/null &
HTTP_PID=$!

# Warmup: wait for sidecar health endpoint to respond before sending turns
echo "  Warming up sidecar..."
for i in $(seq 1 30); do
  if curl -s http://localhost:9180/sidecar-health >/dev/null 2>&1; then
    echo "  Sidecar ready (attempt $i)"
    break
  fi
  sleep 1
done

TASK_IDS=$(grep -o '"task_id":"[^"]*"' "$CORPUS" | sort -u | sed 's/"task_id":"//;s/"//')

for task_id in $TASK_IDS; do
  echo "  System: $task_id"
  # Extract turns for this task
  grep "\"$task_id\"" "$CORPUS" | while IFS= read -r line; do
    user_text=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_text'])" 2>/dev/null || echo "")
    if [ -n "$user_text" ]; then
      # Bounded retry: up to 3 attempts with 2s gap
      response="ERROR"
      for attempt in 1 2 3; do
        response=$(curl -s --max-time 60 -X POST http://localhost:9180/turn \
          -H "Content-Type: application/json" \
          -d "{\"session_id\":\"$task_id\",\"input\":\"$user_text\"}" 2>/dev/null || echo "ERROR")
        if RESPONSE="$response" python3 - <<'PYEOF'
import json, os, sys

raw = os.environ.get("RESPONSE", "")
if raw == "ERROR" or not raw:
    sys.exit(1)
try:
    payload = json.loads(raw)
except Exception:
    sys.exit(1)
if payload.get("status") == "error":
    sys.exit(1)
PYEOF
        then
          break
        fi
        echo "    retry $attempt for $task_id..."
        sleep 2
      done
      RESPONSE="$response" python3 - <<'PYEOF'
import json, os, sys

raw = os.environ.get("RESPONSE", "")
try:
    payload = json.loads(raw)
except Exception as exc:
    raise SystemExit(f"FAIL: invalid System response JSON: {exc}: {raw[:200]}")
if payload.get("status") == "error":
    raise SystemExit(f"FAIL: System turn failed: {json.dumps(payload, ensure_ascii=False)}")
PYEOF
      python3 -c "
import json, sys
task_id = sys.argv[1]
user_text = sys.argv[2]
response = sys.argv[3]
record = {'task_id': task_id, 'user': user_text, 'response': response}
print(json.dumps(record, ensure_ascii=False))
" "$task_id" "$user_text" "$response" >> "$OUTPUT/system/${task_id}.jsonl"
    fi
  done
done

kill $HTTP_PID 2>/dev/null || true

echo "[4/7] Generating Control-A transcripts..."
# Control-A: same system with structure-ablated env vars.
export QXFX0_CONTROL_A_DISABLE_ESSENCE=1
export QXFX0_CONTROL_A_DISABLE_ADMISSION=1
export QXFX0_CONTROL_A_DISABLE_REPAIR=1
export QXFX0_CONTROL_A_DISABLE_CONTENT=1
export QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST=1

 cabal run -v0 qxfx0-main -- --serve-http 9181 2>/dev/null &
HTTP_PID=$!

# Warmup: wait for sidecar health endpoint
echo "  Warming up Control-A sidecar..."
for i in $(seq 1 30); do
  if curl -s http://localhost:9181/sidecar-health >/dev/null 2>&1; then
    echo "  Control-A sidecar ready (attempt $i)"
    break
  fi
  sleep 1
done

for task_id in $TASK_IDS; do
  echo "  Control-A: $task_id"
  grep "\"$task_id\"" "$CORPUS" | while IFS= read -r line; do
    user_text=$(echo "$line" | python3 -c "import json,sys; print(json.load(sys.stdin)['user_text'])" 2>/dev/null || echo "")
    if [ -n "$user_text" ]; then
      response="ERROR"
      for attempt in 1 2 3; do
        response=$(curl -s --max-time 60 -X POST http://localhost:9181/turn \
          -H "Content-Type: application/json" \
          -d "{\"session_id\":\"ctrl-${task_id}\",\"input\":\"$user_text\"}" 2>/dev/null || echo "ERROR")
        if RESPONSE="$response" python3 - <<'PYEOF'
import json, os, sys

raw = os.environ.get("RESPONSE", "")
if raw == "ERROR" or not raw:
    sys.exit(1)
try:
    payload = json.loads(raw)
except Exception:
    sys.exit(1)
if payload.get("status") == "error":
    sys.exit(1)
PYEOF
        then
          break
        fi
        echo "    retry $attempt for ctrl-$task_id..."
        sleep 2
      done
      RESPONSE="$response" python3 - <<'PYEOF'
import json, os, sys

raw = os.environ.get("RESPONSE", "")
try:
    payload = json.loads(raw)
except Exception as exc:
    raise SystemExit(f"FAIL: invalid Control-A response JSON: {exc}: {raw[:200]}")
if payload.get("status") == "error":
    raise SystemExit(f"FAIL: Control-A turn failed: {json.dumps(payload, ensure_ascii=False)}")
PYEOF
      python3 -c "
import json, sys
task_id = sys.argv[1]
user_text = sys.argv[2]
response = sys.argv[3]
record = {'task_id': task_id, 'user': user_text, 'response': response}
print(json.dumps(record, ensure_ascii=False))
" "$task_id" "$user_text" "$response" >> "$OUTPUT/control-a/${task_id}.jsonl"
    fi
  done
done

kill $HTTP_PID 2>/dev/null || true

echo "[5/7] Creating blind pairs + answer key..."
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

    # Pre-registration evidence admissibility: every transcript must carry
    # EvidenceGoverned. The runtime fail-closes on inadmissible turns under
    # QXFX0_GOVERNED_EVIDENCE=1, but the packet verifies it per turn from the
    # captured guard_status (classifyEvidence: Allowed/Blocked -> governed).
    def guard_evidence(rec):
        try:
            resp = json.loads(rec["response"])
        except Exception:
            return "EvidenceInadmissible"
        tag = resp.get("guard_status", "")
        return "EvidenceGoverned" if tag.startswith("Allowed") or tag.startswith("Blocked") else "EvidenceInadmissible"

    for i, t in enumerate(sys_turns):
        ev_a = guard_evidence(turns_a[i]) if i < len(turns_a) else "EvidenceInadmissible"
        ev_b = guard_evidence(turns_b[i]) if i < len(turns_b) else "EvidenceInadmissible"
        if ev_a != "EvidenceGoverned" or ev_b != "EvidenceGoverned":
            print(f"  FAIL {task_id}: inadmissible evidence (A={ev_a}, B={ev_b})")
            sys.exit(1)

    # Write blind pair
    pair = {
        "task_id": task_id,
        "turns": [
            {
                "turn": i + 1,
                "user": t.get("user", ""),
                "response_A": turns_a[i].get(list(turns_a[i].keys())[-1], "") if i < len(turns_a) else "",
                "response_B": turns_b[i].get(list(turns_b[i].keys())[-1], "") if i < len(turns_b) else "",
                "evidence_A": guard_evidence(turns_a[i]) if i < len(turns_a) else "EvidenceInadmissible",
                "evidence_B": guard_evidence(turns_b[i]) if i < len(turns_b) else "EvidenceInadmissible",
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

echo "[6/7] Recording metadata..."
python3 - "$OUTPUT" <<'PYEOF'
import json, os, datetime, hashlib, subprocess, sys

output = sys.argv[1]

# Pre-registration: the packet script must VERIFY evidence admissibility
# (all transcripts EvidenceGoverned) and record the status in metadata.
admissible = 0
inadmissible = 0
total = 0
for side in ("system", "control-a"):
    side_dir = os.path.join(output, side)
    if not os.path.isdir(side_dir):
        continue
    for fname in sorted(os.listdir(side_dir)):
        if not fname.endswith(".jsonl"):
            continue
        for line in open(os.path.join(side_dir, fname)):
            line = line.strip()
            if not line:
                continue
            total += 1
            rec = json.loads(line)
            try:
                resp = json.loads(rec["response"])
            except Exception:
                inadmissible += 1
                continue
            tag = resp.get("guard_status", "")
            if tag.startswith("Allowed") or tag.startswith("Blocked"):
                admissible += 1
            else:
                inadmissible += 1

verified = inadmissible == 0
try:
    gen_commit = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True, check=True
    ).stdout.strip()
except Exception:
    gen_commit = "unknown"
metadata = {
    "generated_at": datetime.datetime.utcnow().isoformat() + "Z",
    "generated_at_commit": gen_commit,
    "governed_evidence_mode": os.environ.get("QXFX0_GOVERNED_EVIDENCE", "not_set"),
    "concepts_path": os.environ.get("QXFX0_CONCEPTS_PATH", "not_set"),
    "corpus_file": "test/fixtures/b2-eval/corpus.jsonl",
    "rubric_file": "test/fixtures/b2-eval/rubric-form-ru.md",
    "rubric_locked_source": "test/fixtures/b2-eval/rubric-form.md",
    "pre_registration_file": "test/fixtures/b2-eval/pre-registration.md",
    "control_a_config": "test/fixtures/b2-eval/control-a-config.json",
    "b3_gate_verdict": "PASS (conjunction Gates 1-5, commit d2e0182)",
    "protocol_errata": [
        {
            "date": "2026-08-22",
            "issue": "rater rubric switched to Russian translation",
            "detail": "rubric_file is rubric-form-ru.md, a translation of the locked EN "
                      "original (rubric_locked_source); rating anchors are unchanged. "
                      "The locked pre-registration.md was NOT modified (erratum "
                      "discipline: correction recorded here instead).",
        }
    ],
    "evidence_admissibility": {
        "verified": verified,
        "admissible_turns": admissible,
        "inadmissible_turns": inadmissible,
        "total_turns": total,
        "rule": "guard_status in {Allowed, Blocked} -> EvidenceGoverned (classifyEvidence); "
                "runtime fail-closes inadmissible turns under QXFX0_GOVERNED_EVIDENCE=1",
    },
    "m6_felt_status": "NOT PROVEN",
}
if not verified:
    print(f"  FAIL: {inadmissible} inadmissible turn(s) out of {total}")
    sys.exit(1)
with open(os.path.join(output, "packet-metadata.json"), "w") as f:
    json.dump(metadata, f, ensure_ascii=False, indent=2)
print(f"  metadata written (evidence verified: {admissible}/{total} governed)")
PYEOF

echo "[7/7] Building rater package (human-readable, no answer key)..."
python3 - "$OUTPUT" "$(dirname "$0")/../test/fixtures/b2-eval/rubric-form-ru.md" <<'PYEOF'
import json, os, shutil, sys

output = sys.argv[1]
rubric_file = sys.argv[2]
pkg = os.path.join(output, "rater-package")
pairs_dir = os.path.join(pkg, "pairs")
os.makedirs(pairs_dir, exist_ok=True)

def response_text(payload_str):
    try:
        r = json.loads(payload_str)
    except Exception:
        return "(invalid)"
    t = r.get("text") or r.get("surface") or "(no text)"
    return t if isinstance(t, str) else json.dumps(t, ensure_ascii=False)

blind_dir = os.path.join(output, "blind-pairs")
for i, fname in enumerate(sorted(os.listdir(blind_dir)), 1):
    pair = json.load(open(os.path.join(blind_dir, fname)))
    tid = pair["task_id"]
    lines = [f"# Pair {i:02d} — {tid}", ""]
    for t in pair["turns"]:
        lines += [f"### Turn {t['turn']}", "",
                  f"**User:** {t['user']}", "",
                  f"**System A:** {response_text(t['response_A'])}", "",
                  f"**System B:** {response_text(t['response_B'])}", ""]
    with open(os.path.join(pairs_dir, f"pair-{i:02d}-{tid}.md"), "w") as f:
        f.write("\n".join(lines))

shutil.copy2(rubric_file, os.path.join(pkg, "rubric-form.md"))
readme = """# B2 Human-Eval Rater Package

Blind paired discrimination — M6-FELT human-eval leg (B2-EXEC-002).

## Contents
- pairs/ — 10 blind pairs (def-ru-01..05, dist-ru-01..05); labels A/B are randomized per pair
- rubric-form.md — rating form in Russian (translation of the locked
  test/fixtures/b2-eval/rubric-form.md; anchors unchanged): fill one per pair
  (D1, D3, D5, D6 + overall)
- README.md — this file

## Protocol erratum (2026-08-22)
The rating form shipped in this package is the Russian translation
(rubric-form-ru.md) of the locked EN original
(test/fixtures/b2-eval/rubric-form.md); rating anchors are unchanged.
The locked pre-registration.md is intentionally NOT modified; this
erratum and packet-metadata.json (`protocol_errata`) record the
substitution.

## Protocol
1. Read both transcripts of a pair fully before rating.
2. For each dimension fill the forced choice + cite a specific transcript line.
3. Do NOT skip the "Reason" field; uncited ratings are discarded.
4. No answer key exists in this package. Blindness is structural — A/B mapping
   is randomized per pair; do not attempt to infer the mapping from formatting.
5. Total: 10 pairs; estimate ~15 min per pair.

## Locked pre-registration (test/fixtures/b2-eval/pre-registration.md)
- Pass requires System preferred on load-bearing D1 and D3 (independently, no averaging with D5/D6).
- No rubric tweaking after rating starts.
"""
with open(os.path.join(pkg, "README.md"), "w") as f:
    f.write(readme)
print(f"  rater package: {pkg}")
PYEOF

echo ""
echo "Done. Output: $OUTPUT"
echo "  system/        — System transcripts (unblinded)"
echo "  control-a/     — Control-A transcripts (unblinded)"
echo "  blind-pairs/   — Blind pairs for raters (randomized labels)"
echo "  answer-key.json — Answer key (KEEP SEPARATE from raters)"
echo "  answer-key.sha256 — Answer key hash"
echo "  packet-metadata.json — Generation metadata + admissibility"
echo "  rater-package/ — Human-readable blind transcript pairs + rubric (no answer key)"
echo ""
echo "Next: copy rater-package/ (pairs + rubric-form.md + README) to raters."
echo "      DO NOT share answer-key.json with raters."
