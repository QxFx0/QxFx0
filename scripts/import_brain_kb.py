#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import re
import sqlite3
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Set, Tuple


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = Path("/home/liskil/Grid_cod/QXFX0_V5/brain_kb.jsonl")
SQL_SCHEMA = ROOT / "spec" / "sql" / "lexicon" / "schema.sql"
OUTPUT_SEED = ROOT / "spec" / "sql" / "lexicon" / "seed_brain_kb_reviewed.sql"
AUTO_SEED_TSV = ROOT / "spec" / "sql" / "lexicon" / "seed_ru_auto.tsv"

CYR_TOKEN_RE = re.compile(r"[а-яё-]{3,32}", re.IGNORECASE)
BAD_EDGE_HYPHEN_RE = re.compile(r"(^-|-$|--)")

RU_STOPWORDS = {
    "что", "это", "как", "так", "или", "если", "для", "при", "без", "про", "над",
    "под", "между", "потому", "поэтому", "когда", "чтобы", "либо", "тогда", "тут",
    "там", "здесь", "туда", "сюда", "где", "куда", "откуда", "очень", "просто",
    "тоже", "снова", "всегда", "иногда", "часто", "редко", "почти", "лишь", "только",
    "много", "мало", "более", "менее", "сам", "сама", "сами", "себя", "собой",
    "мной", "твой", "твоя", "твое", "моя", "мое", "наше", "ваше", "мой", "мои",
    "я", "ты", "он", "она", "оно", "мы", "вы", "они", "мне", "тебе", "ему", "ей",
    "нас", "вас", "их", "ихний", "его", "ее", "не", "ни", "да", "нет", "а", "но",
    "и", "в", "во", "на", "о", "об", "обо", "к", "ко", "с", "со", "у", "от", "до",
    "из", "за", "же", "ли", "бы", "то", "эта", "этот", "эти", "это", "тот", "та",
    "те", "кто", "чей", "чья", "чье", "чьи", "какой", "какая", "какое", "какие",
    "зачем", "почему", "раз", "два", "три", "уже", "ещё", "еще", "меня", "тебя",
    "себе", "нему", "нею", "ними", "ними", "нами", "вами", "этом", "этого", "этим",
    "чем", "чего", "чему", "том", "тома", "того", "того", "кому", "кем", "кем-то",
    "что-то", "кто-то", "где-то", "куда-то", "когда-то", "зачем-то", "почему-то",
    "ничего", "никто", "никого", "ничем", "ничему",
}

COMMON_VERB_FORMS = {
    "могу", "можем", "можете", "можешь", "может", "могут",
    "хочу", "хочешь", "хочет", "хотим", "хотите", "хотят",
    "знаю", "знаешь", "знает", "знаем", "знаете", "знают",
    "понимаю", "понимаешь", "понимает", "понимаем", "понимаете", "понимают",
    "вижу", "видишь", "видит", "видим", "видите", "видят",
    "слышу", "слышишь", "слышит", "слышим", "слышите", "слышат",
    "говорю", "говоришь", "говорит", "говорим", "говорите", "говорят",
    "делаю", "делаешь", "делает", "делаем", "делаете", "делают",
    "буду", "будешь", "будет", "будем", "будете", "будут",
    "есть", "был", "была", "были", "было", "будто", "значит",
}

LIKELY_VERB_ENDINGS = (
    "ться", "ить", "ать", "ять", "еть", "уть", "нуть", "ти", "ть", "чь",
    "ешь", "ет", "ем", "ете", "ут", "ют", "ишь", "ит", "им", "ите", "ат", "ят",
    "ала", "ило", "или", "ело", "ела", "али", "лся", "лась", "лись", "лось",
)

ADJECTIVE_ENDINGS = (
    "ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие", "ого", "ему", "ому", "ыми", "ими"
)

LEMMA_EXCEPTIONS = {"путь"}


def normalize(text: str) -> str:
    return text.strip().lower().replace("ё", "е")


def extract_tokens(text: str) -> List[str]:
    out: List[str] = []
    for raw in CYR_TOKEN_RE.findall(normalize(text)):
        token = raw.strip("-")
        if len(token) < 3 or len(token) > 32:
            continue
        if BAD_EDGE_HYPHEN_RE.search(token):
            continue
        if "-" in token:
            continue
        if token in RU_STOPWORDS:
            continue
        if token in COMMON_VERB_FORMS:
            continue
        if is_likely_non_lemma(token):
            continue
        out.append(token)
    return out


def is_likely_non_lemma(token: str) -> bool:
    if token in LEMMA_EXCEPTIONS:
        return False
    if any(token.endswith(sfx) for sfx in ADJECTIVE_ENDINGS):
        return True
    if any(token.endswith(sfx) for sfx in LIKELY_VERB_ENDINGS):
        return True
    return False


def load_auto_noun_surface_map(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}
    tier_rank = {"auto-verified": 0, "auto-coverage": 1}
    best: Dict[str, Tuple[int, float, str]] = {}
    valid_lemmas: Set[str] = set()
    with path.open("r", encoding="utf-8") as f:
        header = f.readline().strip().split("\t")
        idx = {k: i for i, k in enumerate(header)}
        required = {"surface", "lemma", "pos", "tier", "quality", "case_tag", "number_tag"}
        if not required.issubset(idx.keys()):
            return {}
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) <= max(idx.values()):
                continue
            pos = normalize(parts[idx["pos"]])
            if pos != "noun":
                continue
            surface = normalize(parts[idx["surface"]])
            lemma = normalize(parts[idx["lemma"]])
            case_tag = normalize(parts[idx["case_tag"]])
            number_tag = normalize(parts[idx["number_tag"]])
            if not surface or not lemma:
                continue
            if case_tag == "nominative" and number_tag == "singular":
                valid_lemmas.add(lemma)
            tier = normalize(parts[idx["tier"]])
            rank = tier_rank.get(tier, 2)
            try:
                quality = float(parts[idx["quality"]])
            except ValueError:
                quality = 0.0
            prev = best.get(surface)
            score = (rank, -quality, lemma)
            if prev is None or score < (prev[0], -prev[1], prev[2]):
                best[surface] = (rank, quality, lemma)
    return {
        surface: triple[2]
        for surface, triple in best.items()
        if triple[2] in valid_lemmas and not is_likely_non_lemma(triple[2])
    }


@dataclass
class Candidate:
    lemma: str
    mention_count: int = 0
    weighted_score: float = 0.0
    layers: Set[str] = field(default_factory=set)
    topics: Set[str] = field(default_factory=set)
    triggers: Set[str] = field(default_factory=set)


def candidate_quality(score: float, count: int) -> float:
    # Conservative confidence band for reviewed, not curated.
    base = 0.55
    score_gain = min(0.24, math.log1p(max(score, 0.0)) / 9.0)
    count_gain = min(0.11, min(count, 18) / 160.0)
    return round(min(0.9, base + score_gain + count_gain), 3)


def seed_sql_rows(candidates: Sequence[Candidate], top_n: int) -> List[str]:
    sorted_candidates = sorted(
        candidates,
        key=lambda c: (-c.weighted_score, -c.mention_count, c.lemma),
    )[:top_n]

    if not sorted_candidates:
        return []

    rows: List[str] = []
    for c in sorted_candidates:
        q = candidate_quality(c.weighted_score, c.mention_count)
        lemma = c.lemma.replace("'", "''")
        rows.append(
            "('ru', '{0}', 'noun', '{0}', '{0}', '{0}', '{0}', '{0}', 'brain-kb-reviewed', 'brain-kb-reviewed', {1})".format(
                lemma, q
            )
        )
    return rows


def render_seed(rows: Sequence[str], source_path: Path) -> str:
    lines = [
        "-- AUTO-GENERATED by scripts/import_brain_kb.py.",
        "-- Source: {}".format(source_path),
        "-- Canonical direction: brain_kb.jsonl -> reviewed SQL seed.",
        "INSERT OR IGNORE INTO lexicon_sources (source_name, tier) VALUES",
        "  ('brain-kb-reviewed', 'brain-kb-reviewed');",
        "",
        "DELETE FROM lexicon_entries WHERE tier = 'brain-kb-reviewed';",
        "",
    ]
    if not rows:
        lines.append("-- No reviewed candidates passed the current thresholds.")
        return "\n".join(lines) + "\n"

    lines.append(
        "INSERT OR IGNORE INTO lexicon_entries (language_code, lemma, pos, nominative, genitive, prepositional, accusative, instrumental, source, tier, quality) VALUES"
    )
    for idx, row in enumerate(rows):
        suffix = "," if idx < len(rows) - 1 else ";"
        lines.append(row + suffix)
    lines.append("")
    return "\n".join(lines)


def ingest_units(path: Path) -> List[dict]:
    units: List[dict] = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                units.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return units


def build_candidates(
    units: Sequence[dict], noun_surface_to_lemma: Dict[str, str]
) -> Dict[str, Candidate]:
    acc: Dict[str, Candidate] = {}

    for unit in units:
        layer = normalize(str(unit.get("layer", "")))
        topics = [normalize(str(x)) for x in unit.get("topic", []) if isinstance(x, str)]
        triggers = [normalize(str(x)) for x in unit.get("triggers", []) if isinstance(x, str)]
        text = normalize(str(unit.get("text", "")))
        usage = unit.get("usage", {}) if isinstance(unit.get("usage"), dict) else {}
        weight = float(usage.get("weight", 1.0) or 1.0)
        weight = max(0.1, min(weight, 5.0))

        token_sources: List[Tuple[str, float]] = []
        token_sources.extend((t, 2.0) for t in triggers)
        token_sources.extend((t, 1.5) for t in topics)
        token_sources.extend((t, 1.0) for t in extract_tokens(text))
        token_sources.extend((t, 1.7) for tr in triggers for t in extract_tokens(tr))
        token_sources.extend((t, 1.2) for tp in topics for t in extract_tokens(tp))

        per_unit_seen: Set[str] = set()
        for source_token, source_boost in token_sources:
            for token in extract_tokens(source_token):
                if token in per_unit_seen:
                    continue
                per_unit_seen.add(token)
                lemma = noun_surface_to_lemma.get(token)
                if lemma is None:
                    continue
                c = acc.get(lemma)
                if c is None:
                    c = Candidate(lemma=lemma)
                    acc[lemma] = c
                c.mention_count += 1
                c.weighted_score += source_boost * weight
                if layer:
                    c.layers.add(layer)
                c.topics.update(t for t in topics if t)
                c.triggers.update(t for t in triggers if t)
    return acc


def write_staging_tables(conn: sqlite3.Connection, units: Sequence[dict], candidates: Iterable[Candidate]) -> None:
    conn.execute("DELETE FROM brain_kb_units_raw")
    conn.execute("DELETE FROM brain_kb_lexeme_candidates")

    for unit in units:
        usage = unit.get("usage", {}) if isinstance(unit.get("usage"), dict) else {}
        weight = float(usage.get("weight", 0.0) or 0.0)
        conn.execute(
            """
            INSERT OR REPLACE INTO brain_kb_units_raw
              (id, layer, kind, text, topic_json, triggers_json, source_kind, weight)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(unit.get("id", "")),
                str(unit.get("layer", "")),
                str(unit.get("kind", "")),
                str(unit.get("text", "")),
                json.dumps(unit.get("topic", []), ensure_ascii=False),
                json.dumps(unit.get("triggers", []), ensure_ascii=False),
                str(unit.get("source_kind", "")),
                weight,
            ),
        )

    for c in candidates:
        conn.execute(
            """
            INSERT OR REPLACE INTO brain_kb_lexeme_candidates
              (lemma, mention_count, weighted_score, layers_json, topics_json, triggers_json, selected)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                c.lemma,
                c.mention_count,
                c.weighted_score,
                json.dumps(sorted(c.layers), ensure_ascii=False),
                json.dumps(sorted(c.topics), ensure_ascii=False),
                json.dumps(sorted(c.triggers), ensure_ascii=False),
                1,
            ),
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import brain_kb.jsonl and generate reviewed lexicon SQL seed."
    )
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="Path to brain_kb.jsonl")
    parser.add_argument("--schema", type=Path, default=SQL_SCHEMA, help="Path to lexicon schema.sql")
    parser.add_argument("--output-seed", type=Path, default=OUTPUT_SEED, help="Output SQL seed file")
    parser.add_argument("--top-n", type=int, default=400, help="Max selected reviewed lemmas")
    parser.add_argument("--min-count", type=int, default=2, help="Minimum mention count")
    parser.add_argument("--min-score", type=float, default=2.2, help="Minimum weighted score")
    args = parser.parse_args()

    if not args.input.exists():
        raise SystemExit(f"input file not found: {args.input}")
    if not args.schema.exists():
        raise SystemExit(f"schema file not found: {args.schema}")

    units = ingest_units(args.input)
    noun_surface_to_lemma = load_auto_noun_surface_map(AUTO_SEED_TSV)
    raw_candidates = build_candidates(units, noun_surface_to_lemma)
    filtered_candidates = [
        c
        for c in raw_candidates.values()
        if c.mention_count >= args.min_count and c.weighted_score >= args.min_score
    ]

    conn = sqlite3.connect(":memory:")
    try:
        conn.executescript(args.schema.read_text(encoding="utf-8"))
        write_staging_tables(conn, units, filtered_candidates)
        rows = seed_sql_rows(filtered_candidates, args.top_n)
        args.output_seed.write_text(render_seed(rows, args.input), encoding="utf-8")
    finally:
        conn.close()

    print(
        "brain_kb import complete: units={} candidates={} selected={} seed={}".format(
            len(units), len(raw_candidates), len(rows), args.output_seed
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
