#!/usr/bin/env python3
"""Generate Russian paradigms from lexicon_bilingual.tsv via pymorphy3.

Reads all Russian nouns from spec/gf/lexicon_bilingual.tsv and generates
full paradigms (6 cases × 2 numbers) for each lemma.

Output: resources/morphology/paradigms.json
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

try:
    import pymorphy3 as pymorphy2
except ImportError as e:
    print("pymorphy3 is required. Install: pip install pymorphy3", file=sys.stderr)
    raise SystemExit(1) from e

ROOT = Path(__file__).resolve().parents[1]
LEXICON_PATH = ROOT / "spec" / "gf" / "lexicon_bilingual.tsv"
# The runtime funmap is the authoritative lemma set the render path actually
# resolves against (lookupNounForm is keyed by its Cyrillic nominative). The
# bilingual TSV is a subset (2649 of 3743 nouns), which left ~1321 lemmas
# RGL-uncovered. L3d step 1: cover the full funmap so RGL can be the single
# morphology source and the JSON-map fallback can be retired.
FUNMAP_PATH = ROOT / "spec" / "gf" / "lexicon_funmap.tsv"
DEFAULT_OUT_PATH = ROOT / "resources" / "morphology" / "paradigms.json"

CASES = ["Nom", "Gen", "Dat", "Acc", "Ins", "Loc"]
NUMBERS = ["Sg", "Pl"]


def normalize_yo(s: str) -> str:
    """Flatten ё→е to match the JSON lexicon canon (source of truth).

    pymorphy3 emits oblique forms with ё (e.g. "актёра"); the shipped JSON
    lexicon uses е ("актера"). G1 of the RGL parity backlog: normalising here
    removes ~423 of 573 RGL/JSON form mismatches. Applied to FORM VALUES only —
    paradigm keys come from the lexicon and are left untouched.
    """
    return s.replace("ё", "е").replace("Ё", "Е")


def parse(p: pymorphy2.MorphAnalyzer, word: str) -> pymorphy2.analyzer.Parse:
    parses = p.parse(word)
    if not parses:
        raise ValueError(f"No parses for {word}")
    # Prefer nominative singular if available
    for par in parses:
        if {"nomn", "sing"} <= set(par.tag.grammemes):
            return par
    return parses[0]


def noun_paradigm(p: pymorphy2.MorphAnalyzer, lemma: str) -> dict:
    par = parse(p, lemma)
    forms = {}
    for case in CASES:
        for number in NUMBERS:
            pymorphy_case = {
                "Nom": "nomn", "Gen": "gent", "Dat": "datv",
                "Acc": "accs", "Ins": "ablt", "Loc": "loct",
            }[case]
            pymorphy_number = {"Sg": "sing", "Pl": "plur"}[number]
            inflected = par.inflect({pymorphy_case, pymorphy_number})
            key = f"{case}{number}"
            # G4: when pymorphy cannot produce a form (non-words, pluralia
            # tantum singular, defective paradigms) omit the key rather than
            # emit a "[lemma:key]" placeholder. A missing form makes
            # lookupNounForm return Nothing, so the runtime falls through to the
            # JSON path and the parity gate treats it as a coverage gap, not a
            # mismatch.
            if inflected:
                forms[key] = normalize_yo(inflected.word)
    return {
        "pos": "Noun",
        "gender": str(par.tag.gender) if par.tag.gender else None,
        "animacy": str(par.tag.animacy) if par.tag.animacy else None,
        "forms": forms,
    }


def collect_lemmas(lemmas_path: Path | None = None) -> list[str]:
    """Union of Russian noun lemmas from the bilingual TSV and the runtime funmap.

    If *lemmas_path* is given, read one lemma per line from that file instead.
    """
    if lemmas_path is not None:
        with lemmas_path.open("r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip()]

    seen: set[str] = set()
    lemmas: list[str] = []

    def add(lemma: str) -> None:
        if lemma and lemma not in seen:
            seen.add(lemma)
            lemmas.append(lemma)

    with LEXICON_PATH.open("r", encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            if row.get("lang") == "ru" and row.get("pos") == "noun":
                add(row["lemma"])

    with FUNMAP_PATH.open("r", encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 4 and parts[2] == "noun":
                add(parts[3])  # Cyrillic nominative — the runtime key

    return lemmas


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Russian noun paradigms via pymorphy3")
    parser.add_argument("--lemmas", type=Path, help="Path to a text file with one lemma per line")
    parser.add_argument("--out", type=Path, help="Output JSON path (default: resources/morphology/paradigms.json)")
    args = parser.parse_args()

    out_path = args.out or DEFAULT_OUT_PATH
    p = pymorphy2.MorphAnalyzer()
    paradigms: dict[str, dict] = {}

    for lemma in collect_lemmas(args.lemmas):
        if lemma in paradigms:
            continue
        try:
            paradigms[lemma] = noun_paradigm(p, lemma)
        except Exception as e:
            print(f"SKIP noun {lemma}: {e}", file=sys.stderr)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        json.dump(paradigms, f, ensure_ascii=False, indent=2)
    print(f"Wrote {len(paradigms)} paradigms to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
