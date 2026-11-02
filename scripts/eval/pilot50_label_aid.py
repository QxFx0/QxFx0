#!/usr/bin/env python3
"""Operator aid for the 50-prompt pilot. NOT a scorer.

Two modes:

  artifacts (default)  blind_id, prompt, answer + mechanically detectable
                       artifacts: framing label, duplicated «(основание: …)»
                       clause, echoed question, English template, length.
                       Use this for the blind pass (R1, R3, R4).

  refs                 adds the normalized curated predicates for the row's
                       topic and marks which ones appear verbatim in the
                       answer. Use this only AFTER the blind pass, to verify
                       R2 traceability. P3 hides the split/golden; R2 is by
                       definition a corpus lookup, so this pass is recorded.

Reads blind.tsv and mapping.tsv produced by pilot50_export_blind.py.
Curated corpus = resources/knowledge/curated_predicates.jsonl plus the seed
`definitionCorpus` parsed out of src/QxFx0/Semantic/Content.hs, i.e. the same
merged corpus the runtime uses.
"""
import argparse
import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
norm = lambda s: re.sub(r"\s+", " ", s.strip().lower())

LABEL_RE = re.compile(r"^\s*(Определение|Тезис|Гипотеза)\s*:", re.I)
GROUND_RE = re.compile(r"\(основание:\s*(.*?)\)", re.I | re.S)


def load_corpus():
    merged = {}
    path = ROOT / "resources/knowledge/curated_predicates.jsonl"
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        t = norm(d["topic"])
        ps = merged.setdefault(t, [])
        for p in d.get("predicates", []):
            ru = p.get("ru")
            if ru and norm(ru) not in ps:
                ps.append(norm(ru))

    src = (ROOT / "src/QxFx0/Semantic/Content.hs").read_text(encoding="utf-8")
    topic = None
    for line in src.splitlines():
        m = re.search(r'\bentry\s+"([^"]+)"', line)
        if m:
            topic = norm(m.group(1))
            merged.setdefault(topic, [])
            continue
        m = re.search(r'\b(?:prop|rel)\s+"([^"]+)"', line)
        if m and topic:
            p = norm(m.group(1))
            if p not in merged[topic]:
                merged[topic].append(p)
    return merged


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("blind")
    ap.add_argument("mapping")
    ap.add_argument("--mode", choices=("artifacts", "refs"), default="artifacts")
    args = ap.parse_args()

    topics = {}
    with open(args.mapping, encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            topics[r["blind_id"]] = r["topic"]

    corpus = load_corpus() if args.mode == "refs" else {}

    print("blind_id\ttopic\ttraceable_predicates\tframing\tdup_ground\techo_q\ten_template\tchars")
    with open(args.blind, encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            bid = r["blind_id"]
            prompt = r["prompt"]
            answer = r["answer"]
            low = answer.lower()
            label = (LABEL_RE.match(answer).group(1) if LABEL_RE.match(answer) else "—")
            dups = len(GROUND_RE.findall(answer))
            echo = "yes" if prompt.strip().lower().rstrip("?") in low else "no"
            en = "yes" if "continue the dialogue in english" in low else "no"
            if args.mode == "refs":
                topic = norm(topics.get(bid, ""))
                hits = [p for p in corpus.get(topic, []) if p and p in low]
                refs = " | ".join(hits) if hits else "—"
            else:
                topic, refs = topics.get(bid, ""), "n/a"
            print("\t".join([bid, topic, refs, label, str(dups), echo, en, str(len(answer))]))


if __name__ == "__main__":
    main()
