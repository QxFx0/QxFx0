#!/usr/bin/env python3
"""GF concrete/abstract consistency check.

Only the *compiled* concrete is authoritative: ``scripts/compile_gf_grammar.sh``
builds ``QxFx0SyntaxRus.gf`` and never the legacy ``QxFx0SyntaxEng.gf`` /
``QxFx0SyntaxRusColloquial.gf`` stubs (40/290 functions each, no semantic
layer).  Checking the stubs made this tool permanently red for a known
non-defect, which meant it could not flag a *new* Rus drift
(``DIALOGUE_PILOT50_RESULT_2026-11-02.md`` open question 7).

Default scope: the compiled Rus concrete.  ``--all-concretes`` checks every
concrete and is expected to fail on the legacy stubs; it exists so the known
state stays measurable instead of being silently ignored.

``--self-test`` runs the embedded cases (missing / extra / arity / pass /
determinism / real-tree Rus check).  They live here rather than in a test file
because the repository forbids test-only Python
(``PYTHON_SUPPLIER_ALLOWLIST.md`` §5).
"""
import argparse
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ABSTRACT = ROOT / "spec/gf/QxFx0Syntax.gf"
RUS = ROOT / "spec/gf/QxFx0SyntaxRus.gf"
LEGACY_STUBS = [
    ROOT / "spec/gf/QxFx0SyntaxEng.gf",
    ROOT / "spec/gf/QxFx0SyntaxRusColloquial.gf",
]
DEFAULT_CONCRETES = [RUS]


def parse_abstract(path: Path):
    text = path.read_text(encoding="utf-8")
    result = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("--"):
            continue
        m = re.match(r"^([A-Za-z0-9_']+)\s*:\s*(.+);$", line)
        if not m:
            continue
        name, sig = m.groups()
        result[name] = sig.count("->")
    return result


def parse_concrete(path: Path):
    text = path.read_text(encoding="utf-8")
    result = {}
    in_lin = False
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("--"):
            continue
        if line == "lin" or (line.startswith("lin") and line.endswith("{")):
            in_lin = True
            continue
        if not in_lin:
            continue
        if line == "}":
            in_lin = False
            continue
        m = re.match(r"^([A-Za-z0-9_']+)(.*?)=", line)
        if not m:
            continue
        name, args = m.groups()
        args = [tok for tok in args.strip().split() if tok]
        if name and name[0].isupper():
            result[name] = len(args)
    return result


def compare(abstract, concrete):
    """Pure diff of one concrete against the abstract syntax."""
    missing = sorted(set(abstract) - set(concrete))
    extra = sorted(set(concrete) - set(abstract))
    bad_arity = sorted(
        (name, abstract[name], concrete[name])
        for name in abstract
        if name in concrete and abstract[name] != concrete[name]
    )
    return {"missing": missing, "extra": extra, "arity": bad_arity}


def is_clean(result):
    return not (result["missing"] or result["extra"] or result["arity"])


def check_paths(abstract_path: Path, concrete_paths):
    abstract = parse_abstract(abstract_path)
    return [(path, compare(abstract, parse_concrete(path))) for path in concrete_paths]


def report(results, stream=sys.stderr):
    """Print every drift; return True when at least one concrete drifted."""
    failed = False
    for path, result in results:
        if is_clean(result):
            continue
        failed = True
        print(f"GF_CONCRETE_DRIFT: {path}", file=stream)
        if result["missing"]:
            print(f"  missing: {', '.join(result['missing'])}", file=stream)
        if result["extra"]:
            print(f"  extra: {', '.join(result['extra'])}", file=stream)
        if result["arity"]:
            pairs = ", ".join(
                f"{name} abstract={abstract} concrete={concrete}"
                for name, abstract, concrete in result["arity"]
            )
            print(f"  arity: {pairs}", file=stream)
    return failed


def describe_scope(paths):
    names = ", ".join(path.name for path in paths)
    skipped = [path.name for path in LEGACY_STUBS if path not in paths]
    scope = f"checked: {names}"
    if skipped:
        scope += f"; legacy stubs skipped: {', '.join(skipped)}"
    return scope


def run_check(abstract_path: Path, concrete_paths) -> int:
    results = check_paths(abstract_path, concrete_paths)
    if report(results):
        return 1
    print(f"GF concrete consistency check passed ({describe_scope(concrete_paths)})")
    return 0


def self_test():
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    abstract = {"A": 2, "B": 1}
    case("compare pass", is_clean(compare(abstract, {"A": 2, "B": 1})))
    case("missing detected", compare(abstract, {"A": 2})["missing"] == ["B"])
    case("extra detected", compare(abstract, {"A": 2, "B": 1, "C": 0})["extra"] == ["C"])
    case("arity detected",
         compare(abstract, {"A": 1, "B": 1})["arity"] == [("A", 2, 1)])

    abstract_text = """A : X -> Y -> Z;
B : X -> Y;
"""
    concrete_text = """lin
{
  A x y = { s = x.s ++ y.s } ;
  B x = { s = x.s } ;
}
"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        abs_path = tmp / "Abs.gf"
        good = tmp / "Good.gf"
        bad = tmp / "Bad.gf"
        abs_path.write_text(abstract_text, encoding="utf-8")
        good.write_text(concrete_text, encoding="utf-8")
        bad.write_text(concrete_text.replace("  B x =", "  -- B removed\n  --"), encoding="utf-8")

        parsed_abs = parse_abstract(abs_path)
        parsed_good = parse_concrete(good)
        case("parse abstract", parsed_abs == {"A": 2, "B": 1}, f"{parsed_abs}")
        case("parse concrete", parsed_good == {"A": 2, "B": 1}, f"{parsed_good}")
        case("parse deterministic",
             parse_concrete(good) == parse_concrete(good))
        case("good file clean", is_clean(compare(parsed_abs, parsed_good)))
        case("bad file missing",
             compare(parsed_abs, parse_concrete(bad))["missing"] == ["B"])

        # The CLI's default scope is the compiled Rus concrete only; the
        # legacy stubs must not be able to turn the default check red.
        case("default scope is Rus only", DEFAULT_CONCRETES == [RUS])
        case("legacy stubs are not in default scope",
             all(path not in DEFAULT_CONCRETES for path in LEGACY_STUBS))

        # Real-tree check: a new Rus drift must fail the self-test too.
        if RUS.exists() and ABSTRACT.exists():
            real = check_paths(ABSTRACT, [RUS])
            case("real Rus concrete is consistent",
                 all(is_clean(result) for _, result in real),
                 "run the tool without --self-test for the drift detail")

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--all-concretes", action="store_true",
                    help="check every concrete, including the legacy stubs (expected red)")
    ap.add_argument("--concrete", action="append", default=None,
                    help="check a specific concrete file (repeatable)")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.concrete:
        paths = [Path(p) if Path(p).is_absolute() else ROOT / p for p in args.concrete]
    elif args.all_concretes:
        paths = [RUS, *LEGACY_STUBS]
    else:
        paths = DEFAULT_CONCRETES
    return run_check(ABSTRACT, paths)


if __name__ == "__main__":
    raise SystemExit(main())
