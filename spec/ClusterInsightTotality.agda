{-# OPTIONS --without-K #-}

module ClusterInsightTotality where

-- Structural invariant: ClusterInsight is a total type (every value is either
-- NoClusters or TwoClusters). This is a totality proof on an ADT, not a formal
-- verification of spectral clustering correctness.

open import Agda.Builtin.List
open import Agda.Builtin.Float
open import Agda.Builtin.String
open import Agda.Builtin.Equality using (_≡_; refl)

data ClusterInsight : Set where
  NoClusters  : ClusterInsight
  TwoClusters : List String → List String → Float → ClusterInsight

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

clusterInsightTotal
  : (c : ClusterInsight)
  → (c ≡ NoClusters)
    ⊎ (Σ (List String) (λ xs → Σ (List String) (λ ys → Σ Float (λ d → c ≡ TwoClusters xs ys d))))
clusterInsightTotal NoClusters = inj₁ refl
clusterInsightTotal (TwoClusters xs ys d) = inj₂ (xs , (ys , (d , refl)))
