#!/usr/bin/env python3
"""Freeze a held-out split for Stage-1 semantic-IR data (ADR-0054 §2.4).

Deterministic split by id hash: sha256(id) mod 100 -> <60 train,
<80 dev, else test. Writes data/semantic_ir/splits.json with the id
sets plus the source file sha256 (any silent edit breaks the unit
check). Evaluation scripts read the test split only.

Rules are the model, utterances are the test data: rules and minimal
pairs are NOT split (too small to split meaningfully); the split
covers gold utterance files. Cluster files get their splits at
authoring time with this same script (--source/--out).

Usage: python3 scripts/split_semantic_ir.py [--check]
  --check: verify splits.json against the source file (CI mode).
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GOLD = ROOT / "data" / "semantic_ir" / "gold.jsonl"
SPLITS = ROOT / "data" / "semantic_ir" / "splits.json"


def bucket(rid):
    return int(hashlib.sha256(rid.encode()).hexdigest(), 16) % 100


def split_ids(ids):
    train, dev, test = [], [], []
    for rid in ids:
        b = bucket(rid)
        if b < 60:
            train.append(rid)
        elif b < 80:
            dev.append(rid)
        else:
            test.append(rid)
    return {"train": sorted(train), "dev": sorted(dev), "test": sorted(test)}


def source_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    check = "--check" in sys.argv[1:]
    rows = [json.loads(l) for l in open(GOLD, encoding="utf-8")
            if l.strip()]
    ids = [r["id"] for r in rows]
    digest = source_sha256(GOLD)
    if check:
        saved = json.loads(open(SPLITS, encoding="utf-8").read())
        assert saved["source_sha256"] == digest, "gold.jsonl changed without re-freezing"
        assert saved["source"] == "data/semantic_ir/gold.jsonl"
        seen = saved["splits"]["train"] + saved["splits"]["dev"] + saved["splits"]["test"]
        assert sorted(seen) == sorted(ids), "split does not partition gold ids"
        assert len(set(seen)) == len(seen), "split ids not disjoint"
        print(f"split OK: {len(ids)} rows, digest {digest[:12]}")
        return 0
    splits = split_ids(ids)
    counts = {k: len(v) for k, v in splits.items()}
    print(f"rows={len(ids)} train/dev/test={counts['train']}/{counts['dev']}/{counts['test']}")
    json.dump({"version": 1, "source": "data/semantic_ir/gold.jsonl",
               "source_sha256": digest, "splits": splits},
              open(SPLITS, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"wrote {SPLITS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
