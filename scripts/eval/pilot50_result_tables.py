#!/usr/bin/env python3
"""Descriptive tables for the 50-prompt pilot (no scoring, no thresholds).

Inputs:
  reports/eval_runs/<run>/results.jsonl   harness output
  <export>/mapping.tsv                    blind_id -> real_id, split, topic
  <export>/blind.tsv                      blind_id, prompt, answer

Outputs markdown tables on stdout:
  1. per-split aggregates (family fit, authority, linearization, latency)
  2. mechanical artifacts on the observed surfaces
  3. per-row list sorted by split
"""
import argparse
import csv
import json
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

LABEL_RE = re.compile(r"^\s*(Определение|Тезис|Гипотеза)\s*:", re.I)
GROUND_RE = re.compile(r"\(основание:\s*(.*?)\)", re.I | re.S)
EN_TEMPLATE = "continue the dialogue in english"


def detect_artifacts(answer):
    """Mechanical surface artifacts the pilot rubric prices (R4 / P5)."""
    low = answer.lower()
    grounds = GROUND_RE.findall(answer)
    return {
        "label": (LABEL_RE.match(answer).group(1) if LABEL_RE.match(answer) else "—"),
        "dup": any(low.count(g.strip().lower()) >= 2 for g in grounds if g.strip()),
        "en": EN_TEMPLATE in low,
        "chars": len(answer),
    }


def load_jsonl(path):
    return [json.loads(l) for l in Path(path).read_text(encoding="utf-8").splitlines() if l.strip()]


def self_test():
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    anchor = "Тезис: свобода предполагает возможность выбора. Проверка: верно ли это?"
    a = detect_artifacts(anchor)
    case("anchor label", a["label"] == "Тезис", a["label"])
    case("anchor has no duplicate ground", not a["dup"])
    case("anchor is not English", not a["en"])

    held = ("Гипотеза: граница устанавливает условие формы (основание: граница "
            "устанавливает условие формы). Следующий ход: вернуться к открытому "
            "вопросу: «что такое граница?».")
    h = detect_artifacts(held)
    case("held label", h["label"] == "Гипотеза", h["label"])
    case("duplicate ground detected", h["dup"])

    distinct = "Тезис: X. (основание: Y)"
    case("distinct ground is not a duplicate", not detect_artifacts(distinct)["dup"])

    plain = "Я вижу тему, но в локальной модели нет достаточного основания."
    case("no label is reported as a dash", detect_artifacts(plain)["label"] == "—")

    english = "I am here to continue the dialogue in English."
    case("English template detected", detect_artifacts(english)["en"])

    case("length is the raw character count",
         detect_artifacts(anchor)["chars"] == len(anchor))

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}"
              + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", nargs="?")
    ap.add_argument("export_dir", nargs="?")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.run_dir or not args.export_dir:
        ap.error("run_dir and export_dir are required (or --self-test)")

    run = Path(args.run_dir)
    exp = Path(args.export_dir)
    results = {r["id"]: r for r in load_jsonl(run / "results.jsonl")}

    mapping = {}
    with open(exp / "mapping.tsv", encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            mapping[r["blind_id"]] = r
    answers = {}
    with open(exp / "blind.tsv", encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            answers[r["blind_id"]] = r["answer"]

    rows = []
    for bid, m in mapping.items():
        r = results.get(m["real_id"])
        if not r:
            continue
        answer = answers.get(bid, "")
        art = detect_artifacts(answer)
        rows.append({
            "blind_id": bid, "real_id": m["real_id"], "split": m["split"],
            "topic": m["topic"], "family": r["actual_family"], "expected": r["expected_family"],
            "fit": bool(r.get("intent_fit")), "authority": r.get("authority_class"),
            "lin": r.get("linearization_ok"), "fallback": r.get("trace_fallback_reason"),
            "gfmap": r.get("gf_mapped_fallback"), "latency": r.get("latency_ms"),
            "label": art["label"], "dup": art["dup"], "en": art["en"],
            "chars": art["chars"],
        })

    print("## Per-split aggregates\n")
    print("| split | rows | family fit | canonical | linearized | gf mapped | latency mean / median ms |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    by = defaultdict(list)
    for r in rows:
        by[r["split"]].append(r)
    for split in ("anchor", "held", "oov"):
        rs = by.get(split, [])
        if not rs:
            continue
        lat = [r["latency"] for r in rs if isinstance(r["latency"], int)]
        print(f"| {split} | {len(rs)} | {sum(r['fit'] for r in rs)}/{len(rs)} | "
              f"{sum(r['authority'] == 'AuthorityCanonical' for r in rs)}/{len(rs)} | "
              f"{sum(bool(r['lin']) for r in rs)}/{len(rs)} | "
              f"{sum(bool(r['gfmap']) for r in rs)}/{len(rs)} | "
              f"{statistics.mean(lat):.0f} / {statistics.median(lat):.0f} |" if lat else "")

    print("\n## Mechanical surface artifacts\n")
    print("| split | framing labels | duplicate «основание» | English template |")
    print("|---|---|---|---:|")
    for split in ("anchor", "held", "oov"):
        rs = by.get(split, [])
        if not rs:
            continue
        labels = Counter(r["label"] for r in rs)
        print(f"| {split} | {dict(labels)} | {sum(r['dup'] for r in rs)}/{len(rs)} | "
              f"{sum(r['en'] for r in rs)}/{len(rs)} |")

    print("\n## Rows\n")
    print("| split | real_id | topic | family | auth | fallback | gfmap | lat ms | label | dup | chars |")
    print("|---|---|---|---|---|---|---|---:|---|---|---:|")
    order = {"anchor": 0, "held": 1, "oov": 2}
    for r in sorted(rows, key=lambda x: (order.get(x["split"], 9), x["real_id"])):
        print(f"| {r['split']} | {r['real_id']} | {r['topic']} | {r['family']} | "
              f"{r['authority']} | {r['fallback'] or '—'} | {r['gfmap']} | "
              f"{r['latency']} | {r['label']} | {r['dup']} | {r['chars']} |")


if __name__ == "__main__":
    sys.exit(main())
