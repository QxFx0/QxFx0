# Security Audit Closure Report — WP1–WP5

**Date:** 2026-05-22  
**Base SHA:** `d49e9a7` (post-WP6 roadmap patch)  
**Final HEAD:** `TBD`  
**Scope:** GFMap silent degradation, LLM endpoint hardening, structured response parsing, doc sync, Python CI coverage.

---

## Executive Verdict

| Audit Item | Before | After | Verdict |
|---|---|---|---|
| GFMAP_SILENT_DEGRADATION | Silent empty map on missing/corrupt resource | Explicit `GfMapLoadStatus` with machine-readable reason | **PASS** |
| LLM_ENDPOINT_HARDENING | HTTPS check only, no host allowlist | Allowlist + opt-in override + fail-closed fallback | **PASS** |
| STRUCTURED_PARSING_ROBUSTNESS | Brittle string-search `extractStructured` | Typed Aeson decoder for chat-completion envelope | **PASS** |
| DOC_SURFACE_SYNC | README listed unverified aggregate gates | Verified commands marked, INFRA-DEFERRED noted with blockers | **PASS** |
| PYTHON_CI_STATUS | Unclear if Python tests existed | Proven: no unit-test suite; 3 check scripts verified in CI; gap documented | **PROVEN** |
| CORE_HEALTH | — | — | **PASS** |

---

## Before / After Detail

### WP1 — GF Map Silent Degradation

**Risk:** Missing or corrupt `lexicon_funmap.tsv` at startup produced an empty map silently, leading to subtle semantic regressions.

**Changes:**
- `src/QxFx0/Lexicon/GfMap.hs`: added `GfMapLoadStatus` (`GfMapLoaded Int` | `GfMapLoadFailed Text`)
- Refactored `loadGfMapData` → `loadGfMapResult` + pure `loadGfMapFromContent` for unit-testability
- Exported `gfMapLoadStatus` for runtime observability
- `unsafePerformIO` invariant documented: total, deterministic, pure, never throws

**Tests added (4):** `testGfMapMissingResource`, `testGfMapEmptyContent`, `testGfMapValidContent`, `testGfMapRuntimeLoadHealthy`

### WP2 — LLM Endpoint Hardening

**Risk:** Bearer token could be sent to any `https://` endpoint configured via env var, enabling token leakage on misconfig.

**Changes:**
- `src/QxFx0/Types/ExternalQuery.hs`: added `TfrBlockedHost` fallback reason
- `src/QxFx0/Bridge/ExternalLLM.hs`: added `llmEndpointAllowlist` (`api.mistral.ai`, `api.fireworks.ai`)
- Added `validateEndpointUrl`: checks `https://` scheme, host in allowlist, optional `QXFX0_LLM_ALLOW_UNTRUSTED_HOST=1` override
- Applied validation in both `mistral` and `fireworks` branches of `buildTransportFromEnv`
- Violations return `MockTransport` with typed reason; no HTTP request is ever constructed

**Tests added (7):** `testLlmAllowlistMistral`, `testLlmAllowlistFireworks`, `testLlmBlockedHostNoOverride`, `testLlmBlockedHostWithOverride`, `testLlmNonHttpsEndpoint`, `testLlmEmptyEndpoint`, `testLlmAllowlistContents`

### WP3 — Structured Response Parsing

**Risk:** `extractStructured` used `T.breakOn "\"content\":\""` string search, fragile on API format shifts and could silently return partial/corrupt content.

**Changes:**
- `src/QxFx0/Bridge/ExternalLLM.hs`: added `ChatCompletionResponse`, `ChatCompletionChoice`, `ChatCompletionMessage` typed Aeson decoders with explicit `withObject` `parseJSON` instances
- Replaced `extractStructured` string search with `decodeStrict` → typed field access
- Invalid JSON / empty choices / missing content all return raw body for downstream handling
- Exported `extractStructured` for unit-test coverage

**Tests added (5):** `testExtractStructuredUnwrapsContent`, `testExtractStructuredEmptyChoices`, `testExtractStructuredInvalidJson`, `testExtractStructuredMissingContent`, `testExtractStructuredPlainPayload`

### WP4 — Doc / Command Surface Sync

**Changes:**
- `README.md` Quick Start updated: verified commands listed, INFRA-DEFERRED commands noted with exact blocker (RAM/timeout)
- Added 2026-05-22 status snapshot documenting WP1–WP3
- No cabal executable names changed; surface was already correct

### WP5 — Python Tests in CI

**Verified facts:**
- No `test_*.py` or `*_test.py` files exist in repo
- CI workflow `.github/workflows/ci.yml` runs `bash scripts/ci_gate_contract.sh`
- Three Python check scripts are executed as gate steps:
  - `scripts/sync_embedded_sql.py --check` → PASS
  - `scripts/check_schema_consistency.py` → PASS
  - `scripts/check_schema_contract.py` → PASS

**Gap documented:** `docs/PYTHON_TEST_GAP.md` with required work to close and rationale for deferral.

---

## Gate Table (Post-Audit)

| # | Command | Exit | Verdict | Evidence |
|---|---------|------|---------|----------|
| 1 | `cabal build all` | 0 | **PASS** | 250 modules compiled, 0 errors |
| 2 | `cabal test qxfx0-test-fast` | 0 | **PASS** | 629/629 cases, 0 errors, 0 failures |
| 3 | `bash scripts/check_architecture.sh` | 0 | **PASS** | 12 invariants OK |
| 4 | `bash scripts/gf_quality_gate.sh` | 0 | **PASS** | 0 errors, 0 warnings |
| 5 | `python3 scripts/sync_embedded_sql.py --check` | 0 | **PASS** | `EmbeddedSQL.hs is in sync` |
| 6 | `python3 scripts/check_schema_consistency.py` | 0 | **PASS** | 23 objects match |
| 7 | `python3 scripts/check_schema_contract.py` | 0 | **PASS** | 26 objects match |
| 8 | `bash scripts/check_generated_artifacts.sh` | 124 | **INFRA-DEFERRED** | timeout >60 s (low-RAM) |
| 9 | `bash scripts/check_lexicon.sh` | 124 | **INFRA-DEFERRED** | timeout >60 s (low-RAM) |

---

## Security Proof Table

| Case | Expected | Actual | Status |
|------|----------|--------|--------|
| Official Mistral host (`api.mistral.ai`) | Allowed | `Right ()` | ✅ |
| Official Fireworks host (`api.fireworks.ai`) | Allowed | `Right ()` | ✅ |
| Untrusted host (`evil.com`) no override | Blocked, `TfrBlockedHost` | `Left TfrBlockedHost` | ✅ |
| Untrusted host with `ALLOW_UNTRUSTED_HOST=1` | Allowed | `Right ()` | ✅ |
| Non-https endpoint (`http://...`) | Blocked, `TfrUnsafeEndpoint` | `Left TfrUnsafeEndpoint` | ✅ |
| Empty endpoint | Blocked, `TfrUnsafeEndpoint` | `Left TfrUnsafeEndpoint` | ✅ |
| GF map missing resource | `GfMapLoadFailed` | `GfMapLoadFailed "resource_missing_or_unreadable"` | ✅ |
| GF map empty content | `GfMapLoadFailed` | `GfMapLoadFailed "resource_empty_or_unparseable"` | ✅ |
| Valid chat-completion envelope | Content extracted correctly | `"{\"word\":\"свобода\"}"` | ✅ |
| Invalid JSON envelope | Raw body passed through | Raw body returned | ✅ |

---

## Changed Files

- `src/QxFx0/Lexicon/GfMap.hs` — WP1
- `src/QxFx0/Bridge/ExternalLLM.hs` — WP2, WP3
- `src/QxFx0/Types/ExternalQuery.hs` — WP2
- `test/Test/Suite/ReliabilityHardening.hs` — WP1, WP2, WP3 tests
- `README.md` — WP4
- `docs/PYTHON_TEST_GAP.md` — WP5
- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` — evidence update

---

## Commit SHAs (in order)

1. `9aa8cd8` fix(gfmap): eliminate silent fallback, expose structured GfMapLoadStatus
2. `bde9364` fix(external-llm): enforce endpoint allowlist and fail-closed host validation
3. `96e3080` refactor(learning-parser): replace brittle string extraction with typed JSON decoder
4. `b6702c2` docs(runtime): sync README quick-start and add 2026-05-22 status snapshot
5. `88687dc` ci(test): document verified Python test gap
6. `b8029c0` docs(evidence): update canonical evidence index + release closure report

---

## Residual Risks

1. **Python unit-test gap** — documented, deferred, non-blocking for core contour.
2. **INFRA-DEFERRED gates** (`check_generated_artifacts.sh`, `check_lexicon.sh`, aggregate `ci_gate_contract.sh`) — require high-RAM runner; verified individually where possible.
3. **HTTP runtime perimeter** — not in scope of this audit; existing `app/CLI/Http.hs` and `scripts/http_runtime.py` perimeter invariants remain untouched.

---

## Final `git status --short`

```
?? reports/releases/wp6_live_validation_closure.md
?? reports/wp6_live/
```

(Only untracked pre-existing reports; all audit changes are committed.)

---

## One-Line Conclusion

Security/reliability hardening closed: GFMap silent degradation eliminated, LLM endpoint allowlist enforced, typed JSON decoder replaces brittle parsing, core gates green (629/629), all residual risks documented.
