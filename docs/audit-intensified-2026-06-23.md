# Intensified Audit: Painful Points (2026-06-23)

**Scope:** New findings beyond prior architectural, blind-spot, and dead-code audits. Focus on runtime safety, serialization integrity, security, test quality, and error handling.

---

## Finding 1: Serialization Asymmetry — 49 Write-Only Types (CRITICAL)

**49 types have `ToJSON` but no `FromJSON`.** They can be serialized to SQLite/JSON but can never be decoded back. This is the Class-II defect at scale.

Key affected types:
- `SystemState` — has both, but 49 satellite types don't
- `MeaningGraph`, `MeaningEdge`, `MeaningState` — semantic graph cannot be restored
- `ClaimAst`, `AuthorityClass` — authority claims are write-only
- `TurnDecision`, `ExecutedTurnOutcome` — turn decisions cannot be deserialized
- `SemanticAnchor`, `SemanticRelation` — semantic anchors are write-only
- `ResponseStrategy`, `ResponseStance`, `ResponseDepth` — response metadata is write-only
- `ObservabilityState` — observability data cannot be restored
- `IdentitySignalSnapshot` — identity signals are write-only
- `LiveRenderTelemetry` — telemetry is write-only
- All `Gf*` types (GfNP, GfVP, GfRelation, etc.) — GF parse results are write-only

**Round-trip test coverage:** 16 out of 136 `ToJSON` instances are tested (11.8%). The `RoundTrip.hs` suite covers only a small subset of recovery/shadow/decision types. `SystemState` round-trip is tested only via a slow integration test, not a unit property test.

**Risk:** Any persisted state containing these types is a data-loss trap. The system writes data it cannot read back.

---

## Finding 2: NixGuard Silent Security Downgrade (HIGH)

`NixGuard.hs` attempts `nix-instantiate --restricted` first, but when the `--restricted` flag is unsupported, it **silently falls back to unrestricted mode**:

```haskell
runNixEval nixExpr = do
  restrictedResult <- runNixInstantiate True nixExpr
  case restrictedResult of
    Left err | isRestrictedFlagUnsupported err ->
      runNixInstantiate False nixExpr  -- UNRESTRICTED!
    _ -> pure restrictedResult
```

The unrestricted mode runs user-influenced Nix expressions without sandboxing. Combined with the known fail-open behavior (`Unavailable` → turn proceeds), this means:
1. If nix-instantiate doesn't support `--restricted`, guard runs unrestricted
2. If nix-instantiate fails entirely, guard returns `Unavailable`
3. `Unavailable` in normal mode → turn proceeds (fail-open)

**Attack surface:** The `concept` parameter (from user input) is sanitized via `normalizeConceptKey`/`isSafeChar`, but `agency` and `tension` (Double values) are interpolated via `T.pack . show` into the Nix expression. While `show` on Double is generally safe, the overall pattern of building Nix expressions from runtime values is fragile.

---

## Finding 3: unsafePerformIO with Global Mutable State (HIGH)

3 sites create global mutable state via `unsafePerformIO` at module load time:

1. `Runtime/PGF.hs:62` — `pgfCacheRef = unsafePerformIO (newIORef Map.empty)` — global PGF cache, no thread safety guarantee
2. `Core/PipelineIO/Test.hs:80-81` — `unsafePerformIO (newMVar ...)` — test pipeline creates MVars at load time
3. `Self/ConfigLoad.hs:45` — `loadConfigOrBuiltin` — reads config files at module initialization via `unsafePerformIO`

Additionally, `Lexicon/PGFStatus.hs` and `Lexicon/GfMap.hs` use `unsafePerformIO` to load PGF files at module load time.

**Risk:** Module load order becomes non-deterministic. Config file reads at init time mean the environment must be set before any import. The PGF cache `IORef` has no concurrent access protection — concurrent reads are safe, but concurrent writes (cache population) could race.

---

## Finding 4: Silent Error Swallowing — 14 Sites (MEDIUM-HIGH)

14 `_ -> pure ()` / `_ -> return ()` sites silently discard errors:

- `Runtime/Engine.hs:218` — `Left _ -> pure ()` in the main loop: IO errors from `T.getLine` are silently ignored, potentially causing the loop to spin
- `Types/State/Governance.hs` — 4 sites (lines 692, 696, 709, 787): governance event processing silently drops unmatched cases
- `Bridge/SQLite/Bootstrap.hs` — 3 sites: schema validation errors silently discarded
- `Bridge/SQLite/Pool.hs:174` — `Right _ -> pure ()`: connection cleanup errors swallowed
- `Bridge/Datalog/Support.hs:67` — `catchIO action (\_ -> pure ())`: datalog errors completely silenced
- `Bridge/TxStatement.hs:74` — transaction statement errors swallowed
- `Core/TurnPipeline/Finalize/Commit.hs:207` — `Right _ -> pure ()`: commit errors swallowed
- `Governance/Replay.hs:169` — replay errors swallowed

**Risk:** Governance event drops are invisible. SQLite schema mismatches are invisible. Transaction failures are invisible. These are exactly the kind of silent failures that make production debugging impossible.

---

## Finding 5: No Content Quality Gate — Tests Check Routing, Not Thought (HIGH)

The system has 3,527 HUnit assertions across 100 test files, but content quality testing is shallow:

- `RussianQuality.hs` (568 LOC) checks:
  - `not . T.null . T.strip` — output is non-empty
  - `not (T.null (T.strip rendered))` — rendered text exists
  - No check for grammatical correctness, semantic coherence, factual accuracy, or dialogue relevance

- No test verifies that a response to "что такое свобода" is actually about freedom
- No test checks for hallucination, contradiction, or topic drift
- No test validates Russian grammar or morphology in generated output
- The `assertBool "L3e-0 baseline measurement complete" True` is a tautological assertion

**The system can produce empty, nonsensical, or off-topic output and all tests pass.**

---

## Finding 6: Error Provenance Loss — 15+ `T.pack . show` Sites (MEDIUM)

Structured errors are flattened to strings via `T.pack . show` in 15+ locations:

- `Bridge/StatePersistence.hs:307-326` — shadow family/force values serialized as `show` strings into SQLite columns
- `Core/Ego.hs:100` — ego history doubles stored as `show` strings
- `Self/Perspective.hs:763` — identity claims rendered as `show` strings
- `Core/TurnPipeline/Route/Render.hs:1117` — render telemetry flattened
- `Bridge/NixCache.hs:96` — cache keys built from `show`

**Risk:** Once structured data is flattened to `show` strings, it cannot be parsed back. Debugging from logs requires reverse-engineering `Show` output. This compounds Finding 1 — the system is systematically destroying structured information at persistence boundaries.

---

## Finding 7: Integration Test Coverage is 5% of Total (MEDIUM)

Test distribution across cabal suites:
- `qxfx0-test-unit`: 111 test groups
- `qxfx0-test-fast`: 51 test groups
- `qxfx0-test-slow`: 9 test groups
- `qxfx0-test-integration`: 6 test groups
- `qxfx0-test-property`: 4 test groups

Only 6 integration test groups vs 111 unit groups. The integration suite imports only 5 test modules (SemanticCorpus, LegalAdapter, RenderDialogueCoverage, RussianQuality, LongSessionCorpus). Critical paths like full turn pipeline execution, state persistence round-trips, and governance enforcement are only in slow/integration suites that may not run in CI.

---

## Finding 8: External LLM — 30s Timeout, No Circuit Breaker (MEDIUM)

`Bridge/ExternalLLM.hs` has a 30-second default timeout (`llmDefaultTimeoutMs = 30000`) with configurable minimum. However:
- No circuit breaker pattern — repeated failures don't disable the backend
- No retry budget — every call gets the full timeout
- No fallback to local generation when external LLM is unavailable
- The embedding backend has a 5s timeout (better) but also no circuit breaker

**Risk:** A slow or unresponsive LLM backend blocks the turn pipeline for 30s per call. With no circuit breaker, the system will keep trying indefinitely.

---

## Finding 9: ADR Directories Empty (INFO)

Post-Phase-0 cleanup, ADR directories show 0 files in accepted/, proposed/, or archived/. The 19 ADRs previously in proposed/ were archived in Phase 0, but the archived/ directory now also shows 0. This suggests either:
- ADRs were deleted entirely (not just moved)
- The directory structure changed
- The find pattern doesn't match the actual file naming

This needs verification — if ADRs were deleted rather than archived, the decision history is lost.

---

## Finding 10: NixGuard Input Interpolation Risk (MEDIUM)

The NixGuard builds a Nix expression by interpolating runtime values:
```haskell
let nixExpr = "let agency = " <> T.pack (show agency)
             <> "; tension = " <> T.pack (show tension)
             <> "; data = import " <> nixStringLiteral (T.pack absoluteNixPath)
             <> "; key = " <> nixStringLiteral conceptKey
```

While `isSafeChar` filters the concept key and `nixStringLiteral` escapes strings, `agency` and `tension` are `Double` values interpolated via `show`. Haskell's `show` for `Double` is generally safe (produces numeric strings or `NaN`/`Infinity`), but `NaN`/`Infinity` in a Nix expression would cause evaluation errors, not security issues. The `absoluteNixPath` is escaped via `nixStringLiteral` but the path itself comes from `makeAbsolute` on a user-influenced `FilePath`.

**Risk:** Low for direct injection, but the pattern of building code from data is inherently fragile and should use proper Nix AST construction instead of string interpolation.

---

## Summary: Painful Points Ranked by Severity

| # | Finding | Severity | LOC Impact |
|---|---------|----------|------------|
| 1 | 49 write-only serialization types | CRITICAL | 49 types affected |
| 2 | NixGuard silent security downgrade | HIGH | Security risk |
| 3 | unsafePerformIO global mutable state | HIGH | 5 modules |
| 4 | 14 silent error swallowing sites | MEDIUM-HIGH | 14 sites |
| 5 | No content quality gate | HIGH | Systemic |
| 6 | Error provenance loss via T.pack.show | MEDIUM | 15+ sites |
| 7 | Integration test coverage 5% | MEDIUM | Test architecture |
| 8 | External LLM no circuit breaker | MEDIUM | Runtime risk |
| 9 | ADR directories empty | INFO | Process risk |
| 10 | NixGuard input interpolation | MEDIUM | Security risk |

---

## Recommendations (Priority Order)

1. **Fix serialization asymmetry:** Add `FromJSON` to all 49 write-only types or mark them as telemetry-only (never persisted). Add round-trip property tests for all persisted types.
2. **Fix NixGuard security downgrade:** When `--restricted` is unsupported, return `Unavailable` (fail-open) instead of silently running unrestricted. Log the downgrade.
3. **Replace unsafePerformIO config loading:** Use explicit initialization in `main` or a `ReaderT`/`Has` pattern. Module-level IO is non-deterministic.
4. **Audit all 14 silent error sites:** Each `_ -> pure ()` must either log the error or have a documented reason for discarding it.
5. **Add content quality tests:** At minimum, test that responses to known prompts contain expected keywords and are grammatically valid Russian.
6. **Add circuit breaker to ExternalLLM:** After N consecutive failures, disable the backend for a cooldown period.
7. **Increase integration test proportion:** Target 20% integration, not 5%.
