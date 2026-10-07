#!/usr/bin/env python3
"""Cutover Stage 1a gate battery (ADR-0055, pre-registered 2026-10-07).

Fixed 10-turn battery: 5 seedable ownership events (canonical
order, explicit parties) + 5 controls (must NOT fire). Asserts
gate fires exactly where specified and abstains elsewhere.
Surfaces must be byte-identical to the pre-wiring baseline
(/tmp/opencode/gate_baseline_saved.jsonl pattern): any delta
is triaged before landing.

Usage: python3 scripts/gate_battery_stage1a.py [--baseline PATH]
  --baseline PATH: write responses for later diff instead of asserting.
Sequential, one process at a time. No pushes, no network.
"""
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

TURNS = [
    ("gate-give", "Аня подарила книгу Боре", True),
    ("gate-lend", "Аня одолжила книгу Боре", True),
    ("gate-show", "Аня показала книгу Боре", True),
    ("gate-take", "Боря взял книгу у Ани", True),
    ("gate-steal", "Боря украл книгу у Ани", True),
    ("ctl-define", "что такое свобода?", False),
    ("ctl-contact", "привет", False),
    ("ctl-nomatch", "Аня и Боря гуляли", False),
    ("ctl-pronoun", "Мне Аня одолжила книгу", False),
    ("ctl-single", "Я одолжил книгу", False),
]


def main():
    baseline = None
    if "--baseline" in sys.argv[1:]:
        i = sys.argv.index("--baseline")
        baseline = sys.argv[i + 1]
    binpath = subprocess.run(
        ["cabal", "list-bin", "exe:qxfx0-main"],
        capture_output=True, text=True, cwd=ROOT,
        check=True).stdout.strip().splitlines()[-1]
    outf = open(baseline, "w", encoding="utf-8") if baseline else None
    try:
        failures = []
        for sess, text, must_fire in TURNS:
            tmp = Path(tempfile.mkdtemp(prefix="gate-"))
            db, statedir = str(tmp / "cal.db"), str(tmp / "state")
            os.makedirs(statedir, exist_ok=True)
            env = dict(os.environ, QXFX0_ROOT=str(ROOT),
                       QXFX0_STATE_DIR=statedir, QXFX0_DB=db,
                       QXFX0_RUNTIME_MODE="degraded")
            p = subprocess.run(
                [binpath, "--turn-json", text, "--session-id", sess],
                capture_output=True, text=True, cwd=ROOT,
                env=env, timeout=300)
            if p.returncode != 0:
                print(f"SKIP {text!r}: {p.stderr[-200:]}", flush=True)
                failures.append(sess)
                continue
            out = json.loads(p.stdout)
            c = sqlite3.connect(db)
            tj = c.execute(
                "select replay_trace_json from turn_quality "
                "where session_id=? order by turn desc limit 1",
                (sess,)).fetchone()
            c.close()
            tr = json.loads(tj[0])["trace"] if tj else {}
            cmp = tr.get("trcOwnershipCompare")
            fired = bool(cmp and cmp.get("octGateFired"))
            if outf is not None:
                outf.write(json.dumps(
                    {"sess": sess, "input": text,
                     "response": out.get("response"),
                     "family": out.get("family")},
                    ensure_ascii=False) + "\n")
            else:
                status = "ok" if fired == must_fire else "MISMATCH"
                print(f"[{status}] {sess}: fired={fired} "
                      f"expected={must_fire} "
                      f"reason={(cmp or {}).get('octGateReason')} "
                      f"verdict={(cmp or {}).get('octVerdict')}",
                      flush=True)
                if fired != must_fire:
                    failures.append(sess)
        if outf is None:
            if failures:
                print(f"GATE FAILURES: {failures}")
                return 1
            print("gate battery green")
        return 0
    finally:
        if outf is not None:
            outf.close()


if __name__ == "__main__":
    sys.exit(main())
