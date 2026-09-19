#!/usr/bin/env python3
"""Append GF grammar entries for the 55 gap-closure lexemes.

Reads funIds + RU forms from spec/gf/lexicon_funmap.tsv (source of
truth — must match byte-for-byte, else the shim map and the compiled
grammar diverge). Appends:
- abstract (QxFx0Lexicon.gf): `fun X_N : Lexeme ;`
- Russian concrete: full case record.
- English concrete: `mkN "gloss"` (glosses below, reviewed).
Then recompile via scripts/compile_gf_grammar.sh (separate step).
Idempotent: skips funIds already present in each file.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TSV = ROOT / "spec" / "gf" / "lexicon_funmap.tsv"

ENG = {
    "произвол": "arbitrariness", "мнение": "opinion",
    "воспоминание": "recollection", "самосознание": "self-awareness",
    "красота": "beauty", "история": "history", "труд": "labour",
    "власть": "power", "сущность": "essence", "форма": "form",
    "пространство": "space", "конечность": "finitude",
    "бесконечность": "infinity", "единство": "unity",
    "многообразие": "diversity", "знание": "knowledge",
    "опыт": "experience", "нравственность": "morality",
    "равенство": "equality", "мысль": "thought",
    "воображение": "imagination", "внимание": "attention",
    "желание": "desire", "чувство": "feeling", "искусство": "art",
    "вкус": "taste", "гармония": "harmony", "трагедия": "tragedy",
    "возвышенное": "the sublime", "гражданин": "citizen",
    "общество": "society", "наука": "science",
    "эмпиризм": "empiricism", "рационализм": "rationalism",
    "общение": "communication", "сотрудничество": "cooperation",
    "взаимопонимание": "mutual understanding", "знак": "sign",
    "символ": "symbol", "текст": "text", "мужество": "courage",
    "аутентичность": "authenticity", "забота": "care",
    "трансценденция": "transcendence", "святость": "holiness",
    "бог": "god", "религия": "religion", "молитва": "prayer",
    "рутина": "routine", "мудрость": "wisdom",
    "удивление": "surprise", "любопытство": "curiosity",
    "творчество": "creativity", "насилие": "violence",
    "культура": "culture",
}

MARK = "-- 2026-09-20 covered-topics gap closure (55 lexemes)."


def load_new():
    """Rows appended by add_gf_lexemes.py: funId -> (lemma, forms)."""
    rows = {}
    with open(TSV, encoding="utf-8") as f:
        next(f)
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) == 8 and p[1] in ENG:
                rows[p[0]] = (p[1], p[3], p[4], p[5], p[6], p[7])
    return rows


def append_block(path, lines):
    text = open(path, encoding="utf-8").read()
    assert text.rstrip().endswith("}"), path
    assert MARK not in text, f"block already present in {path}"
    idx = text.rstrip().rfind("}")
    new = (text[:idx].rstrip() + "\n" + MARK + "\n"
           + "\n".join("    " + ln for ln in lines) + "\n}\n")
    open(path, "w", encoding="utf-8").write(new)


def main():
    rows = load_new()
    missing_gloss = [t for t in
                     set(r[0] for r in rows.values()) if t not in ENG]
    assert not missing_gloss, missing_gloss
    print(f"new lexemes: {len(rows)}")
    assert len(rows) == 55, len(rows)
    abs_lines = [f"{fid} : Lexeme ;" for fid in sorted(rows)]
    rus_lines = [
        f"{fid} = {{ nom = \"{nom}\" ; gen = \"{gen}\" ; "
        f"prep = \"{prep}\" ; acc = \"{acc}\" ; ins = \"{ins}\" }} ;"
        for fid, (_lem, nom, gen, prep, acc, ins) in sorted(rows.items())]
    eng_lines = [
        f"{fid} = mkN \"{ENG[lem]}\" ;"
        for fid, (lem, *_rest) in sorted(rows.items())]
    append_block(ROOT / "spec/gf/QxFx0Lexicon.gf", abs_lines)
    append_block(ROOT / "spec/gf/QxFx0LexiconRus.gf", rus_lines)
    append_block(ROOT / "spec/gf/QxFx0LexiconEng.gf", eng_lines)
    print("appended to abstract/Rus/Eng")
    return 0


if __name__ == "__main__":
    sys.exit(main())
