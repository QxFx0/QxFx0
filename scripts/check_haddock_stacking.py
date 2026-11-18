#!/usr/bin/env python3
"""Rule [25]: no stacked Haddock '-- |' blocks before one declaration.

A group of comment lines that contains two or more '-- |' block starts and
is followed by a declaration means only the last block is attached; every
earlier block is silently dropped by Haddock. That is how the rationale for
the Conatus weights and the per-type docs for ConatusComponents /
ConatusEnergy / ConatusGradient were lost.

Lines inside a Haddock code block ('-- @' ... '-- @', '-- >') are not
counted, so ASCII diagrams cannot trip the rule.

Without --baseline every finding is a violation. With --baseline the rule
demands an exact match against docs/closure/HADDOCK_STACKING_BASELINE.tsv:
a new site fails, a changed block count fails, and an entry that no longer
matches fails. The baseline is debt, not a permit.
"""
import contextlib
import io
import re
import sys
import tempfile
from pathlib import Path

DOC_START = re.compile(r"^\s*--\s*\|")
COMMENT = re.compile(r"^\s*--")
CODE_FENCE = re.compile(r"^\s*--\s*@\s*$")
CODE_LINE = re.compile(r"^\s*--\s*(>|>>>)")


def scan(roots):
    findings = []
    for root in roots:
        root_path = Path(root)
        if not root_path.is_dir():
            continue
        for path in sorted(root_path.rglob("*.hs")):
            try:
                lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            first = None
            blocks = 0
            in_code = False
            for line_no, line in enumerate(lines, 1):
                if not line.strip() or COMMENT.match(line):
                    if CODE_FENCE.match(line):
                        in_code = not in_code
                    elif not in_code and not CODE_LINE.match(line) and DOC_START.match(line):
                        if blocks == 0:
                            first = line_no
                        blocks += 1
                    continue
                in_code = False
                if blocks > 1:
                    findings.append((path, first, line_no, blocks, line.strip()))
                first = None
                blocks = 0
            if blocks > 1:
                findings.append((path, first, len(lines), blocks, "<eof>"))
    return findings


def load_baseline(path):
    entries = {}
    for raw in Path(path).read_text(encoding="utf-8").splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        parts = raw.split("\t")
        if len(parts) != 3:
            raise SystemExit(f"baseline: malformed line (want path<TAB>declaration<TAB>blocks): {raw!r}")
        rel, decl, count = parts
        try:
            count = int(count)
        except ValueError:
            raise SystemExit(f"baseline: non-integer block count: {raw!r}")
        key = (rel, decl)
        if key in entries:
            raise SystemExit(f"baseline: duplicate entry: {raw!r}")
        entries[key] = count
    return entries


def compare(findings, base_dir, baseline=None):
    violations = []
    seen = set()
    for path, first, decl, blocks, decl_text in findings:
        try:
            rel = path.relative_to(base_dir).as_posix()
        except ValueError:
            rel = path.as_posix()
        key = (rel, decl_text)
        seen.add(key)
        if baseline is None:
            violations.append(
                f"{rel}:{first}: {blocks} consecutive Haddock blocks before one declaration "
                f"(next code line {decl})"
            )
            continue
        expected = baseline.get(key)
        if expected is None:
            violations.append(
                f"{rel}:{first}: {blocks} consecutive Haddock blocks before one declaration "
                f"(next code line {decl}); not in HADDOCK_STACKING_BASELINE.tsv"
            )
        elif expected != blocks:
            violations.append(
                f"{rel}:{first}: {blocks} consecutive Haddock blocks before one declaration "
                f"(baseline records {expected}); update HADDOCK_STACKING_BASELINE.tsv"
            )
    if baseline is not None:
        for (rel, decl_text), expected in baseline.items():
            if (rel, decl_text) not in seen:
                violations.append(
                    f"{rel}: baseline entry for {decl_text!r} ({expected} blocks) no longer matches; "
                    f"shrink HADDOCK_STACKING_BASELINE.tsv"
                )
    return violations


def selftest():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "tree"
        root.mkdir()
        stacked = root / "Stacked.hs"
        stacked.write_text(
            "module M where\n"
            "\n"
            "-- | First block, silently dropped.\n"
            "-- | Second block, attached.\n"
            "f :: Int\n"
            "f = 1\n",
            encoding="utf-8",
        )
        single_dir = Path(tmp) / "single"
        single_dir.mkdir()
        single = single_dir / "Single.hs"
        single.write_text(
            "module M where\n"
            "\n"
            "-- | One block, attached.\n"
            "g :: Int\n"
            "g = 1\n",
            encoding="utf-8",
        )
        diagram_dir = Path(tmp) / "diagram"
        diagram_dir.mkdir()
        (diagram_dir / "Diagram.hs").write_text(
            "module D where\n"
            "\n"
            "-- | A diagram, not a second block:\n"
            "--\n"
            "-- @\n"
            "--   case x of\n"
            "--     (m, r) | r > 0 -> m\n"
            "-- @\n"
            "h :: Int\n"
            "h = 1\n",
            encoding="utf-8",
        )

        findings = scan([str(root)])
        if len(findings) != 1 or findings[0][3] != 2 or findings[0][1] != 3:
            print(f"detector: expected 1 finding at line 3 with 2 blocks, got {findings}", file=sys.stderr)
            return 1
        if scan([str(single_dir)]):
            print("detector: single block must not be flagged", file=sys.stderr)
            return 1
        if scan([str(diagram_dir)]):
            print("detector: ASCII diagram inside '-- @' must not be flagged", file=sys.stderr)
            return 1

        exact = compare(findings, root, {("Stacked.hs", "f :: Int"): 2})
        if exact:
            print(f"baseline: exact match must be clean, got {exact}", file=sys.stderr)
            return 1
        mismatch = compare(findings, root, {("Stacked.hs", "f :: Int"): 3})
        if len(mismatch) != 1:
            print(f"baseline: count mismatch must fail once, got {mismatch}", file=sys.stderr)
            return 1
        stale = compare(findings, root, {("Stacked.hs", "g :: Int"): 2})
        if len(stale) != 2:
            print(f"baseline: stale entry must fail (new + stale), got {stale}", file=sys.stderr)
            return 1
        no_baseline = compare(findings, root)
        if len(no_baseline) != 1:
            print(f"no-baseline mode: every finding must be a violation, got {no_baseline}", file=sys.stderr)
            return 1

        # The entry point is part of the contract: a detector that drops its
        # first path argument would pass the scan-level checks above and never
        # flag anything in CI.
        quiet = io.StringIO()
        with contextlib.redirect_stdout(quiet):
            stacked_exit = main([str(root)])
            single_exit = main([str(single_dir)])
        if stacked_exit != 1:
            print("entry point: stacked fixture must exit 1", file=sys.stderr)
            return 1
        if single_exit != 0:
            print("entry point: single fixture must exit 0", file=sys.stderr)
            return 1
        return 0


def main(argv):
    if "--self-test" in argv:
        return selftest()
    baseline_path = None
    roots = []
    i = 0
    while i < len(argv):
        if argv[i] == "--baseline":
            if i + 1 >= len(argv):
                print("usage: check_haddock_stacking.py [--baseline FILE] ROOT...", file=sys.stderr)
                return 2
            baseline_path = argv[i + 1]
            i += 2
        else:
            roots.append(argv[i])
            i += 1
    if not roots:
        print("usage: check_haddock_stacking.py [--baseline FILE] ROOT...", file=sys.stderr)
        return 2
    baseline = load_baseline(baseline_path) if baseline_path else None
    violations = compare(scan(roots), Path(roots[0]).parent, baseline)
    for v in violations:
        print(v)
    if not violations and baseline is not None:
        print(f"rule [25]: {len(baseline)} baselined stacked-doc site(s), 0 new")
    return 1 if violations else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
