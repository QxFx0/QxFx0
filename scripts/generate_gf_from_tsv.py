#!/usr/bin/env python3
"""Generate GF abstract and concrete grammars from lexicon_bilingual.tsv."""

import csv
import sys
from collections import defaultdict

def guess_rus_gender(lemma):
    """Rudimentary gender heuristic for Russian nouns."""
    if lemma.endswith(("ость", "есть", "ость")):
        return "feminine"
    if lemma.endswith("мя"):
        return "neuter"
    if lemma.endswith(("а", "я")):
        return "feminine"
    if lemma.endswith(("о", "е")):
        return "neuter"
    return "masculine"

def rus_verb_forms(infinitive):
    """Return (1sg, 3sg) present for common Russian verbs."""
    known = {
        "знать": ("знаю", "знает"),
        "думать": ("думаю", "думает"),
        "понимать": ("понимаю", "понимает"),
        "мыслить": ("мыслю", "мыслит"),
        "сказать": ("скажу", "скажет"),
        "делать": ("делаю", "делает"),
        "основывать": ("основываю", "основывает"),
        "проникнуть": ("проникну", "проникнет"),
        "различать": ("различаю", "различает"),
        "существовать": ("существую", "существует"),
        "уточнять": ("уточняю", "уточняет"),
        "чувствовать": ("чувствую", "чувствует"),
        "доказывать": ("доказываю", "доказывает"),
        "изменять": ("изменяю", "изменяет"),
        "использовать": ("использую", "использует"),
        "исследовать": ("исследую", "исследует"),
        "наблюдать": ("наблюдаю", "наблюдает"),
        "общаться": ("общаюсь", "общается"),
        "познавать": ("познаю", "познает"),
        "развивать": ("развиваю", "развивает"),
        "сознавать": ("сознаю", "сознает"),
        "воспринимать": ("воспринимаю", "воспринимает"),
        "выделять": ("выделяю", "выделяет"),
        "выражать": ("выражаю", "выражает"),
        "критиковать": ("критикую", "критикует"),
        "держать": ("держу", "держит"),
        "возражать": ("возражаю", "возражает"),
        "спрашивать": ("спрашиваю", "спрашивает"),
    }
    return known.get(infinitive, (infinitive, infinitive + "ет"))

def generate_abstract(entries, output_path):
    """Generate QxFx0Lexicon.gf"""
    funs = defaultdict(set)
    for entry in entries:
        funs[entry['pos']].add(entry['fun_id'])

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write("-- Auto-generated from lexicon_bilingual.tsv\n")
        f.write("abstract QxFx0Lexicon = {\n")
        f.write("  flags startcat = Lexeme ;\n")
        f.write("  cat\n")
        f.write("    Lexeme ;\n")
        f.write("    NounLexeme ;\n")
        f.write("    VerbLexeme ;\n")
        f.write("    AdjLexeme ;\n")
        f.write("    AdvLexeme ;\n")
        f.write("    PrepLexeme ;\n")
        f.write("    ConjLexeme ;\n")
        f.write("    DetLexeme ;\n")
        f.write("  fun\n")
        for pos in ['noun', 'verb', 'adj', 'adv', 'prep', 'conj', 'det']:
            cat = f"{pos.capitalize()}Lexeme"
            for fun_id in sorted(funs.get(pos, [])):
                f.write(f"    {fun_id} : {cat} ;\n")
        # Hardcoded determiners (closed-class, not in TSV)
        f.write("    EveryDet : DetLexeme ;\n")
        f.write("    SomeDet : DetLexeme ;\n")
        f.write("    FewDet : DetLexeme ;\n")
        f.write("    ManyDet : DetLexeme ;\n")
        f.write("}\n")

def generate_concrete(entries, lang, output_path):
    """Generate QxFx0Lexicon{Lang}.gf"""
    lang_entries = [e for e in entries if e['lang'] == lang]
    paradigms = "ParadigmsRus" if lang == "ru" else "ParadigmsEng"
    cats = "CatRus" if lang == "ru" else "CatEng"
    struct = "StructuralRus" if lang == "ru" else "StructuralEng"
    mod_suffix = "Rus" if lang == "ru" else "Eng"

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(f"-- Auto-generated from lexicon_bilingual.tsv\n")
        f.write(f"concrete QxFx0Lexicon{mod_suffix} of QxFx0Lexicon = open {paradigms}, {cats}, {struct} in {{\n")
        f.write(f"  lincat\n")
        f.write(f"    Lexeme = N ;\n")
        f.write(f"    NounLexeme = N ;\n")
        f.write(f"    VerbLexeme = V ;\n")
        f.write(f"    AdjLexeme = A ;\n")
        f.write(f"    AdvLexeme = Adv ;\n")
        f.write(f"    PrepLexeme = Prep ;\n")
        f.write(f"    ConjLexeme = Conj ;\n")
        f.write(f"    DetLexeme = Det ;\n")
        f.write(f"  lin\n")

        for entry in lang_entries:
            pos = entry['pos']
            fun_id = entry['fun_id']
            lemma = entry['lemma']

            if pos == 'noun':
                if lang == 'ru':
                    gender = guess_rus_gender(lemma)
                    f.write(f'    {fun_id} = mkN "{lemma}" {gender} inanimate ;\n')
                else:
                    f.write(f'    {fun_id} = mkN "{lemma}" ;\n')
            elif pos == 'verb':
                if lang == 'ru':
                    sg1, sg3 = rus_verb_forms(lemma)
                    f.write(f'    -- explicit forms: {lemma} {sg1} {sg3}\n')
                    f.write(f'    {fun_id} = mkV "{lemma}" "{sg1}" "{sg3}" ;\n')
                else:
                    f.write(f'    {fun_id} = mkV "{lemma}" ;\n')
            elif pos == 'adj':
                f.write(f'    {fun_id} = mkA "{lemma}" ;\n')
            elif pos == 'adv':
                f.write(f'    {fun_id} = mkAdv "{lemma}" ;\n')
            elif pos == 'prep':
                if lang == 'ru':
                    f.write(f'    {fun_id} = mkPrep "{lemma}" prepositional ;\n')
                else:
                    f.write(f'    {fun_id} = mkPrep "{lemma}" ;\n')
            elif pos == 'conj':
                if lang == 'ru':
                    f.write(f'    {fun_id} = mkConj "{lemma}" singular ;\n')
                else:
                    f.write(f'    {fun_id} = mkConj "{lemma}" ;\n')

        # Hardcoded determiners (not present in TSV)
        if lang == 'ru':
            f.write("    EveryDet = every_Det ;\n")
            f.write("    SomeDet = someSg_Det ;\n")
            f.write("    FewDet = few_Det ;\n")
            f.write("    ManyDet = many_Det ;\n")
        else:
            f.write("    EveryDet = every_Det ;\n")
            f.write("    SomeDet = someSg_Det ;\n")
            f.write("    FewDet = few_Det ;\n")
            f.write("    ManyDet = many_Det ;\n")

        f.write("}\n")

def main():
    tsv_path = sys.argv[1] if len(sys.argv) > 1 else "spec/gf/lexicon_bilingual.tsv"
    entries = []
    with open(tsv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            entries.append(row)

    generate_abstract(entries, "spec/gf/QxFx0Lexicon.gf")
    generate_concrete(entries, "ru", "spec/gf/QxFx0LexiconRus.gf")
    generate_concrete(entries, "en", "spec/gf/QxFx0LexiconEng.gf")

    print(f"Generated GF files from {len(entries)} entries")

if __name__ == "__main__":
    main()
