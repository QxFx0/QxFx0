# QxFx0 Production Vulnerability Audit — Round 3

## 1. Unbounded State Growth (Memory/Serialization Risk)

### ssProvisionalAtoms (L181)
- **File**: `src/QxFx0/Types/State/System.hs:181`
- **Issue**: `[ProvisionalAtom]` with no rotation cap
- **Impact**: OOM in long sessions, JSON serialization latency spikes
- **Fix**: Add bounded append with configurable max size (e.g., 500 atoms)

### ssCalibrationSnapshots (L206)
- **File**: `src/QxFx0/Types/State/System.hs:206`
- **Issue**: `[CalibrationSnapshot]` with no rotation cap
- **Impact**: Unbounded memory growth, slow state persistence
- **Fix**: Implement LRU eviction or max-size cap (e.g., 100 snapshots)

### ssGovernanceHistory (L246)
- **File**: `src/QxFx0/Types/State/System.hs:246`
- **Issue**: `[GovernanceEvent]` append-only with no compaction
- **Impact**: Linear growth in state size, eventual serialization failures
- **Fix**: Add periodic compaction or bounded window retention

### ktQuarantine (KnowledgeTree)
- **File**: `src/QxFx0/Learning/KnowledgeTree.hs:144`
- **Issue**: `[KnowledgeFruit]` with no size limit
- **Impact**: Quarantine grows indefinitely if promotion criteria rarely met
- **Fix**: Cap quarantine size; implement age-based eviction

## 2. Error Handling & Observability Gaps

### SomeException Catch in PGF Linearization
- **File**: `src/QxFx0/Runtime/PGF.hs:96`
- **Issue**: `try @SomeException` catches all exceptions, returns `Left "pgf_exception:..."`
- **Impact**: Destroys stack traces, prevents targeted debugging, masks root causes
- **Fix**: Replace with typed `PGFError` variants preserving context

### unsafePerformIO in GfMap
- **File**: `src/QxFx0/Lexicon/GfMap.hs:93`
- **Issue**: `unsafePerformIO loadCanonicalGfMap` at module level
- **Impact**: Non-deterministic initialization, potential race conditions in concurrent contexts
- **Fix**: Use `NOINLINE` pragma with explicit initialization or `unsafeInterleaveIO`

## 3. Injection & Path Safety

### Datalog Fact Rendering
- **File**: `src/QxFx0/Bridge/Datalog/Support.hs:58-64`
- **Issue**: `escapeSymbol` handles `\`, `"`, `\n`, `\r`, `\t` but not all injection vectors
- **Impact**: Malicious propositions could break Souffle parser boundaries
- **Fix**: Add comprehensive CSV/TSV escaping, validate all atom tag payloads

### Agda Witness Path Validation
- **File**: `src/QxFx0/Bridge/AgdaWitness.hs:74-75, L97-105`
- **Issue**: `isPathWithin` only validates report directory, not individual `awFiles` keys
- **Impact**: Path traversal via crafted file keys in witness map
- **Fix**: Validate each key in `awFiles` against sandbox root before writing

## 4. Boundary Conditions & Logic Errors

### Sandbox Safety Floor
- **File**: `src/QxFx0/Learning/Sandbox.hs:161`
- **Issue**: `projectedConatus < scSafetyFloor cfg` uses `<` not `<=`
- **Impact**: Scores exactly at safety floor incorrectly pass
- **Fix**: Use `<=` for strict inequality or explicit tolerance bands

### JSON Deserialization with Defaults
- **File**: `src/QxFx0/Types/State/System.hs:315-377`
- **Issue**: Heavy use of `.:?` with `.!=` defaults for critical fields
- **Impact**: Missing/renamed fields silently default, masking state corruption
- **Fix**: Add strict validation for required fields, versioned migration checks

### Recovery State Inconsistency
- **File**: `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs:188-193`
- **Issue**: `recoverRuntimeTurnState` applies stale snapshots if original save fails mid-transaction
- **Impact**: Divergent state after recovery, potential data loss
- **Fix**: Implement WAL checkpoints or transactional rollback

## 5. Configuration & Transport

### Transport Fallback Behavior
- **File**: `src/QxFx0/Bridge/ExternalLLM.hs:251-339`
- **Issue**: Invalid env vars set fallback reasons but don't fail-closed
- **Impact**: Silent degradation to mock transport in production
- **Fix**: Require explicit `QXFX0_LLM_TRANSPORT=mock` for non-production use

## Priority Matrix

| Severity | Category | Files |
|----------|----------|-------|
| P0 | Unbounded state growth | System.hs:181,206,246; KnowledgeTree.hs:144 |
| P0 | Recovery inconsistency | Commit.hs:188-193 |
| P1 | Error handling gaps | PGF.hs:96; GfMap.hs:93 |
| P1 | Injection vectors | Support.hs:58-64; AgdaWitness.hs:74-75 |
| P2 | Boundary conditions | Sandbox.hs:161; System.hs:315-377 |
| P2 | Transport fallback | ExternalLLM.hs:251-339 |

## Remediation Steps

1. **Immediate (P0)**: Add bounded rotation to all unbounded state lists
2. **Immediate (P0)**: Implement WAL-based state persistence in Commit.hs
3. **Short-term (P1)**: Replace `SomeException` with typed errors in PGF.hs
4. **Short-term (P1)**: Add `NOINLINE` pragma to `unsafePerformIO` call
5. **Short-term (P1)**: Harden Datalog fact escaping and Agda path validation
6. **Medium-term (P2)**: Fix sandbox boundary condition to strict inequality
7. **Medium-term (P2)**: Add strict JSON schema validation for SystemState
8. **Medium-term (P2)**: Remove implicit mock transport fallback
