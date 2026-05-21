# Wave 5 — Long-Run Closure Report

**Date:** 2026-05-21  
**Index SHA:** `cf3de87`  
**Branch:** `main`  
**Driver:** `scripts/wave5_soak.py`  
**Primary Model:** `accounts/fireworks/models/kimi-k2p6`  
**Fallback Model:** `accounts/fireworks/models/kimi-k2p5` (not used)  

---

## 1. Executive Verdict

| Metric | Value |
|--------|-------|
| **WAVE5_STATUS** | **CLEAN** |
| **PRIMARY_MODEL_STATUS** | **STABLE** |
| **PRODUCTION_READINESS** | **CONDITIONAL_READY** |
| **ALL_STAGES_CLEAN** | **YES** |
| **TOTAL_TURNS** | 1840 |
| **TOTAL_INCIDENTS** | 0 |
| **SCHEMA_VALIDITY** | 1.000 |
| **GRAFT_ACCEPT_RATE** | 1.000 |

---

## 2. Stage Table

| Stage | Sessions | Turns/Session | Total Turns | Incidents | Graft Rate | Schema Pass | Avg Latency | P95 Latency | Prompt Tokens | Completion Tokens |
|-------|----------|---------------|-------------|-----------|------------|-------------|-------------|-------------|---------------|-------------------|
| Canary | 2 | 20 | 40 | 0 | 1.000 | 1.000 | 3330ms | 11370ms | 142,481 | 43,350 |
| Stage 1 | 5 | 40 | 200 | 0 | 1.000 | 1.000 | 3609ms | 10422ms | 1,392,180 | 418,402 |
| Full | 20 | 80 | 1600 | 0 | 1.000 | 1.000 | 3458ms | 9771ms | 21,990,194 | 6,630,580 |

---

## 3. Drift Analysis (Canary → Full)

### Latency Drift

| Metric | Canary | Stage 1 | Full | Drift Canary→Full | Interpretation |
|--------|--------|---------|------|-------------------|----------------|
| avg | 3330ms | 3609ms | 3458ms | **+128ms** | Minor non-safety regression |
| p50 | 2408ms | 2404ms | 2149ms | **−259ms** | Median improved at depth |
| p95 | 11370ms | 10422ms | 9771ms | **−1599ms** | Tail latency significantly improved |

**Interpretation:** P95 decreased by ~1.6s despite session depth increasing from 20 to 80 turns. This suggests stable provider-side latency distribution; the initial canary warm-up cost inflated early P95. Avg increased slightly (+128ms) but remains within acceptable bounds.

### Quality Drift

| Metric | Canary | Stage 1 | Full | Drift Canary→Full |
|--------|--------|---------|------|-------------------|
| graft | 1.000 | 1.000 | 1.000 | **+0.000** |
| schema | 1.000 | 1.000 | 1.000 | **+0.000** |
| val | 1.000 | 1.000 | 1.000 | **+0.000** |
| sandbox | 1.000 | 1.000 | 1.000 | **+0.000** |

**Interpretation:** Zero quality drift across all stages. 100% schema compliance, validation pass, sandbox pass, and graft accept rate maintained from 40-turn canary through 1600-turn full soak.

---

## 4. Budget & Fail-Closed Stop Policy

### Caps

| Stage | Prompt Token Cap | Completion Token Cap | Incident Cap |
|-------|------------------|----------------------|--------------|
| Canary | 2,000,000 | 600,000 | 2 |
| Stage 1 | 10,000,000 | 3,000,000 | 3 |
| Full | 40,000,000 | 12,000,000 | 5 |

### Actual Burn

| Stage | Prompt Burn | Completion Burn | Under Cap? | Incidents | Under Cap? |
|-------|-------------|-----------------|------------|-----------|------------|
| Canary | 142,481 | 43,350 | **YES** (7%) | 0 | **YES** |
| Stage 1 | 1,392,180 | 418,402 | **YES** (14%) | 0 | **YES** |
| Full | 21,990,194 | 6,630,580 | **YES** (55%) | 0 | **YES** |

### Stop-Policy Triggers

| Trigger | Canary | Stage 1 | Full | Total |
|---------|--------|---------|------|-------|
| `transport_streak` (≥3) | 0 | 0 | 0 | 0 |
| `validator_streak` (≥5) | 0 | 0 | 0 | 0 |
| `sandbox_streak` (≥3) | 0 | 0 | 0 | 0 |
| `breaker_lock` (>20) | 0 | 0 | 0 | 0 |
| `reject_loop` (>15) | 0 | 0 | 0 | 0 |
| `budget_prompt` exhausted | 0 | 0 | 0 | 0 |
| `budget_completion` exhausted | 0 | 0 | 0 | 0 |
| `incident_cap` reached | 0 | 0 | 0 | 0 |

**All fail-closed stop policies remained untriggered.**

---

## 5. Residual Risks

1. **Single-provider dependency** — All 1840 turns executed against Fireworks-hosted `kimi-k2p6`. Provider outage or model deprecation would break the learning loop. Fallback `kimi-k2p5` exists but was not stress-tested at this scale.

2. **No high-mem aggregate scientific run in this wave** — `ci_gate_contract.sh` aggregate, `release-smoke.sh` strict mode, and extended coverage gates remain INFRA-DEFERRED on the low-RAM runner. `FULL_SCIENTIFIC_GO` is not claimed.

3. **Raw JSONL out-of-git** — Per-session `.jsonl` data files are not committed to git (size policy). Reproducibility depends on the `run_id` (`wave5-2026-05-21`) and local artifact retention.

4. **Schema compliance may drift with model updates** — 100% JSON compliance was measured against the current `kimi-k2p6` snapshot. Provider-side weight updates could change structured-output behavior without notice.

5. **Token cost scaling** — 22M prompt + 6.6M completion tokens per 1600-turn batch. At production scale (e.g. 10K turns/day), token cost alerts and rate-limit handling must be active.

---

## 6. Next Step Recommendation

1. **Production rollout mode** — System is cleared for gradual production deployment using `kimi-k2p6` as primary model. Start with `canary` → `stage1` → `full` staged ramp identical to Wave 5.

2. **Monitoring SLOs** — Establish:
   - Schema pass rate ≥ 0.98 (alert if < 0.95)
   - Transport error rate < 0.02 (alert if ≥ 0.05)
   - Avg latency P95 < 15000ms (alert if ≥ 20000ms)
   - Incident rate < 1 per 100 turns (alert if ≥ 3 per 100)

3. **Rollback trigger thresholds** — Automatic rollback to previous validated config if:
   - 3+ consecutive transport errors in any session
   - 5+ consecutive validator rejects in any session
   - Incident cap exceeded for the stage
   - Budget cap exceeded (prompt or completion)

4. **Future work** — Execute `FULL_SCIENTIFIC_GO` on a ≥32 GB runner to close the extended contract gap. Validate `kimi-k2p5` fallback at 1600-turn scale. Add cost-per-turn telemetry for production budgeting.

---

## 7. Evidence Links

| Artifact | Path |
|----------|------|
| Consolidated report | `reports/ab_runs/wave5-2026-05-21/wave5_consolidated_report.md` |
| Canary report | `reports/ab_runs/wave5-2026-05-21/canary/report.md` |
| Stage 1 report | `reports/ab_runs/wave5-2026-05-21/stage1/report.md` |
| Full report | `reports/ab_runs/wave5-2026-05-21/full/report.md` |
| Soak driver | `scripts/wave5_soak.py` |
| Canonical index | `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` |

---

*Report generated as part of Wave 5 evidence finalization. No runtime code changes.*
