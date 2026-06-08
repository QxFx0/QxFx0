#!/usr/bin/env python3
"""L3e-0 Baseline: candidate 20k parity vs funmap (classified G1–G5).

Compares data/raw/rgl_candidate_20k/paradigms_candidate_20k.json against
spec/gf/lexicon_funmap.tsv and classifies every discrepancy into G1–G5.

Usage:
    python3 scripts/l3e0_baseline_parity.py [--out docs/rgl-russian-migration-spec.md]
"""

import json
import csv
import sys
import os
from collections import defaultdict
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
CANDIDATE_PATH = PROJECT_ROOT / "data/raw/rgl_candidate_20k/paradigms_candidate_20k.json"
FUNMAP_PATH = PROJECT_ROOT / "spec/gf/lexicon_funmap.tsv"
SPEC_PATH = PROJECT_ROOT / "docs/rgl-russian-migration-spec.md"

G4_EMPTY_WHITELIST = {
    "авр", "априори", "арх", "вчера", "далеко",
    "диг", "завтра", "сегодня", "хорошо"
}


def normalize_yo(text: str) -> str:
    return text.replace("ё", "е").replace("Ё", "Е")


def load_candidate() -> dict:
    with open(CANDIDATE_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def load_funmap() -> list[dict]:
    """Load funmap TSV. Columns: fun, lemma, pos, nominative, genitive, prepositional, accusative, instrumental"""
    entries = []
    with open(FUNMAP_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            entries.append(row)
    return entries


def classify_funmap_entries(funmap_entries: list[dict], candidate: dict, existing_lemmas: set) -> dict:
    """Classify each funmap noun entry against candidate paradigms.
    
    Returns a dict with classification counts and details.
    """
    results = {
        "G1": [],      # ё/е normalization mismatches
        "G2": [],      # animacy disagreements
        "G4": [],      # empty/partial paradigms
        "G5_missing": [],  # funmap entries missing from candidate
        "G5_new": [],      # candidate lemmas not in existing production
        "OK": [],
    }
    
    for entry in funmap_entries:
        fun_id = entry["fun"]
        pos = entry.get("pos", "")
        if pos != "noun":
            continue
            
        lemma = entry["lemma"]
        nominative = entry["nominative"]
        genitive = entry["genitive"]
        prepositional = entry["prepositional"]
        accusative = entry["accusative"]
        instrumental = entry["instrumental"]
        
        json_forms = {
            "NomSg": nominative,
            "GenSg": genitive,
            "LocSg": prepositional,
            "AccSg": accusative,
            "InsSg": instrumental,
        }
        
        # Check if lemma exists in candidate
        if nominative not in candidate:
            results["G5_missing"].append((fun_id, nominative, "not in candidate"))
            continue
        
        pe = candidate[nominative]
        candidate_forms = pe.get("forms", {})
        form_count = len(candidate_forms)
        
        # G4: empty or partial paradigms
        if form_count == 0:
            if nominative in G4_EMPTY_WHITELIST:
                results["OK"].append((fun_id, nominative, "whitelisted empty"))
            else:
                results["G4"].append((fun_id, nominative, "empty paradigm (not whitelisted)"))
            continue
        
        if form_count < 12:
            results["G4"].append((fun_id, nominative, f"partial paradigm: {form_count}/12 forms"))
            continue
        
        # G1: ё/е normalization mismatches
        g1_mismatches = []
        for key in ["NomSg", "GenSg", "LocSg", "AccSg", "InsSg"]:
            json_val = json_forms.get(key, "")
            rgl_val = candidate_forms.get(key, "")
            if normalize_yo(json_val) != normalize_yo(rgl_val):
                g1_mismatches.append(f"{key}: json={json_val} rgl={rgl_val}")
        
        if g1_mismatches:
            results["G1"].append((fun_id, nominative, "; ".join(g1_mismatches)))
            continue
        
        # G2: animacy disagreements (Acc form)
        json_acc = json_forms["AccSg"]
        rgl_acc = candidate_forms.get("AccSg", "")
        if json_acc != rgl_acc and normalize_yo(json_acc) == normalize_yo(rgl_acc):
            animacy = pe.get("animacy", "unknown")
            results["G2"].append((fun_id, nominative, f"Acc animacy disagreement: json={json_acc} rgl={rgl_acc} animacy={animacy}"))
            continue
        
        # G5: new coverage (not in existing production)
        if nominative not in existing_lemmas:
            results["G5_new"].append((fun_id, nominative, "new coverage (not in existing prod)"))
            continue
        
        # All checks passed
        results["OK"].append((fun_id, nominative, ""))
    
    return results


def load_existing_lemmas() -> set:
    """Load lemmas from existing production paradigms.json."""
    existing_path = PROJECT_ROOT / "resources/morphology/paradigms.json"
    if not existing_path.exists():
        return set()
    with open(existing_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return set(data.keys())


def print_results(results: dict, total_nouns: int):
    """Print classified results in human-readable format."""
    g1_count = len(results["G1"])
    g2_count = len(results["G2"])
    g4_count = len(results["G4"])
    g5_missing_count = len(results["G5_missing"])
    g5_new_count = len(results["G5_new"])
    ok_count = len(results["OK"])
    total_mismatches = g1_count + g2_count + g4_count + g5_missing_count + g5_new_count
    
    print(f"L3e-0 candidate parity: {total_nouns} funmap nouns")
    print(f"  OK = {ok_count}")
    print(f"  G1 (ё/е) = {g1_count}")
    print(f"  G2 (animacy) = {g2_count}")
    print(f"  G4 (empty/partial) = {g4_count}")
    print(f"  G5_missing_from_funmap = {g5_missing_count}")
    print(f"  G5_new_coverage = {g5_new_count}")
    print(f"  TOTAL MISMATCHES (N) = {total_mismatches}")
    print()
    
    # Print first 20 mismatches per class
    for cls_name in ["G1", "G2", "G4", "G5_missing", "G5_new"]:
        items = results[cls_name]
        if items:
            print(f"  {cls_name} ({len(items)} items):")
            for fun_id, nom, detail in items[:20]:
                print(f"    {fun_id} ({nom}): {detail}")
            if len(items) > 20:
                print(f"    ... and {len(items) - 20} more")
            print()
    
    print(f"L3e-0 baseline N = {total_mismatches} (record in §7 of migration spec)")


def update_spec_section(results: dict, total_nouns: int):
    """Update §7 in the migration spec with measured L3e-0 results."""
    g1_count = len(results["G1"])
    g2_count = len(results["G2"])
    g4_count = len(results["G4"])
    g5_missing_count = len(results["G5_missing"])
    g5_new_count = len(results["G5_new"])
    ok_count = len(results["OK"])
    total_mismatches = g1_count + g2_count + g4_count + g5_missing_count + g5_new_count
    
    l3e0_table = f"""| L3e-0 | Baseline measure | N = {total_mismatches} | 2026-06-08 |
| G1 | ё/е normalization | {g1_count} | |
| G2 | animacy disagreements | {g2_count} | |
| G4 | empty/partial paradigms | {g4_count} | |
| G5_missing | funmap nouns not in candidate | {g5_missing_count} | |
| G5_new | candidate lemmas not in existing prod | {g5_new_count} | |
| OK | perfect matches | {ok_count} | |
| Total funmap nouns | | {total_nouns} | |"""
    
    if not SPEC_PATH.exists():
        print(f"Spec file not found at {SPEC_PATH}, skipping update")
        return
    
    content = SPEC_PATH.read_text(encoding="utf-8")
    
    # Look for the L3e-0 section and update it
    if "L3e-0 measured" in content:
        # Replace existing measurement
        lines = content.split("\n")
        new_lines = []
        in_table = False
        table_inserted = False
        for line in lines:
            if "L3e-0 measured" in line:
                in_table = True
                new_lines.append(line)
                new_lines.append(l3e0_table)
                table_inserted = True
                continue
            if in_table and line.startswith("|") and "Total funmap nouns" in line:
                in_table = False
                continue
            if not in_table:
                new_lines.append(line)
        if table_inserted:
            SPEC_PATH.write_text("\n".join(new_lines), encoding="utf-8")
            print(f"Updated {SPEC_PATH} with L3e-0 measurement")
    else:
        print(f"L3e-0 measured section not found in {SPEC_PATH}, appending")
        with open(SPEC_PATH, "a", encoding="utf-8") as f:
            f.write(f"\n\n### L3e-0 measured (2026-06-08)\n\n{l3e0_table}\n")
        print(f"Appended L3e-0 measurement to {SPEC_PATH}")


def main():
    print("L3e-0 Baseline: candidate 20k parity vs funmap")
    print("=" * 60)
    
    # Load data
    candidate = load_candidate()
    funmap_entries = load_funmap()
    existing_lemmas = load_existing_lemmas()
    
    # Filter to nouns only
    noun_entries = [e for e in funmap_entries if e.get("pos") == "noun"]
    total_nouns = len(noun_entries)
    
    print(f"Loaded {len(candidate)} candidate paradigms")
    print(f"Loaded {len(funmap_entries)} funmap entries ({total_nouns} nouns)")
    print(f"Existing production lemmas: {len(existing_lemmas)}")
    print()
    
    # Classify
    results = classify_funmap_entries(noun_entries, candidate, existing_lemmas)
    
    # Print results
    print_results(results, total_nouns)
    
    # Update spec
    update_spec_section(results, total_nouns)
    
    # Fork decision
    total_mismatches = (len(results["G1"]) + len(results["G2"]) + 
                       len(results["G4"]) + len(results["G5_missing"]) + 
                       len(results["G5_new"]))
    
    if total_mismatches > 500:
        print("\n⚠️  FORK: N > 500 — STOP and escalate to customer:")
        print("   Choice: integrate full 20K vs Layer A (14K frequency core) first")
        print("   See §7 fork 1 in migration spec")
    else:
        print(f"\n✓ N = {total_mismatches} ≤ 500 — proceed to L3e-1 (G1/G4 auto classes)")


if __name__ == "__main__":
    main()
