# Phase ABC Formal Closure Report

- **Branch:** `main`
- **Closure SHA:** `b9232ab8d8ed3f5d6d37a62a80433f528bdd7e66`
- **Date:** 2026-05-20
- **Scope:** SAFE FORMAL CLOSURE — verification + evidence/docs only. No new code changes.

---

## 1. Executive Verdict

- **PHASE_ABC_FORMAL_CLOSURE:** **PASS**
- **CORE_STATUS:** **PASS_BY_INDIVIDUAL_GATES**
- **SCIENTIFIC_STATUS:** **DEFERRED_INFRA** — aggregate `ci_gate_contract.sh` exceeds low-RAM envelope

---

## 2. What Was Verified

### Phase A — EN GF Linearization (языковая целостность)
- `linearizeClaimAstEn` expanded from 12 to 25+ `ClaimAst` handlers (full coverage).
- `structuredBody` EN branches added for all previously RU-only proposition types.
- EN gate: `intent_fit_rate=1.0000`, `fallback_rate=0.0000`, `ru_leakage_rate=0.0000`.

### Phase B — Post-Commitment Bounded Adaptation
- Mutable `ssSalienceWeights` / `ssFieldHeuristics` added to `SystemState` with JSON round-trip.
- Bounded update rules (`adaptSalienceWeights`, `adaptFieldHeuristics`) wired in `buildNextSystemState`.
- Gated strictly on `EssenceCommitted`; signal=0.0 (empirical calibration deferred to Phase 7).
- Property tests: clamping [0,2]/[0,1], anti-drift ±1.0/±0.5, identity-at-zero-signal.

### Phase C — Deterministic Time Injection in Prepare
- `PrepareStatic` gains `psCurrentTime :: !UTCTime`.
- `buildPrepareEffectPlan` accepts `UTCTime` up-front; `prepareTurn` resolves time before plan construction.
- `buildTurnInput` uses `psCurrentTime` for `tiStartTime` instead of non-deterministic timeline.
- Deterministic unit test verifies injection.

---

## 3. Gate Table

| # | Command | Exit | Verdict | Key Metrics |
|---|---------|------|---------|-------------|
| 1 | `cabal build all` | 0 | **PASS** | Clean build, no errors |
| 2 | `cabal test qxfx0-test-fast` | 0 | **PASS** | 469/469 cases, 0 errors, 0 failures |
| 3 | `cabal test qxfx0-test` | 0 | **PASS** | 596/596 cases, 0 errors, 0 failures |
| 4 | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 5 | `bash scripts/gf_quality_gate.sh` | 0 | **PASS** | 0 errors, 0 warnings |
| 6 | `bash scripts/check_gf_render_path.sh` | 0 | **PASS** | 30 turns, fallback=0.0000, gf_atoms=1.0000 |
| 7 | `bash scripts/check_en_render_path.sh` | 0 | **PASS** | 30 turns, intent_fit=1.0000, fallback=0.0000 |
| 8 | `bash scripts/check_generated_artifacts.sh` | 0 | **PASS** | PGF present, skip GF compile (infra) |
| 9 | `bash scripts/check_lexicon.sh` | 0 | **PASS** | score=10.00, lemmas=3756, all quality OK |
| 10 | `QXFX0_CONTRACT_PROFILE=core bash scripts/ci_gate_contract.sh` | — | **INFRA-DEFERRED** | Timeout >300s on low-RAM runner |
| 11 | `bash scripts/release-smoke.sh` | — | **INFRA-DEFERRED** | Extended corpus replay exceeds envelope |

---

## 4. Deferred Checks

| Check | Reason | Mitigation |
|-------|--------|------------|
| `ci_gate_contract.sh` (aggregate) | Multi-suite orchestration >300s / >10 GB on local runner | All constituent individual gates pass; deferred to CI runner with >=32 GB RAM |
| `release-smoke.sh` | Extended corpus replay >120s on local runner | Fast/meta suites cover core paths; deferred to high-mem runner |
| Phase B empirical signal calibration | Requires production trace corpus and statistical analysis | Infrastructure in place; signal hardcoded to 0.0 (identity). No drift risk. |
| Phase C full deterministic replay | Requires `QXFX0_TEST_FIXED_TIME` env fixture across full test matrix | Single unit test covers contract; full matrix deferred to CI |

---

## 5. Residual Risks (Actual)

1. **Phase B adaptation is identity-only.** With `signal=0.0`, no empirical tuning occurs. This is by design for this closure, but means the system has not been validated against real-world drift patterns.
2. **GF compiler unavailable.** EN improvements are Haskell-native (`linearizeClaimAstEn`), not PGF runtime. If EN test fixture expands beyond current 6 families, new handlers must be added manually.
3. **EN `structuredBody` handles 7 proposition types directly; others route through fallback.** While fallback text is now EN-native (no RU leakage), the *structural* richness for advanced EN propositions (e.g., `ContemplativeTopic`, `NextStepQ`) is lower than for RU.
4. **Deterministic time abstraction does not yet cover downstream stages.** Render and Finalize still resolve time through `TurnReqCurrentTime`. This is acceptable because Prepare is the critical non-deterministic entry point for test reproducibility.
5. **Low-RAM build uses `-O1` / single job.** Performance characteristics on high-mem runner may differ; no performance regression testing performed in this closure.

---

## 6. Files Changed in This Closure

- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` — updated SHA, counts, gate table, deferred list
- `reports/releases/phase_abc_formal_closure.md` — this report
- `docs/adr/0017-post-commitment-adaptation.md` — ADR for Phase B mechanics
- `docs/adr/0018-deterministic-time-injection.md` — ADR for Phase C mechanics

---

## 7. Acceptance Criteria Checklist

- [x] All 9 mandatory low-RAM commands executed and reflected
- [x] Docs/evidence consistent with actual command outputs
- [x] No claims at FULL_SCIENTIFIC_GO level
- [x] Git status clean (only expected docs changes)
- [x] Atomic commits: docs(evidence) + docs(release)

---

*Report maintained by release/reliability engineer. Update when new canonical run replaces prior evidence.*
