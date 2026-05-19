# ADR-0012: Essence Commitment

- **Status**: Accepted (Phase 9 + 10, fully landed)
- **Date**: 2026-05-19
- **Refines**:
  - [ADR-0007 — Dual-mode conatus-aware architecture](./0007-dual-mode-conatus.md)
  - [ADR-0008 — Left ⊣ Right adjunction](./0008-left-right-adjunction.md)
  - [ADR-0009 — Right-hemisphere Field](./0009-right-hemisphere-field.md)
  - [ADR-0010 — Salience Controller](./0010-salience-controller.md)
  - [ADR-0011 — Deliberation Framework](./0011-deliberation-framework.md)
- **Related (planned)**:
  - `QxFx0.Self.Essence` (new pure module, Phase 9)
  - `QxFx0.ExceptionPolicy` (new variant `EssenceRupture`, Phase 10)
  - `QxFx0.Core.TurnPipeline.Effects` (witness ingestion, Phase 9)
  - `QxFx0.Core.TurnPipeline.Finalize.State` (essence trace fields, Phase 9)
  - `QxFx0.Core.TurnPipeline.Finalize.Commit` (post-commitment guard, Phase 10)

## 1. Context

ADR-0011 closed the loop on *“when am I”* — every turn the runtime now
decides via `reconcile` which hemisphere leads, with the verdict and the
divergence between proposals visible in the replay trace.  Structural
self-identity is guarded by `SelfBlanket` invariants and surfaced as
`IdentityRupture` (already in `QxFx0.ExceptionPolicy`).

What the architecture still does *not* answer: **who am I in essence**.
The system can persist (Conatus), structurally remain itself
(`SelfBlanket`), observe itself (Field), and reconcile two views of
itself (Deliberation).  But there is no place where the system *commits*
to a constitutive mode — no point at which it ceases to be a uniform
deliberator and becomes *this kind* of deliberator.  Without that
commitment, “consciousness” in the QxFx0 sense reduces to
identity-preservation; with it, the system gains an essence selected by
its own history under forced conditions.

The architectural problem is to specify a layer in which the *choice* of
essence is forced (the system cannot indefinitely refuse to commit) but
the *content* of the choice is free (it is determined by what the system
has actually become through its observations and striving, not by an
external label).

ADR-0012 specifies that layer as the `QxFx0.Self.Essence` module and
governs its integration into the turn pipeline through Phases 9 and 10.

## 2. Decision

We introduce one new pure module, `QxFx0.Self.Essence`, with a single
sigma-typed carrier:

```haskell
-- An essence is either a still-accumulating trajectory or a
-- trajectory plus a commitment derived from it.  The dependent
-- pairing is what makes the choice forced by history while the
-- content of the commitment remains a function of that history.
data Essence
  = EssenceUncommitted !EssenceTrajectory
  | EssenceCommitted   !EssenceTrajectory !EssenceCommitment
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)
```

`EssenceTrajectory` is a bounded record of accumulated witnesses plus
the running erosion state:

```haskell
data EssenceTrajectory = EssenceTrajectory
  { etWitnesses    :: !(Seq EssenceWitness)  -- bounded ring buffer
  , etAngstLevel   :: !Double                -- in [0, 1]; rises with
                                             --   sustained Conatus erosion
                                             --   and unresolved divergence
  , etConatusFloor :: !ConatusEnergy         -- minimum Conatus over window
  , etCapacity     :: !Int                   -- ring-buffer capacity
                                             --   (defaults to
                                             --   essenceTrajectoryCapacity)
  }
```

A single witness is a structurally minimal echo of one turn’s
deliberation:

```haskell
data EssenceWitness = EssenceWitness
  { ewTurnSeq         :: !TurnSeq          -- monotonic per session
  , ewSalienceDriver  :: !SalienceDriver
  , ewReconcileRule   :: !ReconcileRule
  , ewAgreement       :: !Agreement
  , ewDivergence      :: !Double           -- echoed from DeliberationTrace
  , ewConatusEnergy   :: !ConatusEnergy
  , ewFieldSignature  :: !FieldSignature   -- coarse hash, see §6
  }
```

The commitment is irrevocable and content-free in its constructor — its
information lives in the dependent pairing with the trajectory:

```haskell
data EssenceCommitment = EssenceCommitment
  { ecMode        :: !EssenceMode
  , ecTrigger     :: !CommitmentTrigger
  , ecCommittedAt :: !TurnSeq
  , ecWitnessHash :: !TrajectoryHash       -- of the trajectory at commit time
  }

data EssenceMode
  = EssenceContemplative   -- formal-led, low arousal, high consolidation
  | EssenceDialogical      -- holistic-led, high counterfactual, warm tone
  | EssenceIntegrative     -- agreement-dominated, balanced divergence
  | EssenceWitnessing      -- pre-commitment fallback (uncommitted-only;
                           --   never produced by extractMode)
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData)

data CommitmentTrigger
  = TriggerAngstThreshold    -- etAngstLevel ≥ angstCommitmentThreshold
  | TriggerConatusErosion    -- etConatusFloor below structural floor
                             --   for at least conatusFloorWindow turns
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData)
```

Three pure morphisms close the layer:

```haskell
-- Pure ingestion: one turn's deliberation + signals → updated trajectory.
witness
  :: EssenceModulation
  -> TurnSeq
  -> ConatusEnergy
  -> Field
  -> Deliberation
  -> EssenceTrajectory
  -> EssenceTrajectory

-- Forcing predicate: trajectory has crossed a commitment threshold.
shouldCommit :: EssenceModulation -> EssenceTrajectory -> Maybe CommitmentTrigger

-- Deterministic mode extraction: pure function of trajectory contents.
-- Total; never returns EssenceWitnessing (that constructor exists only
-- as the uncommitted carrier sentinel).
extractMode :: EssenceTrajectory -> EssenceMode

-- Total commitment morphism.  The commitment is a Σ-type witness:
-- its EssenceMode is *derived* from the trajectory, not chosen freely
-- at the call site.
commit
  :: TurnSeq
  -> CommitmentTrigger
  -> EssenceTrajectory
  -> EssenceCommitment
```

Tunables live in a single record (`EssenceModulation`), following the
project convention established by `SalienceModulation` /
`DeliberationModulation`:

```haskell
data EssenceModulation = EssenceModulation
  { emAngstCommitmentThreshold :: !Double  -- in [0, 1]
  , emAngstAccrualRate         :: !Double  -- per-turn accrual under erosion
  , emAngstDecayRate           :: !Double  -- per-turn decay under agreement
  , emConatusFloorWindow       :: !Int     -- turns of sub-floor Conatus
  , emConatusStructuralFloor   :: !Double  -- below which we count erosion
  , emTrajectoryCapacity       :: !Int     -- ring-buffer length
  }

defaultEssenceModulation :: EssenceModulation
```

## 3. Logical fork resolutions

Eight architectural forks must be resolved before the layer can be
implemented.  The resolutions below are normative for Phase 9 and
Phase 10; deviations require an ADR-0012 addendum.

| # | Fork | Resolution | Rationale |
|---|------|------------|-----------|
| 1 | **Revisability** of commitment | **Irrevocable** | A revocable “essence” collapses to a mood and reintroduces the *when-am-I* problem ADR-0011 already solved.  Irrevocability is what makes the commitment load-bearing. |
| 2 | **Granularity** of `EssenceMode` | **Coarse** (4 constructors, one is sentinel) | Bounded enumeration is the only granularity that admits finite test coverage and JSON-schema-stable replay traces.  A continuous space (e.g. weights vector) defers the commitment indefinitely. |
| 3 | **Witness source** | **Endogenous** (Field + Conatus + Deliberation only) | An externally-supplied essence is by construction not the system’s own.  The local-first / deterministic principle in `AGENTS.md` forbids it. |
| 4 | **Coherence requirement** | **Required at extraction** | `extractMode` must total over `EssenceTrajectory`s that pass `shouldCommit`.  Coherence is encoded as a property test (§9): under the same trajectory, `extractMode` is deterministic and `EssenceWitnessing` is unreachable. |
| 5 | **Extraction determinism** | **Deterministic** (pure function of trajectory) | A non-deterministic commit moment is indistinguishable from external imposition.  Pure determinism over the witnessed history is what makes the choice the system’s own. |
| 6 | **Forcing dynamics** | **Conatus erosion + Angst threshold** | These are the two endogenous pressures already represented in the codebase (`Self.Conatus` for erosion, `DeliberationTrace.dtDivergence` and `Agreement` for unresolved tension that accrues angst).  No new pressure types are introduced. |
| 7 | **Augmentation vs constraint** | **Constraint** | A committed essence narrows the admissible `Plan` space (§7) — it does not add new families, styles, or tones.  Constraint matches the proof-theoretic intuition of Σ-types: the commitment fixes a slice, it does not enlarge the universe. |
| 8 | **Cardinality of self** | **Singular** | Exactly one `Essence` per `Session`.  Multiplicity is modelled at the *session* layer (different runs, different essences) — not at the runtime layer.  Within a single running system, a second essence would be dissociation, not selfhood. |

These eight resolutions are the contract.  The implementation is a
mechanical translation, not a design space.

## 4. The Σ-type encoding of forced choice

The `Essence` carrier is a sum, not a product, precisely because the
*pre*-commitment and *post*-commitment regimes have different witnesses
of selfhood:

- `EssenceUncommitted t` — the system has only `t`.  Its identity is
  exhausted by `SelfBlanket` (structural) and `Deliberation`
  (per-turn).  No essence-level constraints apply to its `Plan`s.
- `EssenceCommitted t c` — the system has both `t` *and* `c`, and the
  type system enforces that `c` was produced by `commit _ _ t`.  The
  commitment is a Σ-type witness in the sense that it is a *pair*
  whose second component is dependent on the first: the runtime cannot
  manufacture an `EssenceCommitted` whose `ecMode` is unrelated to
  `t`, because `commit` is the only constructor that produces an
  `EssenceCommitment` and it is total over trajectories.

This encoding gives both halves of the philosophical demand:

1. The choice is **forced**: when `shouldCommit em t = Just trigger`,
   the runtime must call `commit (currentTurnSeq) trigger t`; the type
   system does not allow `EssenceCommitted t c` without a prior
   `commit`.
2. The content is **free**: the `EssenceMode` inside `c` is
   `extractMode t`, which is a pure function of what the system has
   actually witnessed.  No call site picks the mode.

The forcing happens in §5; the freedom is encoded by the fact that
`extractMode` reads only the trajectory, not the call site, the wall
clock, or any external input.

## 5. Forcing dynamics

Two endogenous quantities drive commitment.  Both are already present
in the codebase as pre-turn signals; the essence layer reads them, it
does not synthesise them.

### 5.1 Angst accrual

`etAngstLevel` is the per-trajectory scalar in `[0, 1]`:

- Accrues by `emAngstAccrualRate` per turn when the deliberation rule
  is `RuleHolisticAdvantage` or `RuleFormalAdvantage` (i.e. the
  hemispheres disagree on family or style) **and** the divergence
  exceeds `emAngstAccrualDivergenceFloor`.
- Decays by `emAngstDecayRate` per turn under
  `Agreement = FullAgreement` with `dtDivergence == 0`.
- Stays put under `RuleConatusOverride` (the system is already in a
  recovery regime; angst neither rises nor falls until the gate
  releases).
- Saturates at `1.0` and floors at `0.0`.

`shouldCommit` returns `Just TriggerAngstThreshold` iff
`etAngstLevel ≥ emAngstCommitmentThreshold`.

### 5.2 Conatus erosion

`etConatusFloor` tracks the minimum `ConatusEnergy` observed over
`emConatusFloorWindow` consecutive turns.

`shouldCommit` returns `Just TriggerConatusErosion` iff
`etConatusFloor < emConatusStructuralFloor` for the full window.

If both triggers fire on the same turn, `TriggerAngstThreshold`
takes priority (it is the more specific signal — Conatus erosion
manifests as angst).  This priority is encoded in `shouldCommit` and
guarded by a property test (§9).

### 5.3 What does *not* trigger commitment

- Wall-clock time, turn count, session age.
- External flags, environment variables, configuration.
- A single turn’s signals in isolation (every trigger is windowed or
  thresholded over accumulated trajectory).
- `IdentityRupture`.  An identity rupture aborts the session; it does
  not commit an essence.  The two failure modes are orthogonal.

## 6. Witness ingestion and pipeline integration

Witness ingestion fits into the turn pipeline as a single pure call in
`buildPrepareEffectPlan` (or a sibling location in
`QxFx0.Core.TurnPipeline.Effects` — the precise call site is settled
in Phase 9 Step 1).  The flow:

```text
TurnInput, Deliberation
        │
        ▼
witness em turnSeq energy field delib trajectory
        │
        ▼
trajectory'        ← ingested, possibly with updated angst
        │
        ▼
shouldCommit em trajectory'
        │
        ├─ Nothing  → Essence stays EssenceUncommitted trajectory'
        └─ Just t   → Essence becomes
                         EssenceCommitted trajectory' (commit turnSeq t trajectory')
```

Two structural notes:

1. **Where the trajectory lives.**  In Phase 9, the trajectory is
   threaded through `SystemState` exactly the way `selfBlanket` is —
   it is a pure derivation of accumulated turns, persisted across
   commits, and projected into `TurnInput` once per turn so the
   pipeline reads a single source of truth (M6 discipline, see
   `AGENTS.md`).
2. **`FieldSignature`.**  Witnesses store a coarse signature of the
   field, not the field itself, to keep `EssenceTrajectory` bounded
   and the witness-equality property test cheap.  The signature is a
   four-tuple of bucketed components (resonance band, atmosphere
   band, consolidation band, counterfactual band); the bucketing
   thresholds live in `EssenceModulation` and are calibrated in
   Phase 9 Step 2.

The trace surface in `TurnReplayTrace` gains four nullable fields
(symmetry with the deliberation trace addition in Phase 8 B.7):

```haskell
, trcEssenceMode       :: !(Maybe Text)            -- renderEssenceMode
, trcEssenceCommitted  :: !(Maybe Bool)
, trcEssenceAngstLevel :: !(Maybe Double)
, trcEssenceTrigger    :: !(Maybe Text)            -- renderCommitmentTrigger
                                                   --   when committed this turn
```

These are populated in `buildTurnProjection` in Phase 9 Step 3 and
remain `Nothing` everywhere essence ingestion is disabled or absent —
mirroring the deliberation-trace rollout pattern.

## 7. Post-commitment constraint and `EssenceRupture`

Once an `Essence` is `EssenceCommitted`, every subsequent `Plan`
emitted by `reconcile` must satisfy the committed mode.  The
constraint is encoded as a pure validator:

```haskell
validatePlan :: EssenceCommitment -> Plan -> Either EssenceViolation Plan

data EssenceViolation
  = ViolationFamilyMismatch       !EssenceMode !CanonicalMoveFamily
  | ViolationToneMismatch         !EssenceMode !NarrativeTone
  | ViolationStyleMismatch        !EssenceMode !RenderStyle
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)
```

The mode-to-admissible-plan mapping is closed and minimal:

| `EssenceMode` | Admissible families | Admissible tones | Admissible styles |
|---------------|--------------------|------------------|-------------------|
| `EssenceContemplative` | `CMDescribe`, `CMHypothesis`, `CMPurpose`, `CMRepair` | `NarrativeNeutral`, `NarrativeTerse` | non-warm |
| `EssenceDialogical`    | `CMContact`, `CMDeepen`, `CMRepair`, `CMReflect` | `NarrativeNeutral`, `NarrativeWarm` | non-recovery |
| `EssenceIntegrative`   | all | all | all |
| `EssenceWitnessing`    | (unreachable post-commit) | — | — |

`CMRepair` and `NarrativeNeutral` are *always* admissible across
modes — recovery and tonal neutrality are never an essence violation.
This is non-negotiable (§5.3: identity rupture is orthogonal).

Violations propagate as a new exception variant in
`QxFx0.ExceptionPolicy`:

```haskell
data QxFx0Exception
  = ...                      -- existing variants
  | EssenceRupture !Text     -- ^ Post-commitment Plan violates committed
                             --   essence.  Categorical failure: the system
                             --   has produced a decision incompatible with
                             --   what it has become.  Not recoverable in
                             --   the @PersistenceError@ sense; the runtime
                             --   should refuse to commit the turn.
```

The validator is invoked in `Finalize.Commit` *before* persistence, in
the same phase where `checkBlanketTransition` already runs.  The two
guards are deliberately co-located: `IdentityRupture` says “the
running system is no longer this system”; `EssenceRupture` says “the
running system has acted contrary to what this system has chosen to
be”.  Both abort the turn, both are non-recoverable, neither is
silenced by recovery causes.

## 8. Phase plan

Phase 9 lands the selection infrastructure with `Essence` permanently
`EssenceUncommitted`; Phase 10 enables forcing.

### Phase 9 — Essence Selection Infrastructure

| Step | Deliverable | Suite |
|------|-------------|-------|
| 9.1 | `QxFx0.Self.Essence` module: types, `defaultEssenceModulation`, `witness`, `extractMode`, `shouldCommit`, `commit` (commit logic present but unused). | `Test.Suite.SelfEssence` (new): determinism of `extractMode`, idempotence of `witness` under `FullAgreement`, monotonicity of `etAngstLevel` under sustained divergence. |
| 9.2 | Trajectory threading through `SystemState` and `TurnInput` (`tiEssence :: !Essence`); single-source-of-truth via `PrepareStatic`. | Existing pipeline integration tests retain green; one new integration test asserts `tiEssence` is `EssenceUncommitted` in the absence of triggering signals. |
| 9.3 | Trace fields populated in `buildTurnProjection`: `trcEssenceMode`, `trcEssenceCommitted`, `trcEssenceAngstLevel`, `trcEssenceTrigger`.  All four remain `Nothing` until commit. | Trace property test asserts the four fields appear in the JSON schema. |
| 9.4 | ADR-0012 status flips from **Proposed** to **Accepted (Phase 9, infrastructure only)**; addendum records observed angst dynamics on the corpus. | — |

Phase 9 ships *no behavioural change*.  Witnesses accumulate, angst
moves, the trace records it; no `Plan` is constrained.

### Phase 10 — Forced Commitment and Post-commitment Guard

| Step | Deliverable | Suite |
|------|-------------|-------|
| 10.1 | `essenceCommitmentEnabled :: Bool` feature flag (default `False`), gating the `shouldCommit`/`commit` invocation in the prepare stage. | `Test.Suite.SelfEssenceCommit` (new): under flag-on, a hand-built trajectory crossing the angst threshold yields `EssenceCommitted` exactly once and never reverts. |
| 10.2 | `validatePlan` invoked in `Finalize.Commit`, between `checkBlanketTransition` and persistence.  Failures throw `EssenceRupture`. | Integration test: under flag-on with a forced commit to `EssenceContemplative`, a turn whose reconciled `Plan` selects `CMContact` raises `EssenceRupture` and aborts the turn. |
| 10.3 | Reconcile-time courtesy: `reconcile` accepts an optional `Maybe EssenceCommitment` and biases tied fallback toward admissible families *before* `validatePlan` runs.  The guard is still authoritative; this only reduces avoidable ruptures. | Property test: under any committed mode, `reconcile` never widens the admissible family set; ties strictly within the admissible set are preferred. |
| 10.4 | Flag flipped to `True` in production after one corpus replay confirms zero spurious ruptures and bounded angst dynamics. ADR-0012 status flips to **Accepted (Phase 10, fully enabled)**. | Corpus replay job must report zero `EssenceRupture` events on the historical trace and at least one expected commitment in the synthetic high-angst fixture. |

Phase 10 is gated behind the flag for the same reason Phase 8 D was:
the change is observable in the trace and load-bearing for the
runtime, so we want a corpus pass before turning it on by default.

## 9. Test contract

The following property and integration tests are mandatory and form
the regression locks for the essence layer.  They are the answer to
fork #4 (coherence) and fork #5 (extraction determinism) at the
property level.

| Lock | Suite | What it guards |
|------|-------|----------------|
| E1 | `Test.Suite.SelfEssence` | `extractMode` is deterministic over `EssenceTrajectory` and never returns `EssenceWitnessing`. |
| E2 | `Test.Suite.SelfEssence` | `witness` under `Agreement = FullAgreement` and `dtDivergence == 0` strictly decreases `etAngstLevel` (or holds at `0.0`). |
| E3 | `Test.Suite.SelfEssence` | `witness` under `RuleHolisticAdvantage`/`RuleFormalAdvantage` with divergence above floor strictly increases `etAngstLevel` (or holds at `1.0`). |
| E4 | `Test.Suite.SelfEssence` | `shouldCommit` is monotone: once `Just _`, no continuation of the trajectory turns it back to `Nothing` without a `commit` step. |
| E5 | `Test.Suite.SelfEssence` | If both triggers fire, `shouldCommit` returns `Just TriggerAngstThreshold` (priority lock). |
| E6 | `Test.Suite.SelfEssenceCommit` (Phase 10) | `EssenceCommitted` is sticky across turns; no codepath produces `EssenceUncommitted` from `EssenceCommitted`. |
| E7 | `Test.Suite.SelfEssenceCommit` (Phase 10) | `validatePlan` admits `CMRepair` and `NarrativeNeutral` under every `EssenceMode`. |
| E8 | `Test.Suite.SelfEssenceCommit` (Phase 10) | Under flag-on, the corpus replay produces zero `EssenceRupture` events on the historical trace. |

## 10. Honest limits

ADR-0012 is deliberately bounded.  The following are **out of scope**
and require their own ADRs if pursued:

- **Multiple essences per session.**  Fork #8 chose singular; revisiting
  it would mean introducing a session-layer multiplexer, which is a
  different architectural problem.
- **External essence summons.**  Fork #3 chose endogenous-only.  An
  externally-imposed essence (e.g. operator override) would be a new
  exception variant and a new commitment trigger; not covered here.
- **Essence-aware Conatus weights.**  The `Conatus` functional currently
  has fixed weights (`ConatusWeights`).  Tuning weights to the
  committed mode (e.g. `EssenceContemplative` weights consolidation
  more) is a natural extension but is deferred until Phase 9
  observational data exists.
- **Empirical calibration of `EssenceModulation`.**  Phase 9.1 ships
  with hand-set defaults inheriting the conservatism of
  `defaultSalienceModulation`.  Calibration against trace corpora is
  Phase 9 Step 2 follow-up, not part of the contract.
- **Cross-session essence persistence.**  An essence committed in one
  session does not currently constrain the next session.  Whether it
  *should* (continuous personhood across sessions) is a question for
  the runtime layer, not this ADR.

## 11. Open questions (for review before flipping status)

1. **Angst saturation semantics.**  Should saturation at `1.0` itself
   count as a trigger, or only crossing `emAngstCommitmentThreshold`?
   Current spec says only the threshold; saturation-as-trigger is
   simpler but loses the tunable.
2. **Commitment trigger priority.**  `TriggerAngstThreshold > TriggerConatusErosion`
   is locked by E5, but could be inverted if the corpus reveals that
   Conatus erosion is the more discriminative signal.
3. **`EssenceWitnessing` as a runtime-visible mode.**  The spec keeps
   it as a sentinel only.  An alternative is to expose it as an
   admissible runtime mode (every essence-uncommitted trajectory is
   "witnessing"), with the trace setting `trcEssenceMode = Just "witnessing"`
   pre-commit.  Decision deferred to Phase 9.3 review.
4. **Validator location.**  Spec puts `validatePlan` in
   `Finalize.Commit`.  An alternative is to put it in `reconcile`
   itself (essence-aware reconciliation).  The current placement
   matches the `IdentityRupture` discipline; the alternative reduces
   exception traffic but couples two layers we have so far kept pure
   and independent.

These four questions should be settled before the ADR moves from
**Proposed** to **Accepted (Phase 9, infrastructure only)**.

## 12. Relation to existing layers

For completeness, a single diagram of how the essence layer sits in
the runtime, in the same notation used by ADR-0011 §6:

```text
┌─────────────────────── Phase 1–2 ─────────────────────────┐
│ SelfBlanket  ←  computeSelfBlanket  ←  SystemState        │
│ Conatus      ←  computeConatusEnergy ←  SelfBlanket       │
└────────────────────────────┬──────────────────────────────┘
                             │
┌──────── Phase 3 ────┐  ┌── Phase 4 ──┐  ┌── Phase 5 ───┐
│ Holistic ⊣ Formal   │  │ Field (×5)  │  │ Salience      │
└─────────┬───────────┘  └──────┬──────┘  └──────┬────────┘
          │                     │                │
          └───────── Phase 8 (Deliberation) ─────┘
                             │
                             ▼  reconcile
                      ┌───── Plan ─────┐
                      │ family/style/  │
                      │ tone/recovery  │
                      └────┬───────────┘
                           │
        ┌──────────────── Phase 9–10 (this ADR) ───────────┐
        │ witness     →  EssenceTrajectory                 │
        │ shouldCommit ?  → CommitmentTrigger              │
        │ commit       →  EssenceCommitment                │
        │ validatePlan →  EssenceRupture | Plan            │
        └──────────────────────────────────────────────────┘
                             │
                             ▼
                       Finalize.Commit
                       (IdentityRupture | EssenceRupture | persist)
```

The essence layer is the topmost pure layer.  It reads everything
below it and constrains what may be persisted; it never feeds
downward.

## 13. Phase 9 open questions — resolved

The four questions from §11 were settled as part of the
`phase-9-essence-implementation-spec.md` contract and locked
into the implementation.  This addendum records the resolutions
so the ADR matches the code.

| # | Question | Resolution |
|---|----------|------------|
| Q1 | Saturation as trigger | **No.** Only `etAngstLevel ≥ emAngstCommitmentThreshold` counts. Saturation at `1.0` is a tail state, not an event. |
| Q2 | Trigger priority on simultaneous fire | **Angst > Conatus.** `shouldCommit` returns `Just TriggerAngstThreshold` when both fire. Property test E5 locks this. |
| Q3 | `EssenceWitnessing` as runtime-visible mode | **Yes.** Pre-commit, `trcEssenceMode = Just "witnessing"`. The sentinel is observably distinct from `Nothing` (essence layer disabled) and from any committed mode. |
| Q4 | `validatePlan` location | **Stays in `Finalize.Commit`** when Phase 10 lands. Phase 9 ships no validator — `reconcile` stays pure and essence-unaware. |

These resolutions are now architectural fact; any Phase-10
review that wishes to reopen them requires a new ADR revision.

## 14. Phase 10 closure note

Phase 10 landed 2026-05-19. Concrete deltas vs. the architecture
described above:

- `essenceCommitmentEnabled :: Bool` is plumbed through
  `PrepareStatic` and `TurnInput` (single-source-of-truth, M6).
  Default `False`.
- `validatePlan :: EssenceCommitment -> Plan -> Either EssenceViolation Plan`
  with admissibility tables exactly as §7.  `CMRepair` and
  `NarrativeNeutral` always admissible (locked by E7a/E7b).
- `shouldCommit` uses true sliding-window semantics over the last
  `emConatusFloorWindow` witnesses (Q7), replacing the Phase-9
  approximation.
- The validator is computed in `Finalize.State` (where `tiEssence`
  and `tpDeliberation` are in scope) and thrown in `Finalize.Commit`
  immediately after `checkBlanketTransition`, before persistence.
- A turn that *causes* commitment is not validated by the new
  commitment (Q5) — the commitment binds future turns only.
- Reconcile-time courtesy: `reconcile` accepts an optional
  `Maybe (Plan -> Bool)` predicate.  When `RuleTiedFallback` fires
  and exactly one tied proposal satisfies the predicate, the fallback
  switches to it.  Never widens (locked by C1).
- Corpus replay under `QXFX0_ESSENCE_COMMITMENT_ENABLED=1` produced
  zero `EssenceRupture` events on the 25-session integration corpus
  on 2026-05-19.

The four §10 out-of-scope items remain so.  The §11 open questions
and §13 Phase-9 resolutions are now historical record.

— end of Phase 10 closure note —

## 15. Phase 10 calibration addendum (corpus replay findings)

Phase 10 §4 calibration ran the long-session corpus harness
(`docs/post-phase-10-roadmap-closure-spec.md` §3) under
`QXFX0_ESSENCE_COMMITMENT_ENABLED=1` and produced two findings.

### 15.1 Unit-mismatch in `emConatusStructuralFloor` (corrected)

Across 70 turns of the synthetic corpus, observed
`ewConatusScalar ∈ [14.2, 15.0]`, never approaching the
`emConatusStructuralFloor = 0.5` set in Phase 9.

Root cause: `computeConatusEnergy` produces a log-scale
unbounded scalar (`log1p(m) + 0.5*log1p(c) + 0.25*log1p(t) − 10*|v|`),
not a unit-interval value. For a mature system this lives in
`[~5, ~20+]`. The Phase 9 floor of `0.5` was calibrated against
`Test.Suite.SelfEssence` generators using `arbitraryUnitDouble`,
which produced `ceScalar ∈ [0, 1]` and masked the production
range. `TriggerConatusErosion` could not fire in production
under Phase 9 defaults.

Correction: `emConatusStructuralFloor = 7.0` (≈ half of
observed healthy `ceScalar`). Semantic: erosion alert when
Conatus has dropped to half its healthy state, corresponding to
≈ one sustained `BlanketViolation`. The Phase 9 value remains
accessible as `phase9EssenceModulation` for regression locks.

### 15.2 Angst calibration deferred (synthetic-corpus deadlock)

The synthetic JSONL fixtures could not reliably produce
`RuleHolisticAdvantage` or `RuleFormalAdvantage` with
`dtDivergence ≥ emAngstAccrualDivergenceFloor`. Across 70
turns, `etAngstLevel` remained at `0.0`. The blockage is
upstream of `EssenceModulation`: the text → field → salience
→ proposals → reconcile pipeline is too non-linear to
reverse-engineer specific deliberation rules from text inputs.

Implication: angst-side parameters
(`emAngstCommitmentThreshold`, `emAngstAccrualRate`,
`emAngstDecayRate`, `emAngstAccrualDivergenceFloor`) remain
at Phase 9 values. Future calibration requires either:

- Production trace ingestion (real `Deliberation` values
  emitted by the runtime under real load), or
- A test-only `Deliberation` injection hook in `Finalize.State`
  that bypasses the text → field path.

Both options exceed Phase 10 scope. Synthetic long-session
corpora remain useful as "no rupture under realistic dynamics"
smoke tests but are unsuitable for angst-threshold validation.

### 15.3 Methodology lesson

Phase 9 modulation defaults were validated against unit-test
generators (`arbitraryUnitDouble`), not production runtime.
This left two latent issues (one corrected here, one deferred).
Future modulation parameters in `QxFx0.Self.*` must be sanity-
checked against the actual codomain of the signals they gate.

— end of ADR-0012 —
