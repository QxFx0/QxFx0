# ADR-0030: Phase 9 MVP — Autonomous Exploratory Learning

- **Status**: Accepted
- **Date**: 2026-05-21
- **Refines**:
  - [ADR-0028 — Phase 8 Hardening and Real Transport](./0028-phase8-hardening-and-real-transport.md)
  - [ADR-0027 — Phase 8 External Learning Loop](./0027-phase8-external-learning-loop.md)
- **Related**:
  - `QxFx0.Core.TurnPipeline.Route.Render`
  - `QxFx0.Learning.Guardrails`
  - `QxFx0.Semantic.Proposition`
  - `QxFx0.Types.Recovery`

## 1. Context

Phase 8 wired the **request-driven** external learning path: when a `LearningNeed` exceeds the `0.6` threshold and a request strategy fires, the render phase executes an external query, and the finalize phase runs it through parse→validate→sandbox→graft.

However, low-deficit learning needs (`level < 0.6` but `> 0`) were ignored. The system would only ever seek knowledge when explicitly asked for it (request strategy). There was no mechanism for the system to autonomously explore gaps in its own knowledge.

Phase 9 MVP introduces the **exploratory learning path**: the system can initiate an external query on its own behalf when a learning need is active but below the request threshold, provided guardrails permit and a suitable tool is available.

## 2. Decision

### 2.1 Exploratory trigger conditions

Autonomous exploration fires in `planRenderEffects` when **all** of the following hold:

1. **No request-driven query already planned** — request-driven takes priority.
2. **Learning need is active** — `lnsCurrentNeed /= NeedNone`.
3. **Guardrails permit** — `canSubmitProposal guard currentTurn` passes rate limit and circuit breaker.
4. **Tool available and reliable enough** — a tool is selected with `etReliability >= 0.3`.

If any condition fails, the exploratory path is silently skipped (no telemetry emission).

### 2.2 `ExploratoryPrompt` proposition type

A new `PropositionType` constructor was added:

```haskell
data PropositionType = ... | ExploratoryPrompt
```

- Mapped to `CMDescribe` family (`propositionToFamily ExploratoryPrompt = CMDescribe`).
- Base confidence: `0.65`.
- Detected by keyword matching: `["изучи", "исследуй", "разберись", "пойми", "explore", "investigate", "research"]`.
- Base confidence floor: `0.55`.
- Focus entity defaults to `"исследование"`.

This type is **not** used by the autonomous path directly (the path is triggered by learning need state, not by proposition type). It exists for:
- Future UI/API scenarios where a user explicitly asks the system to explore something.
- Symmetry with the other proposition types in the routing taxonomy.

### 2.3 Query text prefixing

`buildExploratoryQueryText` prefixes the query with `Explore ...` to distinguish it from request-driven queries in:
- Mock table lookup (`mockTableLookup` matches on first word).
- Telemetry (`trcLearningQueryType` reports `"exploratory"` vs `"request_concept"`).

```haskell
buildExploratoryQueryText need topic =
  case need of
    NeedLexiconExtension    -> "Explore definition of " <> topic
    NeedKeywordEnrichment   -> "Explore keywords for " <> topic
    NeedSalienceCalibration -> "Explore salience calibration for " <> topic
```

### 2.4 Dual-path finalize processing

`Finalize/Precommit.hs` now calls `applyExternalLearning` **twice** (sequentially):

1. Request-driven result (from `taExternalQueryResult`).
2. Exploratory result (from `taExploratoryQueryResult`).

State updates after each call. The order matters: request-driven grafts first, then exploratory grafts. Both use the same fail-closed semantics.

### 2.5 Telemetry differentiation

`buildTurnProjection` in `Finalize/State.hs` now emits three query-type tags:

| Condition | `trcLearningQueryType` |
|-----------|------------------------|
| Only request-driven executed | `Just "request_concept"` |
| Only exploratory executed | `Just "exploratory"` |
| Both executed | `Just "both"` |
| Neither executed | `Nothing` |

Validation status is similarly scoped per path.

## 3. Consequences

- **Self-directed learning**: the system no longer waits for user-requested high-deficit signals before seeking external knowledge.
- **Conservative rate limiting**: the same `GuardrailState` counters (`maxProposalsPerWindow = 2`, `proposalWindowTurns = 10`, `maxConsecutiveRejections = 3`, `cooldownTurns = 5`) apply to both request-driven and exploratory queries cumulatively. This prevents runaway external API usage.
- **Telemetry completeness**: the replay trace now distinguishes who initiated the query (user vs system), enabling future audit of autonomous learning efficacy.
- **No weight mutation**: this MVP is observational only. No salience weights, Conatus parameters, or field heuristics are mutated by exploratory results. Grafted knowledge fruits are stored in `ssKnowledgeTree` for future calibration signal computation.

## 4. Acceptance Criteria

- [x] `ExploratoryPrompt` proposition type added to `PropositionType` with family mapping, confidence, and keyword detection.
- [x] `planRenderEffects` builds an exploratory query request when no request-driven query is planned, learning need is active, guardrails permit, and tool reliability >= 0.3.
- [x] `resolveRenderEffects` executes the exploratory `TurnReqExternalQuery` and stores the result in `taExploratoryQueryResult`.
- [x] `applyExternalLearning` in finalize processes both request-driven and exploratory results.
- [x] Telemetry fields distinguish `"request_concept"`, `"exploratory"`, and `"both"`.
- [x] Fail-closed: transport/parse/validation/sandbox rejections skip graft and record telemetry.
- [x] Fast suite: 564/564 PASS; full suite: 691/691 PASS.

## 5. Critical Fixes During Implementation

Two regressions were discovered and fixed during MVP development:

### 5.1 `detectKeywordFallbackType` matcher restoration

During the addition of `ExploratoryPrompt`, the `detectKeywordFallbackType` function was accidentally truncated to only 3 fallback matchers (generative, contemplative, exploratory), dropping 28 others (definitional, distinction, ground, reflective, self-desc, purpose, hypothetical, repair, contact, anchor, clarify, deepen, confront, next-step, affective, epistemic, request, evaluation, narrative).

**Impact**: affective inputs (e.g. `"Я чувствую страх и тоску"`) and distinction inputs (e.g. negation corpus case `p0_ru_negation_not_tired`) fell through to unintended families (`CMDeepen`).

**Fix**: restored all original matchers; `exploratoryKeywords` and `contemplativeTopicKeywords` appended at the end.

### 5.2 `circuitBreakerOpen` cooldown expiry semantics

`circuitBreakerOpen gs turn = turn <= gsCooldownExpiry gs` incorrectly treated `cooldownExpiry = 0` (meaning "no active cooldown") as an open circuit at turn 0. This blocked `canSubmitProposal` for all freshly initialised `GuardrailState` instances, preventing exploratory queries from ever firing in tests.

**Fix**: `circuitBreakerOpen gs turn = gsCooldownExpiry gs > 0 && turn <= gsCooldownExpiry gs`. Now `cooldownExpiry = 0` means "no cooldown active".
