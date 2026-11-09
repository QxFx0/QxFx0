#!/usr/bin/env python3
"""M7 golden acceptance gate — mechanical checker.

Pre-registered in docs/closure/M7_GOLDEN_ACCEPTANCE_RULE_2026-10-28.md
(decisions D1-A / D2-A / D3 30/30 / D4 informational).
Amended 2026-11-08 (docs/closure/GF_SLOT_BATCH_GROUP1_RESULT_2026-11-08.md):
nine own-selection rows signed on top of the 2026-10-28 set; the four
group-2 substitutes stay unsigned.

Amended 2026-11-09 (docs/closure/GF_SLOT_BATCH_GROUP2_RESULT_2026-11-09.md):
the group-2 landing removes the substitution, so five more own-selection
rows are signed (013, 017, 020, 024, 025). The old substitute rows stay in
the set; the gate is a membership test, not an exclusive list.

The checker reads a frozen eval run directory and applies the signed rule with
no manual judgement. It aborts if the admissible-set file no longer matches the
pre-registered sha256.

Usage:
    python3 scripts/m7_gate_check.py reports/eval_runs/<run_id> [--db PATH]

Exit codes: 0 = gate passed, 1 = gate failed, 2 = run is not evaluable
(missing trace, frozen-file mismatch, malformed inputs).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path

ADMISSIBLE_PATH = Path("spec/gf/m7_admissible_predicates.tsv")
ADMISSIBLE_SHA256 = "7c3576f221cf2743eb1c2b9688007503ef3ee61869b543bd90376652887ed10f"
SIGNED_DATES = {"2026-10-28", "2026-11-08", "2026-11-09"}
GOLDEN_PATH = Path("spec/gf/release_corpus_golden.tsv")
EXPECTED_TURNS = 30
REQUIRED_MARKERS = ("Тезис:", "Проверка:")
PUNCTUATION = re.compile(r"[.!?;:,]")


def fail(reason: str) -> "NoReturn":  # type: ignore[name-defined]
    print(f"INVALID: {reason}")
    sys.exit(2)


def load_admissible() -> tuple[dict[str, set[str]], dict[str, str]]:
    raw = ADMISSIBLE_PATH.read_bytes()
    # Line endings are normalized before hashing: core.autocrlf rewrites text
    # files on checkout, and the frozen digest must not depend on that.
    data = raw.replace(b"\r\n", b"\n")
    digest = hashlib.sha256(data).hexdigest()
    if digest != ADMISSIBLE_SHA256:
        fail(
            f"admissible-set sha256 mismatch: expected {ADMISSIBLE_SHA256}, got {digest}"
        )
    if data != raw:
        print("note: admissible-set CRLF normalized before hashing (checkout artifact)")
    by_topic: dict[str, set[str]] = {}
    id_to_topic: dict[str, str] = {}
    lines = data.decode("utf-8").splitlines()
    if not lines or lines[0].split("\t")[:4] != [
        "id",
        "topic",
        "admissible_predicate",
        "provenance",
    ]:
        fail("admissible-set header is not the pre-registered one")
    for line in lines[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 6:
            fail(f"malformed admissible-set row: {line!r}")
        rid, topic, predicate, provenance, approver, date = parts
        if provenance not in {"golden", "curated-approved", "fallback-approved"}:
            fail(f"unknown provenance {provenance!r} in row {rid}")
        if approver != "owner" or date not in SIGNED_DATES:
            fail(f"row {rid} is not owner-signed on a pre-registered date")
        by_topic.setdefault(topic, set()).add(normalize(predicate))
        id_to_topic[rid] = topic
    return by_topic, id_to_topic


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", PUNCTUATION.sub("", text.lower())).strip()


def load_golden() -> dict[str, str]:
    golden: dict[str, str] = {}
    for line in GOLDEN_PATH.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        prompt, expected = line.split("\t")
        golden[prompt.strip()] = expected.strip()
    return golden


def find_predicate(node: object) -> str | None:
    if isinstance(node, list):
        for item in node:
            found = find_predicate(item)
            if found is not None:
                return found
        return None
    if isinstance(node, dict):
        if node.get("tag") == "PropositionPredicate":
            contents = node.get("contents")
            if isinstance(contents, list):
                return " ".join(str(part).strip() for part in contents if str(part).strip())
        for value in node.values():
            found = find_predicate(value)
            if found is not None:
                return found
    return None


def load_trace(db_path: Path, session_id: str) -> dict:
    if not db_path.exists():
        fail(f"state database not found: {db_path}")
    with sqlite3.connect(str(db_path)) as conn:
        row = conn.execute(
            "SELECT replay_trace_json FROM turn_quality WHERE session_id=? AND turn=1",
            (session_id,),
        ).fetchone()
    if not row or not row[0]:
        return {}
    trace = json.loads(row[0])
    if isinstance(trace, dict) and "replayTraceEnvelopeVersion" in trace:
        trace = trace.get("trace") or {}
    return trace if isinstance(trace, dict) else {}


def read_surface(raw_file: str) -> str:
    path = Path(raw_file)
    if not path.exists():
        fail(f"raw log not found: {path}")
    for line in reversed(path.read_text(encoding="utf-8", errors="replace").splitlines()):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        surface = payload.get("response") or payload.get("text") or ""
        if surface:
            return surface
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply the pre-registered M7 gate.")
    parser.add_argument("run_dir", type=Path, help="reports/eval_runs/<run_id>")
    parser.add_argument(
        "--db",
        type=Path,
        default=Path.home() / ".local/state/qxfx0/qxfx0.db",
        help="state database holding replay traces (default: %(default)s)",
    )
    args = parser.parse_args()

    run_dir: Path = args.run_dir
    results_path = run_dir / "results.jsonl"
    summary_path = run_dir / "summary.json"
    if not results_path.exists():
        fail(f"results.jsonl not found in {run_dir}")

    admissible, id_to_topic = load_admissible()
    golden = load_golden()
    rows = [
        json.loads(line)
        for line in results_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    summary = json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.exists() else {}

    shim_total = summary.get("authority_shim_count")
    drift_total = summary.get("fallback_drift_count")
    if shim_total is None or drift_total is None:
        fail("summary.json lacks authority_shim_count / fallback_drift_count")

    print(f"run: {run_dir.name}")
    print(f"admissible sets: {ADMISSIBLE_PATH} sha256={ADMISSIBLE_SHA256}")
    print(
        f"{'id':<12} {'auth':<20} {'lin':<5} {'fb':<5} {'struct':<7} "
        f"{'pred':<5} {'exact':<5} note"
    )

    gate_failures: list[str] = []
    exact_hits = 0
    for row in rows:
        rid = row.get("id", "?")
        session_id = row.get("row_session_id") or ""
        surface = read_surface(row.get("raw_file", ""))
        trace = load_trace(args.db, session_id)
        if not trace:
            fail(f"no replay trace for {rid} ({session_id})")

        authority_ok = row.get("authority_class") == "AuthorityCanonical"
        linearization_ok = row.get("linearization_ok") is True
        fallback_ok = row.get("trace_fallback_reason") is None
        structure_ok = all(marker in surface for marker in REQUIRED_MARKERS)
        drift_ok = row.get("fallback_drift") is False

        plan = trace.get("trcResponsePlan") or {}
        predicate = find_predicate(plan.get("rspPropositions") or [])
        topic = id_to_topic.get(rid)
        if topic is None:
            fail(f"{rid} is not present in the frozen admissible sets")
        predicate_ok = predicate is not None and normalize(predicate) in admissible.get(topic, set())

        exact_ok = surface.strip() == golden.get(row.get("prompt", ""), "\0").strip()
        exact_hits += exact_ok

        notes = []
        if not authority_ok:
            notes.append(f"authority={row.get('authority_class')}")
        if not linearization_ok:
            notes.append("linearization not ok")
        if not fallback_ok:
            notes.append(f"fallback_reason={row.get('trace_fallback_reason')}")
        if not structure_ok:
            notes.append("missing thesis/check")
        if not drift_ok:
            notes.append("harness fallback marker")
        if not predicate_ok:
            notes.append(f"predicate not admissible: {predicate!r}")

        if notes:
            gate_failures.append(f"{rid}: " + "; ".join(notes))

        print(
            f"{rid:<12} {str(row.get('authority_class')):<20} "
            f"{str(linearization_ok):<5} {str(fallback_ok):<5} "
            f"{str(structure_ok):<7} {str(predicate_ok):<5} "
            f"{str(exact_ok):<5} {'; '.join(notes)}"
        )

    aggregate_ok = shim_total == 0 and drift_total == 0
    if not aggregate_ok:
        gate_failures.append(
            f"aggregate: authority_shim_count={shim_total}, fallback_drift_count={drift_total}"
        )

    print()
    print(f"turns checked: {len(rows)} (expected {EXPECTED_TURNS})")
    print(f"structural + predicate gate: {len(rows) - len([f for f in gate_failures if not f.startswith('aggregate:')])}/{len(rows)}")
    print(f"authority_shim_count={shim_total} fallback_drift_count={drift_total}")
    print(f"informational exact-surface match: {exact_hits}/{len(rows)} (never blocking, D4)")

    if len(rows) != EXPECTED_TURNS:
        gate_failures.append(f"expected {EXPECTED_TURNS} turns, got {len(rows)}")

    if gate_failures:
        print()
        print("GATE FAILED")
        for failure in gate_failures:
            print(f"  - {failure}")
        return 1

    print()
    print("GATE PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
