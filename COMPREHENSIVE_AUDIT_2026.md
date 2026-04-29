# QxFx0 Comprehensive Architectural Audit Report

**Audit Date:** 2026-04-22  
**Auditor:** Automated Code Analysis  
**Scope:** Full architectural review, technical debt detection, best practices compliance  
**Codebase:** 134 Haskell modules in `src/`, 186 test cases, ~15,478 lines in `src/`

---

## Executive Summary

QxFx0 is a sophisticated philosophical dialogue system with genuine architectural strengths:
- Real phase decomposition in TurnPipeline
- Strong type system usage with 14 canonical move families
- Agda↔Haskell constructor sync verified at build time
- Transactional persistence with corruption recovery
- Multi-layered safety guard pipeline

**Current State:** A live regression was discovered during the final audit iteration: `styleFromLegitimacy` was removed from exports but is still referenced in tests, causing `cabal build` and `cabal test` to fail (`release-smoke.sh` REJECT). Additionally, three HIGH-severity exception-safety defects were identified in the SQLite pool layer: active transactions can be returned to the pool on exception, partial pool initialization leaks connections, and `withDB` only catches `IOException` (missing other sync exceptions). These are not background maintenance items — they are runtime correctness blockers. Supply-chain determinism and formal-verification confidence also require hardening.

### Overall Readiness Scores

| Dimension | Score | Trend |
|-----------|-------|-------|
| **Architecture Readiness** | 9.0/10 | ✅ Design is sound; pool safety is implementation bug |
| **Layer Integrity** | 9.3/10 | ✅ Core↔Bridge coupling eliminated |
| **Spec Contract Integrity** | 6.0/10 | ⚠️ Structural Agda sync, not behavioral equivalence |
| **Data Quality** | 9.5/10 | ✅ Morphology clean |
| **Operational Maturity** | 5.0/10 | 🔴 Release gate broken; pool exception leaks; Datalog no timeout |
| **Test Coverage** | 7.0/10 | ⚠️ 6 QuickCheck properties only; missing roundtrip/concurrency/routing |
| **Supply-Chain Determinism** | 5.0/10 | 🔴 No freeze file; unpinned external tools |
| **Overall System Maturity** | **7.5/10** | 🔴 Down from 9.4 due to live regression + pool safety holes |

---

## Post-Remediation Update (2026-04-22, later pass)

Deep-dive operational findings have been implemented and re-verified:
- `SessionLock` concurrent first-insert race fixed.
- SQLite overflow path now closes connections and restores pool state on exceptions.
- Agda typecheck now has timeout guard (`QXFX0_AGDA_TIMEOUT_MS`).
- Runtime LLM path now reuses shared HTTP manager.
- Datalog rule directory now resolves from `rpDatalogRules`.
- Dead code and repo hygiene items closed (`renderLogicalBond`, `cabal.project.local` ignore).
- Additional tests added for Dream/Identity/SessionLock and runtime infra timeout/overflow behavior.

Verification snapshot after fixes (Iteration 5–6):
- `cabal build all --ghc-option=-Werror --ghc-option=-Wunused-binds --ghc-option=-Wunused-imports --ghc-option=-Wunused-top-binds` PASS
- `cabal test qxfx0-test` PASS (194/194)
- `bash scripts/verify.sh` PASS
- `bash scripts/release-smoke.sh` PASS (10/10, VERDICT: ACCEPT)

**Iteration 7 Regression (2026-04-23):**
- `cabal build all` **FAIL** — `Not in scope: 'Legitimacy.styleFromLegitimacy'` at `test/Test/Suite/CoreBehavior.hs:1719`
- `cabal test qxfx0-test` **FAIL** — same compilation error
- `bash scripts/release-smoke.sh` **FAIL** — REJECT at gates [1] and [2]
- This invalidates the "all commands currently pass" claim from Iteration 6.

---

## CRITICAL ISSUES (Historical, Closed)

### ~~C1: Core→Bridge Logic Coupling Violates Layer Contract~~
**Status:** CLOSED  
**Verification:**
- `ShadowDivergence` + `computeShadowLegitimacyPenalty` live in `Types.ShadowDivergence`
- Core route flow uses `PipelineIO` boundary effects, not direct Bridge calls
- `scripts/check_architecture.sh` check [4] enforces no Core→Bridge imports

### ~~C2: `routeFamily` Returns 14-Element Tuple~~
**Status:** CLOSED  
**Verification:**
- Routing now returns named `RoutingDecision`
- Call sites consume record accessors instead of positional tuple unpacking

### ~~C3: Morphology Dictionary Typos and Wrong Lemmas~~
**Status:** CLOSED  
**Verification:**
- dictionary entries corrected
- lexicon quality gate is stable (`scripts/check_lexicon.sh`, score 10.00 / 85 lemmas)

### ~~C4: Bridge→Core Reverse Imports Create Circular Dependency~~
**Status:** CLOSED — shims eliminated  
**Verification:** `scripts/check_architecture.sh` [4] now enforces zero Core imports from Bridge:
```bash
# check_architecture.sh line 40-45
if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Core' "$file" >/dev/null 2>&1; then
  fail_violation "$file imports Core from Bridge (shims removed)"
fi
```
All four compatibility shims (`Bridge/ClaimBuilder`, `Bridge/LegitimacyBridge`, `Bridge/SqlEgo`, `Bridge.hs` re-exports) have been removed. Bridge is now a pure adapter layer with no reverse Core dependency.

---

## WARNINGS (Open, Non-Critical)

### W1: Inline `0.72` Constants (Historical)
**Status:** CLOSED  
**Resolution:** parser and intuition thresholds were extracted into `Types.Thresholds.Constants` and wired through typed imports.

---

### W2: SQL Schema Exists in Three Operational Forms
**Severity:** LOW  
**Location:**
- `spec/sql/schema.sql`
- `migrations/001_initial_schema.sql`
- generated `src/QxFx0/Bridge/EmbeddedSQL.hs`

**Impact:** minor maintenance overhead; correctness is currently protected by `sync_embedded_sql.py` and gates.

**Recommended fix:** consolidate to one canonical runtime source where practical.

---

### W3: Lower-Level Pure-Module Coverage Can Be Expanded
**Severity:** LOW  
**Location:** selected pure modules (notably `DreamDynamics`, `MeaningGraph` deep vector/math paths)

**Impact:** low-to-medium regression detection depth in edge math-heavy paths.

**Recommended fix:** add targeted unit/property tests on vector-heavy branches.

---

### Closed Warning Notes
- `normalizeClaimText` duplication — CLOSED
- env var naming inconsistency for semantic introspection — CLOSED
- datalog CWD write concern — CLOSED

---

## SUGGESTIONS (Nice to Have)

### S1: Missing Documentation for Key Functions
**Severity:** LOW  
**Location:** Multiple modules

**Problem:** Many exported functions lack Haddock documentation:
- `Core/DreamDynamics.hs`: no module header docs, no function docs
- `Core/Consciousness.hs`: minimal docs
- `Core/TurnRouting.hs`: no docs for `routeFamily` or helpers

**Required Fix:**
1. Add Haddock comments for all public exports
2. Especially critical for complex modules like DreamDynamics

---

### S2: Hardcoded Magic Numbers
**Severity:** LOW  
**Location:** selected non-threshold heuristics

**Current status:** previous `0.72` threshold findings are closed; thresholds are centralized in `Types.Thresholds.Constants`.  

**Remaining suggestion:** continue migrating any newly introduced behavioral constants to named threshold/config symbols when they represent policy rather than data.

---

### S3: Inconsistent Error Handling Patterns
**Severity:** LOW  
**Location:** Bridge modules

**Problem:** Mixed error handling approaches:
- Some use `Either Text a` (e.g., `StatePersistence.saveState`)
- Some use `Maybe a` (e.g., `NSQL.prepare`)
- Some use `IO (Either Text a)` (e.g., `compileAndRunDatalog`)

**Required Fix:**
1. Standardize on `Either Text a` or custom error types
2. Use `MonadError` for composition where appropriate

---

### S4: Type Signature Inconsistencies
**Severity:** LOW  
**Location:** Multiple modules

**Problem:** Some functions have explicit type signatures, others rely on inference:
- `Core/DreamDynamics.hs`: all have signatures ✅
- `Core/Consciousness.hs`: all have signatures ✅
- `Bridge/Datalog.hs`: helper functions lack signatures ⚠️

**Required Fix:**
1. Add explicit type signatures to all top-level functions
2. Enable `-Wmissing-signatures` warning if desired

---

## POSITIVE FINDINGS (What's Working Well)

### ✅ Strong Architectural Patterns

1. **Phase Decomposition:** TurnPipeline genuinely split into Prepare (108 LOC), Route (182 LOC), Finalize (143 LOC) with shared Types (83 LOC)

2. **State Decomposition:** SystemState properly decomposed into DialogueState, IdentityState, SemanticState, ObservabilityState

3. **Runtime Ownership:** RuntimeContext explicitly decomposed into Caches, Workers, Locks, TurnRuntime

4. **Persistence Hardening:** saveState returns `Either Text SystemState` with explicit rollback; loadState uses safeDecode with per-field fallback

5. **Agda↔Haskell Sync:** 14 constructors verified in sync via `verify_agda_sync.py` and runtime checks

6. **Guard Safety Pipeline:** 7 invariant checks applied at two points in pipeline

7. **Build Hygiene:** `cabal check` clean, `cabal build all` warning-free, architecture boundary checks pass

---

## REMEDIATION ROADMAP

### Phase 1: Critical Fixes — CLOSED (all resolved)
- ~~Fix morphology dictionary typos~~ — DONE (score=10.00, 85 lemmas)
- ~~Consolidate `normalizeClaimText`~~ — DONE (single source in `Types.Domain`)
- ~~Move `ShadowDivergence` + `computeShadowLegitimacyPenalty` out of Bridge~~ — DONE (`Types.ShadowDivergence`)
- ~~Replace `routeFamily` tuple with named record~~ — DONE (`RoutingDecision` in `TurnPipeline.Types`)
- ~~Bridge compatibility shims~~ — DONE (fully eliminated, enforced by architecture gate [4])
- ~~Datalog CWD write~~ — DONE (uses `mktemp -d`)
- ~~Repo hygiene~~ — DONE (`__pycache__`/`semantic_rules.dl` removed and ignored)

---

### Phase 2: Remaining Structural Improvements
1. **Consolidate SQL schema sources** (2 hr) — P2
   - Merge `migrations/001_initial_schema.sql` into canonical `spec/sql/schema.sql`
2. **Add unit tests for lower-level pure modules** (4 hr) — P2
   - `DreamDynamics` vector math and dream cycle
   - `R5Dynamics` orbital classification
   - `MeaningGraph` edge rewire properties

**Estimated Effort:** ~6 hours

---

### Phase 3: Polish and Documentation
1. **Add Haddock documentation for key modules** (4 hr) — P3
   - `Core/DreamDynamics`, `Core/Consciousness`, `Core/R5Dynamics`, `Core/MeaningGraph`
2. **Standardize remaining error handling patterns** (2 hr) — P3
   - A few Bridge modules still mix `Either Text` / `Maybe` / `IO (Either Text)`; unify where beneficial

**Estimated Effort:** ~6 hours

---

**Total Estimated Effort:** ~12.5 hours (~1.5 working days)

---

## Iteration 7: Comprehensive Deep-dive — Final Audit (2026-04-23)

Methodology: concurrency/state correctness analysis, formal invariant review, pure/impure architecture verification, property-based testing gap analysis, security hardening review, supply-chain determinism audit, architectural completeness check, technical debt reconciliation, system cohesion assessment («как механические часы»). All findings are repo-grounded with file:line references.

### ⚠️ REGRESSION DISCOVERED DURING FINAL AUDIT

**CRITICAL — Broken Release Gate (`cabal build` / `cabal test` fail)**
- **Location:** `test/Test/Suite/CoreBehavior.hs:1719`
- **What:** `Legitimacy.styleFromLegitimacy score == Just StyleCautious` — function `styleFromLegitimacy` was removed from `QxFx0.Core.Legitimacy` (and its `Scoring` submodule) during a prior cleanup iteration, but the test reference was not updated.
- **Impact:** `cabal build all` and `cabal test qxfx0-test` fail with `Not in scope: 'Legitimacy.styleFromLegitimacy'`. The `release-smoke.sh` gate (10/10 constitutional checks) fails at gate [1] and [2].
- **Root cause:** incomplete cleanup — function removed from implementation and exports, but test dependency missed.
- **Fix:** either restore `styleFromLegitimacy` to the module export surface, or remove/adapt the test assertion.
- **Reproduction:** `bash scripts/release-smoke.sh` → FAIL at "Cabal build" and "Unit tests".

---

### NEW CRITICAL FINDINGS

#### C5: Active Transaction Returned to DB Pool on Exception (HIGH)
- **Location:** `src/QxFx0/Bridge/SQLite/Pool.hs:104-107` (pooled path)
- **What:** `withConnections restore (db : dbs)` returns a connection to the `MVar` pool after `action db` completes. If `action db` throws an exception **after** `BEGIN IMMEDIATE` (inside `saveStateWithProjection` or any callback), the connection is returned to the pool with an **active transaction** still open.
- **Impact:** Next `withPooledDB` consumer gets this connection, attempts `BEGIN IMMEDIATE` → `SQLITE_BUSY` / nested transaction error / deadlock. SQLite does not auto-rollback on connection reuse.
- **Proof:** `withConnections` does not wrap `action db` in `bracket` with `ROLLBACK` on exception.
- **Fix:** Wrap pooled path in `bracket` (or `finally`) that executes `NSQL.rollback db` before `putMVar pool (db : dbs)` when an exception escapes.

#### C6: `newDBPool` Partial Initialization Leaks Connections (MEDIUM)
- **Location:** `src/QxFx0/Bridge/SQLite/Pool.hs:39-52`
- **What:** `sequence (replicate size openOne)` opens `size` connections sequentially. If `openOne` throws on the k-th connection, the previously opened k-1 connections are never closed.
- **Impact:** Resource leak during startup under memory pressure or file-descriptor exhaustion.
- **Fix:** Use `bracket`-style accumulation or `try` + explicit cleanup loop.

#### C7: `withDB` Exception Safety Is Incomplete (MEDIUM)
- **Location:** `src/QxFx0/Bridge/SQLite/Pool.hs:61-73`
- **What:** `catchIO` catches only `IOException`. Other synchronous exceptions (e.g., `QxFx0Exception`, `AssertionFailed`, `ThreadKilled`) bypass the handler and the connection is never closed.
- **Impact:** Connection leak on non-IO exceptions.
- **Fix:** Replace `catchIO` with `finally` or `bracket` around `NSQL.close db`.

---

### NEW SECURITY / OPERATIONAL FINDINGS

#### S5: Datalog Execution Without Timeout (MEDIUM)
- **Location:** `src/QxFx0/Bridge/Datalog/Runtime.hs:267-280`
- **What:** `executeDatalogShadowWithExecutable` calls `readProcessWithExitCode executable ["-D", outDir, dlFile]` without any timeout guard.
- **Impact:** If Soufflé enters an infinite loop (e.g., on a malformed `.dl` file or stratification edge case), the Haskell thread hangs forever. Contrast: `NixGuard.runNixEval` already uses `timeout` from `System.Timeout`.
- **Fix:** Wrap in `System.Timeout.timeout` (or use `timeout` CLI prefix), matching the Nix guard pattern.

#### S6: HTTP Sidecar Plaintext API Key Transmission (MEDIUM)
- **Location:** `scripts/http_runtime.py:677-678`, `app/CLI/Http.hs:56`
- **What:** The Python `ThreadingHTTPServer` serves HTTP (not HTTPS). The `X-API-Key` header is transmitted in plaintext. `CLI/Http.hs` does not validate `hscHost` before passing it to the Python subprocess.
- **Impact:** If the sidecar is bound to a non-loopback interface (permitted when `API_KEY` is set), the API key is sniffable on the network segment.
- **Mitigation:** Default bind is `127.0.0.1`; non-loopback bind requires explicit `API_KEY` AND emits a warning. Still, no TLS.
- **Fix:** Document "loopback-only for production; TLS termination must be handled by reverse proxy for remote exposure."

#### S7: `check_architecture.sh` Regex Gate Is Text-Based, Not AST-Based (LOW)
- **Location:** `scripts/check_architecture.sh` check [5]
- **What:** Gate uses `rg 'SomeException'` to ban the exception type. This is a text search, not an AST analysis. A developer could bypass it by importing `SomeException` under a qualified or aliased name in one module and re-exporting it, so the consuming file never contains the literal string `SomeException`.
- **Impact:** Latent false-negative risk — the gate can miss banned patterns that do not contain the literal substring.
- **Evidence:** Current codebase has no such bypass usage (grep confirmed), so this is latent risk, not active bug.
- **Fix:** Add GHC `-Werror` on warnings that catch over-broad exception handling, or run an actual Haskell AST linter (e.g., `hlint` custom rule) in CI.

---

### NEW FORMAL / VERIFICATION FINDINGS

#### F3: Agda↔Haskell Sync Is Structural, Not Behavioral (LOW-MEDIUM)
- **Location:** `scripts/verify_agda_sync.py`, `spec/r5-snapshot.tsv`
- **What:** The sync checker verifies constructor name matching (14 `CM*` constructors) and function name mappings (`forceForFamily`, `clauseFormForIF`, etc.). It does **not** verify that Agda function bodies match Haskell runtime semantics. The TSV snapshot is generated from Haskell, not extracted from Agda proof terms.
- **Impact:** False confidence — the "formal guarantee" is actually a structural name-check, not a behavioral equivalence proof.
- **Evidence:** `verify_agda_sync.py` line 137-165 compare `show` of Haskell functions against TSV rows; TSV is produced by Haskell codegen.
- **Fix:** Update `AGENTS.md` and audit docs to explicitly state: "Agda↔Haskell sync is structural (constructor + function name coverage), not behavioral equivalence. Behavioral correctness is guaranteed by Haskell test suite, not Agda extraction."

---

### NEW SUPPLY-CHAIN / DETERMINISM FINDINGS

#### D1: No `cabal.project.freeze` (MEDIUM)
- **Location:** repository root
- **What:** 35 dependencies in `qxfx0.cabal` with `^>=` bounds, but no `cabal.project.freeze` committed. Patch-level releases of dependencies can introduce behavioral changes or Hackage metadata drift.
- **Impact:** Non-reproducible builds across time and machines.
- **Fix:** Run `cabal freeze` and commit `cabal.project.freeze`.

#### D2: External Tool Versions Not Pinned in Gates (MEDIUM)
- **Location:** `scripts/verify.sh`, `scripts/release-smoke.sh`
- **What:** Agda, Soufflé, Nix, Python3 are runtime/CI dependencies. The gates do not verify their versions (e.g., `agda --version`, `souffle --version`).
- **Impact:** CI passes with tool version X, but runtime behavior differs with version Y.
- **Fix:** Add minimum/maximum version assertions to `verify.sh`.

---

### NEW TESTING / PROPERTY GAPS

#### T3: Missing Property-Based Test Coverage (LOW)
- **What:** Only 6 QuickCheck properties exist in the test suite.
- **Gaps identified:**
  - State persistence roundtrip (`saveState → loadState` identity law)
  - TurnPipeline state machine invariants (14 families × 3 layers × 4 forces)
  - Concurrent session lock behavior (two threads, same session, overflow backpressure)
  - Routing invariants (legitimacy score monotonicity, shadow divergence consistency)
- **Fix:** Add `Arbitrary` instances for `SystemState`, `RoutingDecision`, `ShadowDivergence`; add roundtrip and monotonicity properties.

---

### REMEDIATION PLAN (Iteration 7)

| Priority | Item | Effort | Location |
|---|---|---|---|
| **P0 (CRITICAL)** | Fix `styleFromLegitimacy` regression — restore export or fix test | 15 min | `test/Test/Suite/CoreBehavior.hs:1719` |
| **P1 (HIGH)** | Add ROLLBACK cleanup in `withConnections` pooled path | 30 min | `src/QxFx0/Bridge/SQLite/Pool.hs:104-107` |
| **P1 (HIGH)** | Fix `newDBPool` partial-init connection leak | 20 min | `src/QxFx0/Bridge/SQLite/Pool.hs:39-52` |
| **P1 (HIGH)** | Replace `catchIO` with `finally`/`bracket` in `withDB` | 15 min | `src/QxFx0/Bridge/SQLite/Pool.hs:61-73` |
| **P2 (MEDIUM)** | Add timeout to Datalog executable call | 20 min | `src/QxFx0/Bridge/Datalog/Runtime.hs:267-280` |
| **P2 (MEDIUM)** | Generate and commit `cabal.project.freeze` | 10 min | repository root |
| **P2 (MEDIUM)** | Pin external tool versions in `verify.sh` | 20 min | `scripts/verify.sh` |
| **P2 (MEDIUM)** | Document HTTP sidecar TLS requirement | 10 min | `AGENTS.md` / docs |
| **P3 (LOW)** | Strengthen `SomeException` regex in architecture gate | 10 min | `scripts/check_architecture.sh` |
| **P3 (LOW)** | Document structural-only Agda sync | 15 min | `AGENTS.md` |
| **P3 (LOW)** | Expand QuickCheck properties (roundtrip, routing, concurrency) | 2-3 hr | `test/Test/Suite/` |
| **P3 (LOW)** | Haddock headers for ~20 domain sub-modules | 2 hr | `src/QxFx0/Core/*/` |

---

## CONCLUSION

QxFx0 demonstrates strong engineering fundamentals with genuine architectural bones. Most critical findings from previous audits are closed:

1. `ShadowDivergence`/`computeShadowLegitimacyPenalty` moved to `Types.ShadowDivergence` — Core→Bridge coupling eliminated.
2. `RoutingDecision` record type is used consistently — no massive tuples remain.
3. Morphology dictionary is clean — zero typo entries verified by `check_lexicon.sh` (score=10.00, 85 lemmas).
4. Bridge→Core reverse imports are fully removed — `check_architecture.sh` [4] enforces this at verification time.

However, **Iteration 7 discovered a live regression that breaks the release gate** (`styleFromLegitimacy` missing export), plus **three HIGH-severity exception-safety defects in the SQLite pool layer** that can cause silent state corruption (active transactions returned to pool), resource leaks (partial pool init), and connection leaks (incomplete exception catching). These are not theoretical: they are in the primary I/O path of every persisted session.

Additionally, **Datalog execution lacks a timeout**, creating a denial-of-service vector if Soufflé misbehaves; **supply-chain determinism is weak** (no freeze file, unpinned external tools); and **formal verification gives false confidence** by claiming Agda↔Haskell sync without clarifying that it is structural, not behavioral.

**Updated Verdict:**
- **System is architecturally sound** at the design level (layers, phases, guards, types).
- **Runtime I/O path has material exception-safety holes** that require immediate patching before any production deployment.
- **Release gate is currently RED** due to the `styleFromLegitimacy` regression.
- **Do not deploy to externally-facing endpoints** without adding TLS termination and fixing the API-key-over-plaintext exposure.

**Corrected Overall Maturity:** **7.5/10** (down from 9.4) — regression severity and pool exception-safety defects are blockers.

---

## Deep-dive Audit Update (2026-04-22)

Methodology: import-graph analysis, `-Wunused-*` compiler sweep, runtime safety review, test-to-module coverage mapping, spec↔src consistency verification.

### Historical Findings (Closed in follow-up pass)

All items in this section were remediated in the subsequent implementation wave and are retained as traceability history.

#### 🔴 MEDIUM — Race condition in `SessionLock.getOrCreateLock`
**Location:** `src/QxFx0/Core/SessionLock.hs:36-49`

Two threads can race on first lock creation: both read `Map.empty`, create separate `MVar ()`, then both `Map.insert`. The losing MVar is orphaned and never released.

**Fix:** Use `Map.insertWith (\_ old -> old)` to guarantee the first-inserted lock wins.

#### 🔴 MEDIUM — SQLite connection leak in `withPooledDB` overflow path
**Location:** `src/QxFx0/Bridge/SQLite.hs:89-99`

If `PRAGMA journal_mode=WAL` fails on an overflow connection, the connection handle leaks because `close` is outside the exception path.

**Fix:** Wrap PRAGMA + action + close in `bracketOnError` or `finally`.

#### 🟡 LOW — HTTP manager leak in `callLLM`
**Location:** `src/QxFx0/Bridge/LLM/Provider.hs:50`

`newManager defaultManagerSettings` created per call, never closed. Shared manager should live in `RuntimeContext`.

#### 🟡 LOW — DB Pool O(n) append
**Location:** `src/QxFx0/Bridge/SQLite.hs:102`

`dbs ++ [db]` is O(n). Replace with LIFO `db : dbs` or `Seq`.

#### 🟡 LOW — `agdaTypeCheck` without timeout
**Location:** `src/QxFx0/Bridge/AgdaR5.hs:32-34`

`readProcessWithExitCode "agda" ...` has no timeout. Wrap with `System.Timeout.timeout`.

#### 🟡 LOW — Fragile Datalog rules resolution
**Location:** `src/QxFx0/Bridge/Datalog.hs:182`

`specDatalogDir = takeDirectory (rpAgdaSpec paths) </> "datalog"` couples Datalog path to Agda spec location. Use `rpDatalogRules` directly.

#### 🟢 COSMETIC — `renderLogicalBond` dead code
**Location:** `src/QxFx0/Types/Observability.hs:73-76`

Defined but not exported or used anywhere.

#### 🟢 COSMETIC — `cabal.project.local` not in `.gitignore`
Contains hardcoded GHC path. Add `cabal.project.local` to `.gitignore`.

### Test Coverage Correction

The deep-dive initially reported "0 tests" for several lower-level pure modules. This was overstated. Correct coverage status:

| Module | Dedicated Tests | Indirect Coverage | True Gap |
|---|---|---|---|
| `Core/DreamDynamics` | 1 (`testDreamBiasAttractorRejectsLowQualityEvidence`) | 1 (`testMeaningGraphDreamBiasCanPromoteBorderlineStrategy`) | `runDreamCycle`, `runDreamCatchup` lack direct unit tests |
| `Core/IdentitySignal` | 0 | Used in render tests (`testRenderStyleFromDecision*`) | `buildIdentitySignalSimple` not directly tested |
| `Core/IdentityGuard` | 0 | Guard layer tested via `testSafetyChecks` | No dedicated `IdentityGuard` unit tests |
| `Core/Consciousness.Kernel` | 0 | `interpretOutput` covered by `testConsciousnessInterpretationTracksHighAffinitySkill` | Kernel internals (`kernelPulse`, `thinkingVectorUpdate`) untested |
| `Core/MeaningGraph` | 3 + 3 property tests | Extensive via `CoreBehavior` | Deep vector math paths adequately covered |
| `Core/R5Dynamics` | 19 | Full coverage in `CoreBehavior` | None significant |

**Revised assessment:** Coverage is *thin* in some lower-level pure modules, not zero. The true gap is absence of dedicated unit tests for `runDreamCycle`/`runDreamCatchup`, `IdentitySignal` construction, and `Consciousness.Kernel` internals.

### Updated Scores

| Dimension | Previous | Deep-dive | Change |
|---|---|---|---|
| Architecture Readiness | 9.0 | 9.0 | → |
| Technical Debt | 8.5 | 8.5 | → |
| Clockwork Precision | — | 8.8 | New: 10 gates pass, but race + leak + thin pure-module coverage |
| **Overall** | **9.0** | **8.9** | Race and leak are real, though low-probability |

### Remediation Priority

**P1 (~1 hour):**
1. Fix `SessionLock` race (`Map.insertWith`)
2. Fix SQLite overflow leak (`bracketOnError`)

**P2 (~3 hours):**
3. Add timeout to `AgdaR5.agdaTypeCheck`
4. Add `cabal.project.local` to `.gitignore`
5. Add unit tests for `runDreamCycle`/`runDreamCatchup`
6. Add unit tests for `IdentitySignal` construction

**P3 (~2 hours):**
7. Shared HTTP manager in `RuntimeContext`
8. LIFO DB Pool return
9. Remove `renderLogicalBond` dead code
10. Use `rpDatalogRules` for datalog dir

---

## Iteration 6: Post-Inline-Extraction Deep-dive (2026-04-23)

Methodology: Full gate suite (verify.sh, release-smoke, architecture, lexicon, generated artifacts) + global `[0-9]+\.[0-9]+` sweep across Core/Runtime/Bridge/app/test + Haddock coverage check + SQL literal audit.

### Closed Since Iteration 5

| Item | Location | Fix | Status |
|---|---|---|---|
| SQL literal inline | `Runtime/Session.hs:142` | Parameterized via `bindDouble` with `Thresholds.Constants` | ✅ |
| 30 inline constants in Core | `PrincipledCore`, `Consciousness.Kernel`, `BackgroundProcess`, `Dream`, `R5Dynamics`, `IdentitySignal`, `Cascade`, `MeaningGraph`, `Narrative`, `Tension`, `ClaimBuilder` | All extracted to `Types.Thresholds.Constants` | ✅ |
| Haddock headers | `Intuition.hs`, `PrincipledCore.hs`, `Consciousness.Kernel.hs` | Module headers + function docstrings added | ✅ |

### Global Inline-Constant Sweep Results

Sweep command: `grep -rn '[0-9]+\.[0-9]+' src/QxFx0/Core/ src/QxFx0/Runtime/ src/QxFx0/Bridge/ app/ test/` with exclusions for `Thresholds/Constants`, `import`, `0.0`, `1.0`, `100.0`, `maxBound`, `1e-`, `printf`, `show`, math functions, `Paths_qxfx0`, generated artifacts.

**Result: zero findings.** All business-logic numeric literals in Core/Runtime/Bridge/app/test are centralized in `Types.Thresholds.Constants`.

### Haddock Coverage Check

| Layer | Total Modules | With Header | Without | Coverage |
|---|---|---|---|---|
| **All src/** | 187 | 48 | 139 | 25.7% |
| **Domain (Core/Runtime/Semantic/Policy/Types/Render)** | ~95 | ~75 | ~20 | 79% |
| **Bridge/CLI/Lexicon.Generated/Resources** | ~92 | ~13 | ~79 | 14% |

**Note:** Bridge layer modules are I/O adapters (SQLite, LLM, Nix, HTTP, Agda, Datalog) where Haddock is less critical for domain understanding. The ~20 domain-layer modules without headers are primarily internal sub-modules (`Guard/Checks`, `PipelineIO/Internal`, `Consciousness/Types`, `Legitimacy/Scoring`, etc.). **P3**.

### Updated Scores

| Dimension | Iteration 5 | Iteration 6 | Change |
|---|---|---|---|
| Architecture Readiness | 9.3 | **9.5** | ↑ +0.2 |
| Technical Debt | 9.0 | **9.3** | ↑ +0.3 |
| Clockwork Precision | 9.3 | **9.5** | ↑ +0.2 |
| **Overall** | **9.2** | **9.4** | ↑ +0.2 |

### Remaining Debt (P3 only)

1. **~20 domain-layer modules without Haddock module headers** — onboarding friction, not architectural.
2. **EmbeddedSQL.hs seed data literals** — generated from `spec/sql`, not business-logic thresholds.

**No MEDIUM, LOW, or critical debt remains.**

## APPENDIX: Verification Commands

```bash
# Build and test
cabal build all
cabal test qxfx0-test
cabal check

# Architecture boundary checks
bash scripts/check_architecture.sh

# Agda sync verification
python3 scripts/verify_agda_sync.py

# Release smoke test
bash scripts/release-smoke.sh

# Strict release contour (CI mandatory)
QXFX0_REQUIRE_AGDA=1 bash scripts/release-smoke.sh
```

**Status as of Iteration 7 (2026-04-23):**
- `cabal build all` ❌ FAIL (test compilation error)
- `cabal test qxfx0-test` ❌ FAIL (same)
- `bash scripts/verify.sh` ❌ FAIL (build prerequisite fails)
- `bash scripts/release-smoke.sh` ❌ REJECT (gates [1] and [2])
- `bash scripts/check_architecture.sh` — unchecked (build fails first)
- `bash scripts/check_lexicon.sh` — unchecked (build fails first)

---

**End of Report**
