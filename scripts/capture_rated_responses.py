#!/usr/bin/env python3
"""Capture response surfaces for rated turns (predicate_relevant needs
the emitted text, which baseline_report.json does not store).

Usage: python3 scripts/capture_rated_responses.py <ids-file>
IDs file: one cal-ID per line. Output: data/calibration_corpus/
rated_responses.json — {id, input, response, family}.
Sequential, one process at a time.
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = subprocess.run(["cabal", "list-bin", "exe:qxfx0-main"],
                     capture_output=True, text=True, cwd=ROOT,
                     check=True).stdout.strip().splitlines()[-1]


def main():
    ids = [l.strip() for l in open(sys.argv[1], encoding="utf-8")
           if l.strip()]
    corpus = {json.loads(l)["id"]: json.loads(l) for l in
              open(ROOT / "data/calibration_corpus/corpus.jsonl",
                   encoding="utf-8")}
    tmp = Path(tempfile.mkdtemp(prefix="calib-rated-"))
    db, statedir = str(tmp / "cal.db"), str(tmp / "state")
    os.makedirs(statedir, exist_ok=True)
    out = []
    for i, cid in enumerate(ids):
        r = corpus[cid]
        env = dict(os.environ, QXFX0_ROOT=str(ROOT),
                   QXFX0_STATE_DIR=statedir, QXFX0_DB=db,
                   QXFX0_RUNTIME_MODE="degraded")
        try:
            p = subprocess.run(
                [BIN, "--turn-json", r["input"]], capture_output=True,
                text=True, cwd=ROOT, env=env, timeout=180)
            resp = json.loads(p.stdout)
            out.append({"id": cid, "input": r["input"],
                        "response": resp.get("response"),
                        "family": resp.get("family")})
            ok = True
        except Exception as e:  # noqa: BLE001 — capture must not die
            out.append({"id": cid, "input": r["input"],
                        "error": str(e)[-300:]})
            ok = False
        print(f"[{i+1}/{len(ids)}] {cid} ok={ok}", flush=True)
    dest = ROOT / "data/calibration_corpus/rated_responses.json"
    json.dump(out, dest.open("w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"wrote {dest}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
