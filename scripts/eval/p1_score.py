#!/usr/bin/env python3
"""P1 label scoring: quadratic weighted kappa, CI, adjudication list.

Eval-only. Reads the packet key and the two rater label files; never writes to
the runtime or the capture database.

Input formats (TSV, no header):
  key.tsv     id <TAB> dialogue <TAB> turn <TAB> class
  labels.tsv  id <TAB> label          (label is an integer 0-4)

The double-rated subset is rater 2's id set. It must be >= 50 ids, a subset of
rater 1's ids, and a subset of the key. Kappa is refused (exit 2) when those
conditions do not hold; the tool never prints a kappa over a partial subset.

usage:
  p1_score.py --key key.tsv --rater1 r1.tsv --rater2 r2.tsv [--json]
  p1_score.py --self-test
"""

from __future__ import annotations

import argparse
import json
import random
import statistics
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

MIN_DOUBLE = 50
MAX_LABEL = 4
BOOTSTRAP_ROUNDS = 1000
BOOTSTRAP_SEED = 20261128


class ScoreError(Exception):
    """A validation failure that must stop scoring."""


def read_key(path: Path) -> Dict[str, Tuple[str, int, str]]:
    key: Dict[str, Tuple[str, int, str]] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise ScoreError(f"{path}:{number}: expected 4 columns, got {len(parts)}")
        ident, dialogue, turn, klass = parts
        if not ident:
            raise ScoreError(f"{path}:{number}: empty id")
        if ident in key:
            raise ScoreError(f"{path}:{number}: duplicate id {ident!r}")
        if not turn.isdigit():
            raise ScoreError(f"{path}:{number}: turn is not an integer: {turn!r}")
        key[ident] = (dialogue, int(turn), klass)
    if not key:
        raise ScoreError(f"{path}: no rows")
    return key


def read_labels(path: Path) -> Dict[str, int]:
    labels: Dict[str, int] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 2:
            raise ScoreError(f"{path}:{number}: expected 2 columns, got {len(parts)}")
        ident, raw = parts
        if not ident:
            raise ScoreError(f"{path}:{number}: empty id")
        if ident in labels:
            raise ScoreError(f"{path}:{number}: duplicate id {ident!r}")
        try:
            label = int(raw)
        except ValueError as exc:
            raise ScoreError(f"{path}:{number}: label is not an integer: {raw!r}") from exc
        if label < 0 or label > MAX_LABEL:
            raise ScoreError(f"{path}:{number}: label out of range 0..{MAX_LABEL}: {label}")
        labels[ident] = label
    if not labels:
        raise ScoreError(f"{path}: no labels")
    return labels


def validate_coverage(
    key: Dict[str, Tuple[str, int, str]],
    rater1: Dict[str, int],
    rater2: Dict[str, int],
) -> List[str]:
    """Return the sorted double-rated ids; raise on any coverage defect."""
    unknown = (set(rater1) | set(rater2)) - set(key)
    if unknown:
        raise ScoreError(f"labels reference ids not in the key: {sorted(unknown)[:5]}")
    missing = set(key) - set(rater1)
    if missing:
        raise ScoreError(f"rater 1 is missing {len(missing)} ids: {sorted(missing)[:5]}")
    double = sorted(rater2)
    if len(double) < MIN_DOUBLE:
        raise ScoreError(
            f"double-rated subset has {len(double)} ids; at least {MIN_DOUBLE} are required"
        )
    return double


def confusion(pairs: Sequence[Tuple[int, int]]) -> List[List[int]]:
    matrix = [[0] * (MAX_LABEL + 1) for _ in range(MAX_LABEL + 1)]
    for a, b in pairs:
        matrix[a][b] += 1
    return matrix


def weighted_kappa(pairs: Sequence[Tuple[int, int]]) -> float:
    """Quadratic weighted Cohen's kappa over labels 0..4."""
    n = len(pairs)
    if n == 0:
        raise ScoreError("cannot compute kappa on an empty subset")
    matrix = confusion(pairs)
    rows = [sum(matrix[i]) for i in range(MAX_LABEL + 1)]
    cols = [sum(matrix[i][j] for i in range(MAX_LABEL + 1)) for j in range(MAX_LABEL + 1)]

    def weight(i: int, j: int) -> float:
        return 1.0 - ((i - j) / MAX_LABEL) ** 2

    observed = sum(weight(i, j) * matrix[i][j] for i in range(MAX_LABEL + 1)
                   for j in range(MAX_LABEL + 1)) / n
    expected = sum(weight(i, j) * rows[i] * cols[j] for i in range(MAX_LABEL + 1)
                   for j in range(MAX_LABEL + 1)) / (n * n)
    if abs(1.0 - expected) < 1e-12:
        return 1.0 if abs(observed - 1.0) < 1e-12 else 0.0
    return (observed - expected) / (1.0 - expected)


def bootstrap_ci(pairs: Sequence[Tuple[int, int]]) -> Tuple[float, float]:
    rng = random.Random(BOOTSTRAP_SEED)
    n = len(pairs)
    samples: List[float] = []
    for _ in range(BOOTSTRAP_ROUNDS):
        resample = [pairs[rng.randrange(n)] for _ in range(n)]
        samples.append(weighted_kappa(resample))
    samples.sort()
    lo = samples[int(0.025 * (len(samples) - 1))]
    hi = samples[int(0.975 * (len(samples) - 1))]
    return lo, hi


def score(
    key: Dict[str, Tuple[str, int, str]],
    rater1: Dict[str, int],
    rater2: Dict[str, int],
) -> dict:
    double = validate_coverage(key, rater1, rater2)
    pairs = [(rater1[i], rater2[i]) for i in double]
    exact = sum(1 for a, b in pairs if a == b)
    diffs = [(i, rater1[i], rater2[i]) for i in double if abs(rater1[i] - rater2[i]) >= 2]
    all_labels = list(rater1.values())
    per_class: Dict[str, int] = {}
    for _dialogue, _turn, klass in key.values():
        per_class[klass] = per_class.get(klass, 0) + 1
    return {
        "rows": len(key),
        "double_rated": len(double),
        "exact_agreement": exact,
        "exact_agreement_rate": exact / len(double),
        "kappa_quadratic": weighted_kappa(pairs),
        "kappa_ci95": bootstrap_ci(pairs),
        "confusion": confusion(pairs),
        "adjudication": [{"id": i, "rater1": a, "rater2": b} for i, a, b in sorted(diffs)],
        "label_mean": statistics.mean(all_labels),
        "label_median": statistics.median(all_labels),
        "per_class_rows": per_class,
    }


def format_report(result: dict) -> str:
    lo, hi = result["kappa_ci95"]
    lines = [
        f"rows: {result['rows']}",
        f"double-rated: {result['double_rated']}",
        f"exact agreement: {result['exact_agreement']}/{result['double_rated']}"
        f" ({result['exact_agreement_rate']:.3f})",
        f"weighted kappa (quadratic): {result['kappa_quadratic']:.4f}"
        f"  95% CI [{lo:.4f}, {hi:.4f}]",
        f"labels: mean {result['label_mean']:.3f}, median {result['label_median']:.1f}",
        "confusion (rows = rater 1, cols = rater 2):",
    ]
    for row in result["confusion"]:
        lines.append("  " + " ".join(f"{v:4d}" for v in row))
    lines.append(f"adjudication list (|diff| >= 2): {len(result['adjudication'])}")
    for item in result["adjudication"]:
        lines.append(f"  {item['id']}: rater1={item['rater1']} rater2={item['rater2']}")
    lines.append("per-class rows: " + ", ".join(
        f"{k}={v}" for k, v in sorted(result["per_class_rows"].items())))
    return "\n".join(lines)


def _write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def self_test() -> int:
    import tempfile

    failures: List[str] = []

    def check(name: str, condition: bool) -> None:
        if not condition:
            failures.append(name)

    def expect_error(name: str, fn) -> None:
        try:
            fn()
        except ScoreError:
            return
        failures.append(name)

    # 1. Perfect agreement.
    perfect = [(i, i) for i in range(5)]
    check("perfect kappa == 1", abs(weighted_kappa(perfect) - 1.0) < 1e-12)

    # 2. Hand-computed case: kappa == 0.5 exactly.
    known = [(0, 0), (0, 0), (1, 1), (1, 0)]
    check("known kappa == 0.5", abs(weighted_kappa(known) - 0.5) < 1e-12)

    # 3. Disagreement lowers kappa.
    check("disagreement lowers kappa", weighted_kappa([(0, 4), (4, 0), (0, 0)]) < 0.0)

    # 4. Bootstrap is deterministic and brackets the point estimate.
    lo, hi = bootstrap_ci(known)
    lo2, hi2 = bootstrap_ci(known)
    check("bootstrap deterministic", (lo, hi) == (lo2, hi2))
    check("bootstrap brackets point", lo <= 0.5 <= hi)

    # 5. Confusion matrix sums to n.
    matrix = confusion(known)
    check("confusion sums", sum(sum(r) for r in matrix) == len(known))

    # 6. Label range validation.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        bad = root / "bad.tsv"
        _write(bad, "a\t5\n")
        expect_error("range > 4 rejected", lambda: read_labels(bad))
        _write(bad, "a\t-1\n")
        expect_error("range < 0 rejected", lambda: read_labels(bad))

        # 7. Duplicate id rejected.
        _write(bad, "a\t1\na\t2\n")
        expect_error("duplicate id rejected", lambda: read_labels(bad))

        # 8. Non-integer label rejected.
        _write(bad, "a\tx\n")
        expect_error("non-integer rejected", lambda: read_labels(bad))

        # 9. Key shape.
        key_path = root / "key.tsv"
        _write(key_path, "a\td1\t1\tcalm\nb\td1\t2\tcalm\n")
        key = read_key(key_path)
        check("key parsed", key["a"] == ("d1", 1, "calm"))

        # 10. Coverage: rater 1 must cover the key.
        expect_error(
            "rater1 coverage",
            lambda: validate_coverage(key, {"a": 1}, {"a": 1}),
        )

        # 11. Double subset < 50 is refused.
        small1 = {str(i): 1 for i in range(10)}
        small2 = {str(i): 1 for i in range(10)}
        small_key = {str(i): ("d", 1, "calm") for i in range(10)}
        expect_error(
            "subset < 50 refused",
            lambda: validate_coverage(small_key, small1, small2),
        )

        # 12. Unknown id rejected.
        big_key = {str(i): ("d", 1, "calm") for i in range(60)}
        big1 = {str(i): 1 for i in range(60)}
        big2 = {str(i): 1 for i in range(60)}
        expect_error(
            "unknown id rejected",
            lambda: validate_coverage(big_key, dict(big1, ghost=1), big2),
        )

        # 13. End-to-end on 60 ids: kappa 1.0, no adjudication.
        labels1 = root / "r1.tsv"
        labels2 = root / "r2.tsv"
        _write(labels1, "".join(f"{i}\t{i % 5}\n" for i in range(60)))
        _write(labels2, "".join(f"{i}\t{i % 5}\n" for i in range(60)))
        result = score(big_key, read_labels(labels1), read_labels(labels2))
        check("end-to-end kappa", abs(result["kappa_quadratic"] - 1.0) < 1e-12)
        check("end-to-end adjudication empty", result["adjudication"] == [])
        check("end-to-end exact", result["exact_agreement"] == 60)

        # 15. Adjudication list only for |diff| >= 2.
        _write(labels2, "".join(f"{i}\t{(i + (2 if i == 0 else 0)) % 5}\n" for i in range(60)))
        result = score(big_key, read_labels(labels1), read_labels(labels2))
        check("adjudication one", [x["id"] for x in result["adjudication"]] == ["0"])

    if failures:
        print("SELF-TEST FAILED:")
        for name in failures:
            print(f"  - {name}")
        return 1
    print(f"p1_score self-test OK (15 cases)")
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key")
    parser.add_argument("--rater1")
    parser.add_argument("--rater2")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not (args.key and args.rater1 and args.rater2):
        parser.error("--key, --rater1 and --rater2 are required unless --self-test")

    try:
        key = read_key(Path(args.key))
        rater1 = read_labels(Path(args.rater1))
        rater2 = read_labels(Path(args.rater2))
        result = score(key, rater1, rater2)
    except ScoreError as exc:
        print(f"p1_score: {exc}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(format_report(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
