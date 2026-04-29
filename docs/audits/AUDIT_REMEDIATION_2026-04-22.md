# Audit Remediation 2026-04-22

Historical note: this report predates the local-recovery architecture. Any
references to LLM provider wiring below are superseded; current turn execution
does not use an LLM rescue fallback.

## Scope

- Fix P1/P2/P3 findings from strengthened audit:
  - `SessionLock` race on concurrent lock creation
  - SQLite overflow-path exception safety and pool behavior
  - Agda typecheck timeout guard
  - Shared HTTP manager reuse for LLM calls
  - Datalog resource-path robustness
  - Dead code and repo hygiene (`cabal.project.local`)
  - Coverage expansion for Dream/Identity/SessionLock flows

## Implemented Changes

1. `src/QxFx0/Core/SessionLock.hs`
- Replaced non-atomic insert pattern with `Map.insertWith` keep-existing semantics in STM.

2. `src/QxFx0/Bridge/SQLite.hs`
- Made `withPooledDB` exception-safe in both pooled and overflow paths via `finally`.
- Ensured overflow connection is always closed and pool `MVar` is always restored.
- Switched pool return order from append (`O(n)`) to LIFO prepend (`O(1)`).
- Added `execOrThrow` helper to fail fast on SQLite exec errors.

3. `src/QxFx0/Bridge/AgdaR5.hs`
- Added timeout around `agda` process execution.
- Added `QXFX0_AGDA_TIMEOUT_MS` env override with default fallback.

4. `src/QxFx0/Types/Thresholds/Constants.hs`
- Added `agdaTypecheckTimeoutMsDefault`.

5. `src/QxFx0/Bridge/LLM/Provider.hs`
- Added `callLLMWithManager` to allow shared HTTP manager usage.
- Kept `callLLM` as compatibility wrapper.

6. `src/QxFx0/Runtime/Wiring.hs`
- Added shared HTTP manager to runtime workers.
- Switched LLM call path to `callLLMWithManager`.

7. `src/QxFx0/Bridge/Datalog.hs`
- Switched datalog directory derivation from `rpAgdaSpec` to `rpDatalogRules`.

8. `src/QxFx0/Types/Observability.hs`
- Removed unused `renderLogicalBond` helper.

9. `.gitignore`
- Added `cabal.project.local`.

10. Tests
- `test/Test/Suite/CoreBehavior.hs`
  - Added burst session-lock serialization test.
  - Added dream cycle/catchup behavior tests.
  - Added identity signal + identity guard tests.
- `test/Test/Suite/RuntimeInfrastructure.hs`
  - Added Agda timeout behavior test.
  - Added pooled SQLite overflow recovery usability test.

## Verification Log

- Baseline before edits:
  - `bash scripts/verify.sh` -> PASS
- Post-fix verification:
  - `cabal build all --ghc-option=-Werror --ghc-option=-Wunused-binds --ghc-option=-Wunused-imports --ghc-option=-Wunused-top-binds` -> PASS
  - `cabal test qxfx0-test` -> PASS
  - `bash scripts/check_architecture.sh` -> PASS
  - `python3 scripts/verify_agda_sync.py` -> PASS
  - `bash scripts/check_generated_artifacts.sh` -> PASS
  - `bash scripts/check_lexicon.sh` -> PASS
  - `bash scripts/verify.sh` -> PASS
  - `bash scripts/release-smoke.sh` -> PASS (10/10, VERDICT: ACCEPT)
  - `cabal check` -> PASS (clean package hygiene)
