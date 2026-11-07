#!/usr/bin/env python3
"""Mechanical 4-point realizability check for GF slot rows.

Pre-registered in ``docs/closure/GF_SLOT_COVERAGE_PREREG_DRAFT_2026-11-01.md``
(§ "Every candidate row must satisfy, mechanically"). Bar 4 of S2 is
"new rows that fail the 4-point realizability check = 0", so the check has to
exist as a tool before rows can be authored against it.

The four points, and how each is mechanized:

1. **constructors exist.** As written the prereg names ``QxFx0Lexicon*.gf``, but
   slot constructors are not lexicon lexemes: ``scripts/export_lexicon.py``
   generates ``Subject*``/``Relation*``/``Object*`` from
   ``spec/gf/curated_predicate_slots.tsv`` into ``QxFx0Syntax.gf`` and
   ``QxFx0SyntaxRus.gf``. Read literally the point rejects every multiword
   object, including all 84 pre-existing rows, so the check is: each id appears
   as the generated constructor in both syntax files, and the table's
   id-to-surface mapping is one-to-one in both directions. The dated correction
   in the prereg records this.
2. **generated Haskell carries the row.** The expected ``SemanticSlots.hs`` is
   rendered from the same TSV and compared with the file on disk (stale
   generation fails), then the row's ``CuratedPredicateSlots`` line must be
   present.
3. **GF round-trip.** The syntax files are rendered into a temp directory with
   the repo's own generator, compiled with ``gf --make
   --startcat=SemanticProposition``, and for every row the tree linearizes
   byte-identically to ``source_ru`` and ``source_ru`` parses back to the same
   tree. Nothing is written into the repository.
4. **byte identity with the corpus.** ``subject_ru + " " + relation_ru + " " +
   object_ru`` must reconstruct ``source_ru`` exactly; with ``--dump`` the
   surface must also be present in the merged runtime corpus dump (the same
   ``topic<TAB>surface`` format ``scripts/eval/gf_slot_gap.py`` consumes).

Nothing here creates slots, edits a corpus file, or changes the 500-prompt or
M7 gates. ``--self-test`` runs the pure cases and needs neither GF nor a
Haskell build; the cases live in the tool because the repository forbids
test-only Python (``PYTHON_SUPPLIER_ALLOWLIST.md`` §5).

**Known-failure baseline.** The check is red at HEAD for two defects that
predate the batch (a duplicated object id and the round-trip it breaks), and a
checker that is permanently red cannot flag a new regression — the criticism
point 3 of the prereg makes about the old GF checker. ``--write-baseline``
freezes the current failure set as a ``point<TAB>surface`` TSV plus a sha256
sidecar, and ``--baseline`` then exits 0 only while the failure set matches it
exactly: a new failure *or* a pinned entry that stopped failing both fail the
run, so the baseline cannot rot silently.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SLOTS_SOURCE = "spec/gf/curated_predicate_slots.tsv"
SYNTAX_ABSTRACT = "spec/gf/QxFx0Syntax.gf"
SYNTAX_CONCRETE = "spec/gf/QxFx0SyntaxRus.gf"
SEMANTIC_SLOTS_HS = "src/QxFx0/Lexicon/Generated/SemanticSlots.hs"
LEXICON_FILES = ("spec/gf/QxFx0Lexicon.gf", "spec/gf/QxFx0LexiconRus.gf")

POINTS = ("constructors", "generated_haskell", "gf_round_trip", "corpus_identity")


def load_generator():
    """Import ``scripts/export_lexicon.py`` as the single source of truth."""
    path = ROOT / "scripts/export_lexicon.py"
    spec = importlib.util.spec_from_file_location("qxfx0_export_lexicon", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["qxfx0_export_lexicon"] = module
    spec.loader.exec_module(module)
    return module


def read_slots(generator, path: Path):
    """Load slot rows through the generator's own loader (same rules as export)."""
    previous = generator.CURATED_PREDICATE_SLOTS
    generator.CURATED_PREDICATE_SLOTS = path
    try:
        return generator.load_curated_predicate_slots()
    finally:
        generator.CURATED_PREDICATE_SLOTS = previous


def constructor(prefix: str, slot_id: str) -> str:
    return prefix + "".join(part.capitalize() for part in slot_id.split("_"))


def tree_of(row) -> str:
    return (
        f"MkSemanticPredicate {constructor('Subject', row.subject_id)} "
        f"{constructor('Relation', row.relation_id)} "
        f"{constructor('Object', row.object_id)}"
    )


def mapping_conflicts(rows):
    """Report ids mapped to several surfaces and surfaces mapped to several ids."""
    problems = []
    for field_id, field_ru in (
        ("subject_id", "subject_ru"),
        ("relation_id", "relation_ru"),
        ("object_id", "object_ru"),
    ):
        by_id, by_ru = {}, {}
        for row in rows:
            slot_id, surface = getattr(row, field_id), getattr(row, field_ru)
            by_id.setdefault(slot_id, set()).add(surface)
            by_ru.setdefault(surface, set()).add(slot_id)
        for slot_id, surfaces in sorted(by_id.items()):
            if len(surfaces) > 1:
                problems.append(
                    f"{field_id} {slot_id!r} maps to several surfaces: {sorted(surfaces)}"
                )
        for surface, ids in sorted(by_ru.items()):
            if len(ids) > 1:
                problems.append(
                    f"{field_ru} {surface!r} maps to several ids: {sorted(ids)}"
                )
    return problems


def reconstruction_error(row):
    """Point 4a: the three slots must concatenate back to ``source_ru``."""
    assembled = f"{row.subject_ru} {row.relation_ru} {row.object_ru}"
    if assembled != row.source_ru:
        return f"reconstructed {assembled!r} != source_ru {row.source_ru!r}"
    return None


def check_constructors(rows, abstract_text, concrete_text, on_disk=None):
    """Point 1: every id appears as a generated constructor in both syntax files.

    ``on_disk`` (abstract, concrete) also catches the authoring failure mode
    where the TSV was edited but the syntax files were never regenerated.
    """
    failures = []
    if on_disk is not None:
        disk_abstract, disk_concrete = on_disk
        if abstract_text != disk_abstract:
            failures.append(
                ("<all rows>", f"{SYNTAX_ABSTRACT} is stale; run scripts/export_lexicon.py")
            )
        if concrete_text != disk_concrete:
            failures.append(
                ("<all rows>", f"{SYNTAX_CONCRETE} is stale; run scripts/export_lexicon.py")
            )
    for row in rows:
        for prefix, slot_id in (
            ("Subject", row.subject_id),
            ("Relation", row.relation_id),
            ("Object", row.object_id),
        ):
            name = constructor(prefix, slot_id)
            for label, text in (("abstract", abstract_text), ("concrete", concrete_text)):
                if not re.search(rf"\b{re.escape(name)}\b", text):
                    failures.append((row.source_ru, f"{label} syntax lacks {name}"))
    return failures


def check_generated_haskell(rows, expected_text, on_disk_text):
    """Point 2: generated file is current and carries every row."""
    failures = []
    if expected_text != on_disk_text:
        failures.append(
            ("<all rows>", "generated SemanticSlots.hs is stale; run scripts/export_lexicon.py")
        )
    for row in rows:
        expected_line = (
            f'CuratedPredicateSlots "{row.source_ru}" '
            f'"{constructor("Subject", row.subject_id)}" '
            f'"{constructor("Relation", row.relation_id)}" '
            f'"{constructor("Object", row.object_id)}"'
        )
        if expected_line not in on_disk_text:
            failures.append((row.source_ru, "row missing from generated SemanticSlots.hs"))
    return failures


def compare_round_trip(rows, results):
    """Point 3: linearization equals ``source_ru`` and parsing returns the tree."""
    failures = []
    for row, (linearized, parsed) in zip(rows, results):
        if linearized != row.source_ru:
            failures.append(
                (row.source_ru, f"linearized {linearized!r} != source_ru")
            )
        elif parsed != tree_of(row):
            failures.append((row.source_ru, f"parsed {parsed!r} != {tree_of(row)!r}"))
    return failures


def round_trip(generator, rows, argued_leaves):
    """Render + compile once, then one process per row so output cannot shift.

    ``gf --run`` separates command outputs with blank lines and prints nothing
    for some failures, so pairing the whole batch positionally silently
    misaligns every row after the first hiccup. One process per row costs about
    0.2 s and makes the mapping exact.
    """
    abstract, concrete = generator.render_gf_syntax_files(rows, argued_leaves)
    env = {
        "PATH": f"{Path.home()}/.cabal/bin:/usr/bin:/bin",
        "HOME": str(Path.home()),
    }
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for relative in LEXICON_FILES:
            (work / Path(relative).name).write_bytes((ROOT / relative).read_bytes())
        (work / Path(SYNTAX_ABSTRACT).name).write_text(abstract, encoding="utf-8")
        (work / Path(SYNTAX_CONCRETE).name).write_text(concrete, encoding="utf-8")
        build = subprocess.run(
            ["gf", "--make", "--startcat=SemanticProposition", Path(SYNTAX_CONCRETE).name],
            cwd=work, capture_output=True, text=True, env=env,
        )
        if build.returncode != 0:
            raise RuntimeError(f"gf build failed:\n{build.stdout[-2000:]}\n{build.stderr[-2000:]}")
        pgf = str(work / "QxFx0Syntax.pgf")
        results = []
        for row in rows:
            script = (
                f"l {tree_of(row)}\n"
                'p "' + row.source_ru.replace('"', '\\"') + '"\n'
                "q\n"
            )
            run = subprocess.run(
                ["gf", "--run", pgf], input=script,
                capture_output=True, text=True, env=env,
            )
            lines = [line for line in run.stdout.splitlines() if line.strip()]
            if run.returncode != 0:
                raise RuntimeError(
                    f"gf run failed for {row.source_ru!r}:\n{run.stdout[-1000:]}\n{run.stderr[-1000:]}"
                )
            results.append((lines[0] if lines else "", lines[1] if len(lines) > 1 else ""))
        return results


def read_dump(path: Path):
    pairs = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if "\t" not in line:
            continue
        topic, _, surface = line.partition("\t")
        topic, surface = topic.strip(), surface.strip()
        if topic and surface:
            pairs.add((topic, surface))
    return pairs


def check_corpus(rows, pairs):
    """Point 4b: the surface must be an actual corpus predicate of that topic."""
    failures = []
    for row in rows:
        if (row.subject_ru, row.source_ru) not in pairs:
            failures.append(
                (row.source_ru, f"not a predicate of topic {row.subject_ru!r} in the dump")
            )
    return failures


def report(failures_by_point, rows, skipped):
    total = len(rows)
    print(f"slot rows checked: {total}")
    bad = 0
    for point in POINTS:
        if point in skipped:
            print(f"  {point}: SKIPPED ({skipped[point]})")
            continue
        failures = failures_by_point.get(point, [])
        row_failures = [item for item in failures if not item[0].startswith("<")]
        table_failures = [item for item in failures if item[0].startswith("<")]
        bad += len(failures)
        status = "PASS" if not failures else "FAIL"
        print(f"  {point}: {status} ({total - len(row_failures)}/{total} rows)")
        for surface, reason in (row_failures + table_failures)[:20]:
            print(f"    FAIL {surface!r}: {reason}")
        if len(failures) > 20:
            print(f"    ... and {len(failures) - 20} more")
    print(f"\nverdict: {'PASS' if bad == 0 else 'FAIL'}")
    return 0 if bad == 0 else 1


def failure_keys(failures_by_point):
    """Stable (point, surface) keys: the reason text is informational only."""
    return sorted(
        (point, surface)
        for point, failures in failures_by_point.items()
        for surface, _reason in failures
    )


def render_baseline(keys):
    return "point\tsurface\n" + "".join(f"{point}\t{surface}\n" for point, surface in keys)


def read_baseline(path: Path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines()[1:]:
        if not line.strip():
            continue
        point, _, surface = line.partition("\t")
        rows.append((point, surface))
    return sorted(rows)


def freeze_baseline(path: Path, keys):
    payload = render_baseline(keys).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    path.with_name(path.name + ".sha256").write_text(
        f"{digest}  {path.name}\n", encoding="utf-8"
    )
    return digest


def compare_baseline(current, baseline):
    """Return (new_failures, stale_entries).

    A checker that is permanently red for a known reason cannot flag a new
    regression — the same criticism the prereg makes about the old GF checker.
    Pinning the known set keeps HEAD green while any addition is loud.
    """
    current_set, baseline_set = set(current), set(baseline)
    return sorted(current_set - baseline_set), sorted(baseline_set - current_set)


def self_test() -> int:
    generator = load_generator()
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    def row(pid="p", sid="bytie", sru="бытие", rid="est", rru="есть",
            oid="osnovanie", oru="основание", source="бытие есть основание"):
        return generator.CuratedPredicateSlots(pid, sid, sru, rid, rru, oid, oru, source)

    good = row()
    case("constructor names", constructor("Object", "vozmozhnost_vybora") == "ObjectVozmozhnostVybora")
    case("tree shape",
         tree_of(good) == "MkSemanticPredicate SubjectBytie RelationEst ObjectOsnovanie",
         tree_of(good))
    case("reconstruction ok", reconstruction_error(good) is None, str(reconstruction_error(good)))
    case("reconstruction fails on drift",
         reconstruction_error(row(oru="основания")) is not None)

    conflicts = mapping_conflicts([good, row(pid="q", oid="osnovanie_2", source="бытие есть основание2")])
    case("surface with two ids flagged", any("several ids" in c for c in conflicts), str(conflicts))
    case("clean table has no conflicts", mapping_conflicts([good]) == [])

    abstract = "    SubjectBytie : SemanticSubject ;\n    RelationEst : SemanticRelation ;\n    ObjectOsnovanie : SemanticObject ;"
    concrete = "    SubjectBytie = { s = \"бытие\" } ;\n    RelationEst = { s = \"есть\" } ;\n    ObjectOsnovanie = { s = \"основание\" } ;"
    case("constructors pass", check_constructors([good], abstract, concrete) == [])
    case("missing constructor flagged",
         check_constructors([good], abstract.replace("ObjectOsnovanie", "ObjectOther"), concrete) != [])
    case("stale syntax files flagged",
         check_constructors([good], abstract, concrete, (abstract + "\n", concrete)) != [])
    case("current syntax files pass",
         check_constructors([good], abstract, concrete, (abstract, concrete)) == [])

    generated = '    CuratedPredicateSlots "бытие есть основание" "SubjectBytie" "RelationEst" "ObjectOsnovanie",'
    case("generated row found", check_generated_haskell([good], generated, generated) == [])
    case("stale generated flagged",
         check_generated_haskell([good], generated + "\n", generated) != [])
    case("missing generated row flagged",
         check_generated_haskell([good], generated, generated.replace("ObjectOsnovanie", "ObjectOther")) != [])

    outputs = [("бытие есть основание", tree_of(good))]
    case("round-trip pass", compare_round_trip([good], outputs) == [])
    case("round-trip linearization drift flagged",
         compare_round_trip([good], [("бытие есть основания", tree_of(good))]) != [])
    case("round-trip parse drift flagged",
         compare_round_trip([good], [("бытие есть основание", "MkSemanticPredicate SubjectBytie RelationEst ObjectOther")]) != [])
    case("round-trip empty output flagged",
         compare_round_trip([good], [("", "")]) != [])

    pairs = {("бытие", "бытие есть основание")}
    case("corpus membership pass", check_corpus([good], pairs) == [])
    case("corpus membership flagged", check_corpus([good], set()) != [])

    keys = failure_keys({"constructors": [("<table>", "dup id")], "gf_round_trip": [("s", "r")]})
    case("failure keys are stable pairs", keys == [("constructors", "<table>"), ("gf_round_trip", "s")], str(keys))
    case("baseline identical", compare_baseline(keys, keys) == ([], []))
    case("baseline new failure detected",
         compare_baseline(keys + [("corpus_identity", "x")], keys)[0] == [("corpus_identity", "x")])
    case("baseline stale entry detected",
         compare_baseline(keys, keys + [("corpus_identity", "gone")])[1] == [("corpus_identity", "gone")])

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "baseline.tsv"
        digest_a = freeze_baseline(path, keys)
        digest_b = freeze_baseline(path, keys)
        case("baseline freeze deterministic", digest_a == digest_b)
        case("baseline sidecar written", path.with_name(path.name + ".sha256").exists())
        case("baseline reads back", read_baseline(path) == keys, str(read_baseline(path)))
        case("baseline digest matches payload",
             hashlib.sha256(path.read_bytes()).hexdigest() == digest_a)

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--slots", default=SLOTS_SOURCE, help="slot table to check")
    parser.add_argument("--dump", help="corpus dump (topic<TAB>surface) for point 4b")
    parser.add_argument("--baseline", help="known-failure list (TSV + .sha256) to diff against")
    parser.add_argument("--write-baseline", help="freeze the current failures here")
    parser.add_argument("--no-gf", action="store_true", help="skip the GF round-trip")
    parser.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    generator = load_generator()
    slots_path = Path(args.slots) if Path(args.slots).is_absolute() else ROOT / args.slots
    if not slots_path.exists():
        print(f"INVALID: missing slot table {slots_path}", file=sys.stderr)
        return 2
    try:
        rows = read_slots(generator, slots_path)
        argued = generator.load_argued_leaf_slots()
    except ValueError as error:
        print(f"INVALID: {error}", file=sys.stderr)
        return 2

    failures = {}
    failures["corpus_identity"] = [
        (row.source_ru, reason)
        for row, reason in ((row, reconstruction_error(row)) for row in rows)
        if reason
    ]
    skipped = {}

    if args.dump:
        failures["corpus_identity"] += check_corpus(rows, read_dump(Path(args.dump)))
    else:
        skipped["corpus_identity"] = "no --dump given; only reconstruction was checked"

    abstract, concrete = generator.render_gf_syntax_files(rows, argued)
    on_disk = (
        (ROOT / SYNTAX_ABSTRACT).read_text(encoding="utf-8")
        if (ROOT / SYNTAX_ABSTRACT).exists() else "",
        (ROOT / SYNTAX_CONCRETE).read_text(encoding="utf-8")
        if (ROOT / SYNTAX_CONCRETE).exists() else "",
    )
    failures["constructors"] = check_constructors(rows, abstract, concrete, on_disk)
    conflicts = mapping_conflicts(rows)
    failures["constructors"] += [("<table>", conflict) for conflict in conflicts]

    expected_hs = generator.render_haskell_semantic_slots(rows, argued)
    disk_path = ROOT / SEMANTIC_SLOTS_HS
    on_disk = disk_path.read_text(encoding="utf-8") if disk_path.exists() else ""
    failures["generated_haskell"] = check_generated_haskell(rows, expected_hs, on_disk)

    if args.no_gf:
        skipped["gf_round_trip"] = "--no-gf"
    else:
        try:
            results = round_trip(generator, rows, argued)
        except (RuntimeError, FileNotFoundError) as error:
            print(f"INVALID: {error}", file=sys.stderr)
            return 2
        failures["gf_round_trip"] = compare_round_trip(rows, results)

    keys = failure_keys(failures)
    if args.write_baseline:
        digest = freeze_baseline(Path(args.write_baseline), keys)
        print(f"baseline written: {args.write_baseline} ({len(keys)} known failures)")
        print(f"baseline sha256: {digest}")

    verdict = report(failures, rows, skipped)

    if args.baseline:
        baseline_path = Path(args.baseline)
        if not baseline_path.exists():
            print(f"\nINVALID: missing baseline {baseline_path}", file=sys.stderr)
            return 2
        baseline_digest = hashlib.sha256(baseline_path.read_bytes()).hexdigest()
        baseline_rows = read_baseline(baseline_path)
        new_failures, stale = compare_baseline(keys, baseline_rows)
        print(f"\nbaseline {baseline_path.name}: {len(keys)} failures now, "
              f"{len(baseline_rows)} pinned, sha256 {baseline_digest}")
        for point, surface in new_failures:
            print(f"  NEW  {point}: {surface!r}")
        for point, surface in stale:
            print(f"  STALE {point}: {surface!r} (no longer failing; prune the baseline)")
        if new_failures or stale:
            print("baseline verdict: FAIL")
            return 1
        print("baseline verdict: PASS (matches the pinned known set)")
        return 0

    return verdict


if __name__ == "__main__":
    raise SystemExit(main())
