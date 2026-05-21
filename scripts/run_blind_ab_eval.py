#!/usr/bin/env python3
"""
run_blind_ab_eval.py — Blind A/B dialogue quality evaluation harness.

Runs a holdout corpus on two QxFx0 binaries (baseline A vs current B),
extracts objective metrics, and prepares blind pairs for judging.

Usage:
  python3 scripts/run_blind_ab_eval.py --binary-a /tmp/qxfx0-main-baseline-a \
    --binary-b ./dist-newstyle/.../qxfx0-main --corpus scripts/ab_eval_corpus.json \
    --output reports/ab_dialogue/ab-eval-2026-05-21
"""

import argparse
import json
import os
import random
import subprocess
import sys
import tempfile
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

DEFAULT_RUN_ID = "ab-eval-2026-05-21"


def run_turn(binary: str, session_id: str, db_path: str, prompt: str) -> Optional[Dict]:
    """Run a single turn via qxfx0-main --turn-json in degraded mode."""
    env = dict(os.environ)
    env["QXFX0_SESSION_ID"] = session_id
    env["QXFX0_DB"] = db_path
    env["QXFX0_RUNTIME_MODE"] = "degraded"
    env["QXFX0_ROOT"] = str(Path(__file__).parent.parent)
    try:
        result = subprocess.run(
            [binary, "--turn-json", prompt],
            capture_output=True,
            text=True,
            env=env,
            timeout=30,
        )
        # The CLI prints log lines then a JSON object
        lines = result.stdout.strip().splitlines()
        if not lines:
            return None
        # Last line should be JSON
        for line in reversed(lines):
            line = line.strip()
            if line.startswith("{"):
                return json.loads(line)
        return None
    except Exception as e:
        return {"_error": str(e), "response": ""}


def extract_objective_metrics(turn_result: Dict) -> Dict:
    """Extract objective metrics from a turn JSON result."""
    decision = turn_result.get("decision", {})
    metrics = {
        "latency_ms": turn_result.get("total_ms", 0.0),
        "family": turn_result.get("family", "UNKNOWN"),
        "legitimacy": turn_result.get("legitimacy", 0.0),
        "ego_agency": turn_result.get("ego_agency", 0.0),
        "ego_tension": turn_result.get("ego_tension", 0.0),
        "guard_status": turn_result.get("guard_status", ""),
        "render_style": turn_result.get("render_style", ""),
        "move_family": turn_result.get("move_family", ""),
        "illocutionary_force": turn_result.get("illocutionary_force", ""),
        "response_length_chars": len(turn_result.get("response", "")),
        "response_length_words": len(turn_result.get("response", "").split()),
        "shadow_gate_fired": 0,
        "api_healthy": 0,
    }
    # Parse guard status for shadow gate / safety
    gs = metrics["guard_status"]
    if gs and "Unavailable" in str(gs):
        metrics["api_healthy"] = 0
    else:
        metrics["api_healthy"] = 1
    return metrics


def run_session(binary: str, session_id: str, db_path: str, prompts: List[str]) -> List[Dict]:
    """Run a multi-turn session."""
    results = []
    for idx, prompt in enumerate(prompts, start=1):
        t0 = time.time()
        result = run_turn(binary, session_id, db_path, prompt)
        t1 = time.time()
        if result is None:
            result = {"_error": "null_result", "response": "", "input": prompt}
        result["_turn_index"] = idx
        result["_prompt"] = prompt
        result["_wall_time_ms"] = int((t1 - t0) * 1000)
        results.append(result)
    return results


def load_corpus(path: str) -> List[Dict]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def run_ab_eval(binary_a: str, binary_b: str, corpus: List[Dict], output_dir: Path, seed: int = 42) -> Tuple[List[Dict], List[Dict]]:
    """Run full A/B evaluation."""
    output_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)

    all_a = []
    all_b = []

    for task_idx, task in enumerate(corpus, start=1):
        task_id = task["id"]
        prompts = task["prompts"]
        db_a = str(output_dir / f"db_A_{task_id}.sqlite")
        db_b = str(output_dir / f"db_B_{task_id}.sqlite")

        # Clean DBs for isolation
        for db in [db_a, db_b]:
            if os.path.exists(db):
                os.remove(db)

        session_a = f"ab-a-{task_id}"
        session_b = f"ab-b-{task_id}"

        print(f"[Task {task_idx}/{len(corpus)}] {task_id} — {len(prompts)} turns ...", flush=True)
        results_a = run_session(binary_a, session_a, db_a, prompts)
        results_b = run_session(binary_b, session_b, db_b, prompts)

        for r in results_a:
            r["_task_id"] = task_id
            r["_version"] = "A"
        for r in results_b:
            r["_task_id"] = task_id
            r["_version"] = "B"

        all_a.extend(results_a)
        all_b.extend(results_b)

    return all_a, all_b


def write_jsonl(path: Path, rows: List[Dict]):
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def build_blind_pairs(rows_a: List[Dict], rows_b: List[Dict], rng: random.Random) -> List[Dict]:
    """Build turn-level blind pairs with randomized AB/BA order."""
    # Group by task and turn index
    by_task = defaultdict(lambda: {"A": {}, "B": {}})
    for r in rows_a:
        by_task[r["_task_id"]]["A"][r["_turn_index"]] = r
    for r in rows_b:
        by_task[r["_task_id"]]["B"][r["_turn_index"]] = r

    pairs = []
    for task_id in sorted(by_task):
        ta = by_task[task_id]["A"]
        tb = by_task[task_id]["B"]
        turns = sorted(set(ta.keys()) & set(tb.keys()))
        for turn_idx in turns:
            a_first = rng.choice([True, False])
            if a_first:
                first, second = ta[turn_idx], tb[turn_idx]
                first_label, second_label = "first", "second"
            else:
                first, second = tb[turn_idx], ta[turn_idx]
                first_label, second_label = "second", "first"
            pairs.append({
                "task_id": task_id,
                "turn_index": turn_idx,
                "prompt": first["_prompt"],
                "response_1": first.get("response", ""),
                "response_2": second.get("response", ""),
                "version_1_label": first_label,  # which version is first (for unblinding later)
                "version_2_label": second_label,
                "a_first": a_first,
            })
    return pairs


def compute_aggregate_metrics(rows: List[Dict]) -> Dict:
    total = len(rows)
    if total == 0:
        return {}
    latencies = [r.get("_wall_time_ms", 0) for r in rows]
    latencies_sorted = sorted(latencies)
    p50 = latencies_sorted[len(latencies_sorted) // 2] if latencies_sorted else 0
    p95_idx = int(len(latencies_sorted) * 0.95)
    p95 = latencies_sorted[min(p95_idx, len(latencies_sorted) - 1)] if latencies_sorted else 0

    families = defaultdict(int)
    styles = defaultdict(int)
    errors = 0
    for r in rows:
        families[r.get("family", "UNKNOWN")] += 1
        styles[r.get("render_style", "")] += 1
        if r.get("_error") or not r.get("response"):
            errors += 1

    return {
        "total_turns": total,
        "avg_latency_ms": sum(latencies) / len(latencies) if latencies else 0,
        "p50_latency_ms": p50,
        "p95_latency_ms": p95,
        "error_count": errors,
        "error_rate": errors / total,
        "family_distribution": dict(families),
        "style_distribution": dict(styles),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary-a", required=True)
    parser.add_argument("--binary-b", required=True)
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--output", default=f"reports/ab_dialogue/{DEFAULT_RUN_ID}")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    corpus = load_corpus(args.corpus)
    print(f"Loaded corpus: {len(corpus)} tasks, {sum(len(t['prompts']) for t in corpus)} total turns planned")

    rows_a, rows_b = run_ab_eval(args.binary_a, args.binary_b, corpus, output_dir, args.seed)

    write_jsonl(output_dir / "raw_A.jsonl", rows_a)
    write_jsonl(output_dir / "raw_B.jsonl", rows_b)

    rng = random.Random(args.seed)
    pairs = build_blind_pairs(rows_a, rows_b, rng)
    write_jsonl(output_dir / "blind_pairs.jsonl", pairs)

    metrics_a = compute_aggregate_metrics([r for r in rows_a if not r.get("_error")])
    metrics_b = compute_aggregate_metrics([r for r in rows_b if not r.get("_error")])

    summary = {
        "run_id": DEFAULT_RUN_ID,
        "binary_a": args.binary_a,
        "binary_b": args.binary_b,
        "corpus_tasks": len(corpus),
        "total_turns_a": len(rows_a),
        "total_turns_b": len(rows_b),
        "metrics_a": metrics_a,
        "metrics_b": metrics_b,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    with (output_dir / "summary.json").open("w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    print(f"\n=== A/B Eval Complete ===")
    print(f"Output: {output_dir}")
    print(f"A turns: {len(rows_a)} | B turns: {len(rows_b)}")
    print(f"Blind pairs: {len(pairs)}")
    print(f"A error rate: {metrics_a.get('error_rate', 0):.3f}")
    print(f"B error rate: {metrics_b.get('error_rate', 0):.3f}")


if __name__ == "__main__":
    main()
