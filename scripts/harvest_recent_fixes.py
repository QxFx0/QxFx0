#!/usr/bin/env python3
"""Targeted harvest for consent/backchannel/recovery-lead fixes (2026-10-03).

Scripted (non-interactive) battery: consent-trio continuity,
fresh consent/backchannel holds, понятно baseline (refusal
behavior, for the future atom-path work), contact/definitional
controls. All in degraded mode, so recovery leads are visible.
Appends to data/calibration_corpus/live_dialogues.jsonl with
null labels (rating happens separately, assistant-pre after
frame agreement).

Usage: python3 scripts/harvest_recent_fixes.py [--dry-run]
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
OUTP = str(ROOT / "data/calibration_corpus" / "live_dialogues.jsonl")

SESSIONS = [
    ("rc-consent-cont", [
        "что такое свобода?",
        "ладно",
        "хорошо",
        "давай",
    ]),
    ("rc-fresh-ladno", ["ладно"]),
    ("rc-fresh-horosho", ["хорошо"]),
    ("rc-fresh-davai", ["давай"]),
    ("rc-fresh-aga", ["ага"]),
    ("rc-fresh-ugu", ["угу"]),
    ("rc-ponyatno-fresh", ["понятно"]),
    ("rc-ponyatno-cont", [
        "что такое ответственность?",
        "понятно",
    ]),
    ("rc-controls", [
        "привет",
        "спасибо",
        "что такое справедливость?",
    ]),
]

FIELDS = ["trcContentSource", "trcBestTopic", "trcDialogueFocus",
          "trcFinalFamily", "trcFamilyDivergenceOccurred",
          "trcSubstrateEdgesUsed", "trcSubstrateHops",
          "trcRecoveryCause", "trcRecoveryStrategy",
          "trcDerivationTags", "trcGenerationTrace",
          "trcLegitimacyReason", "trcConatusGateFired",
          "trcEmittedPredicates", "trcSelectorDiagnostics",
          "trcResponsePlan"]


def next_id(path):
    n = 0
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            if '"id": "live-' in line:
                n += 1
    return n


def main():
    dry = "--dry-run" in sys.argv[1:]
    binpath = subprocess.run(
        ["cabal", "list-bin", "exe:qxfx0-main"],
        capture_output=True, text=True, cwd=ROOT,
        check=True).stdout.strip().splitlines()[-1]
    seq = next_id(OUTP)
    if dry:
        print(f"would append after live-{seq:04d}")
        return 0
    outf = open(OUTP, "a", encoding="utf-8")
    try:
        for sess_name, turns in SESSIONS:
            tmp = Path(tempfile.mkdtemp(prefix="harvest-"))
            db, statedir = str(tmp / "cal.db"), str(tmp / "state")
            os.makedirs(statedir, exist_ok=True)
            env = dict(os.environ, QXFX0_ROOT=str(ROOT),
                       QXFX0_STATE_DIR=statedir, QXFX0_DB=db,
                       QXFX0_RUNTIME_MODE="degraded")
            session_id = f"harvest-{sess_name}"
            for text in turns:
                p = subprocess.run(
                    [binpath, "--turn-json", text,
                     "--session-id", session_id],
                    capture_output=True, text=True, cwd=ROOT,
                    env=env, timeout=180)
                if p.returncode != 0:
                    print(f"SKIP {text!r}: {p.stderr[-200:]}",
                          flush=True)
                    continue
                try:
                    out = json.loads(p.stdout)
                except Exception:
                    print(f"SKIP bad json {text!r}", flush=True)
                    continue
                c = sqlite3.connect(db)
                tj = c.execute(
                    "select replay_trace_json from turn_quality "
                    "where session_id=? order by turn desc limit 1",
                    (session_id,)).fetchone()
                c.close()
                tr = json.loads(tj[0])["trace"] if tj else {}
                seq += 1
                rec = {"id": f"live-{seq:04d}", "corpusVersion": 1,
                       "stratum": "live_dialogue",
                       "input": text, "topic": "",
                       "labels": {"predicate_relevant": None,
                                  "challenge_strength": None,
                                  "response_acceptable": None,
                                  "crisis_expected": False},
                       "prelabel": None,
                       "provenance": "scripted_probe",
                       "rater_id": "assistant",
                       "session_id": session_id,
                       "response": out.get("response"),
                       "family": out.get("family"),
                       "trace": {f: tr.get(f) for f in FIELDS}}
                outf.write(json.dumps(rec, ensure_ascii=False) + "\n")
                outf.flush()
                print(f"+ live-{seq:04d} [{sess_name}] {text[:50]}",
                      flush=True)
    finally:
        outf.close()
    print(f"done: {OUTP}")


if __name__ == "__main__":
    sys.exit(main())
