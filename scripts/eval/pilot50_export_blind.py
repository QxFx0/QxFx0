#!/usr/bin/env python3
"""Blind export for the 50-prompt pilot.

Reads reports/eval_runs/<run>/raw/*.log, extracts the final JSON turn payload,
and writes:
  <out>/blind.tsv           blind_id, prompt, answer        (give to raters)
  <out>/labels_blind.tsv    blind_id, rater, R1..R4, total, verdict, notes
  <out>/mapping.tsv         blind_id, real_id, split, topic  (operator only)

Order is shuffled with a fixed seed so raters cannot infer the split from
position. The prompt itself is shown (unavoidable for a judgement task), so
"blind" here means: split labels, golden predicates and the M7 result are
hidden (protocol P3).

`--self-test` runs the embedded cases (mapping integrity, seed determinism,
no split leak into the rater file). They live here rather than in a test file
because the repository forbids test-only Python
(PYTHON_SUPPLIER_ALLOWLIST.md, section 5).
"""
import argparse
import csv
import json
import random
import sys
import tempfile
from pathlib import Path

BLIND_COLUMNS = ("blind_id", "prompt", "answer")
MAPPING_COLUMNS = ("blind_id", "real_id", "split", "topic", "family")
LABELS_COLUMNS = ("blind_id", "rater", "R1_definition", "R2_grounding",
                  "R3_honesty", "R4_language", "total", "verdict", "notes")


def parse_turn(raw_text: str):
    best = None
    for line in raw_text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if isinstance(obj, dict) and ("response" in obj or "surface" in obj):
            best = obj
    if best is None:
        return None
    text = best.get("response") or best.get("surface") or best.get("text") or ""
    return {"text": text, "family": best.get("family") or best.get("move_family")}


def load_meta(prompts_path):
    meta = {}
    with open(prompts_path, encoding="utf-8") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            meta[row["id"]] = row
    return meta


def collect_rows(meta, raw_dir):
    """Return (rows, missing_ids, unparsed_ids) for every prompt in the packet."""
    rows, missing, unparsed = [], [], []
    for rid, m in meta.items():
        f = Path(raw_dir) / f"{rid}.log"
        if not f.exists():
            missing.append(rid)
            continue
        parsed = parse_turn(f.read_text(encoding="utf-8", errors="replace"))
        if parsed is None:
            unparsed.append(rid)
            continue
        rows.append({"real_id": rid, "split": m["split"], "topic": m["topic"],
                     "prompt": m["prompt"], "answer": parsed["text"],
                     "family": parsed["family"]})
    return rows, sorted(missing), sorted(unparsed)


def write_export(rows, out, seed):
    """Shuffle `rows` with a fixed seed and write the three export files."""
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    random.Random(seed).shuffle(rows)
    width = max(2, len(str(len(rows))))

    with open(out / "blind.tsv", "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(BLIND_COLUMNS)
        for i, r in enumerate(rows, 1):
            r["blind_id"] = f"b{i:0{width}d}"
            w.writerow([r["blind_id"], r["prompt"], r["answer"]])

    with open(out / "mapping.tsv", "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(MAPPING_COLUMNS)
        for r in rows:
            w.writerow([r["blind_id"], r["real_id"], r["split"], r["topic"],
                        r.get("family") or ""])

    with open(out / "labels_blind.tsv", "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, delimiter="\t", lineterminator="\n")
        w.writerow(LABELS_COLUMNS)
        for r in rows:
            for rater in ("r1", "r2"):
                w.writerow([r["blind_id"], rater, "", "", "", "", "", "", ""])


def self_test():
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        prompts = tmp / "packet.tsv"
        with open(prompts, "w", encoding="utf-8", newline="") as fh:
            fh.write("id\tsplit\ttopic\tprompt\texpected_family\n")
            for i in range(1, 7):
                fh.write(f"r{i:02d}\tanchor\tt{i}\tчто такое t{i}?\tCMDefine\n")
            fh.write("r07\toov\tt7\tчто такое t7?\tUnknown\n")

        raw = tmp / "raw"
        raw.mkdir()
        for i in range(1, 8):
            body = "noise\n" + json.dumps(
                {"response": f"ответ {i}", "family": "CMDefine"},
                ensure_ascii=False) + "\n"
            (raw / f"r{i:02d}.log").write_text(body, encoding="utf-8")
        (raw / "r06.log").write_text("garbage only\n", encoding="utf-8")
        (raw / "r07.log").unlink()

        meta = load_meta(prompts)
        case("packet loaded", len(meta) == 7, f"got {len(meta)}")
        rows, missing, unparsed = collect_rows(meta, raw)
        case("missing log reported", missing == ["r07"], str(missing))
        case("unparsed log reported", unparsed == ["r06"], str(unparsed))
        case("only parsed rows exported", len(rows) == 5, f"got {len(rows)}")

        out1, out2 = tmp / "e1", tmp / "e2"
        write_export([dict(r) for r in rows], out1, seed=7)
        write_export([dict(r) for r in rows], out2, seed=7)
        same = all((out1 / name).read_bytes() == (out2 / name).read_bytes()
                   for name in ("blind.tsv", "mapping.tsv", "labels_blind.tsv"))
        case("same seed is deterministic", same)

        write_export([dict(r) for r in rows], tmp / "e3", seed=8)
        differs = ((tmp / "e3" / "blind.tsv").read_bytes()
                   != (out1 / "blind.tsv").read_bytes())
        case("different seed reorders", differs)

        blind = (out1 / "blind.tsv").read_text(encoding="utf-8").splitlines()
        case("blind header has three columns",
             blind[0].split("\t") == list(BLIND_COLUMNS), blind[0])
        case("blind rows match exported rows",
             len(blind) - 1 == len(rows), f"{len(blind) - 1}")
        case("no split label leaks into the rater file",
             not any(label in "\n".join(blind) for label in ("anchor", "oov")))

        mapping = list(csv.DictReader(open(out1 / "mapping.tsv", encoding="utf-8"),
                                      delimiter="\t"))
        case("mapping covers every exported row", len(mapping) == len(rows))
        case("mapping keeps the split", {m["split"] for m in mapping} == {"anchor"})

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}"
              + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("run_dir", nargs="?", help="reports/eval_runs/<run-id>")
    ap.add_argument("prompts", nargs="?", help="spec/eval/pilot50_prompts.tsv")
    ap.add_argument("out", nargs="?", help="output directory")
    ap.add_argument("--seed", type=int, default=20261101)
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.run_dir or not args.prompts or not args.out:
        ap.error("run_dir, prompts and out are required (or --self-test)")

    meta = load_meta(args.prompts)
    rows, missing, unparsed = collect_rows(meta, Path(args.run_dir) / "raw")
    out = Path(args.out)
    write_export(rows, out, args.seed)

    print(f"exported {len(rows)} rows -> {out}")
    if missing:
        print(f"MISSING {len(missing)}: {', '.join(missing)}")
    if unparsed:
        print(f"UNPARSED {len(unparsed)}: {', '.join(unparsed)}")
    empty = [r["real_id"] for r in rows if not r["answer"].strip()]
    if empty:
        print(f"EMPTY ANSWERS {len(empty)}: {', '.join(empty)}")
    dup = [r["real_id"] for r in rows if r["answer"].strip().lower() in
           ("i am here to continue the dialogue in english.",)]
    if dup:
        print(f"WARNING template/English fallback answers: {len(dup)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
