# Effects-Interpreter Conatus-Aware Prior — Implementation Specification

**Status**: Design specification (no code changes in this ticket).  
**Scope**: ADR-0007 §4.3 — "An effect refactor (Phase 6) routing every effect through a conatus-aware prior in the interpreter layer."  
**Date**: 2026-05-19.  
**Depends on**: Phase 1–5 already landed (SelfBlanket, Conatus, Adjunction, Right-hemisphere Field, Salience controller). Phase 9–10 (Essence commitment) landed.

---

## 0. Decisions

### 0.1 Problem

The current `PipelineIO` interpreter (`QxFx0.Core.PipelineIO.Internal`) resolves effects in a **fixed per-phase order** determined by the plan type (`PrepareEffectPlan`, `RouteEffectPlan`, `RenderEffectPlan`, `FinalizeCommitPlan`, `FinalizePrecommitPlan`).  Each plan hardcodes which `TurnEffectRequest` constructors to resolve and in what sequence.  This is correct but **conatus-blind**: a session with critically low `ConatusEnergy` (e.g. after a `BlanketViolation` cascade) still waits for `TurnReqEmbedding` and `TurnReqNixGuard` before it can resolve `TurnReqConsciousness` or `TurnReqApiHealth`, even though the latter are cheaper and may be sufficient for a minimal recovery turn.

ADR-0007 §4.3 calls for "routing every effect through a conatus-aware prior in the interpreter layer."  The prior should be a scheduling policy, not a replacement for the plan types: plans still enumerate *which* effects are needed, but the interpreter decides *in what order* they are submitted to the real IO backend, with the option to skip or defer low-urgency effects when conatus is in the erosion zone.

### 0.2 Design principles

1. **Conatus is read-only to the scheduler.**  The prior is a function `ConatusEnergy -> EffectPrior`, not a mutator.  The Conatus functional is owned by `QxFx0.Self.Conatus`; the scheduler only consumes its output.

2. **Plans are still authoritative on *what* to request.**  The `PrepareEffectPlan` etc. types remain.  The scheduler only reorders (and optionally elides) the resolution of individual `TurnEffectRequest` values within a plan.

3. **Determinism.**  Given the same `ConatusEnergy` and the same plan, the scheduling order must be deterministic.  This is a property-test lock (see §3).

4. **Graceful degradation.**  If a scheduled effect fails, the scheduler falls back to the original fixed order for the remaining effects.  The fallback path is always available, so the conatus-aware path is an optimization, not a load-bearing branch.

5. **No new dependencies.**  The scheduler uses only `QxFx0.Self.Conatus` types (already imported by `Effects.hs`) and standard library containers.

### 0.3 Scope boundary

This spec covers:
- The `ConatusPrior` data type and its scoring function.
- The `scheduleEffects` morphism that consumes a plan and produces an ordered list of `(TurnEffectRequest, ConatusPriorityScore)`.
- The modified `resolve*Effects` functions in each pipeline phase that apply the scheduler.
- Property and unit-test regression locks.

This spec **does not** cover:
- Essence-aware weights (ADR-0012 §10 out-of-scope item #4; deferred to a later ADR).
- Automatic effect elision based on conatus threshold (beyond the explicit `Skip` policy described here).
- Parallel / async effect execution (the current interpreter is `IO`-sequential; parallelism is out of scope).

---

## 1. Step-by-step plan

### 1.1 Add `ConatusPrior` to `QxFx0.Core.TurnPipeline.Effects`

New types, exported from `QxFx0.Core.TurnPipeline.Effects`:

```haskell
-- | A scheduling priority score.  Higher = resolve earlier.
--   Invariant: score ≥ 0.
newtype ConatusPriorityScore = ConatusPriorityScore { unConatusPriorityScore :: Double }
  deriving stock (Eq, Show, Ord)
  deriving newtype (Num, Fractional)

-- | Scheduling decision for a single effect request.
data ConatusScheduling
  = ScheduleNow   !ConatusPriorityScore   -- ^ resolve immediately in the reordered sequence
  | ScheduleDefer   !ConatusPriorityScore   -- ^ resolve only if time budget remains after all ScheduleNow effects
  | ScheduleSkip    !ConatusPriorityScore   -- ^ resolve only if conatus is above erosion threshold; otherwise elide
  deriving stock (Eq, Show)

-- | The conatus-aware prior.  Maps a 'ConatusEnergy' and an
--   individual 'TurnEffectRequest' to a scheduling decision.
--   Pure and total.
newtype ConatusPrior = ConatusPrior
  { runConatusPrior :: ConatusEnergy -> TurnEffectRequest -> ConatusScheduling
  }
```

### 1.2 Define `defaultConatusPrior`

`defaultConatusPrior` scores each `TurnEffectRequest` constructor by two axes:

1. **Intrinsic cost** — estimated wall-clock latency / resource consumption.  Empirically ordered:
   - `TurnReqEmbedding`         → highest (remote HTTP or heavy local model)
   - `TurnReqNixGuard`          → high (spawn subprocess)
   - `TurnReqLinearizeClaimAst` → medium (GF linearization, file IO)
   - `TurnReqLinearizeDialogAtoms` → medium
   - `TurnReqConsciousness`     → medium (LLM call)
   - `TurnReqIntuition`         → medium (LLM call)
   - `TurnReqAgdaVerify`        → medium-heavy (Agda type-check)
   - `TurnReqShadow`            → low (Datalog query, cached)
   - `TurnReqApiHealth`         → low (local check)
   - `TurnReqReadEnv`           → negligible
   - `TurnReqCurrentTime`       → negligible
   - `TurnReqRequestId`         → negligible
   - `TurnReqTestMarkOnceFile`  → negligible
   - `TurnReqCheckpoint`        → low (SQLite write)
   - `TurnReqCommitRuntimeState`→ low (SQLite write)
   - `TurnReqSaveState`         → low (SQLite write)
   - `TurnReqRollbackTurnProjections` → low
   - `TurnReqSemanticIntrospectionEnv` → negligible

2. **Conatus-urgency multiplier** — derived from `ConatusEnergy.ceScalar`:
   - `ceScalar ≥ 10` (healthy)    → multiplier = 1.0 (schedule in intrinsic-cost order)
   - `ceScalar ∈ [5, 10)` (warn)   → multiplier = 1.5 (bump cheap effects earlier)
   - `ceScalar ∈ [0, 5)` (erosion) → multiplier = 2.0 + push expensive effects to `ScheduleDefer` or `ScheduleSkip`
   - `ceScalar < 0` (critical)     → multiplier = 3.0; only `TurnReqApiHealth`, `TurnReqReadEnv`, `TurnReqCurrentTime`, `TurnReqRequestId` get `ScheduleNow`; everything else `ScheduleSkip`

The exact thresholds (`10`, `5`, `0`) are tunable via a `ConatusPriorModulation` record (see §1.5), but the defaults are anchored to the `defaultConatusWeights` (`cwViolation = 10.0`) so that one sustained violation drops the scalar by ~10, crossing the critical boundary.

```haskell
defaultConatusPrior :: ConatusPrior
-- implementation omitted in spec; see §2 touchpoint for sketch
```

### 1.3 Modify `PipelineIO` to carry the prior

```haskell
-- In QxFx0.Core.PipelineIO.Internal
data PipelineIO = PipelineIO
  { pioRuntimeMode         :: !PipelineRuntimeMode
  , pioShadowPolicy        :: !ShadowPolicy
  , pioLocalRecoveryPolicy :: !LocalRecoveryPolicy
  , pioInterpreter         :: !TurnEffectInterpreter
  , pioUpdateHistory       :: Text -> Seq Text -> Seq Text
  , pioConatusPrior        :: !ConatusPrior
    -- ^ Phase 6 (ADR-0007): conatus-aware scheduling prior.
    --   Default = 'defaultConatusPrior'.
  }
```

`mkTestPipelineIO` in `QxFx0.Core.PipelineIO.Test` sets `pioConatusPrior = defaultConatusPrior`.

### 1.4 Modify `resolvePrepareEffects` to use the scheduler

Current (`QxFx0.Core.TurnPipeline.Prepare.Resolve:48`):

```haskell
resolvePrepareEffects :: PipelineIO -> PrepareEffectPlan -> IO PrepareEffectResults
-- resolves embedding, nix, consciousness, intuition, api-health in fixed order
```

Proposed:

```haskell
resolvePrepareEffects :: PipelineIO -> PrepareEffectPlan -> ConatusEnergy -> IO PrepareEffectResults
-- 1. Extract the five requests from the plan.
-- 2. Score each with pioConatusPrior applied to the supplied ConatusEnergy.
-- 3. Sort by score descending.
-- 4. Resolve in sorted order, collecting results.
-- 5. If any Skip'd effect was essential for a downstream result
--    (e.g. embedding is required for routing), detect the omission
--    and fall back to fixed-order resolution for the missing slot.
```

The `ConatusEnergy` is already available in `PrepareEffectPlan` via `pepStatic.psConatusEnergy`.

### 1.5 Add `ConatusPriorModulation` for tunability

```haskell
data ConatusPriorModulation = ConatusPriorModulation
  { cpmHealthyThreshold    :: !Double   -- default 10.0
  , cpmWarnThreshold       :: !Double   -- default 5.0
  , cpmCriticalThreshold     :: !Double   -- default 0.0
  , cpmHealthyMultiplier   :: !Double   -- default 1.0
  , cpmWarnMultiplier      :: !Double   -- default 1.5
  , cpmErosionMultiplier   :: !Double   -- default 2.0
  , cpmCriticalMultiplier  :: !Double   -- default 3.0
  }

defaultConatusPriorModulation :: ConatusPriorModulation
```

This mirrors the `EssenceModulation` / `SalienceModulation` pattern.  The modulation lives in `QxFx0.Core.TurnPipeline.Effects` alongside `ConatusPrior`.

### 1.6 Update all phase resolvers

Each phase resolver (`resolveRouteEffects`, `resolveRenderEffects`, `resolveFinalizePrecommit`, `resolveFinalizeCommit`) gains a `ConatusEnergy` argument sourced from the plan/static input.  The scheduling logic is identical: extract requests, score, sort, resolve, fallback.

The fallback path is a pure helper:

```haskell
resolveScheduled
  :: PipelineIO
  -> ConatusEnergy
  -> [TurnEffectRequest]
  -> IO [(TurnEffectRequest, TurnEffectResult)]
-- Returns an association list in the *original* plan order so that
-- downstream consumers (e.g. 'PrepareEffectResults' constructor)
-- do not need to change their field-access patterns.
```

`resolveScheduled` does the conatus-aware reordering internally but always returns results mapped back to the original request order, so the `*EffectResults` constructors stay unchanged.

### 1.7 Thread `ConatusEnergy` through `buildPrepareEffectPlan`

`buildPrepareEffectPlan` in `QxFx0.Core.TurnPipeline.Effects` already computes `conatusEnergy`.  The only change is to expose it to the caller so the resolver can pass it to `resolveScheduled`.  This is already available via `pepStatic.psConatusEnergy`, so no change to `buildPrepareEffectPlan` is needed; only the resolver signatures change.

---

## 2. Touchpoints

### 2.1 Files to modify

| File | Lines (approx) | Change |
|------|----------------|--------|
| `src/QxFx0/Core/TurnPipeline/Effects.hs` | +60 | Add `ConatusPrior`, `ConatusPriorityScore`, `ConatusScheduling`, `ConatusPriorModulation`, `defaultConatusPrior`, `defaultConatusPriorModulation`. |
| `src/QxFx0/Core/PipelineIO/Internal.hs` | +4 | Add `pioConatusPrior` field to `PipelineIO`. |
| `src/QxFx0/Core/PipelineIO/Test.hs` | +1 | Set `pioConatusPrior = defaultConatusPrior` in `mkTestPipelineIO`. |
| `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs` | +15 | Modify `resolvePrepareEffects` signature and body to use `resolveScheduled`. |
| `src/QxFx0/Core/TurnPipeline/Route/Effects.hs` | +15 | Modify `resolveRouteEffects` similarly. |
| `src/QxFx0/Core/TurnPipeline/Route/Render.hs` | +15 | Modify `resolveRenderEffects` similarly. |
| `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs` | +15 | Modify `resolveFinalizePrecommit` similarly. |
| `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs` | +15 | Modify `resolveFinalizeCommit` similarly. |
| `src/QxFx0/Core/TurnPipeline/Protocol.hs` | +10 | Update `prepareTurn`, `planTurn`, `renderTurn`, `finalizeTurn` to thread `ConatusEnergy`. |
| `test/Test/Suite/ConatusPrior.hs` | +120 | New test suite (see §3). |
| `test/TestMain.hs` | +1 | Wire `conatusPriorTests` into meta suite. |

### 2.2 Types that change

- `PipelineIO` — one new field (§1.3).
- `resolvePrepareEffects`, `resolveRouteEffects`, `resolveRenderEffects`, `resolveFinalizePrecommit`, `resolveFinalizeCommit` — new `ConatusEnergy` argument.
- `prepareTurn`, `planTurn`, `renderTurn`, `finalizeTurn` in `Protocol.hs` — thread the energy through.

### 2.3 Types that do **not** change

- `TurnEffectRequest` — 18 constructors enumerated in `Effects.hs:52-71`; no additions or removals.
- `TurnEffectResult` — 18 constructors; unchanged.
- `PrepareEffectPlan`, `RouteEffectPlan`, `RenderEffectPlan`, `FinalizeCommitPlan`, `FinalizePrecommitPlan` — unchanged.
- `PrepareEffectResults`, `RouteEffectResults`, `RenderEffectResults`, `FinalizeCommitResults`, `FinalizePrecommitResults` — unchanged field layout.
- `ConatusEnergy`, `ConatusWeights`, `ConatusGradient` — owned by `QxFx0.Self.Conatus`; read-only.

### 2.4 Implementation sketch for `defaultConatusPrior`

```haskell
defaultConatusPrior :: ConatusPrior
defaultConatusPrior = ConatusPrior $ \ce req ->
  let base = intrinsicCost req
      mul  = conatusMultiplier (ceScalar ce) defaultConatusPriorModulation
      score = ConatusPriorityScore (base * mul)
  in classify score (ceScalar ce) defaultConatusPriorModulation
  where
    intrinsicCost = \case
      TurnReqEmbedding{}         -> 10.0
      TurnReqNixGuard{}           -> 8.0
      TurnReqConsciousness{}      -> 6.0
      TurnReqIntuition{}          -> 6.0
      TurnReqAgdaVerify          -> 5.0
      TurnReqLinearizeClaimAst{} -> 4.0
      TurnReqLinearizeDialogAtoms{} -> 4.0
      TurnReqShadow{}             -> 2.0
      TurnReqApiHealth            -> 1.0
      TurnReqCommitRuntimeState{} -> 1.0
      TurnReqSaveState{}          -> 1.0
      TurnReqRollbackTurnProjections{} -> 1.0
      TurnReqCheckpoint{}         -> 0.5
      _                           -> 0.1  -- env, time, id, test marks, introspection

    conatusMultiplier s mod
      | s >= cpmHealthyThreshold mod   = cpmHealthyMultiplier mod
      | s >= cpmWarnThreshold mod      = cpmWarnMultiplier mod
      | s >= cpmCriticalThreshold mod  = cpmErosionMultiplier mod
      | otherwise                      = cpmCriticalMultiplier mod

    classify score s mod
      | s < cpmCriticalThreshold mod && score > 2.0 = ScheduleSkip score
      | s < cpmWarnThreshold mod    && score > 5.0 = ScheduleDefer score
      | otherwise                                  = ScheduleNow score
```

This sketch is illustrative; the exact threshold logic in `classify` may need tuning during implementation.  The spec locks only the determinism property (§3.1), not the exact numeric thresholds.

---

## 3. Acceptance

### 3.1 Regression locks

| Lock | Suite | What it guards |
|------|-------|----------------|
| P1 | `Test.Suite.ConatusPrior` | `defaultConatusPrior` is deterministic: same `ConatusEnergy` + same `TurnEffectRequest` → same `ConatusScheduling`. |
| P2 | `Test.Suite.ConatusPrior` | `resolveScheduled` returns results in *original* request order even when the scheduler reordered resolution internally. |
| P3 | `Test.Suite.ConatusPrior` | Under critical `ConatusEnergy` (`ceScalar < 0`), all expensive effects (`TurnReqEmbedding`, `TurnReqNixGuard`, `TurnReqConsciousness`, `TurnReqIntuition`) receive `ScheduleSkip`. |
| P4 | `Test.Suite.ConatusPrior` | Under healthy `ConatusEnergy` (`ceScalar ≥ 10`), `resolveScheduled` resolves all requests (no skips). |
| P5 | `Test.Suite.ConatusPrior` | `ConatusPriorModulation` tunability: changing `cpmCriticalThreshold` from `0.0` to `-5.0` shifts the classification boundary for a `ceScalar = -2.0` case. |

### 3.2 Test count delta

- New suite: `Test.Suite.ConatusPrior` — 5 tests (P1–P5).
- Existing suites: zero breakage expected because all `*EffectResults` constructors keep their field layout; only the resolution order changes.
- Target delta: **+5 tests**.

### 3.3 No-breakage verification

After implementation:

```bash
cabal test qxfx0-test --test-show-details=streaming
# Expect: current count + 5 PASS, zero new failures.
```

### 3.4 Performance smoke test

```bash
# Run the long-session corpus (30 turns) and verify total wall-clock
# does not regress by more than 10% under the default prior.
cabal test qxfx0-test-integration --test-show-details=streaming
```

The conatus-aware scheduler is an optimization; it must not pessimise the common case.

---

## 4. Verification commands

### 4.1 Compile after type changes

```bash
cabal build all -j1 +RTS -M8G -RTS
```

### 4.2 Property suite

```bash
cabal test qxfx0-test-property --test-show-details=streaming
```

### 4.3 Full meta suite

```bash
cabal test qxfx0-test --test-show-details=streaming
# Target: (current + 5) / (current + 5) PASS.
```

### 4.4 Integration suite (performance baseline)

```bash
cabal test qxfx0-test-integration --test-show-details=streaming
```

---

## 5. Out of scope

1. **Essence-aware weights.**  ADR-0012 §10 lists "Essence-aware Conatus weights" as out of scope.  This spec does not propose tuning `ConatusWeights` to the committed `EssenceMode`.  That requires a separate ADR once production essence data exists.

2. **Automatic effect elision beyond Skip.**  The `ScheduleSkip` policy explicitly marks an effect as skippable, but the downstream plan constructor must still handle the missing result (e.g. by using a default or cached value).  Designing per-effect fallback defaults is deferred.

3. **Parallel effect execution.**  The current `PipelineIO` is a single `TurnEffectRequest -> IO TurnEffectResult` function.  This spec does not change that to `Async`-based concurrency.  Reordering is the only concurrency primitive introduced.

4. **Dynamic threshold calibration.**  The `cpm*Threshold` values in `ConatusPriorModulation` are hand-set against `defaultConatusWeights`.  Empirical calibration against production trace corpora is deferred to a later roadmap item (analogous to Phase 10 §4 calibration).

5. **Conatus gradient as scheduling signal.**  The `ConatusGradient` (which axis to recover) is not used by the scheduler; only the scalar `ceScalar` is.  Using gradient direction to prioritise, e.g., `TurnReqEmbedding` when `cgMorphology` is the largest component, is a natural extension but out of scope.

---

## Appendix: Full `TurnEffectRequest` enumeration

For completeness, the 18 constructors from `QxFx0.Core.TurnPipeline.Effects` that the scheduler must handle:

1. `TurnReqEmbedding !Text`
2. `TurnReqNixGuard !Text !Double !Double`
3. `TurnReqConsciousness !SemanticInput !Double !Double !ConatusEnergy`
4. `TurnReqIntuition !Text !Double !Double !Int !ConatusEnergy`
5. `TurnReqApiHealth`
6. `TurnReqShadow !CanonicalMoveFamily !IllocutionaryForce ![AtomTag]`
7. `TurnReqAgdaVerify`
8. `TurnReqCurrentTime`
9. `TurnReqRequestId`
10. `TurnReqReadEnv !Text`
11. `TurnReqTestMarkOnceFile !Text`
12. `TurnReqSemanticIntrospectionEnv`
13. `TurnReqCommitRuntimeState !ConsciousnessLoop !IntuitiveState !ResponseObservation`
14. `TurnReqSaveState !SystemState !Text !(Maybe TurnProjection)`
15. `TurnReqRollbackTurnProjections !Text !Int`
16. `TurnReqCheckpoint !Int`
17. `TurnReqLinearizeClaimAst !(Maybe FilePath) !Text !ClaimAst`
18. `TurnReqLinearizeDialogAtoms !(Maybe FilePath) !Text !DialogAtoms`

The scheduler treats each constructor uniformly by pattern-matching on the outer constructor; inner payload values do not affect `intrinsicCost` in the default prior.
