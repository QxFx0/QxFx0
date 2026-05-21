# Wave 5 — Consolidated Staged Soak Report

**Objective:** Validate long-tail stability across increasing session depth and turn count.
**Model:** accounts/fireworks/models/kimi-k2p6 (primary) / kimi-k2p5 (fallback)

## Stage Summary

| Stage | Sessions | Turns/Session | Total Turns | Incidents | Critical | Graft Rate | Schema Pass | Avg Latency | P95 Latency | Prompt Tokens | Completion Tokens |
|-------|----------|---------------|-------------|-----------|----------|------------|-------------|-------------|-------------|---------------|-------------------|
| canary | 2 | 20 | 40 | 0 | 0 | 1.000 | 1.000 | 3330ms | 11370ms | 142,481 | 43,350 |
| stage1 | 5 | 40 | 200 | 0 | 0 | 1.000 | 1.000 | 3609ms | 10422ms | 1,392,180 | 418,402 |
| full | 20 | 80 | 1600 | 0 | 0 | 1.000 | 1.000 | 3458ms | 9771ms | 21,990,194 | 6,630,580 |

## Drift Analysis (Canary → Stage 1 → Full)

### Latency Drift

| Metric | Canary | Stage 1 | Full | Drift Canary→Full |
|--------|--------|---------|------|-------------------|
| avg | 3330.1ms | 3608.925ms | 3457.96125ms | +128ms |
| p50 | 2408ms | 2404ms | 2149ms | -259ms |
| p95 | 11370ms | 10422ms | 9771ms | -1599ms |

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
| canary | 2,000,000 | 600,000 | 142,481 | 43,350 | YES | 2 | 0 | YES |
| stage1 | 10,000,000 | 3,000,000 | 1,392,180 | 418,402 | YES | 3 | 0 | YES |
| full | 40,000,000 | 12,000,000 | 21,990,194 | 6,630,580 | YES | 5 | 0 | YES |

## Executive Verdict

- **ALL_STAGES_CLEAN:** YES
- **RECOMMENDATION:**
  All stages completed within budget and incident caps. No critical incidents detected. System is cleared for production deployment or further scale testing.
