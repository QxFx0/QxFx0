{-# OPTIONS --without-K #-}

module BayesianCoverage where

-- Structural invariant: every FlashTrigger maps to a non-empty list of gap domains.
-- This is a coverage check on a closed enumeration, not an end-to-end formal
-- verification of runtime Bayesian inference behavior.

open import Agda.Builtin.Bool
open import Agda.Builtin.List
open import Agda.Builtin.String
open import Agda.Builtin.Equality using (_≡_; refl)

data HiddenBelief : Set where
  UserWantsDefine   : HiddenBelief
  UserWantsCompare  : HiddenBelief
  UserWantsConfront : HiddenBelief
  UserSeeksSupport  : HiddenBelief
  UserIsConfused    : HiddenBelief
  UserIsDistressed  : HiddenBelief

{-# COMPILE GHC HiddenBelief = data QxFx0.Types.HiddenBelief
  ( QxFx0.Types.UserWantsDefine
  | QxFx0.Types.UserWantsCompare
  | QxFx0.Types.UserWantsConfront
  | QxFx0.Types.UserSeeksSupport
  | QxFx0.Types.UserIsConfused
  | QxFx0.Types.UserIsDistressed
  ) #-}

data FlashTrigger : Set where
  DeepResonanceTrigger : FlashTrigger
  CrisisMomentTrigger  : FlashTrigger
  PureKernelTrigger    : FlashTrigger
  ConvergenceTrigger   : FlashTrigger

{-# COMPILE GHC FlashTrigger = data QxFx0.Types.Intuition.FlashTrigger
  ( QxFx0.Types.Intuition.DeepResonanceTrigger
  | QxFx0.Types.Intuition.CrisisMomentTrigger
  | QxFx0.Types.Intuition.PureKernelTrigger
  | QxFx0.Types.Intuition.ConvergenceTrigger
  ) #-}

-- Mirror of triggerToGapDomains (always returns a non-empty list)
triggerToGapDomains : FlashTrigger → List String
triggerToGapDomains ConvergenceTrigger   = "HumanPsychology" ∷ "CausalChains" ∷ []
triggerToGapDomains CrisisMomentTrigger  = "HumanPsychology" ∷ []
triggerToGapDomains DeepResonanceTrigger = "HumanPsychology" ∷ "CulturalAnthropology" ∷ []
triggerToGapDomains PureKernelTrigger    = "CausalChains" ∷ "RhetoricalAnalysis" ∷ []

nonEmpty : {A : Set} → List A → Bool
nonEmpty []       = false
nonEmpty (_ ∷ _)  = true

-- Proof: every flash trigger maps to a non-empty list of gap domains.
triggerToGapDomainsNonEmpty : (t : FlashTrigger) → nonEmpty (triggerToGapDomains t) ≡ true
triggerToGapDomainsNonEmpty DeepResonanceTrigger = refl
triggerToGapDomainsNonEmpty CrisisMomentTrigger  = refl
triggerToGapDomainsNonEmpty PureKernelTrigger    = refl
triggerToGapDomainsNonEmpty ConvergenceTrigger   = refl

-- Synonym to emphasise the universal claim.
allTriggersHaveDomains : (t : FlashTrigger) → nonEmpty (triggerToGapDomains t) ≡ true
allTriggersHaveDomains = triggerToGapDomainsNonEmpty
