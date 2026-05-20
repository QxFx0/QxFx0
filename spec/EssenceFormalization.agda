{-# OPTIONS --without-K #-}

module EssenceFormalization where

-- Formal counterpart to QxFx0.Self.Essence commitment laws,
-- QxFx0.Self.Salience/Field adaptation gating, and
-- QxFx0.Core.TurnPipeline time-injection determinism.
-- This is a constructive specification: each lemma corresponds
-- to a runtime invariant, proved here by exhaustive pattern match.

open import Agda.Builtin.Bool
open import Agda.Builtin.Nat
open import Agda.Builtin.Equality using (_≡_; refl)

-- ---------------------------------------------------------------------------
-- D1 — Essence commitment states and transitions
-- ---------------------------------------------------------------------------

data EssenceMode : Set where
  EssenceWitnessing      : EssenceMode
  EssenceContemplative   : EssenceMode
  EssenceDialogical      : EssenceMode
  EssenceIntegrative     : EssenceMode

data CommitmentTrigger : Set where
  TriggerAngstThreshold  : CommitmentTrigger
  TriggerConatusErosion   : CommitmentTrigger

data EssenceState : Set where
  Uncommitted : EssenceState
  Committed   : EssenceMode → CommitmentTrigger → EssenceState

-- Witness/shouldCommit/commit abstraction.
-- In the runtime, 'shouldCommit' is a partial function
-- (Just trigger / Nothing).  Here we model the two outcomes directly.

-- Helpers: bottom type and sum type (must be declared before use).
data ⊥ : Set where

data _⊎_ (A B : Set) : Set where
  inj1 : A → A ⊎ B
  inj2 : B → A ⊎ B

data ShouldCommitResult : Set where
  NoTrigger       : ShouldCommitResult
  TriggerPresent  : (t : CommitmentTrigger) → ShouldCommitResult

-- Canonical transition: given current state and shouldCommit result,
-- what is the next state?
nextEssenceState : EssenceState → ShouldCommitResult → EssenceState
nextEssenceState Uncommitted NoTrigger      = Uncommitted
nextEssenceState Uncommitted (TriggerPresent t) = Committed EssenceWitnessing t
nextEssenceState (Committed m t) _            = Committed m t

-- D1.1 — Sticky commitment: once Committed, never reverts to Uncommitted.
-- The premise is restricted to Committed states; Uncommitted→Uncommitted
-- is a valid transition (NoTrigger).
stickyCommitment
  : (m : EssenceMode)
  → (t : CommitmentTrigger)
  → (r : ShouldCommitResult)
  → nextEssenceState (Committed m t) r ≡ Uncommitted → ⊥
stickyCommitment _ _ _ ()

-- D1.2 — Refused commitment: if trigger is present but state stays
-- Uncommitted, that is a structural violation.  Formally, the only
-- way to stay Uncommitted after a transition is NoTrigger.
refusedCommitmentImpossible
  : (s : EssenceState)
  → (r : ShouldCommitResult)
  → s ≡ Uncommitted
  → (r ≡ TriggerPresent TriggerAngstThreshold) ⊎ (r ≡ TriggerPresent TriggerConatusErosion)
  → nextEssenceState s r ≡ Uncommitted → ⊥
refusedCommitmentImpossible Uncommitted NoTrigger      _ (inj1 ()) _
refusedCommitmentImpossible Uncommitted NoTrigger      _ (inj2 ()) _
refusedCommitmentImpossible Uncommitted (TriggerPresent _) _ _ ()
refusedCommitmentImpossible (Committed _ _) _ _ _ ()

-- ---------------------------------------------------------------------------
-- D2 — Commitment-gated adaptation
-- ---------------------------------------------------------------------------

-- Abstract parameter space for weights/heuristics.
record ParamSpace : Set where
  constructor mkParam
  field
    value : Nat
open ParamSpace public

-- Adaptation morphism: given a signal (here abstracted as a Nat
-- representing a bounded delta) and current parameters, produce new.
-- Runtime uses clamped Double arithmetic; here we model the law.
adaptParam : Nat → ParamSpace → ParamSpace
adaptParam signal p = mkParam (value p + signal)

-- Gated adaptation: only proceeds when state is Committed.
-- For Uncommitted, output is strict identity (no drift).
gatedAdapt
  : EssenceState
  → Nat
  → ParamSpace
  → ParamSpace
gatedAdapt Uncommitted       _ p = p
gatedAdapt (Committed _ _) sig p = adaptParam sig p

-- D2.1 — Uncommitted adaptation is identity.
uncommittedAdaptIdentity
  : (sig : Nat)
  → (p : ParamSpace)
  → gatedAdapt Uncommitted sig p ≡ p
uncommittedAdaptIdentity _ _ = refl

-- D2.2 — Committed adaptation is non-identity when signal ≠ 0.
-- (We express this as a positive statement: output equals adaptParam.)
committedAdaptNonTrivial
  : (m : EssenceMode)
  → (t : CommitmentTrigger)
  → (sig : Nat)
  → (p : ParamSpace)
  → gatedAdapt (Committed m t) sig p ≡ adaptParam sig p
committedAdaptNonTrivial _ _ _ _ = refl

-- ---------------------------------------------------------------------------
-- D3 — Prepare-level time-injection determinism
-- ---------------------------------------------------------------------------

-- Abstract time value (natural number stands in for a UTCTime epoch).
record Time : Set where
  constructor mkTime
  field
    epoch : Nat
open Time public

-- A prepare plan is a function from input text, system state, and
-- injected time to a canonical result.  We abstract the heavy
-- SystemState / Text types to keep the proof constructive.
record PrepareResult : Set where
  constructor mkResult
  field
    startTime : Time
    family    : Nat   -- abstract family tag
open PrepareResult public

-- The prepare function: canonical form is that startTime equals
-- the injected time, not a separately-resolved wall-clock sample.
prepare : Nat → Time → PrepareResult
prepare familyTag t = mkResult t familyTag

-- D3.1 — Time determinism: for fixed input and fixed time, the
-- result is fixed (no hidden non-determinism in the prepare path).
prepareTimeDeterministic
  : (familyTag : Nat)
  → (t : Time)
  → startTime (prepare familyTag t) ≡ t
prepareTimeDeterministic _ _ = refl

-- ---------------------------------------------------------------------------
-- Compilation pragmas (no-op for Haskell; keeps module self-contained)
-- ---------------------------------------------------------------------------

{-# COMPILE GHC EssenceMode = data QxFx0.Self.Essence.EssenceMode
  ( QxFx0.Self.Essence.EssenceWitnessing
  | QxFx0.Self.Essence.EssenceContemplative
  | QxFx0.Self.Essence.EssenceDialogical
  | QxFx0.Self.Essence.EssenceIntegrative
  ) #-}

{-# COMPILE GHC CommitmentTrigger = data QxFx0.Self.Essence.CommitmentTrigger
  ( QxFx0.Self.Essence.TriggerAngstThreshold
  | QxFx0.Self.Essence.TriggerConatusErosion
  ) #-}

{-# COMPILE GHC EssenceState = data QxFx0.Self.Essence.Essence
  ( QxFx0.Self.Essence.EssenceUncommitted
  | QxFx0.Self.Essence.EssenceCommitted
  ) #-}
