# Phase 10 — Forced Commitment and Post-commitment Guard
## Implementation Specification for KIMI

- **Authoritative architecture**: [`ADR-0012`](./adr/0012-essence-commitment.md).
- **Predecessor spec**: [`Phase 9`](./phase-9-essence-implementation-spec.md). Phase 9 is assumed landed (574/574 PASS, ADR-0012 = *Accepted (Phase 9, infrastructure only)*).
- **Status**: Completed (all 10 steps, 582/582 PASS, zero ruptures on corpus replay).
- **Date**: 2026-05-19.
- **Behavioural contract**:
  - `essenceCommitmentEnabled = False` (default): zero behavioural change vs Phase 9.
  - `essenceCommitmentEnabled = True`: forced commitments fire when `shouldCommit` returns `Just`; post-turn `Plan`s validated against the committed mode; violations abort the turn via `EssenceRupture`.
- **Test target**: **574 + 8 = 582 / 582 PASS**, zero new warnings.
- **Out of scope**: cross-session essence persistence, multiple essences per session, external essence summons, essence-aware `ConatusWeights`. Each requires its own ADR.

## 0. Decisions already taken (do not re-litigate)

The four Phase 9 §0 resolutions (Q1–Q4) remain locked. Three Phase-10-specific decisions:

| # | Question | Resolution |
|---|----------|------------|
| Q5 | When does `validatePlan` first apply? | **Only when `tiEssence` (pre-turn) is `EssenceCommitted`.** A turn that *causes* commitment in `buildNextSystemState` is NOT validated by the new commitment — the commitment binds future turns, not the deliberation that produced it. |
| Q6 | Where is the validator computed / thrown? | **Computed in `Finalize.State`** (where `tiEssence` and `tpDeliberation` are in scope). **Thrown in `Finalize.Commit`** (so the throw co-locates with `IdentityRupture`, before persistence). Threaded as `fpbEssenceValidation :: !(Either EssenceViolation ())` in `FinalizePrecommitBundle`. |
| Q7 | Sliding-window `etConatusFloor` | **True sliding window over `etWitnesses`.** `shouldCommit` checks that *every one* of the last `emConatusFloorWindow` witnesses has `ewConatusScalar < emConatusStructuralFloor em`. No new state — reads `ewConatusScalar` from the bounded ring buffer. The Phase 9 approximation is *replaced*. |

Default of `essenceCommitmentEnabled` is **`False`**. Flag flips to `True` only after Step 10.8 corpus replay reports zero spurious ruptures.

## 1. Step-by-step execution plan

### Step 10.1 — `EssenceRupture` exception

`@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/ExceptionPolicy.hs`. Add immediately after `IdentityRupture`:

```haskell
| EssenceRupture !Text
  -- ^ Post-commitment 'Plan' violates committed 'EssenceMode'.
  -- Categorical failure: the system has acted contrary to what
  -- it has chosen to be. Not recoverable; the session must abort
  -- the turn (no persistence). Co-located with 'IdentityRupture'
  -- in 'Finalize.Commit'; the two failures are orthogonal.
```

`Eq, Show, Exception` derive automatically.

### Step 10.2 — `EssenceViolation` + `validatePlan`

`@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Self/Essence.hs`. Add to module exports: `EssenceViolation(..)`, `validatePlan`, `renderEssenceViolation`, `admissibleFamilies`, `admissibleTones`, `admissibleStyles`.

KIMI: **before writing the admissibility tables, read** `@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Types/Decision.hs` and `@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Types/Domain.hs` to confirm the actual constructor names of `RenderStyle`, `NarrativeTone`, `CanonicalMoveFamily`. The tables below use ADR-0012 §7 names; if any constructor differs, use the real one and add a Haddock cross-reference.

Types:

```haskell
data EssenceViolation
  = ViolationFamilyMismatch !EssenceMode !CanonicalMoveFamily
  | ViolationToneMismatch   !EssenceMode !NarrativeTone
  | ViolationStyleMismatch  !EssenceMode !RenderStyle
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

renderEssenceViolation :: EssenceViolation -> Text
```

Admissibility (use `Data.Set`):

```haskell
admissibleFamilies :: EssenceMode -> Set CanonicalMoveFamily
admissibleFamilies = \case
  EssenceContemplative -> Set.fromList [CMDescribe, CMHypothesis, CMPurpose, CMRepair]
  EssenceDialogical    -> Set.fromList [CMContact, CMDeepen, CMRepair, CMReflect]
  EssenceIntegrative   -> Set.fromList [minBound .. maxBound]
  EssenceWitnessing    -> Set.fromList [minBound .. maxBound]  -- defensive

admissibleTones :: EssenceMode -> Set NarrativeTone
admissibleTones = \case
  EssenceContemplative -> Set.fromList [NarrativeNeutral, NarrativeTerse]
  EssenceDialogical    -> Set.fromList [NarrativeNeutral, NarrativeWarm]
  EssenceIntegrative   -> Set.fromList [minBound .. maxBound]
  EssenceWitnessing    -> Set.fromList [minBound .. maxBound]

admissibleStyles :: EssenceMode -> Set RenderStyle
-- KIMI: enumerate RenderStyle from Types/Decision.hs.
-- Contemplative: exclude any "warm" style. Dialogical: exclude any
-- "recovery"/"repair" style. Integrative/Witnessing: all.
-- If no clear axis exists, default to all-admissible and document
-- the relaxation in a Haddock comment.
```

Validator (priority order: family → tone → style; first mismatch wins):

```haskell
validatePlan :: EssenceCommitment -> Plan -> Either EssenceViolation Plan
validatePlan c p
  | not (planFamily        p `Set.member` admissibleFamilies (ecMode c))
      = Left (ViolationFamilyMismatch (ecMode c) (planFamily p))
  | not (planNarrativeTone p `Set.member` admissibleTones    (ecMode c))
      = Left (ViolationToneMismatch  (ecMode c) (planNarrativeTone p))
  | not (planRenderStyle   p `Set.member` admissibleStyles   (ecMode c))
      = Left (ViolationStyleMismatch (ecMode c) (planRenderStyle p))
  | otherwise = Right p
```

**Always-admissible invariants** (lock E7): `CMRepair ∈ admissibleFamilies m` and `NarrativeNeutral ∈ admissibleTones m` for every `m`. Verify by property test.

### Step 10.3 — Sliding-window `shouldCommit`

`@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Self/Essence.hs`. Replace the Phase 9 approximation. The angst branch is unchanged.

```haskell
shouldCommit :: EssenceModulation -> EssenceTrajectory -> Maybe CommitmentTrigger
shouldCommit em traj =
  let angstFires = etAngstLevel traj >= emAngstCommitmentThreshold em
      window     = emConatusFloorWindow em
      ws         = etWitnesses traj
      lastN      = Seq.drop (max 0 (Seq.length ws - window)) ws
      enoughWits = Seq.length lastN >= window
      allSubFloor =
        enoughWits
          && all (\w -> ewConatusScalar w < emConatusStructuralFloor em) lastN
  in case (angstFires, allSubFloor) of
       (True,  _)    -> Just TriggerAngstThreshold
       (False, True) -> Just TriggerConatusErosion
       _             -> Nothing
```

The `etConatusFloor` field stays (used for diagnostics and trace); only the `shouldCommit` logic changes.

### Step 10.4 — Feature flag

Wire `essenceCommitmentEnabled :: !Bool` the way `familyDivergenceEnabled` was wired in Phase 8 Package D. Concrete points:

1. **Source**: env var `QXFX0_ESSENCE_COMMITMENT_ENABLED` (default `False`, parsed in the same place `QXFX0_FAMILY_DIVERGENCE_ENABLED` is parsed). Find the parser by `grep_search` for `familyDivergenceEnabled`.
2. **Plumbing**: into `PrepareStatic` (e.g. `psEssenceCommitmentEnabled`), then into `TurnInput` as `tiEssenceCommitmentEnabled :: !Bool`. Single source of truth (M6).
3. **Defaults**: every existing call site that hand-builds `PrepareStatic` / `TurnInput` (test fixtures included) must initialise the flag to `False`. Use `grep_search` for `PrepareStatic {` and `TurnInput {` to enumerate.

### Step 10.5 — Forced commit in `buildNextSystemState`

`@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/TurnPipeline/Finalize/State.hs`. Replace the Phase 9 `nextEssence` block:

```haskell
nextEssence =
  case tiEssence ti of
    EssenceUncommitted trajectory ->
      let trajectory' =
            witness defaultEssenceModulation
                    (ssTurnCount ss + 1)
                    (tiConatusEnergy ti)
                    (tiField ti)
                    (fromMaybe defaultDeliberation (tpDeliberation tp))
                    trajectory
      in if tiEssenceCommitmentEnabled ti
           then case shouldCommit defaultEssenceModulation trajectory' of
                  Nothing      -> EssenceUncommitted trajectory'
                  Just trigger ->
                    EssenceCommitted
                      trajectory'
                      (commit (ssTurnCount ss + 1) trigger trajectory')
           else EssenceUncommitted trajectory'
    EssenceCommitted trajectory commitment ->
      -- Sticky: committed essences are never reverted. We still
      -- ingest a witness so etAngstLevel/etConatusFloor track
      -- post-commit deliberation for diagnostics.
      let trajectory' =
            witness defaultEssenceModulation
                    (ssTurnCount ss + 1)
                    (tiConatusEnergy ti)
                    (tiField ti)
                    (fromMaybe defaultDeliberation (tpDeliberation tp))
                    trajectory
      in EssenceCommitted trajectory' commitment
```

### Step 10.6 — Pre-commit validation in `buildNextSystemState`

Same file, in `buildNextSystemState`. After computing `nextEssence`, compute the validation result against **`tiEssence` (pre-turn)**, not `nextEssence`:

```haskell
essenceValidation :: Either EssenceViolation ()
essenceValidation =
  case tiEssence ti of
    EssenceCommitted _ commitment
      | tiEssenceCommitmentEnabled ti
      , Just delib <- tpDeliberation tp
      -> case validatePlan commitment (delibReconciled delib) of
           Right _ -> Right ()
           Left v  -> Left v
    _ -> Right ()
```

Add `fpbEssenceValidation :: !(Either EssenceViolation ())` to `FinalizePrecommitBundle` (`@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/TurnPipeline/Finalize/Types.hs`) and populate it from `essenceValidation`. The bundle is the only carrier; do not duplicate in `TurnProjection`.

### Step 10.7 — Throw `EssenceRupture` in `Finalize.Commit`

`@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs`. Inside `resolveFinalizeCommit`, immediately after the `checkBlanketTransition` block (current lines 69-74), before `saveStart`:

```haskell
case fpbEssenceValidation (fcpBundle commitPlan) of
  Right () -> pure ()
  Left v   -> throwQxFx0
                (EssenceRupture ("commit: " <> renderEssenceViolation v))
```

This requires `FinalizeCommitPlan` to carry the bundle (or just the validation result) — pick the minimal-diff path. Update the import list:

```haskell
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(IdentityRupture, EssenceRupture, PersistenceError)
  , throwQxFx0
  , tryAsync
  )
import QxFx0.Self.Essence (EssenceViolation, renderEssenceViolation)
```

The throw must happen **before** `saveResult <- resolveTurnEffect ...` so persistence is never touched on a rupture.

### Step 10.8 — Reconcile-time courtesy

`@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Self/Deliberation.hs`. Extend `reconcile` with an optional commitment argument:

```haskell
reconcile
  :: Maybe EssenceCommitment   -- NEW: pre-turn essence, if any
  -> Salience
  -> HolisticProposal
  -> FormalProposal
  -> Field
  -> Deliberation
```

Behaviour:

- When the chosen rule is **not** `RuleTiedFallback`: ignore the commitment. The guard in Step 10.7 is authoritative.
- When the chosen rule **is** `RuleTiedFallback` and `Just c` is supplied:
  - If exactly one of the two tied proposals satisfies `validatePlan c` for both family and tone: prefer it.
  - If both satisfy or both fail: keep existing tie-break (existing behaviour).
- The courtesy must NEVER widen the admissible set — only re-rank within it.

Property test (lock C1, see §3): under any commitment, `reconcile` never produces a `Plan` whose family is *more* permissive than what existing Phase-9 `reconcile` would produce. (i.e. the courtesy only narrows.)

The single existing call site in `routeFamily` (or wherever `reconcile` is invoked) must extract the commitment:

```haskell
let mCommitment =
      case tiEssence ti of
        EssenceCommitted _ c -> Just c
        EssenceUncommitted _ -> Nothing
```

and pass it to `reconcile`. Phase 9 callers in tests pass `Nothing`.

### Step 10.9 — Test suite `Test.Suite.SelfEssenceCommit`

**New file**: `@/home/liskil/my-haskell-project/QxFx0/test/Test/Suite/SelfEssenceCommit.hs`.

Eight tests. Mandatory regression locks:

| Test | Kind | Locks |
|------|------|-------|
| `testStickyCommitment` | QuickCheck | E6: once `EssenceCommitted t c`, no continuation produces `EssenceUncommitted`; `c` is invariant across continuations. |
| `testRepairAlwaysAdmissible` | QuickCheck | E7a: `validatePlan c p == Right p` whenever `planFamily p == CMRepair`, for every `c`. |
| `testNeutralToneAlwaysAdmissible` | QuickCheck | E7b: `validatePlan c p == Right p` whenever `planNarrativeTone p == NarrativeNeutral`, for every `c`. |
| `testFlagOffNoBehaviouralChange` | HUnit | Regression: under `tiEssenceCommitmentEnabled = False`, `nextEssence` matches Phase 9 output exactly on a fixed fixture. |
| `testFlagOnCommitmentFires` | HUnit | Hand-built trajectory crossing `emAngstCommitmentThreshold`, flag on, single turn → `EssenceCommitted` with `ecTrigger = TriggerAngstThreshold`. |
| `testFlagOnRuptureThrows` | HUnit | Hand-built `EssenceCommitted` (Contemplative) + `Plan` with `planFamily = CMContact`, flag on → `Finalize.Commit` raises `EssenceRupture` and persistence is not invoked. |
| `testSlidingWindowExactSemantics` | QuickCheck | Q7: `shouldCommit` returns `Just TriggerConatusErosion` iff *all* of the last `emConatusFloorWindow` witnesses are sub-floor; partial sub-floor (k < N) returns `Nothing`. |
| `testReconcileCourtesyNeverWidens` | QuickCheck | C1: under any `Just commitment`, reconcile never produces a plan family outside `admissibleFamilies (ecMode commitment)` ∪ {family produced by `Nothing` call}. |

Wire the suite into all six aggregators (`qxfx0-test`, `qxfx0-test-unit`, `qxfx0-test-fast`, `qxfx0-test-property`, `qxfx0-test-slow`, `qxfx0-test-integration`) the same way `Test.Suite.SelfEssence` was wired in Phase 9.

### Step 10.10 — Corpus replay + flag flip + docs

1. **Corpus replay** (manual or scripted):

   ```bash
   QXFX0_ESSENCE_COMMITMENT_ENABLED=1 \
   cabal test qxfx0-test-integration --test-show-details=streaming
   ```

   Inspect the integration trace for any `EssenceRupture` event. If the count is non-zero, **stop and report** — this is a calibration failure, not a bug to suppress.

2. **Flag flip**: only after corpus replay reports zero ruptures, change the parser default to `True` (or document that operators must opt out via `QXFX0_ESSENCE_COMMITMENT_ENABLED=0`). Decision is the user's; the spec defaults to keeping the flag at `False` and letting the user flip it explicitly.

3. **Docs**:

   - `progress.txt` — append a `## Session YYYY-MM-DD — Phase 10 landed` block (mirror Phase 9 §9.7).
   - `ROADMAP.md` long-term #8 — strike Phase 10, leave only out-of-scope items.
   - `AGENTS.md` `QxFx0.Self.*` line — append "Phase 10 (forced commitment + post-commitment guard) landed YYYY-MM-DD".
   - `docs/adr/0012-essence-commitment.md` — flip status to **Accepted (Phase 10, fully landed)**; append §14 with observed corpus dynamics (angst distribution, commitment trigger counts) if collected during corpus replay.

## 2. Touchpoints not to break

| Touchpoint | Lock |
|------------|------|
| Phase 9 trace fields and their values under flag-off | `Test.Suite.SelfEssence`, `Test.Suite.TurnPipelineProtocol`, `Test.Suite.ReplayTrace` |
| `IdentityRupture` discipline (`checkBlanketTransition` runs first) | `Test.Suite.CommitInvariants` |
| `tiConatusEnergy` / `tiField` / `tiEssence` as M6 single sources of truth | regression locks F2, F3 |
| `defaultDeliberation` shape | property tests in `Test.Suite.SelfEssence` |
| `reconcile` purity and signature for `Nothing`-commitment callers | `Test.Suite.SelfDeliberation` |

## 3. Acceptance criteria

Done when **all** hold:

1. `cabal build lib:qxfx0` clean, zero new warnings.
2. `cabal test qxfx0-test` reports **582 / 582 PASS** (Phase 9's 574 + 8 new from `Test.Suite.SelfEssenceCommit`).
3. Per-suite counts:
   - `qxfx0-test-unit`: **458 + N₁** PASS
   - `qxfx0-test-property`: **74 + N₂** PASS
   - `qxfx0-test-fast`: **452 + N₃** PASS
   - `qxfx0-test-slow`: **91 + N₄** PASS
   - `qxfx0-test-integration`: **25 + N₅** PASS

   where `N₁ + N₂ + N₃ + N₄ + N₅ = 8` matches the §1 Step 10.9 split (KIMI chooses the split per test kind; all 8 must land somewhere).

4. Default-off behaviour: with `QXFX0_ESSENCE_COMMITMENT_ENABLED` unset, every existing trace JSON is byte-identical to Phase 9 output on the fixed integration fixtures.
5. Flag-on corpus replay (Step 10.10) reports zero `EssenceRupture` events.
6. `progress.txt`, `ROADMAP.md`, `AGENTS.md`, ADR-0012 status updated.

If any test count differs from the +8 budget, **stop and report**.

## 4. Verification commands

```bash
# Build
cabal build lib:qxfx0 2>&1 | tee /tmp/qxfx0-phase-10-build.log
grep -i 'warning' /tmp/qxfx0-phase-10-build.log | grep -v 'Loaded'

# Default-off (Phase 9 parity)
cabal test qxfx0-test --test-show-details=streaming

# Flag-on
QXFX0_ESSENCE_COMMITMENT_ENABLED=1 \
  cabal test qxfx0-test-integration --test-show-details=streaming

# Per-suite drilldown if aggregate is suspicious
cabal test qxfx0-test-unit
cabal test qxfx0-test-property
cabal test qxfx0-test-fast
cabal test qxfx0-test-slow
```

## 5. If something is unclear

| Ambiguity | Resolution |
|-----------|------------|
| `RenderStyle` has no clear warm/recovery axis | Default `admissibleStyles` to `Set.fromList [minBound .. maxBound]` for every mode; document the relaxation in Haddock; do not invent a categorical filter. |
| `Plan` accessor name for narrative tone | Use whatever Phase 8 `Self.Deliberation` exports (`planNarrativeTone` per ADR-0011). Verify by `grep_search` before writing the validator. |
| Where `essenceCommitmentEnabled` is parsed | Same place `familyDivergenceEnabled` is parsed. Find via `grep_search "familyDivergenceEnabled"`. |
| Whether `validatePlan` should also check `planConfidence` or `planRecoveryCause` | **No.** Confidence is a continuous quality metric; recovery cause is orthogonal to essence. Only family/tone/style are constrained. |
| Whether to add a `ToJSON` instance for `EssenceViolation` | **Yes** — already in the `deriving anyclass` block. The trace surface in Phase 11 (if any) may want it; cheap to add now. |
| Whether reconcile-time courtesy should apply to `RuleHolisticAdvantage` / `RuleFormalAdvantage` too | **No.** Only `RuleTiedFallback`. The hemispheric-advantage rules represent decisive verdicts; courtesy on them would be the layer making decisions for the hemispheres. |
| Whether to refactor `ssTurnCount ss + 1` into a helper | Optional. If KIMI sees this expression repeated 3+ times in the new code, extract `nextTurnOrdinal :: SystemState -> Int`; otherwise leave inline. |

— end of Phase 10 spec —
