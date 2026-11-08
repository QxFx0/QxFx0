#!/usr/bin/env python3
"""Derive slot-table rows from the frozen GF slot-gap list.

Why this exists: the group-1 batch is 123 rows whose subject, relation and
object strings are already fixed by
``spec/gf/gf_slot_gap_2026-11-06.tsv`` (sha256
``10ecdb6a2cfec2ac121f4414a80204c8442babc46a5d7cae1cc66b489765cdc6``). Typing
them by hand would re-introduce exactly the failure this repository already
paid for once: a scope measured by an uncommitted method. The tool derives every
field mechanically, prints the rows for review, and only writes with
``--apply``.

Derivation rules (all deterministic, no judgement):

- ``subject_ru`` / ``relation_ru`` / ``object_ru`` come from the frozen row;
- ``subject_id`` / ``relation_id`` are reused from the existing slot table, so a
  surface never acquires a second id (a duplicate id is what makes a GF
  round-trip ambiguous — see the 4-point checker's baseline);
- ``object_id`` is ``transliterate(object_ru)`` with ``_`` collapsed; if that id
  is already taken by a *different* surface, a numeric suffix is appended;
- ``predicate_id`` is ``transliterate(source_ru)``, truncated and suffixed the
  same way on collision;
- the row is refused unless ``subject_ru + " " + relation_ru + " " +
  object_ru`` reconstructs ``source_ru`` byte for byte.

``--apply`` appends in frozen-file order, which is already topic-grouped. Rows
that are already present are reported as ``present`` and skipped, so the tool is
idempotent and safe to re-run after a partial landing.

It creates no slots on its own, edits no corpus file, and does not touch the GF
grammar: regeneration stays with ``scripts/export_lexicon.py``.
"""
from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SLOTS = "spec/gf/curated_predicate_slots.tsv"
GAP = "spec/gf/gf_slot_gap_2026-11-06.tsv"
GAP_SHA256 = "10ecdb6a2cfec2ac121f4414a80204c8442babc46a5d7cae1cc66b489765cdc6"
COLUMNS = [
    "predicate_id", "subject_id", "subject_ru",
    "relation_id", "relation_ru", "object_id", "object_ru", "source_ru",
]


def load_generator():
    path = ROOT / "scripts/export_lexicon.py"
    spec = importlib.util.spec_from_file_location("qxfx0_export_lexicon", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["qxfx0_export_lexicon"] = module
    spec.loader.exec_module(module)
    return module


def slug(generator, text: str, limit: int = 80) -> str:
    base = re.sub(r"_+", "_", generator.transliterate(text)).strip("_")
    return (base or "slot")[:limit].strip("_")


def unique(base: str, taken) -> str:
    if base not in taken:
        return base
    index = 2
    while f"{base}_{index}" in taken:
        index += 1
    return f"{base}_{index}"


def read_slots_text(text: str):
    lines = [line for line in text.splitlines() if line.strip() and not line.startswith("#")]
    header, rows = lines[0].split("\t"), [line.split("\t") for line in lines[1:]]
    return header, rows


def read_gap_text(text: str):
    lines = [line for line in text.splitlines() if line.strip()]
    header, rows = lines[0].split("\t"), [line.split("\t") for line in lines[1:]]
    return header, rows


def derive(generator, slot_rows, gap_rows):
    """Return (candidates, skipped, problems) without touching the disk."""
    subject_ids, relation_ids, object_ids = {}, {}, {}
    for row in slot_rows:
        subject_ids.setdefault(row[2], row[1])
        relation_ids.setdefault(row[4], row[3])
        object_ids.setdefault(row[6], row[5])

    sources = {row[7] for row in slot_rows}
    predicate_ids = {row[0] for row in slot_rows}
    candidates, skipped, problems = [], [], []

    for gap in gap_rows:
        topic, surface, group, relation, obj = gap[0], gap[1], gap[2], gap[3], gap[4]
        if group != "1":
            skipped.append((surface, f"group {group} (not this batch)"))
            continue
        if surface in sources:
            skipped.append((surface, "present"))
            continue
        if surface != f"{topic} {relation} {obj}":
            problems.append((surface, "row does not reconstruct from topic/relation/object"))
            continue
        if topic not in subject_ids:
            problems.append((surface, f"subject {topic!r} has no existing id"))
            continue
        if relation not in relation_ids:
            problems.append((surface, f"relation {relation!r} has no existing id"))
            continue
        object_id = object_ids.get(obj)
        if object_id is None:
            object_id = unique(slug(generator, obj), set(object_ids.values()))
        elif object_ids.get(obj) != object_id:
            problems.append((surface, f"object {obj!r} maps to two ids"))
            continue
        predicate_id = unique(slug(generator, surface), predicate_ids)
        predicate_ids.add(predicate_id)
        candidates.append([
            predicate_id, subject_ids[topic], topic,
            relation_ids[relation], relation, object_id, obj, surface,
        ])
    return candidates, skipped, problems


def render(candidates) -> str:
    return "".join("\t".join(row) + "\n" for row in candidates)


def self_test() -> int:
    generator = load_generator()
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    header, slot_rows = read_slots_text(
        "\n".join([
            "\t".join(COLUMNS),
            "freedom_choice\tsvoboda\tсвобода\tpredpolagaet\tпредполагает\tvozmozhnost_vybora\tвозможность выбора\tсвобода предполагает возможность выбора",
        ])
    )
    case("slot header parsed", header == COLUMNS)
    case("slot rows parsed", len(slot_rows) == 1, str(slot_rows))

    gap_header, gap_rows = read_gap_text(
        "\t".join(["topic", "source_ru", "group", "matched_relation", "object", "note"]) + "\n"
        + "свобода\tсвобода предполагает новую рамку\t1\tпредполагает\tновую рамку\trelation_exists\n"
        + "свобода\tсвобода раскрывается через выбор\t2\t\t\tnew_relation_required\n"
        + "свобода\tсвобода предполагает возможность выбора\t1\tпредполагает\tвозможность выбора\trelation_exists\n"
        + "чужое\tчужое предполагает нечто\t1\tпредполагает\tнечто\trelation_exists\n"
    )
    case("gap rows parsed", len(gap_rows) == 4)

    candidates, skipped, problems = derive(generator, slot_rows, gap_rows)
    case("group 1 only", [row[7] for row in candidates] == ["свобода предполагает новую рамку"], str(candidates))
    case("group 2 skipped", any(reason.startswith("group 2") for _, reason in skipped), str(skipped))
    case("present row skipped", any(reason == "present" for _, reason in skipped), str(skipped))
    case("unknown subject refused", any("has no existing id" in reason for _, reason in problems), str(problems))
    case("relation id reused", candidates[0][3] == "predpolagaet", str(candidates[0]))
    case("subject id reused", candidates[0][1] == "svoboda", str(candidates[0]))
    case("object id derived", candidates[0][5] == "novuyu_ramku", str(candidates[0]))
    case("predicate id derived", candidates[0][0].startswith("svoboda_predpolagaet"), str(candidates[0]))
    case("reconstruction holds", candidates[0][7] == "свобода предполагает новую рамку")

    case("slug collapses", slug(generator, "то, что не может быть проверено") == "to_chto_ne_mozhet_byt_provereno",
         slug(generator, "то, что не может быть проверено"))
    case("unique suffixes", unique("x", {"x", "x_2"}) == "x_3")
    case("unique leaves free id", unique("y", {"x"}) == "y")
    case("render is tab separated", render([["a", "b"]]) == "a\tb\n")

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--slots", default=SLOTS, help="slot table to extend")
    parser.add_argument("--gap", default=GAP, help="frozen slot-gap TSV")
    parser.add_argument("--apply", action="store_true", help="append the derived rows")
    parser.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    import hashlib

    slots_path = Path(args.slots) if Path(args.slots).is_absolute() else ROOT / args.slots
    gap_path = Path(args.gap) if Path(args.gap).is_absolute() else ROOT / args.gap
    for path in (slots_path, gap_path):
        if not path.exists():
            print(f"INVALID: missing {path}", file=sys.stderr)
            return 2
    gap_digest = hashlib.sha256(gap_path.read_bytes()).hexdigest()
    if args.gap == GAP and gap_digest != GAP_SHA256:
        print(f"INVALID: gap file sha256 {gap_digest} != frozen {GAP_SHA256}", file=sys.stderr)
        return 2

    generator = load_generator()
    _, slot_rows = read_slots_text(slots_path.read_text(encoding="utf-8"))
    _, gap_rows = read_gap_text(gap_path.read_text(encoding="utf-8"))
    candidates, skipped, problems = derive(generator, slot_rows, gap_rows)

    print(f"slot rows: {len(slot_rows)}  gap rows: {len(gap_rows)}")
    print(f"candidates: {len(candidates)}  skipped: {len(skipped)}  problems: {len(problems)}")
    for surface, reason in problems:
        print(f"  PROBLEM {surface!r}: {reason}")
    for surface, reason in skipped:
        if reason != "present" and not reason.startswith("group 2"):
            print(f"  SKIP {surface!r}: {reason}")
    print()
    print(render(candidates), end="")

    if problems:
        print("\nrefusing to apply while problems are open", file=sys.stderr)
        return 1
    if args.apply:
        with slots_path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(render(candidates))
        print(f"\nappended {len(candidates)} rows to {args.slots}")
        print("next: scripts/export_lexicon.py, then the 4-point checker")
    else:
        print("\ndry run; pass --apply to append")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
