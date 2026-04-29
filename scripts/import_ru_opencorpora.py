#!/usr/bin/env python3
"""
import_ru_opencorpora.py — Import Russian morphology from OpenCorpora XML or pymorphy3 dict.

Modes:
  --input dict.opcorpora.xml     Parse OpenCorpora XML via streaming iterparse.
  --pymorphy3                    Extract from built-in pymorphy3 dictionary (pilot fallback).

Outputs:
  --output seed_ru_auto.tsv      TSV of candidate forms (surface lemma pos case_tag number_tag quality)
  --manifest auto_source_manifest.json  License and provenance metadata.

Tier policy:
  P1 (auto-verified):  common nouns/adjectives/verbs with reasonably complete paradigms.
                       Quality ~0.85-0.95.
  P2 (auto-coverage):  broader set, incomplete paradigms allowed.
                       Quality ~0.55-0.75.

Neither tier is used for routing, ParserKeywords, GF, or Agda generation.
Curated P0 always outranks P1/P2 in the resolver.
"""

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

# OpenCorpora grammeme -> canonical mapping
POS_MAP = {
    "NOUN": "noun",
    "ADJF": "adjective",
    "ADJS": "adjective",
    "VERB": "verb",
    "INFN": "verb",
    "PRTF": "adjective",   # full participle — declines like adjective, has case
    "PRTS": "adjective",   # short participle — no case, treated like adjs
}

CASE_MAP = {
    "nomn": "nominative",
    "gent": "genitive",
    "datv": "dative",
    "accs": "accusative",
    "ablt": "instrumental",
    "loct": "prepositional",
    "loc2": "prepositional",   # secondary locative
    "gen2": "genitive",        # secondary genitive
    "acc2": "accusative",      # secondary accusative
}

NUMBER_MAP = {
    "sing": "singular",
    "plur": "plural",
}

# Grammemes that disqualify a form for P1 (too specialized/rare)
P1_DISQUAL_GRAMMEMES = {
    "Abbr", "Name", "Surn", "Patr", "Geox", "Orgn", "Trad",
    "perf", "impf",
    "tran", "intr",
    "1per", "2per", "3per",
    "pres", "past", "futr",
}

# We keep these but don't use them as primary sort keys
SKIP_POS = {
    "PREP", "CONJ", "PRCL", "INTJ", "ADVB", "PRED", "GRND", "NUMR", "NPRO",
}

# Lemmas that MUST be included for resolver test coverage.
PILOT_MUST_INCLUDE: Set[str] = {
    # Nouns (requested test words / homonymy examples)
    "сталь", "стать", "печь", "пила", "пить", "коса", "кос",
    "день", "сон", "любовь", "кофе", "метро", "людь", "ребенок",
    # Adjectives
    "мой",
    # Additional common nouns for coverage
    "человек", "время", "дело", "жизнь", "год",
    "работа", "слово", "место", "лицо", "друг", "глаз",
}

# Common / domain seed list: words that get priority bonus for P1/P2.
# These are philosophically and linguistically useful for QxFx0.
DOMAIN_SEED: Set[str] = {
    "человек", "люди", "мир", "жизнь", "смерть", "смысл", "свобода", "воля",
    "любовь", "страх", "вина", "стыд", "правда", "ложь", "истина", "причина",
    "основание", "вывод", "тезис", "доказательство", "объяснение", "аргумент",
    "посылка", "следствие", "правило", "ошибка", "вопрос", "ответ", "право",
    "обязанность", "выбор", "согласие", "давление", "тело", "вещь", "закон",
    "форма", "содержание", "отношение", "различие", "граница", "пример",
    "случай", "условие", "возможность", "необходимость", "знание", "понятие",
    "идея", "мысль", "разум", "сознание", "дух", "душа", "чувство", "опыт",
    "действие", "событие", "явление", "состояние", "процесс", "система",
    "структура", "функция", "свойство", "качество", "количество", "число",
    "время", "пространство", "движение", "изменение", "развитие", "история",
    "общество", "культура", "язык", "речь", "текст", "знак", "образ",
    "свет", "тьма", "добро", "зло", "сила", "власть", "порядок", "хаос",
    "бог", "вера", "надежда", "май", "март", "апрель", "июнь", "июль",
    "август", "сентябрь", "октябрь", "ноябрь", "декабрь", "январь", "февраль",
    "вода", "земля", "огонь", "воздух", "камень", "дерево", "цвет", "звук",
    "имя", "путь", "дом", "город", "страна", "народ", "семья", "мать",
    "отец", "брат", "сестра", "сын", "дочь", "ребёнок", "друг", "враг",
    "голова", "рука", "нога", "глаз", "сердце", "кровь", "кость", "рот",
    "нос", "ухо", "спина", "живот", "волос", "кожа", "день", "ночь",
    "утро", "вечер", "час", "минута", "секунда", "неделя", "месяц", "год",
    "книга", "бумага", "письмо", "слово", "число", "работа", "труд",
    "игра", "школа", "наука", "искусство", "музыка", "картина",
    "большой", "малый", "новый", "старый", "хороший", "плохой",
    "первый", "последний", "другой", "самый", "весь", "каждый",
    "быть", "иметь", "знать", "мочь", "хотеть", "должен", "стать",
    "делать", "говорить", "видеть", "слышать", "думать", "жить",
    "идти", "стоять", "лежать", "сидеть", "работать", "читать",
    "писать", "учить", "понимать", "любить", "верить", "надеяться",
    "ждать", "искать", "находить", "давать", "брать", "нести",
    "вести", "смотреть", "слушать", "чувствовать", "помнить",
    "начать", "кончить", "продолжать", "кончать", "начинать",
    "рука", "нога", "голова", "глаз", "ухо", "нос", "рот",
    "дом", "дверь", "окно", "стол", "стул", "кровать",
    "вода", "хлеб", "мясо", "рыба", "молоко", "чай",
    "солнце", "луна", "звезда", "небо", "земля", "река", "море",
    "белый", "чёрный", "красный", "синий", "зелёный", "жёлтый",
    "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь", "девять", "десять",
    "я", "ты", "он", "она", "оно", "мы", "вы", "они",
    "кто", "что", "какой", "который", "где", "куда", "откуда", "зачем", "почему", "как",
    "и", "или", "но", "а", "что", "чтобы", "если", "когда", "потому", "так",
}

# Proper-noun POS tags from OpenCorpora that indicate names/surnames/patronymics.
PROPER_NOUN_GRAMMEMES: Set[str] = {"Name", "Surn", "Patr", "Geox", "Orgn", "Trad"}

# Allowlist: proper-noun-tagged lemmas that are also common words worth keeping.
PROPER_ALLOWLIST: Set[str] = {
    "любовь", "воля", "вера", "надежда", "мир", "май", "марс", "слава",
    "виктор", "валентин", "валентина", "виктория", "август", "марк",
    "роза", "лапа", "ключ", "кран", "лук", "рай", "ад", "бог",
}

# Patronymic-like endings: reject from P2 pilot unless allowlisted.
PATRONYMIC_ENDINGS = ("ович", "евич", "ична", "овна", "евна", "ич")

# Technical compound adjective patterns: penalize/reject for P1.
TECHNICAL_PREFIXES = (
    "электро", "термо", "газо", "рентгено", "радио", "аэро", "гидро",
    "пневмо", "фото", "кино", "видео", "аудио", "био", "нано", "микро",
    "макро", "авто", "анти", "контр", "псевдо", "ультра", "супер",
    "инфра", "транс", "поли", "мульти", "интер", "экстра",
)

TECHNICAL_SUFFIXES = (
    "строительный", "распределительный", "производственный", "исследовательский",
    "измерительный", "управленческий", "технический", "механический",
    "электрический", "электронный", "программный", "вычислительный",
    "инженерный", "конструктивный", "промышленный", "эксплуатационный",
)

# Length thresholds
P1_NOUN_MAX_LEN = 24
P1_ADJ_MAX_LEN = 32
P2_NOUN_MAX_LEN = 30
P2_ADJ_MAX_LEN = 40
P1_MAX_HYPHENS = 1
P2_MAX_HYPHENS = 2

# Regex: cyrillic letters and internal hyphens only.
# No leading/trailing hyphens, at least 2 chars, mostly cyrillic.
CYRILLIC_RE = re.compile(r"^[\u0430-\u044f\u0451]+(?:-[\u0430-\u044f\u0451]+)*$")


@dataclass
class ParsedForm:
    surface: str
    lemma: str
    pos: str
    case: Optional[str]
    number: Optional[str]
    gender: Optional[str]
    animacy: Optional[str]
    grammemes: Set[str] = field(default_factory=set)


@dataclass
class LemmaGroup:
    lemma: str
    pos: str
    forms: List[ParsedForm] = field(default_factory=list)


def normalize(text: str) -> str:
    return text.strip().lower().replace("ё", "е")


def is_clean_cyrillic(text: str) -> bool:
    if not text:
        return False
    if len(text) < 2:
        return False
    # Must start and end with cyrillic letter (no leading/trailing hyphen)
    # Reject strings that are all hyphens or start with non-cyrillic
    return CYRILLIC_RE.match(text) is not None


def parse_opencorpora_xml(xml_path: Path) -> Dict[str, LemmaGroup]:
    """Stream-parse OpenCorpora XML into lemma groups."""
    try:
        import xml.etree.ElementTree as ET
    except ImportError:
        raise RuntimeError("xml.etree.ElementTree is required for XML parsing")

    groups: Dict[str, LemmaGroup] = {}
    ns = {"": "http://dict.russe.nlpub.ru/OpencorporaDict"}

    context = ET.iterparse(str(xml_path), events=("start", "end"))
    context = iter(context)
    event, root = next(context)

    current_lemma_id: Optional[int] = None
    current_forms: List[ParsedForm] = []
    current_lemma_text = ""
    current_pos = ""

    for event, elem in context:
        tag = elem.tag.split("}")[-1] if "}" in elem.tag else elem.tag

        if event == "start":
            if tag == "lemma":
                current_lemma_id = int(elem.get("id", 0))
                current_forms = []
                current_lemma_text = ""
                current_pos = ""
            continue

        # end events
        if tag == "l" and current_lemma_id is not None:
            current_lemma_text = normalize(elem.get("t", ""))
            # Collect POS from <g> children inside <l>
            for g in elem.iter():
                if g.tag.split("}")[-1] == "g":
                    v = g.get("v", "")
                    if v in POS_MAP:
                        current_pos = POS_MAP[v]
                    elif v in SKIP_POS:
                        current_pos = ""  # mark as skip
        elif tag == "f" and current_lemma_id is not None:
            surface = normalize(elem.get("t", ""))
            grammemes: Set[str] = set()
            pos = current_pos
            case: Optional[str] = None
            number: Optional[str] = None
            gender: Optional[str] = None
            animacy: Optional[str] = None
            for g in elem.iter():
                if g.tag.split("}")[-1] == "g":
                    v = g.get("v", "")
                    grammemes.add(v)
                    if v in POS_MAP and not pos:
                        pos = POS_MAP[v]
                    if v in CASE_MAP:
                        case = CASE_MAP[v]
                    if v in NUMBER_MAP:
                        number = NUMBER_MAP[v]
                    if v in ("masc", "femn", "neut"):
                        gender = v
                    if v in ("anim", "inan"):
                        animacy = v
            if pos and surface and is_clean_cyrillic(surface):
                current_forms.append(ParsedForm(
                    surface=surface,
                    lemma=current_lemma_text,
                    pos=pos,
                    case=case,
                    number=number,
                    gender=gender,
                    animacy=animacy,
                    grammemes=grammemes,
                ))
        elif tag == "lemma" and current_lemma_id is not None:
            if current_lemma_text and current_pos and current_forms:
                key = f"{current_lemma_text}:{current_pos}"
                if key not in groups:
                    groups[key] = LemmaGroup(
                        lemma=current_lemma_text,
                        pos=current_pos,
                        forms=current_forms,
                    )
                else:
                    groups[key].forms.extend(current_forms)
            current_lemma_id = None
            current_forms = []
            root.clear()

    return groups


def parse_pymorphy3_dict(p1_limit: int, p2_limit: int) -> Dict[str, LemmaGroup]:
    """Extract morphology from built-in pymorphy3 OpenCorpora dictionary."""
    import pymorphy3
    morph = pymorphy3.MorphAnalyzer()
    d = morph.dictionary

    # (word, tag, normal_form, paradigm_id, form_id)
    # We iterate and group by (normal_form, pos)
    raw_groups: Dict[str, List[ParsedForm]] = defaultdict(list)

    for word, tag, normal_form, paradigm_id, form_id in d.iter_known_words():
        pos_raw = tag.POS
        if pos_raw is None:
            continue
        if pos_raw in SKIP_POS:
            continue
        pos = POS_MAP.get(pos_raw)
        if not pos:
            continue

        surface = normalize(word)
        lemma = normalize(normal_form)
        if not is_clean_cyrillic(surface) or not is_clean_cyrillic(lemma):
            continue

        grammemes = set(tag.grammemes) if hasattr(tag, "grammemes") else set()
        case = CASE_MAP.get(tag.case) if tag.case else None
        number = NUMBER_MAP.get(tag.number) if tag.number else None
        gender = tag.gender if tag.gender else None
        animacy = tag.animacy if tag.animacy else None

        raw_groups[f"{lemma}:{pos}"].append(ParsedForm(
            surface=surface,
            lemma=lemma,
            pos=pos,
            case=case,
            number=number,
            gender=gender,
            animacy=animacy,
            grammemes=grammemes,
        ))

    groups: Dict[str, LemmaGroup] = {}
    for key, forms in raw_groups.items():
        lemma, pos = key.split(":", 1)
        # Deduplicate forms by (surface, case, number)
        seen: Set[Tuple[str, Optional[str], Optional[str]]] = set()
        unique_forms: List[ParsedForm] = []
        for f in forms:
            sig = (f.surface, f.case, f.number)
            if sig not in seen:
                seen.add(sig)
                unique_forms.append(f)
        groups[key] = LemmaGroup(lemma=lemma, pos=pos, forms=unique_forms)

    return groups


def score_paradigm_completeness(group: LemmaGroup) -> Tuple[int, float]:
    """Return (score_0_100, coverage_ratio). Higher = more complete paradigm."""
    # For nouns: count distinct cases + numbers
    # For adjectives: cases × numbers × genders
    # For verbs: person/number/tense forms (simplified)
    cases_found: Set[str] = set()
    numbers_found: Set[str] = set()
    genders_found: Set[str] = set()
    for f in group.forms:
        if f.case:
            cases_found.add(f.case)
        if f.number:
            numbers_found.add(f.number)
        if f.gender:
            genders_found.add(f.gender)

    if group.pos == "noun":
        # Ideal: 6 cases × 2 numbers = 12; with gender/animacy metadata
        ideal = 12
        actual = len(cases_found) * len(numbers_found)
        score = min(100, int((actual / ideal) * 100))
        return score, actual / ideal
    elif group.pos == "adjective":
        # Ideal: 6 cases × 2 numbers × 3 genders = 36
        ideal = 36
        actual = len(cases_found) * len(numbers_found) * len(genders_found)
        score = min(100, int((actual / ideal) * 100))
        return score, actual / ideal
    elif group.pos == "verb":
        # Ideal: at least 6 distinct forms (infinitive + key conjugated)
        actual = len(set(f.surface for f in group.forms))
        score = min(100, int((actual / 6) * 100))
        return score, actual / 6
    else:
        return 50, 0.5


def is_auto_eligible(group: LemmaGroup) -> bool:
    """Base eligibility for any auto-tier (P1 or P2).

    Excludes verbs (OpenCorpora lacks case tags for verbs), abbreviations,
    and non-cyrillic garbage.
    Proper nouns (Name/Surn/Patr/Geox/Orgn/Trad) are allowed at P2 if they
    also appear as common nouns (e.g. 'любовь' is both a name and a common noun).
    """
    if group.pos not in ("noun", "adjective"):
        return False
    if not is_clean_cyrillic(group.lemma):
        return False
    if len(group.lemma) < 2:
        return False
    # Only hard-exclude abbreviations and foreign words at base level
    for f in group.forms:
        if {"Abbr", "LATN", "ROMN"} & f.grammemes:
            return False
    return True


def is_mostly_proper_noun(group: LemmaGroup) -> bool:
    """Check if >50%% of forms are tagged as proper nouns."""
    proper_tags = {"Name", "Surn", "Patr", "Geox", "Orgn", "Trad"}
    proper_count = sum(1 for f in group.forms if proper_tags & f.grammemes)
    return proper_count > len(group.forms) / 2


def is_patronymic_like(lemma: str) -> bool:
    """Check if a lemma looks like a patronymic (e.g. Иванович, Петровна)."""
    return lemma.endswith(PATRONYMIC_ENDINGS) and len(lemma) >= 5


def is_technical_compound(lemma: str) -> bool:
    """Check if a lemma looks like a technical compound adjective."""
    lemma_lower = lemma.lower()
    # Multiple hyphens
    if lemma_lower.count("-") > 1:
        return True
    # Hyphenated compound with technical parts
    if "-" in lemma_lower:
        parts = lemma_lower.split("-")
        for part in parts:
            if any(part.startswith(p) for p in TECHNICAL_PREFIXES):
                return True
            if any(part.endswith(s) for s in TECHNICAL_SUFFIXES):
                return True
    # Very long single-word adjective with technical prefix
    if any(lemma_lower.startswith(p) for p in TECHNICAL_PREFIXES) and len(lemma_lower) > 20:
        return True
    return False


def has_excessive_hyphens(lemma: str, max_hyphens: int) -> bool:
    """Check if lemma has more hyphens than allowed."""
    return lemma.count("-") > max_hyphens


def is_domain_seed(lemma: str) -> bool:
    """Check if lemma is in the common/domain seed list."""
    return lemma in DOMAIN_SEED


def is_proper_allowlisted(lemma: str) -> bool:
    """Check if a proper-noun-tagged lemma is in the allowlist."""
    return lemma in PROPER_ALLOWLIST


def compute_p1_score(group: LemmaGroup) -> Tuple[int, int, int, int, int, str]:
    """Compute a deterministic sort key for P1 selection.

    Lower tuple = higher priority.

    Priority order:
      1. must_include (0 = yes, 1 = no)
      2. domain_seed bonus (0 = yes, 1 = no)
      3. POS priority: noun=0, adjective=1
      4. NOT mostly proper noun (0 = good, 1 = bad)
      5. NOT technical compound (0 = good, 1 = bad)
      6. NOT patronymic-like (0 = good, 1 = bad)
      7. length penalty: shorter preferred (capped at 30)
      8. paradigm completeness (negated, higher is better)
      9. alphabetical tiebreak
    """
    score, ratio = score_paradigm_completeness(group)
    lemma = group.lemma

    must = 0 if lemma in PILOT_MUST_INCLUDE else 1
    domain = 0 if is_domain_seed(lemma) else 1
    pos_priority = 0 if group.pos == "noun" else 1
    proper_penalty = 0 if not is_mostly_proper_noun(group) else 1
    tech_penalty = 0 if not is_technical_compound(lemma) else 1
    patronymic_penalty = 0 if not is_patronymic_like(lemma) else 1
    length_key = min(30, len(lemma))
    completeness_key = -score  # negative so higher completeness sorts first
    alpha_key = lemma

    return (must, domain, pos_priority, proper_penalty, tech_penalty,
            patronymic_penalty, length_key, completeness_key, alpha_key)


def compute_p2_score(group: LemmaGroup) -> Tuple[int, int, int, int, int, int, str]:
    """Compute a deterministic sort key for P2 selection.

    Lower tuple = higher priority.

    Priority order:
      1. must_include (0 = yes, 1 = no)
      2. domain_seed bonus (0 = yes, 1 = no)
      3. POS priority: noun=0, adjective=1
      4. NOT mostly proper noun (0 = good, 1 = bad)
      5. NOT patronymic-like (0 = good, 1 = bad)
      6. length penalty: shorter preferred (capped at 40)
      7. paradigm completeness (negated)
      8. alphabetical tiebreak
    """
    score, ratio = score_paradigm_completeness(group)
    lemma = group.lemma

    must = 0 if lemma in PILOT_MUST_INCLUDE else 1
    domain = 0 if is_domain_seed(lemma) else 1
    pos_priority = 0 if group.pos == "noun" else 1
    proper_penalty = 0 if not is_mostly_proper_noun(group) else 1
    patronymic_penalty = 0 if not is_patronymic_like(lemma) else 1
    length_key = min(40, len(lemma))
    completeness_key = -score
    alpha_key = lemma

    return (must, domain, pos_priority, proper_penalty, patronymic_penalty,
            length_key, completeness_key, alpha_key)


def is_p1_rejected(group: LemmaGroup) -> bool:
    """Hard rejection filters for P1."""
    lemma = group.lemma
    # Reject mostly proper nouns
    if is_mostly_proper_noun(group) and not is_proper_allowlisted(lemma):
        return True
    # Reject patronymic-like
    if is_patronymic_like(lemma):
        return True
    # Reject technical compounds
    if is_technical_compound(lemma):
        return True
    # Length thresholds
    if group.pos == "noun" and len(lemma) > P1_NOUN_MAX_LEN:
        return True
    if group.pos == "adjective" and len(lemma) > P1_ADJ_MAX_LEN:
        return True
    # Hyphen thresholds
    if has_excessive_hyphens(lemma, P1_MAX_HYPHENS):
        return True
    return False


def is_p2_rejected(group: LemmaGroup) -> bool:
    """Hard rejection filters for P2 scale-step.

    More lenient than P1: allows domain-seed words even if they carry
    proper-noun tags (e.g. вера, любовь, надежда), and tolerates slightly
    longer compounds.
    """
    lemma = group.lemma
    # Reject mostly proper nouns unless allowlisted or domain-seed
    if is_mostly_proper_noun(group) and not is_proper_allowlisted(lemma) and not is_domain_seed(lemma):
        return True
    # Reject patronymic-like unless allowlisted or domain-seed
    if is_patronymic_like(lemma) and not is_proper_allowlisted(lemma) and not is_domain_seed(lemma):
        return True
    # Length thresholds (more lenient than P1)
    if group.pos == "noun" and len(lemma) > P2_NOUN_MAX_LEN:
        return True
    if group.pos == "adjective" and len(lemma) > P2_ADJ_MAX_LEN:
        return True
    # Hyphen thresholds
    if has_excessive_hyphens(lemma, P2_MAX_HYPHENS):
        return True
    return False


def classify_tier(group: LemmaGroup) -> Optional[str]:
    """Return tier ('auto-verified', 'auto-coverage', or None) based on completeness."""
    if not is_auto_eligible(group):
        return None

    # Hard rejection for P1
    if is_p1_rejected(group):
        # Can still be P2 if not rejected there
        if not is_p2_rejected(group):
            return "auto-coverage"
        return None

    # If mostly proper noun, only allow P2 at best (already handled by is_p1_rejected)
    mostly_proper = is_mostly_proper_noun(group)

    # Disqualify from P1 if any form has rare grammemes
    has_rare = any(P1_DISQUAL_GRAMMEMES & f.grammemes for f in group.forms)

    score, ratio = score_paradigm_completeness(group)

    # Noun thresholds
    if group.pos == "noun":
        if not mostly_proper and not has_rare and ratio >= 0.55:
            return "auto-verified"
        elif ratio >= 0.15:
            return "auto-coverage"
        else:
            return None

    # Adjective thresholds
    if group.pos == "adjective":
        if not mostly_proper and not has_rare and ratio >= 0.40:
            return "auto-verified"
        elif ratio >= 0.10:
            return "auto-coverage"
        else:
            return None

    return None


def is_p1_eligible(group: LemmaGroup) -> bool:
    return classify_tier(group) == "auto-verified"


def is_p2_eligible(group: LemmaGroup) -> bool:
    return classify_tier(group) == "auto-coverage"


def assign_quality(group: LemmaGroup, tier: str) -> float:
    """Assign a deterministic quality score."""
    score, ratio = score_paradigm_completeness(group)
    if tier == "auto-verified":
        # Scale 0.85-0.95 based on completeness
        base = 0.85 + min(0.10, ratio * 0.10)
        # Round to 2 decimals for determinism
        return round(base, 2)
    else:
        # P2: 0.55-0.75
        base = 0.55 + min(0.20, ratio * 0.20)
        return round(base, 2)


def select_p1_p2_groups(
    groups: Dict[str, LemmaGroup],
    p1_limit: int,
    p2_limit: int,
) -> Tuple[List[LemmaGroup], List[LemmaGroup]]:
    """Split groups into P1 and P2 based on deterministic ordering with quality filters.

    P1 prioritizes:
      1. PILOT_MUST_INCLUDE lemmas
      2. Domain/common seed words
      3. Nouns over adjectives
      4. Non-proper nouns
      5. Non-technical compounds
      6. Non-patronymic-like
      7. Shorter reasonable lemma
      8. Higher paradigm completeness
      9. Alphabetical tiebreak

    P2 prioritizes:
      1. PILOT_MUST_INCLUDE lemmas
      2. Domain/common seed words
      3. Nouns over adjectives
      4. Non-proper nouns
      5. Non-patronymic-like
      6. Shorter reasonable lemma
      7. Higher paradigm completeness
      8. Alphabetical tiebreak
    """
    # Build candidate lists with quality filtering
    p1_candidates: List[Tuple] = []
    p2_candidates: List[Tuple] = []

    for key, group in groups.items():
        # Skip if hard-rejected for both tiers
        if is_p1_rejected(group) and is_p2_rejected(group):
            continue

        if is_p1_eligible(group) and not is_p1_rejected(group):
            score_key = compute_p1_score(group)
            p1_candidates.append((score_key, key, group))

        # P2 candidates: any group that is P2-eligible and not P2-rejected,
        # regardless of P1 eligibility. This ensures high-quality lemmas
        # that miss the P1 cut-off still enter P2 as auto-coverage.
        if is_p2_eligible(group) and not is_p2_rejected(group):
            score_key = compute_p2_score(group)
            p2_candidates.append((score_key, key, group))

    # Deterministic sort
    p1_candidates.sort(key=lambda t: t[0])
    p2_candidates.sort(key=lambda t: t[0])

    p1_groups = [g for _, _, g in p1_candidates[:p1_limit]]
    p1_keys = {f"{g.lemma}:{g.pos}" for g in p1_groups}

    p2_groups = []
    for _, key, group in p2_candidates:
        if len(p2_groups) >= p2_limit:
            break
        if key in p1_keys:
            continue
        p2_groups.append(group)

    return p1_groups, p2_groups


def groups_to_tsv_rows(groups: List[LemmaGroup], tier: str) -> List[Tuple[str, str, str, str, str, str, str]]:
    """Flatten groups to TSV rows: (surface, lemma, pos, case_tag, number_tag, tier, quality).

    Forms without an explicit case get 'nominative' as a default (e.g. short-form
    adjectives, predicative forms). Forms without number are skipped.
    """
    rows: List[Tuple[str, str, str, str, str, str, str]] = []
    for group in groups:
        quality = assign_quality(group, tier)
        for f in group.forms:
            case = f.case if f.case else "nominative"
            if not f.number:
                continue
            rows.append((
                f.surface,
                f.lemma,
                f.pos,
                case,
                f.number,
                tier,
                str(quality),
            ))
    # Deterministic sort: surface, lemma, pos, case, number
    rows.sort(key=lambda r: (r[0], r[1], r[2], r[3], r[4]))
    # Deduplicate exact rows
    deduped: List[Tuple[str, str, str, str, str, str, str]] = []
    seen: Set[Tuple[str, str, str, str, str, str, str]] = set()
    for r in rows:
        if r not in seen:
            seen.add(r)
            deduped.append(r)
    return deduped


def compute_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def write_tsv(rows: List[Tuple[str, str, str, str, str, str, str]], out_path: Path) -> None:
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("surface\tlemma\tpos\tcase_tag\tnumber_tag\ttier\tquality\n")
        for r in rows:
            f.write("\t".join(r) + "\n")


def write_manifest(
    manifest_path: Path,
    source_name: str,
    source_url: str,
    source_revision: str,
    license_name: str,
    license_url: str,
    checksum: str,
    import_script: str,
    enabled: bool,
    p1_count: int,
    p2_count: int,
    p1_forms: int,
    p2_forms: int,
) -> None:
    manifest = {
        "source_name": source_name,
        "version": "0.92-scale",
        "import_date": datetime.now(timezone.utc).isoformat(),
        "license": license_name,
        "license_url": license_url,
        "checksum": checksum,
        "import_script": import_script,
        "tier": "auto-coverage",
        "enabled": enabled,
        "comment": (
            "Pilot auto-sourced Russian morphology from OpenCorpora-derived dictionary. "
            f"P1 auto-verified: {p1_count} lemmas ({p1_forms} forms). "
            f"P2 auto-coverage: {p2_count} lemmas ({p2_forms} forms). "
            "P1 outranks P2 in resolver. Neither affects routing/GF/Agda."
        ),
        "provenance": {
            "source_url": source_url,
            "source_revision": source_revision,
            "source_name_full": "OpenCorpora Russian Dictionary",
        },
    }
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")


def run_check(tsv_path: Path) -> bool:
    """Dry-run validation of generated TSV."""
    if not tsv_path.exists():
        print(f"CHECK FAIL: {tsv_path} not found")
        return False

    required = {"surface", "lemma", "pos", "case_tag", "number_tag", "tier", "quality"}
    with open(tsv_path, "r", encoding="utf-8") as f:
        header = f.readline().strip().split("\t")
        if not required.issubset(set(header)):
            print(f"CHECK FAIL: missing columns in TSV: {required - set(header)}")
            return False
        row_count = 0
        empty_lemmas = 0
        empty_surfaces = 0
        invalid_quality = 0
        invalid_tier = 0
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) < len(required):
                continue
            row_count += 1
            if not parts[0]:
                empty_surfaces += 1
            if not parts[1]:
                empty_lemmas += 1
            if parts[5] not in ("auto-verified", "auto-coverage"):
                invalid_tier += 1
            try:
                q = float(parts[6])
                if not (0.0 <= q <= 1.0):
                    invalid_quality += 1
            except ValueError:
                invalid_quality += 1

    print(f"CHECK OK: {row_count} rows, {empty_surfaces} empty surfaces, {empty_lemmas} empty lemmas, {invalid_tier} invalid tier, {invalid_quality} invalid quality")
    return empty_surfaces == 0 and empty_lemmas == 0 and invalid_tier == 0 and invalid_quality == 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Import Russian morphology into QxFx0 lexicon auto-source.")
    parser.add_argument("--input", type=Path, help="Path to dict.opcorpora.xml")
    parser.add_argument("--pymorphy3", action="store_true", help="Use built-in pymorphy3 dictionary instead of XML")
    parser.add_argument("--p1-limit", type=int, default=4000, help="Max P1 (auto-verified) lemmas")
    parser.add_argument("--p2-limit", type=int, default=17500, help="Max P2 (auto-coverage) lemmas")
    parser.add_argument("--output", type=Path, default=Path("spec/sql/lexicon/seed_ru_auto.tsv"), help="Output TSV path")
    parser.add_argument("--manifest", type=Path, default=Path("spec/sql/lexicon/auto_source_manifest.json"), help="Output manifest path")
    parser.add_argument("--check", action="store_true", help="Validate output TSV without writing")
    parser.add_argument("--yes", action="store_true", help="Skip interactive confirmation")
    args = parser.parse_args()

    if args.check:
        ok = run_check(args.output)
        return 0 if ok else 1

    if not args.input and not args.pymorphy3:
        print("Error: specify --input path/to/dict.opcorpora.xml or --pymorphy3")
        return 1

    # Load / parse
    if args.input:
        print(f"Parsing OpenCorpora XML: {args.input}")
        groups = parse_opencorpora_xml(args.input)
        source_name = "opencorpora-xml"
        source_url = "https://opencorpora.org/?page=export"
        source_revision = "unknown"
        checksum = compute_sha256(args.input)
    else:
        print("Extracting from pymorphy3 built-in dictionary (OpenCorpora-derived)")
        groups = parse_pymorphy3_dict(args.p1_limit, args.p2_limit)
        source_name = "pymorphy3-opencorpora-dict"
        source_url = "https://opencorpora.org/"
        source_revision = "417150"  # from pymorphy3 meta
        checksum = "pymorphy3-builtin-dict"

    print(f"Total lemma groups loaded: {len(groups)}")

    p1_groups, p2_groups = select_p1_p2_groups(groups, args.p1_limit, args.p2_limit)
    print(f"P1 (auto-verified) selected: {len(p1_groups)} lemmas")
    print(f"P2 (auto-coverage) selected: {len(p2_groups)} lemmas")

    p1_rows = groups_to_tsv_rows(p1_groups, "auto-verified")
    p2_rows = groups_to_tsv_rows(p2_groups, "auto-coverage")
    all_rows = p1_rows + p2_rows

    # Re-sort combined deterministically, with P1 before P2 for stable reading
    # (export_lexicon.py doesn't care about order inside TSV because it inserts into SQL)
    # But deterministic output is required for gate stability.
    all_rows.sort(key=lambda r: (r[0], r[1], r[2], r[3], r[4]))

    print(f"Total forms written: {len(all_rows)} (P1={len(p1_rows)}, P2={len(p2_rows)})")

    if not args.yes:
        resp = input(f"Write {len(all_rows)} rows to {args.output}? [y/N] ")
        if resp.lower() not in ("y", "yes"):
            print("Aborted.")
            return 1

    # Write TSV
    write_tsv(all_rows, args.output)

    # Compute checksum of written TSV for manifest
    tsv_checksum = compute_sha256(args.output)

    # Write manifest
    write_manifest(
        manifest_path=args.manifest,
        source_name=source_name,
        source_url=source_url,
        source_revision=source_revision,
        license_name="CC-BY-SA-3.0",
        license_url="https://creativecommons.org/licenses/by-sa/3.0/",
        checksum=tsv_checksum,
        import_script="scripts/import_ru_opencorpora.py",
        enabled=True,
        p1_count=len(p1_groups),
        p2_count=len(p2_groups),
        p1_forms=len(p1_rows),
        p2_forms=len(p2_rows),
    )

    # Validate
    ok = run_check(args.output)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
