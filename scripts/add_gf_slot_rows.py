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

Group 2 (``--group2``) cannot be derived from the frozen row: the head hint is
explicitly *not* the relation (``scripts/eval/gf_slot_gap.py``), so 102 rows
need an authored subject/relation/object split. The split lives in
``spec/gf/gf_slot_group2_splits_2026-11-08.tsv``; the tool refuses the batch
unless every group-2 row has exactly one split entry, every ``authored`` row
reconstructs, and every ``deferred`` row carries a reason. Relation and object
ids are reused by surface exactly as in group 1, so a new relation surface is
the only new thing a group-2 row can introduce.

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
SPLITS = "spec/gf/gf_slot_group2_splits_2026-11-08.tsv"
GAP_SHA256 = "10ecdb6a2cfec2ac121f4414a80204c8442babc46a5d7cae1cc66b489765cdc6"
# Group-3 coverage batch: the frozen selection produced by
# `gf_slot_gap.py --select-topics 12 --freeze` (pre-registration
# docs/closure/GF_SLOT_GROUP3_TOPICS_PREREG_2026-11-11.md).
GROUP3_GAP = ROOT / "spec/gf/gf_slot_gap_group3_2026-11-11.tsv"
GROUP3_GAP_SHA256 = "fa5fd7cb1d93cc75ce3bce9ab2d410840d4dc4cf2c9b4f4be83e01ef0b843d87"
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


def read_splits_text(text: str):
    lines = [line for line in text.splitlines() if line.strip() and not line.startswith("#")]
    header, rows = lines[0].split("\t"), [line.split("\t") for line in lines[1:]]
    return header, rows


def derive(generator, slot_rows, gap_rows):
    """Return (candidates, skipped, problems, minted_subjects) without touching the disk.

    Subjects, relations and objects reuse an existing id by surface.  A topic
    with no subject id gets a minted one with the same rule objects already use
    (``unique(slug(transliterate(topic)))``); the minted ids are reported so a
    coverage batch can add topics without hand-editing the table.  The minting
    is deterministic: it follows the frozen gap row order.
    """
    subject_ids, relation_ids, object_ids = {}, {}, {}
    for row in slot_rows:
        subject_ids.setdefault(row[2], row[1])
        relation_ids.setdefault(row[4], row[3])
        object_ids.setdefault(row[6], row[5])

    sources = {row[7] for row in slot_rows}
    predicate_ids = {row[0] for row in slot_rows}
    candidates, skipped, problems = [], [], []
    minted_subjects = []

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
        subject_id = subject_ids.get(topic)
        if subject_id is None:
            subject_id = unique(slug(generator, topic), set(subject_ids.values()))
            subject_ids[topic] = subject_id
            minted_subjects.append((topic, subject_id))
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
            predicate_id, subject_id, topic,
            relation_ids[relation], relation, object_id, obj, surface,
        ])
    return candidates, skipped, problems, minted_subjects


def derive_group2(generator, slot_rows, gap_rows, split_rows):
    """Derive group-2 rows from an authored split file.

    The split file must cover every group-2 row exactly once. A row is either
    ``authored`` (relation_ru/object_ru must reconstruct source_ru) or
    ``deferred`` (schema-incompatible; carries the reason in note). Relations
    and objects reuse an existing id by surface, matching the group-1 rule.
    """
    subject_ids, relation_ids, object_ids = {}, {}, {}
    for row in slot_rows:
        subject_ids.setdefault(row[2], row[1])
        relation_ids.setdefault(row[4], row[3])
        object_ids.setdefault(row[6], row[5])

    sources = {row[7] for row in slot_rows}
    predicate_ids = {row[0] for row in slot_rows}
    gap_by_source = {row[1]: row for row in gap_rows if row[2] == "2"}
    seen = set()
    candidates, skipped, problems = [], [], []

    for split in split_rows:
        if len(split) < 6:
            problems.append(("", f"split row has {len(split)} columns, expected 6"))
            continue
        topic, surface, relation, obj, disposition, note = split[:6]
        if surface not in gap_by_source:
            problems.append((surface, "not a group-2 row in the frozen gap"))
            continue
        if surface in seen:
            problems.append((surface, "duplicate split row"))
            continue
        seen.add(surface)
        gap_topic = gap_by_source[surface][0]
        if topic != gap_topic:
            problems.append((surface, f"topic {topic!r} != gap topic {gap_topic!r}"))
            continue
        if disposition == "deferred":
            skipped.append((surface, f"deferred: {note}"))
            continue
        if disposition != "authored":
            problems.append((surface, f"unknown disposition {disposition!r}"))
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
        relation_id = relation_ids.get(relation)
        if relation_id is None:
            relation_id = unique(slug(generator, relation), set(relation_ids.values()))
            relation_ids[relation] = relation_id
        object_id = object_ids.get(obj)
        if object_id is None:
            object_id = unique(slug(generator, obj), set(object_ids.values()))
            object_ids[obj] = object_id
        predicate_id = unique(slug(generator, surface), predicate_ids)
        predicate_ids.add(predicate_id)
        candidates.append([
            predicate_id, subject_ids[topic], topic,
            relation_id, relation, object_id, obj, surface,
        ])

    for source in gap_by_source:
        if source not in seen:
            problems.append((source, "group-2 row has no split entry"))
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
        + "свобода\tсвобода вдохновляет\t2\t\t\tnew_relation_required\n"
        + "свобода\tсвобода предполагает возможность выбора\t1\tпредполагает\tвозможность выбора\trelation_exists\n"
        + "чужое\tчужое предполагает нечто\t1\tпредполагает\tнечто\trelation_exists\n"
    )
    case("gap rows parsed", len(gap_rows) == 5)

    candidates, skipped, problems, minted = derive(generator, slot_rows, gap_rows)
    case("group 1 only", [row[7] for row in candidates] == ["свобода предполагает новую рамку", "чужое предполагает нечто"], str(candidates))
    case("group 2 skipped", any(reason.startswith("group 2") for _, reason in skipped), str(skipped))
    case("present row skipped", any(reason == "present" for _, reason in skipped), str(skipped))
    case("unknown subject is minted, not refused", minted == [("чужое", "chuzhoe")], str(minted))
    case("no problems when the subject is new", not problems, str(problems))
    case("relation id reused", candidates[0][3] == "predpolagaet", str(candidates[0]))
    case("subject id reused", candidates[0][1] == "svoboda", str(candidates[0]))
    case("minted subject id used", candidates[1][1] == "chuzhoe", str(candidates[1]))
    case("object id derived", candidates[0][5] == "novuyu_ramku", str(candidates[0]))
    case("predicate id derived", candidates[0][0].startswith("svoboda_predpolagaet"), str(candidates[0]))
    case("reconstruction holds", candidates[0][7] == "свобода предполагает новую рамку")
    again = derive(generator, slot_rows, gap_rows)
    case("minting is deterministic", again[0] == candidates and again[3] == minted)

    case("slug collapses", slug(generator, "то, что не может быть проверено") == "to_chto_ne_mozhet_byt_provereno",
         slug(generator, "то, что не может быть проверено"))
    case("unique suffixes", unique("x", {"x", "x_2"}) == "x_3")
    case("unique leaves free id", unique("y", {"x"}) == "y")
    case("render is tab separated", render([["a", "b"]]) == "a\tb\n")

    split_header, split_rows = read_splits_text(
        "\n".join([
            "\t".join(["topic", "source_ru", "relation_ru", "object_ru", "disposition", "note"]),
            "свобода\tсвобода раскрывается через выбор\tраскрывается\tчерез выбор\tauthored\t",
            "свобода\tсвобода вдохновляет\t\t\tdeferred\tintransitive verb; no object slot",
        ])
    )
    case("split header parsed", split_header == ["topic", "source_ru", "relation_ru", "object_ru", "disposition", "note"])
    g2_candidates, g2_skipped, g2_problems = derive_group2(generator, slot_rows, gap_rows, split_rows)
    case("group2 authored row derived", [row[7] for row in g2_candidates] == ["свобода раскрывается через выбор"], str(g2_candidates))
    case("group2 deferred skipped", any(reason.startswith("deferred:") for _, reason in g2_skipped), str(g2_skipped))
    case("group2 relation id derived", g2_candidates[0][3] == "raskryvaetsya", str(g2_candidates[0]))
    case("group2 object id derived", g2_candidates[0][5] == "cherez_vybor", str(g2_candidates[0]))
    case("group2 reconstruction holds", g2_candidates[0][7] == "свобода раскрывается через выбор")
    case("group2 no problems on full coverage", not g2_problems, str(g2_problems))

    missing_candidates, _, missing_problems = derive_group2(
        generator, slot_rows, gap_rows, split_rows[:1]
    )
    case("group2 missing coverage refused", any("no split entry" in reason for _, reason in missing_problems), str(missing_problems))
    case("group2 missing coverage yields one row", len(missing_candidates) == 1, str(missing_candidates))

    bad_reconstruction = [list(row) for row in split_rows]
    bad_reconstruction[0][3] = "выбор"
    _, _, bad_problems = derive_group2(generator, slot_rows, gap_rows, bad_reconstruction)
    case("group2 bad reconstruction refused", any("does not reconstruct" in reason for _, reason in bad_problems), str(bad_problems))

    unknown = [list(row) for row in split_rows]
    unknown[0][1] = "свобода неизвестная строка"
    _, _, unknown_problems = derive_group2(generator, slot_rows, gap_rows, unknown)
    case("group2 unknown surface refused", any("not a group-2 row" in reason for _, reason in unknown_problems), str(unknown_problems))

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--slots", default=SLOTS, help="slot table to extend")
    parser.add_argument("--gap", default=GAP, help="frozen slot-gap TSV")
    parser.add_argument(
        "--splits",
        default=None,
        help=f"authored group-2 split file (default: {SPLITS} when --group2 is given)",
    )
    parser.add_argument(
        "--group2",
        action="store_true",
        help="derive group-2 rows from the authored split file instead of group 1",
    )
    parser.add_argument("--apply", action="store_true", help="append the derived rows")
    parser.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    import hashlib

    slots_path = Path(args.slots) if Path(args.slots).is_absolute() else ROOT / args.slots
    gap_path = Path(args.gap) if Path(args.gap).is_absolute() else ROOT / args.gap
    splits_arg = args.splits or (SPLITS if args.group2 else None)
    splits_path = (
        Path(splits_arg) if splits_arg and Path(splits_arg).is_absolute()
        else (ROOT / splits_arg if splits_arg else None)
    )
    for path in (slots_path, gap_path):
        if not path.exists():
            print(f"INVALID: missing {path}", file=sys.stderr)
            return 2
    if splits_path is not None and not splits_path.exists():
        print(f"INVALID: missing {splits_path}", file=sys.stderr)
        return 2
    gap_digest = hashlib.sha256(gap_path.read_bytes()).hexdigest()
    if args.gap == GAP and gap_digest != GAP_SHA256:
        print(f"INVALID: gap file sha256 {gap_digest} != frozen {GAP_SHA256}", file=sys.stderr)
        return 2
    if gap_path.resolve() == GROUP3_GAP.resolve() and gap_digest != GROUP3_GAP_SHA256:
        print(f"INVALID: group-3 gap sha256 {gap_digest} != frozen {GROUP3_GAP_SHA256}", file=sys.stderr)
        return 2

    generator = load_generator()
    _, slot_rows = read_slots_text(slots_path.read_text(encoding="utf-8"))
    _, gap_rows = read_gap_text(gap_path.read_text(encoding="utf-8"))
    minted = []
    if splits_path is None:
        candidates, skipped, problems, minted = derive(generator, slot_rows, gap_rows)
    else:
        split_header, split_rows = read_splits_text(splits_path.read_text(encoding="utf-8"))
        expected = ["topic", "source_ru", "relation_ru", "object_ru", "disposition", "note"]
        if split_header != expected:
            print(f"INVALID: split header {split_header} != {expected}", file=sys.stderr)
            return 2
        candidates, skipped, problems = derive_group2(generator, slot_rows, gap_rows, split_rows)

    print(f"slot rows: {len(slot_rows)}  gap rows: {len(gap_rows)}")
    print(f"candidates: {len(candidates)}  skipped: {len(skipped)}  problems: {len(problems)}  minted subjects: {len(minted)}")
    for topic, subject_id in minted:
        print(f"  MINT {topic!r} -> {subject_id!r}")
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
