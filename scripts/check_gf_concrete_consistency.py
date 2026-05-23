#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ABSTRACT = ROOT / "spec/gf/QxFx0Syntax.gf"
CONCRETES = [
    ROOT / "spec/gf/QxFx0SyntaxRus.gf",
    ROOT / "spec/gf/QxFx0SyntaxEng.gf",
    ROOT / "spec/gf/QxFx0SyntaxRusColloquial.gf",
]


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


def main() -> int:
    abstract = parse_abstract(ABSTRACT)
    failed = False
    for concrete in CONCRETES:
        entries = parse_concrete(concrete)
        missing = sorted(set(abstract) - set(entries))
        extra = sorted(set(entries) - set(abstract))
        bad_arity = sorted(
            name for name in abstract
            if name in entries and abstract[name] != entries[name]
        )
        if missing or extra or bad_arity:
            failed = True
            print(f"GF_CONCRETE_DRIFT: {concrete.relative_to(ROOT)}", file=sys.stderr)
            if missing:
                print(f"  missing: {', '.join(missing)}", file=sys.stderr)
            if extra:
                print(f"  extra: {', '.join(extra)}", file=sys.stderr)
            if bad_arity:
                pairs = ", ".join(f"{name} abstract={abstract[name]} concrete={entries[name]}" for name in bad_arity)
                print(f"  arity: {pairs}", file=sys.stderr)
    if failed:
        return 1
    print("GF concrete consistency check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
