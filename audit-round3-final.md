# QxFx0 Production Vulnerability Audit — Round 3 (Final)

## Methodology
- Reviewed 30+ core source files across runtime, learning, bridge, state, and pipeline modules.
- Validated each finding against actual code paths, not assumptions.
- Cross-referenced with existing test coverage to confirm gaps.
- Excluded previously covered issues (Round 1 & 2 findings).

## Findings

### 1. Unbounded Guardrail Quarantine Growth (P0)
**File**: `src/QxFx0/Learning/Guardrails.hs:72,124,147`
**State field**: `ssGuardrailState` in `src/QxFx0/Types/State/System.hs:191`
**Update site**: `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:527`

**Issue**: `gsQuarantine :: ![(Int, CalibrationId)]` grows unboundedly. Every call to `recordProposalSubmission` (L114-125) and `quarantineProposal` (L145-147) prepends to the list. The state update at `State.hs:527` passes `ssGuardrailState` through unchanged: `ssGuardrailState = ssGuardrailState ss`. There is **no cleanup, rotation, or expiry logic** in the finalize pipeline.

**Impact**: In long-running sessions with frequent learning proposals, the quarantine list grows linearly. This causes:
- OOM risk in sessions with thousands of turns
- Serialization latency degradation (JSON encoding/decoding grows linearly)
- `isQuarantineExpired` (L150-156) scans the entire list on every check

**Fix**: Add bounded quarantine with LRU eviction (e.g., max 500 entries). Clean expired entries during state finalization.

---

### 2. Unbounded Provisional Atom List (P0)
**File**: `src/QxFx0/Types/State/System.hs:181`
**Type**: `ssProvisionalAtoms :: ![ProvisionalAtom]`
**Update site**: `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:512-521`

**Issue**: While `decayProvisionalAtoms` (AtomAccretion.hs:98-104) and `promoteProvisionalAtoms` (L79-94) are called during state finalization, the list has **no hard cap**. The decay function only removes atoms older than `defaultProvisionalAtomTTL = 20` turns, but in high-variance sessions with continuous novel atom observations, the list can grow significantly before decay kicks in.

**Impact**: 
- Memory growth proportional to novel atom discovery rate
- JSON serialization slowdown in long sessions
- `observeNovelAtom` (AtomAccretion.hs:45-68) uses `find` which is O(n) on the list

**Fix**: Add hard cap (e.g., 1000 atoms) with oldest-first eviction when cap is exceeded.

---

### 3. Unbounded Knowledge Tree Quarantine (P1)
**File**: `src/QxFx0/Learning/KnowledgeTree.hs:144`
**Type**: `ktQuarantine :: ![KnowledgeFruit]`
**Update site**: `quarantineFruit` (L239-243), `promoteFromQuarantine` (L248-268)

**Issue**: `quarantineFruit` prepends to `ktQuarantine` without size checks. `promoteFromQuarantine` only promotes fruits that meet age and delta criteria, but rejected fruits remain in the quarantine list (L262: `ktQuarantine = stillQuarantined ++ reject`). The `pruneFruits` function (L307-328) cleans unvalidated items but doesn't cap total size.

**Impact**: Marginal fruits that fail promotion accumulate indefinitely, causing memory growth and slower quarantine scans.

**Fix**: Add max quarantine size (e.g., 200 fruits) with oldest-first eviction.

---

### 4. Datalog Fact Injection via `escapeSymbol` (P1)
**File**: `src/QxFx0/Bridge/Datalog/Support.hs:57-64,188-196`

**Issue**: `escapeSymbol` handles `\`, `"`, `\n`, `\r`, `\t` but does NOT escape:
- Parentheses `(` and `)` which are syntactically significant in Souffle Datalog
- Periods `.` which terminate Datalog rules
- Percent signs `%` which start comments in Souffle

The `renderRuntimeFacts` function (L57-64) embeds atom names and details directly into Datalog fact syntax:
```haskell
"RequestedFamily(\"" <> escapeSymbol (renderShow (ssRequestedFamily snapshot)) <> "\")."
```

**Impact**: Malicious or malformed `AtomTag` payloads (from user input via `CustomAtom` or `AffectiveAtom` constructors) could break Datalog syntax, inject synthetic rules, or cause Souffle parser errors.

**Fix**: Add comprehensive escaping for Datalog-special characters: `(`, `)`, `.`, `%`, and verify that `escapeSymbol` is applied to ALL user-controlled content before embedding.

---

### 5. Sandbox Safety Floor Boundary Condition (P2)
**File**: `src/QxFx0/Learning/Sandbox.hs:161`

**Issue**: The check uses strict less-than:
```haskell
if projectedConatus < scSafetyFloor cfg
```
This means a score **exactly equal** to `scSafetyFloor` (default `-0.3`) passes as acceptable. The module documentation (L20-22) states "non-regression" as the acceptance criterion, which implies scores at the floor should be rejected.

**Impact**: Marginal scores at exactly the safety floor incorrectly pass, potentially allowing degraded states to be accepted.

**Fix**: Use `<=` for strict inequality: `projectedConatus <= scSafetyFloor cfg`

---

### 6. JSON Deserialization with Silent Defaults (P2)
**File**: `src/QxFx0/Types/State/System.hs:315-377`

**Issue**: The `FromJSON` instance heavily uses `.:?` with `.!=` defaults for fields that are semantically required:
- `ssSalienceWeights` (L356): defaults to `defaultSalienceWeights`
- `ssFieldHeuristics` (L357): defaults to `defaultFieldHeuristics`
- `ssLearningNeedState` (L360): defaults to `emptyLearningNeedState`
- `ssKnowledgeTree` (L363): defaults to `emptyKnowledgeTree`
- `ssGovernanceProjection` (L375): defaults to `emptyGovernanceProjection`

**Impact**: If a state file is corrupted, truncated, or from an older schema version, missing fields silently default to empty values. This masks state corruption and can cause subtle behavioral changes (e.g., lost salience weights, empty knowledge tree).

**Fix**: Add strict validation for required fields with explicit error reporting. Consider versioned migration checks for schema evolution.

---

### 7. Recovery State Inconsistency (P2)
**File**: `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs:188-193`

**Issue**: `recoverRuntimeTurnState` re-applies the commit plan using the intuition state from `savedState`:
```haskell
recoverRuntimeTurnState pipelineIO commitPlan savedState =
  attemptCommitRuntimeState
    pipelineIO
    commitPlan
    (maybe (fcpPreviewIntuition commitPlan) id (ssIntuitionState savedState))
```

If the original `saveStateWithProjection` (L88-95) failed after a partial write, `savedState` may be stale or corrupted. Recovery then applies the commit plan to an inconsistent base state.

**Impact**: After a persistence failure, recovery may produce a divergent state that doesn't match either the pre-commit or post-commit state, leading to subtle data corruption.

**Fix**: Implement WAL (Write-Ahead Log) checkpoints or transactional rollback to ensure atomic state persistence.

---

### 8. `SomeException` Catch in PGF Linearization (P1)
**File**: `src/QxFx0/Runtime/PGF.hs:85-96`

**Issue**: The `linearizeExpr` function wraps PGF operations in `try @SomeException`:
```haskell
result <- try $ do
  pgf <- PGF.readPGF pgfPath
  ...
case result of
  Left (e :: SomeException) -> pure (Left ("pgf_exception:" <> T.pack (show e)))
```

This catches ALL exceptions including async exceptions (`ThreadKilled`, `StackOverflow`), destroying stack traces and preventing proper error handling upstream.

**Impact**: 
- Masks root causes of PGF failures (corrupt files, memory issues, recursion depth)
- Prevents targeted debugging and error recovery
- Async exceptions are swallowed, potentially leaving the runtime in an inconsistent state

**Fix**: Replace `SomeException` with typed `IOException` catch. Let async exceptions propagate. Add structured error variants for PGF-specific failures.

---

### 9. `unsafePerformIO` Without `NOINLINE` (P1)
**File**: `src/QxFx0/Lexicon/GfMap.hs:93`

**Issue**: `gfMapLoadResult = unsafePerformIO loadCanonicalGfMap` lacks a `NOINLINE` pragma. Without it, GHC may duplicate the computation across modules or optimization passes, causing non-deterministic initialization order.

**Impact**: 
- Race conditions in concurrent contexts (multiple threads initializing the map)
- Non-deterministic behavior depending on optimization level
- Potential memory leaks if the computation is duplicated

**Fix**: Add `{-# NOINLINE gfMapLoadResult #-}` pragma. Consider using `unsafeInterleaveIO` or explicit initialization instead.

---

## Priority Matrix

| Severity | Finding | Files | Effort |
|----------|---------|-------|--------|
| P0 | Unbounded guardrail quarantine | Guardrails.hs:72,124,147; State.hs:527 | Low |
| P0 | Unbounded provisional atoms | System.hs:181; State.hs:512-521 | Low |
| P1 | Unbounded knowledge quarantine | KnowledgeTree.hs:144,239-243 | Low |
| P1 | Datalog fact injection | Support.hs:57-64,188-196 | Medium |
| P1 | SomeException catch in PGF | PGF.hs:85-96 | Low |
| P1 | unsafePerformIO without NOINLINE | GfMap.hs:93 | Low |
| P2 | Sandbox boundary condition | Sandbox.hs:161 | Low |
| P2 | Silent JSON defaults | System.hs:315-377 | Medium |
| P2 | Recovery state inconsistency | Commit.hs:188-193 | High |

## Corrected Findings from Initial Assessment

The following initial findings were **incorrect** after code review:

1. **`ssAdaptiveMutationLog` unbounded** — FALSE. Already bounded at `adaptiveMutationLogLimit = 100` (System.hs:495-496).
2. **`ssCalibrationSnapshots` unbounded** — FALSE. Already bounded at `take 100` (State.hs:436).
3. **`lnsHistory` unbounded** — FALSE. Already bounded at `maxHistoryLength = 20` (Need.hs:173,283).
4. **Agda witness path traversal** — FALSE. `awFiles` keys are hardcoded labels from `witnessInputs` (AgdaWitness.hs:197-211), not user-controlled paths.
5. **Transport fallback to MockTransport** — FALSE. `buildTransportFromEnv` properly validates and sets fallback reasons (ExternalLLM.hs:251-339). Invalid env vars result in explicit `TransportFallbackReason` values, not silent mock routing.

## Recommendations

1. **Immediate (P0)**: Add bounded rotation to `gsQuarantine` and `ssProvisionalAtoms`
2. **Short-term (P1)**: Cap `ktQuarantine` size, fix Datalog escaping, replace `SomeException` catch, add `NOINLINE` pragma
3. **Medium-term (P2)**: Fix sandbox boundary, add strict JSON validation, implement WAL-based persistence
