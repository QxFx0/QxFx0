#!/usr/bin/env python3
import csv
import json
import os
import re
import sys
from collections import Counter, defaultdict


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
DEFAULT_INPUT_TXT = os.path.join(REPO_ROOT, "research_packs", "input.txt")
DEFAULT_CSV = "/home/liskil/Downloads/russian_school_parser_corpus_400.csv"

OUTPUT_LEXICON_JSON = os.path.join(REPO_ROOT, "resources", "input_lexicon", "lexicon.json")
OUTPUT_GENERATED_HS = os.path.join(REPO_ROOT, "src", "QxFx0", "Semantic", "Input", "GeneratedLexicon.hs")
OUTPUT_COVERAGE = os.path.join(REPO_ROOT, "reports", "input_coverage_report.json")
OUTPUT_COLLISIONS = os.path.join(REPO_ROOT, "reports", "input_collision_report.json")
OUTPUT_UNKNOWN = os.path.join(REPO_ROOT, "reports", "input_unknown_candidates.json")

TOKEN_RE = re.compile(r"[а-яё-]+", flags=re.IGNORECASE)

CANONICAL_LEMMA_OVERRIDES = {
    "субьектность": "субъектность",
    "субьектности": "субъектность",
    "субьектностью": "субъектность",
    "купил": "купить",
    "купила": "купить",
    "купили": "купить",
    "куплю": "купить",
    "купишь": "купить",
    "купит": "купить",
    "живу": "жить",
    "живешь": "жить",
    "живёт": "жить",
    "живет": "жить",
    "живем": "жить",
    "живём": "жить",
    "живете": "жить",
    "живёте": "жить",
    "живут": "жить",
    "оказался": "оказаться",
    "оказалась": "оказаться",
    "оказалось": "оказаться",
    "оказались": "оказаться",
    "оказывается": "оказаться",
    "голубая": "голубой",
    "голубое": "голубой",
    "голубые": "голубой",
    "голубого": "голубой",
    "голубому": "голубой",
    "дома": "дом",
}

POS_VALUES = {
    "PosNoun",
    "PosAdjective",
    "PosVerb",
    "PosAdverb",
    "PosPronoun",
    "PosNumeral",
    "PosPreposition",
    "PosConjunction",
    "PosParticle",
    "PosInterjection",
}

SEM_VALUES = {
    "SemWorldObject",
    "SemPhysicalObject",
    "SemWorldPhenomenon",
    "SemMentalObject",
    "SemAbstractConcept",
    "SemQualityProperty",
    "SemPurposeFunction",
    "SemRelation",
    "SemAction",
    "SemState",
    "SemCause",
    "SemComparison",
    "SemIdentity",
    "SemKnowledge",
    "SemDialogueRepair",
    "SemDialogueInvitation",
    "SemSelfReference",
    "SemUserReference",
    "SemContemplative",
    "SemUnknown",
}

PREPOSITIONS = {
    "в", "во", "на", "к", "ко", "у", "о", "об", "обо", "от", "до", "по", "из", "изо", "с", "со",
    "без", "для", "при", "перед", "между", "про", "над", "под", "через", "из-за", "вокруг", "около",
}
CONJUNCTIONS = {"и", "или", "а", "но", "если", "чтобы", "когда", "хотя", "либо", "потому", "как"}
PARTICLES = {"не", "ни", "ли", "же", "бы", "вот", "только", "лишь", "даже", "пусть", "разве", "неужели"}
INTERJECTIONS = {"эй", "ах", "ох", "увы", "ого", "ну"}
PRONOUNS = {
    "я", "ты", "он", "она", "оно", "мы", "вы", "они",
    "мне", "меня", "мной", "тебя", "тебе", "тобой", "нас", "вам", "вами", "вас",
    "мой", "твой", "наш", "ваш", "себя", "это", "этот", "эта", "эти", "кто", "что",
}
NUMERALS = {"ноль", "один", "два", "три", "четыре", "пять", "десять", "сто", "первый", "второй", "третий"}
QUESTION_WORDS = {"что", "кто", "где", "когда", "почему", "зачем", "как"}
WORLD_WORDS = {
    "солнце", "земля", "мир", "космос", "дом", "город", "лес", "море", "река", "стол", "ветер",
    "небо", "осень",
}
WORLD_PHENOMENA_WORDS = {"небо", "осень", "дождь", "ветер", "гроза", "снег"}
MENTAL_WORDS = {"мысль", "идея", "смысл", "логика", "память", "разум", "понимание", "знание"}
ABSTRACT_WORDS = {
    "правда", "истина", "субъектность", "явление", "свобода", "любовь", "смерть", "тишина",
    "ответственность", "граница", "сущность", "определение",
    "субьектность",
}
PURPOSE_WORDS = {"функция", "назначение", "цель", "нужный", "полезный", "служить", "использоваться"}
COMPARISON_WORDS = {"разница", "отличие", "между", "логичнее", "вероятнее", "естественнее", "правильнее", "лучше", "хуже"}
CAUSE_WORDS = {"почему", "причина", "следствие", "поэтому", "поскольку", "из-за"}
KNOWLEDGE_WORDS = {"знать", "понимать", "известно", "определение", "значить"}
INVITATION_WORDS = {"поговорим", "обсудим", "давай", "рассмотрим"}
REPAIR_WORDS = {"сбой", "ошибка", "разрыв", "контакт", "потерян", "непонимание"}
CONTEMPLATIVE_WORDS = {"тишина", "дом", "смысл", "любовь", "смерть", "время", "страх", "память", "свобода", "правда", "истина"}
ACTION_WORDS = {"купить", "жить", "оказаться", "делать"}
KNOWN_ADJECTIVES = {"голубой", "хороший", "грустный"}

BASE_LEXICON = [
    {"lemma": "я", "pos": "PosPronoun", "sem": ["SemSelfReference"], "forms": ["я", "мне", "меня", "мной", "мною"]},
    {"lemma": "мы", "pos": "PosPronoun", "sem": ["SemSelfReference"], "forms": ["мы", "нас", "нам", "нами"]},
    {"lemma": "ты", "pos": "PosPronoun", "sem": ["SemUserReference"], "forms": ["ты", "тебе", "тебя", "тобой", "тобою"]},
    {"lemma": "вы", "pos": "PosPronoun", "sem": ["SemUserReference"], "forms": ["вы", "вас", "вам", "вами"]},
    {"lemma": "кто", "pos": "PosPronoun", "sem": ["SemIdentity"], "forms": ["кто", "кого", "кому", "кем", "ком"]},
    {"lemma": "что", "pos": "PosPronoun", "sem": ["SemIdentity"], "forms": ["что", "чего", "чему", "чем", "чем"]},
    {"lemma": "такой", "pos": "PosPronoun", "sem": ["SemIdentity"], "forms": ["такой", "такая", "такое", "такие", "такого", "такую"]},
    {"lemma": "логика", "pos": "PosNoun", "sem": ["SemMentalObject"], "forms": ["логика", "логики", "логике", "логику", "логикой"]},
    {"lemma": "смысл", "pos": "PosNoun", "sem": ["SemMentalObject", "SemContemplative"], "forms": ["смысл", "смысла", "смыслу", "смыслом", "смысле"]},
    {"lemma": "субъектность", "pos": "PosNoun", "sem": ["SemAbstractConcept", "SemContemplative"], "forms": ["субъектность", "субъектности", "субъектностью"]},
    {"lemma": "правда", "pos": "PosNoun", "sem": ["SemAbstractConcept", "SemContemplative"], "forms": ["правда", "правды", "правде", "правду", "правдой"]},
    {"lemma": "истина", "pos": "PosNoun", "sem": ["SemAbstractConcept", "SemContemplative"], "forms": ["истина", "истины", "истине", "истину", "истиной"]},
    {"lemma": "функция", "pos": "PosNoun", "sem": ["SemPurposeFunction"], "forms": ["функция", "функции", "функцию", "функцией"]},
    {"lemma": "дом", "pos": "PosNoun", "sem": ["SemPhysicalObject", "SemWorldObject", "SemContemplative"], "forms": ["дом", "дома", "дому", "домом", "доме"]},
    {"lemma": "стол", "pos": "PosNoun", "sem": ["SemPhysicalObject", "SemWorldObject"], "forms": ["стол", "стола", "столу", "столом", "столе", "столы"]},
    {"lemma": "небо", "pos": "PosNoun", "sem": ["SemWorldObject", "SemWorldPhenomenon"], "forms": ["небо", "неба", "небу", "небом", "небе"]},
    {"lemma": "осень", "pos": "PosNoun", "sem": ["SemWorldPhenomenon"], "forms": ["осень", "осени", "осенью"]},
    {"lemma": "думать", "pos": "PosVerb", "sem": ["SemAction"], "forms": ["думать", "думаю", "думаешь", "думает", "думаем", "думают"]},
    {"lemma": "купить", "pos": "PosVerb", "sem": ["SemAction"], "forms": ["купить", "купил", "купила", "купили", "куплю", "купишь", "купит"]},
    {"lemma": "жить", "pos": "PosVerb", "sem": ["SemAction"], "forms": ["жить", "живу", "живешь", "живет", "живем", "живете", "живут"]},
    {"lemma": "оказаться", "pos": "PosVerb", "sem": ["SemAction", "SemState"], "forms": ["оказаться", "оказался", "оказалась", "оказалось", "оказались", "оказывается"]},
    {"lemma": "делать", "pos": "PosVerb", "sem": ["SemAction"], "forms": ["делать", "делаю", "делаешь", "делает", "делаем", "делают"]},
    {"lemma": "сохранять", "pos": "PosVerb", "sem": ["SemAction"], "forms": ["сохранять", "сохраняю", "сохраняешь", "сохраняет", "сохраняем", "сохраняют"]},
    {"lemma": "скрываться", "pos": "PosVerb", "sem": ["SemAction"], "forms": ["скрываться", "скрывается", "скрываются"]},
    {"lemma": "поговорить", "pos": "PosVerb", "sem": ["SemDialogueInvitation", "SemAction"], "forms": ["поговорить", "поговорим", "поговорите"]},
    {"lemma": "обсудить", "pos": "PosVerb", "sem": ["SemDialogueInvitation", "SemAction"], "forms": ["обсудить", "обсудим", "обсудите"]},
    {"lemma": "быть", "pos": "PosVerb", "sem": ["SemIdentity", "SemState"], "forms": ["быть", "есть", "был", "была", "будет"]},
    {"lemma": "являться", "pos": "PosVerb", "sem": ["SemIdentity", "SemState"], "forms": ["являться", "являюсь", "являешься", "является"]},
    {"lemma": "нужный", "pos": "PosAdjective", "sem": ["SemPurposeFunction", "SemQualityProperty"], "forms": ["нужный", "нужная", "нужное", "нужные", "нужен", "нужна", "нужно", "нужны"]},
    {"lemma": "зачем", "pos": "PosAdverb", "sem": ["SemPurposeFunction"], "forms": ["зачем"]},
    {"lemma": "почему", "pos": "PosAdverb", "sem": ["SemCause"], "forms": ["почему"]},
    {"lemma": "грустно", "pos": "PosAdverb", "sem": ["SemState"], "forms": ["грустно"]},
    {"lemma": "голубой", "pos": "PosAdjective", "sem": ["SemQualityProperty"], "forms": ["голубой", "голубая", "голубое", "голубые", "голубого", "голубому"]},
    {"lemma": "где", "pos": "PosAdverb", "sem": ["SemUnknown"], "forms": ["где"]},
]


def ensure_dirs() -> None:
    os.makedirs(os.path.dirname(OUTPUT_LEXICON_JSON), exist_ok=True)
    os.makedirs(os.path.dirname(OUTPUT_COVERAGE), exist_ok=True)


def tokenize_text(text: str) -> list[str]:
    lowered = text.lower().replace("ё", "е")
    return TOKEN_RE.findall(lowered)


def is_valid_token(token: str) -> bool:
    if not token:
        return False
    if len(token) < 2 or len(token) > 32:
        return False
    if token.startswith("-") or token.endswith("-"):
        return False
    return True


def guess_pos(token: str) -> str:
    if token in PREPOSITIONS:
        return "PosPreposition"
    if token in CONJUNCTIONS:
        return "PosConjunction"
    if token in PARTICLES:
        return "PosParticle"
    if token in INTERJECTIONS:
        return "PosInterjection"
    if token in PRONOUNS:
        return "PosPronoun"
    if token in NUMERALS:
        return "PosNumeral"
    if token in WORLD_WORDS or token in MENTAL_WORDS or token in ABSTRACT_WORDS or token in PURPOSE_WORDS:
        return "PosNoun"
    if token in KNOWN_ADJECTIVES:
        return "PosAdjective"
    if token in ACTION_WORDS:
        return "PosVerb"
    if token.endswith(
        (
            "ть", "ти", "чь",
            "у", "ю", "ем", "ешь", "ет", "ете", "ют", "ут",
            "ил", "ила", "или", "ал", "ала", "али",
            "ался", "алась", "алось", "ались",
            "юсь", "ется", "утся", "ешься", "емся", "етесь",
        )
    ):
        return "PosVerb"
    if token.endswith(("ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие", "ого", "ому", "ыми", "ых")):
        return "PosAdjective"
    if token.endswith(("о", "е")):
        return "PosAdverb"
    return "PosNoun"


def guess_semantics(lemma: str, pos: str) -> list[str]:
    sem = []
    if lemma in WORLD_WORDS:
        sem.extend(["SemWorldObject"])
    if lemma in WORLD_PHENOMENA_WORDS:
        sem.extend(["SemWorldPhenomenon"])
    if lemma in {"стол", "дом", "камень"}:
        sem.extend(["SemPhysicalObject"])
    if lemma in MENTAL_WORDS:
        sem.extend(["SemMentalObject"])
    if lemma in ABSTRACT_WORDS:
        sem.extend(["SemAbstractConcept"])
    if lemma in PURPOSE_WORDS:
        sem.extend(["SemPurposeFunction"])
    if lemma in COMPARISON_WORDS:
        sem.extend(["SemComparison"])
        if lemma in {"разница", "отличие", "между"}:
            sem.extend(["SemRelation"])
    if lemma in CAUSE_WORDS:
        sem.extend(["SemCause"])
    if lemma in KNOWLEDGE_WORDS:
        sem.extend(["SemKnowledge"])
    if lemma in INVITATION_WORDS:
        sem.extend(["SemDialogueInvitation"])
    if lemma in REPAIR_WORDS:
        sem.extend(["SemDialogueRepair"])
    if lemma in CONTEMPLATIVE_WORDS:
        sem.extend(["SemContemplative"])
    if lemma in {"я", "мы"}:
        sem.extend(["SemSelfReference"])
    if lemma in {"ты", "вы"}:
        sem.extend(["SemUserReference"])
    if lemma in {"кто", "что", "такой", "быть", "являться"}:
        sem.extend(["SemIdentity"])
    if lemma in ACTION_WORDS and "SemAction" not in sem:
        sem.extend(["SemAction"])
    if pos == "PosVerb" and "SemAction" not in sem:
        sem.extend(["SemAction"])
    if pos in {"PosAdjective", "PosAdverb"} and "SemState" not in sem:
        sem.extend(["SemState"])
    if not sem:
        sem = ["SemUnknown"]
    return sorted(set(sem))


def maybe_promote(form: str, freq: int) -> bool:
    if not is_valid_token(form):
        return False
    if form in PREPOSITIONS or form in CONJUNCTIONS or form in PARTICLES:
        return False
    if freq < 3:
        return False
    return True


def read_research_input(path: str) -> Counter:
    counter = Counter()
    if not os.path.exists(path):
        return counter
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            for token in tokenize_text(line):
                counter[token] += 1
    return counter


def read_csv_input(path: str) -> Counter:
    counter = Counter()
    if not os.path.exists(path):
        return counter
    with open(path, "r", encoding="utf-8", errors="ignore", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            raw_text = row.get("raw_text", "")
            for token in tokenize_text(raw_text):
                counter[token] += 1
    return counter


def escape_hs_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def render_generated_haskell(form_to_lemma: dict[str, str], lemma_to_pos: dict[str, str], lemma_to_sem: dict[str, list[str]]) -> str:
    lines = [
        "{-# LANGUAGE OverloadedStrings #-}",
        "",
        "module QxFx0.Semantic.Input.GeneratedLexicon",
        "  ( generatedFormToLemma",
        "  , generatedLemmaToPos",
        "  , generatedLemmaToSem",
        "  ) where",
        "",
        "import Data.Text (Text)",
        "import QxFx0.Semantic.Input.Model (InputPartOfSpeech(..), InputSemanticClass(..))",
        "",
        "generatedFormToLemma :: Text -> Maybe Text",
        "generatedFormToLemma t = case t of",
    ]
    for form in sorted(form_to_lemma):
        lemma = form_to_lemma[form]
        lines.append(f'    "{escape_hs_string(form)}" -> Just "{escape_hs_string(lemma)}"')
    lines.append("    _ -> Nothing")
    lines.extend([
        "",
        "generatedLemmaToPos :: Text -> Maybe InputPartOfSpeech",
        "generatedLemmaToPos t = case t of",
    ])
    for lemma in sorted(lemma_to_pos):
        lines.append(f'    "{escape_hs_string(lemma)}" -> Just {lemma_to_pos[lemma]}')
    lines.append("    _ -> Nothing")
    lines.extend([
        "",
        "generatedLemmaToSem :: Text -> [InputSemanticClass]",
        "generatedLemmaToSem t = case t of",
    ])
    for lemma in sorted(lemma_to_sem):
        sem_values = ", ".join(lemma_to_sem[lemma])
        lines.append(f'    "{escape_hs_string(lemma)}" -> [{sem_values}]')
    lines.append("    _ -> []")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    input_txt = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_INPUT_TXT
    corpus_csv = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_CSV

    ensure_dirs()

    form_candidates: dict[str, Counter] = defaultdict(Counter)
    lemma_to_pos: dict[str, str] = {}
    lemma_to_sem: dict[str, set[str]] = defaultdict(set)
    seed_forms = 0

    for entry in BASE_LEXICON:
        lemma = entry["lemma"]
        pos = entry["pos"]
        sem_list = entry["sem"]
        lemma_to_pos[lemma] = pos
        for sem in sem_list:
            lemma_to_sem[lemma].add(sem)
        for form in entry["forms"]:
            canonical_lemma = CANONICAL_LEMMA_OVERRIDES.get(form, lemma)
            form_candidates[form][canonical_lemma] += 1000
            seed_forms += 1

    token_counts = read_research_input(input_txt)
    csv_counts = read_csv_input(corpus_csv)
    merged_counts = token_counts + csv_counts

    unknown_candidates = []
    for form, freq in merged_counts.most_common():
        if not maybe_promote(form, freq):
            continue
        if form not in form_candidates:
            unknown_candidates.append({"form": form, "frequency": freq})
        lemma = CANONICAL_LEMMA_OVERRIDES.get(form, form)
        form_candidates[form][lemma] += freq
        if lemma not in lemma_to_pos:
            lemma_to_pos[lemma] = guess_pos(lemma)
        for sem in guess_semantics(lemma, lemma_to_pos[lemma]):
            lemma_to_sem[lemma].add(sem)

    collisions = {}
    for form, options in form_candidates.items():
        if len(options) > 1:
            ranked = sorted(options.items(), key=lambda item: (-item[1], item[0]))
            collisions[form] = [{"lemma": lemma, "score": score} for lemma, score in ranked]

    form_to_lemma = {}
    for form, options in form_candidates.items():
        best_lemma = sorted(options.items(), key=lambda item: (-item[1], item[0]))[0][0]
        form_to_lemma[form] = best_lemma

    # Keep the generated module bounded for compile-time stability.
    if len(form_to_lemma) > 4000:
        seed_forms = {form for entry in BASE_LEXICON for form in entry["forms"]}
        scored_forms = sorted(
            (
                (max(options.values()), form)
                for form, options in form_candidates.items()
                if form in form_to_lemma
            ),
            key=lambda item: (-item[0], item[1]),
        )
        keep = set(form for form in seed_forms if form in form_to_lemma)
        for _score, form in scored_forms:
            if len(keep) >= 4000:
                break
            keep.add(form)
        form_to_lemma = {k: v for k, v in form_to_lemma.items() if k in keep}

    used_lemmas = sorted(set(form_to_lemma.values()))
    lemma_to_pos = {lemma: lemma_to_pos[lemma] for lemma in used_lemmas}
    lemma_to_sem_sorted = {lemma: sorted(lemma_to_sem[lemma]) for lemma in used_lemmas}

    with open(OUTPUT_LEXICON_JSON, "w", encoding="utf-8") as handle:
        json.dump(
            {
                "form_to_lemma": dict(sorted(form_to_lemma.items())),
                "lemma_to_pos": dict(sorted(lemma_to_pos.items())),
                "lemma_to_sem": dict(sorted(lemma_to_sem_sorted.items())),
                "meta": {
                    "seed_forms": seed_forms,
                    "input_txt_present": os.path.exists(input_txt),
                    "corpus_csv_present": os.path.exists(corpus_csv),
                },
            },
            handle,
            ensure_ascii=False,
            indent=2,
        )

    with open(OUTPUT_GENERATED_HS, "w", encoding="utf-8") as handle:
        handle.write(render_generated_haskell(form_to_lemma, lemma_to_pos, lemma_to_sem_sorted))

    pos_distribution = Counter(lemma_to_pos.values())
    sem_distribution = Counter()
    for sem_list in lemma_to_sem_sorted.values():
        for sem in sem_list:
            sem_distribution[sem] += 1

    with open(OUTPUT_COVERAGE, "w", encoding="utf-8") as handle:
        json.dump(
            {
                "total_forms": len(form_to_lemma),
                "total_lemmas": len(lemma_to_pos),
                "pos_distribution": dict(sorted(pos_distribution.items())),
                "sem_distribution": dict(sorted(sem_distribution.items())),
                "source_tokens": {
                    "research_input_txt": sum(token_counts.values()),
                    "school_parser_csv": sum(csv_counts.values()),
                },
            },
            handle,
            ensure_ascii=False,
            indent=2,
        )

    collision_items = sorted(collisions.items())
    with open(OUTPUT_COLLISIONS, "w", encoding="utf-8") as handle:
        json.dump(
            {
                "collisions": len(collision_items),
                "ambiguous_lemmas": sum(1 for _, values in collision_items if len(values) > 1),
                "samples": [{"form": form, "options": values[:4]} for form, values in collision_items[:150]],
            },
            handle,
            ensure_ascii=False,
            indent=2,
        )

    with open(OUTPUT_UNKNOWN, "w", encoding="utf-8") as handle:
        json.dump(
            {
                "unknown_candidates": unknown_candidates[:500],
                "total_unknown_candidates": len(unknown_candidates),
            },
            handle,
            ensure_ascii=False,
            indent=2,
        )

    print("Build script completed.")
    print(f"forms={len(form_to_lemma)} lemmas={len(lemma_to_pos)} collisions={len(collision_items)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
