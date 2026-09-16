#!/usr/bin/env python3
"""Calibration baseline v1: run a stratified sample through the live
runtime (degraded mode) and record trace fields per stratum.

One fresh session per turn (turn-1 state, no cross-talk). Sequential,
one process at a time — RAM-safe by construction.

Usage: python3 scripts/calibration_baseline.py [N_PER_STRATUM=5]
Output: data/calibration_corpus/baseline_report.json
"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = subprocess.run(["cabal", "list-bin", "exe:qxfx0-main"],
                     capture_output=True, text=True, cwd=ROOT,
                     check=True).stdout.strip().splitlines()[-1]

FIELDS = ["trcContentSource", "trcSubstrateActivated",
          "trcSubstrateEdgesUsed", "trcSubstrateHops",
          "trcFinalFamily", "trcFamilyDivergenceOccurred"]


def run_turn(binpath, db, statedir, text):
    env = dict(os.environ, QXFX0_ROOT=str(ROOT),
               QXFX0_STATE_DIR=statedir, QXFX0_DB=db,
               QXFX0_RUNTIME_MODE="degraded")
    try:
        p = subprocess.run([binpath, "--turn-json", text],
                           capture_output=True, text=True, cwd=ROOT,
                           env=env, timeout=180)
    except OSError:
        # Binary relinked mid-run (cabal build replaces the exe):
        # wait for the new link and retry once.
        import time
        time.sleep(15)
        p = subprocess.run([binpath, "--turn-json", text],
                           capture_output=True, text=True, cwd=ROOT,
                           env=env, timeout=180)
    if p.returncode != 0:
        return {"error": p.stderr[-500:]}
    try:
        resp = json.loads(p.stdout)
    except json.JSONDecodeError:
        return {"error": "bad json: " + p.stdout[-300:]}
    return resp


def main():
    per = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    skip = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    corpus = [json.loads(l) for l in
              open(ROOT / "data/calibration_corpus/corpus.jsonl",
                   encoding="utf-8")]
    strata = {}
    for r in corpus:
        strata.setdefault(r["stratum"], []).append(r)
    sample = []
    for s, rs in sorted(strata.items()):
        step = max(1, len(rs) // per)
        sample.extend(rs[::step][:per])
    sample = sample[skip:]
    print(f"sample={len(sample)} turns (skipped {skip})", flush=True)

    tmp = Path(tempfile.mkdtemp(prefix="calib-base-"))
    db, statedir = str(tmp / "cal.db"), str(tmp / "state")
    os.makedirs(statedir, exist_ok=True)
    results = []
    for i, r in enumerate(sample):
        out = run_turn(BIN, db, statedir, r["input"])
        rec = {"id": r["id"], "stratum": r["stratum"], "input": r["input"]}
        if "error" in out:
            rec["error"] = out["error"]
        else:
            rec["session_id"] = out.get("session_id")
            rec["family"] = out.get("family")
            try:
                c = sqlite3.connect(db)
                tj = c.execute(
                    "select replay_trace_json from turn_quality "
                    "where session_id=? order by turn desc limit 1",
                    (out.get("session_id"),)).fetchone()
                c.close()
                tr = json.loads(tj[0])["trace"] if tj else {}
                for f in FIELDS:
                    rec[f] = tr.get(f)
                ur = tr.get("trcUserRegime") or {}
                rec["protocolB"] = (ur.get("urtCrisis") or {}).get(
                    "cgtProtocolB")
                rec["ontoMove"] = (ur.get("urtOntologicalMove") or {}).get(
                    "ompMoveTag") if ur.get("urtOntologicalMove") else None
                rec["r5score"] = (ur.get("urtUserR5") or {}).get(
                    "ur5ConatusScore")
            except Exception as e:  # noqa: BLE001 — baseline must not die
                rec["error"] = f"trace read: {e}"
        results.append(rec)
        ok = "error" not in rec
        print(f"[{i+1}/{len(sample)}] {r['id']} {r['stratum']} "
              f"family={rec.get('family')} "
              f"src={rec.get('trcContentSource')} ok={ok}", flush=True)

    summary = {"n": len(results),
               "errors": sum(1 for r in results if "error" in r)}
    by_stratum = {}
    for r in results:
        d = by_stratum.setdefault(r["stratum"], {"n": 0, "src": {}})
        d["n"] += 1
        d["src"][str(r.get("trcContentSource"))] = \
            d["src"].get(str(r.get("trcContentSource")), 0) + 1
    report = {"sample_per_stratum": per, "summary": summary,
              "by_stratum": by_stratum, "turns": results}
    outp = ROOT / "data/calibration_corpus/baseline_report.json"
    json.dump(report, outp.open("w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"errors={summary['errors']} wrote {outp}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
