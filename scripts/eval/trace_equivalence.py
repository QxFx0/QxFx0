#!/usr/bin/env python3
"""Path-by-path comparison of two replay-trace streams (read-only).

Pre-registration: docs/closure/P4_STATE_INTEGRITY_PREREG_2026-11-23.md (E2).

The P4 rename was measured by running the same prompt sequence under the
pre-rename and post-rename binaries and comparing the persisted replay
trace field by field.  The ad-hoc driver used for that measurement lived
in a temporary directory and was lost with it; this tool replaces it so
the measurement can be repeated by anyone.

Inputs are either

  * a capture database (`*.db` with `turn_quality.replay_trace_json`),
    read `mode=ro` and ordered by `(session_id, turn)`, or
  * a JSONL file with one trace object per line, in stream order.

Both sides must have the same number of traces; otherwise the comparison
is a structural mismatch, not an equivalence.

Comparison is a recursive walk over the decoded JSON.  A path is written
in dotted form (`trcEffectSnapshot.esCurrentTime`, `trcField.ftValence`);
list elements use their index (`trcX.0`).  A path is skipped when it
equals an ignored path or lies under one.

Default ignores are the values the pre-registration names as
per-run/per-binary: the request id, the session id, the replay envelope
(it carries the input text and the recorded clock), the P4 contour (it
does not exist on the pre-rename side) and the recorded turn clock.

Writes nothing unless `--json` is given.

Self-test: `--self-test` covers identical streams, a mutated scalar, a
mutated list element, a missing key, an extra key, an ignored path, an
ignored prefix, a length mismatch, DB input and a malformed JSONL line.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

DEFAULT_IGNORES = (
    "trcRequestId",
    "trcSessionId",
    "trcReplayEnvelope",
    "trcConatusContour",
    "trcEffectSnapshot.esCurrentTime",
)

# Anything at or above this many reported differences is "the streams
# diverge"; the report still prints the first REPORT_LIMIT paths.
REPORT_LIMIT = 40


def _decode(blob: str) -> object:
    decoded = json.loads(blob)
    if isinstance(decoded, dict) and isinstance(decoded.get("trace"), dict):
        return decoded["trace"]
    return decoded


def _is_sqlite(path: Path) -> bool:
    with path.open("rb") as handle:
        return handle.read(16) == b"SQLite format 3\x00"


def load_stream(path: Path) -> list[object]:
    """Load a trace stream from a capture DB or a JSONL file."""
    if not path.is_file():
        raise SystemExit(f"equivalence: input not found: {path}")
    if _is_sqlite(path):
        con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            rows = con.execute(
                "select replay_trace_json from turn_quality "
                "order by session_id, turn"
            ).fetchall()
        finally:
            con.close()
        return [_decode(row[0]) for row in rows]

    traces: list[object] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            traces.append(_decode(line))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{number}: not JSON: {exc}") from exc
    return traces


def _ignored(path: str, ignores: tuple[str, ...]) -> bool:
    return any(path == item or path.startswith(item + ".") for item in ignores)


def _walk(old: object, new: object, path: str, ignores: tuple[str, ...],
          out: list[tuple[str, object, object]]) -> None:
    if _ignored(path, ignores):
        return
    if isinstance(old, dict) and isinstance(new, dict):
        for key in sorted(set(old) | set(new)):
            child = f"{path}.{key}" if path else str(key)
            if key not in old:
                if not _ignored(child, ignores):
                    out.append((child, "<absent>", new[key]))
            elif key not in new:
                if not _ignored(child, ignores):
                    out.append((child, old[key], "<absent>"))
            else:
                _walk(old[key], new[key], child, ignores, out)
        return
    if isinstance(old, list) and isinstance(new, list):
        for index in range(max(len(old), len(new))):
            child = f"{path}.{index}" if path else str(index)
            if index >= len(old):
                if not _ignored(child, ignores):
                    out.append((child, "<absent>", new[index]))
            elif index >= len(new):
                if not _ignored(child, ignores):
                    out.append((child, old[index], "<absent>"))
            else:
                _walk(old[index], new[index], child, ignores, out)
        return
    if old != new or type(old) is not type(new):
        out.append((path or "<root>", old, new))


def compare(old: list[object], new: list[object],
            ignores: tuple[str, ...] = DEFAULT_IGNORES) -> dict:
    result: dict = {
        "traces_old": len(old),
        "traces_new": len(new),
        "length_mismatch": len(old) != len(new),
        "differing_traces": 0,
        "differing_paths": 0,
        "differences": [],
    }
    if len(old) != len(new):
        return result
    for index, (before, after) in enumerate(zip(old, new)):
        findings: list[tuple[str, object, object]] = []
        _walk(before, after, "", ignores, findings)
        if findings:
            result["differing_traces"] += 1
            result["differing_paths"] += len(findings)
            for path, left, right in findings:
                if len(result["differences"]) < REPORT_LIMIT:
                    result["differences"].append(
                        {"trace": index, "path": path or "<root>",
                         "old": left, "new": right}
                    )
    return result


def summarize(result: dict) -> list[str]:
    if result["length_mismatch"]:
        return [
            f"FAIL trace streams differ in length: "
            f"{result['traces_old']} vs {result['traces_new']}"
        ]
    head = (
        f"traces: {result['traces_old']}, "
        f"differing traces: {result['differing_traces']}, "
        f"reported paths: {len(result['differences'])}"
    )
    lines = [head]
    for diff in result["differences"]:
        lines.append(
            f"  trace {diff['trace']} {diff['path']}: "
            f"{json.dumps(diff['old'], ensure_ascii=False)} != "
            f"{json.dumps(diff['new'], ensure_ascii=False)}"
        )
    lines.append("PASS" if result["differing_traces"] == 0 else "FAIL")
    return lines


def _write_db(path: Path, traces: list[object]) -> None:
    con = sqlite3.connect(path)
    try:
        con.execute(
            "create table turn_quality "
            "(session_id text, turn integer, replay_trace_json text)"
        )
        for index, trace in enumerate(traces, 1):
            blob = trace if isinstance(trace, str) else json.dumps(trace)
            con.execute(
                "insert into turn_quality values (?, ?, ?)",
                (f"s-{index}", 1, blob),
            )
        con.commit()
    finally:
        con.close()


def self_test() -> int:
    import tempfile

    checks: list[tuple[str, bool]] = []

    def check(name: str, condition: bool) -> None:
        checks.append((name, bool(condition)))
        if not condition:
            print(f"FAIL {name}")

    base = {
        "trcSessionId": "a",
        "trcRequestId": "r1",
        "trcReplayEnvelope": {"reInputText": "x", "reEnvelopeVersion": 1},
        "trcConatusContour": {"ctcEssenceCommitments": 1},
        "trcConatusEnergy": {"ceScalar": 7.0,
                             "ceComponents": {"ccTurns": 0.5}},
        "trcEffectSnapshot": {"esCurrentTime": "t0", "esApiHealthy": True},
        "trcField": {"ftValence": 0.1, "ftArousal": 0.2},
        "trcGenerationTrace": [{"gteRule": "a"}, {"gteRule": "b"}],
    }

    # identical except the ignored values: PASS
    same = json.loads(json.dumps(base))
    same["trcSessionId"] = "b"
    same["trcRequestId"] = "r2"
    same["trcReplayEnvelope"]["reInputText"] = "y"
    same["trcConatusContour"]["ctcEssenceCommitments"] = 0
    same["trcEffectSnapshot"]["esCurrentTime"] = "t9"
    result = compare([base], [same])
    check("ignored values do not differ", result["differing_traces"] == 0)

    # mutated scalar is reported with its dotted path
    mutated = json.loads(json.dumps(base))
    mutated["trcConatusEnergy"]["ceScalar"] = 7.5
    result = compare([base], [mutated])
    check("scalar mutation detected", result["differing_traces"] == 1)
    check(
        "scalar path",
        result["differences"][0]["path"] == "trcConatusEnergy.ceScalar",
    )

    # mutated list element uses its index
    mutated = json.loads(json.dumps(base))
    mutated["trcGenerationTrace"][1]["gteRule"] = "c"
    result = compare([base], [mutated])
    check(
        "list index path",
        result["differences"][0]["path"] == "trcGenerationTrace.1.gteRule",
    )

    # missing key: reported as <absent>
    shorter = json.loads(json.dumps(base))
    del shorter["trcField"]["ftArousal"]
    result = compare([base], [shorter])
    check("missing key path", result["differences"][0]["path"] == "trcField.ftArousal")
    check("missing key old", result["differences"][0]["old"] == 0.2)
    check("missing key new", result["differences"][0]["new"] == "<absent>")

    # extra key
    longer = json.loads(json.dumps(base))
    longer["trcField"]["ftExtra"] = 1
    result = compare([base], [longer])
    check("extra key path", result["differences"][0]["path"] == "trcField.ftExtra")
    check("extra key old", result["differences"][0]["old"] == "<absent>")

    # a prefix ignore covers the whole subtree
    mutated = json.loads(json.dumps(base))
    mutated["trcField"] = {"ftValence": 9.9, "ftArousal": 9.9}
    result = compare([base], [mutated], ignores=DEFAULT_IGNORES + ("trcField",))
    check("prefix ignore", result["differing_traces"] == 0)

    # length mismatch is structural, not equivalence
    result = compare([base], [base, base])
    check("length mismatch", result["length_mismatch"] is True)
    check("length mismatch summary", summarize(result)[0].startswith("FAIL"))

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        left = root / "left.db"
        right = root / "right.db"
        _write_db(left, [base])
        mutated = json.loads(json.dumps(base))
        mutated["trcConatusEnergy"]["ceScalar"] = 8.0
        _write_db(right, [mutated])
        result = compare(load_stream(left), load_stream(right))
        check("db input", result["traces_old"] == 1)
        check("db mutation detected", result["differing_traces"] == 1)

        jsonl = root / "traces.jsonl"
        jsonl.write_text(json.dumps(base) + "\n\n" + json.dumps(base) + "\n")
        check("jsonl skips blank lines", len(load_stream(jsonl)) == 2)

        bad = root / "bad.jsonl"
        bad.write_text("{not json}\n")
        try:
            load_stream(bad)
            check("malformed jsonl fails", False)
        except SystemExit:
            check("malformed jsonl fails", True)

        try:
            load_stream(root / "absent.jsonl")
            check("missing input fails", False)
        except SystemExit:
            check("missing input fails", True)

    failed = [name for name, ok in checks if not ok]
    if failed:
        print(f"self-test: {len(checks) - len(failed)}/{len(checks)} passed")
        return 1
    print(f"self-test: {len(checks)}/{len(checks)} passed")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, help="pre-change capture DB or JSONL")
    parser.add_argument("--new", type=Path, help="post-change capture DB or JSONL")
    parser.add_argument(
        "--ignore",
        default=",".join(DEFAULT_IGNORES),
        help="comma-separated paths (or prefixes) to skip",
    )
    parser.add_argument("--json", type=Path, help="write the JSON report here")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.old is None or args.new is None:
        parser.error("--old and --new are required unless --self-test is given")

    ignores = tuple(item for item in args.ignore.split(",") if item)
    result = compare(load_stream(args.old), load_stream(args.new), ignores)
    for line in summarize(result):
        print(line)
    if args.json:
        args.json.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return 0 if result["differing_traces"] == 0 and not result["length_mismatch"] else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
