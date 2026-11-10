#!/usr/bin/env python3
"""Deterministic 500-prompt sampling frame for the dialogue gate.

This tool builds a *frame*, not a labeled corpus.  It reads the merged runtime
topic population (172 seed topics from ``Content.hs`` + 4 036 curated topics
from ``curated_predicates.jsonl``, 138 shared → 4 070), turns every topic into
the pilot's definition prompt shape («что такое <topic>?»), and selects a
uniform deterministic sample of ``--size`` topics by SHA-256 of
``seed + NUL + topic``.  The composition report is the point: it measures how
many selected prompts would hit the GF-mapped path, the multiword path and the
frozen pilot splits *before* anyone spends labeling hours.

``--enriched`` builds the GF-path construct instead of the uniform one: it
crosses the GF-covered topics with a table of *verified* definitional carriers
(prefixes of «что такое <topic>?»).  The carrier space is prefix-only by
construction: ``IntentDefine`` extracts the topic after the first literal
«что такое» (``Semantic/Intent/Classifier.hs``, ``extractTopicAfter``), so a
carrier without that substring yields topic = whole utterance and never reaches
the GF path.  Every carrier in ``CARRIERS`` carries the date on which a runtime
probe confirmed it keeps the ``CMDefine`` family and the same topic.  The
enriched mode reports the **ceiling** (covered topics × verified carriers) and
refuses a size above it instead of silently shrinking the frame; use ``--max``
to take the whole ceiling.

It does not create labels, does not freeze a packet, and does not change the
500-prompt gate status.  The gate stays **BLOCKED** until 500 labeled rows
exist; the packet is frozen only after the owner chooses between the two
honest readings measured in ``DIALOGUE_PILOT50_PROTOCOL_2026-11-01.md``
(text-path quality at scale vs GF path after slot coverage).  The owner chose
on 2026-11-09 to build the tooling first and **not** freeze a frame.

``--self-test`` runs the embedded cases.  They live here rather than in a test
file because the repository forbids test-only Python
(``PYTHON_SUPPLIER_ALLOWLIST.md`` §5).
"""
import argparse
import hashlib
import json
import re
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_SEED = "qxfx0-500-2026-11-06"
DEFAULT_SIZE = 500

SEED_SOURCE = "src/QxFx0/Semantic/Content.hs"
CURATED_SOURCE = "resources/knowledge/curated_predicates.jsonl"
SLOTS_SOURCE = "spec/gf/curated_predicate_slots.tsv"
PILOT_SOURCE = "spec/eval/pilot50_prompts.tsv"
RELEASE_SOURCE = "spec/gf/release_corpus_prompts.txt"

ENTRY_RE = re.compile(r'\bentry\s+"([^"]+)"')
TOPIC_RE = re.compile(r"^что такое (.+?)\?$")

# Definitional carriers.  Each entry is (carrier_id, prefix, verified_on), and
# the prompt is ``prefix + "что такое " + topic + "?"``.  ``verified_on`` is the
# date a runtime probe confirmed the carrier keeps the CMDefine family and the
# same topic as the bare shape; an unverified carrier must not be added here.
# Only prefix carriers are possible: the topic is extracted after the first
# literal «что такое», so trailing material would become part of the topic.
#
# Verification is family+topic, NOT predicate: a carrier changes the utterance
# features, hence the Field, and the per-predicate selector may then pick a
# different predicate for the same topic (observed 2026-11-09:
# «мне нужно понять, что такое свобода?» → atmosphereArousal 0.71 vs 0.15 and
# a different predicate, same topic, same covered_exact path).
CARRIERS = [
    ("bare", "", "2026-11-09"),
    ("skazhi", "скажи, ", "2026-11-09"),
    ("obyasni", "объясни, ", "2026-11-09"),
    ("a", "а ", "2026-11-09"),
    ("interesno", "интересно, ", "2026-11-09"),
    ("kratko", "кратко: ", "2026-11-09"),
    ("opredeli", "определи, ", "2026-11-09"),
    ("poyasni", "поясни, ", "2026-11-09"),
    ("otvet", "ответь, ", "2026-11-09"),
    ("pomogi_ponyat", "помоги понять, ", "2026-11-09"),
    ("mne_nuzhno_ponyat", "мне нужно понять, ", "2026-11-09"),
    ("rasskazhi", "расскажи, ", "2026-11-09"),
]

UNIFORM_COLUMNS = ["frame_id", "topic", "prompt", "source", "gf_mapped", "pilot_split", "multiword"]
ENRICHED_COLUMNS = UNIFORM_COLUMNS + ["carrier"]



def normalize_topic(text: str) -> str:
    return text.strip().lower()


def load_seed_topics(path: Path):
    return {
        normalize_topic(m.group(1))
        for m in (ENTRY_RE.search(line) for line in path.read_text(encoding="utf-8").splitlines())
        if m
    }


def load_curated_topics(path: Path):
    topics = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        topics.add(normalize_topic(json.loads(line)["topic"]))
    return topics


def load_gf_subjects(path: Path):
    subjects = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("predicate_id"):
            continue
        cells = line.split("\t")
        if len(cells) >= 3:
            subjects.add(normalize_topic(cells[2]))
    return subjects


def load_pilot_splits(path: Path):
    splits = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("id\t"):
            continue
        cells = line.split("\t")
        if len(cells) >= 3:
            splits[normalize_topic(cells[2])] = cells[1]
    return splits


def load_release_topics(path: Path):
    topics = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = TOPIC_RE.match(line)
        if m:
            topics.add(normalize_topic(m.group(1)))
    return topics


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class Corpus:
    def __init__(self, root: Path):
        self.root = root
        self.seed = load_seed_topics(root / SEED_SOURCE)
        self.curated = load_curated_topics(root / CURATED_SOURCE)
        self.merged = self.seed | self.curated
        self.gf = load_gf_subjects(root / SLOTS_SOURCE) & self.merged
        self.pilot = load_pilot_splits(root / PILOT_SOURCE)
        self.release = load_release_topics(root / RELEASE_SOURCE) & self.merged

    def sources(self):
        return {
            "seed_topics": len(self.seed),
            "curated_topics": len(self.curated),
            "shared_topics": len(self.seed & self.curated),
            "merged_topics": len(self.merged),
            "multiword_topics": sum(1 for topic in self.merged if " " in topic),
            "gf_mapped_topics": len(self.gf),
            "pilot_topics": len(self.pilot),
            "release_topics": len(self.release),
        }

    def input_hashes(self):
        paths = [SEED_SOURCE, CURATED_SOURCE, SLOTS_SOURCE, PILOT_SOURCE, RELEASE_SOURCE]
        return {name: sha256_file(self.root / name) for name in paths}


def frame_key(seed: str, topic: str) -> str:
    return hashlib.sha256(f"{seed}\x00{topic}".encode("utf-8")).hexdigest()


def build_frame(corpus: Corpus, seed: str, size: int):
    ordered = sorted(corpus.merged, key=lambda topic: (frame_key(seed, topic), topic))
    return ordered[: max(0, size)]


def prompt_for(topic: str) -> str:
    return f"что такое {topic}?"


def frame_rows(corpus: Corpus, frame):
    for index, topic in enumerate(frame, start=1):
        yield {
            "frame_id": f"f500-{index:03d}",
            "topic": topic,
            "prompt": prompt_for(topic),
            "source": (
                "seed+curated" if topic in corpus.seed and topic in corpus.curated
                else "seed" if topic in corpus.seed
                else "curated"
            ),
            "gf_mapped": 1 if topic in corpus.gf else 0,
            "pilot_split": corpus.pilot.get(topic, ""),
            "multiword": 1 if " " in topic else 0,
        }


def composition(corpus: Corpus, frame):
    rows = list(frame_rows(corpus, frame))
    return {
        "frame_size": len(rows),
        "gf_mapped": sum(row["gf_mapped"] for row in rows),
        "multiword": sum(row["multiword"] for row in rows),
        "singleword": len(rows) - sum(row["multiword"] for row in rows),
        "pilot_overlap": sum(1 for row in rows if row["pilot_split"]),
        "pilot_anchor": sum(1 for row in rows if row["pilot_split"] == "anchor"),
        "pilot_held": sum(1 for row in rows if row["pilot_split"] == "held"),
        "pilot_oov": sum(1 for row in rows if row["pilot_split"] == "oov"),
        "from_seed": sum(1 for row in rows if "seed" in row["source"]),
        "from_curated": sum(1 for row in rows if "curated" in row["source"]),
    }


def select_carriers(ids):
    """Filter the carrier table by id; unknown ids fail loudly."""
    if not ids:
        return list(CARRIERS)
    known = {cid for cid, _, _ in CARRIERS}
    unknown = sorted(set(ids) - known)
    if unknown:
        raise SystemExit(
            f"unknown carrier id(s): {', '.join(unknown)}; "
            f"available: {', '.join(sorted(known))}"
        )
    wanted = set(ids)
    return [entry for entry in CARRIERS if entry[0] in wanted]


def carrier_prompt(topic: str, prefix: str) -> str:
    return f"{prefix}что такое {topic}?"


def enriched_ceiling(corpus: Corpus, carriers) -> int:
    return len(corpus.gf) * len(carriers)


def build_enriched_frame(corpus: Corpus, seed: str, size: int, carriers):
    """Cross GF-covered topics with verified carriers, deterministically.

    Raises ``SystemExit`` when ``size`` exceeds the ceiling: a silently shrunk
    frame would misreport what the gate can sample.
    """
    ceiling = enriched_ceiling(corpus, carriers)
    if size > ceiling:
        raise SystemExit(
            f"--size {size} exceeds the enriched ceiling {ceiling} "
            f"({len(corpus.gf)} GF-covered topics x {len(carriers)} verified carriers); "
            "use --max to take the whole ceiling, add verified carriers, or expand "
            "topic coverage"
        )
    candidates = [
        (carrier_prompt(topic, prefix), topic, carrier_id)
        for topic in sorted(corpus.gf)
        for carrier_id, prefix, _ in carriers
    ]
    ordered = sorted(candidates, key=lambda row: (frame_key(seed, row[0]), row[0]))
    return ordered[: max(0, size)]


def enriched_rows(corpus: Corpus, frame):
    for index, (prompt, topic, carrier_id) in enumerate(frame, start=1):
        yield {
            "frame_id": f"f500e-{index:03d}",
            "topic": topic,
            "prompt": prompt,
            "source": (
                "seed+curated" if topic in corpus.seed and topic in corpus.curated
                else "seed" if topic in corpus.seed
                else "curated"
            ),
            "gf_mapped": 1 if topic in corpus.gf else 0,
            "pilot_split": corpus.pilot.get(topic, ""),
            "multiword": 1 if " " in topic else 0,
            "carrier": carrier_id,
        }


def enriched_composition(corpus: Corpus, frame, carriers):
    rows = list(enriched_rows(corpus, frame))
    return {
        "frame_size": len(rows),
        "gf_mapped": sum(row["gf_mapped"] for row in rows),
        "distinct_topics": len({row["topic"] for row in rows}),
        "carriers_used": len({row["carrier"] for row in rows}),
        "ceiling": enriched_ceiling(corpus, carriers),
        "multiword": sum(row["multiword"] for row in rows),
        "singleword": len(rows) - sum(row["multiword"] for row in rows),
        "pilot_overlap": sum(1 for row in rows if row["pilot_split"]),
        "pilot_anchor": sum(1 for row in rows if row["pilot_split"] == "anchor"),
        "pilot_held": sum(1 for row in rows if row["pilot_split"] == "held"),
        "pilot_oov": sum(1 for row in rows if row["pilot_split"] == "oov"),
        "from_seed": sum(1 for row in rows if "seed" in row["source"]),
        "from_curated": sum(1 for row in rows if "curated" in row["source"]),
    }



def write_tsv(path: Path, rows, columns):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("\t".join(columns) + "\n")
        for row in rows:
            handle.write("\t".join(str(row[column]) for column in columns) + "\n")


def write_manifest(path: Path, corpus: Corpus, seed: str, size: int, counts, hashes,
                   mode="uniform", carriers=None):
    manifest = {
        "kind": "prompt_sampling_frame",
        "mode": mode,
        "note": (
            "Frame only, not a labeled corpus. The 500-prompt gate remains BLOCKED "
            "until 500 labeled rows exist. Do not freeze this packet before the owner "
            "chooses between text-path quality and GF-path coverage."
        ),
        "seed": seed,
        "requested_size": size,
        "sources": corpus.sources(),
        "composition": counts,
        "input_sha256": hashes,
    }
    if mode == "enriched":
        manifest["carriers"] = [
            {"carrier_id": cid, "prefix": prefix, "verified_on": verified}
            for cid, prefix, verified in (carriers or [])
        ]
        manifest["note"] = (
            "GF-path frame only, not a labeled corpus, not frozen. The enriched frame "
            "crosses GF-covered topics with verified definitional carriers; it measures "
            "phrasing robustness on the GF path, not topic breadth. The 500-prompt gate "
            "remains BLOCKED until 500 labeled rows exist."
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def report(corpus: Corpus, counts, mode="uniform", carriers=None):
    sources = corpus.sources()
    print("Population")
    for key, value in sources.items():
        print(f"  {key}: {value}")
    if mode == "enriched":
        print("\nVerified carriers")
        for cid, prefix, verified in (carriers or []):
            print(f"  {cid}: {prefix!r} (verified {verified})")
        print(
            f"\nCeiling: {len(corpus.gf)} GF-covered topics x "
            f"{len(carriers or [])} verified carriers = {counts.get('ceiling', 0)} prompts"
        )
    print("\nFrame composition")
    for key, value in counts.items():
        print(f"  {key}: {value}")
    print(
        "\nFrame only: no labels were created and the 500-prompt gate is still BLOCKED."
    )
    if mode == "enriched":
        print(
            "This is a phrasing-robustness frame on the GF path, not a breadth sample: "
            f"{counts.get('distinct_topics', 0)} distinct topics carry it."
        )


def self_test():
    cases = []

    def case(name, ok, detail=""):
        cases.append((name, ok, detail))

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "src/QxFx0/Semantic").mkdir(parents=True)
        (root / "resources/knowledge").mkdir(parents=True)
        (root / "spec/gf").mkdir(parents=True)
        (root / "spec/eval").mkdir(parents=True)

        (root / SEED_SOURCE).write_text(
            '  [ entry "альфа"\n  , entry "бета"\n  , entry "гамма"\n  ]\n',
            encoding="utf-8",
        )
        curated = [
            {"topic": "альфа", "predicates": []},
            {"topic": "гамма", "predicates": []},
            {"topic": "дельта", "predicates": []},
            {"topic": "эпсилон тест", "predicates": []},
            {"topic": "дзета", "predicates": []},
        ]
        (root / CURATED_SOURCE).write_text(
            "\n".join(json.dumps(row, ensure_ascii=False) for row in curated) + "\n",
            encoding="utf-8",
        )
        (root / SLOTS_SOURCE).write_text(
            "predicate_id\tsubject_id\tsubject_ru\trelation_id\trelation_ru\tobject_id\tobject_ru\tsource_ru\n"
            "p1\talfa\tальфа\test\tесть\tobj\tобъект\tальфа есть объект\n",
            encoding="utf-8",
        )
        (root / PILOT_SOURCE).write_text(
            "id\tsplit\ttopic\tprompt\texpected_family\n"
            "oov-001\toov\tэпсилон тест\tчто такое эпсилон тест?\tCMDefine\n",
            encoding="utf-8",
        )
        (root / RELEASE_SOURCE).write_text(
            "# comment\nчто такое альфа?\nчто такое гамма?\n",
            encoding="utf-8",
        )

        corpus = Corpus(root)
        case("seed parse", corpus.seed == {"альфа", "бета", "гамма"}, f"{corpus.seed}")
        case("curated parse", len(corpus.curated) == 5, f"{len(corpus.curated)}")
        case("merged union", corpus.merged == {"альфа", "бета", "гамма", "дельта", "эпсилон тест", "дзета"})
        case("shared count", corpus.sources()["shared_topics"] == 2)
        case("multiword count", corpus.sources()["multiword_topics"] == 1)
        case("gf subject", corpus.gf == {"альфа"}, f"{corpus.gf}")
        case("pilot split", corpus.pilot.get("эпсилон тест") == "oov")
        case("release topics", corpus.release == {"альфа", "гамма"}, f"{corpus.release}")

        frame_a = build_frame(corpus, "seed-a", 4)
        frame_b = build_frame(corpus, "seed-a", 4)
        frame_c = build_frame(corpus, "seed-b", 4)
        case("frame deterministic", frame_a == frame_b)
        case("frame size", len(frame_a) == 4)
        case("frame no duplicates", len(set(frame_a)) == len(frame_a))
        case("frame subset", set(frame_a) <= corpus.merged)
        case("seed changes order", frame_a != frame_c, f"{frame_a} vs {frame_c}")
        case("size is capped by population", len(build_frame(corpus, "seed-a", 99)) == len(corpus.merged))

        counts = composition(corpus, frame_a)
        case("composition size", counts["frame_size"] == 4)
        case("composition gf", 0 <= counts["gf_mapped"] <= 4)
        case("composition pilot", 0 <= counts["pilot_overlap"] <= 4)
        case("composition sums", counts["multiword"] + counts["singleword"] == 4)
        case("composition source sums", counts["from_seed"] + counts["from_curated"] >= 4)

        rows = list(frame_rows(corpus, frame_a))
        case("row prompt shape", all(row["prompt"] == f"что такое {row['topic']}?" for row in rows))
        case("row ids", [row["frame_id"] for row in rows] == ["f500-001", "f500-002", "f500-003", "f500-004"])

        out = root / "out.tsv"
        manifest = root / "manifest.json"
        write_tsv(out, rows, UNIFORM_COLUMNS)
        write_manifest(manifest, corpus, "seed-a", 4, counts, corpus.input_hashes())
        header = out.read_text(encoding="utf-8").splitlines()[0]
        case("tsv header", header == "frame_id\ttopic\tprompt\tsource\tgf_mapped\tpilot_split\tmultiword")
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        case("manifest note", "not a labeled corpus" in payload["note"])
        case("manifest hashes", len(payload["input_sha256"]) == 5)
        case("manifest composition", payload["composition"]["frame_size"] == 4)

        # --- enriched mode -------------------------------------------------
        case("carrier ids unique", len({cid for cid, _, _ in CARRIERS}) == len(CARRIERS))
        case(
            "carriers contain the definition marker",
            all("что такое" in carrier_prompt("x", prefix) for _, prefix, _ in CARRIERS),
        )
        case(
            "carrier prompt shape",
            all(carrier_prompt("альфа", prefix) == f"{prefix}что такое альфа?" for _, prefix, _ in CARRIERS),
        )
        case("carrier dates recorded", all(verified for _, _, verified in CARRIERS))

        carriers = select_carriers(["bare", "skazhi"])
        case("carrier filter", [cid for cid, _, _ in carriers] == ["bare", "skazhi"], f"{carriers}")
        case("carrier filter default is the table", select_carriers([]) == list(CARRIERS))
        unknown_raised = False
        try:
            select_carriers(["nope"])
        except SystemExit as exc:
            unknown_raised = "unknown carrier id" in str(exc)
        case("unknown carrier fails loudly", unknown_raised)

        case("enriched ceiling", enriched_ceiling(corpus, carriers) == len(corpus.gf) * 2)

        enriched = build_enriched_frame(corpus, "seed-a", 2, carriers)
        case("enriched size", len(enriched) == 2, f"{enriched}")
        case("enriched deterministic", enriched == build_enriched_frame(corpus, "seed-a", 2, carriers))
        case(
            "enriched distinct topics",
            len({topic for _, topic, _ in enriched}) == 1,
            f"{[topic for _, topic, _ in enriched]}",
        )
        case(
            "enriched prompts carry the marker",
            all("что такое" in prompt and prompt.endswith("?") for prompt, _, _ in enriched),
        )
        case("enriched topics are GF-covered", all(topic in corpus.gf for _, topic, _ in enriched))
        case(
            "enriched takes the whole ceiling",
            len(build_enriched_frame(corpus, "seed-a", 2, carriers)) == 2
            and len(build_enriched_frame(corpus, "seed-a", enriched_ceiling(corpus, carriers), carriers))
            == enriched_ceiling(corpus, carriers),
        )
        over_raised = False
        try:
            build_enriched_frame(corpus, "seed-a", 3, carriers)
        except SystemExit as exc:
            over_raised = "exceeds the enriched ceiling" in str(exc)
        case("enriched over-ceiling fails loudly", over_raised)

        enriched_counts = enriched_composition(corpus, enriched, carriers)
        case("enriched composition size", enriched_counts["frame_size"] == 2)
        case("enriched composition ceiling", enriched_counts["ceiling"] == 2)
        case("enriched composition gf", enriched_counts["gf_mapped"] == 2)
        case("enriched composition topics", enriched_counts["distinct_topics"] == 1)
        case("enriched composition carriers", enriched_counts["carriers_used"] == 2)
        case(
            "enriched composition sums",
            enriched_counts["multiword"] + enriched_counts["singleword"] == 2
            and enriched_counts["from_seed"] >= 2
            and enriched_counts["from_curated"] >= 2,
        )

        enriched_rows_list = list(enriched_rows(corpus, enriched))
        case(
            "enriched row ids",
            [row["frame_id"] for row in enriched_rows_list] == ["f500e-001", "f500e-002"],
        )
        enriched_out = root / "enriched.tsv"
        write_tsv(enriched_out, enriched_rows_list, ENRICHED_COLUMNS)
        enriched_header = enriched_out.read_text(encoding="utf-8").splitlines()[0]
        case("enriched tsv header", enriched_header == "\t".join(ENRICHED_COLUMNS))
        enriched_manifest = root / "enriched.json"
        write_manifest(
            enriched_manifest, corpus, "seed-a", 2, enriched_counts,
            corpus.input_hashes(), mode="enriched", carriers=carriers,
        )
        enriched_payload = json.loads(enriched_manifest.read_text(encoding="utf-8"))
        case("enriched manifest mode", enriched_payload["mode"] == "enriched")
        case("enriched manifest carriers", len(enriched_payload["carriers"]) == 2)
        case(
            "enriched manifest is not a breadth claim",
            "not topic breadth" in enriched_payload["note"],
        )
        case("enriched manifest is not frozen", "not frozen" in enriched_payload["note"])

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--seed", default=DEFAULT_SEED)
    ap.add_argument("--size", type=int, default=DEFAULT_SIZE)
    ap.add_argument("--enriched", action="store_true",
                    help="GF-path frame: GF-covered topics x verified carriers")
    ap.add_argument("--max", action="store_true",
                    help="enriched only: take the whole ceiling instead of --size")
    ap.add_argument("--carriers",
                    help="enriched only: comma-separated carrier ids (default: all verified)")
    ap.add_argument("--list-carriers", action="store_true",
                    help="print the verified carrier table and exit")
    ap.add_argument("--out", help="write the frame TSV here (omit to only measure)")
    ap.add_argument("--manifest", help="write the manifest JSON here")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.list_carriers:
        for carrier_id, prefix, verified in CARRIERS:
            print(f"{carrier_id}\t{prefix}\t{verified}")
        return 0
    if args.size < 1:
        ap.error("--size must be positive")
    if (args.max or args.carriers) and not args.enriched:
        ap.error("--max/--carriers are only meaningful with --enriched")

    corpus = Corpus(ROOT)

    if args.enriched:
        carriers = select_carriers(
            [part.strip() for part in args.carriers.split(",") if part.strip()]
            if args.carriers else []
        )
        size = enriched_ceiling(corpus, carriers) if args.max else args.size
        frame = build_enriched_frame(corpus, args.seed, size, carriers)
        counts = enriched_composition(corpus, frame, carriers)
        report(corpus, counts, mode="enriched", carriers=carriers)
        if args.out:
            write_tsv(Path(args.out), enriched_rows(corpus, frame), ENRICHED_COLUMNS)
            print(f"\nwrote frame: {args.out}")
        if args.manifest:
            write_manifest(Path(args.manifest), corpus, args.seed, size, counts,
                           corpus.input_hashes(), mode="enriched", carriers=carriers)
            print(f"wrote manifest: {args.manifest}")
        return 0

    frame = build_frame(corpus, args.seed, args.size)
    counts = composition(corpus, frame)
    report(corpus, counts)
    if args.out:
        write_tsv(Path(args.out), frame_rows(corpus, frame), UNIFORM_COLUMNS)
        print(f"\nwrote frame: {args.out}")
    if args.manifest:
        write_manifest(Path(args.manifest), corpus, args.seed, args.size, counts, corpus.input_hashes())
        print(f"wrote manifest: {args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
