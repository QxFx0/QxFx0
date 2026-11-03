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
import sys
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


def self_test():
    """Guard the silent-failure mode: if the corpus loader stops matching the
    real files, every R2 lookup returns "—" and the score looks clean."""
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    corpus = load_corpus()
    case("merged corpus is non-trivial", len(corpus) > 1000, f"{len(corpus)} topics")
    freedom = corpus.get("свобода", [])
    case("known seed topic resolves", bool(freedom), f"{len(freedom)} predicates")
    case("known seed predicate resolves",
         any(p.startswith("свобода") for p in freedom), str(freedom[:2]))
    case("unknown term has no topic entry",
         "термоядерный синтез" not in corpus)
    case("curated-only topic is merged in",
         bool(corpus.get("идентичность")), f"{len(corpus.get('идентичность', []))}")

    answer = "Тезис: свобода предполагает возможность выбора."
    case("traceable predicate is found",
         any(p in answer.lower() for p in freedom), "lookup failed")

    case("framing label extracted",
         (LABEL_RE.match(answer).group(1) if LABEL_RE.match(answer) else None) == "Тезис")
    case("grounding clause counted, not deduplicated",
         len(GROUND_RE.findall("A (основание: X) B (основание: Y)")) == 2)

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}"
              + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("blind", nargs="?")
    ap.add_argument("mapping", nargs="?")
    ap.add_argument("--mode", choices=("artifacts", "refs"), default="artifacts")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.blind or not args.mapping:
        ap.error("blind and mapping paths are required (or --self-test)")

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
    sys.exit(main())
