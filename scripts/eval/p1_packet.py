#!/usr/bin/env python3
"""P1 packet builder: blind rows for human rating.

Reads a capture's results.jsonl (one JSON object per turn, with `dialogue`,
`turn`, `prompt`, `response`, `status`, `arc`) and writes:

  packet.jsonl   one JSON object per line: {"id","prompt","response"[,"context"]}
  key.tsv        id <TAB> dialogue <TAB> turn <TAB> arc              (sealed)
  packet.sha256  sha256 of packet.jsonl

The packet carries no dialogue id, turn number, arc or family. Ids are
assigned after a seeded shuffle, so the packet order is reproducible but the
mapping is not derivable from the packet alone.

usage:
  p1_packet.py --results results.jsonl --out DIR [--seed N] [--context]
  p1_packet.py --self-test
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from pathlib import Path
from typing import Dict, List, Optional, Sequence

SEED = 20261128
PACKET_FIELDS = ("id", "prompt", "response", "context")


class PacketError(Exception):
    pass


def read_results(path: Path) -> List[dict]:
    rows: List[dict] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise PacketError(f"{path}:{number}: invalid JSON: {exc}") from exc
        if row.get("status") != "ok":
            continue
        for field in ("dialogue", "turn", "prompt", "response", "arc"):
            if field not in row:
                raise PacketError(f"{path}:{number}: missing {field}")
        rows.append(row)
    if not rows:
        raise PacketError(f"{path}: no ok rows")
    return rows


def build_packet(rows: Sequence[dict], seed: int, with_context: bool) -> List[dict]:
    ordered = sorted(rows, key=lambda r: (str(r["dialogue"]), int(r["turn"])))
    rng = random.Random(seed)
    shuffled = list(ordered)
    rng.shuffle(shuffled)

    history: Dict[str, List[dict]] = {}
    for row in ordered:
        history.setdefault(str(row["dialogue"]), []).append(row)

    packet: List[dict] = []
    for index, row in enumerate(shuffled, 1):
        item = {
            "id": f"p1-{index:04d}",
            "prompt": row["prompt"],
            "response": row["response"],
        }
        if with_context:
            prior = [r for r in history[str(row["dialogue"])]
                     if int(r["turn"]) < int(row["turn"])]
            item["context"] = [
                {"prompt": r["prompt"], "response": r["response"]} for r in prior
            ]
        packet.append(item)
    return packet


def build_key(rows: Sequence[dict], packet: Sequence[dict], seed: int) -> List[dict]:
    ordered = sorted(rows, key=lambda r: (str(r["dialogue"]), int(r["turn"])))
    rng = random.Random(seed)
    shuffled = list(ordered)
    rng.shuffle(shuffled)
    return [
        {
            "id": item["id"],
            "dialogue": str(row["dialogue"]),
            "turn": int(row["turn"]),
            "arc": str(row["arc"]),
        }
        for item, row in zip(packet, shuffled)
    ]


def packet_text(packet: Sequence[dict]) -> str:
    """One JSON object per line; newlines inside a response stay escaped."""
    return "".join(
        json.dumps(item, ensure_ascii=False, sort_keys=True) + "\n" for item in packet
    )


def key_text(key: Sequence[dict]) -> str:
    return "".join(
        f"{k['id']}\t{k['dialogue']}\t{k['turn']}\t{k['arc']}\n" for k in key
    )


def write_packet(results: Path, out: Path, seed: int, with_context: bool) -> dict:
    rows = read_results(results)
    packet = build_packet(rows, seed, with_context)
    key = build_key(rows, packet, seed)
    text = packet_text(packet)
    out.mkdir(parents=True, exist_ok=True)
    (out / "packet.jsonl").write_text(text, encoding="utf-8")
    (out / "key.tsv").write_text(key_text(key), encoding="utf-8")
    digest = hashlib.sha256(text.encode("utf-8")).hexdigest()
    (out / "packet.sha256").write_text(digest + "\n", encoding="utf-8")
    return {"rows": len(packet), "sha256": digest, "seed": seed}


def self_test() -> int:
    import tempfile

    failures: List[str] = []

    def check(name: str, condition: bool) -> None:
        if not condition:
            failures.append(name)

    rows = [
        {"dialogue": "d1", "turn": 1, "prompt": "p1", "response": "r1", "arc": "calm", "status": "ok"},
        {"dialogue": "d1", "turn": 2, "prompt": "p2", "response": "r2", "arc": "calm", "status": "ok"},
        {"dialogue": "d2", "turn": 1, "prompt": "p3", "response": "r3", "arc": "move", "status": "ok"},
        {"dialogue": "d2", "turn": 2, "prompt": "p4", "response": "r4", "arc": "move", "status": "driver_error"},
    ]
    ok_rows = [r for r in rows if r["status"] == "ok"]

    # 1. Determinism.
    a = build_packet(ok_rows, 7, False)
    b = build_packet(ok_rows, 7, False)
    check("deterministic", a == b)

    # 2. Different seed changes the order.
    c = build_packet(ok_rows, 8, False)
    check("seed changes order", [x["prompt"] for x in a] != [x["prompt"] for x in c])

    # 3. Blind fields.
    check("blind", all(set(x) <= set(PACKET_FIELDS) for x in a))

    # 4. Key is a bijection.
    key = build_key(ok_rows, a, 7)
    check("key bijection", {k["id"] for k in key} == {x["id"] for x in a})
    check("key rows", len(key) == len(ok_rows))

    # 5. Non-ok rows excluded.
    check("non-ok excluded", all("p4" != x["prompt"] for x in a))

    # 6. Context carries exactly the prior turns.
    with_ctx = build_packet(ok_rows, 7, True)
    by_prompt = {x["prompt"]: x for x in with_ctx}
    check("context first empty", by_prompt["p1"]["context"] == [])
    check("context second one", len(by_prompt["p2"]["context"]) == 1)
    check("context other dialogue", by_prompt["p3"]["context"] == [])

    # 7. Verbatim prompt/response.
    check("verbatim", {x["prompt"] for x in a} == {"p1", "p2", "p3"})

    # 8. Unique ids.
    check("unique ids", len({x["id"] for x in a}) == len(a))

    # 9. End-to-end files.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        results = root / "results.jsonl"
        results.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
        info = write_packet(results, root / "out", 7, False)
        check("e2e rows", info["rows"] == 3)
        text = (root / "out" / "packet.jsonl").read_text(encoding="utf-8")
        check("e2e sha", hashlib.sha256(text.encode()).hexdigest() == info["sha256"])
        lines = text.splitlines()
        check("e2e jsonl lines", len(lines) == 3)
        check("e2e jsonl parse", all(
            set(json.loads(line)) <= set(PACKET_FIELDS) for line in lines))
        key_lines = (root / "out" / "key.tsv").read_text(encoding="utf-8").splitlines()
        check("e2e key lines", len(key_lines) == 3)

        # 10. Empty input refused.
        empty = root / "empty.jsonl"
        empty.write_text("", encoding="utf-8")
        try:
            read_results(empty)
            failures.append("empty input refused")
        except PacketError:
            pass

    if failures:
        print("SELF-TEST FAILED:")
        for name in failures:
            print(f"  - {name}")
        return 1
    print("p1_packet self-test OK (12 cases)")
    return 0


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results")
    parser.add_argument("--out")
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--context", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not (args.results and args.out):
        parser.error("--results and --out are required unless --self-test")
    try:
        info = write_packet(Path(args.results), Path(args.out), args.seed, args.context)
    except PacketError as exc:
        print(f"p1_packet: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(info, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
