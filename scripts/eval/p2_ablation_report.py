#!/usr/bin/env python3
"""P2 state-integrity-consumer ablation report (read-only).

Pre-registration: docs/closure/P2_ABLATION_PREREG_2026-11-18.md

Compares two capture run directories produced by
`scripts/run_user_regime_capture.sh`:

  baseline — the hook's env var absent
  ablate   — QXFX0_ABLATE_CONATUS_STABILITY=1

and reports, per the pre-registration's bars:

  P1   surface identity per turn
  P2-5 trace identity per turn (every JSON path, not a summary flag)
  P4   final PerspectiveRegistry identity per session
  P6   dead self-divergence channel census
  P7   threshold-reachability census against every state-integrity consumer

It opens both databases `mode=ro`, writes nothing except the optional
`--json` report, and pins every threshold against the Haskell source so
the census cannot silently measure a different constant than the one the
runtime uses.

Self-test: `--self-test` builds synthetic run directories and checks the
comparison, the censuses, and the pin-drift failure.
"""
import argparse
import json
import re
import sqlite3
import sys
import tempfile
from pathlib import Path

# Ambient values that legitimately differ between any two runs of the
# same binary.  Session ids are normalized instead of ignored, so a
# real change to the field is still caught.
IGNORED_PATHS = {
    "trcReplayEnvelope",
    "esCurrentTime",
    "trcRequestId",
}

THRESHOLD_SOURCES = {
    "stateIntegrityGateThreshold": (
        "src/QxFx0/Self/Salience.hs",
        r"stateIntegrityGateThreshold\s*=\s*([0-9]+(?:\.[0-9]+)?)",
    ),
    "cpStateIntegrityFloor": (
        "src/QxFx0/Types/State/Stance.hs",
        r"cpStateIntegrityFloor\s*=\s*([0-9]+(?:\.[0-9]+)?)",
    ),
    "stateIntegrityLowEnergy": (
        "src/QxFx0/Types/Thresholds/StateIntegrity.hs",
        r"stateIntegrityLowEnergy\s*=\s*([0-9]+(?:\.[0-9]+)?)",
    ),
    "anomalyAntiConatusEnergy": (
        "src/QxFx0/Types/Thresholds/Anomaly.hs",
        r"anomalyAntiConatusEnergy\s*=\s*([0-9]+(?:\.[0-9]+)?)",
    ),
    "emStateIntegrityStructuralFloor": (
        "src/QxFx0/Self/Essence.hs",
        r"emStateIntegrityStructuralFloor\s*=\s*([0-9]+(?:\.[0-9]+)?)",
    ),
}

LADDER_SOURCE = ("src/QxFx0/Core/PipelineIO/Internal.hs",
                 r"siScalar stateIntegrity < ([0-9]+(?:\.[0-9]+)?)")
FAMILY_SOURCE = "resources/config/family_targets.json"

EXPECTED = {
    "stateIntegrityGateThreshold": 0.0,
    "cpStateIntegrityFloor": 5.0,
    "stateIntegrityLowEnergy": 3.0,
    "anomalyAntiConatusEnergy": 5.0,
    "emStateIntegrityStructuralFloor": 7.0,
    "familyMinConatusMax": 3.0,
    "ladder": [0.0, 0.5],
}


def strip_line_comments(text):
    """Drop Haskell line comments before pinning a numeric constant.

    A Haddock note that quotes an old value (e.g. the WP-F unit-fix
    comment recording `0.5` next to the live `7.0`) is documentation,
    not a second definition; treating it as one made the pin ambiguous.
    """
    return "\n".join(line.split("--", 1)[0] for line in text.splitlines())


def pin_thresholds(root):
    """Read every state-integrity threshold from its canonical source.

    Fails loudly when a value moved: the census must measure the
    constants the runtime actually uses.
    """
    root = Path(root)
    values = {}
    for name, (rel, pattern) in THRESHOLD_SOURCES.items():
        text = strip_line_comments((root / rel).read_text(encoding="utf-8"))
        found = [float(x) for x in re.findall(pattern, text)]
        if not found:
            raise SystemExit(f"pin: no {name} in {rel}")
        distinct = sorted(set(found))
        if len(distinct) != 1:
            raise SystemExit(f"pin: {name} is ambiguous in {rel}: {distinct}")
        values[name] = distinct[0]

    text = strip_line_comments((root / LADDER_SOURCE[0]).read_text(encoding="utf-8"))
    ladder = sorted({float(x) for x in re.findall(LADDER_SOURCE[1], text)})
    if not ladder:
        raise SystemExit("pin: no state-integrity priority ladder in Internal.hs")
    values["ladder"] = ladder

    families = json.loads((root / FAMILY_SOURCE).read_text(encoding="utf-8"))
    values["familyMinConatusMax"] = max(t["ftMinConatus"] for t in families)
    values["familyCount"] = len(families)

    for name, expected in EXPECTED.items():
        if values[name] != expected:
            raise SystemExit(
                f"pin drift: {name} = {values[name]!r}, expected {expected!r}; "
                "re-derive the census before reporting it"
            )
    return values


def load_run_id(run_dir):
    """The run id the driver wrote into `meta.env`, else the directory name."""
    meta = Path(run_dir) / "meta.env"
    if meta.exists():
        for line in meta.read_text(encoding="utf-8").splitlines():
            if line.startswith("run_id="):
                return line.split("=", 1)[1].strip()
    return Path(run_dir).name


def normalize_session(session_id, run_id):
    """Strip `cap-<run_id>-`: the dialogue id is what both arms share.

    A run id may itself contain dashes, so the prefix is stripped
    literally rather than split on '-'."""
    prefix = f"cap-{run_id}-"
    return session_id[len(prefix):] if session_id.startswith(prefix) else session_id


def trace_keys(db_path, run_id):
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "select rowid, session_id, turn from turn_quality"
        ).fetchall()
    finally:
        con.close()
    return sorted(
        ((normalize_session(s, run_id), int(t)), rid) for rid, s, t in rows
    )


def fetch_trace(db_path, rowid, run_id):
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        row = con.execute(
            "select replay_trace_json from turn_quality where rowid = ?",
            (rowid,),
        ).fetchone()
    finally:
        con.close()
    if not row:
        return None
    doc = json.loads(row[0])
    trace = doc.get("trace") or {}
    # The session id is chosen by the driver (`cap-<run_id>-<dialogue>`),
    # so it necessarily differs between arms.  Normalize it to the
    # dialogue id: a real change to the field is still caught.
    sid = trace.get("trcSessionId")
    if isinstance(sid, str):
        trace["trcSessionId"] = normalize_session(sid, run_id)
    return trace


def diff_paths(a, b, path="", acc=None):
    if acc is None:
        acc = []
    if path.rsplit(".", 1)[-1] in IGNORED_PATHS:
        return acc
    if type(a) is not type(b):
        acc.append((path, "type", type(a).__name__, type(b).__name__))
        return acc
    if isinstance(a, dict):
        for key in sorted(set(a) | set(b)):
            sub = f"{path}.{key}" if path else key
            if key in IGNORED_PATHS:
                continue
            if key not in a or key not in b:
                acc.append((sub, "missing", key in a, key in b))
                continue
            diff_paths(a[key], b[key], sub, acc)
        return acc
    if isinstance(a, list):
        if len(a) != len(b):
            acc.append((path, "len", len(a), len(b)))
            return acc
        for i, (x, y) in enumerate(zip(a, b)):
            diff_paths(x, y, f"{path}[{i}]", acc)
        return acc
    if a != b:
        acc.append((path, "value", a, b))
    return acc


def compare_traces(baseline_db, baseline_run, ablate_db, ablate_run):
    """Yield (key, [diffs]) turn by turn without holding both corpora."""
    left = trace_keys(baseline_db, baseline_run)
    right = trace_keys(ablate_db, ablate_run)
    if [k for k, _ in left] != [k for k, _ in right]:
        missing = set(k for k, _ in left) ^ set(k for k, _ in right)
        raise SystemExit(f"trace key sets differ: {sorted(missing)[:5]}")
    for (key, lrow), (_, rrow) in zip(left, right):
        lt = fetch_trace(baseline_db, lrow, baseline_run)
        rt = fetch_trace(ablate_db, rrow, ablate_run)
        diffs = diff_paths(lt, rt, "", [])
        if diffs:
            yield key, diffs


def surfaces(run_dir):
    """`raw/<dialogue>-<turn>.json` -> the rendered surface."""
    out = {}
    for path in sorted((Path(run_dir) / "raw").glob("*.json")):
        stem = path.stem
        dialogue, _, turn = stem.rpartition("-")
        try:
            doc = json.loads(path.read_text(encoding="utf-8").strip().splitlines()[-1])
        except (json.JSONDecodeError, IndexError):
            out[(dialogue, int(turn))] = ("<unparseable>", None, None)
            continue
        out[(dialogue, int(turn))] = (
            doc.get("surface"),
            doc.get("family"),
            doc.get("force"),
        )
    return out


def thread_count(registry):
    """Persisted perspective threads (0 when the derived field is stripped)."""
    if not isinstance(registry, dict):
        return 0
    threads = registry.get("threads")
    return len(threads) if isinstance(threads, (list, dict)) else 0


def load_states(db_path, run_id):
    """Final registry + the state-integrity slice recorded in the governance payload.

    The governance event stores 'ppPerspectiveInput', so the ablation is
    visible in the persisted audit history even when no perspective thread
    is created.  That channel is reported post hoc, not as a pre-registered
    bar: the pre-registration's P4 covers the registry only.
    """
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        rows = con.execute(
            "select session_id, value from dialogue_state "
            "where key = '__system_state__'"
        ).fetchall()
    finally:
        con.close()
    out = {}
    for session_id, blob in rows:
        key = normalize_session(session_id, run_id)
        try:
            state = json.loads(blob)
        except json.JSONDecodeError:
            out[key] = ("<unparseable>", [])
            continue
        registry = (state.get("ssSelfState") or {}).get("selfPerspectiveRegistry")
        events = []
        for event in state.get("governanceHistory") or []:
            payload = (event.get("gePayload") or {}).get("contents") or {}
            conatus = ((payload.get("ppPerspectiveInput") or {})
                       .get("pibConatusSlice") or {})
            admissibility = payload.get("ppPerspectiveAdmissibility")
            if isinstance(admissibility, dict):
                admissibility = admissibility.get("tag") or admissibility.get("contents")
            events.append((conatus.get("csStability"), admissibility))
        out[key] = (registry, events)
    return out


def scalar(trace):
    energy = trace.get("trcConatusEnergy") or {}
    value = energy.get("ceScalar")
    return None if value is None else float(value)


def census(baseline_db, run_id, pins):
    """Dead-channel and threshold-reachability census over one arm."""
    thresholds = {
        "salience_gate": pins["stateIntegrityGateThreshold"],
        "stance_floor": pins["cpStateIntegrityFloor"],
        "routing_low_energy": pins["stateIntegrityLowEnergy"],
        "priority_ladder_lo": pins["ladder"][0],
        "priority_ladder_hi": pins["ladder"][1],
        "family_target_min": pins["familyMinConatusMax"],
        "essence_structural_floor": pins["emStateIntegrityStructuralFloor"],
        "anomaly_anti_conatus": pins["anomalyAntiConatusEnergy"],
    }
    reachable = {name: 0 for name in thresholds}
    energies = []
    dead = {"turns": 0, "prediction_active": 0, "total_non_null": 0,
            "window_non_null": 0, "penalty_nonzero": 0}
    # 'shouldCommit' fires conatus erosion only when *every one* of the
    # last 'emStateIntegrityFloorWindow' (8) witnesses is below the floor, so a
    # per-turn count is an upper bound.  Track the real window too.
    floor_window = 8
    windows = {}
    essence_window_fires = 0
    for key, rowid in trace_keys(baseline_db, run_id):
        trace = fetch_trace(baseline_db, rowid, run_id)
        dead["turns"] += 1
        if trace.get("trcSelfDivergencePredictionActive"):
            dead["prediction_active"] += 1
        if trace.get("trcSelfDivergenceTotal") is not None:
            dead["total_non_null"] += 1
        if trace.get("trcSelfDivergenceWindowMean") is not None:
            dead["window_non_null"] += 1
        penalty = trace.get("trcSelfDivergencePenalty")
        if penalty not in (None, 0, 0.0):
            dead["penalty_nonzero"] += 1
        value = scalar(trace)
        if value is None:
            continue
        energies.append(value)
        for name, floor in thresholds.items():
            if value < floor:
                reachable[name] += 1
        dialogue = key[0]
        window = (windows.get(dialogue, []) + [value])[-floor_window:]
        windows[dialogue] = window
        if len(window) == floor_window and all(
                v < pins["emStateIntegrityStructuralFloor"] for v in window):
            essence_window_fires += 1
    energies.sort()
    stats = {}
    if energies:
        n = len(energies)
        stats = {
            "n": n,
            "min": energies[0],
            "median": energies[n // 2],
            "max": energies[-1],
            "above_essence_floor": sum(1 for e in energies if e >= pins["emStateIntegrityStructuralFloor"]),
        }
    return {"thresholds": thresholds, "reachable": reachable,
            "energies": stats, "dead_channel": dead,
            "essence_floor_window": floor_window,
            "essence_window_fires": essence_window_fires}


def build_report(baseline_dir, ablate_dir, pins):
    baseline_dir, ablate_dir = Path(baseline_dir), Path(ablate_dir)
    bdb = baseline_dir / "capture.db"
    adb = ablate_dir / "capture.db"

    base_surface, abl_surface = surfaces(baseline_dir), surfaces(ablate_dir)
    if set(base_surface) != set(abl_surface):
        raise SystemExit("surface key sets differ between arms")
    surface_diffs = sorted(k for k in base_surface if base_surface[k] != abl_surface[k])

    base_run, abl_run = load_run_id(baseline_dir), load_run_id(ablate_dir)
    trace_diffs = list(compare_traces(bdb, base_run, adb, abl_run))

    base_states, abl_states = load_states(bdb, base_run), load_states(adb, abl_run)
    if set(base_states) != set(abl_states):
        raise SystemExit("state session sets differ between arms")
    registry_diffs = sorted(
        session for session in base_states
        if base_states[session][0] != abl_states[session][0]
    )
    # The persisted registry is a *derived* field: canonicalizePersistedState
    # empties it on save (Bridge/StatePersistence.hs) and restore rebuilds it
    # from governanceHistory.  When both arms persist zero threads the
    # identity bar is vacuously true and the report must say so instead of
    # presenting it as a measurement.
    registry_threads = {
        "baseline": sum(thread_count(base_states[s][0]) for s in base_states),
        "ablate": sum(thread_count(abl_states[s][0]) for s in abl_states),
    }
    governance_events = 0
    governance_diffs = []
    governance_deltas = []
    for session in sorted(base_states):
        base_events = base_states[session][1]
        abl_events = abl_states[session][1]
        governance_events += len(base_events)
        if len(base_events) != len(abl_events):
            governance_diffs.append((session, "length", len(base_events), len(abl_events)))
            continue
        for index, (base_event, abl_event) in enumerate(zip(base_events, abl_events)):
            if base_event != abl_event:
                governance_diffs.append((session, index, base_event, abl_event))
                if (isinstance(base_event[0], (int, float))
                        and isinstance(abl_event[0], (int, float))):
                    governance_deltas.append(abl_event[0] - base_event[0])
    governance_mean_delta = (
        sum(governance_deltas) / len(governance_deltas) if governance_deltas else None
    )

    return {
        "turns": len(base_surface),
        "surface_diffs": surface_diffs,
        "trace_diff_turns": [k for k, _ in trace_diffs],
        "trace_diff_paths": sorted({p for _, ds in trace_diffs for p, *_ in ds}),
        "registry_diffs": registry_diffs,
        "registry_threads": registry_threads,
        "registry_vacuous": not any(registry_threads.values()),
        "governance_events": governance_events,
        "governance_diffs": governance_diffs,
        "governance_mean_delta": governance_mean_delta,
        "census_baseline": census(bdb, base_run, pins),
        "census_ablate": census(adb, abl_run, pins),
        "pins": pins,
    }


def print_report(report):
    c = report["census_baseline"]
    print(f"turns compared: {report['turns']}")
    print(f"P1  surface identity: {report['turns'] - len(report['surface_diffs'])}/{report['turns']} identical")
    if report["surface_diffs"]:
        print(f"    differing turns: {report['surface_diffs'][:10]}")
    print(f"P2-5 trace identity: {report['turns'] - len(report['trace_diff_turns'])}/{report['turns']} identical")
    if report["trace_diff_paths"]:
        print(f"    differing paths ({len(report['trace_diff_paths'])}): {report['trace_diff_paths'][:10]}")
    print(f"P4  registry identity: {len(report['registry_diffs'])} sessions differ")
    if report["registry_vacuous"]:
        print("    VACUOUS: 0 threads persisted in both arms "
              "(canonicalizePersistedState strips the derived registry)")
    else:
        print(f"    threads persisted: baseline={report['registry_threads']['baseline']} "
              f"ablate={report['registry_threads']['ablate']}")
    if report["registry_diffs"]:
        print(f"    {report['registry_diffs'][:10]}")
    print(f"post-hoc governance payload (not a bar): "
          f"{len(report['governance_diffs'])}/{report['governance_events']} events differ")
    if report["governance_mean_delta"] is not None:
        print(f"    mean csStability delta (ablate - baseline): "
              f"{report['governance_mean_delta']:+.6f}")
    print("P6  dead self-divergence channel:", c["dead_channel"])
    e = c["energies"]
    if e:
        print(f"    energy n={e['n']} min={e['min']:.4f} median={e['median']:.4f} "
              f"max={e['max']:.4f} above_essence_floor={e['above_essence_floor']}/{e['n']}")
    print("P7  threshold reachability (baseline arm):")
    for name, floor in sorted(c["thresholds"].items()):
        print(f"    {name:26s} floor={floor:<5} reachable={c['reachable'][name]}/{e['n'] if e else 0}")


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _write_arm(root, run_id, prompts, traces, surfaces_, registry, governance=None):
    arm = root / run_id
    (arm / "raw").mkdir(parents=True)
    for (dialogue, turn), prompt in prompts.items():
        (arm / "raw" / f"{dialogue}-{turn}.json").write_text(
            json.dumps({"surface": surfaces_[(dialogue, turn)], "family": "CMDefine",
                        "force": "IFAssert", "input": prompt}),
            encoding="utf-8",
        )
    (arm / "meta.env").write_text(f"run_id={run_id}\n", encoding="utf-8")
    con = sqlite3.connect(arm / "capture.db")
    con.execute("create table turn_quality (session_id text, turn integer, replay_trace_json text)")
    con.execute("create table dialogue_state (session_id text, key text, value text)")
    for (dialogue, turn), trace in traces.items():
        trace = dict(trace)
        trace["trcSessionId"] = f"cap-{run_id}-{dialogue}"
        con.execute(
            "insert into turn_quality values (?,?,?)",
            (f"cap-{run_id}-{dialogue}", turn,
             json.dumps({"replayTraceEnvelopeVersion": 1, "trace": trace})),
        )
    for dialogue in {d for d, _ in traces}:
        con.execute(
            "insert into dialogue_state values (?,?,?)",
            (f"cap-{run_id}-{dialogue}", "__system_state__",
             json.dumps({
                 "ssSelfState": {"selfPerspectiveRegistry": registry[dialogue]},
                 "governanceHistory": (governance or {}).get(dialogue, []),
             })),
        )
    con.commit()
    con.close()


def _fake_pins(root, drift=None):
    root = Path(root)
    for name, (rel, _) in THRESHOLD_SOURCES.items():
        value = EXPECTED[name] if drift is None or drift[0] != name else drift[1]
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        # A historical note quoting an old value must not be read as a
        # second definition (WP-F records 0.5 next to the live 7.0).
        note = "-- historical note: {} = 0.5\n".format(name) if name == "emStateIntegrityStructuralFloor" else ""
        path.write_text(f"{note}{name} = {value}\n", encoding="utf-8")
    ladder = EXPECTED["ladder"] if drift is None or drift[0] != "ladder" else drift[1]
    path = root / LADDER_SOURCE[0]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(f"| siScalar stateIntegrity < {v} = 100" for v in ladder) + "\n",
                    encoding="utf-8")
    path = root / FAMILY_SOURCE
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([{"ftFamily": "A", "ftMinConatus": 0.0},
                                {"ftFamily": "B", "ftMinConatus": 3.0}]), encoding="utf-8")


def _base_trace(energy=14.2, active=False, total=None, window=None, penalty=0.0):
    return {
        "trcConatusEnergy": {"ceScalar": energy, "ceComponents": {}},
        "trcSelfDivergencePredictionActive": active,
        "trcSelfDivergenceTotal": total,
        "trcSelfDivergenceWindowMean": window,
        "trcSelfDivergencePenalty": penalty,
        "trcSessionId": "cap-RUN-d1",
        "trcRequestId": "ambient",
        "trcEffectSnapshot": {"esApiHealthy": True, "esCurrentTime": "2026-11-19T00:00:00Z"},
        "trcPerspectiveProjections": [],
    }


def self_test():
    checks = []

    def check(name, cond):
        checks.append((name, bool(cond)))
        if not cond:
            print(f"FAIL {name}")

    prompts = {("d1", 1): "p1", ("d1", 2): "p2"}
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        _fake_pins(tmp / "pin")

        base_traces = {k: _base_trace() for k in prompts}
        base_surface = {k: "same" for k in prompts}
        registry = {"d1": {"threads": [], "normativeProfiles": []}}
        _write_arm(tmp, "base-run", prompts, base_traces, base_surface, registry)
        _write_arm(tmp, "abl-run", prompts, base_traces, base_surface, registry)

        pins = pin_thresholds(tmp / "pin")
        check("pins read from source", pins["stateIntegrityGateThreshold"] == 0.0
              and pins["familyMinConatusMax"] == 3.0 and pins["ladder"] == [0.0, 0.5])

        rep = build_report(tmp / "base-run", tmp / "abl-run", pins)
        check("identical arms have no surface diff", rep["surface_diffs"] == [])
        check("identical arms have no trace diff", rep["trace_diff_paths"] == [])
        check("identical arms have no registry diff", rep["registry_diffs"] == [])
        check("empty persisted registry is flagged vacuous",
              rep["registry_vacuous"]
              and rep["registry_threads"] == {"baseline": 0, "ablate": 0})
        check("session-id prefix is normalized", rep["turns"] == 2)

        # A single surface character.
        surf2 = dict(base_surface)
        surf2[("d1", 2)] = "same!"
        _write_arm(tmp, "abl-surf", prompts, base_traces, surf2, registry)
        rep = build_report(tmp / "base-run", tmp / "abl-surf", pins)
        check("one surface change is caught", rep["surface_diffs"] == [("d1", 2)])

        # A single trace value.
        tr2 = {k: _base_trace() for k in prompts}
        tr2[("d1", 2)]["trcConatusEnergy"] = {"ceScalar": 13.0, "ceComponents": {}}
        _write_arm(tmp, "abl-trace", prompts, tr2, base_surface, registry)
        rep = build_report(tmp / "base-run", tmp / "abl-trace", pins)
        check("one trace change is caught",
              rep["trace_diff_turns"] == [("d1", 2)]
              and rep["trace_diff_paths"] == ["trcConatusEnergy.ceScalar"])

        # Registry.
        reg2 = {"d1": {"threads": [{"ptPerspectiveId": "x"}], "normativeProfiles": []}}
        _write_arm(tmp, "abl-reg", prompts, base_traces, base_surface, reg2)
        rep = build_report(tmp / "base-run", tmp / "abl-reg", pins)
        check("registry change is caught", rep["registry_diffs"] == ["d1"])
        check("non-empty registry is not flagged vacuous",
              not rep["registry_vacuous"] and rep["registry_threads"]["ablate"] == 1)

        # Ambient fields must not count as differences.
        tr3 = {k: _base_trace() for k in prompts}
        tr3[("d1", 1)]["trcRequestId"] = "other"
        tr3[("d1", 1)]["trcEffectSnapshot"]["esCurrentTime"] = "2027-01-01T00:00:00Z"
        _write_arm(tmp, "abl-amb", prompts, tr3, base_surface, registry)
        rep = build_report(tmp / "base-run", tmp / "abl-amb", pins)
        check("ambient fields are ignored", rep["trace_diff_paths"] == [])

        # The governance payload records the Conatus slice.  It is a
        # post-hoc observation, not a bar: the ablation is expected to
        # change it, and the report must show the difference without
        # failing the identity bars.
        gov_base = {"d1": [{"gePayload": {"contents": {
            "ppPerspectiveInput": {"pibConatusSlice": {"csStability": 0.65}}}}}]}
        gov_abl = {"d1": [{"gePayload": {"contents": {
            "ppPerspectiveInput": {"pibConatusSlice": {"csStability": 0.47}}}}}]}
        _write_arm(tmp, "gov-base", prompts, base_traces, base_surface, registry, gov_base)
        _write_arm(tmp, "gov-abl", prompts, base_traces, base_surface, registry, gov_abl)
        rep = build_report(tmp / "gov-base", tmp / "gov-abl", pins)
        check("governance csStability difference is measured",
              rep["governance_events"] == 1
              and len(rep["governance_diffs"]) == 1
              and abs(rep["governance_mean_delta"] - (-0.18)) < 1e-9)
        check("governance difference is not a bar",
              rep["surface_diffs"] == [] and rep["trace_diff_paths"] == []
              and rep["registry_diffs"] == [])

        # Dead channel census.
        tr4 = {k: _base_trace(active=True, total=0.4, window=0.4, penalty=-0.2) for k in prompts}
        _write_arm(tmp, "dead", prompts, tr4, base_surface, registry)
        rep = build_report(tmp / "base-run", tmp / "dead", pins)
        dead = rep["census_ablate"]["dead_channel"]
        check("dead-channel census counts", dead["prediction_active"] == 2
              and dead["total_non_null"] == 2 and dead["penalty_nonzero"] == 2)
        check("baseline dead-channel is empty",
              build_report(tmp / "base-run", tmp / "abl-run", pins)["census_baseline"]
              ["dead_channel"]["prediction_active"] == 0)

        # Threshold reachability at energy 2.0: 0.0 no, 0.5 no, 3.0 yes,
        # 5.0 no, 7.0 no, family max 3.0 yes.
        tr5 = {k: _base_trace(energy=2.0) for k in prompts}
        _write_arm(tmp, "low", prompts, tr5, base_surface, registry)
        rep = build_report(tmp / "base-run", tmp / "low", pins)
        reach = rep["census_ablate"]["reachable"]
        check("census at 2.0",
              reach["salience_gate"] == 0 and reach["routing_low_energy"] == 2
              and reach["family_target_min"] == 2 and reach["stance_floor"] == 2
              and reach["anomaly_anti_conatus"] == 2
              and reach["priority_ladder_hi"] == 0)
        # 2 turns cannot fill the 8-witness erosion window.
        check("essence erosion needs 8 consecutive sub-floor turns",
              rep["census_ablate"]["essence_window_fires"] == 0
              and rep["census_ablate"]["essence_floor_window"] == 8)
        check("census at 14.2 has no reach",
              all(v == 0 for v in build_report(tmp / "base-run", tmp / "abl-run", pins)
                  ["census_baseline"]["reachable"].values()))

        # Pin drift must fail loudly.
        _fake_pins(tmp / "pin-drift", drift=("stateIntegrityGateThreshold", 0.1))
        try:
            pin_thresholds(tmp / "pin-drift")
            check("pin drift fails", False)
        except SystemExit:
            check("pin drift fails", True)

    passed = sum(1 for _, ok in checks if ok)
    print(f"self-test: {passed}/{len(checks)} passed")
    return 0 if passed == len(checks) else 1


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", help="baseline run directory")
    parser.add_argument("--ablate", help="ablate run directory")
    parser.add_argument("--root", default=".", help="repo root for threshold pins")
    parser.add_argument("--json", help="write the report here")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not (args.baseline and args.ablate):
        parser.error("--baseline and --ablate are required (or --self-test)")

    pins = pin_thresholds(args.root)
    report = build_report(args.baseline, args.ablate, pins)
    print_report(report)
    if args.json:
        Path(args.json).write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n",
                                   encoding="utf-8")
        print(f"report written: {args.json}")

    ok = (not report["surface_diffs"]
          and not report["trace_diff_paths"]
          and not report["registry_diffs"])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
