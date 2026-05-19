# Phase 9 — Essence Selection Infrastructure
## Implementation Specification for KIMI

- **Authoritative architecture**: [`ADR-0012 — Essence Commitment`](./adr/0012-essence-commitment.md).
- **Status of this spec**: Normative. Where this document and ADR-0012
  appear to disagree, ADR-0012 wins; raise a clarification rather than
  guessing.
- **Date**: 2026-05-19.
- **Scope locked**: Phase 9 only. Phase 10 (forced commitment,
  `validatePlan`, `EssenceRupture`) is **out of scope** for this
  ticket; do not implement it.
- **Behavioural contract**: zero behavioural change at runtime. The
  trajectory accumulates, the trace gains four nullable fields,
  no existing test result changes.
- **Test target**: `567/567 + 7 new = 574/574 PASS`, zero new
  warnings.

## 0. Decisions already taken (do not re-litigate)

The four open questions in ADR-0012 §11 are resolved as follows.
These are part of the contract — implement to these answers without
asking.

| # | Question | Resolution |
|---|----------|------------|
| Q1 | Saturation as trigger | **No.** Only `etAngstLevel ≥ emAngstCommitmentThreshold` counts. Saturation at `1.0` is a tail state, not an event. |
| Q2 | Trigger priority on simultaneous fire | **Angst > Conatus.** `shouldCommit` returns `Just TriggerAngstThreshold` when both fire. Property test E5 locks this. |
| Q3 | `EssenceWitnessing` as runtime-visible mode | **Yes.** Pre-commit, `trcEssenceMode = Just "witnessing"`. The sentinel is observably distinct from `Nothing` (essence layer disabled) and from any committed mode. |
| Q4 | `validatePlan` location | **Stays in `Finalize.Commit`** when Phase 10 lands. Phase 9 ships no validator — `reconcile` stays pure and essence-unaware. |

## 1. File-by-file execution plan

The order below is the recommended commit sequence. Each step is
independently green: after step N the build is clean and all tests
pass.

### Step 9.1 — Create the pure module

**New file**: `src/QxFx0/Self/Essence.hs`.

Module header:

```haskell
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE StrictData #-}
{- |

Phase 9 essence selection infrastructure.

Reads the system's deliberation history and accumulates an
'EssenceTrajectory' from which a later 'commit' will produce an
irrevocable 'EssenceCommitment'. Pure and total.

See @docs\/adr\/0012-essence-commitment.md@ for the architecture
and @docs\/phase-9-essence-implementation-spec.md@ for the
contract that produced this module.

This module is /not/ a model of phenomenal selfhood. It is a
structural accumulator over the right- and left-hemispheric
verdicts already produced by 'QxFx0.Self.Deliberation'. The
forcing dynamics (Phase 10) live behind a feature flag; until
then, every essence remains 'EssenceUncommitted'.
-}
module QxFx0.Self.Essence
  ( -- * Carriers
    Essence (..)
  , EssenceTrajectory (..)
  , EssenceWitness (..)
  , FieldSignature (..)
  , FieldBand (..)
  , ValenceBand (..)
  , TrajectoryHash (..)
    -- * Modes and triggers
  , EssenceMode (..)
  , CommitmentTrigger (..)
  , EssenceCommitment (..)
    -- * Modulation
  , EssenceModulation (..)
  , defaultEssenceModulation
    -- * Pure morphisms
  , emptyEssence
  , emptyTrajectory
  , witness
  , shouldCommit
  , extractMode
  , commit
    -- * Renderers (snake_case, JSON-schema-stable)
  , renderEssenceMode
  , renderCommitmentTrigger
    -- * Field signature
  , fieldSignature
  ) where
```

Types follow ADR-0012 §2 verbatim. Concrete defaults below; comments
must explain *why*, not merely paraphrase the types.

```haskell
data Essence
  = EssenceUncommitted !EssenceTrajectory
  | EssenceCommitted   !EssenceTrajectory !EssenceCommitment
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data EssenceTrajectory = EssenceTrajectory
  { etWitnesses    :: !(Seq EssenceWitness)
  , etAngstLevel   :: !Double
  , etConatusFloor :: !Double
  , etCapacity     :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data EssenceWitness = EssenceWitness
  { ewTurnOrdinal     :: !Int
  , ewSalienceDriver  :: !SalienceDriver
  , ewReconcileRule   :: !ReconcileRule
  , ewAgreement       :: !Agreement
  , ewDivergence      :: !Double
  , ewConatusScalar   :: !Double
  , ewFieldSignature  :: !FieldSignature
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)
```

`FieldSignature` is a four-tuple of bucketed components. The
bucketing is the calibration knob; thresholds live in
`EssenceModulation` to keep the trajectory bounded and the
witness-equality test cheap:

```haskell
data FieldSignature = FieldSignature
  { fsResonance      :: !FieldBand
  , fsArousal        :: !FieldBand
  , fsValence        :: !ValenceBand
  , fsConsolidation  :: !FieldBand
  , fsCounterfactual :: !FieldBand
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data FieldBand
  = BandLow
  | BandMid
  | BandHigh
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData)

data ValenceBand
  = ValenceNegative
  | ValenceNeutral
  | ValencePositive
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData)
```

Bucketing function:

```haskell
-- | Coarse hash of a 'Field' into a 'FieldSignature' for
-- trajectory storage. Components in [0, 1] bucket at
-- @bandLow / bandHigh@; valence in [-1, 1] buckets at
-- @valenceLowEdge / valenceHighEdge@.
fieldSignature :: EssenceModulation -> Field -> FieldSignature
```

Mode/trigger/commitment as in ADR-0012 §2 (`EssenceWitnessing`
included; see §0 Q3):

```haskell
data EssenceMode
  = EssenceWitnessing      -- pre-commitment, runtime-visible
  | EssenceContemplative
  | EssenceDialogical
  | EssenceIntegrative
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData)

data CommitmentTrigger
  = TriggerAngstThreshold
  | TriggerConatusErosion
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData)

newtype TrajectoryHash = TrajectoryHash { unTrajectoryHash :: Int }
  deriving stock (Eq, Show, Generic)
  deriving newtype (NFData)

data EssenceCommitment = EssenceCommitment
  { ecMode         :: !EssenceMode
  , ecTrigger      :: !CommitmentTrigger
  , ecCommittedAt  :: !Int                -- turn ordinal
  , ecWitnessHash  :: !TrajectoryHash
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)
```

Modulation record (sixth modulation parameter family in the
project; follow the pattern of `SalienceModulation` and
`DeliberationModulation`):

```haskell
data EssenceModulation = EssenceModulation
  { emAngstCommitmentThreshold     :: !Double  -- [0, 1]
  , emAngstAccrualRate             :: !Double  -- per qualifying turn
  , emAngstDecayRate               :: !Double  -- per agreement turn
  , emAngstAccrualDivergenceFloor  :: !Double  -- below floor no accrual
  , emConatusFloorWindow           :: !Int     -- turns of sub-floor
  , emConatusStructuralFloor       :: !Double  -- below which we count
  , emTrajectoryCapacity           :: !Int     -- ring-buffer length
    -- field-band bucketing knobs
  , emBandLowEdge                  :: !Double  -- below = BandLow
  , emBandHighEdge                 :: !Double  -- above = BandHigh
  , emValenceLowEdge               :: !Double  -- below = ValenceNegative
  , emValenceHighEdge              :: !Double  -- above = ValencePositive
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)
```

Concrete defaults (conservative, derived from existing project
defaults; do not tune in Phase 9, that is calibration work for a
later session):

```haskell
defaultEssenceModulation :: EssenceModulation
defaultEssenceModulation = EssenceModulation
  { emAngstCommitmentThreshold    = 0.75
  , emAngstAccrualRate            = 0.05
  , emAngstDecayRate              = 0.02
  , emAngstAccrualDivergenceFloor = 0.5
  , emConatusFloorWindow          = 8
  , emConatusStructuralFloor      = 0.5
  , emTrajectoryCapacity          = 32
  , emBandLowEdge                 = 0.33
  , emBandHighEdge                = 0.67
  , emValenceLowEdge              = -0.33
  , emValenceHighEdge             = 0.33
  }
```

Constructors and morphisms:

```haskell
-- | The carrier-empty value. Used in 'Bootstrap' and in any test
-- harness that hand-builds a 'SystemState'.
emptyEssence :: Essence
emptyEssence = EssenceUncommitted emptyTrajectory

-- | The carrier-empty trajectory. @etAngstLevel = 0@,
-- @etConatusFloor = 1@ (so the floor only descends with witnessed
-- evidence), capacity from 'defaultEssenceModulation'.
emptyTrajectory :: EssenceTrajectory

-- | Ingest one turn's deliberation into the trajectory.
--
-- Effects:
--
-- 1. Append a new 'EssenceWitness' to 'etWitnesses', truncating
--    the front to keep length ≤ 'etCapacity'.
-- 2. Update 'etAngstLevel':
--      * RuleConatusOverride       → no change.
--      * FullAgreement, divergence 0 → decay by 'emAngstDecayRate'.
--      * RuleHolisticAdvantage/RuleFormalAdvantage with
--        divergence ≥ 'emAngstAccrualDivergenceFloor'
--                              → accrue by 'emAngstAccrualRate'.
--      * otherwise (RuleSalienceLead, RuleTiedFallback,
--        sub-floor divergence)
--                              → no change.
--    Clamp to @[0, 1]@.
-- 3. Update 'etConatusFloor' to @min etConatusFloor ceScalar@.
witness
  :: EssenceModulation
  -> Int          -- turn ordinal (tmTurnCount of the current turn)
  -> ConatusEnergy
  -> Field
  -> Deliberation
  -> EssenceTrajectory
  -> EssenceTrajectory

-- | Returns 'Just' when the trajectory has crossed a commitment
-- threshold. Priority: 'TriggerAngstThreshold' over
-- 'TriggerConatusErosion' (see §0 Q2).
--
-- Conatus erosion triggers only when 'etConatusFloor' has stayed
-- below 'emConatusStructuralFloor' for at least
-- 'emConatusFloorWindow' consecutive witnessed turns. In Phase 9
-- this is approximated by requiring (a) floor below threshold AND
-- (b) the trajectory contains at least
-- 'emConatusFloorWindow' witnesses. The precise sliding-window
-- semantics ('every one of the last N witnesses sub-floor') is
-- Phase-10 work and is the subject of a calibration ADR
-- addendum.
shouldCommit :: EssenceModulation -> EssenceTrajectory -> Maybe CommitmentTrigger

-- | Deterministic mode extraction.  Never returns
-- 'EssenceWitnessing'.  Selection rule:
--
-- @
--   let n = length etWitnesses
--       aRate = #{Agreement = FullAgreement} / n
--       hRate = #{ReconcileRule = RuleHolisticAdvantage} / n
--       fRate = #{ReconcileRule = RuleFormalAdvantage}   / n
--   in case maxBy snd
--        [(EssenceIntegrative,   aRate)
--        ,(EssenceDialogical,    hRate)
--        ,(EssenceContemplative, fRate)] of
--        (m, r) | r > 0     -> m
--               | otherwise -> EssenceContemplative   -- tie-break
-- @
--
-- The tie-break is 'EssenceContemplative' because, in the absence
-- of any signal, the formal hemisphere is the safer default
-- (lower behavioural divergence post-commit).
extractMode :: EssenceTrajectory -> EssenceMode

-- | Construct the commitment.  Total over trajectories that have
-- passed 'shouldCommit'; technically total over all trajectories
-- but used only when 'shouldCommit' returned 'Just'.  The hash is
-- the Haskell 'hashWithSalt' (or simple structural fold) over the
-- 'etWitnesses' sequence — enough to detect tampering across
-- replay, not a cryptographic guarantee.
commit
  :: Int                -- current turn ordinal
  -> CommitmentTrigger
  -> EssenceTrajectory
  -> EssenceCommitment

-- | Snake_case JSON-schema-stable tag for 'EssenceMode'.
-- Stable across builds; any change is a breaking schema change.
renderEssenceMode :: EssenceMode -> Text
renderEssenceMode = \case
  EssenceWitnessing    -> "witnessing"
  EssenceContemplative -> "contemplative"
  EssenceDialogical    -> "dialogical"
  EssenceIntegrative   -> "integrative"

renderCommitmentTrigger :: CommitmentTrigger -> Text
renderCommitmentTrigger = \case
  TriggerAngstThreshold -> "angst_threshold"
  TriggerConatusErosion -> "conatus_erosion"
```

Implementation notes:

- Imports come from `QxFx0.Self.Deliberation` (for `Agreement`,
  `ReconcileRule`, `Deliberation`, accessor `delibTrace`), from
  `QxFx0.Self.Salience` (for `SalienceDriver` and any helpers),
  from `QxFx0.Self.Conatus` (for `ConatusEnergy(..)` /
  `ceScalar`), and from `QxFx0.Self.Field` (for `Field` and its
  five components).
- Use `Data.Sequence` for `Seq`. Truncation via `Seq.drop (n - cap)`
  or `Seq.viewl` pattern; pick whichever is idiomatic.
- The dependency on `QxFx0.Self.Deliberation` is one-way:
  `Self.Essence` reads `DeliberationTrace` accessors but
  `Self.Deliberation` must not depend on `Self.Essence`.
  Verify this with `ghc -ddump-mod-cycles` or just by inspection.

### Step 9.2 — Expose the module

**Modify** `qxfx0.cabal`. Find the `library` stanza, locate the
`QxFx0.Self.Deliberation` line, and add `QxFx0.Self.Essence`
immediately after it. Keep the alphabetical-within-subtree
discipline that the file already uses.

### Step 9.3 — Thread `Essence` through `SystemState` and `TurnInput`

**Modify** `src/QxFx0/Core/State.hs` (or wherever `SystemState` lives
— follow the path from `QxFx0.Core.State` import in
`Finalize/State.hs`).  Add a new strict field:

```haskell
, ssEssence :: !Essence
```

Default constructor (`emptySystemState` or equivalent) initialises
to `emptyEssence`. Update every existing call site that builds a
fresh `SystemState`: there is exactly one in `Bootstrap`, one in
test helpers, and one in each integration fixture. Use
`grep_search` for `emptySystemState`, `mkSystemState`,
`SystemState { ` — every literal needs the new field.

**Modify** `src/QxFx0/Core/TurnPipeline/Types.hs`. Add to
`TurnInput`:

```haskell
, tiEssence :: !Essence
  -- ^ Phase 9: the pre-turn essence carrier, populated by
  --   'buildPrepareEffectPlan' from 'ssEssence'.  Single source
  --   of truth for the turn's essence-layer reads.
```

**Modify** `src/QxFx0/Core/TurnPipeline/Effects.hs`. In
`buildPrepareEffectPlan` (or wherever `PrepareStatic` is
constructed), add `psEssence :: !Essence` to `PrepareStatic` and
populate it from `ssEssence ss`. Plumb through to the `TurnInput`
construction the same way `tiConatusEnergy` / `tiField` are
plumbed.

### Step 9.4 — Ingest witnesses in `Finalize.State`

**Modify** `src/QxFx0/Core/TurnPipeline/Finalize/State.hs`.

`buildNextSystemState` is where the post-turn `SystemState` is
constructed. After all existing field updates, compute the new
essence:

```haskell
let nextEssence =
      case tiEssence ti of
        EssenceUncommitted trajectory ->
          let
            trajectory' =
              witness
                defaultEssenceModulation
                (tmTurnCount (tiMetrics ti))
                (tiConatusEnergy ti)
                (tiField ti)
                (fromMaybe defaultDeliberation (tpDeliberation tp))
                trajectory
          in EssenceUncommitted trajectory'
        EssenceCommitted trajectory commitment ->
          -- Phase 10 will replace this with a witness + validate
          -- pipeline.  Phase 9 keeps committed essences immutable.
          EssenceCommitted trajectory commitment
```

Then set `ssEssence = nextEssence` in the produced `SystemState`.

Two notes:

- `defaultDeliberation` is the fallback for turns that did not run
  reconcile (Conatus-gated, early-exit). Add it to
  `QxFx0.Self.Deliberation` if it does not exist:

    ```haskell
    defaultDeliberation :: Deliberation
    defaultDeliberation = ...   -- agreement, neutral, ruleSalienceLead,
                                -- divergence 0; document explicitly
    ```

  If `Deliberation` already has an `emptyDeliberation`-style
  smart constructor, reuse it and skip the addition.

- Do not introduce a second witness call site. The single source
  of truth for essence update is `buildNextSystemState`.

### Step 9.5 — Trace fields

**Modify** `src/QxFx0/Types/TurnProjection.hs`. Add four nullable
fields to `TurnReplayTrace`, immediately after the existing
deliberation block:

```haskell
, trcEssenceMode       :: !(Maybe Text)
  -- ^ Phase 9: snake_case 'renderEssenceMode' tag of the
  --   post-turn essence.  @Just "witnessing"@ pre-commit;
  --   @Just "contemplative" | "dialogical" | "integrative"@
  --   post-commit (Phase 10).  @Nothing@ only when the essence
  --   layer is statically disabled (not currently exposed).
, trcEssenceCommitted  :: !(Maybe Bool)
  -- ^ Phase 9: @Just False@ pre-commit, @Just True@ post-commit
  --   (Phase 10).  Always @Just False@ in Phase 9 by contract.
, trcEssenceAngstLevel :: !(Maybe Double)
  -- ^ Phase 9: 'etAngstLevel' of the post-turn trajectory in
  --   @[0, 1]@.  Tracks accumulated unresolved divergence.
, trcEssenceTrigger    :: !(Maybe Text)
  -- ^ Phase 9: snake_case 'renderCommitmentTrigger' tag set only
  --   on the turn a commitment fires (Phase 10).  Always
  --   @Nothing@ in Phase 9.
```

**Modify** `buildTurnProjection` in `Finalize/State.hs`. Compute
the new fields from the *post-turn* essence — i.e. read from
`nextSs`, the next-state value produced by `buildNextSystemState`,
not from `tiEssence`:

```haskell
let postEssence = ssEssence nextSs
    (modeTag, committedFlag, angst, triggerTag) = case postEssence of
      EssenceUncommitted t ->
        ( Just (renderEssenceMode EssenceWitnessing)
        , Just False
        , Just (etAngstLevel t)
        , Nothing
        )
      EssenceCommitted t c ->
        ( Just (renderEssenceMode (ecMode c))
        , Just True
        , Just (etAngstLevel t)
        , Just (renderCommitmentTrigger (ecTrigger c))
        )
```

Populate the four new fields in the `TurnReplayTrace` record
literal. Phase 9 will always emit `Just "witnessing"`,
`Just False`, `Just <angst>`, `Nothing` — the post-commit
branches exist for Phase 10 and must be compilable in Phase 9.

### Step 9.6 — Test suite

**New file**: `test/Test/Suite/SelfEssence.hs`.

Five property tests and two unit tests. Use `Hspec` +
`QuickCheck` following the pattern of `Test.Suite.SelfSalience`
and `Test.Suite.SelfField` exactly.

Mandatory tests (regression-lock identifiers from ADR-0012 §9):

```haskell
-- | E1 — extractMode determinism + non-Witnessing.
testExtractModeDeterministic
  :: Property
  -- ∀ t : EssenceTrajectory.
  --   extractMode t === extractMode t
  --   ∧ extractMode t /= EssenceWitnessing

-- | E2 — angst decays under FullAgreement.
testAngstDecaysUnderAgreement
  :: Property
  -- Given a trajectory with etAngstLevel = a in [0, 1] and a
  -- 'Deliberation' with Agreement = FullAgreement and divergence
  -- 0, after one 'witness' call:
  --   either etAngstLevel' < a, or etAngstLevel' == 0.

-- | E3 — angst accrues under hemispheric advantage with divergence.
testAngstAccruesUnderDivergence
  :: Property
  -- Given a trajectory with etAngstLevel = a < 1 and a
  -- 'Deliberation' whose dtRule is RuleHolisticAdvantage or
  -- RuleFormalAdvantage with dtDivergence ≥
  -- emAngstAccrualDivergenceFloor, after one 'witness' call:
  --   either etAngstLevel' > a, or etAngstLevel' == 1.

-- | E4 — shouldCommit monotone.
testShouldCommitMonotone
  :: Property
  -- Once 'shouldCommit em t = Just _', for all continuations t'
  -- of t produced by 'witness ... t', 'shouldCommit em t'' is
  -- also 'Just _'.  Phase 9 implementation note: this property
  -- holds vacuously when 'shouldCommit' returns Nothing on every
  -- random trajectory; mark the test as 'expectFailure' if no
  -- generated trajectory ever reaches the threshold (low
  -- defaults) and adjust generator parameters until at least one
  -- positive case fires per run.

-- | E5 — trigger priority: angst beats Conatus when both fire.
testTriggerPriorityAngst
  :: Property
  -- Hand-construct a trajectory with etAngstLevel ≥
  -- emAngstCommitmentThreshold AND etConatusFloor <
  -- emConatusStructuralFloor AND length etWitnesses ≥
  -- emConatusFloorWindow.  Assert
  -- 'shouldCommit em t == Just TriggerAngstThreshold'.

-- | Unit — emptyEssence shape.
testEmptyEssenceShape :: Expectation
-- emptyEssence should pattern as 'EssenceUncommitted t' with
-- 'etWitnesses == mempty', etAngstLevel == 0,
-- etConatusFloor == 1, etCapacity == emTrajectoryCapacity defaults.

-- | Unit — fieldSignature totality.
testFieldSignatureTotal :: Expectation
-- 'fieldSignature defaultEssenceModulation emptyField'
-- produces a valid 'FieldSignature' (no bottoms, no exceptions).
```

QuickCheck generators (place in
`test/Test/Generators/Essence.hs` or inline if KIMI prefers; the
existing project pattern is per-suite `Test.Suite.SelfField`
keeps its generator inline):

```haskell
arbitraryEssenceTrajectory :: Gen EssenceTrajectory
arbitraryEssenceWitness    :: Gen EssenceWitness
arbitraryDeliberation      :: Gen Deliberation   -- reuse if already exists
```

**Wire**: add `Test.Suite.SelfEssence` to the unit test suite in
`qxfx0.cabal` next to `Test.Suite.SelfField` and
`Test.Suite.SelfSalience`. Add a top-level `testSelfEssence` entry
to whatever aggregator the unit suite uses (search for
`testSelfField` to find it).

### Step 9.7 — Documentation sync

**Modify**:

- `progress.txt` — append a `## Session 2026-05-19 — Phase 9 Step 1`
  block listing the modules touched, the test count delta, and
  the verification command. Follow the format of the
  `## Session 2026-05-18 — Phase 7 Step 2` block.
- `ROADMAP.md` — under long-term #8, mark Phase 9 as
  *“in progress (Step 9.1 landed YYYY-MM-DD)”*. Do not mark it
  completed until §3 acceptance below is met.
- `AGENTS.md` — update the `QxFx0.Self.*` landed-phases line:
  add *“Phase 9 (essence selection infrastructure, infra-only)
  in progress / landed YYYY-MM-DD”* once the suite is green.
- `docs/adr/0012-essence-commitment.md` — flip status from
  **Proposed (Phase 9, awaiting implementation)** to
  **Accepted (Phase 9, infrastructure only)** at the very end
  of Step 9.7. Add a short addendum to §11 closing out the four
  open questions per §0 of this spec.

## 2. Touchpoints not to break

The Phase 9 work must not change any of the following observable
behaviours. Each is currently locked by a test; if you find
yourself about to violate one, stop and raise a clarification.

| Touchpoint | Lock |
|------------|------|
| Existing `TurnReplayTrace` fields and their values | `Test.Suite.TurnPipelineProtocol`, `Test.Suite.ReplayTrace` |
| `reconcile` purity and signature | `Test.Suite.SelfDeliberation` |
| `IdentityRupture` discipline in `Finalize.Commit` | `Test.Suite.CommitInvariants` |
| `defaultSalienceWeights` / `defaultFieldHeuristics` values | `Test.Suite.SelfSalience`, `Test.Suite.SelfField` |
| `tiConatusEnergy` / `tiConatusGateFired` / `tiField` as single source of truth (M6) | regression lock F2 |

The new `tiEssence` is *added* alongside these, not in place of
any. The Conatus / Field / Deliberation surfaces are unchanged.

## 3. Acceptance criteria

The Phase 9 ticket is done when *all* of the following hold:

1. `cabal build lib:qxfx0` succeeds with zero new warnings.
2. `cabal test all` (or `cabal test qxfx0-test`) reports
   **574 / 574 PASS** (current 567 plus exactly seven new tests
   from `Test.Suite.SelfEssence` — five properties, two units).
3. `cabal test qxfx0-test-unit` reports
   **458 / 458 PASS** (current 451 plus seven new).
4. `cabal test qxfx0-test-property` retains **80 / 80 PASS**.
5. `cabal test qxfx0-test-integration` retains **32 / 32 PASS**.
6. `cabal test qxfx0-test-fast` retains the prior count.
7. `cabal test qxfx0-test-slow` retains **98 / 98 PASS**.
8. A grep for `trcEssenceMode` in the JSON-schema fixture (if
   the project has one — search `docs/` and `test/fixtures/`)
   confirms the four new fields appear with `Just`-typed
   schema entries.
9. `progress.txt`, `ROADMAP.md`, `AGENTS.md`, ADR-0012 status
   updated as in Step 9.7.

If any test count differs from the +7 budget, stop and report:
either a test was unexpectedly affected (which is a violation of
the “no behavioural change” contract) or the generator parameters
need tuning before the suite is final.

## 4. Verification commands

KIMI should run these in order. They are designed for low memory
budgets and may be split across sessions if necessary.

```bash
# 1. Library compiles cleanly.
cabal build lib:qxfx0 2>&1 | tee /tmp/qxfx0-phase-9-build.log
grep -i 'warning' /tmp/qxfx0-phase-9-build.log | grep -v 'Loaded'

# 2. Unit suite (fastest signal on Self.Essence properties).
cabal test qxfx0-test-unit --test-show-details=streaming

# 3. Aggregate suite.
cabal test qxfx0-test --test-show-details=streaming

# 4. Per-suite verification (do these only if 3 is suspicious).
cabal test qxfx0-test-property
cabal test qxfx0-test-integration
cabal test qxfx0-test-fast
cabal test qxfx0-test-slow
```

## 5. Out of scope (Phase 10 reminder)

Do **not** implement any of the following in this ticket. They
are Phase 10 work and require their own ADR review:

- `essenceCommitmentEnabled` feature flag.
- `validatePlan` and the `EssenceViolation` / `EssenceRupture`
  machinery.
- The `QxFx0.ExceptionPolicy.EssenceRupture` constructor.
- Reconcile-time biasing toward admissible families.
- Sliding-window `etConatusFloor` semantics (Phase 9
  approximation is sufficient — see §1 Step 9.1 `shouldCommit`
  comment).
- Corpus-replay validation of `shouldCommit` defaults.

If `shouldCommit` happens to fire on real traffic in Phase 9,
that is harmless — Phase 9 never actually calls `commit`, the
trajectory remains `EssenceUncommitted`, and the trace truthfully
reports `trcEssenceMode = Just "witnessing"` and an elevated
`trcEssenceAngstLevel`.

## 6. If something is unclear

Default to the conservative choice. The four checkpoints below
are common ambiguity points; the resolutions are part of the
contract.

| Ambiguity | Resolution |
|-----------|------------|
| Where to put `defaultDeliberation` if it does not exist | `QxFx0.Self.Deliberation`, exported. Document its fields explicitly in the Haddock. |
| Whether `ssEssence` should default to `emptyEssence` or `EssenceUncommitted emptyTrajectory` | They are equal by definition; use `emptyEssence`. |
| Whether to expose `EssenceWitness(..)` (constructors and accessors) | Yes — full export. The trajectory is internal data but the witness is a structurally observable record. |
| Whether to add a `ToJSON` instance for `EssenceMode` etc. | No. Phase 9 only goes through `renderEssenceMode` text. ToJSON for the carrier itself is a Phase-10 concern. |
| Whether `etConatusFloor` should be `Double` or `ConatusEnergy` | `Double`. The floor is the scalar value, and `ConatusEnergy` carries components that are not part of the floor semantics. |
| Whether `fieldSignature` needs a `Hashable` instance for trajectory hashing | No — `commit` can use the structural `Show`-derivable hash or a simple `foldl'` over the witnesses. Cryptographic strength is not required (§ADR-0012 commentary). |

— end of Phase 9 spec —
