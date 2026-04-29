# QxFx0 Technical Debt Closed — 2026 Remediation

Date: 2026-04-22
Scope: 5-wave remediation covering exception policy, resource unification, test coverage, CI gates, and audit closeout

Note: this is a remediation ledger. Current open items and current scores live in `TECH_DEBT.md` and `COMPREHENSIVE_AUDIT_2026.md`.

## Wave 1: Smoke Cleanup + CLI Hardening + App Gate

| Item | Resolution |
|---|---|
| Datalog probe writes to CWD in release-smoke.sh | `mktemp -d` + `-D "$SMOKE_TMPDIR"` + cleanup |
| `last` in CLI.hs | Pattern matching `(c:_) -> Just c` |
| Raw `SomeException` / `AsyncException` in CLI.hs | `ExceptionPolicy.tryAsync` |
| 32 over-broad `catch SomeException` across 8 files | `ExceptionPolicy` module (`tryIO`/`catchIO`/`tryAsync`); all Bridge, Semantic, Core, App modules migrated |
| Architecture check doesn't scan app/ | Checks 5 (SomeException), 6 (partial read), 7 (bare partials) extended to app/ |
| `ExceptionPolicy` not in cabal | Added to exposed-modules |

**Files changed:** CLI.hs, release-smoke.sh, check_architecture.sh, ExceptionPolicy.hs (new), Bridge/Datalog.hs, Bridge/SQLite.hs, Bridge/AgdaR5.hs, Bridge/LLM/Provider.hs, Bridge/NixGuard.hs, Bridge/StatePersistence.hs, Semantic/Embedding.hs, Core/Runtime.hs, qxfx0.cabal

## Wave 2: Resource Resolver Unification

| Item | Resolution |
|---|---|
| Duplicated resource discovery (Resources.hs + Bridge/Datalog.hs) | Datalog imports canonical `resolveResourcePaths`/`rpDatalogRules` from `QxFx0.Resources` |
| Bridge→Core path resolution coupling | `Bridge.SQLite` and `Bridge.AgdaR5` now import `QxFx0.Resources` (top-level), not `Core.Resources` |

**Functions removed from Datalog:** `resolveDatalogRulesPath`, `findResourceRoot`, `discoverResourceRoot`, `pickFirstRoot`, `isResourceRoot`, `ancestors`

**Files changed:** Bridge/Datalog.hs

## Wave 3: Remaining Tests

| Module | Tests Added | Classification |
|---|---|---|
| `QxFx0.Resources` | 3 (computeReadinessMode: Ready/Degraded/NotReady) | unit |
| `Bridge.NixGuard` | 3 (isSafeChar, nixStringLiteral escaping, nixStringLiteral empty) | unit |
| `Bridge.LLM.Provider` | 2 (extractResponseField simple, missing path) | unit |
| `Render.Dialogue` | 7 (isVapidTopic×2, cleanTopic×2, stancePrefix, moveToText×2) | unit |
| `Render.Semantic` | 1 (renderSemanticIntrospection format) | unit |
| `Core.ConsciousnessLoop` | 4 (initialLoop, runConsciousnessLoop, updateAfterResponse, addCoreSignal cap) | unit |

**Bug found and fixed:** `nixStringLiteral` had wrong escaping order (backslash-after-quote → backslash-first). Corrected order: `\` → `"` → `${`.

**Total test count:** 61 → 83 (+22)

**Modules documented as smoke-only (not unit-testable from library):**
- CLI parser/worker boundary: pure parsers in executable component; tested via release-smoke.sh steps 7-8
- `Bridge.NixGuard` checkConstitution/evaluatePolicy: requires nix-instantiate
- `Bridge.LLM.Provider` callLLM/execCurlWithSecretHeader: requires network/LLM API

## Wave 4: CI/Debt Gates + Exception Policy Module

| Item | Resolution |
|---|---|
| Post-smoke cleanliness check | `release-smoke.sh` records `git status --porcelain` before smoke and diffs after; fails if new dirty files |
| Bridge→Core compatibility shims | Fully eliminated (no shim allowlist remains) |
| No new Bridge→Core dependencies | Enforced by `check_architecture.sh` check [4] (zero Core imports from Bridge) |

## Wave 5: Audit/Doc Closeout

| Item | Resolution |
|---|---|
| ARCHITECTURAL_AUDIT.md outdated | Updated: 23 resolved findings, 5 remaining (all LOW/MEDIUM), scores recalculated |
| No tech debt closure document | This document created |

## Wave 6: Deep-Dive Follow-up Hardening

| Item | Resolution |
|---|---|
| `SessionLock` first-creation race | `Map.insertWith (\_ old -> old)` keep-existing insertion semantics in STM |
| SQLite overflow path exception safety | `withPooledDB` now guarantees close + pool restore via `finally` |
| DB pool return complexity | switched from `dbs ++ [db]` to O(1) LIFO `db : dbs` |
| Agda typecheck may hang | timeout added (`QXFX0_AGDA_TIMEOUT_MS`, default constant) |
| Runtime LLM HTTP manager churn | shared manager in `RuntimeContext` + `callLLMWithManager` path |
| Datalog path fragility (`rpAgdaSpec` derived dir) | switched to `rpDatalogRules`-root lookup |
| Dead helper in observability | `renderLogicalBond` removed |
| Repo hygiene (`cabal.project.local`) | added to `.gitignore` |
| Thin test coverage in targeted pure/runtime paths | added tests: session-lock burst, Dream cycle/catchup, Identity signal/guard, Agda timeout, pooled DB overflow recovery |

## Wave 7: Inline Constant Extraction + SQL Parameterization + Haddock Closeout

| Item | Resolution |
|---|---|
| 30 inline numeric constants in Core (Intuition, PrincipledCore, Consciousness.Kernel, BackgroundProcess, Dream, R5Dynamics, IdentitySignal, Cascade, MeaningGraph, Narrative, Tension, ClaimBuilder) | All extracted to `Types.Thresholds.Constants` |
| SQL literal inline in `Runtime/Session.hs` (`agency=0.5`, `tension=0.3`) | Parameterized via `bindDouble` with canonical constants |
| Haddock gaps in complex Core modules | Module headers added: `Intuition.hs`, `PrincipledCore.hs`, `Consciousness.Kernel.hs`, `DreamDynamics.hs`, `R5Dynamics.hs`, `MeaningGraph.hs`, `Consciousness.hs` |
| Global inline sweep | Zero findings across Core/Runtime/Bridge/app/test after full extraction |

## Historical Score Progression

| Metric | Pre-Audit | Pre-Wave | Post-Wave 5 | Post-Wave 7 |
|---|---|---|---|---|
| Architecture Readiness | 7.5 | 8.8 | 9.2 | 9.5 |
| Layer Integrity | 7.0 | 8.5 | 9.3 | 9.5 |
| Spec Soundness | 8.0 | 8.5 | 8.5 | 8.5 |
| Code Hygiene | 7.0 | 8.0 | 9.5 | 9.5 |
| Data Quality | 8.0 | 9.0 | 9.5 | 9.5 |
| Operational Maturity | 8.0 | 8.8 | 9.3 | 9.5 |
| **Overall** | **7.6** | **8.6** | **9.2** | **9.4** |

## Wave 8: Iteration 7 — Comprehensive Audit Discovery / Documentation Closure

Wave 8 did not introduce code changes; it was a pure audit and documentation wave. The following items were discovered, documented, and their true status clarified (closing previous false-confidence claims).

| Item | Previous Claim | Discovered Truth | Documented In |
|---|---|---|---|
| Agda↔Haskell sync guarantee | "14 constructors verified = formal guarantee" | Sync is structural (names + mappings only), not behavioral equivalence | `COMPREHENSIVE_AUDIT_2026.md` Iteration 7 |
| All gates pass | Iteration 6 claimed 10/10 ACCEPT | `styleFromLegitimacy` regression breaks build + test gates | `COMPREHENSIVE_AUDIT_2026.md`, `TECH_DEBT.md` |
| SQLite pool safety | "overflow path closes connections and restores pool state" | Pooled path lacks `ROLLBACK` on exception; `newDBPool` leaks on partial init; `withDB` misses non-IO exceptions | `COMPREHENSIVE_AUDIT_2026.md`, `TECH_DEBT.md` |
| Datalog runtime safety | "Datalog path resolved correctly" | Soufflé execution has no timeout → thread can hang forever | `COMPREHENSIVE_AUDIT_2026.md`, `TECH_DEBT.md` |
| Supply-chain reproducibility | Not previously tracked | No `cabal.project.freeze`; external tool versions unchecked | `COMPREHENSIVE_AUDIT_2026.md`, `TECH_DEBT.md` |
| HTTP sidecar security | "API key required for non-loopback" | API key transmitted in plaintext HTTP; `CLI/Http.hs` does not validate host | `COMPREHENSIVE_AUDIT_2026.md`, `TECH_DEBT.md` |
| Architecture gate [5] | "No `SomeException` usage found" | Regex could miss `@SomeException` via TypeApplications (latent risk) | `COMPREHENSIVE_AUDIT_2026.md`, `TECH_DEBT.md` |
| Property-based testing | "6 properties cover key invariants" | Missing: state roundtrip, pipeline state-machine, concurrent session lock, routing monotonicity | `COMPREHENSIVE_AUDIT_2026.md`, `TECH_DEBT.md` |

**Audit artifacts updated:**
- `COMPREHENSIVE_AUDIT_2026.md` — appended Iteration 7 section with all findings, remediation plan, revised scores, and verdict.
- `TECH_DEBT.md` — restructured with P0 (regression), P1 (pool safety), P2 (security/determinism), P3 (gates/formal/tests/docs).
- `TECH_DEBT_CLOSED_2026.md` — this Wave 8 entry.

**No code modifications were made in Wave 8** (per audit scope: findings and documents only).

---

## Remaining Items (Documented Non-Debt or Low Priority)

1. **~20 domain-layer sub-modules without Haddock headers** — `Guard/Checks`, `PipelineIO/Internal`, `Consciousness/Types`, `Legitimacy/Scoring`, etc. P3, ~2hr.
2. **SQL schema source consolidation** — `spec/sql/schema.sql` + `migrations/001_initial_schema.sql` + `EmbeddedSQL.hs` (generated). P3, ~1hr.
3. **CLI pure parser extraction** — would require moving `extractSessionArgs`, `decodeWorkerCommand`, etc. to a library module. P3, ~2hr.
4. **`_≤_` COMPILE GHC pragma** — Sovereignty.agda runtime verifiability. P3, ~15min.
