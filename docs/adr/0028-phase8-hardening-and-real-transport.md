# ADR-0028: Phase 8 Hardening — Real Transport, Typed Fallback, API Key Redaction

- **Status**: Accepted
- **Date**: 2026-05-20
- **Refines**:
  - [ADR-0027 — Phase 8 External Learning Loop](./0027-phase8-external-learning-loop.md)
- **Related**:
  - `QxFx0.Bridge.ExternalLLM`
  - `QxFx0.Types.ExternalQuery`
  - `QxFx0.Learning.Validator`
  - `QxFx0.Learning.Sandbox`

## 1. Context

Phase 8 MVP wired a Mistral transport with basic error handling and mock fallback.
Before moving to production scenarios, we needed to harden three surfaces:

1. **Transport configuration** — env vars were read inline without an explicit config
   contract; the fallback path was implicit.
2. **Error taxonomy** — HTTP status codes (401/403/429/5xx) were not mapped to
   distinct constructors; telemetry lost granularity.
3. **API key hygiene** — the `Show` instance for `MistralConfig` could leak the
   bearer token into logs or traces.

## 2. Decision

### 2.1 Explicit `ExternalQueryConfig` contract

A pure record captures the full transport contract:

```haskell
data ExternalQueryConfig = ExternalQueryConfig
  { eqcTransportMode   :: !Text          -- "mock" | "mistral"
  , eqcApiKey          :: !(Maybe Text)  -- redacted in Show
  , eqcModel           :: !Text
  , eqcEndpoint        :: !Text
  , eqcTimeoutMs       :: !Int
  , eqcFallbackReason  :: !(Maybe TransportFallbackReason)
  }
```

`buildTransportFromEnv` now:
1. Reads env vars into `ExternalQueryConfig`.
2. Calls `buildTransportFromConfig`, which makes the fallback decision explicit.

### 2.2 `TransportFallbackReason` — deterministic telemetry

Four typed reasons explain why the real Mistral path was not taken:

| Reason | Trigger | Telemetry Tag |
|--------|---------|---------------|
| `TfrEnvNotSet` | `QXFX0_LLM_TRANSPORT` missing or not "mistral" | `env_not_set` |
| `TfrKeyMissing` | `QXFX0_MISTRAL_API_KEY` absent/empty | `key_missing` |
| `TfrExplicitMock` | User explicitly set `mock` | `explicit_mock` |
| `TfrUnsafeEndpoint` | Endpoint does not start with `https://` | `unsafe_endpoint` |

The `eqcFallbackReason` field is carried into the `MockTransport` constructor so
unit tests and telemetry can assert the exact path taken.

### 2.3 API key redaction

`Show` instances for `ExternalQueryConfig` and `LLMTransport` replace the key with
`<REDACTED>`.  Serialisation (`ToJSON`) of `ExternalQueryConfig` is only used in
mock/test contexts where `eqcApiKey` is already `Nothing`.

### 2.4 Detailed HTTP error mapping

`mistralQuery` now discriminates:

- `401` / `403` → `EqeAuthFailure` (with status message + body snippet)
- `429` → `EqeRateLimited`
- `5xx` → `EqeServerError`
- Other `4xx` → `EqeInvalidResponse`
- Empty body after 2xx → `EqeEmptyResponse`

All constructors carry a `Text` payload for operator diagnosis.

### 2.5 Validator tightening

Two new rejection paths:

- `VeSemanticallyEmpty` — definition consists only of English stop-words
  (e.g. "a thing is a thing").  A minimal stop-word list is kept inline;
  it is not meant to be linguistically complete, only to catch obvious junk.
- `VeInvalidSchema` — top-level JSON schema mismatch (used by the parser layer
  when it cannot decode the expected fields).

The validator order is unchanged: word → definition length → semantic
emptiness → morphology sanity → lexicon conflict.

### 2.6 Sandbox uplift

`SandboxConfig` exposes all tunables:

```haskell
data SandboxConfig = SandboxConfig
  { scWindowSize        :: !Int     -- default 5
  , scSafetyFloor       :: !Double  -- default -0.3
  , scMinNetScore       :: !Double  -- default -0.05
  , scMaxLatencyIncrease :: !Double  -- default 0.20 (20%)
  , scTimeoutBudgetUs   :: !Int     -- default 50 ms
  }
```

Acceptance policy:
- Strict non-regression: projected conatus ≥ safetyFloor AND netScore ≥ minNetScore.
- Improvement bonus: if both `conatusDelta` and `predictiveDelta` are positive,
  the net-score threshold is relaxed by +0.05.
- Repair-loop risk gate: if loop frequency > 0.8, reject regardless of deltas.

`runSandboxGateWithConfig` is pure and deterministic; no real timer is used in
the low-RAM test profile.  The `scTimeoutBudgetUs` field is reserved for future
profiling integration.

## 3. Consequences

- **Operator observability improved**: every mock fallback carries an explicit
  machine-readable reason.
- **Security**: API key never appears in `show` output or logs.
- **Fail-closed strengthened**: empty 2xx bodies and unsafe endpoints are rejected.
- **Test determinism**: `buildTransportFromConfig` allows unit tests to construct
  exact fallback scenarios without env-var manipulation.
- **No gate weakening**: all thresholds are additive or equal to previous defaults.

## 4. Acceptance Criteria

- [x] `ExternalQueryConfig` typed contract with redacted `Show`.
- [x] `TransportFallbackReason` with four constructors and rendered telemetry tags.
- [x] `mistralQuery` maps 401/403/429/5xx/empty-body to distinct errors.
- [x] `VeSemanticallyEmpty` rejects stop-word-only definitions.
- [x] `SandboxConfig` with configurable window, floor, and improvement bonus.
- [x] Fast suite: 551/551 PASS; full suite: 678/678 PASS.
- [x] Architecture gate: 12/12 invariants PASS.
- [x] GF quality gate: 0 errors, 0 warnings PASS.
