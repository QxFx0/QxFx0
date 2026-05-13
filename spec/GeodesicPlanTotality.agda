{-# OPTIONS --without-K #-}

module GeodesicPlanTotality where

-- Structural invariant: GeodesicPlan is a total type (every value is either
-- DirectJump or BridgedJump). This is a totality proof on an ADT, not a formal
-- verification of topic transition routing correctness.

open import Agda.Builtin.List
open import Agda.Builtin.String
open import Agda.Builtin.Equality using (_≡_; refl)

data GeodesicPlan : Set where
  DirectJump  : GeodesicPlan
  BridgedJump : List String → GeodesicPlan

-- We do not attach COMPILE GHC because the Haskell counterpart uses [Text]
-- rather than [String], and our verification pipeline only type-checks Agda.

data _⊎_ (A B : Set) : Set where
  inj₁ : A → A ⊎ B
  inj₂ : B → A ⊎ B

record Σ (A : Set) (B : A → Set) : Set where
  constructor _,_
  field
    fst : A
    snd : B fst
open Σ public

geodesicPlanTotal
  : (p : GeodesicPlan)
  → (p ≡ DirectJump)
    ⊎ (Σ (List String) (λ xs → p ≡ BridgedJump xs))
geodesicPlanTotal DirectJump = inj₁ refl
geodesicPlanTotal (BridgedJump xs) = inj₂ (xs , refl)
