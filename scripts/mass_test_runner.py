#!/usr/bin/env python3
"""Mass test runner — run scenarios against service-mode binary.

From QxFx4: collect latency and guard counts, fresh DB per run.
"""

import json
import os
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCENARIOS = ROOT / "data" / "scenarios"
BIN = os.environ.get("QXFX0_BIN", str(ROOT / "dist" / "build" / "qxfx0-main" / "qxfx0-main"))
SCHEMA = ROOT / "spec" / "sql" / "schema.sql"
SEEDS = sorted(ROOT / "spec" / "sql" / f for f in (ROOT / "spec" / "sql").glob("seed_*.sql"))
RESULTS_DIR = ROOT / "data" / "results"

def fresh_db(path):
    if path.exists():
        path.unlink()
    conn = sqlite3.connect(str(path))
    if SCHEMA.exists():
        conn.executescript(SCHEMA.read_text())
    for seed in SEEDS:
        conn.executescript(seed.read_text())
    conn.close()

def run_turn(session_id, user_input):
    t0 = time.monotonic()
    try:
        proc = subprocess.run(
            [BIN, "--session", session_id, "--input", user_input, "--json"],
            capture_output=True, text=True, timeout=10,
            preexec_fn=os.setpgrp,
        )
        elapsed = time.monotonic() - t0
        if proc.returncode != 0:
            return {"error": "nonzero", "rc": proc.returncode, "latency": elapsed}
        try:
            data = json.loads(proc.stdout)
        except json.JSONDecodeError:
            return {"error": "bad_json", "latency": elapsed}
        guard_count = data.get("guard_count", data.get("guard_hits", 0))
        return {"family": data.get("family"), "force": data.get("force"),
                "guard_count": guard_count, "latency": elapsed, "ok": True}
    except subprocess.TimeoutExpired:
        elapsed = time.monotonic() - t0
        return {"error": "timeout", "latency": elapsed}
    except FileNotFoundError:
        return {"error": "binary_missing"}

def run_scenario(scenario_path, db_path):
    with open(scenario_path, encoding="utf-8") as f:
        scenario = json.load(f)
    sid = scenario["scenario_id"]
    turns = scenario["turns"]
    fresh_db(db_path)
    results = []
    for idx, turn_input in enumerate(turns):
        r = run_turn(sid, turn_input)
        r["turn"] = idx
        r["input"] = turn_input[:80]
        results.append(r)
        status = "ok" if r.get("ok") else r.get("error", "?")
        lat = f"{r.get('latency',0):.3f}s" if "latency" in r else "?"
        gc = r.get("guard_count", "?")
        print(f"  [{sid} t{idx:02d}] {status} lat={lat} guards={gc}")
    return {"scenario_id": sid, "primary_theme": scenario.get("primary_theme"),
            "turns": results}

def main():
    if not SCENARIOS.exists():
        print("No scenarios found. Run mass_test_generator.py first.")
        sys.exit(1)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    scenario_files = sorted(SCENARIOS.glob("scenario_*.json"))
    if not scenario_files:
        print("No scenario JSON files found.")
        sys.exit(1)
    all_results = []
    for sf in scenario_files:
        db_path = RESULTS_DIR / f"smoke_{sf.stem}.db"
        print(f"Running {sf.name} ...")
        result = run_scenario(sf, db_path)
        all_results.append(result)
        ok_count = sum(1 for t in result["turns"] if t.get("ok"))
        latencies = [t["latency"] for t in result["turns"] if "latency" in t and t.get("ok")]
        avg_lat = sum(latencies) / len(latencies) if latencies else 0
        max_lat = max(latencies) if latencies else 0
        total_guards = sum(t.get("guard_count", 0) for t in result["turns"] if isinstance(t.get("guard_count"), int))
        print(f"  => {ok_count}/{len(result['turns'])} ok, avg_lat={avg_lat:.3f}s, "
              f"max_lat={max_lat:.3f}s, total_guards={total_guards}")
    summary_path = RESULTS_DIR / "summary.json"
    summary_path.write_text(json.dumps(all_results, ensure_ascii=False, indent=2), encoding="utf-8")
    total_ok = sum(1 for r in all_results for t in r["turns"] if t.get("ok"))
    total_turns = sum(len(r["turns"]) for r in all_results)
    print(f"\nSummary: {total_ok}/{total_turns} turns ok, saved to {summary_path}")
    sys.exit(0 if total_ok == total_turns else 1)

if __name__ == "__main__":
    main()
