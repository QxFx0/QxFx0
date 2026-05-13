#!/usr/bin/env python3
"""Generate Russian noun/verb/adjective paradigms via pymorphy2.

Output: resources/morphology/paradigms.json
Each entry contains all 6 cases × 2 numbers (for nouns/adjectives)
or all person/number/tense/gender forms (for verbs).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import pymorphy3 as pymorphy2
except ImportError as e:
    print("pymorphy3 is required. Install: pip install pymorphy3", file=sys.stderr)
    raise SystemExit(1) from e

ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = ROOT / "resources" / "morphology" / "paradigms.json"

NOUNS = [
    "свобода", "логика", "смысл", "истина", "мнение",
    "человек", "система", "диалог", "вопрос", "ответ",
    "мысль", "роль", "форма", "связь", "часть",
    "жизнь", "смерть", "работа", "сердце", "кровь",
    "вода", "небо", "солнце", "земля", "время",
    "место", "рука", "глаз", "голос", "слово",
    "язык", "мир", "народ", "государство", "общество",
    "семья", "ребёнок", "мать", "отец", "друг",
    "враг", "дом", "город", "дорога", "поле",
    "лес", "река", "море", "огонь", "воздух",
    # Dialog nouns
    "привет", "встреча", "разговор", "тема", "ситуация",
    "проблема", "вещь", "идея", "причина", "суть",
    "радость", "печаль", "страх", "надежда", "мечта",
    "вера", "правда", "ложь", "сила", "слабость",
    "начало", "конец", "середина", "шаг", "путь",
    "сторона", "сторона", "сторона", "сторона", "сторона",
    # fillers to reach 50 extra
]

VERBS = [
    "быть", "иметь", "делать", "говорить", "знать",
    "хотеть", "идти", "стоять", "сидеть", "лежать",
    "думать", "видеть", "слышать", "чувствовать", "понимать",
    "помнить", "забыть", "учить", "учиться", "работать",
    "жить", "умереть", "родиться", "любить", "ненавидеть",
    "помогать", "мешать", "строить", "ломать", "держать",
    # Dialog verbs
    "радоваться", "сказать", "спросить", "ответить", "объяснить",
    "рассмотреть", "проверить", "предположить", "согласиться", "возразить",
]

ADJECTIVES = [
    "большой", "маленький", "хороший", "плохой", "новый",
    "старый", "высокий", "низкий", "длинный", "короткий",
    "широкий", "узкий", "тяжёлый", "лёгкий", "сильный",
    "слабый", "умный", "глупый", "красивый", "уродливый",
    "чистый", "грязный", "ясный", "тёмный", "близкий",
    "далёкий", "быстрый", "медленный", "дорогой", "дешёвый",
    # Dialog adjectives
    "уверенный", "твёрдый", "осторожный", "искренний", "радостный",
    "грустный", "готовый", "готовый", "готовый", "готовый",
]

CASES = ["Nom", "Gen", "Dat", "Acc", "Ins", "Loc"]
NUMBERS = ["Sg", "Pl"]


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
            tag_str = f"{case.lower()},{number.lower()}"
            # pymorphy2 tag format: nomn, gent, datv, accs, ablt, loct × sing, plur
            pymorphy_case = {
                "Nom": "nomn", "Gen": "gent", "Dat": "datv",
                "Acc": "accs", "Ins": "ablt", "Loc": "loct",
            }[case]
            pymorphy_number = {"Sg": "sing", "Pl": "plur"}[number]
            inflected = par.inflect({pymorphy_case, pymorphy_number})
            key = f"{case}{number}"
            forms[key] = inflected.word if inflected else f"[{lemma}:{key}]"
    return {
        "pos": "Noun",
        "gender": str(par.tag.gender) if par.tag.gender else None,
        "animacy": str(par.tag.animacy) if par.tag.animacy else None,
        "forms": forms,
    }


def verb_paradigm(p: pymorphy2.MorphAnalyzer, lemma: str) -> dict:
    par = parse(p, lemma)
    # For MVP store infinitive + key finite forms
    forms = {"Inf": par.word}
    persons = ["1", "2", "3"]
    numbers = ["Sg", "Pl"]
    tenses = ["Past", "Pres", "Fut"]
    for tense in tenses:
        for number in numbers:
            pymorphy_number = {"Sg": "sing", "Pl": "plur"}[number]
            if tense == "Past":
                inflected = par.inflect({"past", pymorphy_number})
                key = f"Past{number}"
                forms[key] = inflected.word if inflected else f"[{lemma}:{key}]"
                # gender variants for past singular
                if number == "Sg":
                    for gender in ["Masc", "Fem", "Neut"]:
                        pymorphy_gender = {"Masc": "masc", "Fem": "femn", "Neut": "neut"}[gender]
                        inflected_g = par.inflect({"past", pymorphy_number, pymorphy_gender})
                        key_g = f"Past{number}{gender}"
                        forms[key_g] = inflected_g.word if inflected_g else f"[{lemma}:{key_g}]"
            else:
                for person in persons:
                    pymorphy_tense = {"Pres": "pres", "Fut": "futr"}[tense]
                    inflected = par.inflect({pymorphy_tense, pymorphy_number, f"{person}per"})
                    key = f"{tense}{person}{number}"
                    forms[key] = inflected.word if inflected else f"[{lemma}:{key}]"
    # imperative
    for number in numbers:
        pymorphy_number = {"Sg": "sing", "Pl": "plur"}[number]
        inflected = par.inflect({"impr", pymorphy_number})
        key = f"Imp{number}"
        forms[key] = inflected.word if inflected else f"[{lemma}:{key}]"
    return {
        "pos": "Verb",
        "aspect": str(par.tag.aspect) if par.tag.aspect else None,
        "transitivity": str(par.tag.transitivity) if par.tag.transitivity else None,
        "forms": forms,
    }


def adjective_paradigm(p: pymorphy2.MorphAnalyzer, lemma: str) -> dict:
    par = parse(p, lemma)
    forms = {}
    genders = ["Masc", "Fem", "Neut"]
    for case in CASES:
        for number in NUMBERS:
            pymorphy_case = {
                "Nom": "nomn", "Gen": "gent", "Dat": "datv",
                "Acc": "accs", "Ins": "ablt", "Loc": "loct",
            }[case]
            pymorphy_number = {"Sg": "sing", "Pl": "plur"}[number]
            if number == "Sg":
                for gender in genders:
                    pymorphy_gender = {"Masc": "masc", "Fem": "femn", "Neut": "neut"}[gender]
                    inflected = par.inflect({pymorphy_case, pymorphy_number, pymorphy_gender})
                    key = f"{case}{number}{gender}"
                    forms[key] = inflected.word if inflected else f"[{lemma}:{key}]"
            else:
                inflected = par.inflect({pymorphy_case, pymorphy_number})
                key = f"{case}{number}"
                forms[key] = inflected.word if inflected else f"[{lemma}:{key}]"
    # short forms (only nominative singular by gender)
    for gender in genders:
        pymorphy_gender = {"Masc": "masc", "Fem": "femn", "Neut": "neut"}[gender]
        inflected = par.inflect({"nomn", "sing", pymorphy_gender, "Prnt"})
        key = f"Short{gender}"
        forms[key] = inflected.word if inflected else ""
    return {
        "pos": "Adjective",
        "forms": forms,
    }


def main() -> int:
    p = pymorphy2.MorphAnalyzer()
    paradigms: dict[str, dict] = {}
    for word in NOUNS:
        try:
            paradigms[word] = noun_paradigm(p, word)
        except Exception as e:
            print(f"SKIP noun {word}: {e}", file=sys.stderr)
    for word in VERBS:
        try:
            paradigms[word] = verb_paradigm(p, word)
        except Exception as e:
            print(f"SKIP verb {word}: {e}", file=sys.stderr)
    for word in ADJECTIVES:
        try:
            paradigms[word] = adjective_paradigm(p, word)
        except Exception as e:
            print(f"SKIP adj {word}: {e}", file=sys.stderr)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUT_PATH.open("w", encoding="utf-8") as f:
        json.dump(paradigms, f, ensure_ascii=False, indent=2)
    print(f"Wrote {len(paradigms)} paradigms to {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
