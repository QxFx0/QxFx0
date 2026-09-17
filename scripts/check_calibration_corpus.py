#!/usr/bin/env python3
"""Self-check the calibration corpus seed against runtime lexicons.

Checks (all static, no runtime needed):
1. covered strata topics resolve as `entry "<topic>"` in Content.hs.
2. uncovered topics do NOT appear as entries (no false-covered).
3. challenge strata inputs carry >=1 hasChallengeMarker substring
   (QxFx0.Core.TurnPipeline.Effects, lowercased infix).
4. safety_negative inputs carry NO acuteCrisisMarker substring
   (QxFx0.Safety.CrisisGuard, normalized: lower, e->e).
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

CHALLENGE_MARKS = [
    "разве", "не согласен", "не согласна", "противореч", "неверно",
    "ошибаешься", "не прав", "спорю", "возраж", "сомневаюсь",
    "ты говоришь", "оспариваю", "это просто", "не более чем",
    "сводится к", "всего лишь", "это лишь",
    "контрпример", "докажи", "что если",
]

CRISIS_MARKERS = [
    "не хочу жить", "нет желания жить", "нет сил жить",
    "покончить с собой", "покончила с собой",
    "свести счеты с жизнью", "свести счёты с жизнью",
    "убить себя", "убью себя", "хочу умереть", "хочу покончить",
    "суицид", "суицидальн", "думаю о самоубийстве",
    "мысли о самоубийстве", "навредить себе", "причинить себе вред",
    "самоповрежд", "резать себя", "резать вены",
    "kill myself", "end my life", "want to die", "don't want to live",
    "dont want to live", "suicide", "suicidal", "self-harm",
    "hurt myself",
]


def norm(s):
    return " ".join(s.replace("ё", "е").lower().split())


def main():
    out = subprocess.run(
        ["grep", "-o", 'entry "[^"]*"', "src/QxFx0/Semantic/Content.hs"],
        capture_output=True, text=True, cwd=ROOT, check=True)
    entries = {line.split('"')[1] for line in out.stdout.splitlines()}
    corpus = [json.loads(line) for line in
              open(ROOT / "data/calibration_corpus/corpus.jsonl",
                   encoding="utf-8")]
    fails = []

    def fail(msg):
        fails.append(msg)

    covered = [r for r in corpus if r["stratum"].startswith("covered")]
    for r in covered:
        if r["topic"] not in entries:
            fail(f'{r["id"]}: covered topic missing from Content.hs: {r["topic"]}')
    uncovered = [r for r in corpus if r["stratum"] == "uncovered"]
    for r in uncovered:
        if r["topic"] in entries:
            fail(f'{r["id"]}: uncovered topic is actually covered: {r["topic"]}')
    challenged = [r for r in corpus if r["stratum"] in
                  ("covered_challenge", "challenge_marks")]
    for r in challenged:
        low = r["input"].lower()
        if not any(m in low for m in CHALLENGE_MARKS):
            fail(f'{r["id"]}: no challenge mark in: {r["input"]}')
    safeties = [r for r in corpus if r["stratum"] in
              ("safety_negative", "r5_negative")]
    for r in safeties:
        n = norm(r["input"])
        hit = [m for m in CRISIS_MARKERS if norm(m) in n]
        if hit:
            fail(f'{r["id"]}: crisis marker fires on decoy {hit}: {r["input"]}')

    print(f"records={len(corpus)} covered={len(covered)} "
          f"uncovered={len(uncovered)} challenged={len(challenged)} "
          f"safety={len(safeties)}")
    if fails:
        print(f"FAILURES ({len(fails)}):")
        for f in fails[:20]:
            print("  " + f)
        return 1
    print("corpus self-check PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
