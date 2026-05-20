# ADR-0027: Phase 8 External Learning Loop

- **Status**: Accepted
- **Date**: 2026-05-20
- **Refines**:
  - [ADR-0025 — Rooted Knowledge Tree](./0025-rooted-knowledge-tree.md)
  - [ADR-0026 — Phase 7 Calibration Signal](./0026-phase7-calibration-signal.md)
- **Related**:
  - `QxFx0.Bridge.ExternalLLM`
  - `QxFx0.Learning.Parser`
  - `QxFx0.Learning.Validator`
  - `QxFx0.Learning.Sandbox`
  - `QxFx0.Learning.Loop`
  - `QxFx0.Core.TurnPipeline.Finalize.Precommit`

## 1. Context

After Phase 7, the system could detect learning needs (WP1), select tools (WP2), emit request strategies (WP3), version calibrations (WP4), guardrail proposals (WP5), and persist structural state (WP-D).  However, the loop was still *endogenous* — it could reason about what it needed, but could not actually *call* an external generative tool and safely integrate the response.

Phase 8 closes the external learning loop by connecting the system to an LLM transport (Mistral), parsing the response into typed fruit, validating it, sandboxing it against non-regression, and grafting accepted fruit into the `KnowledgeTree`.  The design priorities were:

1. **Fail-closed**: any dubious external response is rejected, never grafted.
2. **Deterministic mock fallback**: when no API key is present, the transport falls back to a deterministic lookup table so tests and CI remain reproducible.
3. **No weakening of gates**: thresholds, commitment law, and the refused-commitment boundary are untouched.
4. **Pure-functional state mutation**: the IO effect (`TurnReqExternalQuery`) is resolved in runtime handlers, but the resulting state graft is applied deterministically in `Finalize.Precommit`.

## 2. Decision

### 2.1 Typed error taxonomy (`ExternalQueryError`)

Six typed constructors capture every failure mode so the loop can telemetry precisely:

| Constructor | Cause | Telemetry |
|-------------|-------|-----------|
| `EqeTransportError Text` | HTTP/TLS failure | `trcExternalTool` + `trcLearningRejectReason` |
| `EqeParseError Text` | JSON/text parse failure | `trcLearningValidationStatus` = `InvalidSchema` |
| `EqeValidationError [ValidationError]` | Schema/semantic mismatch | `trcLearningValidationStatus` = `InvalidPayload` |
| `EqeSandboxReject SandboxRejectReason` | Non-regression gate failure | `trcLearningSandboxResult` = `Reject` |
| `EqeRateLimited` | External API 429 | `trcExternalTool` = `rate_limited` |
| `EqeUnknownError Text` | Catch-all | `trcLearningRejectReason` |

### 2.2 Transport layer (`LLMTransport`)

Two constructors:

- `MockTransport (Text -> ExternalQueryResponse)` — deterministic, pure, used in tests and when `QXFX0_LLM_TRANSPORT=mock`.
- `MistralTransport Manager Text Text` — `http-client-tls` `Manager`, API key, and endpoint.

Env-based builder (`buildTransportFromEnv`):

| Variable | Default | Behaviour |
|----------|---------|-----------|
| `QXFX0_LLM_TRANSPORT` | `mock` | `mock` → `MockTransport`; `mistral` → `MistralTransport` |
| `QXFX0_MISTRAL_API_KEY` | — | Required when mode=`mistral`; missing → fallback to mock |
| `QXFX0_MISTRAL_MODEL` | `mistral-small-latest` | Model slug for Mistral API |
| `QXFX0_MISTRAL_ENDPOINT` | `https://api.mistral.ai/v1/chat/completions` | API base URL |

Missing key is **never** a hard failure; the system logs `trcExternalTool=mock_fallback` and continues.

### 2.3 Validator (`validateFruitPayload`)

`KnowledgeFruitPayload` carries a `word`, `definition`, and optional `morphology` map.

Validation rules (all must pass):
1. **Word presence** — non-empty `word` text.
2. **Definition length** — at least 3 words.
3. **Morphology sanity** — if provided, every surface form is non-empty.
4. **Lexicon conflict** — `word` must not already exist in the static lexicon with an identical definition.

Failures produce `ValidationError` with a machine-readable tag (`InvalidSchema`, `MissingWord`, `DefinitionTooShort`, `MalformedMorphology`, `LexiconConflict`).

### 2.4 Parser (`parseLLMResponseToFruit`)

Two-stage parsing with strict fallback ordering:
1. **JSON first** — attempt to decode a constrained JSON schema: `{"word": "...", "definition": "...", "morphology": {"case": "..."}}`.
2. **Text fallback** — if JSON fails, apply a constrained regex/text heuristic to extract the same three fields.

If both stages fail, the result is `EqeParseError` with the raw response snippet for telemetry.

### 2.5 Sandbox (`runSandboxGate`)

Lightweight non-regression projection rather than a full N-turn replay (which would be too expensive on a low-RAM runner):

- **History slope** — compares the last N turn latencies / error counts before and after a simulated injection of the candidate fruit.
- **Delta injection** — the candidate is merged into a cloned `SystemState` and a lightweight projection runs one synthetic turn.
- **Thresholds** — latency may not increase by >20 %; error count may not increase; `Conatus` energy may not drop.

Result: `SandboxAccept` or `SandboxReject SandboxRejectReason`.

### 2.6 Integration loop (`runLearningStep` / `applyExternalLearning`)

`runLearningStep` is the pure end-to-end function:

```
transport query
  → parse response
  → validate payload
  → sandbox gate
  → (graft OR quarantine)
  → telemetry
```

`applyExternalLearning` is called in `Finalize.Precommit` after `buildNextSystemState`.  It:
1. Reads `tiExternalQueryResult` from the current `TurnInput`.
2. On `Right payload` + `SandboxAccept`, grafts into `ssKnowledgeTree`, bumps `ssToolReliability`, and merges `MorphologyPayload`.
3. On any rejection, records the reject reason in trace telemetry and leaves system state unchanged.

All mutation is deterministic and traceable via `TurnReplayTrace`:
- `trcLearningQueryType`
- `trcExternalTool`
- `trcLearningValidationStatus`
- `trcLearningSandboxResult`
- `trcLearningGraftTurn`
- `trcLearningRejectReason`

### 2.7 Effect wiring

`TurnReqExternalQuery` / `TurnResExternalQuery` added to the turn effect system.  The runtime handler in `Wiring/Handlers.hs` resolves the IO by calling `buildTransportFromEnv` and `queryExternalTool`, then injects the result into `TurnInput.tiExternalQueryResult` so the pure `Finalize` stage can apply it.

## 3. Consequences

- **External loop is closed**: the system can now reason about a gap, request a concept from an LLM, validate the response, and safely integrate it.
- **Fail-closed by default**: any transport, parse, validation, or sandbox failure rejects the fruit and telemetry records the exact stage.
- **Mock fallback preserves determinism**: CI and low-RAM local runs never depend on a live API key.
- **No threshold weakening**: sandbox gate is additive; existing shadow, legitimacy, and commitment gates are untouched.
- **Telemetry completeness**: six new trace fields let operators diagnose why a given external query was accepted or rejected.

## 4. Acceptance Criteria

- [x] `ExternalQueryError` typed taxonomy with 6 constructors.
- [x] `LLMTransport` supports Mock and Mistral with env-based builder.
- [x] Missing API key falls back to mock transport (no hard failure).
- [x] `validateFruitPayload` enforces word presence, definition length, morphology sanity, and lexicon conflict.
- [x] `parseLLMResponseToFruit` uses strict JSON-first then constrained text fallback.
- [x] `runSandboxGate` rejects degrading candidates and accepts improving ones.
- [x] `runLearningStep` wires transport → parse → validate → sandbox → graft/quarantine → telemetry.
- [x] `applyExternalLearning` grafts accepted fruit into `SystemState` atomically in `Finalize.Precommit`.
- [x] Six new `TurnReplayTrace` fields populated for every external learning interaction.
- [x] Architecture gate 12/12 PASS.
- [x] Fast suite: 537/537 PASS; full suite: 664/664 PASS.
