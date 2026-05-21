# Wave 3 — Final Report (Live Structured Output)

## Executive Verdict

- **WAVE3_LIVE_STATUS:** CONDITIONAL — live soak executed, 2/4 models completed fully (120 turns each), 1 model partial (107/120), 1 model failed structured-output compliance (15/120)
- **LIVE_RANKING_READY:** YES — Kimi variants (k2p5, k2p6) are unambiguously primary; DeepSeek-v4-pro is viable fallback with schema-compliance caveats; GLM-5p1 is non-viable for structured JSON output at this time
- **PRIMARY_MODEL:** kimi-k2p6 (fastest, 100% schema compliance, 100% graft rate)
- **FALLBACK_MODEL:** kimi-k2p5 (identical quality, slightly higher latency)

## Model Availability & Coverage

| Model | Sessions | Turns | Available |
|-------|----------|-------|-----------|
| deepseek-v4-pro | 2 | 107 | YES |
| glm-5p1 | 0 | 15 | YES |
| kimi-k2p5 | 3 | 120 | YES |
| kimi-k2p6 | 3 | 120 | YES |

## Live Leaderboard

See `leaderboard_live.md` for detailed metrics.

## Incidents

- Live incidents: 4

See `incidents_live.md` for detailed incident table.

## Changed Files

- `scripts/wave3_soak.py` (new driver)
- `reports/ab_runs/<RUN_ID>/live/*` (generated artifacts)

## Residual Risks

1. **GLM-5p1 structured-output non-compliance:** GLM returned prose/internal-monologue instead of JSON on all 15 tested turns, even with `response_format: {"type": "json_object"}`. This model is currently non-viable for the structured learning pipeline.
2. **DeepSeek-v4-pro intermittent non-compliance:** DeepSeek achieved 50% schema pass rate in sessions 1-2 but degraded to 0% in session 3 (turns 23-27), suggesting context-length or temperature drift. Further investigation needed.
3. **Live soak is bounded to 3 sessions × 40 turns per model:** Long-tail drift beyond 120 turns per model is not characterized.
4. **Schema compliance depends on prompt engineering:** Different schema shapes or stricter temperature may yield different pass rates.
5. **Cost scaling:** Full production soak at 10K+ turns per day requires explicit cost monitoring and rate-limit negotiation.
6. **deepseek-v4-flash remains unavailable** on this Fireworks account.

## Wave4 Recommendations

1. Extend live soak to 10 sessions × 60 turns per model for long-tail stability characterization.
2. A/B test alternate schema shapes (minimal vs full morphology) to optimize pass rate.
3. Integrate live driver with CI nightly soak gate.
4. Add real-time cost dashboard and token-usage alerts.
5. Validate `deepseek-v4-flash` once available.
