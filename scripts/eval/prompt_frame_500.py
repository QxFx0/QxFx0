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

It does not create labels, does not freeze a packet, and does not change the
500-prompt gate status.  The gate stays **BLOCKED** until 500 labeled rows
exist; the packet is frozen only after the owner chooses between the two
honest readings measured in ``DIALOGUE_PILOT50_PROTOCOL_2026-11-01.md``
(text-path quality at scale vs GF path after slot coverage).

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


def write_tsv(path: Path, rows):
    columns = ["frame_id", "topic", "prompt", "source", "gf_mapped", "pilot_split", "multiword"]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write("\t".join(columns) + "\n")
        for row in rows:
            handle.write("\t".join(str(row[column]) for column in columns) + "\n")


def write_manifest(path: Path, corpus: Corpus, seed: str, size: int, counts, hashes):
    manifest = {
        "kind": "prompt_sampling_frame",
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
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def report(corpus: Corpus, counts):
    sources = corpus.sources()
    print("Population")
    for key, value in sources.items():
        print(f"  {key}: {value}")
    print("\nFrame composition")
    for key, value in counts.items():
        print(f"  {key}: {value}")
    print(
        "\nFrame only: no labels were created and the 500-prompt gate is still BLOCKED."
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
        write_tsv(out, rows)
        write_manifest(manifest, corpus, "seed-a", 4, counts, corpus.input_hashes())
        header = out.read_text(encoding="utf-8").splitlines()[0]
        case("tsv header", header == "frame_id\ttopic\tprompt\tsource\tgf_mapped\tpilot_split\tmultiword")
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        case("manifest note", "not a labeled corpus" in payload["note"])
        case("manifest hashes", len(payload["input_sha256"]) == 5)
        case("manifest composition", payload["composition"]["frame_size"] == 4)

    failures = [name for name, ok, _ in cases if not ok]
    for name, ok, detail in cases:
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + (f"  ({detail})" if not ok and detail else ""))
    print(f"\nself-test: {len(cases) - len(failures)}/{len(cases)} passed")
    return 0 if not failures else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--seed", default=DEFAULT_SEED)
    ap.add_argument("--size", type=int, default=DEFAULT_SIZE)
    ap.add_argument("--out", help="write the frame TSV here (omit to only measure)")
    ap.add_argument("--manifest", help="write the manifest JSON here")
    ap.add_argument("--self-test", action="store_true", help="run embedded cases")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.size < 1:
        ap.error("--size must be positive")

    corpus = Corpus(ROOT)
    frame = build_frame(corpus, args.seed, args.size)
    counts = composition(corpus, frame)
    report(corpus, counts)
    if args.out:
        write_tsv(Path(args.out), frame_rows(corpus, frame))
        print(f"\nwrote frame: {args.out}")
    if args.manifest:
        write_manifest(Path(args.manifest), corpus, args.seed, args.size, counts, corpus.input_hashes())
        print(f"wrote manifest: {args.manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
