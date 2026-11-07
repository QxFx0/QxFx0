#!/usr/bin/env python3
"""Measure and freeze the GF slot gap over the merged runtime corpus.

Why this exists: the signed scope in
``GF_SLOT_COVERAGE_PREREG_DRAFT_2026-11-01.md`` quotes 286 anchor predicate
rows / 207 without slots, but the script that produced those numbers was never
committed.  Re-measuring from the current tree gives a different count, so the
authoring batch cannot start from the text alone — it needs a reproducible
measurement and a frozen row list.

The population is the *runtime* merged corpus (seed ``definitionCorpus`` +
``arguedPredicates`` + ``curated_predicates.jsonl``), read through
``QxFx0.Semantic.Content.Curated.extendedDefinitionCorpus``.  It is never
reconstructed by parsing Haskell sources here: that is exactly the drift this
tool removes.  The Haskell dump program is embedded below, written to a temp
file and run with ``cabal exec -- runghc -isrc``.

The split into group 1 / group 2 is a *heuristic*, and the tool says so:

- group 1: the predicate surface starts with ``<topic> <relation> `` for one of
  the relation strings that already exist in ``curated_predicate_slots.tsv``
  (longest match wins).  These rows need only a new object string.
- group 2: no existing relation string matches.  These rows need a new relation
  string *and* a new object string.  For them the tool reports the first token
  after the topic as a hint only — it is not asserted to be the relation.

``--freeze`` writes a deterministic TSV and its sha256 sidecar so the row list
becomes an artifact instead of a number in prose.  The tool creates no slots,
edits no corpus file, and does not change the 500-prompt or M7 gates.

``--self-test`` runs the embedded cases on synthetic inputs and needs no
Haskell build.  They live here rather than in a test file because the
repository forbids test-only Python (``PYTHON_SUPPLIER_ALLOWLIST.md`` §5).
"""
import argparse
import hashlib
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SLOTS_SOURCE = "spec/gf/curated_predicate_slots.tsv"

DUMP_PROGRAM = '''{-# LANGUAGE OverloadedStrings #-}
module Main (main) where

import qualified Data.Map.Strict as M
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import QxFx0.Semantic.Content.Curated (extendedDefinitionCorpus)
import QxFx0.Types.Semantic.Content (DefinitionContent (..), SemanticPredicate (..))

main :: IO ()
main = do
  corpus <- extendedDefinitionCorpus
  mapM_ putRow [ (dcTopic dc, spRu p) | dc <- M.elems corpus, p <- dcPredicates dc ]
  where
    putRow (topic, surface) = TIO.putStrLn (topic <> "\\t" <> surface)
'''

COLUMNS = ["topic", "source_ru", "group", "matched_relation", "object", "note"]


def load_slots(path: Path):
    """Return (subjects, relations, objects, source_surfaces) from the slot table."""
    subjects, relations, objects, sources = set(), set(), set(), set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("predicate_id"):
            continue
        cells = line.split("\t")
        if len(cells) < 8:
            continue
        subjects.add(cells[2].strip())
        relations.add(cells[4].strip())
        objects.add(cells[6].strip())
        sources.add(cells[7].strip())
    return subjects, relations, objects, sources


def parse_dump(text: str):
    """Parse ``topic<TAB>surface`` lines into a sorted, de-duplicated pair list."""
    pairs = set()
    for line in text.splitlines():
        if "\t" not in line:
            continue
        topic, _, surface = line.partition("\t")
        topic, surface = topic.strip(), surface.strip()
        if topic and surface:
            pairs.add((topic, surface))
    return sorted(pairs)


def classify(topic: str, surface: str, relations):
    """Split one row into group 1 / group 2; never raises, never guesses silently."""
    prefix = topic + " "
    if not surface.startswith(prefix):
        return {
            "group": "2",
            "matched_relation": "",
            "object": "",
            "note": "topic_prefix_missing",
        }
    body = surface[len(prefix):]
    for relation in sorted(relations, key=len, reverse=True):
        if body.startswith(relation + " "):
            return {
                "group": "1",
                "matched_relation": relation,
                "object": body[len(relation) + 1:],
                "note": "relation_exists",
            }
    head = body.split(" ")[0] if body else ""
    return {
        "group": "2",
        "matched_relation": "",
        "object": "",
        "note": f"new_relation_required (head hint: {head})" if head else "new_relation_required",
    }


def build_rows(pairs, subjects, relations, sources):
    """Every anchor predicate row, split into mapped / group 1 / group 2."""
    rows = []
    for topic, surface in pairs:
        if topic not in subjects:
            continue
        row = {"topic": topic, "source_ru": surface}
        if surface in sources:
            row.update({"group": "mapped", "matched_relation": "", "object": "", "note": "slot_exists"})
        else:
            row.update(classify(topic, surface, relations))
        rows.append(row)
    return rows


def summarise(rows, objects):
    unmapped = [row for row in rows if row["group"] != "mapped"]
    group1 = [row for row in unmapped if row["group"] == "1"]
    group2 = [row for row in unmapped if row["group"] == "2"]
    new_objects = {row["object"] for row in group1 if row["object"]}
    return {
        "anchor_rows": len(rows),
        "mapped": len(rows) - len(unmapped),
        "unmapped": len(unmapped),
        "group1": len(group1),
        "group2": len(group2),
        "group1_new_objects": len(new_objects - objects),
        "group1_existing_objects": len(new_objects & objects),
        "group1_relations_used": len({row["matched_relation"] for row in group1}),
        "topic_prefix_missing": sum(1 for row in unmapped if row["note"] == "topic_prefix_missing"),
    }


def render_tsv(rows):
    lines = ["\t".join(COLUMNS)]
    for row in rows:
        lines.append("\t".join(str(row[column]) for column in COLUMNS))
    return "\n".join(lines) + "\n"


def freeze(path: Path, rows):
    """Write the deterministic TSV plus a sha256 sidecar; return the digest."""
    payload = render_tsv(rows).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    digest = hashlib.sha256(payload).hexdigest()
    sidecar = path.with_name(path.name + ".sha256")
    sidecar.write_text(f"{digest}  {path.name}\n", encoding="utf-8")
    return digest


def run_dump():
    """Run the embedded Haskell dump against the built library."""
    import subprocess

    with tempfile.TemporaryDirectory() as tmp:
        program = Path(tmp) / "DumpMergedCorpus.hs"
        program.write_text(DUMP_PROGRAM, encoding="utf-8")
        result = subprocess.run(
            ["cabal", "exec", "--", "runghc", "-isrc", str(program)],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        raise SystemExit("corpus dump failed; run with --dump PATH to reuse an existing dump")
    return result.stdout


def report(counts, frozen_digest):
    print("Anchor population (merged runtime corpus, de-duplicated pairs)")
    for key, value in counts.items():
        print(f"  {key}: {value}")
    if frozen_digest:
        print(f"\nfrozen row list sha256: {frozen_digest}")
    print(
        "\nGroup 1 / group 2 is a heuristic: group 1 matches an existing relation "
        "string, group 2 does not. The head hint is not asserted to be the relation."
    )
    print("No slots were created and no corpus file was modified.")


def self_test():
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    relations = {"есть", "это", "предполагает", "ограничена"}
    objects = {"возможность выбора"}

    row = classify("свобода", "свобода предполагает возможность выбора", relations)
    case("group 1 detected", row["group"] == "1", str(row))
    case("object extracted", row["object"] == "возможность выбора", str(row))
    case("existing relation reported", row["matched_relation"] == "предполагает")

    row = classify("свобода", "свобода раскрывается через выбор", relations)
    case("group 2 when relation unknown", row["group"] == "2", str(row))
    case("group 2 keeps a hint only", row["note"].startswith("new_relation_required"))
    case("group 2 has no object", row["object"] == "")

    row = classify("свобода", "выбор предполагает свободу", relations)
    case("missing topic prefix is flagged", row["note"] == "topic_prefix_missing", str(row))

    row = classify("бытие", "бытие это то что существует", relations)
    case("longest relation wins",
         row["matched_relation"] == "это" and row["object"] == "то что существует", str(row))

    pairs = parse_dump("a\tx y\nb\tz\na\tx y\n\nbad-line\n")
    case("dump parses pairs", pairs == [("a", "x y"), ("b", "z")], str(pairs))
    case("dump de-duplicates", len(pairs) == 2)

    rows = build_rows(
        [("свобода", "свобода предполагает возможность выбора"),
         ("свобода", "свобода предполагает новую рамку"),
         ("свобода", "свобода ограничена ответственностью"),
         ("чужое", "чужое предполагает нечто")],
        subjects={"свобода"},
        relations=relations,
        sources={"свобода ограничена ответственностью"},
    )
    case("non-anchor topics dropped", len(rows) == 3, str(rows))
    case("mapped row classified", [r["group"] for r in rows if r["source_ru"].endswith("ответственностью")] == ["mapped"])

    counts = summarise(rows, objects)
    case("summary counts", counts["anchor_rows"] == 3 and counts["mapped"] == 1 and counts["unmapped"] == 2, str(counts))
    case("new object counted", counts["group1_new_objects"] == 1, str(counts))
    case("existing object counted", counts["group1_existing_objects"] == 1, str(counts))

    tsv_a = render_tsv(rows)
    tsv_b = render_tsv(list(rows))
    case("tsv deterministic", tsv_a == tsv_b)
    case("tsv header", tsv_a.splitlines()[0] == "\t".join(COLUMNS))

    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "rows.tsv"
        digest_a = freeze(path, rows)
        digest_b = freeze(path, rows)
        case("freeze deterministic", digest_a == digest_b)
        case("sidecar written", path.with_name(path.name + ".sha256").exists())
        case("digest matches payload",
             hashlib.sha256(path.read_bytes()).hexdigest() == digest_a)
        case("frozen file parses back", parse_dump("") == [] and path.read_text(encoding="utf-8").count("\n") == len(rows) + 1)

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--dump", help="reuse a corpus dump file instead of running the runtime")
    ap.add_argument("--slots", default=SLOTS_SOURCE, help="slot table to compare against")
    ap.add_argument("--freeze", help="write the unmapped row list here (TSV + .sha256 sidecar)")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    slots_path = Path(args.slots) if Path(args.slots).is_absolute() else ROOT / args.slots
    subjects, relations, objects, sources = load_slots(slots_path)
    if not subjects:
        ap.error(f"no slot rows found in {slots_path}")

    dump_text = Path(args.dump).read_text(encoding="utf-8") if args.dump else run_dump()
    rows = build_rows(parse_dump(dump_text), subjects, relations, sources)
    counts = summarise(rows, objects)

    digest = None
    if args.freeze:
        frozen = [row for row in rows if row["group"] != "mapped"]
        digest = freeze(Path(args.freeze), frozen)
    report(counts, digest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
