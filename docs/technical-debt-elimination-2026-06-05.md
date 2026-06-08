# Technical Debt Elimination — 2026-06-05

> ## ⚠️ Corrections (2026-06-06)
>
> As originally written, this report overstated several impacts. The originals
> are corrected in place below; this block is the honest ledger. Verifier
> convention: every impact claim cites a `file:line` or a test.
>
> - **P0-3 "catches typos at build time" — FALSE.** `propositionTypeFromText =
>   readMaybe . T.unpack` (`Semantic/Proposition/Types.hs:108`) is a *runtime*
>   parse: a bad string yields `Nothing` silently, not a build error. The
>   behaviour-gating dispatch sites are still string comparisons (`== "SelfStateQ"`
>   etc. — 5 in `Core/`+`Learning/`). The typed enum landed at the render/
>   diagnostic edge, not the gate. Real gain: a `read`→`readMaybe` safety fix
>   (removes a partial parse). Not compile-time typo safety.
> - **P0-1 "enables graceful degradation" — UNPROVEN.** Both sites use `throw`
>   (not `throwIO`) in *pure* code (`Finalize/State.hs:584,630`) — an imprecise
>   exception with the same lazy-eval timing hazard as the `error` it replaced.
>   Real gain: a *typed payload* (better diagnostics). No catch handler makes it
>   "graceful."
> - **P0-2 / "unsafePerformIO eliminated" — ONE OF SEVERAL.** One instance moved
>   to IO (`logTraceAnomalies`). Six call-sites remain: `Lexicon/GfMap.hs:99`,
>   `Core/PipelineIO/Test.hs:79-80`, `Render/Authority.hs:82`,
>   `Runtime/PGFStatus.hs:26`, `Runtime/PGF.hs`, `Runtime/Health.hs`. Most are
>   accepted load-once-CAF idiom; `Render/Authority.hs:82` wraps a parse on the
>   render path.
> - **"~2000 lines removed" — UNREALIZED; the Core dedup is line-neutral.** P1-1
>   has since been **completed** (18/18 clones, commits `eee9a42` + `b03cdf9`)
>   under an equivalence lock (`Test.Suite.AdmissionEquivalence`) — net **+30**
>   lines across the 15 Core modules. The win is single-source-of-truth for the
>   admission *logic*, not line count. The ~2000 figure only materialises from
>   Phase 2 (Types templates), which is **not started**.
> - **"No behavioral changes introduced" — not proven at the time.** The P0-3
>   render-path change had no equivalence test when written. P1-1's later
>   conversions ARE behaviour-locked. The determinism leak this report did not
>   mention (legitimacy consumed a live `apiHealthy` probe) was fixed separately
>   (`a1dd66c` / `f0e229f`).

## Executive Summary

A technical-debt pass across QxFx0 (see the Corrections block above for what
landed fully vs. partially):
- **14 tasks** across 4 priority levels (P0-P3)
- **~15 hours** of work
- **39 files** modified (+489/-214 lines)
- **2 git commits** with structured documentation

## Completed Work

### P0 — Critical Safety Defects (5h)

**P0-1: Replace unsafe error calls with typed exceptions**
- Added `StateInvariantViolation` constructor to `QxFx0Exception`
- Replaced 2 `error` calls in `buildNextSystemState` with `throw`
- Updated exception rendering in `ExceptionPolicy.hs`
- **Impact**: typed payload instead of bare `error` (better diagnostics). NOTE:
  the 2 sites use `throw` in *pure* code (`Finalize/State.hs:584,630`) — still an
  imprecise exception, not graceful degradation (no catch handler).

**P0-2: Remove unsafePerformIO from pure function**
- Moved `logTraceAnomalies` to IO boundary in `buildFinalizePrecommit`
- Changed signature from pure to `IO FinalizePrecommitBundle`
- Updated 8 call sites (Orchestrate, Protocol, test fixtures)
- **Impact**: Restores referential transparency, fixes lazy evaluation issues

**P0-3: Replace string-based proposition dispatch with typed enum**
- Introduced `propositionTypeFromText` (`= readMaybe . T.unpack`) at the
  render/diagnostic edge
- **Impact**: `read`→`readMaybe` removes a partial parse. NOTE: NOT compile-time
  typo safety — a bad string yields `Nothing` silently at runtime; the
  behaviour-gating sites remain string compares (`== "SelfStateQ"` etc.).

### P1 — Dead Code & Duplication (3h)

**P1-2a: Remove fmarSelectFamilyRescue**
- Removed from `Self.FamilyTargets` exports
- Deleted corresponding tests
- **Impact**: -10 lines, cleaner API surface

**P1-2b: Remove dead exports**
- Removed `renderTurnOutput` and `routeTurnPlan` from `TurnPipeline.Route`
- **Impact**: Cleaner module interface

**P1-1: Generic Admission Foundation (Phase 1 of 3)**
- Created `QxFx0.Core.GenericPropositionAdmission` (92 lines)
- Introduced `PropositionAdmissionConfig` for parameterized admission
- Refactored `PropositionContactAdmission` as proof-of-concept
- Documented completion plan in `docs/P1-1-REFACTORING-PLAN.md`
- **Impact**: single-source-of-truth for admission logic. NOTE: Core conversions
  are ~line-neutral (the ~2000-line figure is Phase-2/Types-templates only).
  Since **completed** 18/18 under equivalence lock (`eee9a42`, `b03cdf9`).

### P3 — Code Quality (3h)

**P3-1: Fix orphan instance**
- Moved `Hashable TurnSeq` to `Types.State.SemanticCommitment`
- **Impact**: Eliminates -Worphans warning

**P3-2: Add deriving strategies**
- Added `{-# LANGUAGE DerivingStrategies #-}` to 5 files
- Changed `deriving (...)` to `deriving stock (...)`
- **Impact**: Eliminates -Wmissing-deriving-strategies warnings

**P3-3: Remove unused imports**
- Cleaned 7 unused imports from 6 files
- **Impact**: Eliminates -Wunused-imports warnings

**P3-4: Fix test failures for promoted flags**
- Updated tests for `episodicRecallActive` and `contentSalienceActive`
- Updated module documentation (3 files)
- **Impact**: 16 → 14 test failures (2 fixed)

**P3-5: Resolve fieldDelta name collision**
- Renamed to `maxFieldHeuristicsDelta` in `Finalize/State.hs`
- **Impact**: Eliminates shadowing confusion

### P2 — Documentation & Consistency (4h)

**P2-1: Sync AGENTS.md with code**
- Updated 3 flag descriptions (family divergence, promoted flags)
- Corrected default values and semantics
- **Impact**: Documentation matches reality

**P2-2: Resolve familyDivergenceEnabled collision**
- Split into `salienceGuardDivergenceEnabled` (Cascade.hs)
- And `reconcileFamilyDivergence` (TurnRouting.hs)
- **Impact**: Eliminates name shadowing, clarifies semantics

**P2-3: holisticFormalContextSplitActive**
- ✅ Completed earlier (flag activated)

## Git Commits

```
e9dec67 docs: update CHANGELOG for technical debt elimination
c83a48f refactor(P0): eliminate critical safety defects
```

## Files Modified (39 total)

### Core Changes
- `src/QxFx0/ExceptionPolicy.hs` — Added StateInvariantViolation
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` — Replaced error with throw
- `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs` — IO boundary for logging
- `src/QxFx0/Core/PropositionAdmission.hs` — Typed dispatch
- `src/QxFx0/Core/GenericPropositionAdmission.hs` — NEW: Generic admission
- `src/QxFx0/Core/PropositionContactAdmission.hs` — Refactored example
- `src/QxFx0/Core/TurnRouting/Cascade.hs` — Renamed flag
- `src/QxFx0/Core/TurnRouting.hs` — Renamed flag

### Types & Infrastructure
- `src/QxFx0/Types/State/SemanticCommitment.hs` — Moved Hashable instance
- `qxfx0.cabal` — Added GenericPropositionAdmission to exposed-modules

### Documentation
- `AGENTS.md` — Synchronized with code
- `CHANGELOG.md` — Added comprehensive entry
- `docs/P1-1-REFACTORING-PLAN.md` — NEW: Completion plan

### Tests (8 files)
- Updated for IO boundary changes
- Fixed promoted flag expectations
- Removed dead code tests

## Metrics

### Code Changes
- **Lines added**: +489
- **Lines removed**: -214
- **Net change**: +275 (mostly new generic module + documentation)
- **Files modified**: 39
- **New files**: 2 (GenericPropositionAdmission.hs, P1-1-REFACTORING-PLAN.md)

### Quality Improvements
- **Compiler warnings eliminated**: ~15 (unused imports, deriving strategies, orphans)
- **Test failures fixed**: 2 (16 → 14)
- **Critical defects addressed**: 3, each partial (see Corrections): `error`→typed
  `throw` (still imprecise in pure code); 1 of 6 `unsafePerformIO` moved to IO;
  string dispatch typed at the edge only (gating sites unchanged)
- **Name collisions resolved**: 2 (fieldDelta, familyDivergenceEnabled)
- **Dead code removed**: 2 exports + 1 function

### Future Potential (P1-1 Phase 2 only)
- P1-1 **Core conversions are done** (18/18, line-neutral).
- Remaining is **Phase 2** (Types-module templates via TH): the only source of
  the ~1460-2120 line reduction. Not started; ~2h estimated.

## Build Status

✅ **Compilation**: Successful
✅ **Test suite**: 14 failures (down from 16, remaining unrelated to this work)
🟡 **Type safety**: typed enum at render edge; gating dispatch still string-based
🟡 **Memory safety**: 1 of 6 `unsafePerformIO` moved to IO; rest remain
🟡 **Exception safety**: typed payload, but `throw` still imprecise in pure code

## Next Steps

### Immediate (Optional)
1. ~~Apply generic pattern to remaining Core modules~~ — **done** (18/18, `b03cdf9`)
2. P1-1 Phase 2: Types-module templates via Template Haskell (~2h) — the only
   step that yields the ~2000-line reduction
3. Promote the P0 items from partial to real: type the gating dispatch (not just
   the edge); `throwIO` in IO instead of `throw` in pure; decide on the 6
   remaining `unsafePerformIO`

### Long-term
1. Address remaining 14 test failures (unrelated to this work)
2. Continue architectural improvements per roadmap
3. Monitor for regression in refactored areas

## References

- **Original ТЗ**: Technical debt specification (Russian)
- **Completion Plan**: `docs/P1-1-REFACTORING-PLAN.md`
- **Changelog**: `CHANGELOG.md` (Unreleased section)
- **Operator Notes**: `AGENTS.md` (updated)

## Conclusion

Addressed technical debt across safety, code quality, and documentation. The
P3 code-quality items (warnings, orphans, collisions, dead code) landed fully;
the P0 safety items landed partially (see Corrections). Net for the project:
- Safer exception handling
- Cleaner code (no orphans, unused imports, or name collisions)
- Synchronized documentation
- Single-source-of-truth for admission logic (P1-1 since completed 18/18,
  line-neutral; the ~2000-line reduction is Phase-2-only, not started)

Changes are backward-compatible. Behavioural equivalence is *proven* only where a
test locks it (P1-1 via `Test.Suite.AdmissionEquivalence`); the P0 changes had no
equivalence test when written. See the Corrections block at the top.