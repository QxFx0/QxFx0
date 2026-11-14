#!/usr/bin/env python3
"""Compare two M7 run directories (determinism or regression vs a baseline).

M7 runs live under ``reports/eval_runs/<run_id>/`` and are produced by
``scripts/run_m7_batch.sh``.  Two comparisons matter:

* **run vs replica** — bar 5 of the GF slot group-2 result: does the same
  packet render the same predicate and the same surface twice?
* **baseline vs candidate** — did a landing change predicate choice or the
  surface on the bounded 30-prompt packet?

Both reduce to the same two comparisons over the recorded rows:
``derivation_rules`` (the selected predicate chain) and the rendered surface,
taken from the last parseable JSON line of ``raw/<id>.log``.  The RTS report
from ``QXFX0_EVAL_RTS_ARGS`` lands in that same file and must be skipped.

This tool mechanizes what used to be an inline Python block in
``run_m7_batch.sh`` (replica leg) and an ad-hoc script in the gitignored
``reports/`` tree (baseline leg) — the latter is exactly the loss class the
M7 harness itself already suffered once.

Eval-only and read-only: it opens no database, writes no artifact, and is not
on the runtime authority path (``scripts/eval/NON_AUTHORITY.txt``).

usage::

    scripts/eval/m7_compare.py <baseline_dir> <candidate_dir>
    scripts/eval/m7_compare.py --self-test

Exit codes: ``0`` pass, ``1`` comparison failed, ``2`` usage/IO error.

Pre-registration context: ``docs/closure/GF_SLOT_BATCH_GROUP2_RESULT_2026-11-09.md``
(bar 5) and ``docs/closure/PREPARE_FALLBACK_PREREG_2026-11-12.md`` (bar A4).
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

RESULTS_NAME = "results.jsonl"
RAW_DIR = "raw"


class CompareError(Exception):
    """A run directory that cannot be compared at all (usage/IO error)."""


# --------------------------------------------------------------------------
# Reading a run
# --------------------------------------------------------------------------


def read_rows(run_dir):
    """``{row_id: row}`` from ``results.jsonl``; duplicate ids are an error."""
    path = Path(run_dir) / RESULTS_NAME
    if not path.is_file():
        raise CompareError(f"missing {RESULTS_NAME} in {run_dir}")
    rows = {}
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as error:
                raise CompareError(f"{path}:{number}: invalid JSON: {error}")
            row_id = row.get("id")
            if not row_id:
                raise CompareError(f"{path}:{number}: row has no id")
            if row_id in rows:
                raise CompareError(f"{path}:{number}: duplicate id {row_id!r}")
            rows[row_id] = row
    return rows


def read_surface(run_dir, row_id):
    """The rendered surface for ``row_id``, or ``None`` when the log is absent.

    The eval appends an optional RTS report to the same log, so the surface is
    the last line that parses as a JSON object and carries ``response``/``text``.
    """
    path = Path(run_dir) / RAW_DIR / f"{row_id}.log"
    if not path.is_file():
        return None
    raw = path.read_text(encoding="utf-8", errors="replace")
    for line in reversed(raw.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(payload, dict):
            continue
        surface = payload.get("response") or payload.get("text")
        return "" if surface is None else str(surface)
    return ""


# --------------------------------------------------------------------------
# Comparison
# --------------------------------------------------------------------------


def compare(baseline_dir, candidate_dir):
    """Compare two run directories; returns a JSON-able result dict."""
    baseline_dir, candidate_dir = Path(baseline_dir), Path(candidate_dir)
    base_rows = read_rows(baseline_dir)
    cand_rows = read_rows(candidate_dir)

    row_set_mismatch = sorted(set(base_rows) ^ set(cand_rows))
    predicate_mismatch = []
    surface_mismatch = []
    missing_raw = []
    for row_id in sorted(set(base_rows) & set(cand_rows)):
        if base_rows[row_id].get("derivation_rules") != cand_rows[row_id].get(
            "derivation_rules"
        ):
            predicate_mismatch.append(row_id)
        base_surface = read_surface(baseline_dir, row_id)
        cand_surface = read_surface(candidate_dir, row_id)
        if base_surface is None or cand_surface is None:
            # A missing raw log is not "empty surface": the comparison is
            # blind there, and a blind comparison must not report PASS.
            missing_raw.append(row_id)
        elif base_surface != cand_surface:
            surface_mismatch.append(row_id)

    total = len(set(base_rows) & set(cand_rows))
    verdict = (
        total > 0
        and not row_set_mismatch
        and not predicate_mismatch
        and not surface_mismatch
        and not missing_raw
    )
    return {
        "baseline": str(baseline_dir),
        "candidate": str(candidate_dir),
        "rows_compared": total,
        "row_set_mismatch": row_set_mismatch,
        "predicate_mismatch": predicate_mismatch,
        "surface_mismatch": surface_mismatch,
        "missing_raw": missing_raw,
        "verdict": "PASS" if verdict else "FAIL",
        "passed": verdict,
    }


def render(result, verdict_name="determinism"):
    lines = [
        f"baseline: {result['baseline']}",
        f"candidate: {result['candidate']}",
        f"rows compared: {result['rows_compared']}",
    ]
    for key, label in (
        ("row_set_mismatch", "row set mismatch"),
        ("predicate_mismatch", "predicate mismatches"),
        ("surface_mismatch", "surface mismatches"),
        ("missing_raw", "missing raw logs"),
    ):
        ids = result[key]
        suffix = f" ({', '.join(ids)})" if ids else ""
        lines.append(f"{label}: {len(ids)}{suffix}")
    lines.append(f"{verdict_name}: {result['verdict']}")
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------

CASES = []


def case(name):
    def register(fn):
        CASES.append((name, fn))
        return fn

    return register


def write_run(root, rows, surfaces=None, skip_raw=()):
    """Build a synthetic run directory.

    ``rows`` maps row id to ``derivation_rules``; ``surfaces`` maps row id to
    the response text (default: ``surface-<id>``); ``skip_raw`` omits the log.
    """
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    with (root / RESULTS_NAME).open("w", encoding="utf-8") as handle:
        for row_id, rules in rows.items():
            handle.write(
                json.dumps({"id": row_id, "derivation_rules": rules}) + "\n"
            )
    (root / RAW_DIR).mkdir(exist_ok=True)
    surfaces = surfaces or {}
    for row_id in rows:
        if row_id in skip_raw:
            continue
        payload = {"status": "ok", "response": surfaces.get(row_id, f"surface-{row_id}")}
        (root / RAW_DIR / f"{row_id}.log").write_text(
            json.dumps(payload) + "\n", encoding="utf-8"
        )
    return root


def with_runs(fn):
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        fn(tmp / "base", tmp / "cand")


@case("identical runs pass")
def _case_identical():
    def body(base, cand):
        rows = {"r1": ["DeriveSelectedPredicate"], "r2": ["DeriveContrast"]}
        write_run(base, rows)
        write_run(cand, rows)
        result = compare(base, cand)
        assert result["passed"] is True, result
        assert result["rows_compared"] == 2
        assert result["predicate_mismatch"] == []
        assert result["surface_mismatch"] == []

    with_runs(body)


@case("row set mismatch fails and names the ids")
def _case_row_set():
    def body(base, cand):
        write_run(base, {"r1": [], "r2": []})
        write_run(cand, {"r1": [], "r3": []})
        result = compare(base, cand)
        assert result["passed"] is False
        assert result["row_set_mismatch"] == ["r2", "r3"], result

    with_runs(body)


@case("predicate mismatch fails")
def _case_predicate():
    def body(base, cand):
        write_run(base, {"r1": ["DeriveSelectedPredicate"]})
        write_run(cand, {"r1": ["DeriveGfMappedFallback"]})
        result = compare(base, cand)
        assert result["passed"] is False
        assert result["predicate_mismatch"] == ["r1"]

    with_runs(body)


@case("surface mismatch fails")
def _case_surface():
    def body(base, cand):
        write_run(base, {"r1": []}, surfaces={"r1": "alpha"})
        write_run(cand, {"r1": []}, surfaces={"r1": "beta"})
        result = compare(base, cand)
        assert result["passed"] is False
        assert result["surface_mismatch"] == ["r1"]

    with_runs(body)


@case("RTS noise before the payload is skipped")
def _case_rts_noise():
    def body(base, cand):
        write_run(base, {"r1": []}, surfaces={"r1": "alpha"})
        write_run(cand, {"r1": []}, surfaces={"r1": "alpha"})
        log = cand / RAW_DIR / "r1.log"
        log.write_text(
            "some preamble\n" + json.dumps({"response": "alpha"}) + "\n"
            "   1,234,567 bytes allocated in the heap\n",
            encoding="utf-8",
        )
        result = compare(base, cand)
        assert result["passed"] is True, result

    with_runs(body)


@case("missing raw log fails the comparison")
def _case_missing_raw():
    def body(base, cand):
        write_run(base, {"r1": []})
        write_run(cand, {"r1": []}, skip_raw=("r1",))
        result = compare(base, cand)
        assert result["passed"] is False
        assert result["missing_raw"] == ["r1"], result

    with_runs(body)


@case("empty results fail")
def _case_empty():
    def body(base, cand):
        write_run(base, {})
        write_run(cand, {})
        result = compare(base, cand)
        assert result["passed"] is False
        assert result["rows_compared"] == 0

    with_runs(body)


@case("missing results.jsonl is an error")
def _case_missing_results():
    def body(base, cand):
        base.mkdir(parents=True)
        write_run(cand, {"r1": []})
        try:
            compare(base, cand)
        except CompareError as error:
            assert RESULTS_NAME in str(error)
        else:
            raise AssertionError("expected CompareError")

    with_runs(body)


@case("duplicate ids are an error")
def _case_duplicate_ids():
    def body(base, cand):
        write_run(base, {"r1": []})
        write_run(cand, {"r1": []})
        with (cand / RESULTS_NAME).open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({"id": "r1", "derivation_rules": []}) + "\n")
        try:
            compare(base, cand)
        except CompareError as error:
            assert "duplicate" in str(error)
        else:
            raise AssertionError("expected CompareError")

    with_runs(body)


@case("render names the verdict and the counts")
def _case_render():
    def body(base, cand):
        write_run(base, {"r1": []})
        write_run(cand, {"r1": []})
        text = render(compare(base, cand), verdict_name="regression-vs-baseline")
        assert "regression-vs-baseline: PASS" in text
        assert "rows compared: 1" in text

    with_runs(body)


def self_test():
    failures = 0
    for name, fn in CASES:
        try:
            fn()
        except AssertionError as error:
            failures += 1
            print(f"FAIL {name}: {error}")
        else:
            print(f"ok   {name}")
    total = len(CASES)
    print(f"\n{total - failures}/{total} cases passed")
    return 0 if failures == 0 else 2


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Compare two M7 run directories (predicate + surface)."
    )
    parser.add_argument("baseline", nargs="?", help="baseline run directory")
    parser.add_argument("candidate", nargs="?", help="candidate run directory")
    parser.add_argument(
        "--verdict-name",
        default="determinism",
        help="label of the final verdict line (default: determinism)",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--self-test", action="store_true", help="run the built-in cases")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.baseline or not args.candidate:
        parser.print_usage(sys.stderr)
        return 2
    try:
        result = compare(args.baseline, args.candidate)
    except CompareError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(render(result, verdict_name=args.verdict_name))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
