#!/usr/bin/env python3
"""Cross-validate paradigms.json and exceptions.json against pymorphy2/pymorphy3 inflection.

Usage:
    python3 scripts/validate_paradigms.py [--sample N] [--verbose]

Reports mismatches between our paradigms.json / exceptions.json and pymorphy3-generated forms.
A mismatch does NOT necessarily mean the paradigm is wrong — our dictionary
may contain more nuanced forms than pymorphy3's heuristics produce.
"""
import argparse
import json
import sys

try:
    import pymorphy3 as pymorphy
except ImportError:
    import pymorphy2 as pymorphy

CASE_MAP = {
    "nomn": "Nom",
    "gent": "Gen",
    "datv": "Dat",
    "accs": "Acc",
    "ablt": "Ins",
    "loct": "Loc",
}
NUM_MAP = {"sing": "Sg", "plur": "Pl"}
GEND_MAP = {"masc": "Masc", "femn": "Fem", "neut": "Neut"}

# Verb mood/number/person tags used by pymorphy
VERB_PRES = {
    ("1sg", "Pres1Sg"): {"1per", "sing"},
    ("2sg", "Pres2Sg"): {"2per", "sing"},
    ("3sg", "Pres3Sg"): {"3per", "sing"},
    ("1pl", "Pres1Pl"): {"1per", "plur"},
    ("2pl", "Pres2Pl"): {"2per", "plur"},
    ("3pl", "Pres3Pl"): {"3per", "plur"},
}
VERB_PAST = {
    ("masc", "PastSgMasc"): {"masc", "past"},
    ("fem", "PastSgFem"): {"femn", "past"},
    ("neut", "PastSgNeut"): {"neut", "past"},
    ("pl", "PastPl"): {"plur", "past"},
}
VERB_FUT = {
    ("1sg", "Fut1Sg"): {"1per", "sing"},
    ("2sg", "Fut2Sg"): {"2per", "sing"},
    ("3sg", "Fut3Sg"): {"3per", "sing"},
    ("1pl", "Fut1Pl"): {"1per", "plur"},
    ("2pl", "Fut2Pl"): {"2per", "plur"},
    ("3pl", "Fut3Pl"): {"3per", "plur"},
}
VERB_IMP = {
    ("sg", "ImpSg"): {"sing"},
    ("pl", "ImpPl"): {"plur"},
}


def inflect_noun(morph, lemma):
    """Inflect a noun into all 12 case/number combinations via pymorphy."""
    parsed = morph.parse(lemma)
    if not parsed:
        return None
    p = parsed[0]
    if "NOUN" not in p.tag:
        return None
    results = {}
    for case_tag, case_key in CASE_MAP.items():
        for num_tag, num_key in NUM_MAP.items():
            try:
                forms = p.inflect({case_tag, num_tag})
                if forms:
                    results[f"{case_key}{num_key}"] = forms.word
            except Exception:
                pass
    return results


def inflect_adj(morph, lemma):
    """Inflect an adjective into all case/number/gender combinations + short forms."""
    parsed = morph.parse(lemma)
    if not parsed:
        return None
    p = parsed[0]
    if "ADJF" not in p.tag and "ADJS" not in p.tag:
        return None
    results = {}
    for case_tag, case_key in CASE_MAP.items():
        for num_tag, num_key in NUM_MAP.items():
            for gend_tag, gend_key in GEND_MAP.items():
                if num_key == "Pl" and gend_key != "Masc":
                    continue  # plural has no gender in our paradigm keys
                key = f"{case_key}{num_key}{gend_key}" if num_key == "Sg" else f"{case_key}{num_key}"
                # For paradigm consistency we only store Sg with gender, Pl without
                actual_key = f"{case_key}{num_key}{gend_key}" if num_key == "Sg" else f"{case_key}{num_key}"
                try:
                    tags = {case_tag, num_tag}
                    if num_key == "Sg":
                        tags.add(gend_tag)
                    forms = p.inflect(tags)
                    if forms:
                        results[actual_key] = forms.word
                except Exception:
                    pass
    # Short forms (ADJS)
    for gend_tag, gend_key in GEND_MAP.items():
        try:
            forms = p.inflect({gend_tag, "sing", "adjs"})
            if forms:
                results[f"Short{gend_key}"] = forms.word
        except Exception:
            pass
    try:
        forms = p.inflect({"plur", "adjs"})
        if forms:
            results["ShortPl"] = forms.word
    except Exception:
        pass
    return results


def inflect_verb(morph, lemma):
    """Inflect a verb: infinitive, past, present/future, imperative."""
    parsed = morph.parse(lemma)
    if not parsed:
        return None
    p = parsed[0]
    if "VERB" not in p.tag and "INFN" not in p.tag:
        return None
    results = {"Inf": p.normal_form}
    # Past
    for _, tags in VERB_PAST.items():
        try:
            forms = p.inflect(tags)
            if forms:
                results[list(VERB_PAST.values())[list(VERB_PAST.values()).index(tags)]] = forms.word
        except Exception:
            pass
    # Present / Future depends on aspect; we try both
    for _, tags in VERB_PRES.items():
        try:
            forms = p.inflect(tags)
            if forms:
                # Map to the right key by index
                idx = list(VERB_PRES.values()).index(tags)
                key = list(VERB_PRES.keys())[idx][1]
                results[key] = forms.word
        except Exception:
            pass
    for _, tags in VERB_FUT.items():
        try:
            forms = p.inflect(tags)
            if forms:
                idx = list(VERB_FUT.values()).index(tags)
                key = list(VERB_FUT.keys())[idx][1]
                # Only store if not already present (present takes precedence for imperfective)
                if key not in results:
                    results[key] = forms.word
        except Exception:
            pass
    # Imperative
    for _, tags in VERB_IMP.items():
        try:
            forms = p.inflect(tags | {"impr"})
            if forms:
                idx = list(VERB_IMP.values()).index(tags)
                key = list(VERB_IMP.keys())[idx][1]
                results[key] = forms.word
        except Exception:
            pass
    return results


def inflect_adv(morph, lemma):
    """Adverbs are invariable in Russian; just verify parsing."""
    parsed = morph.parse(lemma)
    if not parsed:
        return None
    p = parsed[0]
    if "ADVB" not in p.tag:
        return None
    return {"Base": lemma}


def validate_entry(morph, lemma, entry, pos_filter, verbose):
    pos = entry.get("pos", "")
    if pos_filter and pos not in pos_filter:
        return 0, 0, 0
    our_forms = entry.get("forms", {})
    pm_forms = None
    if pos == "Noun":
        pm_forms = inflect_noun(morph, lemma)
    elif pos == "Adjective":
        pm_forms = inflect_adj(morph, lemma)
    elif pos == "Verb":
        pm_forms = inflect_verb(morph, lemma)
    elif pos == "Adverb":
        pm_forms = inflect_adv(morph, lemma)
    if pm_forms is None:
        if verbose:
            print(f"[MISS] {lemma} ({pos}): pymorphy could not parse")
        return 1, 0, 0
    mismatches = 0
    for key, our_form in our_forms.items():
        if not our_form:
            continue  # empty slots are OK (e.g., no present for perfective verbs)
        pm_form = pm_forms.get(key)
        if pm_form is None:
            continue
        if our_form != pm_form:
            mismatches += 1
            if verbose:
                print(f"[MISM] {lemma} {key}: ours={our_form} pymorphy={pm_form}")
    checked = len([k for k, v in our_forms.items() if v])
    return 0, checked, mismatches


def validate_file(path, morph, args):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    missing = 0
    checked = 0
    mismatches = 0
    items = list(data.items())
    if args.sample:
        import random
        random.seed(42)
        items = random.sample(items, min(args.sample, len(items)))
    for lemma, entry in items:
        miss, chk, mism = validate_entry(morph, lemma, entry, args.pos, args.verbose)
        missing += miss
        checked += chk
        mismatches += mism
    return missing, checked, mismatches


def main():
    parser = argparse.ArgumentParser(description="Validate paradigms and exceptions against pymorphy3")
    parser.add_argument("--sample", type=int, default=None, help="Sample size")
    parser.add_argument("--verbose", action="store_true", help="Print every mismatch")
    parser.add_argument("--pos", nargs="+", default=None, help="Filter by POS (Noun, Verb, Adjective, Adverb)")
    args = parser.parse_args()

    morph = pymorphy.MorphAnalyzer()
    total_missing = 0
    total_checked = 0
    total_mismatches = 0

    for path in ("resources/morphology/paradigms.json", "resources/morphology/exceptions.json"):
        miss, chk, mism = validate_file(path, morph, args)
        total_missing += miss
        total_checked += chk
        total_mismatches += mism

    print(f"Checked forms: {total_checked}")
    print(f"Missing from pymorphy: {total_missing}")
    print(f"Mismatches: {total_mismatches}")
    if total_checked > 0:
        print(f"Mismatch rate: {total_mismatches / total_checked:.2%}")
    return 0 if total_mismatches < total_checked else 1


if __name__ == "__main__":
    sys.exit(main())
