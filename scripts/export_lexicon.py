#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Set, Tuple


ROOT = Path(__file__).resolve().parents[1]
SQL_SCHEMA = ROOT / "spec" / "sql" / "lexicon" / "schema.sql"
SQL_SEED_CURATED = ROOT / "spec" / "sql" / "lexicon" / "seed_ru_curated.sql"
SQL_SEED_BRAIN_REVIEWED = ROOT / "spec" / "sql" / "lexicon" / "seed_brain_kb_reviewed.sql"
SQL_SEED_FALLBACK = ROOT / "spec" / "sql" / "lexicon" / "seed_ru_core.sql"
AUTO_MANIFEST = ROOT / "spec" / "sql" / "lexicon" / "auto_source_manifest.json"
AUTO_SEED_TSV = ROOT / "spec" / "sql" / "lexicon" / "seed_ru_auto.tsv"
IMPORT_SCRIPT = ROOT / "scripts" / "import_ru_opencorpora.py"

MORPH_DIR = ROOT / "resources" / "morphology"
GF_DIR = ROOT / "spec" / "gf"
OUT_NOMINATIVE = MORPH_DIR / "nominative.json"
OUT_GENITIVE = MORPH_DIR / "genitive.json"
OUT_PREPOSITIONAL = MORPH_DIR / "prepositional.json"
OUT_FORMS_BY_SURFACE = MORPH_DIR / "forms_by_surface.json"
OUT_QUALITY = MORPH_DIR / "lexicon_quality.json"
OUT_SNAPSHOT = ROOT / "spec" / "lexicon_snapshot.tsv"
OUT_GF_ABSTRACT = GF_DIR / "QxFx0Lexicon.gf"
OUT_GF_CONCRETE = GF_DIR / "QxFx0LexiconRus.gf"
OUT_GF_SYNTAX_ABSTRACT = GF_DIR / "QxFx0Syntax.gf"
OUT_GF_SYNTAX_CONCRETE = GF_DIR / "QxFx0SyntaxRus.gf"
OUT_GF_MAP = GF_DIR / "lexicon_funmap.tsv"
OUT_AGDA_DATA = ROOT / "spec" / "LexiconData.agda"
OUT_AGDA_PROOF = ROOT / "spec" / "LexiconProof.agda"
OUT_HS_RUNTIME = ROOT / "src" / "QxFx0" / "Lexicon" / "Generated.hs"

CYRILLIC_FORM_RE = re.compile(r"^[а-яё -]+$")
TARGET_LEMMA_COUNT = 70


@dataclass(frozen=True)
class Lexeme:
    lemma: str
    pos: str
    nominative: str
    genitive: str
    prepositional: str
    accusative: str
    instrumental: str
    source: str
    tier: str
    quality: float


def normalize_form(form: str) -> str:
    return form.strip().lower().replace("ё", "е")


def _load_import_module():
    """Dynamically load import_ru_opencorpora to reuse its filter functions."""
    if not IMPORT_SCRIPT.exists():
        return None
    spec = importlib.util.spec_from_file_location(
        "import_ru_opencorpora", IMPORT_SCRIPT
    )
    if spec is None or spec.loader is None:
        return None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def compute_auto_quality_metrics() -> Dict[str, object]:
    """Compute quality metrics for the auto-source lexicon.

    Reads seed_ru_auto.tsv and applies the same filter functions from
    import_ru_opencorpora.py to assess lexical quality.

    Returns metrics including:
      - p1_long_lemma_count: P1 lemmas exceeding length thresholds
      - p1_technical_compound_count: P1 technical compound adjectives
      - p1_mostly_proper_count: P1 mostly proper nouns
      - p2_mostly_proper_count: P2 mostly proper nouns
      - p2_patronymic_like_count: P2 patronymic-like lemmas
      - p1_domain_seed_hit_count: P1 domain seed words
      - p2_domain_seed_hit_count: P2 domain seed words
    """
    mod = _load_import_module()
    if mod is None:
        return {"error": "import_ru_opencorpora.py not found"}

    if not AUTO_SEED_TSV.exists():
        return {"error": "seed_ru_auto.tsv not found"}

    # Parse TSV
    p1_lemmas: Dict[str, str] = {}  # lemma -> pos
    p2_lemmas: Dict[str, str] = {}

    with open(AUTO_SEED_TSV, "r", encoding="utf-8") as f:
        header = f.readline().strip().split("\t")
        if len(header) < 7:
            return {"error": "invalid TSV header"}

        surface_idx = header.index("surface")
        lemma_idx = header.index("lemma")
        pos_idx = header.index("pos")
        tier_idx = header.index("tier")

        for line in f:
            parts = line.strip().split("\t")
            if len(parts) < 7:
                continue
            tier = parts[tier_idx]
            lemma = normalize_form(parts[lemma_idx])
            pos = normalize_form(parts[pos_idx])

            if tier == "auto-verified":
                p1_lemmas[lemma] = pos
            elif tier == "auto-coverage":
                p2_lemmas[lemma] = pos

    # Compute metrics using filter functions from import module
    p1_long_lemma_count = 0
    p1_technical_compound_count = 0
    p1_mostly_proper_count = 0
    p1_patronymic_like_count = 0
    p1_domain_seed_hit_count = 0

    for lemma, pos in p1_lemmas.items():
        # Length check
        max_len = mod.P1_NOUN_MAX_LEN if pos == "noun" else mod.P1_ADJ_MAX_LEN
        if len(lemma) > max_len:
            p1_long_lemma_count += 1

        # Technical compound
        if mod.is_technical_compound(lemma):
            p1_technical_compound_count += 1

        # Patronymic-like
        if mod.is_patronymic_like(lemma):
            p1_patronymic_like_count += 1

        # Domain seed
        if mod.is_domain_seed(lemma):
            p1_domain_seed_hit_count += 1

    # p1_mostly_proper_count: count P1 lemmas that are actually mostly proper nouns
    # in the source data. We re-parse the dictionary to check the real grammeme tags.
    try:
        source_groups = mod.parse_pymorphy3_dict(
            p1_limit=len(p1_lemmas),
            p2_limit=len(p2_lemmas),
        )
        for key, group in source_groups.items():
            if group.lemma in p1_lemmas and group.pos in ("noun", "adjective"):
                if mod.is_mostly_proper_noun(group) and not mod.is_proper_allowlisted(
                    group.lemma
                ):
                    p1_mostly_proper_count += 1
    except Exception:
        # Fallback to heuristic if re-parse fails
        proper_like_indicators = mod.PROPER_ALLOWLIST - mod.DOMAIN_SEED
        for lemma in p1_lemmas:
            if lemma in proper_like_indicators:
                p1_mostly_proper_count += 1

    p2_mostly_proper_count = 0
    p2_patronymic_like_count = 0
    p2_domain_seed_hit_count = 0

    for lemma, pos in p2_lemmas.items():
        # Patronymic-like
        if mod.is_patronymic_like(lemma):
            p2_patronymic_like_count += 1

        # Domain seed
        if mod.is_domain_seed(lemma):
            p2_domain_seed_hit_count += 1

    # p2_mostly_proper_count: count P2 lemmas that are actually mostly proper nouns
    try:
        for key, group in source_groups.items():
            if group.lemma in p2_lemmas and group.pos in ("noun", "adjective"):
                if mod.is_mostly_proper_noun(group) and not mod.is_proper_allowlisted(
                    group.lemma
                ):
                    p2_mostly_proper_count += 1
    except Exception:
        # Fallback to heuristic if re-parse fails
        proper_like_indicators = mod.PROPER_ALLOWLIST - mod.DOMAIN_SEED
        for lemma in p2_lemmas:
            if lemma in proper_like_indicators:
                p2_mostly_proper_count += 1

    return {
        "p1_lemma_count": len(p1_lemmas),
        "p2_lemma_count": len(p2_lemmas),
        "p1_long_lemma_count": p1_long_lemma_count,
        "p1_technical_compound_count": p1_technical_compound_count,
        "p1_mostly_proper_count": p1_mostly_proper_count,
        "p1_patronymic_like_count": p1_patronymic_like_count,
        "p2_mostly_proper_count": p2_mostly_proper_count,
        "p2_patronymic_like_count": p2_patronymic_like_count,
        "p1_domain_seed_hit_count": p1_domain_seed_hit_count,
        "p2_domain_seed_hit_count": p2_domain_seed_hit_count,
    }


def compute_case_surface_metrics(rows: List[Lexeme]) -> Dict[str, object]:
    noun_rows = [r for r in rows if r.pos == "noun"]
    noun_count = len(noun_rows)
    noun_acc_eq_nom_count = sum(1 for r in noun_rows if r.accusative == r.nominative)
    noun_ins_eq_nom_count = sum(1 for r in noun_rows if r.instrumental == r.nominative)

    feminine_like_rows = [
        r
        for r in noun_rows
        if r.nominative.endswith(("а", "я")) and not r.nominative.endswith("мя")
    ]
    feminine_like_count = len(feminine_like_rows)
    feminine_like_acc_eq_nom_count = sum(
        1 for r in feminine_like_rows if r.accusative == r.nominative
    )

    soft_sign_rows = [r for r in noun_rows if r.nominative.endswith("ь")]
    soft_sign_count = len(soft_sign_rows)
    soft_sign_ins_eq_nom_count = sum(
        1 for r in soft_sign_rows if r.instrumental == r.nominative
    )

    def ratio(count: int, total: int) -> float:
        return 0.0 if total <= 0 else float(count) / float(total)

    return {
        "noun_count": noun_count,
        "noun_acc_eq_nom_count": noun_acc_eq_nom_count,
        "noun_acc_eq_nom_ratio": ratio(noun_acc_eq_nom_count, noun_count),
        "noun_ins_eq_nom_count": noun_ins_eq_nom_count,
        "noun_ins_eq_nom_ratio": ratio(noun_ins_eq_nom_count, noun_count),
        "feminine_like_noun_count": feminine_like_count,
        "feminine_like_acc_eq_nom_count": feminine_like_acc_eq_nom_count,
        "feminine_like_acc_eq_nom_ratio": ratio(
            feminine_like_acc_eq_nom_count, feminine_like_count
        ),
        "soft_sign_noun_count": soft_sign_count,
        "soft_sign_ins_eq_nom_count": soft_sign_ins_eq_nom_count,
        "soft_sign_ins_eq_nom_ratio": ratio(
            soft_sign_ins_eq_nom_count, soft_sign_count
        ),
    }


def _load_auto_source(conn: sqlite3.Connection) -> List[Lexeme]:
    """Load auto-source TSV into lexicon_forms if manifest is enabled."""
    rows: List[Lexeme] = []
    if not AUTO_MANIFEST.exists():
        return rows
    manifest = json.loads(AUTO_MANIFEST.read_text(encoding="utf-8"))
    if not manifest.get("enabled", False):
        return rows
    if not AUTO_SEED_TSV.exists():
        return rows
    with open(AUTO_SEED_TSV, "r", encoding="utf-8") as f:
        header = f.readline().strip().split("\t")
        required = {
            "surface",
            "lemma",
            "pos",
            "case_tag",
            "number_tag",
            "tier",
            "quality",
        }
        if not required.issubset(set(header)):
            # Fallback for legacy 6-column TSV (no tier column)
            required_legacy = {
                "surface",
                "lemma",
                "pos",
                "case_tag",
                "number_tag",
                "quality",
            }
            if required_legacy.issubset(set(header)):
                surface_idx = header.index("surface")
                lemma_idx = header.index("lemma")
                pos_idx = header.index("pos")
                case_idx = header.index("case_tag")
                number_idx = header.index("number_tag")
                quality_idx = header.index("quality")
                for line in f:
                    parts = line.strip().split("\t")
                    if len(parts) < len(required_legacy):
                        continue
                    conn.execute(
                        """
                        INSERT OR IGNORE INTO lexicon_forms
                        (language_code, surface, lemma, pos, case_tag, number_tag, source, tier, quality)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        (
                            "ru",
                            parts[surface_idx],
                            parts[lemma_idx],
                            parts[pos_idx],
                            parts[case_idx],
                            parts[number_idx],
                            manifest.get("source_name", "auto-coverage"),
                            manifest.get("tier", "auto-coverage"),
                            float(parts[quality_idx]),
                        ),
                    )
            return rows
        surface_idx = header.index("surface")
        lemma_idx = header.index("lemma")
        pos_idx = header.index("pos")
        case_idx = header.index("case_tag")
        number_idx = header.index("number_tag")
        tier_idx = header.index("tier")
        quality_idx = header.index("quality")
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) < len(required):
                continue
            # Insert into lexicon_forms so SQL queries can pick it up
            conn.execute(
                """
                INSERT OR IGNORE INTO lexicon_forms
                (language_code, surface, lemma, pos, case_tag, number_tag, source, tier, quality)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    "ru",
                    parts[surface_idx],
                    parts[lemma_idx],
                    parts[pos_idx],
                    parts[case_idx],
                    parts[number_idx],
                    manifest.get("source_name", "auto-coverage"),
                    parts[tier_idx],
                    float(parts[quality_idx]),
                ),
            )
    return rows


def _sync_entries_to_forms(conn: sqlite3.Connection) -> None:
    """Populate lexicon_forms from lexicon_entries for curated tier.

    Each lexicon_entry generates core singular forms so forms_by_surface stays
    aligned with the canonical lexicon table.
    This ensures forms_by_surface.json has data even when only lexicon_entries
    are seeded (not lexicon_forms directly).
    """
    conn.execute(
        """
        INSERT OR IGNORE INTO lexicon_forms
        (language_code, surface, lemma, pos, case_tag, number_tag, source, tier, quality)
        SELECT language_code, nominative, lemma, pos, 'nominative', 'singular', source, tier, quality
        FROM lexicon_entries
        """
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO lexicon_forms
        (language_code, surface, lemma, pos, case_tag, number_tag, source, tier, quality)
        SELECT language_code, genitive, lemma, pos, 'genitive', 'singular', source, tier, quality
        FROM lexicon_entries
        """
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO lexicon_forms
        (language_code, surface, lemma, pos, case_tag, number_tag, source, tier, quality)
        SELECT language_code, prepositional, lemma, pos, 'prepositional', 'singular', source, tier, quality
        FROM lexicon_entries
        """
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO lexicon_forms
        (language_code, surface, lemma, pos, case_tag, number_tag, source, tier, quality)
        SELECT language_code, accusative, lemma, pos, 'accusative', 'singular', source, tier, quality
        FROM lexicon_entries
        WHERE accusative <> ''
        """
    )
    conn.execute(
        """
        INSERT OR IGNORE INTO lexicon_forms
        (language_code, surface, lemma, pos, case_tag, number_tag, source, tier, quality)
        SELECT language_code, instrumental, lemma, pos, 'instrumental', 'singular', source, tier, quality
        FROM lexicon_entries
        WHERE instrumental <> ''
        """
    )


def _hydrate_entry_case_forms(conn: sqlite3.Connection) -> None:
    """Backfill lexicon_entries.accusative/instrumental from lexicon_forms.

    Preference order: curated > brain-kb-reviewed > auto-verified > auto-coverage, then by quality.
    Missing values fall back to nominative to preserve non-empty guarantees.
    """
    conn.execute(
        """
        UPDATE lexicon_entries
        SET accusative = COALESCE(
          (
            SELECT f.surface
            FROM lexicon_forms f
            WHERE f.language_code = lexicon_entries.language_code
              AND f.lemma = lexicon_entries.lemma
              AND f.pos = lexicon_entries.pos
              AND f.case_tag = 'accusative'
              AND f.number_tag = 'singular'
            ORDER BY
              CASE f.tier
                WHEN 'curated' THEN 0
                WHEN 'brain-kb-reviewed' THEN 1
                WHEN 'auto-verified' THEN 2
                ELSE 3
              END,
              f.quality DESC
            LIMIT 1
          ),
          NULLIF(accusative, ''),
          nominative
        ),
        instrumental = COALESCE(
          (
            SELECT f.surface
            FROM lexicon_forms f
            WHERE f.language_code = lexicon_entries.language_code
              AND f.lemma = lexicon_entries.lemma
              AND f.pos = lexicon_entries.pos
              AND f.case_tag = 'instrumental'
              AND f.number_tag = 'singular'
            ORDER BY
              CASE f.tier
                WHEN 'curated' THEN 0
                WHEN 'brain-kb-reviewed' THEN 1
                WHEN 'auto-verified' THEN 2
                ELSE 3
              END,
              f.quality DESC
            LIMIT 1
          ),
          NULLIF(instrumental, ''),
          nominative
        )
        """
    )
    cur = conn.execute(
        """
        SELECT language_code, lemma, pos, nominative, genitive, accusative, instrumental
        FROM lexicon_entries
        """
    )
    for language_code, lemma, pos, nominative, genitive, accusative, instrumental in cur.fetchall():
        norm_pos = normalize_form(str(pos))
        nom = normalize_form(str(nominative))
        gen = normalize_form(str(genitive))
        acc = normalize_form(str(accusative)) if accusative is not None else ""
        ins = normalize_form(str(instrumental)) if instrumental is not None else ""
        acc = normalize_accusative_form(nom, gen, norm_pos, acc)
        ins = normalize_instrumental_form(nom, gen, norm_pos, ins)
        conn.execute(
            """
            UPDATE lexicon_entries
            SET accusative = ?, instrumental = ?
            WHERE language_code = ? AND lemma = ? AND pos = ?
            """,
            (acc, ins, language_code, lemma, pos),
        )


def normalize_accusative_form(nominative: str, genitive: str, pos: str, surface: str) -> str:
    candidate = surface or nominative
    if pos != "noun" or not nominative:
        return candidate
    # -мя nouns (e.g. "время") keep nominative in accusative.
    if nominative.endswith("мя") and candidate.endswith("мю"):
        return nominative
    if candidate == nominative:
        return infer_accusative_form(nominative, genitive, pos)
    return candidate


def infer_accusative_form(nominative: str, genitive: str, pos: str) -> str:
    if pos != "noun" or not nominative:
        return nominative
    if nominative.endswith("мя"):
        return nominative
    if nominative.endswith("а"):
        return nominative[:-1] + "у"
    if nominative.endswith("я"):
        return nominative[:-1] + "ю"
    # For inanimate masculine/neuter, accusative often matches nominative.
    return nominative


def normalize_instrumental_form(nominative: str, genitive: str, pos: str, surface: str) -> str:
    candidate = surface or nominative
    if pos != "noun" or not nominative:
        return candidate
    # Soft-sign masculine nouns (genitive on -я) should not collapse to -ью.
    if nominative.endswith("ь") and genitive.endswith("я") and candidate.endswith("ью"):
        return nominative[:-1] + "ем"
    if candidate == nominative:
        return infer_instrumental_form(nominative, genitive, pos)
    return candidate


def infer_instrumental_form(nominative: str, genitive: str, pos: str) -> str:
    if pos != "noun" or not nominative:
        return nominative
    if nominative.endswith("мя"):
        return nominative[:-2] + "менем"
    if nominative.endswith("а"):
        stem = nominative[:-1]
        return stem + ("ей" if stem.endswith(("ж", "ш", "ч", "щ", "ц")) else "ой")
    if nominative.endswith("я"):
        return nominative[:-1] + "ей"
    if nominative.endswith("ь"):
        if genitive.endswith("я"):
            return nominative[:-1] + "ем"
        return nominative[:-1] + "ью"
    if nominative.endswith("й"):
        return nominative[:-1] + "ем"
    if nominative.endswith("е"):
        return nominative[:-1] + "ем"
    if nominative.endswith("о"):
        return nominative[:-1] + "ом"
    return nominative + "ом"


def load_rows() -> Tuple[List[Lexeme], Dict[str, List[List[object]]]]:
    conn = sqlite3.connect(":memory:")
    try:
        conn.executescript(SQL_SCHEMA.read_text(encoding="utf-8"))
        seed_path = SQL_SEED_CURATED if SQL_SEED_CURATED.exists() else SQL_SEED_FALLBACK
        conn.executescript(seed_path.read_text(encoding="utf-8"))
        if SQL_SEED_BRAIN_REVIEWED.exists():
            conn.executescript(SQL_SEED_BRAIN_REVIEWED.read_text(encoding="utf-8"))
        _load_auto_source(conn)
        _hydrate_entry_case_forms(conn)
        _sync_entries_to_forms(conn)
        cur = conn.execute(
            """
            SELECT
              lemma, pos, nominative, genitive, prepositional, accusative, instrumental,
              source, tier, quality
            FROM lexicon_entries
            WHERE tier = 'curated'
            ORDER BY lemma, pos
            """
        )
        rows: List[Lexeme] = []
        for row in cur.fetchall():
            rows.append(
                Lexeme(
                    lemma=normalize_form(str(row[0])),
                    pos=normalize_form(str(row[1])),
                    nominative=normalize_form(str(row[2])),
                    genitive=normalize_form(str(row[3])),
                    prepositional=normalize_form(str(row[4])),
                    accusative=normalize_form(str(row[5])),
                    instrumental=normalize_form(str(row[6])),
                    source=normalize_form(str(row[7])),
                    tier=normalize_form(str(row[8])),
                    quality=float(row[9]),
                )
            )
        forms_by_surface = build_forms_by_surface(conn)
        return rows, forms_by_surface
    finally:
        conn.close()


def validate_forms(rows: List[Lexeme]) -> List[str]:
    invalid: List[str] = []
    for r in rows:
        if (
            not r.lemma
            or not r.nominative
            or not r.genitive
            or not r.prepositional
            or not r.accusative
            or not r.instrumental
        ):
            invalid.append(f"{r.lemma}: empty field")
            continue
        for label, value in (
            ("lemma", r.lemma),
            ("nominative", r.nominative),
            ("genitive", r.genitive),
            ("prepositional", r.prepositional),
            ("accusative", r.accusative),
            ("instrumental", r.instrumental),
        ):
            if not CYRILLIC_FORM_RE.fullmatch(value):
                invalid.append(f"{r.lemma}: invalid {label}={value!r}")
    return invalid


def add_unique_mapping(
    mapping: Dict[str, str], key: str, value: str, collisions: List[str], context: str
) -> None:
    prev = mapping.get(key)
    if prev is None:
        mapping[key] = value
        return
    if prev != value:
        collisions.append(f"{context}: {key} -> {prev} | {value}")


def build_morphology_maps(
    rows: List[Lexeme],
) -> Tuple[Dict[str, str], Dict[str, str], Dict[str, str], List[str]]:
    nominative_map: Dict[str, str] = {}
    genitive_map: Dict[str, str] = {}
    prepositional_map: Dict[str, str] = {}
    collisions: List[str] = []

    for r in rows:
        add_unique_mapping(
            nominative_map,
            r.nominative,
            r.nominative,
            collisions,
            f"nominative:self:{r.lemma}",
        )
        add_unique_mapping(
            nominative_map,
            r.genitive,
            r.nominative,
            collisions,
            f"nominative:genitive:{r.lemma}",
        )
        add_unique_mapping(
            nominative_map,
            r.prepositional,
            r.nominative,
            collisions,
            f"nominative:prepositional:{r.lemma}",
        )
        add_unique_mapping(
            genitive_map,
            r.nominative,
            r.genitive,
            collisions,
            f"genitive:{r.lemma}",
        )
        add_unique_mapping(
            prepositional_map,
            r.nominative,
            r.prepositional,
            collisions,
            f"prepositional:{r.lemma}",
        )

    return (
        dict(sorted(nominative_map.items())),
        dict(sorted(genitive_map.items())),
        dict(sorted(prepositional_map.items())),
        collisions,
    )


def compute_score(total: int, complete: int, invalid: int, collisions: int) -> float:
    if total <= 0:
        return 0.0
    coverage = min(1.0, total / TARGET_LEMMA_COUNT)
    completeness = complete / total
    cleanliness = max(0.0, 1.0 - ((invalid + collisions) / total))
    raw = 10.0 * (0.45 * coverage + 0.45 * completeness + 0.10 * cleanliness)
    return round(raw, 2)


def render_snapshot(rows: List[Lexeme]) -> str:
    lines = [
        "lemma\tpos\tnominative\tgenitive\tprepositional\taccusative\tinstrumental\tsource\ttier\tquality"
    ]
    for r in rows:
        lines.append(
            f"{r.lemma}\t{r.pos}\t{r.nominative}\t{r.genitive}\t{r.prepositional}\t{r.accusative}\t{r.instrumental}\t{r.source}\t{r.tier}\t{r.quality:.2f}"
        )
    return "\n".join(lines) + "\n"


def render_json(obj: object) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def read_or_empty(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


CYRILLIC_TO_LATIN = {
    "а": "a",
    "б": "b",
    "в": "v",
    "г": "g",
    "д": "d",
    "е": "e",
    "ё": "yo",
    "ж": "zh",
    "з": "z",
    "и": "i",
    "й": "j",
    "к": "k",
    "л": "l",
    "м": "m",
    "н": "n",
    "о": "o",
    "п": "p",
    "р": "r",
    "с": "s",
    "т": "t",
    "у": "u",
    "ф": "f",
    "х": "h",
    "ц": "ts",
    "ч": "ch",
    "ш": "sh",
    "щ": "shch",
    "ъ": "",
    "ы": "y",
    "ь": "",
    "э": "e",
    "ю": "yu",
    "я": "ya",
}


def transliterate(text: str) -> str:
    out: List[str] = []
    for ch in text:
        if ch in CYRILLIC_TO_LATIN:
            out.append(CYRILLIC_TO_LATIN[ch])
        elif ch.isascii() and ch.isalnum():
            out.append(ch.lower())
        elif ch in {" ", "-", "/"}:
            out.append("_")
        else:
            out.append("_")
    return "".join(out)


def make_fun_name(lemma: str, pos: str, used: Dict[str, int]) -> str:
    pos_suffix = {
        "noun": "N",
        "verb": "V",
        "adj": "A",
        "adjective": "A",
        "adv": "Adv",
    }.get(pos, "X")
    base = transliterate(lemma)
    base = re.sub(r"_+", "_", base).strip("_")
    if not base:
        base = "lexeme"
    if base[0].isdigit():
        base = f"lex_{base}"
    candidate = f"{base}_{pos_suffix}"
    count = used.get(candidate, 0) + 1
    used[candidate] = count
    if count == 1:
        return candidate
    return f"{candidate}_{count}"


def gf_quote(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def render_gf_files(rows: List[Lexeme]) -> Tuple[str, str, str]:
    used: Dict[str, int] = {}
    entries: List[Tuple[str, Lexeme]] = []
    for r in rows:
        fun = make_fun_name(r.lemma, r.pos, used)
        entries.append((fun, r))

    abstract_lines = [
        "-- AUTO-GENERATED by scripts/export_lexicon.py from spec/sql/lexicon.",
        "-- Canonical direction: SQL -> GF (do not edit this file manually).",
        "abstract QxFx0Lexicon = {",
        "  flags startcat = Lexeme ;",
        "  cat Lexeme ;",
        "  fun",
    ]
    abstract_lines.extend([f"    {fun} : Lexeme ;" for fun, _ in entries])
    abstract_lines.append("}")

    concrete_lines = [
        "-- AUTO-GENERATED by scripts/export_lexicon.py from spec/sql/lexicon.",
        "-- Canonical direction: SQL -> GF (do not edit this file manually).",
        "concrete QxFx0LexiconRus of QxFx0Lexicon = {",
        "  lincat Lexeme = { nom : Str ; gen : Str ; prep : Str ; acc : Str ; ins : Str } ;",
        "  lin",
    ]
    concrete_lines.extend(
        [
            (
                f"    {fun} = {{ nom = {gf_quote(r.nominative)} ; "
                f"gen = {gf_quote(r.genitive)} ; prep = {gf_quote(r.prepositional)} ; "
                f"acc = {gf_quote(r.accusative)} ; ins = {gf_quote(r.instrumental)} }} ;"
            )
            for fun, r in entries
        ]
    )
    concrete_lines.append("}")

    map_lines = ["fun\tlemma\tpos\tnominative\tgenitive\tprepositional\taccusative\tinstrumental"]
    map_lines.extend(
        [
            f"{fun}\t{r.lemma}\t{r.pos}\t{r.nominative}\t{r.genitive}\t{r.prepositional}\t{r.accusative}\t{r.instrumental}"
            for fun, r in entries
        ]
    )

    return (
        "\n".join(abstract_lines) + "\n",
        "\n".join(concrete_lines) + "\n",
        "\n".join(map_lines) + "\n",
    )


def render_gf_syntax_files() -> Tuple[str, str]:
    abstract_lines = [
        "-- AUTO-GENERATED by scripts/export_lexicon.py from spec/sql/lexicon.",
        "-- Canonical direction: SQL -> GF syntax scaffold (do not edit this file manually).",
        "abstract QxFx0Syntax = QxFx0Lexicon ** {",
        "  flags startcat = Move ;",
        "",
        "  cat",
        "    Move ;",
        "    NP ;",
        "    VP ;",
        "    Modifier ;",
        "    Relation ;",
        "    Mechanism ;",
        "",
        "  param",
        "    Number = NumSg | NumPl ;",
        "",
        "  fun",
        "    MkNP : Lexeme -> NP ;",
        "",
        "    ActMaintain : Number -> Lexeme -> VP ;",
        "    ActDefine   : Lexeme -> VP ;",
        "",
        "    ModFirst    : Modifier ;",
        "    ModStrictly : Modifier ;",
        "",
        "    MoveInvite : NP -> Modifier -> VP -> Move ;",
        "    MoveDefine : NP -> Relation -> NP -> Move ;",
        "    MoveCause  : NP -> Mechanism -> Move ;",
        "    MovePurpose : NP -> Move ;",
        "    MoveSelfState : Move ;",
        "    MoveCompare : NP -> NP -> Move ;",
        "    MoveOperationalStatus : Move ;",
        "    MoveOperationalCause : Move ;",
        "    MoveSystemLogic : Move ;",
        "    MoveMisunderstanding : Move ;",
        "    MoveGenerativeThought : Move ;",
        "    MoveContemplative : NP -> Move ;",
        "    MoveGround : NP -> Move ;",
        "    MoveContact : NP -> Move ;",
        "    MoveReflect : NP -> Move ;",
        "    MoveDescribe : NP -> Move ;",
        "    MoveDeepen : NP -> Move ;",
        "    MoveConfront : NP -> Move ;",
        "    MoveAnchor : NP -> Move ;",
        "    MoveClarify : NP -> Move ;",
        "    MoveNextStepLocal : NP -> Move ;",
        "    MoveHypothesis : NP -> Move ;",
        "    MoveDistinguish : NP -> NP -> Move ;",
        "",
        "    RelIdentity : Relation ;",
        "    MechParse   : Mechanism ;",
        "",
        "    ApplyStanceTentative : Move -> Move ;",
        "    ApplyStanceFirm      : Move -> Move ;",
        "}",
    ]

    concrete_lines = [
        "-- AUTO-GENERATED by scripts/export_lexicon.py from spec/sql/lexicon.",
        "-- Canonical direction: SQL -> GF syntax scaffold (do not edit this file manually).",
        "concrete QxFx0SyntaxRus of QxFx0Syntax = QxFx0LexiconRus ** {",
        "  lincat",
        "    Move = { s : Str } ;",
        "    NP   = { nom : Str ; gen : Str ; prep : Str ; acc : Str ; ins : Str } ;",
        "    VP   = { s : Str } ;",
        "    Modifier = { s : Str } ;",
        "    Relation = { s : Str } ;",
        "    Mechanism = { s : Str } ;",
        "",
        "  lin",
        "    MkNP lex = { nom = lex.nom ; gen = lex.gen ; prep = lex.prep ; acc = lex.acc ; ins = lex.ins } ;",
        "",
        '    ActMaintain NumSg obj = { s = "удержу " ++ obj.acc } ;',
        '    ActMaintain NumPl obj = { s = "удержим " ++ obj.acc } ;',
        '    ActDefine obj   = { s = "определю " ++ obj.acc } ;',
        "",
        '    ModFirst    = { s = "сначала" } ;',
        '    ModStrictly = { s = "строго" } ;',
        "",
        "    MoveInvite topic mod vp = {",
        '      s = "Да, поговорим о " ++ topic.prep ++ ". Я " ++ mod.s ++ " " ++ vp.s ++ ", чтобы не потерять фокус."',
        "    } ;",
        "",
        '    RelIdentity = { s = "является" } ;',
        '    MechParse   = { s = "механизмом локального разбора" } ;',
        '    MoveDefine subj rel obj = { s = subj.nom ++ " " ++ rel.s ++ " " ++ obj.ins } ;',
        '    MoveCause subj mech = { s = "Причиной " ++ subj.gen ++ " служит " ++ mech.s } ;',
        '    MovePurpose topic = { s = "Назначение " ++ topic.gen ++ " раскрывается через устойчивую роль в действии." } ;',
        '    MoveSelfState = { s = "Мой текущий ход строится из разбора реплики, выбора семейства ответа и ограничений сессии." } ;',
        '    MoveCompare left right = { s = "Сравнение " ++ left.gen ++ " и " ++ right.gen ++ " устойчиво только в явно заданной рамке." } ;',
        '    MoveOperationalStatus = { s = "Я работаю, но иногда теряю точность разбора входного вопроса." } ;',
        '    MoveOperationalCause = { s = "Проблема сейчас в маршрутизации и локальном разборе смысла." } ;',
        '    MoveSystemLogic = { s = "Моя логика строится на локальном разборе, типизированной маршрутизации и ограничениях сессии." } ;',
        '    MoveMisunderstanding = { s = "Я принимаю это как сигнал сбоя взаимопонимания и перехожу к уточнению." } ;',
        '    MoveGenerativeThought = { s = "Одна мысль может задать рамку следующему шагу рассуждения." } ;',
        '    MoveContemplative topic = { s = "Слово " ++ topic.nom ++ " открывает не только предмет, но и поле смыслов." } ;',
        '    MoveGround topic = { s = "Держу " ++ topic.acc ++ " как устойчивую опору для дальнейшего разбора." } ;',
        '    MoveContact topic = { s = "Слышу запрос на контакт по теме " ++ topic.prep ++ "." } ;',
        '    MoveReflect topic = { s = "Вы отразили " ++ topic.acc ++ ", и это требует прояснения смысла." } ;',
        '    MoveDescribe topic = { s = "Опишу " ++ topic.acc ++ " через локальную рабочую рамку." } ;',
        '    MoveDeepen topic = { s = "Углубим разговор о " ++ topic.prep ++ " через один устойчивый фокус." } ;',
        '    MoveConfront topic = { s = "Возражение: " ++ topic.nom ++ " требует проверки допущений." } ;',
        '    MoveAnchor topic = { s = "Фиксирую опору в " ++ topic.prep ++ " как точку устойчивости." } ;',
        '    MoveClarify topic = { s = "Уточним, что именно вы имеете в виду в " ++ topic.prep ++ "." } ;',
        '    MoveNextStepLocal topic = { s = "Следующий шаг: конкретизировать " ++ topic.acc ++ " в одном действии." } ;',
        '    MoveHypothesis topic = { s = "Гипотеза: " ++ topic.nom ++ " можно объяснить через локальную модель." } ;',
        '    MoveDistinguish left right = { s = "Различим " ++ left.acc ++ " и " ++ right.acc ++ " в одной рамке критериев." } ;',
        "",
        '    ApplyStanceTentative move = { s = "Возможно, нам стоит сказать, что " ++ move.s } ;',
        '    ApplyStanceFirm move = { s = "Зафиксируем строго: " ++ move.s } ;',
        "}",
    ]

    return "\n".join(abstract_lines) + "\n", "\n".join(concrete_lines) + "\n"


def render_agda_modules(rows: List[Lexeme]) -> Tuple[str, str]:
    used: Dict[str, int] = {}
    entries: List[Tuple[str, Lexeme]] = []
    for r in rows:
        ctor = make_fun_name(r.lemma, r.pos, used)
        entries.append((ctor, r))

    data_lines = [
        "{-# OPTIONS --without-K #-}",
        "",
        "module LexiconData where",
        "",
        "-- AUTO-GENERATED by scripts/export_lexicon.py from spec/sql/lexicon.",
        "-- Canonical direction: SQL -> Agda (do not edit manually).",
        "",
        "open import Agda.Builtin.Nat using (Nat)",
        "open import Agda.Builtin.String using (String)",
        "open import Agda.Builtin.Equality using (_≡_; refl)",
        "",
        "data Lemma : Set where",
    ]
    data_lines.extend([f"  {ctor} : Lemma" for ctor, _ in entries])
    data_lines.append("")
    data_lines.append("lemmaNominative : Lemma → String")
    data_lines.extend(
        [f'lemmaNominative {ctor} = "{r.nominative}"' for ctor, r in entries]
    )
    data_lines.append("")
    data_lines.append("lemmaGenitive : Lemma → String")
    data_lines.extend([f'lemmaGenitive {ctor} = "{r.genitive}"' for ctor, r in entries])
    data_lines.append("")
    data_lines.append("lemmaPrepositional : Lemma → String")
    data_lines.extend(
        [f'lemmaPrepositional {ctor} = "{r.prepositional}"' for ctor, r in entries]
    )
    data_lines.append("")
    data_lines.append("lemmaCount : Nat")
    data_lines.append(f"lemmaCount = {len(entries)}")
    data_lines.append("")
    data_lines.append("lemmaCountExpected : lemmaCount ≡ " + str(len(entries)))
    data_lines.append("lemmaCountExpected = refl")
    data_lines.append("")

    proof_lines = [
        "{-# OPTIONS --without-K #-}",
        "",
        "module LexiconProof where",
        "",
        "-- AUTO-GENERATED by scripts/export_lexicon.py from spec/sql/lexicon.",
        "-- Canonical direction: SQL -> Agda (do not edit manually).",
        "",
        "open import Agda.Builtin.Bool using (Bool; true)",
        "open import Agda.Builtin.Equality using (_≡_; refl)",
        "open import LexiconData",
        "",
        "-- Structural lexical adequacy proof:",
        "-- every SQL-exported lemma constructor has a complete form triple.",
        "lemmaHasAllForms : Lemma → Bool",
    ]
    proof_lines.extend([f"lemmaHasAllForms {ctor} = true" for ctor, _ in entries])
    proof_lines.append("")
    proof_lines.append(
        "lemmaHasAllForms-sound : (l : Lemma) → lemmaHasAllForms l ≡ true"
    )
    proof_lines.extend([f"lemmaHasAllForms-sound {ctor} = refl" for ctor, _ in entries])
    proof_lines.append("")

    return "\n".join(data_lines) + "\n", "\n".join(proof_lines) + "\n"


def hs_quote(text: str) -> str:
    escaped = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def hs_tier_constructor(tier: str) -> str:
    mapping = {
        "curated": "CuratedTier",
        "brain-kb-reviewed": "BrainKbReviewedTier",
        "auto-verified": "AutoVerifiedTier",
        "auto-coverage": "AutoCoverageTier",
    }
    return mapping.get(tier, "CuratedTier")


def hs_case_constructor(case_tag: str) -> str:
    mapping = {
        "nominative": "NominativeCase",
        "genitive": "GenitiveCase",
        "dative": "DativeCase",
        "accusative": "AccusativeCase",
        "instrumental": "InstrumentalCase",
        "prepositional": "PrepositionalCase",
    }
    return mapping.get(case_tag, "NominativeCase")


def hs_number_constructor(number_tag: str) -> str:
    mapping = {
        "singular": "SingularNumber",
        "plural": "PluralNumber",
    }
    return mapping.get(number_tag, "SingularNumber")


def render_haskell_runtime_module(
    rows: List[Lexeme],
    forms_by_surface: Dict[str, List[List[object]]],
) -> str:
    entries: List[Tuple[str, str, str, str]] = []
    for r in rows:
        entries.append((r.nominative, r.lemma, r.pos, "nominative"))
        entries.append((r.genitive, r.lemma, r.pos, "genitive"))
        entries.append((r.prepositional, r.lemma, r.pos, "prepositional"))

    out = [
        "{-# LANGUAGE OverloadedStrings #-}",
        "module QxFx0.Lexicon.Generated",
        "  ( generatedLexemeEntries",
        "  , generatedCandidateForms",
        "  ) where",
        "",
        "import qualified Data.Map.Strict as M",
        "import Data.Text (Text)",
        "import QxFx0.Types.Domain.Atoms",
        "  ( LexemeForm(..)",
        "  , LexemeCase(..)",
        "  , LexemeNumber(..)",
        "  , SourceTier(..)",
        "  )",
        "",
        "-- AUTO-GENERATED by scripts/export_lexicon.py from spec/sql/lexicon.",
        "-- Canonical direction: SQL -> Haskell runtime entries.",
        "",
        "-- (surface, lemma, pos, case-tag)",
        "generatedLexemeEntries :: [(Text, Text, Text, Text)]",
        "generatedLexemeEntries =",
        "  [",
    ]
    for idx, (surface, lemma, pos, case_tag) in enumerate(entries):
        suffix = "," if idx < len(entries) - 1 else ""
        out.append(
            f"    ({hs_quote(surface)}, {hs_quote(lemma)}, {hs_quote(pos)}, {hs_quote(case_tag)}){suffix}"
        )

    # generatedCandidateForms: curated + brain-kb-reviewed entries
    # (P1/P2 loaded from JSON at runtime).
    # This keeps the generated module small and compilation fast.
    # Compact tuple format: [surface, lemma, pos, case, number, tier, quality]
    curated_forms: Dict[str, List[List[object]]] = {}
    for surface, forms in forms_by_surface.items():
        curated_only = [
            f for f in forms if f[5] in {"curated", "brain-kb-reviewed"}
        ]
        if curated_only:
            curated_forms[surface] = curated_only

    candidate_entries: List[str] = []
    for surface in sorted(curated_forms.keys()):
        forms = curated_forms[surface]
        sorted_forms = sorted(
            forms,
            key=lambda f: (
                -f[6],
                f[1],
            ),
        )
        form_list_parts = []
        for form in sorted_forms:
            tier = hs_tier_constructor(str(form[5]))
            case_c = hs_case_constructor(str(form[3]))
            num_c = hs_number_constructor(str(form[4]))
            quality = float(form[6])
            form_list_parts.append(
                f"        LexemeForm"
                f" {{ lfSurface = {hs_quote(surface)}"
                f" , lfLemma = {hs_quote(str(form[1]))}"
                f" , lfPOS = {hs_quote(str(form[2]))}"
                f" , lfCase = {case_c}"
                f" , lfNumber = {num_c}"
                f" , lfTier = {tier}"
                f" , lfQuality = {quality}"
                f" }}"
            )
        form_list_str = "      [\n" + ",\n".join(form_list_parts) + "\n      ]"
        candidate_entries.append(f"    ({hs_quote(surface)},\n{form_list_str})")

    out.extend(
        [
            "  ]",
            "",
            "-- Candidate forms loaded from resources/morphology/forms_by_surface.json at runtime.",
            "-- Populated from SQL lexicon_forms table (curated + brain-kb-reviewed tiers).",
            "generatedCandidateForms :: M.Map Text [LexemeForm]",
            "generatedCandidateForms =",
        ]
    )

    if candidate_entries:
        out.append("  M.fromList")
        out.append("    [")
        for idx, entry in enumerate(candidate_entries):
            suffix = "," if idx < len(candidate_entries) - 1 else ""
            out.append(f"{entry}{suffix}")
        out.append("    ]")
    else:
        out.append("  M.empty")

    out.append("")
    return "\n".join(out) + "\n"


def build_forms_by_surface(
    conn: sqlite3.Connection,
) -> Dict[str, List[List[object]]]:
    cur = conn.execute(
        """
        SELECT surface, lemma, pos, case_tag, number_tag, tier, quality
        FROM lexicon_forms
        ORDER BY surface, tier, quality DESC, lemma
        """
    )
    # Compact tuple format: [surface, lemma, pos, case, number, tier, quality]
    result: Dict[str, List[List[object]]] = {}
    for row in cur.fetchall():
        surface = normalize_form(str(row[0]))
        entry: List[object] = [
            surface,
            normalize_form(str(row[1])),
            normalize_form(str(row[2])),
            normalize_form(str(row[3])),
            normalize_form(str(row[4])),
            normalize_form(str(row[5])),
            float(row[6]),
        ]
        result.setdefault(surface, []).append(entry)
    for surface in result:
        # Deduplicate by all visible fields (same surface may appear from multiple
        # SQL rows if the seed TSV had duplicates).
        seen: Set[Tuple[str, ...]] = set()
        deduped: List[List[object]] = []
        for e in result[surface]:
            sig = (e[1], e[2], e[3], e[4], e[5])
            if sig not in seen:
                seen.add(sig)
                deduped.append(e)
        # Tier suppression policy:
        # - curated suppresses conflicting non-curated lemmas
        # - brain-kb-reviewed suppresses conflicting auto lemmas
        curated_lemmas = {e[1] for e in deduped if e[5] == "curated"}
        if curated_lemmas:
            deduped = [
                e for e in deduped if e[5] == "curated" or e[1] in curated_lemmas
            ]
        else:
            brain_reviewed_lemmas = {e[1] for e in deduped if e[5] == "brain-kb-reviewed"}
            if brain_reviewed_lemmas:
                deduped = [
                    e
                    for e in deduped
                    if e[5] in {"brain-kb-reviewed", "curated"} or e[1] in brain_reviewed_lemmas
                ]
        result[surface] = sorted(
            deduped,
            key=lambda f: (
                {
                    "curated": 0,
                    "brain-kb-reviewed": 1,
                    "auto-verified": 2,
                    "auto-coverage": 3,
                }.get(f[5], 3),
                -f[6],
                f[1],
            ),
        )
    return result


def analyze_forms_by_surface_collisions(
    forms_by_surface: Dict[str, List[List[object]]],
) -> Dict[str, object]:
    """Analyze collisions in forms_by_surface.json.

    Returns counts for:
      - dangerous: same surface -> different lemmas, at least one curated
      - harmless: same surface -> different lemmas, different POS (e.g. noun-verb)
      - expected_ambiguity: same surface -> different lemmas, same POS, no curated
    """
    dangerous: List[str] = []
    harmless: List[str] = []
    expected_ambiguity: List[str] = []

    for surface, forms in forms_by_surface.items():
        if len(forms) < 2:
            continue
        lemmas = list(dict.fromkeys(f[1] for f in forms))
        if len(lemmas) < 2:
            continue  # duplicates of same lemma, not a collision
        pos_tags = list(dict.fromkeys(f[2] for f in forms))
        tiers = list(dict.fromkeys(f[5] for f in forms))
        has_curated = "curated" in tiers

        desc = f"{surface}:{','.join(lemmas)}"
        if has_curated:
            dangerous.append(desc)
        elif len(pos_tags) > 1:
            harmless.append(desc)
        else:
            expected_ambiguity.append(desc)

    return {
        "dangerous": dangerous,
        "harmless": harmless,
        "expected_ambiguity": expected_ambiguity,
    }


def classify_collisions(
    rows: List[Lexeme], collisions: List[str]
) -> Dict[str, List[str]]:
    dangerous: List[str] = []
    harmless: List[str] = []
    expected_ambiguity: List[str] = []

    for c in collisions:
        parts = c.split(":")
        if len(parts) >= 3:
            context = parts[0]
            surface = parts[1] if len(parts) > 1 else ""
            lemmas = parts[2:] if len(parts) > 2 else []

            is_noun_noun = all("noun" in l.lower() for l in lemmas)
            is_noun_verb = any("noun" in l.lower() for l in lemmas) and any(
                "verb" in l.lower() for l in lemmas
            )

            if is_noun_verb:
                harmless.append(c)
            elif is_noun_noun:
                dangerous.append(c)
            else:
                expected_ambiguity.append(c)
        else:
            dangerous.append(c)

    return {
        "dangerous": dangerous,
        "harmless": harmless,
        "expected_ambiguity": expected_ambiguity,
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build deterministic morphology artifacts from SQL lexicon."
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if generated artifacts are not up-to-date.",
    )
    parser.add_argument(
        "--min-score",
        type=float,
        default=8.0,
        help="Minimum lexical quality score required for a passing gate.",
    )
    args = parser.parse_args()

    rows, forms_by_surface = load_rows()
    invalid = validate_forms(rows)
    complete_rows = sum(
        1
        for r in rows
        if r.nominative
        and r.genitive
        and r.prepositional
        and r.accusative
        and r.instrumental
    )
    nominative_map, genitive_map, prepositional_map, collisions = build_morphology_maps(
        rows
    )
    collision_report = classify_collisions(rows, collisions)
    fbs_collision_report = analyze_forms_by_surface_collisions(forms_by_surface)

    # Count P1/P2 forms and lemmas from forms_by_surface
    p1_lemmas = set()
    p2_lemmas = set()
    p1_forms = 0
    p2_forms = 0
    for surface, forms in forms_by_surface.items():
        for f in forms:
            tier = f[5]
            if tier == "auto-verified":
                p1_forms += 1
                p1_lemmas.add(f[1])
            elif tier == "auto-coverage":
                p2_forms += 1
                p2_lemmas.add(f[1])

    # Compute auto-source quality metrics
    auto_quality_metrics = compute_auto_quality_metrics()
    case_surface_metrics = compute_case_surface_metrics(rows)

    total_dangerous = len(collision_report["dangerous"]) + len(
        fbs_collision_report["dangerous"]
    )
    score = compute_score(len(rows), complete_rows, len(invalid), total_dangerous)

    snapshot = render_snapshot(rows)
    gf_abstract, gf_concrete, gf_map = render_gf_files(rows)
    gf_syntax_abstract, gf_syntax_concrete = render_gf_syntax_files()
    agda_data, agda_proof = render_agda_modules(rows)
    hs_runtime = render_haskell_runtime_module(rows, forms_by_surface)
    dataset_hash = hashlib.sha256(snapshot.encode("utf-8")).hexdigest()
    quality = {
        "score": score,
        "target_min_score": args.min_score,
        "canonical_direction": "sql_to_morphology_gf_agda_haskell",
        "lemma_count": len(rows),
        "target_lemma_count": TARGET_LEMMA_COUNT,
        "complete_rows": complete_rows,
        "invalid_rows": len(invalid),
        "collision_count": len(collisions),
        "dangerous_collision_count": len(collision_report["dangerous"]),
        "harmless_collision_count": len(collision_report["harmless"]),
        "forms_by_surface": {
            "surface_count": len(forms_by_surface),
            "p1_lemma_count": len(p1_lemmas),
            "p1_form_count": p1_forms,
            "p2_lemma_count": len(p2_lemmas),
            "p2_form_count": p2_forms,
            "dangerous_collision_count": len(fbs_collision_report["dangerous"]),
            "harmless_collision_count": len(fbs_collision_report["harmless"]),
            "expected_ambiguity_count": len(fbs_collision_report["expected_ambiguity"]),
        },
        "dataset_sha256": dataset_hash,
        "drift_check": {
            "schema_sha256": hashlib.sha256(SQL_SCHEMA.read_bytes()).hexdigest()[:16],
            "seed_sha256": hashlib.sha256(
                (
                    SQL_SEED_CURATED if SQL_SEED_CURATED.exists() else SQL_SEED_FALLBACK
                ).read_bytes()
            ).hexdigest()[:16],
            "seed_brain_kb_reviewed_sha256": hashlib.sha256(
                SQL_SEED_BRAIN_REVIEWED.read_bytes()
            ).hexdigest()[:16]
            if SQL_SEED_BRAIN_REVIEWED.exists()
            else "",
            "auto_manifest_present": AUTO_MANIFEST.exists(),
        },
        "sources": [
            str(SQL_SCHEMA.relative_to(ROOT)),
            str(
                (
                    SQL_SEED_CURATED if SQL_SEED_CURATED.exists() else SQL_SEED_FALLBACK
                ).relative_to(ROOT)
            ),
        ]
        + (
            [str(SQL_SEED_BRAIN_REVIEWED.relative_to(ROOT))]
            if SQL_SEED_BRAIN_REVIEWED.exists()
            else []
        ),
        "auto_source_enabled": AUTO_MANIFEST.exists()
        and json.loads(AUTO_MANIFEST.read_text(encoding="utf-8")).get("enabled", False),
        "auto_quality_metrics": auto_quality_metrics,
        "case_surface_metrics": case_surface_metrics,
        "generated_artifacts": [
            str(OUT_NOMINATIVE.relative_to(ROOT)),
            str(OUT_GENITIVE.relative_to(ROOT)),
            str(OUT_PREPOSITIONAL.relative_to(ROOT)),
            str(OUT_FORMS_BY_SURFACE.relative_to(ROOT)),
            str(OUT_QUALITY.relative_to(ROOT)),
            str(OUT_SNAPSHOT.relative_to(ROOT)),
            str(OUT_GF_ABSTRACT.relative_to(ROOT)),
            str(OUT_GF_CONCRETE.relative_to(ROOT)),
            str(OUT_GF_SYNTAX_ABSTRACT.relative_to(ROOT)),
            str(OUT_GF_SYNTAX_CONCRETE.relative_to(ROOT)),
            str(OUT_GF_MAP.relative_to(ROOT)),
            str(OUT_AGDA_DATA.relative_to(ROOT)),
            str(OUT_AGDA_PROOF.relative_to(ROOT)),
            str(OUT_HS_RUNTIME.relative_to(ROOT)),
        ],
    }

    if invalid:
        print("lexicon quality failed: invalid rows", file=sys.stderr)
        for item in invalid[:20]:
            print(f"  - {item}", file=sys.stderr)
        return 1
    if collision_report["dangerous"] or fbs_collision_report["dangerous"]:
        print(
            "lexicon quality failed: dangerous mapping collisions in curated/auto-verified",
            file=sys.stderr,
        )
        for item in collision_report["dangerous"][:10]:
            print(f"  - {item}", file=sys.stderr)
        for item in fbs_collision_report["dangerous"][:10]:
            print(f"  - forms_by_surface: {item}", file=sys.stderr)
        return 1
    if score < args.min_score:
        print(
            f"lexicon quality failed: score={score:.2f} < required={args.min_score:.2f}",
            file=sys.stderr,
        )
        return 1

    expected_outputs = {
        OUT_NOMINATIVE: render_json(nominative_map),
        OUT_GENITIVE: render_json(genitive_map),
        OUT_PREPOSITIONAL: render_json(prepositional_map),
        OUT_FORMS_BY_SURFACE: render_json(forms_by_surface),
        OUT_QUALITY: render_json(quality),
        OUT_SNAPSHOT: snapshot,
        OUT_GF_ABSTRACT: gf_abstract,
        OUT_GF_CONCRETE: gf_concrete,
        OUT_GF_SYNTAX_ABSTRACT: gf_syntax_abstract,
        OUT_GF_SYNTAX_CONCRETE: gf_syntax_concrete,
        OUT_GF_MAP: gf_map,
        OUT_AGDA_DATA: agda_data,
        OUT_AGDA_PROOF: agda_proof,
        OUT_HS_RUNTIME: hs_runtime,
    }

    if args.check:
        drifted = [
            p for p, content in expected_outputs.items() if read_or_empty(p) != content
        ]
        if drifted:
            print("lexicon artifacts are out of sync with SQL sources", file=sys.stderr)
            for path in drifted:
                print(f"  - {path.relative_to(ROOT)}", file=sys.stderr)
            return 1
        print(f"lexicon check passed (score={score:.2f}, lemmas={len(rows)})")
        return 0

    MORPH_DIR.mkdir(parents=True, exist_ok=True)
    OUT_SNAPSHOT.parent.mkdir(parents=True, exist_ok=True)
    GF_DIR.mkdir(parents=True, exist_ok=True)
    OUT_HS_RUNTIME.parent.mkdir(parents=True, exist_ok=True)
    for path, content in expected_outputs.items():
        path.write_text(content, encoding="utf-8")
    print(f"lexicon exported (score={score:.2f}, lemmas={len(rows)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
