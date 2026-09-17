#!/usr/bin/env python3
"""Inject verb paradigms (v1: the 24 relationLexicon infinitives) into
resources/morphology/paradigms.json.

Why: the morphology resource is nouns-only, so the runtime lemma map
never produces verb infinitives and term-level relation tagging was
dead (measured 0/24 attested). Each verb gets its infinitive + core
finite forms + short participles where applicable.

Format mirrors noun entries; loader (morphologyDataFromParadigms)
unions every (lemma, form) pair into the lemma map, so no code
change is needed. Style preserved: indent=2, raw UTF-8, CRLF, no
trailing newline.

Safety: asserts no surface collides with an existing different lemma
before writing. Re-run lemma_verb_coverage.py after to confirm the
attested jump.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARA = ROOT / "resources" / "morphology" / "paradigms.json"

# lemma: (aspect, transitivity, [forms...]) — Inf first by convention.
VERBS = {
    "требовать": ("imperf", "T",
        ["требовать", "требует", "требовал", "требовала",
         "требовало", "требовали"]),
    "предполагать": ("imperf", "T",
        ["предполагать", "предполагает", "предполагал",
         "предполагала", "предполагало", "предполагали"]),
    "ограничивать": ("imperf", "T",
        ["ограничивать", "ограничивает", "ограничивал",
         "ограничивала", "ограничивало", "ограничивали",
         "ограничен", "ограничена", "ограничено", "ограничены"]),
    "исключать": ("imperf", "T",
        ["исключать", "исключает", "исключал", "исключала",
         "исключало", "исключали", "исключён", "исключена",
         "исключено", "исключены"]),
    "связать": ("perf", "T",
        ["связать", "свяжет", "связал", "связала", "связало",
         "связали", "связан", "связана", "связано", "связаны"]),
    "давать": ("imperf", "T",
        ["давать", "даёт", "давал", "давала", "давало", "давали"]),
    "означать": ("imperf", "I",
        ["означать", "означает", "означал", "означала",
         "означало", "означали"]),
    "определять": ("imperf", "T",
        ["определять", "определяет", "определял", "определяла",
         "определяло", "определяли", "определён", "определена",
         "определено", "определены"]),
    "оставаться": ("imperf", "I",
        ["оставаться", "остаётся", "оставался", "оставалась",
         "оставалось", "оставались"]),
    "отражать": ("imperf", "T",
        ["отражать", "отражает", "отражал", "отражала",
         "отражало", "отражали", "отражён", "отражена",
         "отражено", "отражены"]),
    "порождать": ("imperf", "T",
        ["порождать", "порождает", "порождал", "порождала",
         "порождало", "порождали", "порождён", "порождена",
         "порождено", "порождены"]),
    "превращать": ("imperf", "T",
        ["превращать", "превращает", "превращал", "превращала",
         "превращало", "превращали", "превращён", "превращена",
         "превращено", "превращены"]),
    "противоречить": ("imperf", "I",
        ["противоречить", "противоречит", "противоречил",
         "противоречила", "противоречило", "противоречили"]),
    "различать": ("imperf", "T",
        ["различать", "различает", "различал", "различала",
         "различало", "различали"]),
    "служить": ("imperf", "I",
        ["служить", "служит", "служил", "служила",
         "служило", "служили"]),
    "совпадать": ("imperf", "I",
        ["совпадать", "совпадает", "совпадал", "совпадала",
         "совпадало", "совпадали"]),
    "соединять": ("imperf", "T",
        ["соединять", "соединяет", "соединял", "соединяла",
         "соединяло", "соединяли", "соединён", "соединена",
         "соединено", "соединены"]),
    "становиться": ("imperf", "I",
        ["становиться", "становится", "становился",
         "становилась", "становилось", "становились"]),
    "вести": ("imperf", "T",
        ["вести", "ведёт", "вёл", "вела", "вело", "вели",
         "ведомый", "ведома", "ведомо", "ведомы"]),
    "включать": ("imperf", "T",
        ["включать", "включает", "включал", "включала",
         "включало", "включали", "включён", "включена",
         "включено", "включены"]),
    "влечь": ("imperf", "T",
        ["влечь", "влечёт", "влёк", "влекла", "влекло", "влекли"]),
    "выражать": ("imperf", "T",
        ["выражать", "выражает", "выражал", "выражала",
         "выражало", "выражали", "выражен", "выражена",
         "выражено", "выражены"]),
    "делать": ("imperf", "T",
        ["делать", "делает", "делал", "делала", "делало", "делали"]),
    "зависеть": ("imperf", "I",
        ["зависеть", "зависит", "зависел", "зависела",
         "зависело", "зависели"]),
}

KEYS = ["Inf", "Pres3Sg", "PastMasc", "PastFem", "PastNeut", "PastPl",
        "PartShortMasc", "PartShortFem", "PartShortNeut", "PartShortPl"]


def main():
    data = json.loads(PARA.read_text(encoding="utf-8"))
    # Collision check against every existing surface.
    taken = {}
    for lem, entry in data.items():
        for _k, surf in entry.get("forms", {}).items():
            taken.setdefault(str(surf).lower(), str(lem))
    added_forms = 0
    for lem, (aspect, trans, forms) in VERBS.items():
        if lem in data:
            print(f"SKIP (already present): {lem}")
            continue
        skipped = set()
        for surf in forms:
            owner = taken.get(surf.lower())
            if owner is not None and owner != lem:
                print(f"COLLISION: {surf} already maps to {owner}; "
                      f"skipping form (verb {lem})")
                skipped.add(surf.lower())
        entry_forms = {}
        for i, surf in enumerate(forms):
            if surf.lower() in skipped:
                continue
            key = KEYS[i] if i < len(KEYS) else f"Form{i}"
            entry_forms[key] = surf
            added_forms += 1
        data[lem] = {"pos": "Verb", "gender": None, "animacy": None,
                     "aspect": aspect, "transitivity": trans,
                     "forms": entry_forms}
    out = json.dumps(data, ensure_ascii=False, indent=2)
    out = out.replace("\n", "\r\n")
    PARA.write_bytes(out.encode("utf-8"))
    print(f"verbs={len(VERBS)} forms={added_forms} "
          f"total_lemmas={len(data)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
