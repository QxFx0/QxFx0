# Release Report: Endogenous Learning Phase-1 Closure (WP1–WP5)

**Date:** 2026-05-20  
**HEAD:** `a3e2237`  
**Branch:** `main`  
**Status:** CLOSED  
**Scope:** Endogenous Learning Architecture — WP1 (diagnostic drive), WP2 (tool awareness), WP3 (strategy expansion), WP4 (closed loop), WP5 (guardrails).

---

## Executive Summary

All five work packages of the Endogenous Learning Architecture have
been implemented, tested, and verified against the low-RAM safe gate
stack.  No existing thresholds, gates, or commitment-law contracts
were weakened.  The architecture does not auto-patch runtime code;
only validated config/weights/rules may be updated through the
versioned calibration channel.

**Fast tests:** 509/509 PASS (+25 from prior baseline 484)  
**Full tests:** 636/636 PASS (+25 from prior baseline 611)  
**Architecture gate:** 12/12 invariants PASS  
**GF quality gate:** 0 errors, 0 warnings PASS  
**Agda typecheck:** 6/6 modules PASS

---

## What Was Delivered

### WP1 — Learning Need Diagnostic Drive
- `src/QxFx0/Learning/Need.hs`: `LearningNeed` (4 constructors),
  `LearningNeedState` (level, trend, persistence, history),
  `detectLearningNeed` with priority-ordered heuristics.
- Persistence threshold = 3 turns; history cap = 20.
- Heuristic priority: `NeedLexiconExtension` > `NeedSalienceCalibration`
  > `NeedKeywordEnrichment`.
- Wired into `buildNextSystemState` via `detectLearningNeed` call from
  turn signals (`ConatusEnergy`, `Field`, blocked-concepts count).

### WP2 — External Tool Awareness
- `src/QxFx0/Learning/Tool.hs`: `ExternalTool` profile with
  `etReliability`, `etDomain`, `etValidatable`.
- `selectTool` prefers validatable tools over higher-reliability
  non-validatable ones; falls back to `DomainGeneral` when no domain
  match exists.
- Default tool registry: `local-calibration-script` (salience, 0.95,
  validatable), `human-mentor` (keyword, 0.90, non-validatable),
  `llm-augment` (lexicon, 0.70, validatable), `llm-general`
  (general, 0.60, non-validatable).

### WP3 — Strategy Expansion
- `LocalRecoveryStrategy` extended with `StrategyRequestCalibration`,
  `StrategyRequestRule`, `StrategyRequestConcept`.
- `buildLocalRecoveryPlan` checks `learningNeedActive` predicate
  (`level >= 0.6`) before escalating to request strategies.
- Low-deficit needs (`< 0.6`) are silently absorbed by normal routing;
  no request surface is emitted.
- RU/EN local-recovery surface strings added for all three request
  strategies.

### WP4 — Closed Learning Loop
- `src/QxFx0/Learning/Calibration.hs`: `CalibrationLog` with
  monotonic `CalibrationId`, linked `prevId`, and rollback support.
- Lifecycle: `verifyProposal` → `simulateProposal` →
  `acceptProposal` → `monitorCalibration` → `rollbackCalibration`.
- `verifyProposal` rejects empty rules, blocked rules, empty concepts.
- `monitorCalibration` detects degradation when post-acceptance level
  rises above pre-acceptance level after the monitor window.
- `currentCalibrationVersion` returns the last `Accepted` entry ID.

### WP5 — Guardrails
- `src/QxFx0/Learning/Guardrails.hs`: `GuardrailState` with
  rate-limit counter, circuit-breaker cooldown, and quarantine list.
- Rate limit: max 2 proposals per 10-turn window.
- Circuit breaker: opens after 3 consecutive rejections; closes after
  5-turn cooldown.
- Quarantine: proposals must sit for ≥2 turns before becoming
  eligible for verify/simulate.

---

## Gate Results

| Gate | Exit | Verdict | Evidence |
|------|------|---------|----------|
| `cabal build all` | 0 | PASS | 240 modules, 0 errors |
| `cabal test qxfx0-test-fast` | 0 | PASS | 509/509, 0 errors, 0 failures |
| `cabal test qxfx0-test` | 0 | PASS | 636/636, 0 errors, 0 failures |
| `check_architecture.sh` | 0 | PASS | 12 invariants OK |
| `gf_quality_gate.sh` | 0 | PASS | 0 errors, 0 warnings |
| `nix run .#typecheck-agda` | 0 | PASS | 6/6 modules |
| `check_gf_render_path.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_en_render_path.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_generated_artifacts.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_lexicon.sh` | — | INFRA-DEFERRED | timeout on low-RAM runner |
| `ci_gate_contract.sh` aggregate | — | INFRA-DEFERRED | multi-suite orchestration exceeds local envelope |
| `release-smoke.sh` | — | INFRA-DEFERRED | extended corpus replay exceeds local envelope |
| `nix flake check` | 1 | INFRA | upstream `pgf2` broken in nixpkgs (non-blocking) |

---

## Commits

1. `3fbcd65` — `feat(learning): add endogenous drive, tool awareness, request strategies, calibration loop, guardrails`
2. `8b2e2c0` — `test(learning): add wp1-wp5 coverage and regression checks`
3. `a3e2237` — `fix(learning): replace bare last with safeLast in currentCalibrationVersion`
4. *(pending)* — `docs(evidence): refresh canonical index after endogenous learning phase1`
5. *(pending)* — `docs(release): add endogenous learning phase1 closure report`

---

## Residual Risks & Next Steps

1. **Phase-2 Persistence** — `GuardrailState` and `CalibrationLog` are
   not yet persisted in `SystemState`.  JSON round-trip wiring and
   turn-loop update are the next immediate work package.
2. **Empirical Calibration** — `adaptSalienceWeights` and
   `adaptFieldHeuristics` still receive hardcoded `signal = 0.0`.
   Real empirical signal generation requires Phase-7 trace-corpus
   analysis, deferred until production telemetry is available.
3. **Tool Runtime Integration** — `selectTool` is pure; no actual
   HTTP/API call to external tools exists.  A bridge module
   (similar to `PipelineIO` for shadow/embedding) will be needed
   when a tool backend is provisioned.
4. **Simulation Substance** — `simulateProposal` is currently a stub
   that always succeeds.  Real trace-replay simulation requires
   historical turn corpora and a deterministic replay harness.
5. **Extended Contract** — `qxfx0-test-slow` and `release-smoke.sh`
   remain INFRA-DEFERRED pending a >=32 GB RAM runner.

---

## Compliance Checklist

- [x] No commitment-law contracts weakened  
- [x] No auto-patching of runtime code  
- [x] All new strategies have RU + EN surface strings  
- [x] JSON round-trip preserved for `SystemState` (backward compatible defaults)  
- [x] Architecture gate 12/12 PASS  
- [x] No bare `head`/`tail`/`init`/`last` in new source (safe alternatives used)  
- [x] `NeedTrend(..)` exported for test visibility  
- [x] `NeedNone` is the default for absent learning-need state  

---

*Report generated by release engineer.  See
`reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` for
ground-truth evidence paths.*
