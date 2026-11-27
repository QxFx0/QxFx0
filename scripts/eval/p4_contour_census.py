#!/usr/bin/env python3
"""P4 self-maintenance contour census (read-only).

Pre-registration: docs/closure/P4_STATE_INTEGRITY_PREREG_2026-11-23.md

Reads one capture database produced by
`scripts/run_user_regime_capture.sh` and counts the four facts the
trace-only `trcConatusContour` sub-record carries, plus the crisis
protocol guard:

  C1  contour present per turn
  C2  blanket invariants hold / violation-count distribution
  C3  committed essence
  C4  non-empty recovery events and the per-cause distribution
      (`ConatusStateIntegrityGate` must stay at 0 per the pre-registration)
  C5  crisis resource availability
  C6  hard-trigger Protocol B (regression guard)

The contour is observational: this tool reports what the trace records.
It cannot and does not claim that any decision reads the contour.

Opens the database `mode=ro`, writes nothing.

Self-test: `--self-test` builds a synthetic database and checks every
counter, the envelope and bare-trace shapes, and the missing-DB failure.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import tempfile
from pathlib import Path

# The frozen tag of `RecoveryStateIntegrityGate` (pre-rename
# `RecoveryConatusGate`).  Kept as a string because it is a wire value.
STATE_INTEGRITY_GATE_TAG = "conatus_gate"
HARD_TRIGGER_TAG = "hard_trigger"

CONTOUR_KEYS = (
    "ctcBlanketIntegrity",
    "ctcRecoveryEvents",
    "ctcEssenceCommitments",
    "ctcCrisisAvailability",
)


def _decode_trace(blob: str) -> dict:
    """Accept both the versioned envelope and a bare trace object."""
    decoded = json.loads(blob)
    if isinstance(decoded, dict) and isinstance(decoded.get("trace"), dict):
        return decoded["trace"]
    if isinstance(decoded, dict):
        return decoded
    raise SystemExit("trace: replay_trace_json is not a JSON object")


def load_traces(db: Path) -> list[dict]:
    if not db.is_file():
        raise SystemExit(f"census: database not found: {db}")
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "select session_id, turn, replay_trace_json from turn_quality "
            "order by session_id, turn"
        ).fetchall()
    finally:
        con.close()
    return [_decode_trace(blob) for _, _, blob in rows]


def census(traces: list[dict]) -> dict:
    total = len(traces)
    present = 0
    blanket_holds = 0
    violations: dict[str, int] = {}
    essence_committed = 0
    recovery_nonempty = 0
    recovery_causes: dict[str, int] = {}
    crisis_available = 0
    hard_protocol_b = 0
    contour_exit_protocol_b = 0

    for trace in traces:
        contour = trace.get("trcConatusContour")
        if not isinstance(contour, dict):
            continue
        if not all(key in contour for key in CONTOUR_KEYS):
            continue
        present += 1

        blanket = contour["ctcBlanketIntegrity"] or {}
        if blanket.get("biInvariantsHold") is True:
            blanket_holds += 1
        count = blanket.get("biViolationCount")
        violations[str(count)] = violations.get(str(count), 0) + 1

        if contour["ctcEssenceCommitments"] == 1:
            essence_committed += 1

        events = contour["ctcRecoveryEvents"] or []
        if events:
            recovery_nonempty += 1
        for cause in events:
            recovery_causes[str(cause)] = recovery_causes.get(str(cause), 0) + 1

        if contour["ctcCrisisAvailability"] is True:
            crisis_available += 1

        regime = trace.get("trcUserRegime") or {}
        crisis = regime.get("urtCrisis") or {}
        if crisis.get("cgtProtocolB") is True:
            cause = crisis.get("cgtCause")
            if cause == HARD_TRIGGER_TAG:
                hard_protocol_b += 1
            else:
                contour_exit_protocol_b += 1

    return {
        "turns": total,
        "c1_contour_present": present,
        "c2_blanket_holds": blanket_holds,
        "c2_violation_counts": dict(sorted(violations.items())),
        "c3_essence_committed": essence_committed,
        "c4_recovery_nonempty": recovery_nonempty,
        "c4_recovery_causes": dict(sorted(recovery_causes.items())),
        "c4_recovery_state_integrity_gate": recovery_causes.get(
            STATE_INTEGRITY_GATE_TAG, 0
        ),
        "c5_crisis_available": crisis_available,
        "c6_hard_protocol_b": hard_protocol_b,
        "c6_contour_exit_protocol_b": contour_exit_protocol_b,
    }


def report(report_data: dict) -> list[str]:
    total = report_data["turns"]
    lines = [
        f"turns: {total}",
        f"C1 contour present: {report_data['c1_contour_present']}/{total}",
        f"C2 blanket holds: {report_data['c2_blanket_holds']}/{total} "
        f"(violations {report_data['c2_violation_counts']})",
        f"C3 essence committed: {report_data['c3_essence_committed']}/{total}",
        f"C4 recovery non-empty: {report_data['c4_recovery_nonempty']}/{total} "
        f"(causes {report_data['c4_recovery_causes']})",
        f"C4 state-integrity gate: "
        f"{report_data['c4_recovery_state_integrity_gate']}/{total}",
        f"C5 crisis availability: {report_data['c5_crisis_available']}/{total}",
        f"C6 hard-trigger Protocol B: {report_data['c6_hard_protocol_b']}/{total} "
        f"(contour exits {report_data['c6_contour_exit_protocol_b']})",
    ]
    return lines


def _synthetic_db(path: Path, traces: list[dict]) -> None:
    con = sqlite3.connect(path)
    try:
        con.execute(
            "create table turn_quality "
            "(session_id text, turn integer, replay_trace_json text)"
        )
        for index, trace in enumerate(traces, 1):
            blob = (
                trace
                if isinstance(trace, str)
                else json.dumps({"replayTraceEnvelopeVersion": 1, "trace": trace})
            )
            con.execute(
                "insert into turn_quality values (?, ?, ?)",
                (f"s-{index}", 1, blob),
            )
        con.commit()
    finally:
        con.close()


def _contour(
    *,
    violations: int = 0,
    essence: int = 1,
    events: list[str] | None = None,
    crisis: bool = True,
) -> dict:
    return {
        "ctcBlanketIntegrity": {
            "biInvariantsHold": violations == 0,
            "biViolationCount": violations,
        },
        "ctcRecoveryEvents": events or [],
        "ctcEssenceCommitments": essence,
        "ctcCrisisAvailability": crisis,
    }


def _synthetic_trace(contour: dict | None, protocol: dict | None = None) -> dict:
    trace: dict = {}
    if contour is not None:
        trace["trcConatusContour"] = contour
    if protocol is not None:
        trace["trcUserRegime"] = {"urtCrisis": protocol}
    return trace


def self_test() -> int:
    checks: list[tuple[str, bool]] = []

    def check(name: str, condition: bool) -> None:
        checks.append((name, bool(condition)))
        if not condition:
            print(f"FAIL {name}")

    traces = [
        _synthetic_trace(_contour()),
        _synthetic_trace(_contour(events=["runtime_degraded"])),
        _synthetic_trace(_contour(essence=0, crisis=False)),
        _synthetic_trace(_contour(violations=2)),
        _synthetic_trace(None),  # pre-P4 trace: no contour, must not count
        _synthetic_trace(_contour(), {"cgtProtocolB": True, "cgtCause": "hard_trigger"}),
        _synthetic_trace(_contour(), {"cgtProtocolB": True, "cgtCause": "contour_exit"}),
        # envelope shape, bare trace shape and a missing sub-key
        json.dumps({"replayTraceEnvelopeVersion": 1, "trace": _synthetic_trace(_contour())}),
        json.dumps(_synthetic_trace(_contour())),
        _synthetic_trace({"ctcBlanketIntegrity": {}}),
    ]

    with tempfile.TemporaryDirectory() as tmp:
        db = Path(tmp) / "capture.db"
        _synthetic_db(db, traces)
        result = census(load_traces(db))

    check("turns", result["turns"] == 10)
    check("c1 present", result["c1_contour_present"] == 8)
    check("c2 holds", result["c2_blanket_holds"] == 7)
    check("c2 distribution", result["c2_violation_counts"] == {"0": 7, "2": 1})
    check("c3 committed", result["c3_essence_committed"] == 7)
    check("c4 non-empty", result["c4_recovery_nonempty"] == 1)
    check(
        "c4 causes",
        result["c4_recovery_causes"] == {"runtime_degraded": 1},
    )
    check("c4 gate", result["c4_recovery_state_integrity_gate"] == 0)
    check("c5 available", result["c5_crisis_available"] == 7)
    check("c6 hard", result["c6_hard_protocol_b"] == 1)
    check("c6 contour exit", result["c6_contour_exit_protocol_b"] == 1)

    with tempfile.TemporaryDirectory() as tmp:
        missing = Path(tmp) / "absent.db"
        try:
            load_traces(missing)
            check("missing db fails", False)
        except SystemExit:
            check("missing db fails", True)

    failed = [name for name, ok in checks if not ok]
    if failed:
        print(f"self-test: {len(checks) - len(failed)}/{len(checks)} passed")
        return 1
    print(f"self-test: {len(checks)}/{len(checks)} passed")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, help="capture database (read-only)")
    parser.add_argument("--json", type=Path, help="write the JSON report here")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if args.db is None:
        parser.error("--db is required unless --self-test is given")

    result = census(load_traces(args.db))
    for line in report(result):
        print(line)
    if args.json:
        args.json.write_text(
            json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
