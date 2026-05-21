# Wave 4 — Intelligence Delta A/B (Baseline vs Post-Learning)

**Baseline:** Wave3 kimi-k2p6 pilot (120 turns, 3 sessions × 40 turns)
**Post-Learning:** Wave4 kimi-k2p6 long-run (600 turns, 10 sessions × 60 turns)

## Metric Comparison

| Metric | Baseline (Wave3) | Post-Learning (Wave4) | Delta | Verdict |
|--------|------------------|----------------------|-------|---------|
| Graft accept rate | 1.0 | 1.000 | +0.000 | NO_CHANGE |
| Schema pass rate | 1.0 | 1.000 | +0.000 | NO_CHANGE |
| Validation pass rate | 1.0 | 1.000 | +0.000 | NO_CHANGE |
| Sandbox pass rate | 1.0 | 1.000 | +0.000 | NO_CHANGE |
| Avg latency (ms) | 2260 | 3150.722 | +890.722 | REGRESSED |
| P95 latency (ms) | 6193 | 8486.000 | +2293.000 | REGRESSED |
| Transport error rate | 0.0 | 0.000 | +0.000 | NO_CHANGE |
| Parse reject rate | 0.0 | 0.000 | +0.000 | NO_CHANGE |
| Validation reject rate | 0.0 | 0.000 | +0.000 | NO_CHANGE |
| Sandbox reject rate | 0.0 | 0.000 | +0.000 | NO_CHANGE |
| Retry rate | 0.0 | 0.000 | +0.000 | NO_CHANGE |
| Breaker activations | 0 | 0.000 | +0.000 | NO_CHANGE |
| Net conatus delta | 0.0 | 0.300 | +0.300 | IMPROVED |
| Net predictive delta | 0.0 | 0.200 | +0.200 | IMPROVED |

## Intelligence Verdict

- Improved metrics: 2
- Regressed metrics: 2
- Safety regression: NO
- **INTELLIGENCE_DELTA_STATUS:** IMPROVED

**Interpretation:**
At least 2 key metrics improved with no critical safety regression. The system shows signs of stabilization or improvement at scale.
