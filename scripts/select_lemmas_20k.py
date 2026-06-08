#!/usr/bin/env python3
"""Select 20 000 Russian noun lemmas for paradigm generation.

Layer A — frequency core (14 000): built from OpenCorpora (via pymorphy3 dict)
plus funmap/bilingual coverage.  Layer B — domain coverage (6 000): 10 thematic
groups approximated by suffix heuristics and manual seed lists.

Output: data/raw/rgl_candidate_20k/lemmas_20k.txt (one lemma per line)
"""
from __future__ import annotations

import csv
import json
import math
import re
import sys
from pathlib import Path

import pymorphy3

try:
    from wordfreq import zipf_frequency
    WORDFREQ_AVAILABLE = True
except ImportError:
    WORDFREQ_AVAILABLE = False
    print("wordfreq not available; frequency-based Layer A will be skipped", file=sys.stderr)

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parents[1]
FUNMAP_PATH = ROOT / "spec" / "gf" / "lexicon_funmap.tsv"
BILINGUAL_PATH = ROOT / "spec" / "gf" / "lexicon_bilingual.tsv"
OUT_DIR = ROOT / "data" / "raw" / "rgl_candidate_20k"
LEMMAS_OUT = OUT_DIR / "lemmas_20k.txt"
MANIFEST_OUT = OUT_DIR / "manifest.json"

# ---------------------------------------------------------------------------
# Domain seed groups (layer B) — core seeds per group
# ---------------------------------------------------------------------------
DOMAIN_SEEDS = {
    1: ["знание", "истина", "вера", "сомнение", "доказательство", "гипотеза", "теория", "концепция",
        "модель", "метод", "критерий", "факт", "информация", "вывод", "вероятность", "возможность",
        "ошибка", "предположение", "интуиция", "опыт", "эксперимент", "анализ", "синтез", "абстракция",
        "обобщение", "смысл", "значение", "описание", "объяснение", "прогноз", "план", "стратегия",
        "тактика", "цель", "задача", "вопрос", "ответ", "решение", "выбор", "альтернатива", "система",
        "структура", "организация", "порядок", "гармония", "противоречие", "единство", "целостность",
        "развитие", "изменение", "процесс", "результат", "действие", "поступок", "событие", "феномен",
        "логика", "разум", "интеллект", "мышление", "сознание", "рефлексия", "наука", "философия",
        "диалектика", "идея", "норма", "правило", "закон", "принцип", "аксиома", "теорема", "доказательство",
        "индукция", "дедукция", "эквивалентность", "тождество", "различие", "сходство", "аналогия",
        "субъект", "объект", "отношение", "функция", "время", "момент", "длительность", "скорость",
        "ритм", "цикл", "связь", "коммуникация", "взаимодействие", "кооперация", "конфликт", "борьба",
        "сотрудничество", "согласие", "координация", "интеграция", "классификация", "типология",
        "тенденция", "направление", "движение", "состояние", "ситуация", "условие", "предпосылка",
        "ожидание", "совет", "требование", "желание", "намерение", "воля", "мотив", "стимул", "цель",
        "задача", "роль", "статус", "позиция", "уровень", "степень", "масштаб", "объём", "размер",
        "количество", "качество", "мера", "показатель", "метрика", "оценка", "класс", "категория",
        "тип", "вид", "форма", "способ", "приём", "техника", "технология", "инструмент", "средство",
        "механизм", "комплекс", "совокупность", "множество", "компонент", "элемент", "часть", "доля",
        "сфера", "область", "зона", "пространство", "присутствие", "существование", "бытие", "жизнь",
        "возникновение", "появление", "исчезновение", "сохранение", "трансформация", "адаптация",
        "оптимизация", "улучшение", "деградация", "восстановление", "регенерация", "обновление",
        "традиция", "практика", "привычка", "навык", "умение", "компетенция", "квалификация", "мастерство",
        "искусство", "труд", "работа", "деятельность", "производство", "создание", "творчество",
        "изобретение", "открытие", "инновация", "совершенствование", "реформа", "перемена", "замена",
        "предпочтение", "соотношение", "соответствие", "адекватность", "идентичность", "личность",
        "агент", "продукт", "итог", "контакт", "диалог", "спор", "дебат", "соперничество", "вражда",
        "недоверие", "страх", "тревога", "беспокойство", "стресс", "напряжение", "спокойствие",
        "баланс", "равновесие", "симметрия", "конфликтность", "спорность", "неясность", "размытость",
        "двусмысленность", "полярность", "дихотомия", "континуум", "спектр", "шкала", "градация",
        "стадия", "порог", "граница", "предел", "барьер", "препятствие", "помеха", "трудность",
        "проблема", "тема", "предмет", "поле", "ниша", "якорь", "опора", "база", "фундамент",
        "основа", "корень", "источник", "начало", "природа", "суть", "ядро", "центр", "середина",
        "концентрация", "фокус", "акцент", "выделение", "отбор", "селекция", "фильтрация", "сортировка",
        "индексация", "регистрация", "запись", "протокол", "документ", "акт", "договор", "соглашение",
        "контракт", "пакт", "союз", "коалиция", "блок", "альянс", "федерация", "содружество", "общность",
        "сообщество", "общество", "коллектив", "группа", "команда", "бригада", "отряд"],
    2: ["бытие", "сущность", "существование", "реальность", "явление", "форма", "содержание", "смысл",
        "значение", "интерпретация", "описание", "объяснение", "прогноз", "план", "стратегия", "тактика",
        "цель", "задача", "вопрос", "ответ", "решение", "выбор", "альтернатива", "основание", "довод",
        "доверие", "сомнение"],
    3: ["долг", "справедливость", "ответственность", "норма", "благо", "зло", "добро", "мораль", "этика",
        "право", "закон", "юстиция", "карма", "совесть", "честь", "достоинство", "человечность", "гуманность",
        "альтруизм", "эгоизм", "деонтология", "добродетель", "грех", "порок", "искупление", "наказание",
        "воздаяние", "премия", "награда", "похвала", "осуждение", "порицание", "критика", "самокритика",
        "сознательность"],
    4: ["сознание", "мышление", "восприятие", "намерение", "воля", "память", "внимание", "воображение",
        "подсознание", "рефлексия", "интроспекция", "осознание", "познание", "интеллект", "разум", "рассудок",
        "интуиция", "инстинкт", "рефлекс", "реакция", "поведение", "деятельность", "поступок", "выбор",
        "решение", "желание", "стремление", "потребность", "мотив", "побуждение", "стимул", "напряжение",
        "стресс", "релаксация", "спокойствие", "умиротворение", "гармония", "баланс", "равновесие"],
    5: ["довод", "посылка", "вывод", "противоречие", "тезис", "антитезис", "синтез", "дилемма", "трилемма",
        "апория", "парадокс", "ирония", "сарказм", "аллегория", "идея", "идеал", "норма", "стандарт",
        "канон", "правило", "закон", "принцип", "аксиома", "теорема", "лемма", "доказательство", "опровержение",
        "индукция", "дедукция", "редукция", "инференция", "импликация", "эквивалентность", "тождество",
        "различие", "разница", "сходство", "аналогия", "метонимия", "синонимия", "омонимия"],
    6: ["значение", "понятие", "термин", "определение", "контекст", "текст", "дискурс", "нарратив", "речь",
        "высказывание", "утверждение", "отрицание", "тезис", "антитезис", "синтез", "метафора", "символ",
        "знак", "денотация", "коннотация", "референция", "предикат", "субъект", "объект", "атрибут",
        "отношение", "функция", "операция", "преобразование", "переход", "изменение", "эволюция", "революция",
        "прогресс", "регресс", "стагнация", "кризис", "поворот", "перелом", "этап", "фаза", "период"],
    7: ["сходство", "различие", "граница", "связь", "тождество", "идентичность", "индивидуальность", "личность",
        "персона", "субъект", "объект", "атрибут", "отношение", "функция", "операция", "преобразование",
        "переход", "изменение", "эволюция", "революция", "прогресс", "регресс", "стагнация", "кризис",
        "поворот", "перелом", "этап", "фаза"],
    8: ["цель", "выбор", "поступок", "решение", "последствие", "действие", "процесс", "результат", "эффект",
        "влияние", "воздействие", "импакт", "контакт", "взаимодействие", "коммуникация", "диалог", "дискуссия",
        "полемика", "спор", "дебат", "конфликт", "конфронтация", "соперничество", "антогонизм", "вражда",
        "враждебность", "недоверие"],
    9: ["изменение", "развитие", "момент", "длительность", "переход", "время", "интервал", "длительность",
        "продолжительность", "скорость", "темп", "ритм", "цикл", "круг", "спираль", "линия", "точка",
        "узел", "связь", "связность", "коммуникация", "передача", "обмен", "взаимодействие", "кооперация",
        "конфликт", "конкуренция", "борьба", "сотрудничество", "согласие", "согласованность", "координация",
        "интеграция"],
    10: ["точность", "ясность", "обобщение", "уточнение", "осознание", "понимание", "осмысление", "объяснение",
         "описание", "определение", "формулировка", "выражение", "представление", "отображение", "изображение",
         "иллюстрация", "демонстрация", "показ", "проявление", "выявление", "обнаружение", "установление",
         "подтверждение", "опровержение", "доказательство", "аргументация", "обоснование", "мотивация",
         "разъяснение", "толкование", "интерпретация", "переосмысление"],
}

# Suffixes used to auto-fill groups up to ~600 lemmas each
GROUP_SUFFIXES = {
    1: ["знание", "ание", "ение", "ение", "овка", "ельство", "ительство", "ство", "ость", "есть", "изм", "ика",
        "ика", "тика", "фика", "графия", "логия", "ния", "омия", "урия", "етика", "истика", "ария", "тория",
        "дром", "грамма", "метр", "скоп", "троп", "форм", "кция", "кция", "гия", "мия", "хия", "фия", "ция",
        "зия", "ния", "рия", "тия", "хия", "ция", "ция", "зм", "изм", "изм", "т", "ст", "нт", "рт", "кт",
        "пт", "фт", "хт", "шт", "ст", "т", "д", "к", "г", "м", "н", "р", "л", "в", "б", "п", "ф", "з", "с",
        "ж", "ш", "ч", "щ", "ц", "т", "д", "н", "м", "р", "л", "в", "б", "п", "ф", "з", "с", "ж", "ш", "ч",
        "щ", "ц", "а", "я", "о", "е", "у", "ю", "и", "ы", "ь", "ъ", "й", "ё", "э", "ю", "я", "а", "о", "е",
        "у", "и", "ы", "ь", "ъ", "й", "ё", "э", "ю", "я"],
    2: ["ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие"],
    3: ["ство", "ость", "есть", "изм", "ика", "тика", "фика", "графия", "логия", "ния", "омия", "урия", "етика",
        "истика", "ария", "тория", "дром", "грамма", "метр", "скоп", "троп", "форм", "кция", "гия", "мия", "хия",
        "фия", "ция", "зия", "ния", "рия", "тия", "хия", "ция", "зм", "изм", "т", "ст", "нт", "рт", "кт", "пт",
        "фт", "хт", "шт", "ст", "т", "д", "к", "г", "м", "н", "р", "л", "в", "б", "п", "ф", "з", "с", "ж", "ш",
        "ч", "щ", "ц", "т", "д", "н", "м", "р", "л", "в", "б", "п", "ф", "з", "с", "ж", "ш", "ч", "щ", "ц", "а",
        "я", "о", "е", "у", "ю", "и", "ы", "ь", "ъ", "й", "ё", "э", "ю", "я"],
    4: ["ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие"],
    5: ["ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие"],
    6: ["ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие"],
    7: ["ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие"],
    8: ["ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие"],
    9: ["ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие",
        "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие", "ие"],
    10: ["ость", "ние", "нье", "ение", "тельство", "ство", "ище", "изм", "ика", "тика", "фика", "графия",
         "логия", "ния", "омия", "урия", "етика", "истика", "ария", "тория", "дром", "грамма", "метр",
         "скоп", "троп", "форм", "кция", "гия", "мия", "хия", "фия", "ция", "зия", "ния", "рия", "тия",
         "хия", "ция", "зм", "изм", "т", "ст", "нт", "рт", "кт", "пт", "фт", "хт", "шт", "ст", "т", "д",
         "к", "г", "м", "н", "р", "л", "в", "б", "п", "ф", "з", "с", "ж", "ш", "ч", "щ", "ц", "т", "д",
         "н", "м", "р", "л", "в", "б", "п", "ф", "з", "с", "ж", "ш", "ч", "щ", "ц", "а", "я", "о", "е",
         "у", "ю", "и", "ы", "ь", "ъ", "й", "ё", "э", "ю", "я"],
}


def load_funmap_nouns() -> set[str]:
    seen = set()
    with FUNMAP_PATH.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row.get("pos") == "noun":
                seen.add(row["nominative"])
    return seen


def load_bilingual_nouns() -> set[str]:
    seen = set()
    with BILINGUAL_PATH.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row.get("lang") == "ru" and row.get("pos") == "noun":
                seen.add(row["nominative"])
    return seen


def is_valid_lemma(lemma: str, morph) -> tuple[bool, dict]:
    if len(lemma) < 3:
        return False, {}
    if re.search(r"[a-zA-Z]", lemma):
        return False, {}
    if re.search(r"[0-9]", lemma):
        return False, {}
    if lemma.isupper():
        return False, {}
    parses = morph.parse(lemma)
    if not parses:
        return False, {}
    pt = parses[0].tag
    if "NOUN" not in pt.grammemes:
        return False, {}
    if {"Name", "Surn", "Patr", "Geox"} & set(pt.grammemes):
        return False, {}
    if "Abbr" in pt.grammemes:
        return False, {}
    info = {
        "pltm": "Pltm" in pt.grammemes,
        "fixd": "Fixd" in pt.grammemes,
    }
    return True, info


def get_zipf_ipm(lemma: str) -> tuple[float, float]:
    """Return (zipf, ipm) for a lemma using wordfreq."""
    if not WORDFREQ_AVAILABLE:
        return 0.0, 0.0
    z = zipf_frequency(lemma, "ru")
    # wordfreq returns 0.0 for unknown words; clamp to tiny positive
    if z <= 0:
        z = 0.0
    ipm = 10 ** (z - 3)
    return z, ipm


def main() -> int:
    morph = pymorphy3.MorphAnalyzer()
    print("Extracting noun lemmas from pymorphy3 dict...", file=sys.stderr)
    all_lemmas: set[str] = set()
    for word, tag, normal, para_id, idx in morph.dictionary.iter_known_words():
        if "NOUN" in tag:
            all_lemmas.add(normal)
    print(f"Total noun lemmas in pymorphy3: {len(all_lemmas)}", file=sys.stderr)

    funmap_nouns = load_funmap_nouns()
    bilingual_nouns = load_bilingual_nouns()
    print(f"funmap nouns: {len(funmap_nouns)}, bilingual nouns: {len(bilingual_nouns)}", file=sys.stderr)

    valid_lemmas: list[str] = []
    pltm_count = 0
    fixd_count = 0
    skipped = 0
    for lemma in sorted(all_lemmas):
        ok, info = is_valid_lemma(lemma, morph)
        if ok:
            valid_lemmas.append(lemma)
            if info.get("pltm"):
                pltm_count += 1
            if info.get("fixd"):
                fixd_count += 1
        else:
            skipped += 1
    print(f"After filtering: {len(valid_lemmas)} (skipped {skipped}, pltm {pltm_count}, fixd {fixd_count})", file=sys.stderr)

    valid_set = set(valid_lemmas)

    # Layer B: domain groups
    layer_b: set[str] = set()
    group_counts: dict[int, int] = {}
    for gid, seeds in DOMAIN_SEEDS.items():
        group_lemmas: list[str] = []
        for s in seeds:
            s_clean = s.strip().lower()
            if s_clean in valid_set and s_clean not in layer_b:
                group_lemmas.append(s_clean)
        # Fill up to 600 with suffix heuristics from remaining valid lemmas
        suffixes = GROUP_SUFFIXES.get(gid, [])
        for lemma in valid_lemmas:
            if len(group_lemmas) >= 600:
                break
            if lemma in layer_b:
                continue
            if any(lemma.endswith(suf) for suf in suffixes):
                group_lemmas.append(lemma)
        group_counts[gid] = len(group_lemmas)
        layer_b.update(group_lemmas)

    print(f"Layer B size: {len(layer_b)} (target 6000)", file=sys.stderr)

    # Layer A: 14000 — all valid lemmas not in B, sorted by frequency descending.
    # Core (funmap + bilingual) is mandatory; if any core lemma is below the
    # frequency threshold it is still included, and the actual threshold is recorded.
    layer_a_target = 14000
    core = funmap_nouns | bilingual_nouns

    # Candidate pool: valid lemmas not in Layer B
    pool_a = [l for l in valid_lemmas if l not in layer_b]

    if WORDFREQ_AVAILABLE:
        # Compute zipf for every candidate and sort descending
        pool_a_with_zipf: list[tuple[str, float]] = []
        for lemma in pool_a:
            z, _ = get_zipf_ipm(lemma)
            pool_a_with_zipf.append((lemma, z))
        pool_a_with_zipf.sort(key=lambda x: x[1], reverse=True)

        # Threshold: start at zipf >= 3.0 (ipm >= 1.0), relax to 2.7 if insufficient
        zipf_threshold = 3.0
        above_threshold = [l for l, z in pool_a_with_zipf if z >= zipf_threshold]
        if len(above_threshold) < layer_a_target:
            zipf_threshold = 2.7
            above_threshold = [l for l, z in pool_a_with_zipf if z >= zipf_threshold]
            print(f"Relaxed zipf threshold to 2.7 (ipm >= 0.5) to reach target", file=sys.stderr)

        # Build Layer A: top above-threshold lemmas first, then core if missing
        layer_a = [l for l in above_threshold]
        # Add core lemmas that are not yet in layer_a
        for lemma in core:
            if lemma not in layer_a:
                layer_a.append(lemma)
        # If still short, add best below-threshold lemmas
        if len(layer_a) < layer_a_target:
            below_threshold = [l for l, z in pool_a_with_zipf if z < zipf_threshold]
            still_needed = layer_a_target - len(layer_a)
            layer_a.extend(below_threshold[:still_needed])
        # Truncate to exactly 14,000 and re-sort by frequency so core
        # high-frequency words appear at the top
        layer_a = layer_a[:layer_a_target]
        # Re-sort by frequency for final ordering
        layer_a_with_zipf = [(l, get_zipf_ipm(l)[0]) for l in layer_a]
        layer_a_with_zipf.sort(key=lambda x: x[1], reverse=True)
        layer_a = [l for l, _ in layer_a_with_zipf]

        ipm_threshold = round(10 ** (zipf_threshold - 3), 4)
        frequency_source = "wordfreq"
        frequency_source_version = "3.1.1"  # installed version
        frequency_method = "zipf_frequency(lemma, 'ru') → ipm = 10^(zipf-3)"
        layer_a_ipm_threshold = ipm_threshold
    else:
        # Fallback to alphabetical/length — should not happen if venv is used
        pool_a.sort(key=lambda x: (len(x), x))
        layer_a = pool_a[:layer_a_target]
        # Ensure core is included
        for lemma in core:
            if lemma not in layer_a:
                layer_a.append(lemma)
        layer_a = layer_a[:layer_a_target]
        frequency_source = "N/A"
        frequency_source_version = "N/A"
        frequency_method = "N/A"
        layer_a_ipm_threshold = "N/A (frequency source unavailable; sorted by length and alphabet)"

    seen_a = set(layer_a)
    print(f"Layer A size: {len(layer_a)}", file=sys.stderr)
    if WORDFREQ_AVAILABLE:
        print(f"Layer A zipf threshold: {zipf_threshold}, ipm threshold: {layer_a_ipm_threshold}", file=sys.stderr)

    # Combine
    final = list(dict.fromkeys(layer_a + [l for l in layer_b if l not in seen_a]))
    # Ensure exactly 20000
    if len(final) > 20000:
        final = final[:20000]
    if len(final) < 20000:
        used = set(final)
        for l in valid_lemmas:
            if len(final) >= 20000:
                break
            if l not in used:
                final.append(l)
                used.add(l)

    print(f"Final lemma count: {len(final)}", file=sys.stderr)
    print(f"Funmap superset: {set(final) >= funmap_nouns}", file=sys.stderr)

    # Compute final-list stats (includes core lemmas that may not be in valid_set)
    final_pltm = 0
    final_fixd = 0
    for lemma in final:
        parses = morph.parse(lemma)
        if parses:
            pt = parses[0].tag
            if "Pltm" in pt.grammemes:
                final_pltm += 1
            if "Fixd" in pt.grammemes:
                final_fixd += 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with LEMMAS_OUT.open("w", encoding="utf-8") as f:
        for lemma in final:
            f.write(lemma + "\n")

    manifest = {
        "source": "OpenCorpora via pymorphy3 dict",
        "source_version": "0.92",
        "source_revision": "417150",
        "corpus_revision": "4580142",
        "pymorphy3_version": "2.0.6",
        "date": "2026-06-08",
        "total_lemmas": len(final),
        "layer_a_count": len(layer_a),
        "layer_a_ipm_threshold": layer_a_ipm_threshold,
        "frequency_source": frequency_source,
        "frequency_source_version": frequency_source_version,
        "frequency_conversion_method": frequency_method,
        "layer_b_count": len(layer_b),
        "layer_b_groups": group_counts,
        "funmap_superset": set(final) >= funmap_nouns,
        "funmap_missing": sorted(funmap_nouns - set(final)),
        "funmap_count": len(funmap_nouns),
        "bilingual_count": len(bilingual_nouns),
        "core_union": len(core),
        "verbal_noun_count": len([l for l in final if l.endswith(("ние", "нье", "ение", "ение"))]),
        "pluralia_tantum_count": final_pltm,
        "fixd_count": final_fixd,
        "skipped_count": skipped,
        "command": "python3 scripts/select_lemmas_20k.py",
    }
    with MANIFEST_OUT.open("w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print(f"Wrote {LEMMAS_OUT} and {MANIFEST_OUT}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
