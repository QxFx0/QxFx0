# Phase 9 Autonomous Exploratory Learning MVP Report

**Date:** 2026-05-21  
**Scope:** System-initiated external learning when request-driven path is inactive  
**Commit:** `3f0f09f`  
**Parent:** `3041b12` (Phase 8 telemetry hotfix)

---

## Executive Verdict

| Gate | Verdict |
|------|---------|
| AUTONOMOUS_EXPLORATION_PATH | **PASS** |
| TELEMETRY_DIFFERENTIATION | **PASS** |
| GUARDRAIL_CUMULATIVE_RATE_LIMIT | **PASS** |
| REQUEST_PATH_NON_REGRESSION | **PASS** |
| CORE_HEALTH | **PASS** |

---

## What Changed

### New behaviour: the system can seek knowledge on its own

Before this commit, external learning only happened when:
1. A `LearningNeed` reached `level >= 0.6` (high deficit).
2. `buildLocalRecoveryPlan` emitted a **request strategy** (`StrategyRequestConcept`, `StrategyRequestRule`, or `StrategyRequestCalibration`).
3. The render phase executed a `TurnReqExternalQuery`.

Low-deficit needs (`0 < level < 0.6`) were ignored. The system would never explore unless explicitly asked.

After this commit, the render phase also checks:
- Is no request-driven query already planned? (request takes priority)
- Is a learning need active (`NeedNone` excluded)?
- Do guardrails permit (`canSubmitProposal`)?
- Is a suitable tool available with reliability `>= 0.3`?

If yes, an **exploratory** `TurnReqExternalQuery` is built, executed, and its result stored in `taExploratoryQueryResult`. The finalize phase processes both `taExternalQueryResult` (request-driven) and `taExploratoryQueryResult` (autonomous) through the same parse→validate→sandbox→graft chain.

### Telemetry now distinguishes who initiated the query

| Scenario | `trcLearningQueryType` | `trcLearningValidationStatus` |
|----------|------------------------|------------------------------|
| User asked → request strategy | `"request_concept"` | `"pending_validation"` / `"transport_error"` / etc. |
| System explored autonomously | `"exploratory"` | `"exploratory_pending_validation"` / etc. |
| Both on same turn | `"both"` | `"both_pending_validation"` / etc. |
| Neither | `Nothing` | `Nothing` |

### New proposition type (future-proofing)

`ExploratoryPrompt` was added to `PropositionType` with:
- Family: `CMDescribe`
- Confidence: `0.65` (base), `0.55` (floor)
- Keywords: `["изучи", "исследуй", "разберись", "пойми", "explore", "investigate", "research"]`
- Focus entity default: `"исследование"`

This type is **not** used by the autonomous path today (the path is triggered by `LearningNeedState`, not by proposition type). It exists for future API/UI scenarios where a user explicitly asks the system to explore a topic.

---

## Root Cause: Two Critical Fixes

### Fix 1 — `detectKeywordFallbackType` matcher restoration

**Problem:** While adding `ExploratoryPrompt` to `detectKeywordFallbackType`, the function was accidentally truncated from 31 matchers to 3. The remaining 28 (including `definitionalKeywords`, `distinctionKeywords`, `contactKeywords`, `affectiveKeywords`) were dropped.

**Impact:**
- Affective input `"Я чувствую страх и тоску"` lost its `CMContact` routing and fell through to `CMDeepen`.
- Negation corpus case `p0_ru_negation_not_tired` lost its `CMDistinguish` routing and fell through to `CMDeepen`.

**Fix:** Restored all original keyword fallback matchers. `exploratoryKeywords` and `contemplativeTopicKeywords` are now appended at the end of the list, preserving the original priority order.

### Fix 2 — `circuitBreakerOpen` cooldown expiry semantics

**Problem:** `circuitBreakerOpen gs turn = turn <= gsCooldownExpiry gs` treated `cooldownExpiry = 0` (meaning "no active cooldown") as an **open** circuit at turn 0. Since `emptyGuardrailState` starts with `gsCooldownExpiry = 0`, `canSubmitProposal` returned `False` for all fresh states, blocking exploratory queries from ever firing in tests and in practice.

**Impact:** The autonomous exploratory path was dead code — `mExploratoryQueryRequest` always evaluated to `Nothing` because `canSubmitProposal` was always `False` at turn 0.

**Fix:** Changed to `circuitBreakerOpen gs turn = gsCooldownExpiry gs > 0 && turn <= gsCooldownExpiry gs`. Now `cooldownExpiry = 0` correctly means "no cooldown active, circuit breaker is closed".

---

## Gate Verification

| # | Command | Exit | Verdict | Evidence |
|---|---------|------|---------|----------|
| 1 | `cabal build all` | 0 | **PASS** | 0 compilation errors |
| 2 | `cabal test qxfx0-test-fast` | 0 | **PASS** | 564/564 cases, 0 errors, 0 failures |
| 3 | `cabal test qxfx0-test` | 0 | **PASS** | 691/691 cases, 0 errors, 0 failures |
| 4 | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 5 | `nix run .#typecheck-agda` | 0 | **PASS** | 6/6 modules typecheck |

---

## Files Changed

| File | Lines | Nature |
|------|-------|--------|
| `src/QxFx0/Semantic/Proposition.hs` | +16 | `ExploratoryPrompt` type, detection, confidence, focus |
| `src/QxFx0/Policy/ParserKeywords.hs` | +11 | `exploratoryKeywords` list |
| `src/QxFx0/Types/Recovery.hs` | +4 | `StrategyExternalDialogue` recovery strategy |
| `src/QxFx0/Core/TurnPipeline/Route/Render.hs` | +66 | Exploratory query request building, `buildExploratoryQueryText`, dual execution in `resolveRenderEffects` |
| `src/QxFx0/Core/TurnPipeline/Types.hs` | +4 | `taExploratoryQueryResult` field |
| `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs` | +4/-2 | Dual `applyExternalLearning` calls |
| `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` | +26/-4 | Telemetry query type differentiation |
| `src/QxFx0/Bridge/ExternalLLM.hs` | +5 | Mock table entry for `"Explore"` prefix |
| `src/QxFx0/Learning/Guardrails.hs` | +1/-1 | `circuitBreakerOpen` fix |
| `test/Test/Suite/TurnPipelineProtocol.hs` | +144 | 8 new exploratory learning tests |

---

## Regression Status

| Regression | Status |
|------------|--------|
| Fast suite (baseline 556) | **PASS** — now 564/564 |
| Full suite (baseline 683) | **PASS** — now 691/691 |
| Architecture gate | **PASS** — 12/12 invariants |
| `p0_ru_negation_not_tired` routing | **PASS** — restored by Fix 1 |
| `affective input should map to CMContact` | **PASS** — restored by Fix 1 |
| Request-driven external query path | **PASS** — verified by `testRequestDrivenPathNotRegressedByExploration` |
| Commitment law / refused_commitment | **PASS** — no changes to Essence or commitment logic |

---

## Deferred Work

- **Exploratory-to-request escalation**: if an exploratory query produces a high-confidence fruit that resolves the learning need, the system does not yet auto-elevate the need level or suppress the next request strategy. Future work.
- **Tool reliability decay for exploratory queries**: exploratory success/failure currently updates `ssToolReliability` the same way as request-driven. A separate reliability track for autonomous vs assisted queries may be desirable.
- **Exploratory prompt UI integration**: the `ExploratoryPrompt` proposition type is wired but not yet exposed through any API or surface.

---

## How to Reproduce

```bash
# Build
cabal build all

# Fast suite
cabal test qxfx0-test-fast --ghc-options="-O0" +RTS -M8G
# Expected: Cases: 564  Tried: 564  Errors: 0  Failures: 0

# Full suite
cabal test qxfx0-test --ghc-options="-O0" +RTS -M8G
# Expected: Cases: 691  Tried: 691  Errors: 0  Failures: 0

# Architecture gate
bash scripts/check_architecture.sh
# Expected: Architecture check passed.
```

---

*Report generated by release pipeline. Commit `3f0f09f` on branch `main`.*
