# Security Audit Report: QxFx0

## Executive Summary
This audit examined the Haskell project at `/home/liskil/my-haskell-project/QxFx0` across 10 security domains. The analysis identified **3 Critical**, **5 High**, **8 Medium**, and **4 Low** severity findings requiring immediate remediation.

---

## Critical Severity

### 1. Unsafe Indexing in Game Theory Solver
- **File**: `src/QxFx0/Learning/GameTheory/LP.hs`
- **Lines**: 67, 95, 97, 103–105, 108, 115, 118, 127
- **Risk**: Use of `!!` operator without bounds checking causes runtime crashes on malformed or empty matrices.
- **Impact**: Denial of service during learning cycle; potential for crafted adversarial inputs to crash the solver.
- **Mitigation**: Replace `!!` with `Data.Vector` indexing or explicit bounds checks using `safe` package functions.

### 2. Raw SQL Execution in Pool Layer
- **File**: `src/QxFx0/Bridge/SQLite/Pool.hs`
- **Function**: `execOrThrow`
- **Risk**: Executes arbitrary SQL strings without parameterization.
- **Impact**: SQL injection if any caller passes untrusted input directly to `execOrThrow`.
- **Mitigation**: Deprecate `execOrThrow` for user-facing operations; enforce parameterized queries via `Queries.hs` patterns.

### 3. Partial Function in Route Rendering
- **File**: `src/QxFx0/Core/TurnPipeline/Route/Render.hs`
- **Line**: 586
- **Risk**: `error` call on recovery failure crashes the runtime.
- **Impact**: Unhandled exception propagates to top level, terminating the session.
- **Mitigation**: Return `Either` or `Maybe` type; handle gracefully in the pipeline.

---

## High Severity

### 4. Path Traversal Vulnerability
- **File**: `src/QxFx0/Internal/FilePath.hs`
- **Function**: `isPathWithin`
- **Risk**: Uses `normalise` + `isPrefixOf`, which is bypassed by symlinks or `..` edge cases.
- **Impact**: Arbitrary file read/write if external tool outputs craft paths.
- **Mitigation**: Resolve to canonical paths via `canonicalizePath` before comparison; reject symlinks in sensitive directories.

### 5. Unsanitized External Process Input
- **Files**: `src/QxFx0/Bridge/Datalog/Runtime.hs`, `AgdaR5.hs`
- **Risk**: Spawns `agda`, `souffle`, `python3` with user-influenced arguments.
- **Impact**: Command injection if input contains shell metacharacters not properly escaped.
- **Mitigation**: Use `proc` with explicit argument lists (not `shell`); validate against allowlists; escape all paths.

### 6. Unsafe `head` Usage in Build Config
- **File**: `flake.nix`
- **Lines**: 33, 43
- **Risk**: `head` on empty list crashes Nix evaluation.
- **Impact**: Build failure if filtered lists are empty.
- **Mitigation**: Use `lib.lists.headOr` with safe defaults.

### 7. FFI Bounds Checking Missing
- **File**: `src/QxFx0/Bridge/SQLite/NativeSQLite.hs`
- **Risk**: `CString` conversions lack explicit length validation.
- **Impact**: Buffer overread/overwrite if SQLite returns malformed strings.
- **Mitigation**: Use `unsafePackCStringLen` with verified lengths; add bounds assertions.

### 8. Concurrency Deadlock Risk
- **File**: `src/QxFx0/Core/SessionLock.hs`
- **Risk**: `TVar` + `MVar` composition for `slmOverflowLock` may deadlock under contention.
- **Impact**: Session hangs indefinitely if lock order is violated.
- **Mitigation**: Use single `TMVar` or enforce strict lock ordering with timeout.

---

## Medium Severity

### 9. Resource Exhaustion in PGF Linearization
- **File**: `src/QxFx0/Runtime/PGF.hs`
- **Risk**: No limits on grammar size or recursion depth during linearization.
- **Impact**: Memory/CPU exhaustion on large grammars.
- **Mitigation**: Add configurable bounds; use `timeout` for linearization calls.

### 10. Learning Loop Unbounded Recursion
- **File**: `src/QxFx0/Learning/Loop.hs`
- **Risk**: Validation failures may retry indefinitely without backoff.
- **Impact**: Infinite loop on persistent malformed input.
- **Mitigation**: Implement exponential backoff with max retry cap.

### 11. CLI JSON Fallback Parsing
- **File**: `src/QxFx0/CLI/Parser.hs`
- **Risk**: Legacy string parsing path may accept malformed JSON.
- **Impact**: Unexpected behavior or crashes on edge-case inputs.
- **Mitigation**: Enforce strict JSON schema validation; deprecate legacy mode.

### 12. Datalog Temp File Exposure
- **File**: `src/QxFx0/Bridge/Datalog/Runtime.hs`
- **Risk**: Temp files created with predictable names in `/tmp`.
- **Impact**: Race condition / symlink attack.
- **Mitigation**: Use `openTempFile` with random names; set restrictive permissions.

### 13. Nix Guard Process Spawning
- **File**: `src/QxFx0/Bridge/NixGuard.hs`
- **Risk**: `nix-instantiate` called with user-influenced paths.
- **Impact**: Arbitrary code execution if path contains injection vectors.
- **Mitigation**: Validate paths against allowlist; use `proc` not `shell`.

### 14. Semantic Input Parse Robustness
- **File**: `src/QxFx0/Semantic/Input/Parse.hs`
- **Risk**: Parser may not handle malformed Unicode or control characters.
- **Impact**: Crash or incorrect parsing on adversarial input.
- **Mitigation**: Add input sanitization layer; use `attoparsec` with error recovery.

### 15. UI Session Timeout Missing
- **File**: `src/QxFx0/Runtime/Session/UI.hs`
- **Risk**: No idle timeout for interactive sessions.
- **Impact**: Session hijacking if terminal left unattended.
- **Mitigation**: Add configurable idle timeout with re-authentication.

### 16. Lexicon Runtime Indexing
- **File**: `src/QxFx0/Semantic/Lexicon/RuntimeParadigms.hs`
- **Line**: 323, 407
- **Risk**: `!!` and `head` used without bounds checks.
- **Impact**: Runtime crash on malformed lexicon data.
- **Mitigation**: Replace with safe indexing; validate data at load time.

---

## Low Severity

### 17. LLM API Key in Environment
- **File**: `src/QxFx0/Bridge/ExternalLLM.hs`
- **Risk**: API keys read from env vars may leak in process listings or logs.
- **Mitigation**: Use secure secret storage; mask in logs.

### 18. Dependency Bounds Too Loose
- **File**: `qxfx0.cabal`
- **Risk**: Some dependencies lack upper version bounds.
- **Mitigation**: Pin versions or use `>=` and `<` ranges.

### 19. Missing Input Length Limits
- **File**: `src/QxFx0/CLI/Parser.hs`
- **Risk**: No max length on CLI arguments.
- **Mitigation**: Add length checks before parsing.

### 20. Error Messages May Leak Info
- **File**: Multiple
- **Risk**: Exception messages may reveal internal paths or structure.
- **Mitigation**: Sanitize error output before displaying to users.

---

## Remediation Priority

1. **Immediate**: Fix `!!` indexing in `LP.hs` and `Render.hs` (Critical #1, #3)
2. **Short-term**: Replace `execOrThrow` with parameterized queries (Critical #2)
3. **Short-term**: Harden `isPathWithin` with canonical paths (High #4)
4. **Medium-term**: Add process input validation across all external tool calls (High #5)
5. **Ongoing**: Replace all partial functions with total alternatives

---

*Audit completed: 2026-05-24*
*Scope: 10 security domains across QxFx0 codebase*
