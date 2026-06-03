# QxFx0 Singleton Register

This register enumerates the remaining justified process-wide singletons in the
current hardening contour.

| module | singleton_name | why_global | lifecycle_owner | init_semantics | teardown_semantics | tests_covering_initialization_failure_behavior | acceptable_alternative_not_chosen |
|---|---|---|---|---|---|---|---|
| `QxFx0.Lexicon.GfMap` | `gfMapLoadResult` | immutable GF lexicon map must remain pure/read-only after one load | runtime process | `unsafePerformIO loadCanonicalGfMap`, `NOINLINE`; render path now fail-closes on `GfMapLoadFailed`, and generic-topic substitution is kept explicit through `gf_default_lexeme*` derivation tags instead of silently passing as authoritative GF output | immutable cached value; no teardown | reliability hardening tests cover missing/empty/healthy GF map contours plus explicit `gf_map_unavailable:*` and `gf_default_lexeme*` degradation semantics | eagerly threading a loaded map through every render path would have widened the current refactor surface more than necessary |
| `QxFx0.Core.PipelineIO.Test` | test-harness `consciousState` / `intuitionState` | deterministic isolated mutable cells for the in-memory test interpreter only | test harness | `unsafePerformIO (newMVar ...)` inside `mkTestPipelineIO` | test-lifetime only | `qxfx0-test-fast` covers pipeline/test-interpreter paths | replacing these with a larger explicit test runtime record is desirable but deferred because this singleton is test-only, not production |
