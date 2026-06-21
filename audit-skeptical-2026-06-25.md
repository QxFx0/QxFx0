# Skeptical Audit — 2026-06-25

## Methodology
Verified every claim against actual code. No reliance on documentation or prior audit conclusions without code-level confirmation.

## Critical Findings

### 1. DECORATIVE GATE IN PRODUCTION PATH (CONFIRMED BUG)
**File:** `src/QxFx0/Semantic/Content/PathFinder.hs:263-289`

`composeDefinition` (called from `Render/Dialogue.hs:1860` — the production path) computes `_gateVerdict = validatePath combinedProof` but **discards the result**. The `GeneratedSurface` is returned regardless of whether the gate verdict passes or fails.

A parallel function `composeDefinitionWithGates` (line 404) **does** enforce gates (filters paths by `gvOverall`), is tested in `GeneratedPredicateGate.hs`, but is **never called from production code**.

**This is the Representation–Execution Gap (L3) in miniature:** the gate-enforcing version exists in tests, the non-enforcing version runs in production.

**Fix:** Replace `composeDefinition` call in `Dialogue.hs:1860` with gate-enforcing logic, or make `composeDefinition` itself check `gvOverall combinedVerdict` and return `GeneratedSurface "" [] []` on failure.

### 2. NIXGUARD FAIL-OPEN BY DEFAULT (CONFIRMED)
**File:** `src/QxFx0/Core/EvidenceAdmissibility.hs:44-48`

`isGovernedEvidenceMode` reads env var `QXFX0_GOVERNED_EVIDENCE`, defaults to `False`. When guard returns `Unavailable`:
- Normal mode (default): `EvidenceDegradedGuardUnavailable` — runtime continues (fail-OPEN)
- Governed mode (env var=1): `EvidenceInadmissible` — caller should fail-closed

**The fail-closed mode is opt-in via env var.** In default deployment, unavailable guards allow degraded evidence through.

`runPipelineNixCheck` (Operations.hs:155) does return `Blocked` on internal error — that part is fail-closed. But the `Unavailable` path (guard not reachable) is fail-open by default.

### 3. NO -Werror (CONFIRMED)
**File:** `qxfx0.cabal:37`

GHC options: `-Wall -Wcompat -Wincomplete-uni-patterns -Wmissing-deriving-strategies -Wno-unticked-promoted-constructors`

No `-Werror`. Redundant patterns (dead code paths) compile silently. Prior memory mentioned 207 redundant patterns — could not verify warning count due to cabal caching issues, but the flag absence is confirmed.

## Corrections to Prior Memory

| Memory claim | Actual state | 
|---|---|
| SystemState ~85 fields | **44 fields** (Types/State/System.hs:195) |
| Bayesian not wired into production | **Partially wired**: `bayesianBeliefNudge` in Intuition.hs:136 feeds capped (0.08) input to flash detection |
| Round-trip coverage 11.8% (16/136) | **~28%**: 80 `assertRoundTrip` calls, 140 ToJSON + 147 FromJSON instances |
| 299 compiler warnings | Could not verify (cabal cache prevents clean rebuild within timeout) |

## Persistent Issues (Unchanged since prior audits)

1. **unsafePerformIO: 7+ real uses** — PGFStatus.hs, GfMap.hs, ConfigLoad.hs, PipelineIO/Test.hs, Runtime/PGF.hs, Runtime/AuthorityParse.hs. All are startup/cache patterns with NOINLINE, but still violate referential transparency.

2. **T.pack . show: 40 occurrences** — structured information destroyed to string at boundaries.

3. **RussianQuality tests: shallow** — only check non-empty/non-collapse. No semantic coherence, grammar, or topic-relevance assertions. System can produce nonsensical output and all tests pass.

4. **GameTheory confirmed NOT wired** — no imports outside `Learning/` module. Dead code in production terms.

5. **SystemState = 44 fields** — still a god-record mixing all layers (Dialogue, Identity, Semantic, Self, Learning, Governance, etc.). Root cause of circular deps persists.

## New Finding: Dual-Function Pattern

The `composeDefinition` vs `composeDefinitionWithGates` split is a newly identified systemic pattern: **gate-enforcing code exists in tests but non-enforcing code runs in production**. This should be checked across other safety mechanisms (shadow veto, guardrails, admission gates).

## Test Status
- 100 test files, 1161 cases
- Fast tests: passing (405/1161 tried in partial run, 0 errors, 0 failures)
- Tests verify structure (non-empty, type correctness) not substance (semantic quality, end-to-end enforcement)

## Priority Actions (unchanged from prior audit, now verified)
1. **composeDefinition**: Wire gate enforcement into production path
2. **NixGuard**: Make governed-evidence mode default (fail-closed), or at minimum document the fail-open default
3. **Enable -Werror** for redundant patterns at minimum
4. **Content quality gate**: Add semantic coherence tests beyond non-empty checks
5. **Audit other safety mechanisms** for the dual-function pattern (test-enforcing, production-not-enforcing)

## Meta-Assessment

The L3 meta-pathology (Representation–Execution Gap) remains the correct diagnostic frame. The system continues to build safety mechanisms and test them in isolation while production paths bypass them. The `composeDefinition` finding is a perfect example: the fix was built (`composeDefinitionWithGates`), tested, and then never connected to the production call site.

Phase 2 of the roadmap remains effectively unstarted. The 3 priority fixes identified in the prior audit are all confirmed present and unaddressed.