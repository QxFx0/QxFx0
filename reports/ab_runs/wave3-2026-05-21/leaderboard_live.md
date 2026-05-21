# Wave 3 — Live Leaderboard (Structured Output)

| Model | Total | Schema Pass | Val Pass | Sandbox Pass | Graft Rate | Transport Err | Parse Reject | Val Reject | Sandbox Reject | Retry Rate | Avg Latency | P50 | P95 | Net Conatus | Net Predictive | TTFG | Breaker Acts | Tokens In | Tokens Out |
|-------|-------|-------------|----------|--------------|------------|---------------|--------------|------------|----------------|------------|-------------|-----|-----|-------------|----------------|------|--------------|-----------|------------|
| deepseek-v4-pro | 107 | 0.50 | 0.50 | 1.00 | 0.50 | 0.00 | 0.50 | 0.00 | 0.00 | 0.00 | 14958 | 13807 | 30518 | 0.000 | 0.000 | 1 | 87 | 878020 | 1274632 |
| glm-5p1 | 15 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 1.00 | 0.00 | 0.00 | 0.00 | 19718 | 19277 | 29512 | 0.000 | 0.000 | N/A | 15 | 20442 | 36000 |
| kimi-k2p5 | 120 | 1.00 | 1.00 | 1.00 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 4260 | 2554 | 11977 | 0.000 | 0.000 | 1 | 0 | 654020 | 250794 |
| kimi-k2p6 | 120 | 1.00 | 1.00 | 1.00 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 2260 | 1662 | 6193 | 0.000 | 0.000 | 1 | 0 | 654020 | 246681 |

## Composite Ranking

1. **kimi-k2p5** — composite=0.900 (utility=1.00, reliability=1.00, stability=1.00, impact=0.50)
2. **kimi-k2p6** — composite=0.900 (utility=1.00, reliability=1.00, stability=1.00, impact=0.50)
3. **deepseek-v4-pro** — composite=0.435 (utility=0.50, reliability=0.50, stability=0.19, impact=0.50)
4. **glm-5p1** — composite=0.100 (utility=0.00, reliability=0.00, stability=0.00, impact=0.50)
