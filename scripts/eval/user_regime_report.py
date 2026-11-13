#!/usr/bin/env python3
"""Read-only user-regime report over the QxFx0 trace database.

Concept v3 writes a per-turn ``trcUserRegime`` sub-record into
``turn_quality.replay_trace_json``.  The eval harness runs isolated
one-turn sessions, so the multi-turn evidence (prediction residual,
bounded window, contour membership, ontological move) never accumulates.
This reader turns the stored traces into that evidence:

    python3 scripts/eval/user_regime_report.py --db capture.db --session-prefix cap-

It never writes to the database (opened ``mode=ro``) and is not on the
runtime authority path (see ``scripts/eval/NON_AUTHORITY.txt``).

The three flags mirror ``QxFx0.Observability.TraceAnalysis.analyzeUserRegime``
exactly, including its first-match order.  Two numeric constants are
mirrored and pinned against the Haskell source by ``--self-test``:

* ``userResidualAnomalyThreshold`` (0.35) — ``TraceAnalysis.hs``
* ``vcAbsoluteFloor`` (0.05) — ``Types/User/R5.hs``

Pre-registration: ``docs/closure/USER_REGIME_CAPTURE_PREREG_2026-11-13.md``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
from collections import Counter
from pathlib import Path

# Mirrored from the Haskell source; pinned by --self-test.
USER_RESIDUAL_ANOMALY_THRESHOLD = 0.35
VC_ABSOLUTE_FLOOR = 0.05
CONTOUR_EXIT_CAUSE = "contour_exit"
R5_ENCODER_VERSION = 1

MOVE_TAGS = (
    "MoveMirrorState",
    "MoveEstablishResonance",
    "MoveAffirmBeing",
    "MoveOpenAlternative",
)


# --------------------------------------------------------------------------
# Trace decoding
# --------------------------------------------------------------------------


def unwrap_trace(raw):
    """Decode the stored envelope ``{replayTraceEnvelopeVersion, trace}``.

    Accepts a bare trace dict too (older rows and synthetic fixtures).
    Returns ``None`` for anything that is not a JSON object.
    """
    if isinstance(raw, (bytes, bytearray)):
        raw = raw.decode("utf-8", errors="replace")
    if not isinstance(raw, str):
        return None
    try:
        decoded = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return None
    if isinstance(decoded, dict) and "replayTraceEnvelopeVersion" in decoded:
        decoded = decoded.get("trace")
    return decoded if isinstance(decoded, dict) else None


def regime_of(trace):
    """Return the ``trcUserRegime`` sub-record, or ``None``."""
    if not isinstance(trace, dict):
        return None
    regime = trace.get("trcUserRegime")
    return regime if isinstance(regime, dict) else None


def _number(value):
    """A JSON number or ``None``; rejects bools (which are ints in Python)."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value)


def _sub(regime, key):
    value = regime.get(key)
    return value if isinstance(value, dict) else {}


def user_r5(regime):
    return _sub(regime, "urtUserR5")


def crisis(regime):
    return _sub(regime, "urtCrisis")


def ontological_move(regime):
    value = regime.get("urtOntologicalMove")
    return value if isinstance(value, dict) else None


def contour_exit_class(regime):
    """``absolute_floor``, ``relative`` or ``None``.

    The runtime decides membership; this only names which branch of
    ``outsideViabilityContour`` produced it, from the observed score.
    """
    state = user_r5(regime)
    if state.get("ur5OutsideContour") is not True:
        return None
    score = _number(state.get("ur5ConatusScore"))
    if score is None:
        return "unknown"
    return "absolute_floor" if score < VC_ABSOLUTE_FLOOR else "relative"


def flags_of(regime):
    """All applicable flags, and the first one (the ``analyzeUserRegime`` result)."""
    state = user_r5(regime)
    cause = crisis(regime).get("cgtCause")
    residual = _number(state.get("ur5PredictionError"))
    window_mean = _number(state.get("ur5WindowMean"))
    flags = []
    if cause == CONTOUR_EXIT_CAUSE:
        flags.append("user_contour_exit")
    if residual is not None and residual > USER_RESIDUAL_ANOMALY_THRESHOLD:
        flags.append("user_model_high_residual")
    if window_mean is not None and window_mean > USER_RESIDUAL_ANOMALY_THRESHOLD:
        flags.append("user_model_sustained_residual")
    return flags, (flags[0] if flags else None)


def decode_row(session_id, turn, raw):
    """One per-turn record, or ``None`` when the row carries no regime."""
    trace = unwrap_trace(raw)
    regime = regime_of(trace)
    if regime is None:
        return None
    state = user_r5(regime)
    move = ontological_move(regime)
    flags, flag = flags_of(regime)
    return {
        "session": session_id,
        "turn": turn,
        "protocol_b": crisis(regime).get("cgtProtocolB") is True,
        "crisis_cause": crisis(regime).get("cgtCause"),
        "resonance": _number(state.get("ur5Resonance")),
        "atmosphere": _number(state.get("ur5Atmosphere")),
        "confidence": _number(state.get("ur5Confidence")),
        "consolidation": _number(state.get("ur5Consolidation")),
        "counterfactual": _number(state.get("ur5Counterfactual")),
        "conatus_score": _number(state.get("ur5ConatusScore")),
        "baseline": _number(state.get("ur5Baseline")),
        "outside_contour": state.get("ur5OutsideContour") is True,
        "exit_class": contour_exit_class(regime),
        "prediction_error": _number(state.get("ur5PredictionError")),
        "window_mean": _number(state.get("ur5WindowMean")),
        "move": move.get("omtMove") if move else None,
        "move_distance_before": _number(move.get("omtDistanceBefore")) if move else None,
        "move_distance_after": _number(move.get("omtDistanceAfter")) if move else None,
        "affirm_gate_passed": move.get("omtAffirmGatePassed") is True if move else None,
        "ontological": regime.get("urtOntologicalVector") if isinstance(
            regime.get("urtOntologicalVector"), dict
        ) else {},
        "encoder_version": regime.get("urtEncoderVersion"),
        "regime_version": trace.get("trcRegimeVersion"),
        "flags": flags,
        "flag": flag,
    }


# --------------------------------------------------------------------------
# Aggregation
# --------------------------------------------------------------------------


def _stats(values):
    values = [v for v in values if v is not None]
    if not values:
        return {"n": 0, "mean": None, "max": None, "over_threshold": 0}
    return {
        "n": len(values),
        "mean": sum(values) / len(values),
        "max": max(values),
        "over_threshold": sum(1 for v in values if v > USER_RESIDUAL_ANOMALY_THRESHOLD),
    }


def aggregate(records, turns_scanned, missing_regime):
    sessions = {}
    for record in records:
        sessions.setdefault(record["session"], []).append(record)

    detail = []
    for session_id in sorted(sessions):
        rows = sorted(sessions[session_id], key=lambda r: r["turn"])
        exits = [r for r in rows if r["outside_contour"]]
        moves = [r for r in rows if r["move"]]
        detail.append(
            {
                "session": session_id,
                "turns": len(rows),
                "protocol_b": sum(1 for r in rows if r["protocol_b"]),
                "exits": len(exits),
                "exit_classes": dict(Counter(r["exit_class"] for r in exits)),
                "moves": len(moves),
                "move_tags": dict(Counter(r["move"] for r in moves)),
                "affirm_gate_passed": sum(1 for r in moves if r["affirm_gate_passed"]),
                "residual": _stats(r["prediction_error"] for r in rows),
                "window": _stats(r["window_mean"] for r in rows),
                "score_min": min(
                    (r["conatus_score"] for r in rows if r["conatus_score"] is not None),
                    default=None,
                ),
                "score_max": max(
                    (r["conatus_score"] for r in rows if r["conatus_score"] is not None),
                    default=None,
                ),
                "flags": dict(Counter(r["flag"] for r in rows if r["flag"])),
            }
        )

    exits = [r for r in records if r["outside_contour"]]
    moves = [r for r in records if r["move"]]
    return {
        "turns_scanned": turns_scanned,
        "turns_with_regime": len(records),
        "missing_regime": missing_regime,
        "sessions": len(sessions),
        "protocol_b": sum(1 for r in records if r["protocol_b"]),
        "protocol_b_causes": dict(
            Counter(r["crisis_cause"] for r in records if r["protocol_b"])
        ),
        "contour_exits": len(exits),
        "contour_exit_classes": dict(Counter(r["exit_class"] for r in exits)),
        "moves": len(moves),
        "move_tags": dict(Counter(r["move"] for r in moves)),
        "affirm_gate_passed": sum(1 for r in moves if r["affirm_gate_passed"]),
        "residual": _stats(r["prediction_error"] for r in records),
        "window": _stats(r["window_mean"] for r in records),
        "flags": dict(Counter(r["flag"] for r in records if r["flag"])),
        "encoder_versions": sorted(
            {r["encoder_version"] for r in records if r["encoder_version"] is not None}
        ),
        "regime_versions": sorted(
            {r["regime_version"] for r in records if r["regime_version"] is not None}
        ),
        "session_detail": detail,
        "records": records,
    }


# --------------------------------------------------------------------------
# Database access (read-only)
# --------------------------------------------------------------------------


def default_db_path():
    for name in ("QXFX0_DB", "QXFX0_DB_PATH"):
        value = os.environ.get(name)
        if value:
            return value
    state_dir = os.environ.get("QXFX0_STATE_DIR")
    if state_dir:
        return str(Path(state_dir) / "qxfx0.db")
    xdg = os.environ.get("XDG_STATE_HOME")
    if xdg:
        return str(Path(xdg) / "qxfx0" / "qxfx0.db")
    return str(Path.home() / ".local" / "state" / "qxfx0" / "qxfx0.db")


def read_records(db_path, session_prefix=None):
    path = Path(db_path)
    if not path.is_file():
        raise SystemExit(f"database not found: {db_path}")
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=5.0)
    try:
        query = "SELECT session_id, turn, replay_trace_json FROM turn_quality"
        params = ()
        if session_prefix:
            # Prefix match without LIKE wildcards: an operator-supplied '%'
            # or '_' must match literally.
            query += " WHERE substr(session_id, 1, length(?)) = ?"
            params = (session_prefix, session_prefix)
        query += " ORDER BY session_id, turn"
        rows = connection.execute(query, params).fetchall()
    except sqlite3.Error as error:
        raise SystemExit(f"cannot read turn_quality: {error}")
    finally:
        connection.close()

    records = []
    missing = 0
    for session_id, turn, raw in rows:
        record = decode_row(session_id, turn, raw)
        if record is None:
            missing += 1
        else:
            records.append(record)
    return records, len(rows), missing


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------


def _fmt(value, digits=3):
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def render_summary(result, db_path, prefix):
    lines = [
        "# User-regime report",
        f"db: {db_path}",
        f"session-prefix: {prefix or '(all)'}",
        "",
        f"turns scanned:     {result['turns_scanned']}",
        f"turns with regime: {result['turns_with_regime']}"
        f"  (missing: {result['missing_regime']})",
        f"sessions:          {result['sessions']}",
        f"protocol B:        {result['protocol_b']}"
        + (
            f"  causes={result['protocol_b_causes']}"
            if result["protocol_b_causes"]
            else ""
        ),
        f"contour exits:     {result['contour_exits']}"
        + (
            f"  classes={result['contour_exit_classes']}"
            if result["contour_exit_classes"]
            else ""
        ),
        f"moves fired:       {result['moves']}"
        + (f"  tags={result['move_tags']}" if result["move_tags"] else ""),
        f"affirm gate:       {result['affirm_gate_passed']} passed",
        f"residual:          n={result['residual']['n']}"
        f" mean={_fmt(result['residual']['mean'])}"
        f" max={_fmt(result['residual']['max'])}"
        f" over-{USER_RESIDUAL_ANOMALY_THRESHOLD}={result['residual']['over_threshold']}",
        f"window mean:       n={result['window']['n']}"
        f" mean={_fmt(result['window']['mean'])}"
        f" max={_fmt(result['window']['max'])}"
        f" over-{USER_RESIDUAL_ANOMALY_THRESHOLD}={result['window']['over_threshold']}",
        f"encoder versions:  {result['encoder_versions']}",
        f"regime versions:   {result['regime_versions']}",
        f"flags:             {result['flags'] or '-'}",
        "",
        "session                                 turns  b  exits  moves  resid_n  resid_mean  resid_max  win_max  score_min  flags",
    ]
    for row in result["session_detail"]:
        lines.append(
            f"{row['session'][:39]:39s} {row['turns']:5d} {row['protocol_b']:2d}"
            f" {row['exits']:6d} {row['moves']:6d} {row['residual']['n']:8d}"
            f" {_fmt(row['residual']['mean']):>10s} {_fmt(row['residual']['max']):>9s}"
            f" {_fmt(row['window']['max']):>8s} {_fmt(row['score_min']):>9s}"
            f"  {row['flags'] or '-'}"
        )
    return "\n".join(lines)


def render_turns(result):
    lines = [
        "",
        "per-turn detail",
        "session                                 turn  proto  cause         score   baseline  outside  exit_class      resid   win_mean  move                    gate   flags",
    ]
    for record in result["records"]:
        onto = record["ontological"]
        lines.append(
            f"{record['session'][:39]:39s} {record['turn']:4d}"
            f"  {'B' if record['protocol_b'] else 'A':5s}"
            f"  {str(record['crisis_cause'] or '-'):12s}"
            f"  {_fmt(record['conatus_score']):>6s}"
            f"  {_fmt(record['baseline']):>8s}"
            f"  {str(record['outside_contour']):>7s}"
            f"  {str(record['exit_class'] or '-'):14s}"
            f"  {_fmt(record['prediction_error']):>6s}"
            f"  {_fmt(record['window_mean']):>8s}"
            f"  {str(record['move'] or '-'):22s}"
            f"  {str(record['affirm_gate_passed']):>5s}"
            f"  {','.join(record['flags']) or '-'}"
            f"  onto=({_fmt(onto.get('ovBeing'), 0)},{_fmt(onto.get('ovStriving'), 0)},{_fmt(onto.get('ovAffirmation'), 0)})"
        )
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Self-test
# --------------------------------------------------------------------------

CASES = []


def case(name):
    def register(fn):
        CASES.append((name, fn))
        return fn

    return register


def _trace(regime, **extra):
    trace = {"trcRegimeVersion": 4, **extra}
    if regime is not None:
        trace["trcUserRegime"] = regime
    return trace


def _regime(
    *,
    protocol_b=False,
    cause=None,
    score=0.25,
    outside=False,
    residual=None,
    window_mean=None,
    move=None,
    encoder=1,
):
    return {
        "urtCrisis": {
            "cgtProtocolB": protocol_b,
            "cgtCause": cause,
            "cgtCategory": None,
            "cgtResourceVersion": 0,
        },
        "urtUserR5": {
            "ur5Resonance": 0.7,
            "ur5Atmosphere": 0.25,
            "ur5Confidence": 0.5,
            "ur5Consolidation": 0.5,
            "ur5Counterfactual": 0.48,
            "ur5ConatusScore": score,
            "ur5Baseline": 0.3,
            "ur5OutsideContour": outside,
            "ur5PredictionError": residual,
            "ur5WindowMean": window_mean,
        },
        "urtOntologicalVector": {"ovBeing": 0, "ovStriving": 0, "ovAffirmation": 0},
        "urtOntologicalMove": move,
        "urtEncoderVersion": encoder,
    }


@case("envelope unwrap")
def _case_envelope():
    trace = _trace(_regime())
    raw = json.dumps({"replayTraceEnvelopeVersion": 1, "trace": trace})
    assert unwrap_trace(raw) == trace


@case("bare trace without envelope")
def _case_bare():
    trace = _trace(_regime())
    assert unwrap_trace(json.dumps(trace)) == trace


@case("invalid JSON decodes to None")
def _case_invalid():
    assert unwrap_trace("{not json") is None
    assert unwrap_trace(None) is None


@case("missing regime is skipped")
def _case_missing_regime():
    assert decode_row("s", 1, json.dumps(_trace(None))) is None


@case("null residual and window mean stay null")
def _case_nulls():
    record = decode_row("s", 1, json.dumps(_trace(_regime())))
    assert record["prediction_error"] is None
    assert record["window_mean"] is None
    assert record["flag"] is None


@case("contour exit flag")
def _case_contour_flag():
    record = decode_row(
        "s", 2, json.dumps(_trace(_regime(cause=CONTOUR_EXIT_CAUSE, outside=True, score=0.02)))
    )
    assert record["flag"] == "user_contour_exit"
    assert record["exit_class"] == "absolute_floor"


@case("contour exit wins over high residual")
def _case_flag_order():
    record = decode_row(
        "s",
        2,
        json.dumps(
            _trace(
                _regime(
                    cause=CONTOUR_EXIT_CAUSE,
                    outside=True,
                    score=0.2,
                    residual=0.9,
                    window_mean=0.9,
                )
            )
        ),
    )
    assert record["flag"] == "user_contour_exit"
    assert record["flags"] == [
        "user_contour_exit",
        "user_model_high_residual",
        "user_model_sustained_residual",
    ]
    assert record["exit_class"] == "relative"


@case("high residual flag")
def _case_high_residual():
    record = decode_row(
        "s", 3, json.dumps(_trace(_regime(residual=USER_RESIDUAL_ANOMALY_THRESHOLD + 0.01)))
    )
    assert record["flag"] == "user_model_high_residual"


@case("sustained residual flag")
def _case_sustained():
    record = decode_row(
        "s",
        4,
        json.dumps(_trace(_regime(residual=0.1, window_mean=USER_RESIDUAL_ANOMALY_THRESHOLD + 0.01))),
    )
    assert record["flag"] == "user_model_sustained_residual"


@case("threshold boundary is strict")
def _case_boundary():
    record = decode_row(
        "s", 3, json.dumps(_trace(_regime(residual=USER_RESIDUAL_ANOMALY_THRESHOLD)))
    )
    assert record["flag"] is None


@case("exit class absolute versus relative")
def _case_exit_class():
    absolute = _regime(outside=True, score=VC_ABSOLUTE_FLOOR - 0.001)
    relative = _regime(outside=True, score=VC_ABSOLUTE_FLOOR)
    assert contour_exit_class(absolute) == "absolute_floor"
    assert contour_exit_class(relative) == "relative"
    assert contour_exit_class(_regime(outside=False)) is None


@case("aggregate counts and stats")
def _case_aggregate():
    records = [
        decode_row("s1", 1, json.dumps(_trace(_regime()))),
        decode_row("s1", 2, json.dumps(_trace(_regime(residual=0.2)))),
        decode_row(
            "s2",
            1,
            json.dumps(
                _trace(
                    _regime(
                        cause=CONTOUR_EXIT_CAUSE,
                        outside=True,
                        score=0.01,
                        residual=0.4,
                        move={
                            "omtMove": "MoveMirrorState",
                            "omtDistanceBefore": 0.5,
                            "omtDistanceAfter": 0.4,
                            "omtAffirmGatePassed": True,
                        },
                    )
                )
            ),
        ),
    ]
    result = aggregate(records, 3, 0)
    assert result["sessions"] == 2
    assert result["turns_with_regime"] == 3
    assert result["contour_exits"] == 1
    assert result["contour_exit_classes"] == {"absolute_floor": 1}
    assert result["moves"] == 1
    assert result["move_tags"] == {"MoveMirrorState": 1}
    assert result["affirm_gate_passed"] == 1
    assert result["residual"]["n"] == 2
    assert abs(result["residual"]["mean"] - 0.3) < 1e-9
    assert result["residual"]["max"] == 0.4
    assert result["residual"]["over_threshold"] == 1
    assert result["encoder_versions"] == [1]
    assert result["flags"] == {"user_contour_exit": 1}
    assert [row["session"] for row in result["session_detail"]] == ["s1", "s2"]


@case("prefix filtering")
def _case_prefix():
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "traces.db"
        connection = sqlite3.connect(db_path)
        connection.execute(
            "CREATE TABLE turn_quality (session_id TEXT, turn INT, replay_trace_json TEXT)"
        )
        for session_id in ("cap-a", "cap-b", "other"):
            connection.execute(
                "INSERT INTO turn_quality VALUES (?, 1, ?)",
                (session_id, json.dumps(_trace(_regime()))),
            )
        connection.commit()
        connection.close()

        all_records, scanned, missing = read_records(db_path)
        assert (len(all_records), scanned, missing) == (3, 3, 0)
        filtered, scanned, missing = read_records(db_path, "cap-")
        assert [r["session"] for r in filtered] == ["cap-a", "cap-b"]
        assert (scanned, missing) == (2, 0)
        assert aggregate(filtered, scanned, missing)["sessions"] == 2
        # A prefix containing LIKE wildcards must match literally.
        none, scanned, _ = read_records(db_path, "cap_")
        assert (none, scanned) == ([], 0)


@case("reader mirrors the Haskell residual threshold")
def _case_threshold_mirror():
    root = Path(__file__).resolve().parents[2]
    source = root / "src" / "QxFx0" / "Observability" / "TraceAnalysis.hs"
    if not source.is_file():
        raise AssertionError(f"cannot locate {source}")
    match = re.search(
        r"^userResidualAnomalyThreshold\s*=\s*([0-9.]+)\s*$",
        source.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if not match:
        raise AssertionError("userResidualAnomalyThreshold not found in TraceAnalysis.hs")
    assert abs(float(match.group(1)) - USER_RESIDUAL_ANOMALY_THRESHOLD) < 1e-12, (
        f"Haskell {match.group(1)} != Python {USER_RESIDUAL_ANOMALY_THRESHOLD}"
    )


@case("reader mirrors the Haskell absolute floor")
def _case_floor_mirror():
    root = Path(__file__).resolve().parents[2]
    source = root / "src" / "QxFx0" / "Types" / "User" / "R5.hs"
    if not source.is_file():
        raise AssertionError(f"cannot locate {source}")
    match = re.search(
        r"vcAbsoluteFloor\s*=\s*([0-9.]+)", source.read_text(encoding="utf-8")
    )
    if not match:
        raise AssertionError("vcAbsoluteFloor not found in Types/User/R5.hs")
    assert abs(float(match.group(1)) - VC_ABSOLUTE_FLOOR) < 1e-12, (
        f"Haskell {match.group(1)} != Python {VC_ABSOLUTE_FLOOR}"
    )


def self_test():
    failures = 0
    for name, fn in CASES:
        try:
            fn()
        except AssertionError as error:
            failures += 1
            print(f"FAIL {name}: {error}")
        else:
            print(f"ok   {name}")
    total = len(CASES)
    print(f"\n{total - failures}/{total} cases passed")
    return 0 if failures == 0 else 2


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Read-only user-regime report over turn_quality traces."
    )
    parser.add_argument("--db", help="trace database (default: runtime resolution)")
    parser.add_argument("--session-prefix", default=None, help="only sessions starting with this")
    parser.add_argument("--verbose", action="store_true", help="per-turn table")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--self-test", action="store_true", help="run the built-in cases")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    db_path = args.db or default_db_path()
    records, scanned, missing = read_records(db_path, args.session_prefix)
    result = aggregate(records, scanned, missing)
    result["db"] = db_path
    result["session_prefix"] = args.session_prefix

    if args.json:
        payload = dict(result)
        payload.pop("records", None)
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return 0

    print(render_summary(result, db_path, args.session_prefix))
    if args.verbose:
        print(render_turns(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
