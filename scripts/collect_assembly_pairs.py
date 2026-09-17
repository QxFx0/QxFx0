#!/usr/bin/env python3
"""Collect the assembly_pairs rating stratum (COMPOSER_DESIGN.md).

Runs distinction/relation inputs (linked-topic pairs) through the live
runtime and harvests trcAssemblyCandidates into
data/calibration_corpus/assembly_pairs.jsonl with null labels
(assembly_coherent / assembly_grounded in {0,1,2}, human-rated later).

Sequential, one process at a time. Turns with zero candidates are
dropped (nothing to rate).
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


def main():
    want = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    corpus = [json.loads(l) for l in
              open(ROOT / "data/calibration_corpus/corpus.jsonl",
                   encoding="utf-8")]
    pool = [r for r in corpus if r["stratum"] in
            ("covered_distinction", "covered_relation")]
    uncovered = {r["topic"] for r in corpus
                 if r["stratum"] == "uncovered"}
    topics = sorted({r["topic"] for r in corpus if r["topic"]
                     and r["topic"] not in uncovered})
    # Varied-form harvest (v2): non-cyclic topic pairs (i, i*7) across
    # four surface forms — cyclic sampling saturates at ~35 unique
    # (harvest-2: 48 records, 0 new). Forms rotate to vary pool selection.
    forms = ["чем {a} отличается от {b}?", "как {a} связано с {b}?",
             "почему {a} важно для человека, а {b} нет?",
             "{A} — это иллюзия, а {b} нет. докажи обратное"]
    varied = []
    i = 0
    while len(varied) < want:
        a = topics[i % len(topics)]
        b = topics[(i * 7) % len(topics)]
        if a != b:
            tpl = forms[len(varied) % len(forms)]
            varied.append({"id": f"var-{len(varied):04d}",
                           "input": tpl.format(a=a, b=b, A=a[0].upper()+a[1:])})
        i += 1
        if i > want * len(topics):
            break
    sample = [{"id": r["id"], "input": r["input"]} for r in varied]
    print(f"sample={len(sample)} turns", flush=True)

    tmp = Path(tempfile.mkdtemp(prefix="calib-asm-"))
    db, statedir = str(tmp / "cal.db"), str(tmp / "state")
    os.makedirs(statedir, exist_ok=True)
    pairs = []
    n = 0
    for i, r in enumerate(sample):
        env = dict(os.environ, QXFX0_ROOT=str(ROOT),
                   QXFX0_STATE_DIR=statedir, QXFX0_DB=db,
                   QXFX0_RUNTIME_MODE="degraded")
        try:
            p = subprocess.run(
                [BIN, "--turn-json", r["input"]], capture_output=True,
                text=True, cwd=ROOT, env=env, timeout=180)
            resp = json.loads(p.stdout)
            c = sqlite3.connect(db)
            tj = c.execute(
                "select replay_trace_json from turn_quality "
                "where session_id=? order by turn desc limit 1",
                (resp.get("session_id"),)).fetchone()
            c.close()
            cands = (json.loads(tj[0])["trace"].get(
                "trcAssemblyCandidates") or []) if tj else []
        except Exception as e:  # noqa: BLE001 — harvest must not die
            print(f"[{i+1}/{len(sample)}] {r['id']} error "
                  f"{str(e)[-120:]}", flush=True)
            continue
        for cnd in cands:
            n += 1
            pairs.append({
                "id": f"asm-{n:04d}", "corpusVersion": 1,
                "stratum": "assembly_pairs",
                "input": r["input"], "family": resp.get("family"),
                "topicA": cnd["acTopicA"], "topicB": cnd["acTopicB"],
                "bridge": cnd["acBridge"], "head": cnd["acHead"],
                "relations": cnd["acRelations"],
                "pathLen": cnd["acPathLen"],
                "pathScore": cnd["acPathScore"],
                "labels": {"assembly_coherent": None,
                           "assembly_grounded": None},
                "provenance": "runtime-v4-assembly+human-pending"})
        print(f"[{i+1}/{len(sample)}] {r['id']} candidates={len(cands)} "
              f"total={n}", flush=True)
    dest = ROOT / "data/calibration_corpus/assembly_pairs.jsonl"
    with open(dest, "w", encoding="utf-8") as f:
        for rec in pairs:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print(f"pairs={n} wrote {dest}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
