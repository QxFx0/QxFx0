#!/usr/bin/env python3
"""Pre-flight contract check for prompt files read by run_dialogue_eval_200.sh.

The harness reads a prompt file positionally:

    while IFS=$'\\t' read -r id prompt expected_family

so a packet with more columns is silently misread: the second column becomes
the prompt. On 2026-11-02 the frozen five-column pilot packet
(`id, split, topic, prompt, expected_family`) was passed to the harness and
produced 50 one-word "prompts" (the split labels), 50 English template
answers, and zero reported errors -- a fully invalid run that looked
successful. See `docs/closure/DIALOGUE_PILOT50_RESULT_2026-11-02.md`
(Deviations 1-2).

This checker turns that silent misread into a loud pre-flight refusal. It runs
before the run directory is created, so a refused file leaves no partial run
artifacts behind.

Contract enforced:

  1. every data line has exactly three tab-separated fields;
  2. `id`, `prompt` and `expected_family` are non-empty;
  3. the prompt column is not a split label (`anchor`, `held`, `oov`, ...);
  4. ids are unique.

Blank lines, `#` comments and a leading `id<TAB>...` header are skipped.

Exit codes: 0 admissible, 1 refused, 2 usage error.
`--self-test` runs the embedded cases and exits 0 (all pass) or 1.
"""
import argparse
import sys
from pathlib import Path

COLUMNS = 3
HEADER_FIRST_FIELD = "id"
MAX_REPORTED = 10

# Split labels used by the frozen pilot and release packets. A prompt equal to
# one of these is a column-mapping defect, never a real question.
SPLIT_LABELS = frozenset({"anchor", "held", "oov", "oos", "seed", "dev", "test"})


def check(path):
    """Return a list of contract problems; empty list means admissible."""
    problems = []
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError as exc:
        return [f"cannot read {path}: {exc}"]

    seen = {}
    data_lines = 0
    first_data_line = True
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip("\r")
        if not line.strip():
            continue
        if line.lstrip().startswith("#"):
            continue
        data_lines += 1

        fields = line.split("\t")
        if len(fields) != COLUMNS:
            problems.append(
                f"line {lineno}: {len(fields)} tab-separated columns, expected "
                f"{COLUMNS} (the harness reads id, prompt, expected_family; a "
                f"wider packet sends column 2 as the prompt)"
            )
            continue

        rid, prompt, family = (field.strip() for field in fields)
        if first_data_line and rid == HEADER_FIRST_FIELD:
            first_data_line = False
            continue
        first_data_line = False

        if not rid:
            problems.append(f"line {lineno}: empty id")
        if not prompt:
            problems.append(f"line {lineno}: empty prompt")
        elif prompt.lower() in SPLIT_LABELS:
            problems.append(
                f"line {lineno}: prompt is the split label {prompt!r}, not a "
                f"prompt (wrong column mapping?)"
            )
        if not family:
            problems.append(f"line {lineno}: empty expected_family")

        if rid:
            if rid in seen:
                problems.append(
                    f"line {lineno}: duplicate id {rid!r} (first at line {seen[rid]})"
                )
            else:
                seen[rid] = lineno

    if data_lines == 0:
        problems.append("no data rows")
    return problems


def self_test():
    """Embedded cases. Kept here because the repository forbids test-only
    Python files (docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md, section 5)."""
    import tempfile

    header = "id\tprompt\texpected_family\n"
    cases = [
        (
            "valid three-column packet",
            header + "a\tчто такое свобода?\tCMDefine\nb\tчто такое долг?\tCMDefine\n",
            [],
        ),
        (
            "five-column packet is refused",
            "id\tsplit\ttopic\tprompt\texpected_family\n"
            "a\tanchor\tсвобода\tчто такое свобода?\tCMDefine\n",
            ["5 tab-separated columns"],
        ),
        (
            "split label in the prompt column is refused",
            header + "a\tanchor\tCMDefine\n",
            ["split label"],
        ),
        (
            "empty prompt is refused",
            header + "a\t \tCMDefine\n",
            ["empty prompt"],
        ),
        (
            "duplicate id is refused",
            header + "a\tчто такое свобода?\tCMDefine\n"
            "a\tчто такое долг?\tCMDefine\n",
            ["duplicate id"],
        ),
        (
            "comments, blank lines and no trailing newline are accepted",
            "# packet comment\na\tчто такое свобода?\tCMDefine\n\n",
            [],
        ),
        (
            "empty file is refused",
            "",
            ["no data rows"],
        ),
        (
            "CRLF is tolerated",
            "a\tчто такое свобода?\tCMDefine\r\n",
            [],
        ),
    ]

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, body, expected in cases:
            path = Path(tmp) / "case.tsv"
            path.write_text(body, encoding="utf-8", newline="")
            problems = check(path)
            joined = " | ".join(problems)
            if expected:
                missing = [needle for needle in expected if needle not in joined]
                ok = bool(problems) and not missing
            else:
                ok = not problems
            status = "ok  " if ok else "FAIL"
            print(f"{status} {name}")
            if not ok:
                failures += 1
                print(f"      expected {expected!r}, got {problems!r}")

    print(f"\nself-test: {len(cases) - failures}/{len(cases)} passed")
    return 0 if failures == 0 else 1


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Check a prompt file against the eval harness column contract."
    )
    ap.add_argument("path", nargs="?", help="prompt TSV to validate")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.path:
        ap.error("a prompt file path is required (or --self-test)")

    problems = check(args.path)
    if problems:
        print(f"prompt file refused: {args.path}", file=sys.stderr)
        for problem in problems[:MAX_REPORTED]:
            print(f"  {problem}", file=sys.stderr)
        hidden = len(problems) - MAX_REPORTED
        if hidden > 0:
            print(f"  ... {hidden} more problem(s) not shown", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
