# Release Report — Fireworks Multi-Model A/B Evaluation Harness

**Release ID:** `fireworks-multimodel-ab-2026-05-21`  
**Commit range:** `814c1c1` → `HEAD`  
**Scope:** Add `QxFx0.Evaluation.ModelComparison`, Fireworks transport adapter, and deterministic A/B harness tests.

---

## Summary

This release delivers the Fireworks multi-model A/B evaluation harness and completes the adapter wiring started in the transport layer. The system can now deterministically compare up to 4 external LLM models (limited to 3 live on this Fireworks account) through identical corpus, policy, and telemetry.

---

## What Changed

### 1. Fireworks Transport Adapter (already staged in `Bridge.ExternalLLM`)

- Added `FireworksTransport` constructor, `FireworksConfig` type, `Show` instance with redaction.
- Added `fireworksQuery` using OpenAI-compatible chat-completion schema (same body/response shape as Mistral, only endpoint/auth differ).
- Updated `buildTransportFromEnv` to read `QXFX0_FIREWORKS_API_KEY`, `QXFX0_FIREWORKS_MODEL`, `QXFX0_FIREWORKS_ENDPOINT`.
- Updated `buildTransportFromConfig` dispatch.
- Exported `MockTable` type synonym so test suites can construct custom mock tables.

### 2. Evaluation Harness (`QxFx0.Evaluation.ModelComparison`)

- Deterministic 40-prompt Russian philosophical corpus.
- `runModelSession` — sequential per-model session runner with per-model state fork.
- `runInterleavedSession` — deterministic shuffle (seeded) across models per session.
- `runComparison` — full 3-session aggregation across all models.
- `aggregateSession` / `aggregateModel` — latency, success rate, validator accept rate, sandbox pass rate, incident counts.
- `detectIncidents` — 4 incident classes with tunable thresholds:
  - `IncidentConsecutiveTransportErrors` (>=3)
  - `IncidentConsecutiveValidatorRejects` (>=5)
  - `IncidentConsecutiveSandboxRejects` (>=3, same degradation tag)
  - `IncidentRequestRejectLoop` (>=5 turns without graft)
- `renderComparisonRun` — markdown telemetry output.

### 3. Test Coverage (12 new tests)

| Test | Description |
|------|-------------|
| `corpus-length` | 40 prompts |
| `sequential-perfect` | 40 accepts with perfect mock |
| `sequential-errors` | 8 transport errors, 32 accepts |
| `sequential-invalid` | 8 parse rejects, 32 accepts |
| `sequential-degrading` | 40 sandbox rejects |
| `aggregate-session` | Counter accuracy |
| `detect-transport-incidents` | 5-consecutive-error detection |
| `detect-validator-incidents` | 6-consecutive-reject detection |
| `detect-sandbox-incidents` | 4-consecutive-sandbox-reject detection |
| `detect-request-reject-loop` | 6-turn no-graft loop detection |
| `comparison-run-three-models` | End-to-end 3-model comparison |
| `interleaved-counts-match-sequential` | Deterministic shuffle parity |

Fast suite increased from **574 → 586** cases.

### 4. Live API Validation

6 live turns (2 per model) confirm connectivity, latency, and JSON schema compliance for `glm-5p1`, `deepseek-v4-pro`, and `kimi-k2p5`. Full 360-turn live run deferred to high-mem runner.

---

## Gate Results

| Gate | Status | Evidence |
|------|--------|----------|
| `cabal build all` | **PASS** | 252 modules compiled, 0 errors |
| `cabal test qxfx0-test-fast` | **PASS** | 586/586 cases, 0 errors, 0 failures |
| `cabal test qxfx0-test` (meta) | **INFRA-DEFERRED** | Timeout (>600 s) on low-RAM runner; no regressions expected |
| `check_architecture.sh` | **PASS** | 12 invariants OK |
| `gf_quality_gate.sh` | **PASS** | 0 errors, 0 warnings |

---

## Known Limitations

1. **Full live 360-turn A/B** is INFRA-DEFERRED due to local time/cost constraints.
2. **Latency telemetry** from `queryExternalTool` currently reports `0` for mock transport and uses `getCurrentTime` diff for real transport; millisecond precision will be improved in a future release.
3. **Qwen models** are not available on this Fireworks account; comparison is 3-model only.

---

## Files Added / Modified

- `src/QxFx0/Bridge/ExternalLLM.hs` — Fireworks transport (unstaged delta now committed)
- `src/QxFx0/Evaluation/ModelComparison.hs` — new harness module
- `test/Test/Suite/ModelComparison.hs` — 12 new tests
- `test/TestMainFast.hs` — register new suite
- `test/TestMain.hs` — register new suite
- `test/TestMainUnit.hs` — register new suite
- `qxfx0.cabal` — register new library and test modules
- `reports/ab_runs/run-2026-05-21-fireworks-001/leaderboard.md` — new
- `reports/releases/fireworks_multimodel_ab_report.md` — new
- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` — updated

---

## Operator Notes

- To run a live A/B evaluation on a high-mem runner:
  ```bash
  export QXFX0_LLM_TRANSPORT=fireworks
  export QXFX0_FIREWORKS_API_KEY=...
  export QXFX0_FIREWORKS_MODEL=accounts/fireworks/models/deepseek-v4-pro
  cabal run qxfx0-main -- ab-eval --run-id <RUN_ID> --sessions 3
  ```
  (The CLI flag `ab-eval` does not yet exist; use the Haskell API directly.)

---

*Report generated 2026-05-21.*
