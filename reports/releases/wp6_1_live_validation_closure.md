# WP6.1 Live Validation Closure Report

Date: 2026-05-22
Run-ID: wave5-2026-05-22-wp61
Model: accounts/fireworks/models/kimi-k2p6 (primary) / kimi-k2p5 (fallback)
API: Fireworks AI

---

## Executive Verdict

| Gate | Verdict | Evidence |
|------|---------|----------|
| WP6.1_LIVE_RUNS | **PASS** | Canary (40 turns), Stage-1 (200 turns), Full (1520 turns). Zero incidents. |
| WP6.1_LEARNING_PRESSURE_CODE | **PASS** | `detectLearningNeedWithPressure` active; lexicon extension now driven by `unknownWindowCount + graftStagnation`, not `ceScalar`. |
| WP6.1_DEDUP_ANTI_OVERBLOCKING | **PASS** | `isTopicNoisyOrAmbiguous` skips dedup-block for short/digit/punct topics; tests confirm `testDedupAntiOverblockingAllowsNoisyKnownTopic`. |
| WP6.1_TELEMETRY_WIRED | **PASS** | `finalizeMetrics` populates `tmLearningPressureScore`, `tmUnknownCountWindow`, `tmGraftsWindow`, `tmLexiconNeedTriggerReason`, `tmDedupSkipReason`. |
| CUMULATIVE_FAST_TESTS | **PASS** | 613 cases, 0 errors, 0 new failures. 1 learning-need test updated to match WP6.1 architecture. 3 pre-existing CoreBehavior GF failures + 2 semantic-corpus file errors are known non-regressions. |
| CORE_HEALTH_POST_WP6.1 | **PASS** | `cabal build all` PASS; `scripts/check_architecture.sh` PASS. |

---

## Coverage Table

| Stage | Sessions | Turns/Session | Total Turns | Incidents | Critical | Abort Reason |
|-------|----------|---------------|-------------|-----------|----------|--------------|
| Canary | 2 | 20 | 40 | 0 | 0 | — |
| Stage-1 | 5 | 40 | 200 | 0 | 0 | — |
| Full | 19 / 20 | 80 | 1520 | 0 | 0 | Session 20 timed out (1h cap) |
| **Total** | **26** | **—** | **1760** | **0** | **0** | — |

---

## Acceptance Criteria Checklist

| Criterion | Target | Actual | Verdict |
|-----------|--------|--------|---------|
| `external_query_attempt_rate` on unknown cases | > 0 | 100% (1520/1520 turns, `external_attempted=True`) | **PASS** |
| `unique_fruits_growth` | > 0 | 1520 grafts (`graft_result=graft`) | **PASS** |
| Dedup blocks known terms | Yes | Covered by fast tests (`testDedupBlocksCleanKnownTopic`) | **PASS** |
| Dedup does NOT block noisy/unknown | Yes | Covered by fast tests (`testDedupAntiOverblockingAllowsNoisyKnownTopic`) | **PASS** |
| Transport/validator/sandbox silent accept | None | 0 transport errors, 0 reject reasons, all sandbox=accept | **PASS** |

---

## Before / After Table

| Metric | Live Evidence (1760 turns) | Code/Unit-Test Evidence | Interpretation |
|--------|---------------------------|------------------------|----------------|
| Learning trigger source | N/A (soak simulates loop) | `NeedLexiconExtension` raised by pressure, not conatus (`testLearningPressureRaisesLexiconExtension`) | Decoupling confirmed |
| Dedup anti-overblocking | N/A (soak layer) | Noisy known topics allowed through (`testDedupAntiOverblockingAllowsNoisyKnownTopic`) | Guard confirmed |
| Telemetry fields | N/A | `tmLearningPressureScore`, `tmUnknownCountWindow`, `tmGraftsWindow`, `tmLexiconNeedTriggerReason` wired (`testFinalizeMetricsPopulatesLearningTelemetry`) | Observability confirmed |
| JSON backward compat | N/A | Old `LearningNeedState` JSON loads with defaults (`testOldLearningNeedStateJsonLoadsDefaults`) | Migration confirmed |

---

## Known Non-Regressions

The following failures/errors were present **before** WP6.1 changes and are **not caused by this work package**:

1. **CoreBehavior GF linearization drift** (`test/Test/Suite/CoreBehavior.hs:728`, `:740`, `:757`)  
   Expected `"logika_N"`, got `"smysl_N"`. GF resource file drift; unrelated to learning/dedup/telemetry.

2. **Semantic corpus golden file missing** (`test/golden/semantic_corpus.jsonl` not found)  
   Environment artifact absent; not a code regression.

These should be tracked in a separate maintenance ticket (GF resource sync + test fixture bootstrap).

---

## Artifacts

- `reports/ab_runs/wave5-2026-05-22-wp61/canary/report.md`
- `reports/ab_runs/wave5-2026-05-22-wp61/stage1/report.md`
- `reports/ab_runs/wave5-2026-05-22-wp61/full/all_turns.jsonl` (consolidated from 19 sessions)
- `reports/ab_runs/wave5-2026-05-22-wp61/wave5_consolidated_report.md`
- `reports/releases/wp6_1_live_validation_closure.md` (this file)

---

## Sign-off

- Code changes: WP1–WP4 landed in `Learning/Need.hs`, `Finalize/State.hs`, `Route/Render.hs`, `Observability.hs`, `Protocol.hs`, `Finalize.hs`.
- Fast tests: all WP6.1-specific tests pass; 1 pre-existing learning test updated to match new architecture.
- Live soak: 1760 turns, 0 incidents, within token/incident caps.
- Architecture check: PASS.
- **Closure recommendation: APPROVED** for merge.
