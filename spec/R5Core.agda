{-# OPTIONS --without-K #-}

module R5Core where

-- Canonical R5 vocabulary and constructive invariants.
-- This module is kept proof-backed; incomplete higher-level specs live elsewhere.

open import Agda.Builtin.Bool
open import Agda.Builtin.Nat
open import Agda.Builtin.List
open import Agda.Builtin.String
open import Agda.Builtin.Equality using (_≡_; refl)

data CanonicalMoveFamily : Set where
  CMGround      : CanonicalMoveFamily
  CMDefine      : CanonicalMoveFamily
  CMDistinguish : CanonicalMoveFamily
  CMReflect     : CanonicalMoveFamily
  CMDescribe    : CanonicalMoveFamily
  CMPurpose     : CanonicalMoveFamily
  CMHypothesis  : CanonicalMoveFamily
  CMRepair      : CanonicalMoveFamily
  CMContact     : CanonicalMoveFamily
  CMAnchor      : CanonicalMoveFamily
  CMClarify     : CanonicalMoveFamily
  CMDeepen      : CanonicalMoveFamily
  CMConfront    : CanonicalMoveFamily
  CMNextStep    : CanonicalMoveFamily

{-# COMPILE GHC CanonicalMoveFamily = data QxFx0.Types.CanonicalMoveFamily
  ( QxFx0.Types.CMGround
  | QxFx0.Types.CMDefine
  | QxFx0.Types.CMDistinguish
  | QxFx0.Types.CMReflect
  | QxFx0.Types.CMDescribe
  | QxFx0.Types.CMPurpose
  | QxFx0.Types.CMHypothesis
  | QxFx0.Types.CMRepair
  | QxFx0.Types.CMContact
  | QxFx0.Types.CMAnchor
  | QxFx0.Types.CMClarify
  | QxFx0.Types.CMDeepen
  | QxFx0.Types.CMConfront
  | QxFx0.Types.CMNextStep
  ) #-}

data IllocutionaryForce : Set where
  IFAsk      : IllocutionaryForce
  IFAssert   : IllocutionaryForce
  IFOffer    : IllocutionaryForce
  IFConfront : IllocutionaryForce
  IFContact  : IllocutionaryForce

{-# COMPILE GHC IllocutionaryForce = data QxFx0.Types.IllocutionaryForce
  ( QxFx0.Types.IFAsk
  | QxFx0.Types.IFAssert
  | QxFx0.Types.IFOffer
  | QxFx0.Types.IFConfront
  | QxFx0.Types.IFContact
  ) #-}

data SemanticLayer : Set where
  ContentLayer : SemanticLayer
  MetaLayer    : SemanticLayer
  ContactLayer : SemanticLayer

{-# COMPILE GHC SemanticLayer = data QxFx0.Types.SemanticLayer
  ( QxFx0.Types.ContentLayer
  | QxFx0.Types.MetaLayer
  | QxFx0.Types.ContactLayer
  ) #-}

data ClauseForm : Set where
  Declarative   : ClauseForm
  Interrogative : ClauseForm
  Imperative    : ClauseForm
  Hortative     : ClauseForm

{-# COMPILE GHC ClauseForm = data QxFx0.Types.ClauseForm
  ( QxFx0.Types.Declarative
  | QxFx0.Types.Interrogative
  | QxFx0.Types.Imperative
  | QxFx0.Types.Hortative
  ) #-}

data WarrantedMoveMode : Set where
  AlwaysWarranted         : WarrantedMoveMode
  NeverWarranted          : WarrantedMoveMode
  ConditionallyWarranted  : WarrantedMoveMode

{-# COMPILE GHC WarrantedMoveMode = data QxFx0.Types.WarrantedMoveMode
  ( QxFx0.Types.AlwaysWarranted
  | QxFx0.Types.NeverWarranted
  | QxFx0.Types.ConditionallyWarranted
  ) #-}

isContentFamily : CanonicalMoveFamily → Bool
isContentFamily CMGround      = true
isContentFamily CMDefine      = true
isContentFamily CMDistinguish = true
isContentFamily CMReflect     = false
isContentFamily CMDescribe    = true
isContentFamily CMPurpose     = true
isContentFamily CMHypothesis  = false
isContentFamily CMRepair      = false
isContentFamily CMContact     = false
isContentFamily CMAnchor      = true
isContentFamily CMClarify     = false
isContentFamily CMDeepen      = false
isContentFamily CMConfront    = false
isContentFamily CMNextStep    = false

forceForFamily : CanonicalMoveFamily → IllocutionaryForce
forceForFamily CMGround      = IFAssert
forceForFamily CMDefine      = IFAssert
forceForFamily CMDistinguish = IFAssert
forceForFamily CMReflect     = IFAssert
forceForFamily CMDescribe    = IFAssert
forceForFamily CMPurpose     = IFAssert
forceForFamily CMHypothesis  = IFAsk
forceForFamily CMRepair      = IFOffer
forceForFamily CMContact     = IFContact
forceForFamily CMAnchor      = IFAssert
forceForFamily CMClarify     = IFAsk
forceForFamily CMDeepen      = IFAsk
forceForFamily CMConfront    = IFConfront
forceForFamily CMNextStep    = IFOffer

clauseFormForIF : IllocutionaryForce → ClauseForm
clauseFormForIF IFAsk      = Interrogative
clauseFormForIF IFAssert   = Declarative
clauseFormForIF IFOffer    = Hortative
clauseFormForIF IFConfront = Imperative
clauseFormForIF IFContact  = Declarative

layerForFamily : CanonicalMoveFamily → SemanticLayer
layerForFamily CMGround      = ContentLayer
layerForFamily CMDefine      = ContentLayer
layerForFamily CMDistinguish = ContentLayer
layerForFamily CMReflect     = MetaLayer
layerForFamily CMDescribe    = ContentLayer
layerForFamily CMPurpose     = ContentLayer
layerForFamily CMHypothesis  = MetaLayer
layerForFamily CMRepair      = MetaLayer
layerForFamily CMContact     = ContactLayer
layerForFamily CMAnchor      = ContentLayer
layerForFamily CMClarify     = MetaLayer
layerForFamily CMDeepen      = MetaLayer
layerForFamily CMConfront    = MetaLayer
layerForFamily CMNextStep    = MetaLayer

warrantedForFamily : CanonicalMoveFamily → WarrantedMoveMode
warrantedForFamily CMGround      = AlwaysWarranted
warrantedForFamily CMDefine      = AlwaysWarranted
warrantedForFamily CMDistinguish = ConditionallyWarranted
warrantedForFamily CMReflect     = AlwaysWarranted
warrantedForFamily CMDescribe    = AlwaysWarranted
warrantedForFamily CMPurpose     = ConditionallyWarranted
warrantedForFamily CMHypothesis  = ConditionallyWarranted
warrantedForFamily CMRepair      = AlwaysWarranted
warrantedForFamily CMContact     = AlwaysWarranted
warrantedForFamily CMAnchor      = AlwaysWarranted
warrantedForFamily CMClarify     = ConditionallyWarranted
warrantedForFamily CMDeepen      = ConditionallyWarranted
warrantedForFamily CMConfront    = NeverWarranted
warrantedForFamily CMNextStep    = ConditionallyWarranted

record R5Verdict : Set where
  field
    vFamily    : CanonicalMoveFamily
    vForce     : IllocutionaryForce
    vClause    : ClauseForm
    vLayer     : SemanticLayer
    vWarranted : WarrantedMoveMode

{-# COMPILE GHC R5Verdict = data QxFx0.Types.R5Verdict (QxFx0.Types.R5Verdict) #-}

mkVerdict : CanonicalMoveFamily → R5Verdict
mkVerdict f = record
  { vFamily    = f
  ; vForce     = forceForFamily f
  ; vClause    = clauseFormForIF (forceForFamily f)
  ; vLayer     = layerForFamily f
  ; vWarranted = warrantedForFamily f
  }

{-# COMPILE GHC mkVerdict = QxFx0.Types.mkVerdict #-}

data ⊥ : Set where
data ⊤ : Set where
  tt : ⊤

infix 3 ¬_
¬_ : Set → Set
¬ P = P → ⊥

sym : {A : Set} {x y : A} → x ≡ y → y ≡ x
sym refl = refl

contentNotClarify : (f : CanonicalMoveFamily) → isContentFamily f ≡ true → f ≡ CMClarify → ⊥
contentNotClarify CMClarify () q
contentNotClarify CMReflect () q
contentNotClarify CMHypothesis () q
contentNotClarify CMRepair () q
contentNotClarify CMContact () q
contentNotClarify CMDeepen () q
contentNotClarify CMConfront () q
contentNotClarify CMNextStep () q
contentNotClarify CMGround p ()
contentNotClarify CMDefine p ()
contentNotClarify CMDistinguish p ()
contentNotClarify CMDescribe p ()
contentNotClarify CMPurpose p ()
contentNotClarify CMAnchor p ()

metaNotContent : (f : CanonicalMoveFamily) → layerForFamily f ≡ MetaLayer → isContentFamily f ≡ true → ⊥
metaNotContent CMReflect refl ()
metaNotContent CMHypothesis refl ()
metaNotContent CMRepair refl ()
metaNotContent CMClarify refl ()
metaNotContent CMDeepen refl ()
metaNotContent CMConfront refl ()
metaNotContent CMNextStep refl ()
metaNotContent CMGround () c
metaNotContent CMDefine () c
metaNotContent CMDistinguish () c
metaNotContent CMDescribe () c
metaNotContent CMPurpose () c
metaNotContent CMAnchor () c
metaNotContent CMContact () c

hypothesisIsAsk : (f : CanonicalMoveFamily) → f ≡ CMHypothesis → forceForFamily f ≡ IFAsk
hypothesisIsAsk .CMHypothesis refl = refl

warrantedConsistent : (f : CanonicalMoveFamily) → warrantedForFamily f ≡ NeverWarranted → f ≡ CMConfront
warrantedConsistent CMConfront refl = refl

confrontIsImperative : (f : CanonicalMoveFamily) → f ≡ CMConfront → clauseFormForIF (forceForFamily f) ≡ Imperative
confrontIsImperative .CMConfront refl = refl
