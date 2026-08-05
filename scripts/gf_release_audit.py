#!/usr/bin/env python3
"""Bounded GF release audit over persistent, session-affine workers.

The audit deliberately separates process/bootstrap cost from warm turn cost.
It also persists every reviewed surface together with its replay trace and can
run a bounded session canary with explicit GF-on and GF-off cohorts.
"""

from __future__ import annotations

import argparse
import collections
import dataclasses
import datetime as dt
import json
import os
import pathlib
import queue
import re
import sqlite3
import statistics
import subprocess
import tempfile
import threading
import time
from typing import Any, Iterable


ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_PROMPTS = ROOT / "spec/gf/release_corpus_prompts.txt"
PHASE_MESSAGE = "Turn pipeline phases completed"
BOOTSTRAP_MESSAGE = "Session bootstrap complete"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", dest="binary", help="qxfx0-main executable")
    parser.add_argument("--prompts", type=pathlib.Path, default=DEFAULT_PROMPTS)
    parser.add_argument("--mode", choices=("latency", "surface", "canary", "all"), default="all")
    parser.add_argument("--canary-sessions", type=int, default=10)
    parser.add_argument("--turns-per-session", type=int, default=3)
    parser.add_argument("--canary-percent", type=int, default=20)
    parser.add_argument("--warm-p95-ms", type=float, default=10_000.0)
    parser.add_argument("--turn-timeout", type=float, default=60.0)
    parser.add_argument("--report-dir", type=pathlib.Path, default=ROOT / "reports/gf-release")
    parser.add_argument("--golden", type=pathlib.Path, default=ROOT / "spec/gf/release_corpus_golden.tsv")
    parser.add_argument("--write-golden", action="store_true")
    return parser.parse_args()


def resolve_binary(explicit: str | None) -> pathlib.Path:
    if explicit:
        path = pathlib.Path(explicit).resolve()
    else:
        result = subprocess.run(
            ["cabal", "list-bin", "qxfx0-main"],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        path = pathlib.Path(result.stdout.strip().splitlines()[-1]).resolve()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise SystemExit(f"qxfx0-main is not executable: {path}")
    return path


def load_prompts(path: pathlib.Path) -> list[str]:
    prompts = [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if not prompts:
        raise SystemExit(f"empty prompt corpus: {path}")
    return prompts


def parse_context(line: str) -> dict[str, str]:
    return dict(re.findall(r"(?:^|\s)([a-z][a-z0-9_]*)=([^\s]+)", line))


def percentile(values: Iterable[float], percentile_value: float) -> float | None:
    ordered = sorted(values)
    if not ordered:
        return None
    index = max(0, min(len(ordered) - 1, int((len(ordered) * percentile_value + 99) // 100) - 1))
    return float(ordered[index])


def unwrap_trace(raw: str) -> dict[str, Any]:
    decoded = json.loads(raw)
    if isinstance(decoded, dict) and "replayTraceEnvelopeVersion" in decoded:
        decoded = decoded.get("trace")
    if not isinstance(decoded, dict):
        raise ValueError("replay trace is not an object")
    return decoded


def read_trace(db_path: pathlib.Path, session_id: str, turn: int) -> dict[str, Any]:
    deadline = time.monotonic() + 5.0
    while True:
        try:
            with sqlite3.connect(db_path) as db:
                row = db.execute(
                    "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? AND turn = ?",
                    (session_id, turn),
                ).fetchone()
            if row:
                return unwrap_trace(row[0])
        except sqlite3.OperationalError:
            pass
        if time.monotonic() >= deadline:
            raise RuntimeError(f"missing replay trace: session={session_id} turn={turn}")
        time.sleep(0.05)


class PersistentWorker:
    def __init__(
        self,
        binary: pathlib.Path,
        session_id: str,
        db_path: pathlib.Path,
        state_dir: pathlib.Path,
        gf_enabled: bool | None,
        runtime_mode: str,
        timeout_seconds: float,
    ) -> None:
        env = os.environ.copy()
        env.update(
            {
                "QXFX0_DB": str(db_path),
                "QXFX0_STATE_DIR": str(state_dir),
                "QXFX0_RUNTIME_MODE": runtime_mode,
                "QXFX0_USE_SELFPLAY": "0",
                "QXFX0_AUTONOMOUS_LEARNING": "0",
                "QXFX0_LEARNING_AUDIT_INTERVAL_SEC": "0",
            }
        )
        if gf_enabled is None:
            env.pop("QXFX0_GF_RUNTIME", None)
        else:
            env["QXFX0_GF_RUNTIME"] = "1" if gf_enabled else "0"
        self.session_id = session_id
        self.db_path = db_path
        self.gf_enabled = gf_enabled is not False
        self.timeout_seconds = timeout_seconds
        self.stdout_queue: queue.Queue[str] = queue.Queue()
        self.stderr_lines: list[str] = []
        self.stderr_condition = threading.Condition()
        self.started_at = time.monotonic()
        self.process = subprocess.Popen(
            [str(binary), "--session-id", session_id, "--worker-stdio"],
            cwd=ROOT,
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            bufsize=1,
        )
        assert self.process.stdout is not None
        assert self.process.stderr is not None
        self.stdout_thread = threading.Thread(target=self._read_stdout, daemon=True)
        self.stderr_thread = threading.Thread(target=self._read_stderr, daemon=True)
        self.stdout_thread.start()
        self.stderr_thread.start()
        self.bootstrap = self._wait_for_log(BOOTSTRAP_MESSAGE, timeout_seconds * 2)
        self.bootstrap_wall_ms = (time.monotonic() - self.started_at) * 1000.0
        self.phase_cursor = 0

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        for line in self.process.stdout:
            self.stdout_queue.put(line.rstrip("\n"))

    def _read_stderr(self) -> None:
        assert self.process.stderr is not None
        for line in self.process.stderr:
            with self.stderr_condition:
                self.stderr_lines.append(line.rstrip("\n"))
                self.stderr_condition.notify_all()

    def _wait_for_log(self, marker: str, timeout_seconds: float, start: int = 0) -> str:
        deadline = time.monotonic() + timeout_seconds
        with self.stderr_condition:
            while True:
                for line in self.stderr_lines[start:]:
                    if marker in line:
                        return line
                if self.process.poll() is not None:
                    tail = "\n".join(self.stderr_lines[-20:])
                    raise RuntimeError(f"worker exited before {marker!r}:\n{tail}")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    tail = "\n".join(self.stderr_lines[-20:])
                    raise TimeoutError(f"timeout waiting for {marker!r}:\n{tail}")
                self.stderr_condition.wait(min(remaining, 0.2))

    def turn(self, prompt: str) -> tuple[dict[str, Any], dict[str, str], float]:
        assert self.process.stdin is not None
        phase_start = len(self.stderr_lines)
        started = time.monotonic()
        command = ["turn", self.session_id, "dialogue", prompt]
        self.process.stdin.write(json.dumps(command, ensure_ascii=False) + "\n")
        self.process.stdin.flush()
        try:
            raw_response = self.stdout_queue.get(timeout=self.timeout_seconds)
        except queue.Empty as exc:
            tail = "\n".join(self.stderr_lines[-30:])
            raise TimeoutError(f"warm turn timeout for {prompt!r}:\n{tail}") from exc
        warm_wall_ms = (time.monotonic() - started) * 1000.0
        response = json.loads(raw_response)
        if response.get("status") != "ok":
            raise RuntimeError(f"worker turn failed: {response}")
        phase_line = self._wait_for_log(PHASE_MESSAGE, 5.0, phase_start)
        return response, parse_context(phase_line), warm_wall_ms

    def close(self) -> None:
        if self.process.poll() is not None:
            return
        assert self.process.stdin is not None
        self.process.stdin.write(json.dumps(["shutdown"]) + "\n")
        self.process.stdin.flush()
        try:
            self.stdout_queue.get(timeout=15.0)
            self.process.wait(timeout=15.0)
        except (queue.Empty, subprocess.TimeoutExpired):
            self.process.terminate()
            try:
                self.process.wait(timeout=5.0)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5.0)

    def __enter__(self) -> "PersistentWorker":
        return self

    def __exit__(self, _exc_type: Any, _exc: Any, _tb: Any) -> None:
        self.close()


def surface_issues(surface: str) -> list[str]:
    issues: list[str] = []
    if not surface.strip():
        return ["empty_surface"]
    if surface != surface.strip():
        issues.append("outer_whitespace")
    if re.search(r"\s+[,.!?;:]", surface):
        issues.append("space_before_punctuation")
    if re.search(r"([,.!?;:])\1", surface):
        issues.append("repeated_punctuation")
    if re.search(r"[!?]\.", surface):
        issues.append("mixed_terminal_punctuation")
    if re.search(r"\b([\w-]+)\s+\1\b", surface, re.IGNORECASE):
        issues.append("adjacent_word_repetition")
    sentences = [
        re.sub(r"\W+", " ", part.lower()).strip()
        for part in re.split(r"(?<=[.!?])\s+", surface)
        if part.strip()
    ]
    if len(sentences) != len(set(sentences)):
        issues.append("duplicate_sentence")
    return issues


def proposition_leaves(node: Any) -> list[str]:
    leaves: list[str] = []
    if isinstance(node, list):
        for item in node:
            leaves.extend(proposition_leaves(item))
        return leaves
    if not isinstance(node, dict):
        return leaves
    tag = node.get("tag")
    contents = node.get("contents")
    if tag == "PropositionPredicate" and isinstance(contents, list):
        leaves.append(" ".join(str(part).strip() for part in contents if str(part).strip()))
        return leaves
    for value in node.values():
        leaves.extend(proposition_leaves(value))
    return leaves


def normalize_semantics(text: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[.!?]+", "", text.lower())).strip()


def semantic_substitutions(surface: str, trace: dict[str, Any]) -> list[str]:
    plan = trace.get("trcResponsePlan")
    if not isinstance(plan, dict):
        return ["missing_response_plan"] if trace.get("trcLinearizationOk") else []
    leaves = proposition_leaves(plan.get("rspPropositions", []))
    normalized_surface = normalize_semantics(surface)
    return [leaf for leaf in leaves if normalize_semantics(leaf) not in normalized_surface]


@dataclasses.dataclass
class TurnAudit:
    cohort: str
    session_id: str
    gf_enabled: bool
    prompt: str
    output: str
    turn: int
    warm_wall_ms: float
    phases_ms: dict[str, float]
    canonical: bool
    fallback_reason: str | None
    recovery: bool
    quality_issues: list[str]
    semantic_substitutions: list[str]
    trace: dict[str, Any]

    def public_dict(self, include_trace: bool = False) -> dict[str, Any]:
        value = dataclasses.asdict(self)
        trace = value.pop("trace", None)
        if include_trace and isinstance(trace, dict):
            value["trace"] = {
                key: trace.get(key)
                for key in (
                    "trcResponsePlan",
                    "trcLinearizationLang",
                    "trcLinearizationOk",
                    "trcFallbackReason",
                    "trcRecoveryCause",
                    "trcRecoveryStrategy",
                    "trcAuthorityClass",
                    "trcAssemblyPath",
                    "trcSurfaceProvenance",
                    "trcEmittedPredicates",
                )
            }
        return value


def phase_values(context: dict[str, str]) -> dict[str, float]:
    values: dict[str, float] = {}
    for name in ("prepare", "plan", "render", "finalize", "total"):
        raw = context.get(f"{name}_ms")
        if raw is not None:
            values[name] = float(raw)
    return values


def audit_turn(
    worker: PersistentWorker,
    cohort: str,
    prompt: str,
) -> TurnAudit:
    response, phase_context, warm_wall_ms = worker.turn(prompt)
    turn = int(response["turns"])
    trace = read_trace(worker.db_path, worker.session_id, turn)
    # The public machine contract intentionally retains the historical
    # surface/text/response aliases; there is no separate output field.
    output = str(response.get("surface", response.get("text", response.get("response", ""))))
    fallback = trace.get("trcFallbackReason")
    canonical = bool(
        trace.get("trcLinearizationOk")
        and trace.get("trcAuthorityClass") == "AuthorityCanonical"
        and trace.get("trcLinearizationLang") in ("QxFx0SyntaxRus", "ru_GF_ATOMS")
    )
    recovery = trace.get("trcRecoveryCause") is not None or trace.get("trcAuthorityClass") == "AuthorityRecovery"
    return TurnAudit(
        cohort=cohort,
        session_id=worker.session_id,
        gf_enabled=worker.gf_enabled,
        prompt=prompt,
        output=output,
        turn=turn,
        warm_wall_ms=warm_wall_ms,
        phases_ms=phase_values(phase_context),
        canonical=canonical,
        fallback_reason=fallback,
        recovery=recovery,
        quality_issues=surface_issues(output),
        semantic_substitutions=semantic_substitutions(output, trace),
        trace=trace,
    )


def run_cold_probe(
    binary: pathlib.Path,
    db_path: pathlib.Path,
    state_dir: pathlib.Path,
    prompt: str,
    runtime_mode: str,
    timeout_seconds: float,
) -> dict[str, Any]:
    env = os.environ.copy()
    env.update(
        {
            "QXFX0_DB": str(db_path),
            "QXFX0_STATE_DIR": str(state_dir),
            "QXFX0_RUNTIME_MODE": runtime_mode,
            "QXFX0_USE_SELFPLAY": "0",
            "QXFX0_AUTONOMOUS_LEARNING": "0",
        }
    )
    env.pop("QXFX0_GF_RUNTIME", None)
    started = time.monotonic()
    result = subprocess.run(
        [str(binary), "--session-id", "gf-cold-probe", "--turn-json", prompt],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=timeout_seconds * 3,
    )
    wall_ms = (time.monotonic() - started) * 1000.0
    if result.returncode != 0:
        raise RuntimeError(f"cold probe failed ({result.returncode}):\n{result.stderr[-4000:]}")
    lines = result.stderr.splitlines()
    bootstrap_line = next(line for line in lines if BOOTSTRAP_MESSAGE in line)
    phase_line = next(line for line in lines if PHASE_MESSAGE in line)
    bootstrap_context = parse_context(bootstrap_line)
    return {
        "cold_cli_wall_ms": wall_ms,
        "bootstrap_ms": float(bootstrap_context["bootstrap_ms"]),
        "pgf_preload_ms": float(bootstrap_context["pgf_preload_ms"]),
        "turn_phases_ms": phase_values(parse_context(phase_line)),
    }


def prepare_strict_witness(binary: pathlib.Path, state_dir: pathlib.Path) -> None:
    env = os.environ.copy()
    env["QXFX0_STATE_DIR"] = str(state_dir)
    result = subprocess.run(
        [str(binary), "--write-agda-witness"],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        encoding="utf-8",
        timeout=60.0,
    )
    if result.returncode != 0:
        raise RuntimeError(f"cannot prepare strict Agda witness: {result.stderr.strip()}")


def summarize_turns(turns: list[TurnAudit]) -> dict[str, Any]:
    fallbacks = collections.Counter(turn.fallback_reason or "none" for turn in turns)
    warm = [turn.warm_wall_ms for turn in turns]
    phase_summary: dict[str, dict[str, float | None]] = {}
    for phase in ("prepare", "plan", "render", "finalize", "total"):
        values = [turn.phases_ms[phase] for turn in turns if phase in turn.phases_ms]
        phase_summary[phase] = {
            "median_ms": statistics.median(values) if values else None,
            "p95_ms": percentile(values, 95),
        }
    return {
        "turns": len(turns),
        "canonical_rate": sum(turn.canonical for turn in turns) / len(turns) if turns else 0.0,
        "fallback_histogram": dict(sorted(fallbacks.items())),
        "recovery_rate": sum(turn.recovery for turn in turns) / len(turns) if turns else 0.0,
        "quality_issue_count": sum(bool(turn.quality_issues) for turn in turns),
        "semantic_substitution_count": sum(bool(turn.semantic_substitutions) for turn in turns),
        "warm_wall_median_ms": statistics.median(warm) if warm else None,
        "warm_wall_p95_ms": percentile(warm, 95),
        "phases": phase_summary,
    }


def write_golden(path: pathlib.Path, turns: list[TurnAudit]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# prompt\texpected_surface"]
    for turn in turns:
        prompt = turn.prompt.replace("\t", " ").replace("\n", " ")
        output = turn.output.replace("\t", " ").replace("\n", "\\n")
        lines.append(f"{prompt}\t{output}")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def compare_golden(path: pathlib.Path, turns: list[TurnAudit]) -> list[dict[str, str]]:
    if not path.exists():
        return [{"error": "golden_missing", "path": str(path)}]
    expected: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        prompt, surface = line.split("\t", 1)
        expected[prompt] = surface.replace("\\n", "\n")
    return [
        {"prompt": turn.prompt, "expected": expected.get(turn.prompt, "<missing>"), "actual": turn.output}
        for turn in turns
        if expected.get(turn.prompt) != turn.output
    ]


def markdown_report(report: dict[str, Any]) -> str:
    lines = ["# GF release audit", "", f"Run: `{report['run_id']}`", ""]
    if "cold_probe" in report:
        cold = report["cold_probe"]
        lines.extend(
            [
                "## Latency split",
                "",
                f"Cold CLI wall: {cold['cold_cli_wall_ms']:.0f} ms; bootstrap: {cold['bootstrap_ms']:.0f} ms; PGF preload: {cold['pgf_preload_ms']:.0f} ms.",
                "Cold CLI wall time is reported separately and is not classified as GF latency.",
                "",
            ]
        )
    for key, title in (("surface_summary", "Surface corpus"), ("canary_summary", "Bounded canary")):
        if key not in report:
            continue
        summary = report[key]
        lines.extend(
            [
                f"## {title}",
                "",
                f"Turns: {summary['turns']}; canonical rate: {summary['canonical_rate']:.4f}; recovery rate: {summary['recovery_rate']:.4f}.",
                f"Fallbacks: `{json.dumps(summary['fallback_histogram'], ensure_ascii=False, sort_keys=True)}`.",
                f"Quality issues: {summary['quality_issue_count']}; semantic substitutions: {summary['semantic_substitution_count']}; warm p95: {summary['warm_wall_p95_ms']:.0f} ms.",
                "",
            ]
        )
    lines.extend(["## Verdict", "", "PASS" if report.get("passed") else "FAIL", ""])
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    binary = resolve_binary(args.binary)
    prompts = load_prompts(args.prompts)
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    args.report_dir.mkdir(parents=True, exist_ok=True)
    report: dict[str, Any] = {
        "run_id": run_id,
        "binary": str(binary),
        "prompt_count": len(prompts),
        "warm_p95_limit_ms": args.warm_p95_ms,
    }
    surface_turns: list[TurnAudit] = []
    canary_turns: list[TurnAudit] = []

    with tempfile.TemporaryDirectory(prefix="qxfx0-gf-release-") as tmp:
        tmp_path = pathlib.Path(tmp)
        db_path = tmp_path / "audit.db"
        state_dir = tmp_path / "state"
        runtime_mode = "strict"
        prepare_strict_witness(binary, state_dir)

        if args.mode in ("latency", "all"):
            report["cold_probe"] = run_cold_probe(
                binary, db_path, state_dir, prompts[0], runtime_mode, args.turn_timeout
            )

        if args.mode in ("latency", "surface", "all"):
            selected_prompts = prompts[:5] if args.mode == "latency" else prompts
            with PersistentWorker(
                binary,
                f"gf-surface-{run_id}",
                db_path,
                state_dir,
                None,
                runtime_mode,
                args.turn_timeout,
            ) as worker:
                report["persistent_bootstrap"] = {
                    "wall_ms": worker.bootstrap_wall_ms,
                    **parse_context(worker.bootstrap),
                }
                for prompt in selected_prompts:
                    surface_turns.append(audit_turn(worker, "surface", prompt))
            report["surface_summary"] = summarize_turns(surface_turns)

        if args.mode in ("canary", "all"):
            session_count = max(1, args.canary_sessions)
            turns_per_session = max(1, args.turns_per_session)
            selected_count = max(1, round(session_count * max(0, min(100, args.canary_percent)) / 100))
            for session_index in range(session_count):
                gf_enabled = session_index < selected_count
                cohort = "canary" if gf_enabled else "control"
                session_id = f"gf-{cohort}-{run_id}-{session_index:02d}"
                with PersistentWorker(
                    binary,
                    session_id,
                    db_path,
                    state_dir,
                    gf_enabled,
                    runtime_mode,
                    args.turn_timeout,
                ) as worker:
                    for turn_index in range(turns_per_session):
                        prompt = prompts[(session_index * turns_per_session + turn_index) % len(prompts)]
                        canary_turns.append(audit_turn(worker, cohort, prompt))
            selected_turns = [turn for turn in canary_turns if turn.gf_enabled]
            control_turns = [turn for turn in canary_turns if not turn.gf_enabled]
            report["canary_scope"] = {
                "sessions": session_count,
                "selected_sessions": selected_count,
                "percent": args.canary_percent,
                "turns_per_session": turns_per_session,
            }
            report["canary_summary"] = summarize_turns(selected_turns)
            report["control_summary"] = summarize_turns(control_turns)

    if surface_turns:
        surface_path = args.report_dir / f"surfaces-{run_id}.jsonl"
        surface_path.write_text(
            "".join(json.dumps(turn.public_dict(include_trace=True), ensure_ascii=False) + "\n" for turn in surface_turns),
            encoding="utf-8",
        )
        report["surface_artifact"] = str(surface_path)
        if args.write_golden:
            write_golden(args.golden, surface_turns)
        if args.golden.exists():
            report["golden_mismatches"] = compare_golden(args.golden, surface_turns)

    if canary_turns:
        canary_path = args.report_dir / f"canary-{run_id}.jsonl"
        canary_path.write_text(
            "".join(json.dumps(turn.public_dict(), ensure_ascii=False) + "\n" for turn in canary_turns),
            encoding="utf-8",
        )
        report["canary_artifact"] = str(canary_path)

    relevant_summaries = [
        report[key]
        for key in ("surface_summary", "canary_summary")
        if key in report
    ]
    report["passed"] = bool(relevant_summaries) and all(
        summary["canonical_rate"] == 1.0
        and summary["fallback_histogram"] == {"none": summary["turns"]}
        and summary["semantic_substitution_count"] == 0
        and summary["quality_issue_count"] == 0
        and summary["warm_wall_p95_ms"] is not None
        and summary["warm_wall_p95_ms"] <= args.warm_p95_ms
        for summary in relevant_summaries
    )
    if report.get("golden_mismatches"):
        report["passed"] = False

    json_path = args.report_dir / f"audit-{run_id}.json"
    md_path = args.report_dir / f"audit-{run_id}.md"
    json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    md_path.write_text(markdown_report(report), encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "json": str(json_path), "markdown": str(md_path)}, ensure_ascii=False))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
