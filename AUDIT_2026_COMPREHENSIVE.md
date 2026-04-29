# QxFx0 — Comprehensive Hardened Audit Report

**Audit Date:** 2026-04-24
**Auditor:** Principal-level automated code analysis
**Scope:** Replay/crash/capacity/dependency/gate/data/spec/interface/adversarial (A–I)
**Methodology:** repo-grounded, findings-first, practically verified where possible
**Codebase:** 207 Haskell src modules, 462 unit tests, 6 QuickCheck properties, ~15,000 LOC src

---

## 1. Executive Summary

### 5 Strongest Conclusions

1. **Architecture is genuinely decomposed.** Prepare/Route/Render/Finalize phases are real, types are strong (14 families × 5 forces × 3 layers × 4 clauses), and `check_architecture.sh` enforces layer boundaries. This is not a monolith pretending to be modular.

2. **Transaction safety is mostly correct, not merely nominal.** `withImmediateTransaction` uses `mask` + `onException` rollback + COMMIT failure recovery. `testSaveStateWithProjectionFailureRollsBackTransaction` and `testBootstrapSessionMarksRecoveredCorruption` prove recovery paths are exercised.

3. **External dependency timeouts exist and are tested.** Nix (5s), Agda (configurable, default 30s), Datalog/Soufflé (configurable, default 30s), LLM (configurable), embedding health (2s), embedding fetch (5s). `testDatalogShadowTimesOutWithControlledDiagnostic` and `testAgdaTypeCheckTimesOut` verify timeout behavior.

4. **All 11 gates pass (green), but several gates are weaker than they look.** `check_architecture.sh` is regex-based and can be bypassed. `verify_agda_sync.py` checks structural names, not behavioral equivalence. `release-smoke.sh` tests a single happy-path turn, not stress or chaos.

5. **Replay determinism is broken by temporal leakage.** `MeaningGraph` edges persist `UTCTime` (`meLastRewiredAt`). Two identical turns at different times produce different persisted blobs. The `testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty` only covers 3 inputs with 20 QuickCheck cases — far too narrow to claim replayability.

### What is Really Solid

- Layer boundary enforcement via `check_architecture.sh` (10 sub-checks)
- SQLite persistence with WAL, explicit transactions, and rollback on failure
- Shadow divergence snapshot IDs are deterministic (FNV-1a hash of canonical inputs)
- Input sanitization in HTTP sidecar (length limit, control-char filter, session regex)
- Graceful degradation paths for missing Soufflé, Nix, Agda, LLM backend

### Where the Main Residual Risk Lives

- **Unbounded growth in `MeaningGraph` edges** — every turn adds edges; no cap; over long sessions this becomes an operational time-bomb.
- **SessionLock orphan leak** — after 4096 unique sessions, new sessions lose per-session serialization and fall back to a single global lock.
- **Formal-to-runtime gap** — Agda proves types exist, but does not prove the Haskell runtime implements the same semantics. The "verified" badge is structural, not behavioral.
- **No stress/soak/chaos tests** — the system has never been exercised under sustained load, memory pressure, or adversarial input streams.

---

## 2. Findings First

### Summary Table

| ID | Severity | Category | Location | One-line verdict |
|---|---|---|---|---|
| A1 | MEDIUM | Replay / Determinism | `src/QxFx0/Types/Observability.hs:182` | `MeaningEdge.meLastRewiredAt` leaks wall-clock time into persisted state, breaking bitwise replay |
| A2 | MEDIUM | Replay / Determinism | `src/QxFx0/Types/State/System.hs:138-173` | `FromJSON` uses `.!=` silent defaults; corrupt/missing fields recover as defaults, not as failures — replay of corrupted state is lossy |
| A3 | LOW | Replay / Determinism | `test/Test/Suite/RuntimeInfrastructure.hs:765-789` | Replay determinism property covers only 3 inputs with 20 cases — insufficient to claim determinism |
| B1 | MEDIUM | Crash / Consistency | `src/QxFx0/Bridge/SQLite/Pool.hs:104-107` | Pooled path `withConnections` returns connection without explicit ROLLBACK on exception; relies on SQLite implicit behavior (test passes, but not guaranteed across SQLite versions) |
| B2 | MEDIUM | Crash / Consistency | `test/Test/Suite/CoreBehavior.hs:414-445` | Two concurrent-turn tests exist, but no test for `ThreadKilled` during SQLite transaction, Datalog execution, or state commit |
| C1 | HIGH | Capacity / Leak | `src/QxFx0/Types/Observability.hs:188-189` | `MeaningGraph` edges grow unbounded per session; no truncation or compaction |
| C2 | MEDIUM | Capacity / Leak | `src/QxFx0/Core/SessionLock.hs:31-57` | `SessionLock` never garbage-collects orphaned locks; after 4096 sessions all new sessions share one overflow lock |
| C3 | MEDIUM | Capacity / Leak | — | No soak, stress, heap, or longevity tests in any suite |
| D1 | LOW | Dependency | `src/QxFx0/Bridge/NixGuard.hs:71-72` | `runNixEval` uses `timeout` CLI wrapper; if `timeout` binary is missing, `nix-instantiate` runs without timeout |
| E1 | MEDIUM | Gate Sufficiency | `scripts/check_architecture.sh:131-136` | `SomeException` check is regex-based, not AST-based; can be bypassed by qualified/aliased imports |
| E2 | MEDIUM | Gate Sufficiency | `scripts/verify_agda_sync.py` | Verifies constructor names and function mappings only — no behavioral equivalence |
| E3 | LOW | Gate Sufficiency | — | No gate checks for `cabal.project.freeze` or external tool versions (Agda, Soufflé, Nix, Python3) |
| F1 | MEDIUM | Data Lifecycle | `migrations/001_initial_schema.sql` | Only one migration exists; no forward/rollback migration path; schema version mismatch hard-fails with no upgrade path |
| G1 | MEDIUM | Formal / Spec | `spec/R5Core.agda`, `spec/Sovereignty.agda` | Agda specs define constructors and proofs, but no extraction into Haskell runtime; `verify_agda_sync.py` is structural name-check only |
| H1 | MEDIUM | Interface / Security | `scripts/http_runtime.py:826-836` | API key transmitted in plaintext HTTP; documented but not remediated |
| I1 | MEDIUM | Adversarial | — | No fuzz tests for HTTP sidecar, worker protocol, SQLite payloads, or LLM responses |

---

## 3. Detailed Findings

### A1: `MeaningEdge.meLastRewiredAt` Leaks Wall-Clock Time into Persisted State (MEDIUM)

- **Location:** `src/QxFx0/Types/Observability.hs:182` (`meLastRewiredAt :: !(Maybe UTCTime)`)
- **Evidence:** `MeaningEdge` is part of `MeaningGraph`, which is part of `SystemState`, which is persisted as a JSON blob in `dialogue_state`. `UTCTime` is wall-clock dependent.
- **Why it matters:** Two sessions processing the exact same input sequence will produce different persisted blobs if turns occur at different times. Bitwise replay (diffing persisted blobs) is impossible. Deterministic regression testing across time is broken.
- **Minimal correct fix:** Replace `UTCTime` with `TurnCount`-relative index or monotonic sequence number. If absolute time is needed for analytics, store it in a separate non-replay observability table.
- **Confidence:** HIGH — code inspection + JSON encoding path confirmed.
- **Status:** OPEN

### A2: `FromJSON` Silent Defaults Make Corrupt Replay Lossy (MEDIUM)

- **Location:** `src/QxFx0/Types/State/System.hs:138-173` (`.!=` defaults for `lastGuardReport`, `dreamState`, `intuitionState`, `semanticAnchor`, `lastTurnDecision`)
- **Evidence:** `.:? "lastGuardReport" .!= Nothing`, `.:? "dreamState" .!= emptyDreamState zeroVec`, etc.
- **Why it matters:** If a persisted JSON blob is truncated or field is missing, `loadState` silently recovers with defaults. The system continues as if nothing happened, but the replay trace is inaccurate. A truly strict replay system should fail on missing decision-relevant fields.
- **Minimal correct fix:** For decision-critical fields (family, force, decision, shadow status), use `.:` (strict) instead of `.:?` + `.!=`. For optional fields, keep `.:?` but log a warning.
- **Confidence:** HIGH — code inspection.
- **Status:** OPEN

### A3: Replay Determinism Property Coverage is Too Narrow (LOW)

- **Location:** `test/Test/Suite/RuntimeInfrastructure.hs:765-789`
- **Evidence:** `forAll (elements replayInputs)` where `replayInputs = ["Что такое свобода?", "Мне нужен контакт.", "Где граница между смыслом и пустотой?"]` with `quickCheckTest 20`.
- **Why it matters:** Three inputs across 20 QuickCheck cases cannot claim determinism for a system with 14 families, 3 layers, 4 forces, emotion detection, atom extraction, and shadow divergence. The property only checks that `TurnReplayTrace` JSON is identical after normalizing session/request IDs — it does not check `SystemState` blob equality or `MeaningGraph` equality.
- **Minimal correct fix:** Expand to 100+ inputs covering all families, add `SystemState` blob equality check, and test across multiple turns (turn N depends on turn N-1 state).
- **Confidence:** HIGH — test code read.
- **Status:** OPEN

### B1: Pooled DB Path Lacks Explicit ROLLBACK on Exception (MEDIUM)

- **Location:** `src/QxFx0/Bridge/SQLite/Pool.hs:104-107`
- **Evidence:**
  ```haskell
  withConnections restore (db : dbs) =
    finally
      (restore (action db))
      (putMVar (poolMVar pool) (db : dbs))
  ```
- **Why it matters:** If `action db` begins a transaction and then throws, the connection is returned to the pool with an active transaction. The next consumer may get `SQLITE_BUSY` or nested-transaction errors. The existing test `testWithPooledDBSanitizesDirtyTransactionBeforeReuse` passes, but it relies on SQLite implicitly cleaning up the transaction between `takeMVar` and reuse — this is not guaranteed by SQLite semantics and may vary by version or build flags.
- **Minimal correct fix:** Add `safeClose db` or explicit `NSQL.execSql db "ROLLBACK;"` in the `finally` handler before `putMVar`, or document the assumption.
- **Confidence:** MEDIUM — code inspection + test passes, but SQLite behavior not contractually guaranteed.
- **Status:** OPEN

### B2: No Tests for Async Exception During Commit (MEDIUM)

- **Location:** `test/Test/Suite/CoreBehavior.hs:414-445` (concurrent turn tests), `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs` (commit path)
- **Evidence:** Two tests verify max concurrent turns = 1 with session lock. No test for `ThreadKilled` arriving during `withImmediateTransaction` COMMIT, during `saveStateWithProjection`, or during Soufflé execution.
- **Why it matters:** `mask` in `withImmediateTransaction` protects the critical section, but `COMMIT` itself is not masked. A `ThreadKilled` between `action` completion and `COMMIT` could leave the database in a state where `dialogue_state` is written but `turn_quality` is not — observable inconsistency.
- **Minimal correct fix:** Add a test that injects `ThreadKilled` at a specific point in the commit pipeline and verifies atomicity.
- **Confidence:** MEDIUM — code inspection; no practical test attempted due to injection complexity.
- **Status:** OPEN

### C1: `MeaningGraph` Edges Grow Unbounded (HIGH)

- **Location:** `src/QxFx0/Types/Observability.hs:188-189` (`mgEdges :: ![MeaningEdge]`)
- **Evidence:** `recordTransition` in `src/QxFx0/Core/MeaningGraph.hs` appends edges on every turn. No truncation, compaction, or cap.
- **Why it matters:** Every turn adds at least one `MeaningEdge` (often more). For a 24/7 service with 1000 turns/day, that's 365k edges/year per session. Persisted JSON blob size grows linearly. Eventually `saveState` and `loadState` become slow, and memory pressure increases.
- **Minimal correct fix:** Add a bounded ring buffer (e.g., keep last 1000 edges) or periodic compaction/summarization. `updateHistoryStrict` already caps at 50 — `MeaningGraph` should have a similar bound.
- **Confidence:** HIGH — code inspection.
- **Status:** OPEN

### C2: `SessionLock` Orphan Leak After 4096 Sessions (MEDIUM)

- **Location:** `src/QxFx0/Core/SessionLock.hs:31-57`
- **Evidence:** `maxTrackedLocks = 4096`. When `Map.size locks >= maxTrackedLocks`, new sessions get `slmOverflowLock` (a single global MVar). Orphaned locks (sessions that are never used again) are never removed from the Map.
- **Why it matters:** After 4096 unique session IDs, every new session shares one lock. Per-session serialization is lost. Two different sessions cannot run turns concurrently, even though they have no shared state. This is a correctness-to-performance degradation that may not be noticed until production scale.
- **Minimal correct fix:** Add TTL-based GC for old locks (e.g., purge locks unused for >1 hour), or switch to a bounded LRU cache.
- **Confidence:** HIGH — code inspection.
- **Status:** OPEN

### C3: No Soak / Stress / Heap Tests (MEDIUM)

- **Location:** —
- **Evidence:** `grep -rn "soak\|stress\|chaos\|fuzz\|heap\|benchmark\|performance" test/ scripts/ README.md` returns zero matches.
- **Why it matters:** The system may be correct for 10 turns and broken for 10,000. Memory leaks (thunk accumulation in `Seq`, unbounded `MeaningGraph`, orphaned `SessionLock` entries) only manifest under sustained load. Without soak tests, these risks are theoretical until they explode in production.
- **Minimal correct fix:** Add a soak test that runs 1000 turns in a loop and asserts: (1) heap residency stable, (2) `MeaningGraph` edge count bounded, (3) `SessionLock` map size bounded, (4) turn latency does not drift.
- **Confidence:** HIGH — search confirmed.
- **Status:** OPEN

### D1: `runNixEval` Falls Back to No Timeout if `timeout` CLI Missing (LOW)

- **Location:** `src/QxFx0/Bridge/NixGuard.hs:71-72`
- **Evidence:** `readProcessWithExitCode "timeout" [show timeoutSec, "nix-instantiate", ...] ""`. If `timeout` is not in PATH, the process spawn fails with `IOException` which is caught, but the fallback is to report an error — not to run `nix-instantiate` without timeout. Actually, re-reading: `catchIO` wraps the entire `readProcessWithExitCode "timeout" ...`. If `timeout` is missing, `catchIO` catches the `IOException` and returns `Left "nix exception: ..."`. So no silent no-timeout fallback. Wait, that's actually correct — if `timeout` is missing, it reports error, not runs without timeout.
- **Correction:** This finding is **NOT CONFIRMED**. The `catchIO` wrapper ensures that missing `timeout` binary produces a failure, not a silent no-timeout execution.
- **Status:** NOT CONFIRMED

### E1: Architecture Gate is Regex-Based, Bypassable (MEDIUM)

- **Location:** `scripts/check_architecture.sh:131-136`
- **Evidence:** `rg -n 'SomeException' "$file" | rg -v ':[0-9]+:\s*--'`. A developer could define `import qualified Control.Exception as E` and use `E.SomeException`, or re-export it under a different name in one module, and the consuming file would never contain the literal string `SomeException`.
- **Why it matters:** The gate gives a strong green checkmark, but the guarantee is weaker than it appears. The project has no history of such bypasses, so this is latent risk, not active violation.
- **Minimal correct fix:** Replace regex with a GHC warning or an AST-based tool (e.g., `hlint` custom rule, or compile-time check via Template Haskell).
- **Confidence:** MEDIUM — no active bypass found, but gate design is fundamentally weak.
- **Status:** OPEN

### E2: Agda Sync is Structural, Not Behavioral (MEDIUM)

- **Location:** `scripts/verify_agda_sync.py`
- **Evidence:** The script checks that `forceForFamily`, `clauseFormForIF`, `layerForFamily`, `warrantedForFamily` have matching names and return values in the TSV snapshot. It does not check function bodies in Agda against Haskell runtime behavior.
- **Why it matters:** The project claims "Agda↔Haskell sync verified at build time" (see `COMPREHENSIVE_AUDIT_2026.md`). This gives false confidence. The formal layer proves types exist, but not that `routeFamily` in Haskell implements the same routing logic as the Agda spec.
- **Minimal correct fix:** Update all docs to explicitly state: "Agda sync is structural (constructor + function name coverage), not behavioral equivalence. Behavioral correctness is verified by Haskell test suite."
- **Confidence:** HIGH — script source read.
- **Status:** OPEN

### E3: No Freeze File or Tool Version Gates (LOW)

- **Location:** repository root, `scripts/verify.sh`
- **Evidence:** No `cabal.project.freeze`. `verify.sh` does not run `agda --version`, `souffle --version`, `nix --version`, `python3 --version`.
- **Why it matters:** A future CI run may pass with Agda 2.6.4 but fail or behave differently with Agda 2.7.0. Without a freeze file, Hackage metadata drift can change build behavior.
- **Minimal correct fix:** `cabal freeze` + commit freeze file. Add minimum version assertions to `verify.sh`.
- **Confidence:** HIGH — file search confirmed.
- **Status:** OPEN

### F1: Single Migration, No Upgrade Path (MEDIUM)

- **Location:** `migrations/001_initial_schema.sql`, `src/QxFx0/Bridge/SQLite/Bootstrap.hs:32-37`
- **Evidence:** `currentSchemaVersion = 1`. `validateSchemaVersion` hard-fails if version ≠ 1. No migration framework for v1 → v2.
- **Why it matters:** When the schema inevitably changes (e.g., adding a new observability column), existing user databases will hard-fail on bootstrap. Users will have to manually migrate or lose data.
- **Minimal correct fix:** Implement a simple sequential migration runner (check `schema_version`, apply `002_*.sql`, `003_*.sql`, etc.) with idempotent ALTER TABLE.
- **Confidence:** HIGH — code inspection.
- **Status:** OPEN

### G1: Formal Spec Has No Runtime Behavioral Extraction (MEDIUM)

- **Location:** `spec/R5Core.agda`, `spec/Sovereignty.agda`
- **Evidence:** Agda defines `CanonicalMoveFamily`, `IllocutionaryForce`, proofs about sovereignty. `COMPILE GHC` pragmas map constructors. No extraction of decision functions (`routeFamily`, `buildRmpForce`, etc.) from Agda into Haskell.
- **Why it matters:** The formal layer is a parallel specification, not a source of truth for the runtime. If Agda proves a routing invariant, the Haskell runtime does not automatically satisfy it. This is a common and acceptable pattern, but it must be documented explicitly to avoid false confidence.
- **Minimal correct fix:** Document the formal/runtime relationship as "parallel specification with manual sync, not extraction-based verification."
- **Confidence:** HIGH — Agda source read.
- **Status:** OPEN

### H1: HTTP Sidecar Serves API Key in Plaintext (MEDIUM)

- **Location:** `scripts/http_runtime.py:826-836`, `README.md:100`
- **Evidence:** `hmac.compare_digest(key, API_KEY)` compares plaintext header value. Server is `ThreadingHTTPServer` (HTTP, not HTTPS). README documents: "API key transmitted in plaintext HTTP... TLS termination must be handled by reverse proxy."
- **Why it matters:** If the sidecar is accidentally exposed beyond loopback (misconfigured firewall, container networking), the API key is sniffable. The safety depends on operational configuration, not on the code.
- **Minimal correct fix:** Add runtime validation that host is loopback when no reverse proxy is detected; or bind to `127.0.0.1` by default and require explicit env var to override.
- **Confidence:** HIGH — code + docs read.
- **Status:** OPEN (documented, not remediated)

### I1: No Fuzz Tests for Any Boundary (MEDIUM)

- **Location:** —
- **Evidence:** Zero fuzz/stress/adversarial tests across all 4 test suites (462 tests).
- **Why it matters:** Input sanitization (`sanitize_input`, `validate_session`) is present but not adversarially tested. Malformed JSON arrays, oversized UTF-8 sequences, SQLite injection attempts, and broken LLM responses are not exercised.
- **Minimal correct fix:** Add a small fuzz suite: (a) random session IDs, (b) random worker commands, (c) random SQLite text payloads, (d) malformed LLM JSON responses.
- **Confidence:** HIGH — search confirmed.
- **Status:** OPEN

---

## 4. Replay & Crash Verdict

### Is replayability real or nominal?

**NOMINAL.**

- `TurnReplayTrace` is deterministic for the same input (verified by property test), but it only captures 17 fields of the full decision pipeline.
- `SystemState` persistence includes `MeaningGraph` with `UTCTime` — two identical inputs produce different blobs.
- `FromJSON` silent defaults mean a corrupt blob replays as a "healthy" default-filled state, not as a failure.
- There is no end-to-end test that takes a persisted blob from turn N and produces the exact same output at turn N+1.

### Is crash-consistency real or under-proven?

**MOSTLY REAL, WITH BLIND SPOTS.**

- SQLite `BEGIN IMMEDIATE` + `onException ROLLBACK` + COMMIT failure recovery is correct and tested.
- `saveStateWithProjection` rollback on failure is tested.
- `testBootstrapSessionMarksRecoveredCorruption` proves recovery from corrupt JSON.
- **Blind spot:** No test for `ThreadKilled` during COMMIT or during Soufflé execution. The `mask` in `withImmediateTransaction` protects the action, but not the COMMIT itself.
- **Blind spot:** The pooled DB path lacks explicit ROLLBACK in cleanup; the passing test may rely on SQLite implementation details.

---

## 5. Gate Verdict

### Which gates are genuinely strong?

1. **`verify.sh` [7/10] Embedded SQL sync** — `sync_embedded_sql.py --check` is a real diff gate.
2. **`verify.sh` [8/10] Schema consistency** — `check_schema_consistency.py` compares migrations to canonical schema.
3. **`verify.sh` [3/10] Agda typecheck** — real compilation check, but no behavioral verification.
4. **`release-smoke.sh` [9/10] HTTP sidecar turn** — actually boots a worker, runs a turn, checks response.
5. **`check_architecture.sh` [4] Bridge→Core import ban** — actively caught and closed real violations.

### Which gates give a false sense of control?

1. **`check_architecture.sh` [5] `SomeException` regex** — text search, not AST. Bypassable.
2. **`verify_agda_sync.py`** — structural name-check only. A renamed function with wrong semantics would pass.
3. **`release-smoke.sh`** — one happy-path turn, one rate-limit test. No chaos, no stress, no soak.
4. **All gates** — no heap/leak check, no bounded-growth validation, no concurrent load test.

### What is critically missing from CI?

1. **Soak test:** 1000 turns, assert stable heap and bounded latency.
2. **Property-based state roundtrip:** `saveState → loadState ≡ id` for all reachable `SystemState` values.
3. **Concurrent load test:** 10 threads, 100 turns each, assert no `SQLITE_BUSY`, no deadlocks.
4. **`cabal.project.freeze` check:** fail if freeze file is stale or missing.
5. **External tool version gate:** fail if Agda/Soufflé/Nix versions drift from tested range.

---

## 6. Scorecard

| Dimension | Score | Justification |
|---|---|---|
| **Replay / Determinism** | **5/10** | Shadow snapshots deterministic, but `MeaningGraph` leaks time, `FromJSON` is lossy, replay tests are tiny |
| **Crash Consistency** | **7/10** | Transaction rollback tested, recovery from corrupt state tested, but no async-exception-during-commit tests, pooled path ROLLBACK implicit |
| **Capacity / Operational Resilience** | **5/10** | `MeaningGraph` unbounded, `SessionLock` orphan leak, no soak/stress/heap tests, most other structures bounded |
| **Formal-to-Runtime Integrity** | **4/10** | Structural Agda sync verified, but no behavioral extraction or proof-to-runtime bridge |
| **Gate Sufficiency** | **6/10** | 11 gates pass, but regex-based checks, no stress/chaos, no freeze/tool-version gates |
| **Interface / Protocol Robustness** | **7/10** | Good sanitization and docs, but plaintext API key, `lenientDecode` may corrupt worker output |
| **Technical Debt** | **6/10** | Inline constants fixed, schema sync enforced, but unbounded growth, orphaned locks, narrow tests remain |
| **Cohesion "как механические часы"** | **6/10** | Phases decomposed, types strong, but concurrent effects lack cancellation, observability timing nondeterministic, temporal leakage in state |
| **Overall** | **5.5/10** | Architecturally sound, operationally under-verified. Will work correctly for demo-scale use, but has latent time-bombs for production load. |

---

## 7. Status Matrix

| Status | Count | IDs |
|---|---|---|
| **OPEN** | 13 | A1, A2, A3, B1, B2, C1, C2, C3, E1, E2, E3, F1, G1, H1, I1 |
| **FIXED** | 0 | — |
| **PARTIAL** | 0 | — |
| **NOT CONFIRMED** | 1 | D1 |
| **REGRESSED** | 0 | — |

(Note: previous audit findings about `styleFromLegitimacy` and pool exception safety were either fixed or re-evaluated as less severe based on passing tests.)

---

## 8. Top Remediation Plan

### P0 — Before any production deployment

| # | Action | Expected Effect | Effort |
|---|---|---|---|
| 1 | Cap `MeaningGraph` edges (ring buffer or compaction) | Prevents unbounded memory growth and slow save/load | 2–4h |
| 2 | Add explicit `ROLLBACK` in `withConnections` pooled path cleanup | Removes dependency on SQLite implicit transaction cleanup | 30m |
| 3 | Add `SessionLock` TTL-based GC or bounded LRU | Prevents 4096-session cliff and global lock fallback | 2–4h |
| 4 | Document Agda sync as structural-only in `AGENTS.md` and `README.md` | Prevents false confidence from formal verification badge | 30m |

### P1 — Before scaling beyond 100 daily sessions

| # | Action | Expected Effect | Effort |
|---|---|---|---|
| 5 | Add soak test: 1000 turns, assert heap/latency/edge-count stability | Finds leaks and drift before production scale | 4–8h |
| 6 | Add concurrent load test: 10 threads × 100 turns | Validates SQLite pool and session lock under contention | 4–8h |
| 7 | Replace `MeaningEdge.meLastRewiredAt` with turn-relative index | Restores bitwise replay determinism | 2h |
| 8 | Add `cabal.project.freeze` + version gate in `verify.sh` | Reproducible builds, deterministic CI | 1h |
| 9 | Add sequential migration runner (`002_*.sql`, etc.) | Enables safe schema evolution | 4h |

### P2 — Background maintenance

| # | Action | Expected Effect | Effort |
|---|---|---|---|
| 10 | Expand `TurnReplayTrace` determinism property to 100+ inputs + multi-turn | Stronger replay guarantee | 4h |
| 11 | Add fuzz tests for HTTP sidecar, worker protocol, SQLite payloads | Finds adversarial edge cases | 4–8h |
| 12 | Strengthen `check_architecture.sh` with AST-based check or GHC warning | Removes regex bypass risk | 2–4h |
| 13 | Add `ThreadKilled` injection test during commit pipeline | Verifies async exception safety | 4–8h |

---

## 9. Verification Gaps

### Scenarios not covered by tests

1. **Long-running session soak:** No test runs >100 turns in one session.
2. **Memory pressure:** No test measures heap residency before/after turns.
3. **Concurrent session contention:** Only 2 tests verify max concurrent turns = 1; no test for 10+ threads.
4. **Async exception during COMMIT:** `ThreadKilled` or `UserInterrupt` during `saveStateWithProjection`.
5. **Corrupt `MeaningGraph` blob:** What happens when `meLastRewiredAt` is unparsable?
6. **LLM returning garbage:** `extractResponseField` returns `""` on missing path, but what about unexpected JSON shape?
7. **SQLite file corruption:** No test for `sqlite3_open` on a corrupt file.

### Failure modes not covered by gates

1. **Unbounded `MeaningGraph` growth** — no gate measures edge count.
2. **`SessionLock` orphan accumulation** — no gate checks map size.
3. **Missing `cabal.project.freeze`** — no gate enforces lock file.
4. **External tool version drift** — no gate checks versions.
5. **Heap leak** — no gate measures residency.

### Invariants claimed but not proven

1. "Deterministic replay" — claimed by `testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty`, but `MeaningGraph` contains wall-clock time.
2. "Agda↔Haskell sync" — claimed by `verify_agda_sync.py`, but only structural names are checked.
3. "Crash consistency" — mostly proven for `saveState`, but not for async exceptions during commit.

---

## 10. Final Judgement

> **Архитектурно крепкая, но эксплуатационно недодоказанная.**

QxFx0 has genuine architectural bones: phase-separated pipeline, strong typing, explicit transaction rollback, and dependency degradation with timeouts. These are not cosmetic — they are real structural investments that pay off in maintainability and safety.

However, the system has **not yet been operationally stress-tested**. The most dangerous findings are not crash bugs (those are mostly handled), but **slow-burn capacity leaks**: unbounded `MeaningGraph` edges, orphaned `SessionLock` entries, and a replay mechanism that silently loses temporal fidelity. These will not show up in a 10-turn demo or a 131-second smoke test. They will show up on day 100 of a production deployment.

**Verdict:** Safe for experimental/research use with bounded session counts (<1000 turns/session). Not recommended for 24/7 production without addressing P0 items (MeaningGraph cap, SessionLock GC, pooled path ROLLBACK).
