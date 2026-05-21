# Wave 2 — Final Report

## Executive Verdict

- **WAVE2_STATUS:** PASS
- **LIVE_VALIDATED:** YES
- **SIMULATION_VALIDATED:** YES
- **RANKING_READY:** YES

## Model Availability & Coverage

| Model | Live Available | Live Turns | Sim Turns |
|-------|---------------|------------|-----------|
| deepseek-v4-pro | YES | 5 | 600 |
| glm-5p1 | YES | 5 | 600 |
| kimi-k2p5 | YES | 5 | 600 |
| kimi-k2p6 | YES | 5 | 600 |

## Live Leaderboard (Pilot)

See `leaderboard_live.md` for detailed metrics.

## Simulated Leaderboard (Full)

See `leaderboard_simulated.md` for detailed metrics.

## Incidents

- Live incidents: 4
- Simulated incidents: 0

See `incidents.md` for detailed incident table.

## Changed Files

- `scripts/wave2_soak.py` (new driver)
- `scripts/run_wave2.sh` (new wrapper)
- `reports/ab_runs/<RUN_ID>/*` (generated artifacts)

## Residual Risks

1. **Live pilot is small (10 turns/model):** does not capture long-tail stability or session-level drift. Wave3 should extend to 3 sessions × 40 turns.
2. **Structured-output formatting missing:** Live prompts are raw user queries; models return prose, causing parse failures. A production pipeline would use JSON-schema-constrained prompts.
3. **Rate-limit / cost uncertainty:** Fireworks free-tier limits not explicitly tested at 2400-turn scale.
4. **Model availability:** `deepseek-v4-flash` was unavailable on this account; only 4 models tested.

## Wave3 Recommendations

1. Add structured-output prompt templates to the corpus for live evaluation.
2. Increase live pilot to 3 sessions × 40 turns per model (360 turns total live).
3. Add real-time cost tracking and rate-limit backoff to the driver.
4. Integrate live driver into CI with nightly soak gate.
5. Validate `deepseek-v4-flash` once it becomes available on the account.
