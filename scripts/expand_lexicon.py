#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
SQL_SCHEMA = ROOT / "spec" / "sql" / "lexicon" / "schema.sql"
SQL_CURATED = ROOT / "spec" / "sql" / "lexicon" / "seed_ru_curated.sql"
TSV_BILINGUAL = ROOT / "spec" / "gf" / "lexicon_bilingual.tsv"
AUTO_TSV = ROOT / "spec" / "sql" / "lexicon" / "seed_ru_auto.tsv"

NEEDED_CASES = ("nominative", "genitive", "prepositional", "accusative", "instrumental")
CYR_RE = re.compile(r"^[а-яё]+$")
# Domain safety filter for conversational RU contour.
RU_LEMMA_DENYLIST: Set[str] = {"блядь", "говно"}


@dataclass(frozen=True)
class Candidate:
    lemma: str
    nominative: str
    genitive: str
    prepositional: str
    accusative: str
    instrumental: str
    quality: float


def transliterate(text: str) -> str:
    c2l = {
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
        "ж": "zh", "з": "z", "и": "i", "й": "j", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    }
    out: List[str] = []
    for ch in text.lower():
        if ch in c2l:
            out.append(c2l[ch])
        elif ch.isascii() and ch.isalnum():
            out.append(ch)
        else:
            out.append("_")
    return re.sub(r"_+", "_", "".join(out)).strip("_") or "lexeme"


def sql_escape(value: str) -> str:
    return value.replace("'", "''")


def load_curated_baseline() -> Tuple[Set[str], Dict[str, Set[str]], int]:
    conn = sqlite3.connect(":memory:")
    try:
        conn.executescript(SQL_SCHEMA.read_text(encoding="utf-8"))
        conn.executescript(SQL_CURATED.read_text(encoding="utf-8"))
        cur = conn.execute(
            """
            SELECT lemma, nominative, genitive, prepositional, accusative, instrumental
            FROM lexicon_entries
            WHERE tier = 'curated' AND language_code = 'ru'
            """
        )
        lemma_set: Set[str] = set()
        form_map: Dict[str, Set[str]] = {}
        count = 0
        for lemma, nom, gen, prep, acc, ins in cur.fetchall():
            lemma = lemma.strip().lower()
            lemma_set.add(lemma)
            count += 1
            for form in (nom, gen, prep, acc, ins):
                surface = str(form).strip().lower()
                if not surface:
                    continue
                form_map.setdefault(surface, set()).add(lemma)
        return lemma_set, form_map, count
    finally:
        conn.close()


def load_existing_tsv_ids() -> Tuple[Set[str], Dict[str, str], Set[str]]:
    if not TSV_BILINGUAL.exists():
        return set(), {}, set()
    ru_lemmas: Set[str] = set()
    lemma_to_fun: Dict[str, str] = {}
    used_fun_ids: Set[str] = set()
    with TSV_BILINGUAL.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            fun_id = row.get("fun_id", "").strip()
            lemma = row.get("lemma", "").strip().lower()
            lang = row.get("lang", "").strip()
            if fun_id:
                used_fun_ids.add(fun_id)
            if lang == "ru" and lemma:
                ru_lemmas.add(lemma)
                if fun_id:
                    lemma_to_fun[lemma] = fun_id
    return ru_lemmas, lemma_to_fun, used_fun_ids


def gather_candidates(existing_lemmas: Set[str], existing_form_map: Dict[str, Set[str]]) -> List[Candidate]:
    by_lemma: Dict[str, Dict[str, Tuple[str, float]]] = {}
    with AUTO_TSV.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row.get("pos") != "noun" or row.get("number_tag") != "singular":
                continue
            lemma = row.get("lemma", "").strip().lower()
            case_tag = row.get("case_tag", "").strip().lower()
            surface = row.get("surface", "").strip().lower()
            if case_tag not in NEEDED_CASES:
                continue
            if lemma in existing_lemmas:
                continue
            if lemma in RU_LEMMA_DENYLIST:
                continue
            if not CYR_RE.fullmatch(lemma):
                continue
            if not CYR_RE.fullmatch(surface):
                continue
            if len(lemma) < 3 or len(lemma) > 28:
                continue
            quality = float(row.get("quality") or 0.0)
            slot = by_lemma.setdefault(lemma, {})
            prev = slot.get(case_tag)
            if prev is None or quality > prev[1]:
                slot[case_tag] = (surface, quality)

    candidates: List[Candidate] = []
    for lemma, forms in by_lemma.items():
        if not all(case in forms for case in NEEDED_CASES):
            continue
        nom, gen, prep, acc, ins = [forms[case][0] for case in NEEDED_CASES]
        if len({nom, gen, prep, acc, ins}) < 3:
            continue

        # Reject new lemmas whose case forms already belong to another curated lemma.
        collides = False
        for surface in (nom, gen, prep, acc, ins):
            owners = existing_form_map.get(surface)
            if owners and lemma not in owners:
                collides = True
                break
        if collides:
            continue

        min_q = min(forms[case][1] for case in NEEDED_CASES)
        candidates.append(
            Candidate(
                lemma=lemma,
                nominative=nom,
                genitive=gen,
                prepositional=prep,
                accusative=acc,
                instrumental=ins,
                quality=min_q,
            )
        )

    candidates.sort(key=lambda c: (-c.quality, c.lemma))
    return candidates


def select_non_colliding_candidates(
    candidates: List[Candidate],
    need: int,
    existing_form_map: Dict[str, Set[str]],
) -> List[Candidate]:
    selected: List[Candidate] = []
    working_map: Dict[str, Set[str]] = {k: set(v) for k, v in existing_form_map.items()}

    for c in candidates:
        if len(selected) >= need:
            break
        forms = (c.nominative, c.genitive, c.prepositional, c.accusative, c.instrumental)
        collides = False
        for surface in forms:
            owners = working_map.get(surface)
            if owners and c.lemma not in owners:
                collides = True
                break
        if collides:
            continue
        selected.append(c)
        for surface in forms:
            working_map.setdefault(surface, set()).add(c.lemma)
    return selected


def build_fun_id(lemma: str, used_fun_ids: Set[str]) -> str:
    base = f"{transliterate(lemma)}_N"
    fun_id = base
    idx = 2
    while fun_id in used_fun_ids:
        fun_id = f"{base}v{idx}"
        idx += 1
    used_fun_ids.add(fun_id)
    return fun_id


def english_gloss(lemma: str) -> str:
    return transliterate(lemma)


def append_tsv(entries: List[Tuple[str, Candidate]]) -> None:
    with TSV_BILINGUAL.open("a", encoding="utf-8", newline="") as f:
        for fun_id, c in entries:
            ru_row = [
                fun_id,
                c.lemma,
                "ru",
                "noun",
                c.nominative,
                c.genitive,
                c.prepositional,
                c.accusative,
                c.instrumental,
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
            ]
            en_lemma = english_gloss(c.lemma)
            en_row = [
                fun_id,
                en_lemma,
                "en",
                "noun",
                en_lemma,
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
                "",
            ]
            f.write("\t".join(ru_row) + "\n")
            f.write("\t".join(en_row) + "\n")


def append_sql(entries: List[Candidate]) -> None:
    if not entries:
        return
    text = SQL_CURATED.read_text(encoding="utf-8")
    stripped = text.rstrip()
    if not stripped.endswith(";"):
        raise RuntimeError("seed_ru_curated.sql has unexpected format: no trailing ';'")
    stripped = stripped[:-1].rstrip()
    if not stripped.endswith(")"):
        raise RuntimeError("seed_ru_curated.sql has unexpected format: expected VALUES tuples")

    lines: List[str] = [stripped + ","]
    for idx, c in enumerate(entries):
        tail = ";" if idx == len(entries) - 1 else ","
        lines.append(
            "('ru', '{lemma}', 'noun', '{nom}', '{gen}', '{prep}', '{acc}', '{ins}', 'curated', 'curated', 0.99){tail}".format(
                lemma=sql_escape(c.lemma),
                nom=sql_escape(c.nominative),
                gen=sql_escape(c.genitive),
                prep=sql_escape(c.prepositional),
                acc=sql_escape(c.accusative),
                ins=sql_escape(c.instrumental),
                tail=tail,
            )
        )
    SQL_CURATED.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Expand curated RU lexicon deterministically from auto-source.")
    parser.add_argument("target", nargs="?", type=int, default=2000, help="Target curated lemma count (default: 2000)")
    parser.add_argument("--dry-run", action="store_true", help="Print plan without writing files")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    existing_sql_lemmas, existing_form_map, curated_count = load_curated_baseline()
    tsv_ru_lemmas, _lemma_to_fun, used_fun_ids = load_existing_tsv_ids()

    # Keep SQL and TSV lemma sets synchronized by skipping anything already present in either.
    existing_all = set(existing_sql_lemmas) | set(tsv_ru_lemmas)

    if curated_count >= args.target:
        print(f"No-op: curated lemma_count={curated_count} already >= target={args.target}")
        return 0

    need = args.target - curated_count
    candidates = gather_candidates(existing_all, existing_form_map)
    if len(candidates) < need:
        raise RuntimeError(
            f"Not enough valid candidates: need {need}, have {len(candidates)} after filters"
        )

    selected = select_non_colliding_candidates(candidates, need, existing_form_map)
    if len(selected) < need:
        raise RuntimeError(
            f"Not enough collision-safe candidates: need {need}, selected {len(selected)}"
        )
    tsv_entries: List[Tuple[str, Candidate]] = []
    for c in selected:
        fun_id = build_fun_id(c.lemma, used_fun_ids)
        tsv_entries.append((fun_id, c))

    print(f"Curated before: {curated_count}")
    print(f"Target: {args.target}")
    print(f"Need: {need}")
    print(f"Selected candidates: {len(selected)}")
    if selected:
        print(f"First selected lemma: {selected[0].lemma}")
        print(f"Last selected lemma: {selected[-1].lemma}")

    if args.dry_run:
        print("Dry-run mode: no files written")
        return 0

    append_tsv(tsv_entries)
    append_sql([c for _, c in tsv_entries])
    print("Updated:")
    print(f"- {TSV_BILINGUAL}")
    print(f"- {SQL_CURATED}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
