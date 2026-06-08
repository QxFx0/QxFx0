#!/usr/bin/env python3
"""Generate parity_report.md for the 20k candidate paradigms.

Compares data/raw/rgl_candidate_20k/paradigms_candidate_20k.json against
spec/gf/lexicon_funmap.tsv and the existing resources/morphology/paradigms.json.
"""
from __future__ import annotations

import csv
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE_PATH = ROOT / "data" / "raw" / "rgl_candidate_20k" / "paradigms_candidate_20k.json"
FUNMAP_PATH = ROOT / "spec" / "gf" / "lexicon_funmap.tsv"
EXISTING_PATH = ROOT / "resources" / "morphology" / "paradigms.json"
REPORT_PATH = ROOT / "data" / "raw" / "rgl_candidate_20k" / "parity_report.md"

CASES = ["Nom", "Gen", "Dat", "Acc", "Ins", "Loc"]
NUMBERS = ["Sg", "Pl"]
ALL_KEYS = {f"{c}{n}" for c in CASES for n in NUMBERS}


def load_funmap() -> set[str]:
    nouns = set()
    with FUNMAP_PATH.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row.get("pos") == "noun":
                nouns.add(row["nominative"])
    return nouns


def load_paradigms(path: Path) -> dict[str, dict]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def classify_discrepancy(lemma: str, candidate: dict, existing: dict | None) -> str:
    """Classify discrepancy between candidate and existing paradigm."""
    cforms = candidate.get("forms", {})
    if not cforms:
        return "G4 (empty paradigm — no inflectable forms)"
    if existing is None:
        return "G5 (not in existing JSON — new coverage)"
    eforms = existing.get("forms", {})
    # G1: yo normalization
    has_yo = any("ё" in v for v in cforms.values())
    if has_yo:
        return "G1 (yo not normalized — forms contain ё)"
    # G2/G3: gender or animacy mismatch
    if candidate.get("gender") != existing.get("gender"):
        return "G3 (gender mismatch)"
    if candidate.get("animacy") != existing.get("animacy"):
        return "G2 (animacy mismatch)"
    # G4: missing forms
    ckeys = set(cforms.keys())
    ekeys = set(eforms.keys())
    if ckeys != ekeys:
        missing = ekeys - ckeys
        extra = ckeys - ekeys
        if missing:
            return f"G4 (missing forms: {sorted(missing)})"
        if extra:
            return f"G4 (extra forms: {sorted(extra)})"
    # Form value mismatches (not one of G1-G5)
    mismatches = []
    for k in sorted(ckeys & ekeys):
        if cforms[k] != eforms[k]:
            mismatches.append(k)
    if mismatches:
        return f"G1-adjacent (form value mismatch: {mismatches[:5]}{'...' if len(mismatches) > 5 else ''})"
    return "OK"


def main() -> int:
    funmap = load_funmap()
    candidate = load_paradigms(CANDIDATE_PATH)
    existing = load_paradigms(EXISTING_PATH)

    present = funmap & set(candidate.keys())
    missing = funmap - set(candidate.keys())

    # Full-candidate stats (all 20k)
    all_empty = [k for k, v in candidate.items() if not v["forms"]]
    all_partial = [k for k, v in candidate.items() if 0 < len(v["forms"]) < 12]

    stats = {
        "funmap_total": len(funmap),
        "candidate_total": len(candidate),
        "existing_total": len(existing),
        "funmap_present": len(present),
        "funmap_missing": len(missing),
        "funmap_superset": len(missing) == 0,
        "g1": 0,
        "g2": 0,
        "g3": 0,
        "g4": 0,
        "g5": 0,
        "ok": 0,
        "verbal_noun_count": 0,
        "verbal_noun_in_candidate": 0,
        "empty_paradigms": 0,
        "partial_paradigms": 0,
    }

    discrepancies: list[tuple[str, str]] = []
    for lemma in sorted(funmap):
        cand = candidate.get(lemma)
        ex = existing.get(lemma)
        if cand is None:
            stats["g5"] += 1
            discrepancies.append((lemma, "G5 (missing from candidate entirely)"))
            continue
        d = classify_discrepancy(lemma, cand, ex)
        if d.startswith("G1"):
            stats["g1"] += 1
        elif d.startswith("G2"):
            stats["g2"] += 1
        elif d.startswith("G3"):
            stats["g3"] += 1
        elif d.startswith("G4"):
            stats["g4"] += 1
            if "empty paradigm" in d:
                stats["empty_paradigms"] += 1
            else:
                stats["partial_paradigms"] += 1
        elif d.startswith("G5"):
            stats["g5"] += 1
        elif d == "OK":
            stats["ok"] += 1
        else:
            stats["g1"] += 1  # G1-adjacent
        discrepancies.append((lemma, d))

    # Verbal nouns (funmap subset)
    verbal_nouns_funmap = [l for l in funmap if l.endswith(("ние", "нье", "ение", "ение"))]
    stats["verbal_noun_count"] = len(verbal_nouns_funmap)
    stats["verbal_noun_in_candidate"] = sum(1 for l in verbal_nouns_funmap if l in candidate)

    # Full 20k verbal nouns with InsSg breakdown
    all_verbal_nouns = [k for k in candidate.keys() if k.endswith(("ние", "нье", "ение", "ение"))]
    niem_list = []
    niem_other_list = []
    for w in all_verbal_nouns:
        forms = candidate[w]["forms"]
        if "InsSg" in forms:
            ins = forms["InsSg"]
            if ins.endswith("нием"):
                niem_list.append((w, ins))
            else:
                niem_other_list.append((w, ins))
        else:
            niem_other_list.append((w, "NO InsSg"))

    # Full 20k predicted G-class examples
    g1_full = []
    g2_full = []
    g3_full = []
    g4_empty_full = list(all_empty)
    g4_partial_full = list(all_partial)
    g5_full = []

    for k, v in candidate.items():
        # G1
        if any("ё" in val for val in v["forms"].values()):
            g1_full.append(k)
        # G2/G3/G5 only if in existing
        if k in existing:
            if v.get("animacy") != existing[k].get("animacy"):
                g2_full.append(k)
            if v.get("gender") != existing[k].get("gender"):
                g3_full.append(k)
        else:
            g5_full.append(k)

    lines = []
    lines.append("# RGL Candidate 20k Parity Report\n")
    lines.append(f"**Date:** 2026-06-08\n")
    lines.append(f"**Candidate:** `data/raw/rgl_candidate_20k/paradigms_candidate_20k.json` ({stats['candidate_total']:,} paradigms)\n")
    lines.append(f"**Existing:** `resources/morphology/paradigms.json` ({stats['existing_total']:,} paradigms)\n")
    lines.append(f"**Funmap:** `spec/gf/lexicon_funmap.tsv` ({stats['funmap_total']:,} noun lemmas)\n")
    lines.append("")
    lines.append("## Coverage Summary\n")
    lines.append(f"- **Funmap superset:** {'YES' if stats['funmap_superset'] else 'NO'}\n")
    lines.append(f"- **Funmap present in candidate:** {stats['funmap_present']:,} / {stats['funmap_total']:,}\n")
    lines.append(f"- **Funmap missing from candidate:** {stats['funmap_missing']:,}\n")
    lines.append(f"- **Verbal nouns in funmap:** {stats['verbal_noun_count']:,} (all present in candidate: {stats['verbal_noun_in_candidate'] == stats['verbal_noun_count']})\n")
    lines.append("")
    lines.append("## Discrepancy Classification (funmap vs candidate)\n")
    lines.append(f"| Class | Count | Description |\n")
    lines.append(f"|-------|-------|-------------|\n")
    lines.append(f"| G1 (ё normalization) | {stats['g1']:,} | Forms contain ё or value mismatch vs existing JSON |\n")
    lines.append(f"| G2 (animacy) | {stats['g2']:,} | Animacy flag differs from existing JSON |\n")
    lines.append(f"| G3 (gender) | {stats['g3']:,} | Gender flag differs from existing JSON |\n")
    lines.append(f"| G4 (missing forms) | {stats['g4']:,} | Empty or partial paradigm (empty: {len(g4_empty_full)}, partial: {len(g4_partial_full)}) |\n")
    lines.append(f"| G5 (new coverage) | {stats['g5']:,} | Not in existing JSON or missing from candidate |\n")
    lines.append(f"| OK | {stats['ok']:,} | Perfect match with existing JSON |\n")
    lines.append("")
    lines.append("## Notable Cases\n")
    lines.append("### Empty paradigms (no inflectable forms)\n")
    for lemma in sorted(g4_empty_full):
        lines.append(f"- `{lemma}`: G4 (empty paradigm — no inflectable forms)\n")
    lines.append("")
    lines.append("### Partial paradigms (fewer than 12 forms)\n")
    for lemma in sorted(g4_partial_full)[:20]:
        form_count = len(candidate[lemma]["forms"])
        lines.append(f"- `{lemma}`: {form_count}/12 forms\n")
    lines.append(f"... and {len(g4_partial_full) - 20} more partial paradigms\n")
    lines.append("")
    lines.append("### Verbal nouns (funmap subset)\n")
    for lemma in sorted(verbal_nouns_funmap):
        cand = candidate.get(lemma, {})
        form_count = len(cand.get("forms", {}))
        lines.append(f"- `{lemma}`: {form_count}/12 forms\n")
    lines.append("")
    lines.append("## Predicted Integration Backlog (full 20k set)\n")
    lines.append("")
    lines.append("### Verbal nouns — InsSg breakdown\n")
    lines.append(f"- **Total verbal nouns in candidate:** {len(all_verbal_nouns):,}\n")
    lines.append(f"- **InsSg ending in `-нием`:** {len(niem_list):,}\n")
    lines.append(f"- **InsSg NOT ending in `-нием` (potential G1-like fix):** {len(niem_other_list):,}\n")
    lines.append("")
    lines.append("#### Examples: `-нием` (5)\n")
    for w, ins in sorted(niem_list)[:5]:
        lines.append(f"- `{w}` → `{ins}`\n")
    lines.append("")
    lines.append("#### Examples: non`-нием` (5)\n")
    for w, ins in sorted(niem_other_list)[:5]:
        lines.append(f"- `{w}` → `{ins}`\n")
    lines.append("")
    lines.append("### Predicted G-class examples (5 each, full 20k)\n")
    lines.append(f"- **G1 (yo in forms):** {len(g1_full):,} total\n")
    if g1_full:
        for w in sorted(g1_full)[:5]:
            lines.append(f"  - `{w}`\n")
    else:
        lines.append("  - None\n")
    lines.append(f"- **G2 (animacy mismatch):** {len(g2_full):,} total\n")
    if g2_full:
        for w in sorted(g2_full)[:5]:
            lines.append(f"  - `{w}`\n")
    else:
        lines.append("  - None\n")
    lines.append(f"- **G3 (gender mismatch):** {len(g3_full):,} total\n")
    if g3_full:
        for w in sorted(g3_full)[:5]:
            lines.append(f"  - `{w}`\n")
    else:
        lines.append("  - None\n")
    lines.append(f"- **G4 empty (no forms):** {len(g4_empty_full):,} total\n")
    for w in sorted(g4_empty_full)[:5]:
        lines.append(f"  - `{w}`\n")
    lines.append(f"- **G4 partial (< 12 forms):** {len(g4_partial_full):,} total\n")
    for w in sorted(g4_partial_full)[:5]:
        lines.append(f"  - `{w}` ({len(candidate[w]['forms'])}/12)\n")
    lines.append(f"- **G5 (new coverage, not in existing):** {len(g5_full):,} total\n")
    for w in sorted(g5_full)[:5]:
        lines.append(f"  - `{w}`\n")
    lines.append("")
    lines.append("## Methodology\n")
    lines.append("- G1: checked for unnormalized ё in candidate form values; also flagging form-value mismatches against existing JSON.\n")
    lines.append("- G2/G3: compared `animacy` and `gender` fields against existing JSON.\n")
    lines.append("- G4: counted candidate paradigms with 0 forms (empty) or fewer than 12 keys (partial).\n")
    lines.append("- G5: funmap lemmas missing from candidate entirely, or not present in existing JSON.\n")
    lines.append("- Verbal nouns: identified by suffix `-ние`, `-нье`, `-ение` in funmap lemmas.\n")
    lines.append("- Predicted integration backlog: classified across full 20k candidate set for future integration planning.\n")
    lines.append("")

    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with REPORT_PATH.open("w", encoding="utf-8") as f:
        f.writelines(lines)
    print(f"Wrote parity report to {REPORT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
