#!/usr/bin/env python3
"""Golden render snapshots: freeze the strict-mode surface of a fixed corpus.

P3-4 of the 2026-11-20 owner plan.  The repository has thousands of pin
assertions, but almost all of them check *shape* ("the surface contains
X").  None of them let a reader see a whole answer and judge whether it is
adequate.  This tool closes that gap with a small, fixed corpus:

* **strict mode** (``QXFX0_RUNTIME_MODE=strict``);
* **fixed state** — one fresh database per session, turns replayed in
  order, one process per turn (the canonical eval invocation);
* **substrate disabled** — ``QXFX0_BRAIN_KB_PATH`` points at a missing
  file, so the explicit layer only.  The 44 MB ``brain_kb.jsonl`` is
  gitignored, and a snapshot that depended on it could not be reproduced
  on a fresh clone.

The snapshots are *current behaviour*, not a quality endorsement.  A
mismatch means "the surface changed"; read the diff and decide whether the
change is the intended one, then regenerate with ``--write``.  The
``--report`` mode prints the frozen surfaces as a Markdown table for a
human adequacy review.

Eval-only and read-only on the runtime: it invokes ``qxfx0-main`` as a
subprocess and writes only inside its own work directory (and the snapshot
file under ``--write``).  Not on the authority path
(``scripts/eval/NON_AUTHORITY.txt``).

usage::

    scripts/eval/render_snapshots.py --check
    scripts/eval/render_snapshots.py --write
    scripts/eval/render_snapshots.py --report
    scripts/eval/render_snapshots.py --self-test

Exit codes: ``0`` pass, ``1`` mismatch, ``2`` usage/IO/runtime error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CORPUS = ROOT / "spec" / "golden" / "render_snapshots_corpus.tsv"
DEFAULT_SNAPSHOTS = ROOT / "spec" / "golden" / "render_snapshots_2026-11-21.tsv"
CORPUS_COLUMNS = ("id", "session", "turn", "input")
SNAPSHOT_COLUMNS = CORPUS_COLUMNS + ("surface",)
META_PREFIX = "#"
DEFAULT_TIMEOUT = 300


class SnapshotError(Exception):
    """A corpus/snapshot file or a runtime invocation that cannot proceed."""


# --------------------------------------------------------------------------
# Escaping: the surface may contain tabs and newlines, the file is TSV
# --------------------------------------------------------------------------


def escape_field(text: str) -> str:
    """One TSV field: backslash, tab, CR and LF are escaped."""
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        else:
            out.append(ch)
    return "".join(out)


def unescape_field(text: str) -> str:
    """Inverse of :func:`escape_field`; an unknown escape is an error."""
    out = []
    index = 0
    while index < len(text):
        ch = text[index]
        if ch != "\\":
            out.append(ch)
            index += 1
            continue
        if index + 1 >= len(text):
            raise SnapshotError("dangling backslash in escaped field")
        code = text[index + 1]
        if code == "\\":
            out.append("\\")
        elif code == "t":
            out.append("\t")
        elif code == "n":
            out.append("\n")
        elif code == "r":
            out.append("\r")
        else:
            raise SnapshotError(f"unknown escape sequence \\{code}")
        index += 2
    return "".join(out)


# --------------------------------------------------------------------------
# Reading and validating the corpus / snapshot files
# --------------------------------------------------------------------------


def read_data_lines(path: Path) -> list[tuple[int, list[str]]]:
    """Non-comment, non-blank lines with their 1-based line number."""
    if not path.is_file():
        raise SnapshotError(f"file not found: {path}")
    rows = []
    for line_number, raw in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not raw.strip() or raw.startswith(META_PREFIX):
            continue
        rows.append((line_number, raw.split("\t")))
    return rows


def parse_corpus(path: Path) -> list[dict]:
    """Validated corpus rows: unique ids, contiguous 1..n turns per session.

    A session is a fixed state trajectory: turn ``k`` runs against the state
    left by turns ``1..k-1``, so a gap would silently change the starting
    state of every later turn.  Sessions must also stay contiguous in the
    file, otherwise the runner's grouping order is surprising to a reader.
    """
    cases = []
    seen_ids = set()
    last_turn: dict[str, int] = {}
    closed_sessions: set[str] = set()
    current_session = None
    for line_number, fields in read_data_lines(path):
        if tuple(fields) == CORPUS_COLUMNS:
            continue
        if len(fields) != len(CORPUS_COLUMNS):
            raise SnapshotError(
                f"{path}:{line_number}: expected {len(CORPUS_COLUMNS)} columns, "
                f"got {len(fields)}"
            )
        case_id, session, turn_text, input_text = fields
        if not case_id or not session or not input_text:
            raise SnapshotError(f"{path}:{line_number}: empty id/session/input")
        if case_id in seen_ids:
            raise SnapshotError(f"{path}:{line_number}: duplicate id {case_id!r}")
        seen_ids.add(case_id)
        try:
            turn = int(turn_text)
        except ValueError as error:
            raise SnapshotError(
                f"{path}:{line_number}: turn is not an integer: {turn_text!r}"
            ) from error
        if turn < 1:
            raise SnapshotError(f"{path}:{line_number}: turn must be >= 1")
        if session != current_session:
            if current_session is not None:
                closed_sessions.add(current_session)
            if session in closed_sessions:
                raise SnapshotError(
                    f"{path}:{line_number}: session {session!r} reappears after "
                    "another session"
                )
            current_session = session
        expected_turn = last_turn.get(session, 0) + 1
        if turn != expected_turn:
            raise SnapshotError(
                f"{path}:{line_number}: session {session!r} turn {turn}, "
                f"expected {expected_turn}"
            )
        last_turn[session] = turn
        cases.append(
            {"id": case_id, "session": session, "turn": turn, "input": input_text}
        )
    if not cases:
        raise SnapshotError(f"{path}: corpus is empty")
    return cases


def parse_snapshots(path: Path) -> list[dict]:
    """Snapshot rows in file order; the surface is unescaped."""
    rows = []
    seen_ids = set()
    for line_number, fields in read_data_lines(path):
        if tuple(fields) == SNAPSHOT_COLUMNS:
            continue
        if len(fields) != len(SNAPSHOT_COLUMNS):
            raise SnapshotError(
                f"{path}:{line_number}: expected {len(SNAPSHOT_COLUMNS)} columns, "
                f"got {len(fields)}"
            )
        case_id, session, turn_text, input_text, surface_text = fields
        if case_id in seen_ids:
            raise SnapshotError(f"{path}:{line_number}: duplicate id {case_id!r}")
        seen_ids.add(case_id)
        try:
            turn = int(turn_text)
        except ValueError as error:
            raise SnapshotError(
                f"{path}:{line_number}: turn is not an integer: {turn_text!r}"
            ) from error
        rows.append(
            {
                "id": case_id,
                "session": session,
                "turn": turn,
                "input": input_text,
                "surface": unescape_field(surface_text),
            }
        )
    return rows


# --------------------------------------------------------------------------
# Comparison
# --------------------------------------------------------------------------


def first_diff(expected: str, actual: str):
    """(line, column) of the first differing character, or ``None``."""
    expected_lines = expected.splitlines()
    actual_lines = actual.splitlines()
    for line_index in range(max(len(expected_lines), len(actual_lines))):
        left = expected_lines[line_index] if line_index < len(expected_lines) else None
        right = actual_lines[line_index] if line_index < len(actual_lines) else None
        if left == right:
            continue
        if left is None or right is None:
            return line_index + 1, 0
        for column, (a, b) in enumerate(zip(left, right)):
            if a != b:
                return line_index + 1, column + 1
        return line_index + 1, min(len(left), len(right)) + 1
    return None


def compare_rows(expected_rows: list[dict], actual_rows: list[dict]) -> list[dict]:
    """Mismatches by id: missing, extra, changed metadata, changed surface."""
    expected = {row["id"]: row for row in expected_rows}
    actual = {row["id"]: row for row in actual_rows}
    mismatches = []
    for case_id in expected:
        if case_id not in actual:
            mismatches.append({"id": case_id, "kind": "missing"})
    for case_id in actual:
        if case_id not in expected:
            mismatches.append({"id": case_id, "kind": "extra"})
    for case_id in expected:
        if case_id not in actual:
            continue
        left = expected[case_id]
        right = actual[case_id]
        for field in ("session", "turn", "input"):
            if left[field] != right[field]:
                mismatches.append(
                    {
                        "id": case_id,
                        "kind": "metadata",
                        "field": field,
                        "expected": left[field],
                        "actual": right[field],
                    }
                )
        if left["surface"] != right["surface"]:
            mismatches.append(
                {
                    "id": case_id,
                    "kind": "surface",
                    "expected": left["surface"],
                    "actual": right["surface"],
                    "first_diff": first_diff(left["surface"], right["surface"]),
                }
            )
    return mismatches


# --------------------------------------------------------------------------
# Running the corpus
# --------------------------------------------------------------------------


def resolve_binary(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_file():
            raise SnapshotError(f"--bin does not exist: {path}")
        return path
    try:
        result = subprocess.run(
            ["cabal", "list-bin", "qxfx0-main"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        raise SnapshotError(f"cannot run cabal list-bin: {error}") from error
    if result.returncode != 0:
        raise SnapshotError(
            "cabal list-bin qxfx0-main failed:\n" + result.stderr.strip()
        )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if not lines:
        raise SnapshotError("cabal list-bin printed no path")
    path = Path(lines[-1])
    if not path.is_file():
        raise SnapshotError(f"cabal list-bin path does not exist: {path}")
    return path


def parse_surface(stdout: str, case_id: str) -> str:
    """The last JSON object on stdout that carries a string ``surface``."""
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        surface = payload.get("surface")
        if isinstance(surface, str):
            return surface
    raise SnapshotError(f"{case_id}: no JSON object with a string surface on stdout")


def run_corpus(
    cases: list[dict],
    binary: Path,
    workdir: Path,
    timeout: int,
) -> list[dict]:
    """Run every case; one process per turn, one fresh DB per session."""
    if workdir.exists():
        shutil.rmtree(workdir)
    workdir.mkdir(parents=True)
    logs = workdir / "logs"
    logs.mkdir()
    missing_substrate = workdir / "no-brain-kb.jsonl"
    rows = []
    sessions: dict[str, list[dict]] = {}
    for case in cases:
        sessions.setdefault(case["session"], []).append(case)
    for session, session_cases in sessions.items():
        db_path = workdir / f"{session}.db"
        for case in session_cases:
            env = os.environ.copy()
            env["QXFX0_DB"] = str(db_path)
            env["QXFX0_RUNTIME_MODE"] = "strict"
            env["QXFX0_BRAIN_KB_PATH"] = str(missing_substrate)
            env["QXFX0_ROOT"] = str(ROOT)
            try:
                result = subprocess.run(
                    [
                        str(binary),
                        "--session",
                        session,
                        "--input",
                        case["input"],
                        "--json",
                    ],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                    check=False,
                )
            except subprocess.TimeoutExpired as error:
                raise SnapshotError(
                    f"{case['id']}: turn exceeded {timeout}s"
                ) from error
            log_path = logs / f"{case['id']}.err"
            log_path.write_text(result.stderr, encoding="utf-8")
            if result.returncode != 0:
                tail = "\n".join(result.stderr.splitlines()[-20:])
                raise SnapshotError(
                    f"{case['id']}: exit {result.returncode}; stderr tail:\n{tail}"
                )
            surface = parse_surface(result.stdout, case["id"])
            rows.append(
                {
                    "id": case["id"],
                    "session": session,
                    "turn": case["turn"],
                    "input": case["input"],
                    "surface": surface,
                }
            )
    return rows


# --------------------------------------------------------------------------
# Writing and reporting
# --------------------------------------------------------------------------


def write_snapshots(path: Path, rows: list[dict]) -> str:
    lines = [
        "# QxFx0 golden render snapshots — current behaviour, not a quality endorsement.",
        "# mode=strict substrate=disabled (QXFX0_BRAIN_KB_PATH -> missing file)",
        "# generated_by=scripts/eval/render_snapshots.py --write",
        "# columns: id<TAB>session<TAB>turn<TAB>input<TAB>surface (escapes: \\\\ \\t \\n \\r)",
        "\t".join(SNAPSHOT_COLUMNS),
    ]
    for row in rows:
        lines.append(
            "\t".join(
                [
                    row["id"],
                    row["session"],
                    str(row["turn"]),
                    row["input"],
                    escape_field(row["surface"]),
                ]
            )
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def markdown_report(rows: list[dict]) -> str:
    lines = [
        "| id | session/turn | input | frozen surface |",
        "|---|---|---|---|",
    ]
    for row in rows:
        surface = row["surface"].replace("|", "\\|").replace("\n", "<br>")
        lines.append(
            f"| `{row['id']}` | `{row['session']}` / {row['turn']} "
            f"| {row['input']} | {surface} |"
        )
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------


def self_test() -> int:
    cases = []

    def check(label, condition):
        cases.append((label, bool(condition)))

    check("escape leaves plain text", escape_field("abc") == "abc")
    check(
        "escape handles tab/newline/backslash",
        escape_field("a\tb\nc\\d") == "a\\tb\\nc\\\\d",
    )
    check(
        "unescape is the inverse",
        unescape_field(escape_field("a\tb\nc\\d\r")) == "a\tb\nc\\d\r",
    )
    try:
        unescape_field("bad\\q")
        check("unknown escape is rejected", False)
    except SnapshotError:
        check("unknown escape is rejected", True)

    with tempfile.TemporaryDirectory() as temp_dir:
        temp = Path(temp_dir)
        good_corpus = temp / "corpus.tsv"
        good_corpus.write_text(
            "# comment\n"
            "id\tsession\tturn\tinput\n"
            "a\ts1\t1\tпривет\n"
            "b\ts1\t2\tкак жизнь?\n"
            "c\ts2\t1\tхм\n",
            encoding="utf-8",
        )
        parsed = parse_corpus(good_corpus)
        check("corpus parses three rows", len(parsed) == 3)
        check("corpus keeps the session order", [r["session"] for r in parsed] == ["s1", "s1", "s2"])

        duplicate = temp / "duplicate.tsv"
        duplicate.write_text(
            "a\ts1\t1\tx\n" "a\ts1\t2\ty\n", encoding="utf-8"
        )
        try:
            parse_corpus(duplicate)
            check("duplicate id is rejected", False)
        except SnapshotError:
            check("duplicate id is rejected", True)

        gap = temp / "gap.tsv"
        gap.write_text("a\ts1\t2\tx\n", encoding="utf-8")
        try:
            parse_corpus(gap)
            check("turn gap is rejected", False)
        except SnapshotError:
            check("turn gap is rejected", True)

        short = temp / "short.tsv"
        short.write_text("a\ts1\t1\n", encoding="utf-8")
        try:
            parse_corpus(short)
            check("short row is rejected", False)
        except SnapshotError:
            check("short row is rejected", True)

        empty = temp / "empty.tsv"
        empty.write_text("# nothing\n", encoding="utf-8")
        try:
            parse_corpus(empty)
            check("empty corpus is rejected", False)
        except SnapshotError:
            check("empty corpus is rejected", True)

        reopened = temp / "reopened.tsv"
        reopened.write_text(
            "a\ts1\t1\tx\n" "b\ts2\t1\ty\n" "c\ts1\t2\tz\n", encoding="utf-8"
        )
        try:
            parse_corpus(reopened)
            check("reopened session is rejected", False)
        except SnapshotError:
            check("reopened session is rejected", True)

        snapshot_path = temp / "snapshots.tsv"
        digest = write_snapshots(
            snapshot_path,
            [
                {
                    "id": "a",
                    "session": "s1",
                    "turn": 1,
                    "input": "привет",
                    "surface": "строка\tс\nпереносом",
                }
            ],
        )
        check("write returns a sha256", len(digest) == 64)
        round_trip = parse_snapshots(snapshot_path)
        check(
            "snapshot surface round-trips",
            round_trip[0]["surface"] == "строка\tс\nпереносом",
        )

        expected = [
            {"id": "a", "session": "s1", "turn": 1, "input": "x", "surface": "one"}
        ]
        actual_same = [
            {"id": "a", "session": "s1", "turn": 1, "input": "x", "surface": "one"}
        ]
        check("equal rows pass", compare_rows(expected, actual_same) == [])
        actual_changed = [
            {"id": "a", "session": "s1", "turn": 1, "input": "x", "surface": "two"}
        ]
        changed = compare_rows(expected, actual_changed)
        check(
            "surface change is a mismatch",
            len(changed) == 1 and changed[0]["kind"] == "surface",
        )
        check(
            "first_diff locates the change",
            changed[0]["first_diff"] == (1, 1),
        )
        check(
            "missing id is a mismatch",
            compare_rows(expected, [])[0]["kind"] == "missing",
        )
        check(
            "extra id is a mismatch",
            compare_rows([], expected)[0]["kind"] == "extra",
        )
        check(
            "metadata change is a mismatch",
            compare_rows(
                expected,
                [{"id": "a", "session": "s2", "turn": 1, "input": "x", "surface": "one"}],
            )[0]["kind"]
            == "metadata",
        )

    passed = sum(1 for _, ok in cases if ok)
    for label, ok in cases:
        print(("ok   " if ok else "FAIL ") + label)
    print(f"self-test: {passed}/{len(cases)} cases passed")
    return 0 if passed == len(cases) else 1


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Golden render snapshots for a fixed strict-mode corpus."
    )
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--snapshots", type=Path, default=DEFAULT_SNAPSHOTS)
    parser.add_argument("--bin", default=None, help="qxfx0-main path (default: cabal list-bin)")
    parser.add_argument("--workdir", type=Path, default=None, help="state directory (default: temp)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    parser.add_argument("--write", action="store_true", help="run and rewrite the snapshot file")
    parser.add_argument("--check", action="store_true", help="run and compare with the snapshot file")
    parser.add_argument("--report", action="store_true", help="print the frozen surfaces as Markdown")
    parser.add_argument("--self-test", action="store_true", help="run the built-in cases")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    try:
        if args.report:
            rows = parse_snapshots(args.snapshots)
            print(markdown_report(rows))
            return 0
        if not args.write and not args.check:
            parser.print_usage(sys.stderr)
            return 2
        corpus = parse_corpus(args.corpus)
        binary = resolve_binary(args.bin)
        workdir = args.workdir
        temporary = workdir is None
        if temporary:
            workdir = Path(tempfile.mkdtemp(prefix="qxfx0-render-snapshots-"))
        actual = run_corpus(corpus, binary, workdir, args.timeout)
        if args.write:
            digest = write_snapshots(args.snapshots, actual)
            print(f"wrote {len(actual)} snapshots to {args.snapshots}")
            print(f"sha256: {digest}")
            return 0
        expected = parse_snapshots(args.snapshots)
        mismatches = compare_rows(expected, actual)
        if not mismatches:
            print(f"render snapshots: {len(expected)}/{len(expected)} match")
            return 0
        for mismatch in mismatches:
            kind = mismatch["kind"]
            if kind == "surface":
                line, column = mismatch["first_diff"]
                print(
                    f"MISMATCH {mismatch['id']}: surface changed "
                    f"(first diff at line {line}, column {column})"
                )
                print(f"  expected: {mismatch['expected']!r}")
                print(f"  actual:   {mismatch['actual']!r}")
            elif kind == "metadata":
                print(
                    f"MISMATCH {mismatch['id']}: {mismatch['field']} changed "
                    f"({mismatch['expected']!r} -> {mismatch['actual']!r})"
                )
            else:
                print(f"MISMATCH {mismatch['id']}: {kind}")
        print(f"render snapshots: {len(mismatches)} mismatch(es)")
        return 1
    except SnapshotError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
