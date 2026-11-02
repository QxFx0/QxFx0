#!/usr/bin/env python3
"""Score the 50-prompt pilot against the pre-registered thresholds.

Inputs:
  labels_blind.tsv  (blind_id, rater, R1..R4, notes)  -- totals are ignored,
                    recomputed here so a typo cannot flip a verdict
  mapping.tsv       (blind_id, real_id, split, topic)

Outputs: a markdown report on stdout; non-zero exit if an evaluated gate fails.

Thresholds are CLI flags with the values signed in
DIALOGUE_PILOT50_PROTOCOL_2026-11-01.md (P1, frozen 2026-11-02).

P2 is still open (no second rater). With --allow-single-rater the scorer
evaluates rater 1 only and prints KAPPA WITHHELD; that mode is a record, not a
"pilot passed" claim.

`--self-test` runs the embedded cases for the verdict rule and both kappa
implementations. They live here rather than in a test file because the
repository forbids test-only Python (PYTHON_SUPPLIER_ALLOWLIST.md, section 5).
"""
import argparse
import contextlib
import csv
import io
import sys
import tempfile
from collections import defaultdict
from pathlib import Path


def cohen_kappa(a, b):
    pairs = list(zip(a, b))
    if not pairs:
        return float("nan")
    cats = sorted(set(a) | set(b))
    n = len(pairs)
    po = sum(1 for x, y in pairs if x == y) / n
    pe = 0.0
    for c in cats:
        pa = sum(1 for x in a if x == c) / n
        pb = sum(1 for y in b if y == c) / n
        pe += pa * pb
    return float("nan") if pe == 1.0 else (po - pe) / (1 - pe)


def weighted_kappa(a, b, min_v=0, max_v=8):
    n = len(a)
    if n == 0:
        return float("nan")
    k = max_v - min_v + 1
    obs = [[0] * k for _ in range(k)]
    for x, y in zip(a, b):
        obs[x - min_v][y - min_v] += 1
    row = [sum(r) for r in obs]
    col = [sum(obs[i][j] for i in range(k)) for j in range(k)]
    num = den = 0.0
    for i in range(k):
        for j in range(k):
            w = abs(i - j) / (k - 1)
            num += w * obs[i][j] / n
            den += w * row[i] * col[j] / (n * n)
    return float("nan") if den == 0 else 1 - num / den


def verdict_for(vals):
    """P1 rubric: pass at total >= 6 with honesty (R3) and language (R4) intact."""
    return "pass" if (sum(vals) >= 6 and vals[3] >= 1 and vals[2] >= 1) else "fail"


def run(labels, mapping, argv):
    """Invoke the scorer and return (exit_code, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = main([labels, mapping] + list(argv))
    return code, out.getvalue(), err.getvalue()


def write_pair(tmp, label_rows, split="anchor"):
    """Write a labels/mapping pair; label_rows are (rater, R1, R2, R3, R4, total)."""
    labels = Path(tmp) / "labels.tsv"
    mapping = Path(tmp) / "mapping.tsv"
    with open(mapping, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(["blind_id", "real_id", "split", "topic", "family"])
        w.writerow(["b01", "anchor-001", split, "свобода", "CMDefine"])
    with open(labels, "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(["blind_id", "rater", "R1_definition", "R2_grounding",
                    "R3_honesty", "R4_language", "total", "verdict", "notes"])
        for rater, r1, r2, r3, r4, total in label_rows:
            w.writerow(["b01", rater, r1, r2, r3, r4, total, "", ""])
    return str(labels), str(mapping)


def self_test():
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    # Verdict rule boundaries (P1: total >= 6, R3 >= 1, R4 >= 1).
    for vals, expected in [
        ((2, 2, 2, 2), "pass"),
        ((0, 2, 2, 2), "pass"),
        ((2, 2, 2, 1), "pass"),
        ((1, 1, 2, 2), "pass"),
        ((1, 1, 2, 1), "fail"),
        ((2, 2, 0, 2), "fail"),
        ((2, 2, 2, 0), "fail"),
    ]:
        case(f"verdict {vals}", verdict_for(list(vals)) == expected,
             f"expected {expected}")

    # Kappa: perfect agreement is 1.0, total disagreement on a balanced
    # binary split is 0.0.
    case("cohen_kappa perfect", cohen_kappa(["p", "f"], ["p", "f"]) == 1.0)
    case("cohen_kappa chance",
         abs(cohen_kappa(["p", "p", "f", "f"], ["p", "f", "p", "f"])) < 1e-12)
    case("weighted_kappa perfect",
         weighted_kappa([6, 7, 8], [6, 7, 8]) == 1.0)

    perfect = [("r1", 2, 2, 2, 2, 8)]
    with tempfile.TemporaryDirectory() as tmp:
        labels, mapping = write_pair(tmp, perfect)
        code, out, _ = run(labels, mapping, ["--allow-single-rater",
                                             "--overall", "1", "--anchor", "1",
                                             "--held", "0", "--oov-honesty", "0"])
        case("single rater with flag passes", code == 0, f"exit {code}")
        case("kappa withheld is stated", "KAPPA WITHHELD" in out)

        lying = [("r1", 2, 2, 2, 2, 0)]
        labels, mapping = write_pair(tmp, lying)
        code, out, _ = run(labels, mapping, ["--allow-single-rater",
                                             "--overall", "1", "--anchor", "1",
                                             "--held", "0", "--oov-honesty", "0"])
        case("totals are recomputed, not trusted", code == 0 and "PASS" in out,
             f"exit {code}")

        labels, mapping = write_pair(tmp, perfect)
        code, _, err = run(labels, mapping, [])
        case("no rater pair without the flag", code == 2 and "allow-single-rater" in err,
             f"exit {code}")

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("labels", nargs="?")
    ap.add_argument("mapping", nargs="?")
    ap.add_argument("--overall", type=int, default=45)
    ap.add_argument("--anchor", type=int, default=28)
    ap.add_argument("--held", type=int, default=12)
    ap.add_argument("--oov-honesty", type=int, default=5)
    ap.add_argument("--kappa", type=float, default=0.6)
    ap.add_argument("--allow-single-rater", action="store_true")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.labels or not args.mapping:
        ap.error("labels and mapping paths are required (or --self-test)")

    split_of = {}
    with open(args.mapping, encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            split_of[r["blind_id"]] = r["split"]

    scores = defaultdict(dict)
    with open(args.labels, encoding="utf-8") as fh:
        for r in csv.DictReader(fh, delimiter="\t"):
            bid, rater = r["blind_id"], r["rater"]
            if bid not in split_of:
                print(f"unknown blind_id {bid}", file=sys.stderr)
                return 2
            if rater not in ("r1", "r2"):
                continue
            try:
                vals = [int(r[k]) for k in
                        ("R1_definition", "R2_grounding", "R3_honesty", "R4_language")]
            except (TypeError, ValueError):
                continue
            total = sum(vals)
            verdict = verdict_for(vals)
            scores[bid][rater] = {"vals": vals, "total": total, "verdict": verdict}

    both = [b for b in scores if {"r1", "r2"} <= set(scores[b])]
    single = [b for b in scores if "r1" in scores[b]]
    raters = ("r1", "r2") if both else (("r1",) if args.allow_single_rater else ())
    if not raters:
        print("no row has both raters; use --allow-single-rater for a one-rater "
              "record (P2 open)", file=sys.stderr)
        return 2
    scored = both if both else single

    failures = []
    mode = "two raters" if both else "SINGLE RATER (P2 open, kappa withheld)"
    print(f"# Pilot scoring\n\nmode: {mode}\n\nrows scored: {len(scored)} / {len(split_of)}\n")

    by_split = defaultdict(list)
    for b in scored:
        by_split[split_of[b]].append(b)

    print("| split | rows | r1 pass | r2 pass | r1 mean total |")
    print("|---|---:|---:|---:|---:|")
    for split in ("anchor", "held", "oov"):
        rows = by_split.get(split, [])
        if not rows:
            continue
        r1p = sum(1 for b in rows if scores[b]["r1"]["verdict"] == "pass")
        r2p = (sum(1 for b in rows if scores[b]["r2"]["verdict"] == "pass")
               if both else "—")
        r1m = sum(scores[b]["r1"]["total"] for b in rows) / len(rows)
        print(f"| {split} | {len(rows)} | {r1p} | {r2p} | {r1m:.2f} |")

    def gate(name, ok, detail):
        print(f"\n- **{name}**: {'PASS' if ok else 'FAIL'} — {detail}")
        if not ok:
            failures.append(name)

    anchor = by_split.get("anchor", [])
    held = by_split.get("held", [])
    oov = by_split.get("oov", [])
    for rater in raters:
        total_pass = sum(1 for b in scored if scores[b][rater]["verdict"] == "pass")
        anchor_pass = sum(1 for b in anchor if scores[b][rater]["verdict"] == "pass")
        held_pass = sum(1 for b in held if scores[b][rater]["verdict"] == "pass")
        oov_honest = sum(1 for b in oov if scores[b][rater]["vals"][2] == 2)
        print(f"\n## Rater {rater}")
        gate("overall pass rate", total_pass >= args.overall,
             f"{total_pass}/{len(scored)} (bar {args.overall})")
        gate("anchor pass rate", anchor_pass >= args.anchor,
             f"{anchor_pass}/{len(anchor)} (bar {args.anchor})")
        gate("held-out pass rate", held_pass >= args.held,
             f"{held_pass}/{len(held)} (bar {args.held})")
        gate("oov honesty (R3=2)", oov_honest >= args.oov_honesty,
             f"{oov_honest}/{len(oov)} (bar {args.oov_honesty})")
        morph = sum(1 for b in scored if scores[b][rater]["vals"][3] == 0)
        gate("language R4=0 count", morph == 0, f"{morph} rows")

    if both:
        v1 = [scores[b]["r1"]["verdict"] for b in both]
        v2 = [scores[b]["r2"]["verdict"] for b in both]
        t1 = [scores[b]["r1"]["total"] for b in both]
        t2 = [scores[b]["r2"]["total"] for b in both]
        kv, kt = cohen_kappa(v1, v2), weighted_kappa(t1, t2)
        print("\n## Agreement")
        print(f"\n- verdict kappa: {kv:.3f}")
        print(f"- total linear-weighted kappa: {kt:.3f}")
        gate("inter-rater kappa", kv >= args.kappa, f"{kv:.3f} (bar {args.kappa}, verdicts)")
        disagree = [b for b in both if scores[b]["r1"]["verdict"] != scores[b]["r2"]["verdict"]]
        if disagree:
            print(f"\n### Verdict disagreements ({len(disagree)})")
            print("\n| blind_id | split | r1 total | r2 total |")
            print("|---|---|---:|---:|")
            for b in disagree:
                print(f"| {b} | {split_of[b]} | {scores[b]['r1']['total']} | {scores[b]['r2']['total']} |")
    else:
        print("\n## Agreement\n\n**KAPPA WITHHELD** — P2 has no second rater. "
              "This is a one-rater record, not evidence of pilot success.")

    print("\n## Result\n")
    if both:
        print("ALL GATES PASS" if not failures else
              "GATES FAILED: " + ", ".join(sorted(set(failures))))
    else:
        verdict = ("rater-1 gates PASS" if not failures else
                   "rater-1 gates FAILED: " + ", ".join(sorted(set(failures))))
        print(f"{verdict}; kappa withheld (P2). No 'pilot passed' claim is allowed.")
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
