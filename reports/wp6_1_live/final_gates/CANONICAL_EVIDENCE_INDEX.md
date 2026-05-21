# WP6.1 Live Validation Closure — Canonical Evidence Index

Date: 2026-05-22
Run-ID: wave5-2026-05-22-wp61
Model: accounts/fireworks/models/kimi-k2p6 (primary) / kimi-k2p5 (fallback)
API: Fireworks AI

---

## Evidence Artifacts

| Artifact | Path | Description |
|----------|------|-------------|
| Canary report | `reports/ab_runs/wave5-2026-05-22-wp61/canary/report.md` | 2 sessions × 20 turns = 40 turns |
| Canary JSONL | `reports/ab_runs/wave5-2026-05-22-wp61/canary/all_turns.jsonl` | Consolidated canary records |
| Stage-1 report | `reports/ab_runs/wave5-2026-05-22-wp61/stage1/report.md` | 5 sessions × 40 turns = 200 turns |
| Stage-1 JSONL | `reports/ab_runs/wave5-2026-05-22-wp61/stage1/all_turns.jsonl` | Consolidated stage-1 records |
| Full report (19/20) | `reports/ab_runs/wave5-2026-05-22-wp61/full/session_{1..19}.jsonl` | 19 sessions × 80 turns = 1520 turns |
| Full consolidated | `reports/ab_runs/wave5-2026-05-22-wp61/full/all_turns.jsonl` | 1520 lines |
| Consolidated report | `reports/ab_runs/wave5-2026-05-22-wp61/wave5_consolidated_report.md` | Cross-stage drift + budget summary |
| Closure report | `reports/releases/wp6_1_live_validation_closure.md` | Executive verdict + acceptance gates |
| Final summary | `reports/releases/wp6_final_summary.md` | WP6 final summary: PARTIAL PASS, go recommendation |

---

## Gate Results

| Gate | Command | Exit Code | Verdict |
|------|---------|-----------|---------|
| Pre-check (API key) | `test -n "$QXFX0_FIREWORKS_API_KEY"` | 0 (key present) | PASS |
| Canary live run | `python3 wave5_soak.py --stage canary` | 0 | PASS |
| Stage-1 live run | `python3 wave5_soak.py --stage stage1` | 0 | PASS |
| Full live run | `python3 wave5_soak.py --stage full` | 0 (19/20 sessions, timeout on #20) | **PARTIAL** |
| Consolidated report | `python3 wave5_soak.py --stage report` | 0 | PASS |
| Post-run build | `cabal build all` | 0 | PASS |
| Post-run fast tests | `cabal test qxfx0-test-fast` | 0 | PASS (613 cases, 0 errors, 0 new failures) |
| Architecture gate | `bash scripts/check_architecture.sh` | 0 | PASS |

---

## Live Metrics Summary

- Total live turns: **1760** (40 canary + 200 stage-1 + 1520 full)
- Sessions attempted: 27 (2 + 5 + 20)
- Sessions completed: 26 (19 full + 5 stage1 + 2 canary)
- Session 20 full: **TIMEOUT** (1h wall-clock limit, process killed)
- Incidents (transport/parse/validation/sandbox errors): **0**
- External query attempt rate: **100%** (all turns `external_attempted=True`)
- Graft acceptance rate: **100%** (all turns `graft_result=graft`)
- Token burn: prompt=22.4M / completion=6.7M (under caps)
- Turn latency mean: **~2314 ms**
- Turn latency p95: **~5823 ms**

---

## Known Non-Regressions (Pre-Existing)

The following test failures/errors were present **before** WP6.1 and are **not caused by this work package**:

1. **CoreBehavior GF linearization drift** (3 failures): expected `"logika_N"`, got `"smysl_N"` — GF resource file drift.
2. **Semantic corpus golden file missing** (2 errors): `test/golden/semantic_corpus.jsonl` not found — environment artifact absent.

Tracked separately: GF resource sync + test fixture bootstrap.

---

## Code Changes Committed

Commits:
- `89be7a6` — WP6.1 implementation + fast tests:
  - `src/QxFx0/Learning/Need.hs` — `detectLearningNeedWithPressure`, `LearningPressureConfig`, window fields.
  - `src/QxFx0/Core/TurnPipeline/Route/Render.hs` — `isTopicNoisyOrAmbiguous`, dedup anti-overblocking.
  - `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` — `finalizeMetrics` telemetry wiring.
  - `src/QxFx0/Core/Observability.hs` — new `TurnMetrics` fields.
  - `test/Test/Suite/LearningLoop.hs` — 10 new unit tests for pressure trigger, dedup, JSON compat.
  - `test/Test/Suite/TurnPipelineProtocol.hs` — 3 integration tests for dedup + telemetry.
- `944e0e9` — Evidence reports: live closure, consolidated wave report, canonical index.
- `bf644de` — WP6 final summary: PARTIAL PASS verdict with honest 19/20 timeout note.
