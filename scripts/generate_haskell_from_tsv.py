#!/usr/bin/env python3
"""Generate src/QxFx0/Lexicon/Generated.hs from lexicon_bilingual.tsv."""

import csv
import sys

CASE_MAP = {
    "nominative": ("NominativeCase", "nominative"),
    "genitive": ("GenitiveCase", "genitive"),
    "prepositional": ("PrepositionalCase", "prepositional"),
    "accusative": ("AccusativeCase", "accusative"),
    "instrumental": ("InstrumentalCase", "instrumental"),
}

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

def main():
    tsv_path = sys.argv[1] if len(sys.argv) > 1 else "spec/gf/lexicon_bilingual.tsv"
    out_path = sys.argv[2] if len(sys.argv) > 2 else "src/QxFx0/Lexicon/Generated.hs"

    ru_entries = []
    with open(tsv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row.get("lang") == "ru":
                ru_entries.append(row)

    # collect finite verb map (infinitive -> 1sg)
    finite_verbs = {}
    for row in ru_entries:
        if row.get("pos") == "verb":
            inf = row.get("lemma", "").strip()
            if inf:
                sg1, _ = rus_verb_forms(inf)
                finite_verbs[inf] = sg1
    # Hardcoded verbs from QxFx0SyntaxRus.gf not present in TSV
    for inf in ["критиковать", "держать", "возражать", "спрашивать"]:
        sg1, _ = rus_verb_forms(inf)
        finite_verbs[inf] = sg1

    with open(out_path, "w", encoding="utf-8") as f:
        f.write('{-# LANGUAGE OverloadedStrings #-}\n')
        f.write('module QxFx0.Lexicon.Generated\n')
        f.write('  ( generatedLexemeEntries\n')
        f.write('  , generatedCandidateForms\n')
        f.write('  , generatedFiniteVerbMap\n')
        f.write('  ) where\n\n')
        f.write('import qualified Data.Map.Strict as M\n')
        f.write('import Data.Text (Text)\n')
        f.write('import QxFx0.Types.Domain.Atoms\n')
        f.write('  ( LexemeForm(..)\n')
        f.write('  , LexemeCase(..)\n')
        f.write('  , LexemeNumber(..)\n')
        f.write('  , SourceTier(..)\n')
        f.write('  )\n\n')
        f.write('-- AUTO-GENERATED from lexicon_bilingual.tsv\n\n')

        # generatedLexemeEntries
        f.write('generatedLexemeEntries :: [(Text, Text, Text, Text)]\n')
        f.write('generatedLexemeEntries =\n  [\n')
        lines = []
        for row in ru_entries:
            lemma = row["lemma"]
            pos = row["pos"]
            for case_key, (case_const, case_tag) in CASE_MAP.items():
                form = row.get(case_key, "").strip()
                if form:
                    lines.append((lemma, pos, case_tag, f'    ("{form}", "{lemma}", "{pos}", "{case_tag}")'))
        lines.sort(key=lambda x: (x[0], x[1], x[2]))
        f.write(",\n".join(l[3] for l in lines))
        f.write('\n  ]\n\n')

        # generatedCandidateForms
        forms_by_surface = {}
        for row in ru_entries:
            lemma = row["lemma"]
            pos = row["pos"]
            for case_key, (case_const, _) in CASE_MAP.items():
                form = row.get(case_key, "").strip()
                if form:
                    lf = f'LexemeForm {{ lfSurface = "{form}" , lfLemma = "{lemma}" , lfPOS = "{pos}" , lfCase = {case_const} , lfNumber = SingularNumber , lfTier = CuratedTier , lfQuality = 0.98 }}'
                    forms_by_surface.setdefault(form, []).append(lf)

        f.write('generatedCandidateForms :: M.Map Text [LexemeForm]\n')
        f.write('generatedCandidateForms = M.fromList\n  [\n')
        blocks = []
        for surface in sorted(forms_by_surface.keys()):
            forms = forms_by_surface[surface]
            block = f'    ("{surface}",\n      [\n'
            block += ",\n".join(f"        {lf}" for lf in forms)
            block += '\n      ])'
            blocks.append(block)
        f.write(",\n".join(blocks))
        f.write('\n  ]\n\n')

        # generatedFiniteVerbMap
        f.write('generatedFiniteVerbMap :: M.Map Text Text\n')
        f.write('generatedFiniteVerbMap = M.fromList\n  [\n')
        fv_lines = [f'    ("{inf}", "{sg1}")' for inf, sg1 in sorted(finite_verbs.items())]
        f.write(",\n".join(fv_lines))
        f.write('\n  ]\n')

    print(f"Written {len(lines)} lexeme entries and {len(forms_by_surface)} surface forms and {len(finite_verbs)} finite verbs to {out_path}")

if __name__ == "__main__":
    main()
