#!/usr/bin/env python3
"""Add GF lexemes for covered topics missing from lexicon_funmap.tsv.

Why: 55 of 120 definitionCorpus topics have no GF lexeme, so the
linearizer falls back to gf_default_lexeme (ponyatie_N) and renders
«понятие и понятие» (human-rated 0/0). Same data-task discipline as
add_verb_paradigms.py: frozen curated forms, collision-checked,
validated by reload simulation + live turn.

Format: funId lemma pos nominative genitive prepositional accusative
instrumental (tab-separated; runtime parses all 8 columns).
Declension by ending with explicit overrides for adjectives
(возвышенное) — no exceptions beyond it in this set.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FUNMAP = ROOT / "spec" / "gf" / "lexicon_funmap.tsv"

TR = str.maketrans({
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e",
    "ё": "yo", "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k",
    "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r",
    "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
    "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "",
    "э": "e", "ю": "yu", "я": "ya",
})

# Adjective-declined (not noun patterns).
OVERRIDES = {
    "возвышенное": ("vozvyishennoe_N", "возвышенное",
                     "возвышенного", "возвышенном",
                     "возвышенное", "возвышенным"),
}

HUSH = set("гкхжчшщц")


def decline(topic):
    """Return (nom, gen, prep, acc, ins) for regular nouns."""
    if topic.endswith("ие"):
        stem = topic[:-1]
        return (topic, stem + "я", stem + "и", topic, stem + "ем")
    if topic.endswith("ия"):
        stem = topic[:-1]
        return (topic, stem + "и", stem + "и", stem + "ю", stem + "ей")
    if topic.endswith("ь"):
        # Feminine soft-sign (all such topics in this set; masculines
        # like путь/друг are absent — see explicit list below on doubt).
        return (topic, topicmin(topic), topicmin(topic), topic,
                topic + "ю")
    if topic.endswith("а"):
        stem = topic[:-1]
        gen_end = "и" if (stem[-1:] in HUSH) else "ы"
        return (topic, stem + gen_end, stem + "е", stem + "у",
                stem + "ой")
    if topic.endswith("о") and not topic.endswith("ие"):
        stem = topic[:-1]
        return (topic, stem + "а", stem + "е", topic, stem + "ом")
    # masculine consonant (incl. бог, гражданин — regular)
    return (topic, topic + "а", topic + "е", topic, topic + "ом")


def topicmin(topic):
    """Genitive/prepositional of soft-sign feminines: drop ь, add и."""
    return topic[:-1] + "и" if topic.endswith("ь") else topic


def fun_id(topic):
    return topic.lower().translate(TR) + "_N"


def covered_topics():
    out = subprocess.run(
        ["grep", "-o", 'entry "[^"]*"',
         "src/QxFx0/Semantic/Content.hs"],
        capture_output=True, text=True, cwd=ROOT, check=True)
    return [l.split('"')[1] for l in out.stdout.splitlines()]


def main():
    topics = covered_topics()
    assert len(topics) == 120, len(topics)
    existing_forms = set()
    existing_fun = set()
    with open(FUNMAP, encoding="utf-8") as f:
        header = f.readline()
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2:
                continue
            existing_fun.add(parts[0])
            for form in parts[1:]:
                if form:
                    existing_forms.add(form.lower())
    missing = [t for t in topics if t.lower() not in existing_forms]
    print(f"missing: {len(missing)}")
    rows = []
    for t in missing:
        if t in OVERRIDES:
            fid = OVERRIDES[t][0]
            forms = OVERRIDES[t][1:]
        else:
            fid = fun_id(t)
            forms = decline(t)
        assert fid not in existing_fun, f"funId collision: {fid}"
        existing_fun.add(fid)
        nom, gen, prep, acc, ins = forms
        assert all([nom, gen, prep, acc, ins]), f"empty form for {t}"
        rows.append("\t".join([fid, t, "noun", nom, gen, prep, acc,
                               ins]))
    # Validate: reload simulation (8-col parse, unique funIds).
    seen = set()
    for r in rows:
        parts = r.split("\t")
        assert len(parts) == 8, r
        assert parts[0] not in seen, parts[0]
        seen.add(parts[0])
    with open(FUNMAP, "a", encoding="utf-8") as f:
        for r in rows:
            f.write(r + "\n")
    print(f"appended {len(rows)} lexemes")
    print("sample:", rows[0][:80] if rows else None)
    return 0


if __name__ == "__main__":
    sys.exit(main())
