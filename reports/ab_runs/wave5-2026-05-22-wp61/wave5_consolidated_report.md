# Wave 5 — Consolidated Staged Soak Report

**Objective:** Validate long-tail stability across increasing session depth and turn count.
**Model:** accounts/fireworks/models/kimi-k2p6 (primary) / kimi-k2p5 (fallback)

## Stage Summary

| Stage | Sessions | Turns/Session | Total Turns | Incidents | Critical | Graft Rate | Schema Pass | Avg Latency | P95 Latency | Prompt Tokens | Completion Tokens |
|-------|----------|---------------|-------------|-----------|----------|------------|-------------|-------------|-------------|---------------|-------------------|
| canary | 2 | 20 | 40 | 0 | 0 | 1.000 | 1.000 | 2344ms | 6400ms | 142,481 | 43,636 |
| stage1 | 5 | 40 | 200 | 0 | 0 | 1.000 | 1.000 | 2117ms | 3757ms | 1,392,180 | 418,701 |
| full | 20 | 80 | 1520 | 0 | 0 | 1.000 | 1.000 | 2314ms | 5823ms | 20,891,221 | 6,289,029 |

## Drift Analysis (Canary → Stage 1 → Full)

### Latency Drift

| Metric | Canary | Stage 1 | Full | Drift Canary→Full |
|--------|--------|---------|------|-------------------|
| avg | 2344.075ms | 2116.73ms | 2313.936842105263ms | -30ms |
| p50 | 1813ms | 1823ms | 1760ms | -53ms |
| p95 | 6400ms | 3757ms | 5823ms | -577ms |

### Quality Drift

| Metric | Canary | Stage 1 | Full | Drift Canary→Full |
|--------|--------|---------|------|-------------------|
| graft | 1.000 | 1.000 | 1.000 | +0.000 |
| schema | 1.000 | 1.000 | 1.000 | +0.000 |
| val | 1.000 | 1.000 | 1.000 | +0.000 |
| sandbox | 1.000 | 1.000 | 1.000 | +0.000 |

## Fail-Closed Budget Summary

| Stage | Prompt Cap | Completion Cap | Prompt Burn | Completion Burn | Under Cap? | Incident Cap | Incidents | Under Cap? |
|-------|------------|------------------|-------------|-----------------|------------|--------------|-----------|------------|
| canary | 2,000,000 | 600,000 | 142,481 | 43,636 | YES | 2 | 0 | YES |
| stage1 | 10,000,000 | 3,000,000 | 1,392,180 | 418,701 | YES | 3 | 0 | YES |
| full | 40,000,000 | 12,000,000 | 20,891,221 | 6,289,029 | YES | 5 | 0 | YES |

## Executive Verdict

- **ALL_STAGES_CLEAN:** YES
- **RECOMMENDATION:**
  All stages completed within budget and incident caps. No critical incidents detected. System is cleared for production deployment or further scale testing.
