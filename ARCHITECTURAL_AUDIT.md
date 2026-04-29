# QxFx0 Architectural Audit Report

Audit date: 2026-04-21 (post-boundary-closure wave)
Scope: architectural integrity, layer boundaries, technical debt, spec soundness, code hygiene

## Verification Baseline

- `cabal build all`: **PASS**
- `cabal test qxfx0-test`: **PASS** (105/105)
- `bash scripts/check_architecture.sh`: **PASS** (9 checks, scanning src/ + app/)
- Modules: **77** exposed (+ ExceptionPolicy), 8 app modules, ~9 200 LOC
- Compiler warnings: **0**
- `rg SomeException src/ app/`: **0** hits outside ExceptionPolicy module
- `rg bare partial (head/tail/init/last/read) src/ app/`: **0** hits

---

## Resolved Findings (Cumulative)

| # | Finding | Date Resolved | How |
|---|---------|---------------|-----|
| 1 | Morphology dictionary typos (6 entries) | 2026-04-20 | Fixed all surface forms and lemmas |
| 2 | Duplicate `normalizeClaimText` | 2026-04-20 | Guard.hs imports from Types.hs |
| 3 | `ShadowDivergence` in Bridge | 2026-04-20 | Moved to `Types.ShadowDivergence` |
| 4 | `routeFamily` 14-tuple | 2026-04-20 | `RoutingDecision` named record |
| 5 | `QxFx0_SEMANTIC_INTROSPECTION` | 2026-04-20 | Renamed to `QXFX0_SEMANTIC_INTROSPECTION` |
| 6 | Datalog CWD write | 2026-04-20 | Temp directory + cleanup |
| 7 | `__pycache__/` + `semantic_rules.dl` | 2026-04-20 | Removed; `.gitignore` updated |
| 8 | Types importing Core | 2026-04-20 | `Types.Orbital`, `Types.IdentityGuard` |
| 9 | `postulate contradiction` in R5Core.agda | 2026-04-20 | Removed; `⊥` as empty data type |
| 10 | ~80 unnamed magic numbers | 2026-04-20 | `Types.Thresholds` (203 LOC, named constants) |
| 11 | `clamp01` defined 3x | 2026-04-20 | Single definition in `Thresholds.hs` |
| 12 | Depth mode as Text | 2026-04-20 | `DepthMode` ADT + `depthModeText` + JSON instances |
| 13 | Souffle `-D.` output to CWD | 2026-04-20 | `-D outDir` with temp directory |
| 14 | 32 over-broad `catch SomeException` handlers | 2026-04-20 | `ExceptionPolicy` module with `tryAsync`/`tryIO`/`catchIO` |
| 15 | `last` in CLI.hs | 2026-04-20 | Pattern matching `(c:_) -> Just c` |
| 16 | Raw SomeException in CLI.hs | 2026-04-20 | `ExceptionPolicy.tryAsync` |
| 17 | Resource discovery duplication (Resources + Datalog) | 2026-04-20 | Datalog imports canonical resolver from `QxFx0.Resources` |
| 18 | 9 partial function calls | 2026-04-20 | `head`→pattern match; `tail`/`init`→`drop 1`/`take (n-1)`; `T.last`/`T.init`→`T.unsnoc`; `read`→`readMaybe` |
| 19 | 2 partial `read` calls | 2026-04-20 | DreamDynamics→UTCTime constructor; Migrations→readMaybe |
| 20 | `nixStringLiteral` wrong escaping order | 2026-04-20 | Reordered: backslash first, then quotes, then interpolation |
| 21 | Test coverage gaps in pure modules | 2026-04-20 | 22 new tests: Resources, NixGuard, LLM.Provider, Render.Dialogue, Render.Semantic, ConsciousnessLoop |
| 22 | No post-smoke cleanliness gate | 2026-04-20 | `release-smoke.sh` records and checks `git status --porcelain` |
| 23 | Architecture check doesn't scan app/ | 2026-04-20 | Checks 5,6,7 now include app/ directory |
| 24 | `lowerFirst` broken for Cyrillic | 2026-04-20 | `Data.Char.toLower` instead of ASCII-only |
| 25 | NativeSQLite UTF-8 broken for non-ASCII | 2026-04-20 | `bindText`/`columnText`→`TE.encodeUtf8`/`TE.decodeUtf8` + `sqlite3_column_bytes` FFI |
| 26 | CoreVec scattered across DreamDynamics/Intuition | 2026-04-20 | New `Core.Vec` module |
| 27 | Dockerfile missing resources/lexicon/Agda | 2026-04-20 | Full Dockerfile with COPY + Agda compile + --serve-http |
| 28 | Core→Bridge direct coupling in Route.hs | 2026-04-20 | `PipelineIO` abstraction (ShadowVerifier, LLMBackend) |
| 29 | `hPutStrLnWarning` defined in multiple modules | 2026-04-20 | Single definition in Observability |
| 30 | Guard report inline construction | 2026-04-20 | `buildGuardReport` helper in TurnRouting |
| 31 | Semantic.Logic 14 rule* pattern-match | 2026-04-20 | Table-driven `LogicRule` + `runRule` |
| 32 | Semantic.Proposition 19 match* pattern-match | 2026-04-20 | Unified `matchKeywords` |
| 33 | `accusativeForm` wrong for inanimate masc/neuter | 2026-04-20 | Animacy-dependent (inanimate = nominative) |
| 34 | Missing type signatures (6 functions) | 2026-04-20 | Added to DreamDynamics, ConsciousnessLoop, TurnRouting |
| 35 | DreamDynamics `logsAcc` O(n²) catchup | 2026-04-20 | `log' : logsAcc` + `reverse` |
| 36 | `detectConflicts` O(n²) linear scan | 2026-04-20 | Map-grouping by concept |
| 37 | `case () of` anti-pattern in TurnModulation | 2026-04-20 | if/else if chain |
| 38 | Dead code: fragment="", AgdaResult | 2026-04-20 | Removed |
| 39 | NixGuard interpolation vulnerability | 2026-04-20 | `isNixPolicySafe` filter before interpolation |
| 40 | `fallbackEmbedding` uses non-deterministic `Data.Hashable.hash` | 2026-04-20 | `stableHash` (polynomial 31) |
| 41 | Core.Runtime 437 LOC monolith | 2026-04-20 | Decomposed into Runtime.Context, Runtime.Health, Runtime.Session + re-export hub |
| 42 | StatePersistence 424 LOC manual serialization | 2026-04-20 | Generic JSON blob save + legacy fallback loader |
| 43 | FromJSON SystemState field order bug (lastTopic/lastFamily swapped) | 2026-04-20 | Fixed field order to match DialogueState constructor |
| 44 | LLM.Provider uses curl subprocess | 2026-04-20 | Native `http-client` + `System.Timeout.timeout` |
| 45 | Worker test hooks active in production | 2026-04-20 | `QXFX0_TEST_MODE` guard on crash/error hooks |
| 46 | `allow-newer: all` masking dependency conflicts | 2026-04-20 | Removed (no conflicts exist) |
| 47 | Migration ↔ spec SQL not verified | 2026-04-20 | `testMigrationMatchesCanonicalSpec` test added |

---

## Current Layer Boundary Status

### Clean boundaries

| Direction | Imports | Status |
|---|---|---|
| Types → Core/Bridge | 0 | **clean** |
| Semantic → Core/Bridge | 0 | **clean** |
| Render → Core/Bridge | 0 | **clean** |
| App → SomeException/partial | 0 | **clean** (enforced by check_architecture.sh) |

### Core → Bridge (0 direct imports — enforced by check_architecture.sh)

Core internal modules (`Core.TurnPipeline.*`, `Core.Guard`, etc.) import only `Core.PipelineIO` for I/O operations. PipelineIO provides:

| Field | Type | Injected from |
|---|---|---|
| `pioShadowVerifier` | `ShadowVerifier` | `Runtime.Wiring` |
| `pioLLMBackend` | `LLMBackend` | `Runtime.Wiring` |
| `pioPersistence` | `PersistenceOps` | `Runtime.Wiring` |
| `pioNixPath` | `IO (Maybe FilePath)` | `Runtime.Wiring` |
| `pioNixCheck` | `Maybe FilePath -> Text -> Double -> Double -> IO NixGuardStatus` | `Runtime.Wiring` |
| `pioConsciousLoop` | `ConsciousLoopOps` | `Runtime.Wiring` |
| `pioIntuition` | `IntuitionOps` | `Runtime.Wiring` |
| `pioApiHealth` | `IO Bool` | `Runtime.Wiring` |
| `pioUpdateHistory` | `Text -> Seq Text -> Seq Text` | `Runtime.Wiring` |

The top-level `Core.hs` facade imports `QxFx0.Runtime` for `runTurn` (which takes `RuntimeContext`) and re-exports `QxFx0.Runtime`. All other Core internal modules are Runtime-free.

### Runtime → Bridge (composition root)

`Runtime.Wiring` is the composition root: it imports Bridge modules and wires them into `PipelineIO`. `Runtime.Context` is a re-export shim. `Runtime.Session` bootstraps the system (imports Bridge.SQLite, Bridge.StatePersistence). `Runtime.Health` provides health checks.

### Bridge → Core (0 imports)

Previous audit listed 3 "compatibility shims" — these were removed. `Core.Runtime.*` shim modules were deleted and replaced by `QxFx0.Runtime.*`. `grep 'import QxFx0.Core' src/QxFx0/Bridge/` returns 0 hits. `check_architecture.sh` check 4 directly forbids Bridge→Core imports and Core internal→Bridge/Runtime imports.

### Exception Policy

All Bridge, Core, Semantic, and App modules use `QxFx0.ExceptionPolicy` (`tryIO`, `catchIO`, `tryAsync`) instead of raw `Control.Exception` catches. The sole `SomeException` usage is inside `ExceptionPolicy.tryAsync`, which explicitly re-raises `AsyncException`.

---

## Remaining Findings

### Finding 1 [RESOLVED]: Sovereignty.agda postulate concern

Previous concern about "4 postulates" is no longer applicable in the current file state. `Sovereignty.agda` is treated as a specification artifact and is type-checked in verification flow.

**Status:** CLOSED (file state and gate flow updated).

### Finding 2 [LOW]: Stray depth-mode string literals (resolved)

Both `Finalize.hs` bare `"medium"` and `TestMain.hs` bare `"surface"` have been verified as resolved — current code uses `DepthMode`/`ScenePressure` ADT constructors everywhere.

### Finding 3 [RESOLVED]: CLI pure parser functions now unit-tested

`extractSessionArgs`, `decodeWorkerCommand`, `parseWorkerArgs`, `parseMode`, `parseJsonStringArray` now live in `QxFx0.CLI.Parser` (library module) and are exercised from `TestMain.hs`.

---

## Test Coverage Summary

| Module | Unit Tests | Integration | Smoke |
|---|---|---|---|
| `QxFx0.Resources` | 3 (computeReadinessMode) | covered by bootstrap tests | - |
| `Bridge.NixGuard` | 3 (isSafeChar, nixStringLiteral) | - | smoke step 5 |
| `Bridge.LLM.Provider` | 2 (extractResponseField) | - | smoke step 7/8 |
| `Bridge.Datalog` | 1 (shadow respects atoms) | - | smoke step 6 |
| `Render.Dialogue` | 7 (isVapidTopic, cleanTopic, stancePrefix, moveToText) | - | - |
| `Render.Semantic` | 1 (renderSemanticIntrospection) | 1 (semantic mode turn) | - |
| `Core.ConsciousnessLoop` | 4 (initialLoop, run, updateAfterResponse, addCoreSignal) | - | - |
| `Core.Consciousness` | 1 (interpretation tracking) | - | - |
| `Core.Ego` | 1 | - | - |
| `Core.Legitimacy` | 1 | - | - |
| `Core.Guard` | 1 | - | - |
| `Core.DreamDynamics` | 1 | - | - |
| `Core.BackgroundProcess` | 1 | - | - |
| `Core.Intuition` | 1 | - | - |
| `Core.MeaningGraph` | 2 | - | - |
| `Core.SessionLock` | 1 | - | - |
| `Core (routing, tension, modulation)` | 20 | 3 (bootstrap, turn, persistence) | - |
| `Bridge.StatePersistence` | 3 | - | - |
| `Bridge.EmbeddedSQL` | 2 (spec match + migration spec sync) | - | - |
| `Semantic.Embedding` | 2 | - | - |
| `Semantic.Morphology` | 2 | - | - |
| `Semantic.Logic` | 3 | - | - |
| `Semantic.Proposition` | 2 | - | - |
| `Semantic.MeaningAtoms` | 2 | - | - |
| `QxFx0.CLI.Parser` | 5 | - | smoke steps 7-8 |
| HTTP runtime | 6 (health, turn, crash recovery, post-commit tail, state, explicit error) | - | - |

**Total: 105 test cases, 0 errors, 0 failures**

---

## Updated Scores

### Architecture Readiness: 8.8/10

- Thin Core with phase decomposition
- Runtime decomposed into Context/Health/Session submodules
- PipelineIO abstraction decouples Route from Bridge internals
- RoutingDecision named record
- Types as clean shared dependency
- Core→Bridge via PipelineIO (no direct logic coupling)
- Bridge→Core: 0 imports (previous 3 "shims" did not exist)
- ExceptionPolicy as canonical exception handler

### Layer Integrity: 9.2/10

- Types/Semantic/Render: zero cross-layer violations
- Core internal modules: 0 Bridge/Runtime imports (all I/O via PipelineIO)
- Core.hs facade: imports Runtime (composition root wiring, not internal module)
- Runtime: imports Bridge (composition root) + Core (types/logic)
- Bridge→Core: 0 imports (enforced by check_architecture.sh)
- Architecture check enforces Core internal→Bridge/Runtime = 0
- No SomeException in production code outside ExceptionPolicy

### Spec Soundness: 9.0/10

- R5Core.agda: proven core mapping and constructor contracts
- Constructor sync: verified
- SQL sync: generated + tested
- Migration↔spec sync: tested
- Sovereignty.agda: type-checked in gate flow
- Legitimacy.agda: type-checked in `verify.sh`/`release-smoke.sh`

### Code Hygiene: 9.0/10

- 0 TODO, 0 undefined, 0 error calls, 0 unsafePerformIO, 0 Debug.Trace
- Named constants in Thresholds.hs
- DepthMode ADT
- Single `clamp01`
- 0 bare partial functions (all replaced)
- 0 raw SomeException catches (all via ExceptionPolicy)
- nixStringLiteral escaping order fixed
- Worker test hooks guarded by QXFX0_TEST_MODE
- LLM.Provider uses native HTTP client (no curl subprocess)
- allow-newer: all removed (was unnecessary)
- Stray depth-mode string literals resolved
- Lexical markers centralized in Policy.Templates
- TurnProjection DTO in Types.TurnProjection (not Bridge)
- SQL fallback now noisy (hPutStrLn stderr on fallback)
- WorkerDBPool now rotates connections with FK pragma

### Data Quality: 9.0/10

- Morphology typos fixed
- `normalizeClaimText` consolidated
- Dead tables auto-cleaned on bootstrap
- `schema_version` actively used
- Generic JSON serialization (no more 30+ manual saveKV)
- FromJSON field order bug fixed

### Operational Maturity: 9.0/10

- Build/test/check clean
- Env var naming consistent
- Datalog temp directory with cleanup
- Post-smoke cleanliness gate
- Architecture check covers app/
- ExceptionPolicy prevents silent degradation
- .gitignore complete
- Persistence with rollbacks + legacy fallback
- Resource resolver unified (no duplication)
- Dockerfile production-ready (resources, lexicon, Agda, --serve-http)
- Test hooks safe in production (-0.5 → now fixed)
- `stableHash` instead of `Data.Hashable.hash` for deterministic embeddings

### **Overall: 9.0/10**

Previous scores: 7.6 (first audit) → 7.9 (second audit) → 8.6 (pre-wave) → 8.8 (wave 6) → 9.0 (now)

Key improvements since wave 6:
- Core internal modules fully decoupled from Bridge and Runtime (all I/O via PipelineIO)
- Runtime layer extracted as composition root (QxFx0.Runtime.*)
- WorkerDBPool rotates connections + FK pragma enforced on all pooled handles
- SQL fallback now noisy (warns to stderr)
- Lexical markers centralized in Policy.Templates
- TurnProjection moved to Types layer

---

## Remaining Remediation

| Priority | Finding | Effort | Impact |
|---|---|---|---|
| P3 | Remove StatePersistence legacy fallback after all sessions migrated to JSON blob | 1 hr | Code simplification |
| P3 | Make SQL one-source-at-runtime (embedded as primary for packaged binary, spec for dev) | 4 hr | Architectural canonicality |
| P4 | Consciousness `T.isInfixOf` heuristic fragility | 4 hr | Robustness |
