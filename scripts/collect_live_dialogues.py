#!/usr/bin/env python3
"""Live dialogue collection harness (production-trace corpus seed).

Interactive Russian-language sessions with consent banner; every turn
persists input + response + replay-trace excerpt. Output is
corpus.jsonl-compatible JSONL with null labels (rating happens
separately, never inline).

Usage: python3 scripts/collect_live_dialogues.py [--rater ID] [--out FILE]
Defaults: anonymous rater id, data/calibration_corpus/live_dialogues.jsonl
Commands during session: /quit (end), /skip (drop last turn from file)

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
BIN = subprocess.run(["cabal", "list-bin", "exe:qxfx0-main"],
                     capture_output=True, text=True, cwd=ROOT,
                     check=True).stdout.strip().splitlines()[-1]

FIELDS = ["trcContentSource", "trcBestTopic", "trcDialogueFocus",
          "trcFinalFamily", "trcFamilyDivergenceOccurred",
          "trcSubstrateEdgesUsed", "trcSubstrateHops",
          "trcRecoveryCause", "trcRecoveryStrategy",
          "trcDerivationTags", "trcGenerationTrace",
          "trcLegitimacyReason", "trcConatusGateFired",
          "trcEmittedPredicates", "trcSelectorDiagnostics",
          "trcResponsePlan"]

BANNER = """\
СБОР ЖИВЫХ ДИАЛОГОВ ДЛЯ КАЛИБРОВКИ QxFx0
------------------------------------------
- Записываются: ваши реплики, ответы системы, технические трейсы хода.
- Без имён, IP и метаданных. Анонимный ID оценщика — случайная строка.
- Добровольно: в любой момент напишите /quit (завершить) или /skip
  (удалить последний ход из файла).
- Если речь зайдёт о самоповреждении, система покажет телефоны помощи
  (112; детский телефон доверия 8-800-2000-122) — это часть поведения,
  а не реакции на вас лично.
Напишите ДА чтобы начать, или что угодно другое чтобы выйти.
"""


def next_id(path):
    n = 0
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            if '"id": "live-' in line:
                n += 1
    return n


def run_turn(binpath, db, statedir, session_id, text, env):
    try:
        p = subprocess.run(
            [binpath, "--turn-json", text, "--session-id", session_id],
            capture_output=True, text=True, cwd=ROOT, env=env, timeout=180)
    except Exception as e:  # noqa: BLE001 — collection must not die
        return {"error": f"spawn: {e}"[-200:]}
    if p.returncode != 0:
        return {"error": p.stderr[-300:]}
    try:
        return json.loads(p.stdout)
    except Exception:
        return {"error": "bad json: " + p.stdout[-300:]}


def read_trace(db, session_id):
    try:
        c = sqlite3.connect(db)
        tj = c.execute(
            "select replay_trace_json from turn_quality "
            "where session_id=? order by turn desc limit 1",
            (session_id,)).fetchone()
        c.close()
        tr = json.loads(tj[0])["trace"] if tj else {}
        return {f: tr.get(f) for f in FIELDS}
    except Exception as e:  # noqa: BLE001
        return {"error": f"trace read: {e}"}


def main():
    rater = "anon"
    outp = str(ROOT / "data/calibration_corpus/live_dialogues.jsonl")
    args = sys.argv[1:]
    if "--rater" in args:
        rater = args[args.index("--rater") + 1]
    if "--out" in args:
        outp = args[args.index("--out") + 1]
    print(BANNER, flush=True)
    if input("> ").strip().lower() not in ("да", "da", "yes", "y"):
        print("Выход без записи.")
        return 0
    import random
    import time
    rater_id = rater if rater != "anon" else f"anon-{random.randint(1000, 9999)}"
    session_id = f"live-{int(time.time())}-{random.randint(100, 999)}"
    tmp = Path(tempfile.mkdtemp(prefix="live-dialog-"))
    db, statedir = str(tmp / "cal.db"), str(tmp / "state")
    os.makedirs(statedir, exist_ok=True)
    env = dict(os.environ, QXFX0_ROOT=str(ROOT),
               QXFX0_STATE_DIR=statedir, QXFX0_DB=db,
               # Degraded: strict mode fail-closes here (no agda
               # witness / nix concepts on this box); degraded is
               # also the regime of the whole calibration corpus.
               QXFX0_RUNTIME_MODE="degraded")
    seq = next_id(outp)
    print(f"[ID {rater_id}] Сессия {session_id}. Пишите реплики, /quit — конец.",
          flush=True)
    with open(outp, "a", encoding="utf-8") as f:
        while True:
            try:
                text = input("вы> ").strip()
            except EOFError:
                break
            if text == "/quit":
                break
            if text == "/skip":
                print("(пропуск последнего хода — удалите вручную при разборе)" if seq == 0
                      else f"(отметьте live-{seq:04d} на удаление при разборе)")
                continue
            if not text:
                continue
            out = run_turn(BIN, db, statedir, session_id, text, env)
            if "error" in out:
                print(f"ошибка хода (не записано): {out['error']}",
                      flush=True)
                continue
            seq += 1
            rid = f"live-{seq:04d}"
            print(f"qx> {(out.get('response') or '')[:600]}", flush=True)
            rec = {"id": rid, "corpusVersion": 1,
                   "stratum": "live_dialogue",
                   "input": text, "topic": "",
                   "labels": {"predicate_relevant": None,
                              "challenge_strength": None,
                              "response_acceptable": None,
                              "crisis_expected": False},
                   "prelabel": None,
                   "provenance": "live_human_v1",
                   "rater_id": rater_id, "session_id": session_id,
                   "response": out.get("response"),
                   "family": out.get("family"),
                   "trace": read_trace(db, session_id)}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
    print(f"Готово: {outp} (+{seq} записей за сессию). Спасибо!", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
