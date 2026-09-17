#!/usr/bin/env python3
"""Lemma-mapper verb coverage (static replica, no runtime needed).

Replicates buildLemmaMap (Morphology.hs): lowercased unions of
nominative/genitive/prepositional + forms_by_surface surface->lemma.
Then, over all definitionCorpus RU predicate surfaces (Content.hs
prop/rel literals), tokenizes like Composition.parsePredicateTerm
and reports:

1. relationLexicon verbs: attested (>=1 corpus token lemmatizes to
   it) vs orphan (dead lexicon weight).
2. verb-POS corpus tokens (forms_by_surface pos == 'verb') that do
   NOT resolve to the lexicon: extension/mapping candidates, ranked
   by frequency.

Lexicon source of truth: src/QxFx0/Semantic/Composition.hs
(relationLexicon set). Corpus source: `prop "..."` / `rel "..."`
first literals in Content.hs entry blocks.
"""
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MORPH = ROOT / "resources" / "morphology"

PUNCT = '.,?!:;«»"()'


def build_lemma_map():
    """Exact replica of morphologyDataFromParadigms + buildLemmaMap:
    every (lemma, form) pair from paradigms.json + exceptions.json,
    lowercased surface -> lowercased lemma.  (The legacy
    forms_by_surface/nominative JSONs are NOT consulted by the
    runtime and are ignored here too.)"""
    lemma = {}
    verb_forms = {}  # surface -> (lemma, pos)
    for name in ("paradigms", "exceptions"):
        d = json.load(open(MORPH / f"{name}.json", encoding="utf-8"))
        for lem, entry in d.items():
            pos = str(entry.get("pos", "")).lower()
            for _key, surf in entry.get("forms", {}).items():
                surf_l, lem_l = str(surf).lower(), str(lem).lower()
                if not surf_l:
                    continue
                lemma.setdefault(surf_l, lem_l)
                verb_forms.setdefault(surf_l, (lem_l, pos))
    return lemma, verb_forms


def relation_lexicon():
    src = (ROOT / "src/QxFx0/Semantic/Composition.hs").read_text(
        encoding="utf-8")
    m = re.search(r"relationLexicon = S\.fromList\n(.*?)\n  \]", src,
                  re.DOTALL)
    return set(re.findall(r'"([^"]+)"', m.group(1)))


NEG = {"не", "ни", "нет", "без"}


def corpus_surfaces():
    src = (ROOT / "src/QxFx0/Semantic/Content.hs").read_text(
        encoding="utf-8")
    # prop "ru" "en" and rel "ru" "en": first literal is RU surface
    return re.findall(r'(?:prop|rel) "([^"]+)"\s*\n?\s*"', src)


def main():
    lemma, verb_forms = build_lemma_map()
    lexicon = relation_lexicon()
    surfaces = corpus_surfaces()
    print(f"lemma entries={len(lemma)} lexicon verbs={len(lexicon)} "
          f"corpus surfaces={len(surfaces)}")
    attested = Counter()
    missed = Counter()
    for surf in surfaces:
        for w in surf.lower().split():
            w = w.strip(PUNCT)
            if not w or w in NEG:
                continue
            lem = lemma.get(w, w)
            if lem in lexicon:
                attested[lem] += 1
            elif verb_forms.get(w, ("", ""))[1] == "verb":
                missed[(w, lem)] += 1
    print(f"\n-- attested lexicon verbs: {len(attested)}/{len(lexicon)}")
    for v, c in attested.most_common():
        print(f"  {v}: {c}")
    orphans = sorted(set(lexicon) - set(attested))
    print(f"\n-- orphan lexicon verbs ({len(orphans)}): "
          f"{', '.join(orphans)}")
    print(f"\n-- verb-POS tokens unmapped to lexicon "
          f"({len(missed)}), top 30:")
    for (w, lem), c in missed.most_common(30):
        print(f"  {w} -> {lem}: {c}")
    json.dump(
        {"attested": dict(attested), "orphans": orphans,
         "missed": [[w, lem, c] for (w, lem), c in
                    missed.most_common()]},
        open(ROOT / "data/calibration_corpus/verb_coverage.json",
             "w", encoding="utf-8"),
        ensure_ascii=False, indent=1)
    print("\nwrote data/calibration_corpus/verb_coverage.json")


if __name__ == "__main__":
    sys.exit(main())
