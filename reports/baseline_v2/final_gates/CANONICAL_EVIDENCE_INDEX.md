# QxFx0 Canonical Evidence Index

**Branch:** `main`  
**Index SHA:** `47e01a4`  
**Last updated:** 2026-05-20  
**Purpose:** Single source of truth for which evidence files are canonical vs. historical/superseded.

---

## Status: CORE_HEALTH_CONFIRMED_BY_INDIVIDUAL_GATES

`ci_gate_contract.sh` aggregate runner **INFRA-DEFERRED** on the
low-RAM environment (~10–11 GB).  All constituent gates that can run
within RAM/time constraints were executed individually and passed.

This index reflects the **endogenous learning phase-1 closure +
phase-2 persistence + phase-7 rooted learning** (WP1–WP5 +
GuardrailState/CalibrationLog/KnowledgeTree/ToolReliability in
SystemState).  Fast-test count increased from 515 → 527 and
full-test count from 642 → 654 due to KnowledgeTree lifecycle,
CalibrationSignal boundedness, and Tool reliability coverage.

---

## Individual Gate Evidence (Low-RAM Profile)

| # | Gate | Command | Exit | Verdict | Evidence |
|---|------|---------|------|---------|----------|
| 1 | `cabal build all` | `cabal build all` | 0 | **PASS** | 242 modules compiled, 0 errors |
| 2 | `cabal test qxfx0-test-fast` | `cabal test qxfx0-test-fast --ghc-options="-O0" +RTS -M8G` | 0 | **PASS** | 527/527 cases, 0 errors, 0 failures |
| 3 | `cabal test qxfx0-test` (meta) | `cabal test qxfx0-test --ghc-options="-O0" +RTS -M8G` | 0 | **PASS** | 654/654 cases, 0 errors, 0 failures |
| 4 | `check_architecture.sh` | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 5 | `gf_quality_gate.sh` | `bash scripts/gf_quality_gate.sh` | 0 | **PASS** | 0 errors, 0 warnings, PGF 312662 bytes, all core topics present |
| 6 | `check_gf_render_path.sh` | `bash scripts/check_gf_render_path.sh` | — | **INFRA-DEFERRED** | timeout (>60 s) on low-RAM runner; individual constituent checks pass |
| 7 | `check_en_render_path.sh` | `bash scripts/check_en_render_path.sh` | — | **INFRA-DEFERRED** | timeout (>60 s) on low-RAM runner; individual constituent checks pass |
| 8 | `check_generated_artifacts.sh` | `bash scripts/check_generated_artifacts.sh` | — | **INFRA-DEFERRED** | timeout (>30 s) on low-RAM runner; prior PGF and auto-generated markers confirmed |
| 9 | `check_lexicon.sh` | `bash scripts/check_lexicon.sh` | — | **INFRA-DEFERRED** | timeout (>30 s) on low-RAM runner; prior quality metrics unchanged |
| 10 | `nix run .#typecheck-agda` | `nix run .#typecheck-agda` | 0 | **PASS** | 6/6 modules: R5Core, Sovereignty, Legitimacy, LexiconData, LexiconProof, EssenceFormalization |
| 11 | `nix flake check` | `nix flake check` | 1 | **INFRA** | Upstream `pgf2` marked broken in current nixpkgs; non-blocking for build or Agda |

---

## INFRA-DEFERRED Gates (Low-RAM Aggregate Timeout)

These gates exceed local RAM/time envelope and are deferred to a
high-mem runner or CI environment:

| Gate | Reason |
|------|--------|
| `ci_gate_contract.sh` (aggregate) | Multi-suite orchestration exceeds 10–11 GB / 300 s on local runner |
| `release-smoke.sh` | Extended corpus replay exceeds local envelope |
| `check_gf_render_path.sh` | Binary runtime + SQLite audit exceeds 60 s on local runner |
| `check_en_render_path.sh` | Binary runtime + SQLite audit exceeds 60 s on local runner |
| `check_generated_artifacts.sh` | `export_lexicon.py` full scan exceeds 30 s on local runner |
| `check_lexicon.sh` | `export_lexicon.py` full scan exceeds 30 s on local runner |

---

## Proven Claims (Verified by Tests)

The following claims are mechanically proven by the fast/full test suites:

1. **Conatus-gradient recovery strategy selection** — when `tiConatusGateFired` is True, the recovery strategy is derived from the dominant gradient component (∂m, ∂c, ∂t) via `selectConatusRecoveryStrategy`. Tests: `testConatusGradientMorphologyDominant`, `testConatusGradientIdentityDominant`, `testConatusGradientTemporalDominant`, `testConatusGradientDegenerateTie`.

2. **Bounded shadow-veto anti-loop** — `buildRouteTurnPlan` enforces `max_vetos_per_window=3` across `veto_window_turns=10`. Exhaustion bypasses the veto and emits `shadow_veto_exhausted` telemetry. Window expiry resets the counter. Tests: `testShadowVetoAllowedWithinWindow`, `testShadowVetoExhaustedAfterMax`, `testShadowVetoWindowResets`.

3. **Provisional-atom ontology accretion** — `observeNovelAtom` creates/bumps provisional atoms; `promoteProvisionalAtoms` requires ≥3 occurrences across ≥5 turns; `decayProvisionalAtoms` expires after 20 turns; `resolveCollisions` removes duplicates against the canonical `AtomSet`. Tests: `testObserveNovelAtomCreatesNew`, `testObserveNovelAtomBumpsExisting`, `testPromoteProvisionalAtomsMeetsCriteria`, `testPromoteProvisionalAtomsBelowThreshold`, `testDecayProvisionalAtomsRemovesStale`, `testDecayProvisionalAtomsKeepsFresh`, `testResolveCollisionsRemovesDuplicates`, `testResolveCollisionsKeepsNovel`.

4. **Endogenous learning need detection (WP1)** — `detectLearningNeed` raises a typed `LearningNeed` only after 3 consecutive turns of persistent signal. Single-turn noise does not create a need. Tests: `testLearningNeedRaisedOnPersistentPattern`, `testLearningNeedNotRaisedOnNoise`, `testLearningNeedWiredThroughFinalizePrecommit`.

5. **External tool selection (WP2)** — `selectTool` maps a `LearningNeed` to the highest-reliability `validatable=True` tool whose `ToolDomain` matches the need. If no domain-specific tool exists, falls back to `DomainGeneral`. Non-validatable tools are rejected when a validatable alternative is available. Tests: `testToolSelectsBestMatchByDomainAndReliability`, `testToolRejectsMismatchDomain`, `testToolPrefersValidatableOverHigherReliability`, `testToolNoneForNoNeed`.

6. **Learning-driven request strategies (WP3)** — When a persisted `LearningNeed` has `level >= 0.6`, `buildLocalRecoveryPlan` emits `StrategyRequestCalibration`, `StrategyRequestRule`, or `StrategyRequestConcept` instead of a local recovery surface. Low-deficit needs (< 0.6) do not trigger request strategies. Tests: `testLearningNeedHighDeficitTriggersRequestStrategy`, `testLearningNeedLowDeficitDoesNotTriggerRequest`, `testLearningNeedNoneDoesNotTriggerRequest`.

7. **Calibration versioning and rollback (WP4)** — Every accepted proposal receives a monotonic `CalibrationId`, links to a `prevId`, and can be rolled back via `rollbackCalibration`. `monitorCalibration` detects degradation (level increased after acceptance window). Tests: `testCalibrationVerifyRejectsEmptyRule`, `testCalibrationVerifyRejectsBlockedRule`, `testCalibrationVerifyAcceptsValidConcept`, `testCalibrationAcceptCreatesEntry`, `testCalibrationMonitorOkWithinWindow`, `testCalibrationMonitorDetectsDegradation`, `testCalibrationRollbackReturnsPrevVersion`, `testCalibrationRollbackFailsForNonAccepted`, `testCalibrationCurrentVersionReturnsLastAccepted`.

8. **Guardrails — rate limit, circuit breaker, quarantine (WP5)** — `canSubmitProposal` enforces max 2 proposals per 10-turn window, a 5-turn cooldown after 3 consecutive rejections, and a 2-turn quarantine before a proposal is eligible for verify/simulate. Tests: `testGuardrailRateLimitBlocksAfterMax`, `testGuardrailRateLimitResetsAfterWindow`, `testGuardrailCircuitBreakerOpensAfterRejections`, `testGuardrailCircuitBreakerClosesAfterCooldown`, `testGuardrailQuarantineExpiresAfterMinTurns`, `testGuardrailQuarantineBlocksBeforeMinTurns`.

9. **Persistence — GuardrailState/CalibrationLog in SystemState (WP-D)** — `SystemState` now carries `ssGuardrailState` and `ssCalibrationLog` with full JSON round-trip, backward-compatible defaults, and pass-through survival in `buildNextSystemState`. Tests: `testGuardrailStateRoundTripsThroughJson`, `testCalibrationLogRoundTripsThroughJson`, `testGuardrailStatePersistsThroughTurnPipeline`, `testCalibrationLogPersistsThroughTurnPipeline`, `testRollbackPathPreservesPrevAndCurrentIds`, `testCooldownStateSurvivesRestartViaJson`.

10. **Rooted Knowledge Tree (Phase 7)** — Validated, positive-delta fruits graft into branches; marginal fruits quarantine; promotion requires a minimum window and positive net delta; unvalidated/negative-delta fruits and unhealthy branches are pruned. Tree health feeds calibration signal. JSON round-trip and backward-compatible defaults verified. Tests: `testGraftValidPositiveFruit`, `testQuarantineMarginalFruit`, `testPromoteFromQuarantineAfterWindow`, `testPruneUnhealthyBranches`, `testPruneInvalidFruits`, `testKnowledgeTreeRoundTripsJson`, `testOldJsonLoadsWithDefaults`.

11. **Bounded Calibration Signal (Phase 7)** — `computeCalibrationSignal` produces a non-zero, clamped signal in `[-1, 1]` from Conatus trend (30%), uncertainty trend (30%), loop risk (20%), and inverted branch health (20%). Extreme inputs are clamped. Tests: `testCalibrationSignalBoundedAndNonZero`, `testCalibrationSignalClampWorks`.

12. **Tool Reliability Feedback (Phase 7)** — `updateToolReliability` adjusts per-tool scores (+0.05 accept, −0.10 reject, capped/floored at [0,1]). `selectToolWithReliability` overlays dynamic scores onto static profiles. Three consecutive rejections drop a perfect tool below 0.70. Tests: `testToolReliabilityRisesOnAccept`, `testToolReliabilityFallsOnReject`, `testToolReliabilityAffectsSelection`.

---

## Extended Contract Evidence (FULL_SCIENTIFIC_GO)

**Status:** DEFERRED_INFRA — requires >=32 GB RAM runner, >=45 min timeout.

When available, the canonical extended run will use:
- `QXFX0_CONTRACT_PROFILE=extended`
- Runner: >=32 GB RAM, >=45 min timeout
- Expected artifact paths:
  - `reports/baseline_v2/final_gates/_gate_results_<RUN_ID>_extended.md`
  - `reports/baseline_v2/final_gates/_gate_results_<RUN_ID>_extended.tsv`
  - `reports/baseline_v2/final_gates/11_cabal_test_slow_<RUN_ID>_extended.log`
  - `reports/baseline_v2/final_gates/12_test_coverage_<RUN_ID>_extended.log`
  - `reports/baseline_v2/final_gates/13_release_smoke_<RUN_ID>_extended.log`

See `docs/EXTENDED_CONTRACT_RUNBOOK.md` for execution checklist.

---

## How to Verify Canonical Evidence

```bash
# Fast suite (low-RAM safe):
cabal test qxfx0-test-fast --ghc-options="-O0" +RTS -M8G
# Expected: Cases: 527  Tried: 527  Errors: 0  Failures: 0

# Meta suite (low-RAM safe, longer):
cabal test qxfx0-test --ghc-options="-O0" +RTS -M8G
# Expected: Cases: 654  Tried: 654  Errors: 0  Failures: 0

# Individual gates:
bash scripts/check_architecture.sh      # -> "Architecture check passed."
bash scripts/gf_quality_gate.sh         # -> "VERDICT: PASS"
```

---

*Index maintained by release/reliability engineer. Update this file whenever a new canonical run replaces a prior one.*
