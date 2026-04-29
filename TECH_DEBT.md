# QxFx0 Technical Debt Audit

Audit date: 2026-04-20
Last updated: 2026-04-25 (Runtime invariant closure pass)
Audit scope: architecture debt, operational debt, readiness blockers, security, determinism, formal verification

## Current Status (2026-04-24)

This document retains earlier findings for traceability. The current implementation status is:

- `styleFromLegitimacy` regression: **CLOSED** (`cabal test qxfx0-test` PASS).
- SQLite pool exception safety: **CLOSED** (rollback sanitation and cleanup tests pass).
- Datalog execution timeout: **CLOSED** (controlled timeout diagnostic test passes).
- `cabal.project.freeze`: **CLOSED** (freeze file present; `verify.sh` gate `[13]` passes).
- HTTP sidecar loopback validation: **CLOSED** (`isLoopbackHost` + explicit non-loopback opt-in).
- LLM rescue fallback: **CLOSED/REMOVED** from the turn runtime. Local recovery
  now handles low-legitimacy and degraded cases without a model call.
- NixGuard unknown safe concepts: **CLOSED** fail-closed (strict mode blocks unknown concept keys).
- Soak/fuzz coverage: **CLOSED** (`scripts/soak.sh` and `scripts/fuzz.sh` pass).
- Runtime readiness/schema/persistence invariants: **CLOSED** (`docs/runtime_invariants.md`, `spec/sql/runtime_critical_contract.tsv`, `scripts/check_schema_contract.py`).
- Dirty-tree local artifact noise: **CLOSED** for known generated temp outputs (`.test-tmp/`, `.verify-home/`, DB sidecars, Souffle relation CSVs).
- HTTP perimeter ownership and opt-in boundaries: **CLOSED** for authenticated
  session token binding, `/health` auth parity, `0.0.0.0` non-loopback guard,
  and removal of implicit `cwd` script trust.
- Remote embedding implicit egress: **CLOSED**. `EMBEDDING_API_URL` alone no
  longer enables remote HTTP embeddings.

Remaining items below this line are either historical audit notes or accepted lower-priority limitations unless explicitly marked open in `AUDIT_2026_CURRENT_STATE.md`.

## Runtime Invariant Closure (2026-04-25)

The latest closure pass records and guards the invariants introduced by the
runtime/schema remediation work:

- `--runtime-ready` and strict bootstrap share the same readiness meaning.
- Fresh DBs report `schema_bootstrapable_fresh_db`; v1 DBs report not-ready
  until migration; inconsistent current DBs remain not-ready.
- Migration version markers are written only after validation succeeds.
- Runtime-critical tables, columns, indexes, triggers, and FTS tables are listed
  in `spec/sql/runtime_critical_contract.tsv`.
- `scripts/check_schema_contract.py` verifies the manifest against
  `spec/sql/schema.sql` and `QxFx0.Bridge.SQLite.SchemaContract`.
- Persistence diagnostics are typed with `PersistenceStage`.
- Replay traces now persist local recovery policy/cause/strategy/evidence
  instead of an LLM fallback policy.
- Known local generated artifacts are ignored before commit preparation.
- Authenticated HTTP turns now claim `session_id` ownership only after input
  validation and require `X-QXFX0-Session-Token` on subsequent turns for that
  session.
- The deprecated `/health` alias now shares the same API-key perimeter as
  `/sidecar-health`.
- Implicit `http_runtime.py` resolution no longer trusts `cwd`.
- Remote embedding requires explicit `QXFX0_EMBEDDING_BACKEND=remote-http`.

## Update (2026-04-23)

### Regression Discovered During Final Audit — CLOSED 2026-04-24

**CRITICAL — `styleFromLegitimacy` export removed but still referenced in tests**
- `test/Test/Suite/CoreBehavior.hs:1719` references `Legitimacy.styleFromLegitimacy`, which was removed from `QxFx0.Core.Legitimacy` and `QxFx0.Core.Legitimacy.Scoring` during a prior cleanup wave.
- This previously caused `cabal build all` and `cabal test qxfx0-test` to fail.
- `release-smoke.sh` previously failed at gate [1] (build) and gate [2] (unit tests).
- **Closure:** export/test surface restored; `cabal test qxfx0-test` and release smoke pass.

### New HIGH Findings (Concurrency / Resource Safety) — CLOSED 2026-04-24

**HIGH — Active transaction returned to DB pool on exception**
- `src/QxFx0/Bridge/SQLite/Pool.hs:104-107`: pooled path `withConnections restore (db : dbs)` returns connection to `MVar` pool after `action db`, but if `action db` throws after `BEGIN IMMEDIATE`, the connection has an active transaction.
- Next consumer gets a busy connection → `SQLITE_BUSY` / nested transaction / deadlock.
- **Closure:** pooled return path sanitizes with rollback/fallback before reuse.

**HIGH — `newDBPool` partial initialization leaks connections**
- `src/QxFx0/Bridge/SQLite/Pool.hs:39-52`: `sequence (replicate size openOne)` — if the k-th `openOne` throws, the first k-1 connections are never closed.
- **Closure:** partial initialization cleanup closes accumulated handles.

**HIGH — `withDB` exception safety is incomplete**
- `src/QxFx0/Bridge/SQLite/Pool.hs:61-73`: `catchIO` catches only `IOException`. Other sync exceptions (`QxFx0Exception`, `ThreadKilled`, etc.) leak the connection.
- **Closure:** connection restoration uses `finally`/async-aware policy.

### New MEDIUM Findings (Security / Determinism / Operational) — MOSTLY CLOSED 2026-04-24

**MEDIUM — Datalog execution without timeout**
- `src/QxFx0/Bridge/Datalog/Runtime.hs:267-280`: `readProcessWithExitCode` on Soufflé has no timeout.
- Infinite loop in Soufflé → Haskell thread hangs forever.
- **Closure:** Soufflé execution is wrapped in timeout and covered by regression test.

**CLOSED — `cabal.project.freeze` present**
- `cabal.project.freeze` exists and is checked by `scripts/verify.sh` gate `[13]`.

**MEDIUM — External tools not version-pinned in gates**
- `scripts/verify.sh` does not check `agda --version`, `souffle --version`, `nix --version`, `python3 --version`.
- **Fix:** add minimum/maximum version assertions.

**MEDIUM — HTTP sidecar plaintext API key exposure**
- `scripts/http_runtime.py` serves HTTP (not HTTPS). `X-API-Key` is plaintext.
- Default bind is loopback; non-loopback now requires explicit `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1`.
- **Closure:** loopback validation is enforced in the CLI HTTP path; remote exposure requires explicit operator opt-in.

### New LOW Findings (Gates / Formal / Testing / Docs)

**LOW — `check_architecture.sh` [5] regex bypassable**
- `SomeException` regex does not catch `catch @SomeException` via `TypeApplications`.
- No current usage, but gate is latent-risk.
- **Fix:** strengthen regex or add GHC `-Werror`.

**LOW — Agda↔Haskell sync is structural, not behavioral**
- `verify_agda_sync.py` checks constructor names and function mappings, not function bodies.
- TSV snapshot is generated from Haskell, not extracted from Agda proofs.
- Gives false confidence in formal guarantees.
- **Fix:** document explicitly in `AGENTS.md` that sync is structural only.

**LOW — Missing property-based test coverage**
- Only 6 QuickCheck properties.
- Missing: state persistence roundtrip, TurnPipeline state-machine invariants, concurrent session lock behavior, routing monotonicity.
- **Fix:** add `Arbitrary` instances and properties.

**LOW — ~20 domain-layer sub-modules without Haddock headers**
- Onboarding friction. Not architectural.

---

## Snapshot (Pre-Regression — Iteration 6)

- `cabal build all`: PASS
- `cabal test qxfx0-test`: PASS
- `cabal check`: clean
- compiler warnings on normal build path: 0
- `bash scripts/verify.sh`: PASS
- `QXFX0_REQUIRE_AGDA=1 bash scripts/release-smoke.sh`: PASS (10/10)
- `nix run .#typecheck-agda`: PASS
- `TurnPipeline` is now phase-split instead of one large implementation file

## Snapshot (Iteration 7 — Superseded)

- Superseded by the 2026-04-24 closure pass.
- Current build, test, verify, soak, fuzz, architecture, lexicon, schema, and release-smoke gates pass.

---

## Priority: CRITICAL (P0)

### 0. Fix `styleFromLegitimacy` regression — CLOSED

Evidence:
- `test/Test/Suite/CoreBehavior.hs:1719`
- `src/QxFx0/Core/Legitimacy.hs` (module export list)
- `src/QxFx0/Core/Legitimacy/Scoring.hs` (module export list)

Historical impact:
- Release gate was red. Build, tests, and verification were blocked.

Closure:
- Export/test surface restored; current gates pass.

---

## Priority: HIGH (P1)

### 1. SQLite pool exception safety — CLOSED

Evidence:
- `src/QxFx0/Bridge/SQLite/Pool.hs:104-107` (active transaction leak)
- `src/QxFx0/Bridge/SQLite/Pool.hs:39-52` (partial init leak)
- `src/QxFx0/Bridge/SQLite/Pool.hs:61-73` (incomplete catch)

Impact:
- Silent state corruption (active tx returned to pool), resource leaks, deadlocks under concurrent load.

Closure:
- `ROLLBACK` sanitation, partial-init cleanup, and async-aware restoration are implemented and covered.

---

## Priority: MEDIUM (P2)

### 2. Datalog execution timeout — CLOSED

Evidence: `src/QxFx0/Bridge/Datalog/Runtime.hs:267-280`

Impact: DoS if Soufflé hangs.

Closure: `System.Timeout.timeout` wrapper implemented and covered.

### 3. Supply-chain determinism — CLOSED

Evidence: `cabal.project.freeze` present; `verify.sh` gate `[13]` checks it.

Impact: lock-file drift is now guarded by the verification gate.

Required fix: completed for Cabal freeze. External tool version pinning remains an optional hardening improvement, not a release blocker.

### 4. HTTP sidecar security posture — CLOSED

Evidence: `scripts/http_runtime.py` plaintext HTTP; `app/CLI/Http.hs` now validates host exposure.

Impact: API key sniffing risk is bounded to explicit non-loopback operator opt-in.

Closure: host validation implemented; non-loopback requires `QXFX0_ALLOW_NON_LOOPBACK_HTTP=1`.

---

## Priority: LOW (P3)

### 5. Architecture gate is text-based, not AST-based

Evidence: `scripts/check_architecture.sh` check [5] uses `rg 'SomeException'`.

Impact: A developer could bypass the gate by using a qualified/aliased import so the literal string `SomeException` never appears in the consuming file.

Required fix: Add GHC `-Werror` on over-broad exception warnings, or run an AST linter in CI.

### 6. Formal sync documentation

Evidence: `scripts/verify_agda_sync.py`, `AGENTS.md`

Required fix: explicit "structural sync, not behavioral equivalence" disclaimer.

### 7. Property-based test expansion

Evidence: only 6 QuickCheck properties in test suite.

Required fix: roundtrip, state-machine, concurrency, routing invariants.

### 8. Haddock coverage for ~20 domain sub-modules

Evidence: `Guard/Checks`, `PipelineIO/Internal`, `Consciousness/Types`, `Legitimacy/Scoring`, etc.

Required fix: module headers.

---

## Historical Closed Items (Retained for Traceability)

- Closed: `Types -> Core` dependency for orbital/identity-guard data.
- Closed: no architecture gate in verification; `scripts/check_architecture.sh` now runs in `verify.sh` and release smoke.
- Closed: missing projection persistence; `turn_quality`/`shadow_divergence_log` are now written transactionally with state save.
- Closed: Bridge→Core compatibility shims fully eliminated; `check_architecture.sh` [4] enforces zero Core imports from Bridge.
- Closed: `SessionLock.getOrCreateLock` race on first-lock creation (`Map.insertWith` keep-existing semantics).
- Closed: SQLite overflow path exception safety in `withPooledDB`; close+pool-restore now guaranteed via `finally`.
- Closed: `AgdaR5.agdaTypeCheck` timeout support (`QXFX0_AGDA_TIMEOUT_MS`, default constant).
- Closed: historical runtime LLM path removed; HTTP manager remains for local runtime infrastructure and embedding paths.
- Closed: `Datalog` rules path now resolved from `rpDatalogRules` root, not `rpAgdaSpec`-derived directory.
- Closed: dead code `renderLogicalBond` removed; `.gitignore` now includes `cabal.project.local`.
- Closed: coverage expansion for Dream/Identity/SessionLock + runtime infra timeout/overflow paths.
- Closed: **all 30 inline numeric constants** in Core extracted to `Types.Thresholds.Constants` (global sweep: zero findings in Core/Runtime/Bridge/app).
- Closed: SQL literal inline in `Runtime/Session.hs` parameterized via `bindDouble` with canonical constants.
- Closed: full Core Haddock coverage (all `QxFx0.Core.*` top-level modules now have module headers).
- Closed: SQL single-source enforcement hardened: `sync_embedded_sql.py --check` and `check_schema_consistency.py` are mandatory gates.

---

## Remediation Order (Iteration 7)

1. **P0:** Fix `styleFromLegitimacy` regression (15 min).
2. **P1:** SQLite pool exception-safety trilogy (45 min: rollback cleanup, init leak, catch completeness).
3. **P2:** Datalog timeout + freeze file + tool version checks (1 hr).
4. **P2:** HTTP sidecar docs + host validation (20 min).
5. **P3:** Architecture regex + Agda sync disclaimer + property tests + Haddock (4–5 hr).

**Total to return to green:** ~2 hours for critical/high/medium blockers; ~4–5 hours for full low-priority closeout.
