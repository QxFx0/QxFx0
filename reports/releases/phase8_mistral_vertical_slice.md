# Release Report: Phase 8 — Mistral Learning Loop Vertical Slice

**Date:** 2026-05-20  
**HEAD:** `bc4849e`  
**Branch:** `main`  
**Status:** CLOSED (Phase 8 / External Learning Loop)  
**Scope:** Close the external learning loop via transport → validator → parser → sandbox → graft → telemetry (WP1–WP8).  Feature-flagged Mistral integration with deterministic mock fallback.

---

## Executive Summary

Phase 8 closes the external learning loop that Phase 7 left open.  The system can now:
1. Detect a learning need endogenously (WP1–WP3).
2. Call an external LLM (Mistral) or a deterministic mock transport.
3. Parse the response into a typed `KnowledgeFruitPayload`.
4. Validate the payload against word presence, definition length, morphology sanity, and lexicon conflict.
5. Sandbox the candidate against non-regression (latency, error count, Conatus energy).
6. Graft accepted fruit into the `KnowledgeTree`, update tool reliability, and merge morphology.
7. Telemetry every stage via six new `TurnReplayTrace` fields.

All changes are additive, pure-functional in the graft path, and fail-closed.  No existing threshold, gate, or commitment-law contract is weakened.

**Fast tests:** 537/537 PASS (+10 from Phase 7 baseline 527)  
**Full tests:** 664/664 PASS (+10 from Phase 7 baseline 654)  
**Architecture gate:** 12/12 invariants PASS  
**GF quality gate:** 0 errors, 0 warnings PASS  
**Agda typecheck:** 6/6 modules PASS

---

## What Was Delivered

### External LLM Transport (`Bridge.ExternalLLM`)

- `LLMTransport` with `MockTransport` (pure deterministic table) and `MistralTransport` (`http-client-tls`).
- `buildTransportFromEnv` reads `QXFX0_LLM_TRANSPORT`, `QXFX0_MISTRAL_API_KEY`, `QXFX0_MISTRAL_MODEL`, and `QXFX0_MISTRAL_ENDPOINT`.
- Missing API key → automatic mock fallback with telemetry `trcExternalTool=mock_fallback`.
- `queryExternalTool` executes the request and returns `ExternalQueryResponse`.

### Typed Error Taxonomy (`Types.ExternalQuery`)

- `ExternalQueryError` with six constructors: `EqeTransportError`, `EqeParseError`, `EqeValidationError`, `EqeSandboxReject`, `EqeRateLimited`, `EqeUnknownError`.
- Each constructor carries enough detail for precise telemetry and operator diagnosis.

### Parser (`Learning.Parser`)

- `parseLLMResponseToFruit` implements strict JSON-first decoding.
- Constrained text fallback when JSON fails.
- Both paths target the same `KnowledgeFruitPayload` schema: `word`, `definition`, optional `morphology`.

### Validator (`Learning.Validator`)

- `validateFruitPayload` enforces four rules:
  1. Word must be non-empty.
  2. Definition must contain ≥3 words.
  3. Morphology surface forms must be non-empty (if present).
  4. Word+definition pair must not duplicate an existing lexicon entry.
- `ValidationError` carries machine-readable tags for telemetry.

### Sandbox (`Learning.Sandbox`)

- `runSandboxGate` performs lightweight projection:
  - History slope over last N turns.
  - Delta injection into cloned `SystemState`.
  - Reject if latency rises >20 %, errors increase, or Conatus energy drops.
- `SandboxResult` = `SandboxAccept` or `SandboxReject SandboxRejectReason`.

### Integration Loop (`Learning.Loop`)

- `runLearningStep` — pure end-to-end function: transport → parse → validate → sandbox → graft/quarantine → telemetry.
- `applyExternalLearning` — called in `Finalize.Precommit` after `buildNextSystemState`.
  - On acceptance: updates `ssKnowledgeTree`, `ssToolReliability`, `ssMorphology`.
  - On rejection: records reason in `TurnReplayTrace`, leaves state untouched.

### Turn Effect Wiring

- `TurnReqExternalQuery` / `TurnResExternalQuery` added to `Effects.hs`.
- Runtime handler in `Wiring/Handlers.hs` resolves IO and injects the result into `TurnInput.tiExternalQueryResult`.
- `Prepare/Build.hs` initialises `tiExternalQueryResult = Nothing` for every turn.

### Telemetry (`Types.TurnProjection`)

Six new trace fields in `TurnReplayTrace`:
- `trcLearningQueryType` — what was asked.
- `trcExternalTool` — which tool / mock fallback was used.
- `trcLearningValidationStatus` — parse/validation outcome.
- `trcLearningSandboxResult` — accept or reject.
- `trcLearningGraftTurn` — turn number when fruit was grafted (if accepted).
- `trcLearningRejectReason` — machine-readable reject tag (if rejected).

### Test Coverage

- `test/Test/Suite/LearningLoop.hs` — 10 new Phase 8 tests:
  - Mock transport success / failure (2)
  - Validator rejects junk (1)
  - Parser valid schema / rejects malformed (2)
  - Sandbox rejects degrading / accepts improving (2)
  - Graft updates tree and morphology (1)
  - Telemetry fields populated (1)
  - Fail-closed on external error (1)

---

## Gate Summary

| Gate | Result | Evidence |
|------|--------|----------|
| `cabal build all` | PASS | 249 modules, 0 errors |
| Fast suite (`qxfx0-test-fast`) | PASS | 537/537 cases, 0 errors, 0 failures |
| Full suite (`qxfx0-test`) | PASS | 664/664 cases, 0 errors, 0 failures |
| Architecture gate | PASS | 12/12 invariants |
| GF quality gate | PASS | 0 errors, 0 warnings |
| Agda typecheck | PASS | 6/6 modules |
| `check_gf_render_path.sh` | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_en_render_path.sh` | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_generated_artifacts.sh` | INFRA-DEFERRED | timeout on low-RAM runner |
| `check_lexicon.sh` | INFRA-DEFERRED | timeout on low-RAM runner |
| `nix flake check` | INFRA | upstream `pgf2` marked broken |

---

## Risks and Mitigations

| Risk | Mitigation | Status |
|------|------------|--------|
| Live LLM responses are non-deterministic | JSON schema validation + sandbox gate + deterministic mock fallback for CI | ACCEPTED |
| Latency increase from external call | Feature-flagged; mock mode has near-zero overhead; Mistral mode only when explicitly enabled | ACCEPTED |
| Lexicon conflict false positives | Validator checks exact word+definition duplicate only; morphology merge is additive | ACCEPTED |
| Partial state mutation on crash | `applyExternalLearning` updates `SystemState` atomically in `Finalize.Precommit`; no partial writes survive | MITIGATED |

---

## Next Phase Candidates

- **Phase 9 — Adaptive Tool Discovery**: extend `selectTool` to discover new tool profiles from external tool registries rather than a static list.
- **Phase 10 — Calibrated Sandbox Replay**: replace lightweight projection with a full N-turn pipeline replay for the sandbox gate when running on high-mem infrastructure.
- **Extended contract run**: execute `ci_gate_contract.sh` aggregate on a >=32 GB RAM runner to move INFRA-DEFERRED gates to PASS.

---

## Sign-off

- **Implementation:** OpenCode  
- **Test verification:** 664/664 PASS on low-RAM profile  
- **Architecture gate:** 12/12 PASS  
- **Commit range:** `ad37ea6` → `bc4849e`  
- **Status:** CLOSED
