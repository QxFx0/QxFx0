{-# OPTIONS --without-K #-}

module FamilyCoverage where

-- Structural invariant: the families list is complete (covers every CanonicalMoveFamily).
-- This is an enumeration coverage check, not a formal verification of game-theoretic
-- routing correctness.

open import Agda.Builtin.Bool
open import Agda.Builtin.List
open import Agda.Builtin.Equality using (_≡_; refl)
open import R5Core using
  ( CanonicalMoveFamily
  ; CMGround
  ; CMDefine
  ; CMDistinguish
  ; CMReflect
  ; CMDescribe
  ; CMPurpose
  ; CMHypothesis
  ; CMRepair
  ; CMContact
  ; CMAnchor
  ; CMClarify
  ; CMDeepen
  ; CMConfront
  ; CMNextStep
  )

families : List CanonicalMoveFamily
families =
  CMGround    ∷
  CMDefine    ∷
  CMDistinguish ∷
  CMReflect   ∷
  CMDescribe  ∷
  CMPurpose   ∷
  CMHypothesis ∷
  CMRepair    ∷
  CMContact   ∷
  CMAnchor    ∷
  CMClarify   ∷
  CMDeepen    ∷
  CMConfront  ∷
  CMNextStep  ∷
  []

eqFamily : CanonicalMoveFamily → CanonicalMoveFamily → Bool
eqFamily CMGround      CMGround      = true
eqFamily CMDefine      CMDefine      = true
eqFamily CMDistinguish CMDistinguish = true
eqFamily CMReflect     CMReflect     = true
eqFamily CMDescribe    CMDescribe    = true
eqFamily CMPurpose     CMPurpose     = true
eqFamily CMHypothesis  CMHypothesis  = true
eqFamily CMRepair      CMRepair      = true
eqFamily CMContact     CMContact     = true
eqFamily CMAnchor      CMAnchor      = true
eqFamily CMClarify     CMClarify     = true
eqFamily CMDeepen      CMDeepen      = true
eqFamily CMConfront    CMConfront    = true
eqFamily CMNextStep    CMNextStep    = true
eqFamily _             _             = false

if_then_else_ : {A : Set} → Bool → A → A → A
if true  then t else _ = t
if false then _ else f = f

elem : {A : Set} → (A → A → Bool) → A → List A → Bool
elem _eq x [] = false
elem eq x (y ∷ ys) = if eq x y then true else elem eq x ys

familiesComplete : (f : CanonicalMoveFamily) → elem eqFamily f families ≡ true
familiesComplete CMGround      = refl
familiesComplete CMDefine      = refl
familiesComplete CMDistinguish = refl
familiesComplete CMReflect     = refl
familiesComplete CMDescribe    = refl
familiesComplete CMPurpose     = refl
familiesComplete CMHypothesis  = refl
familiesComplete CMRepair      = refl
familiesComplete CMContact     = refl
familiesComplete CMAnchor      = refl
familiesComplete CMClarify     = refl
familiesComplete CMDeepen      = refl
familiesComplete CMConfront    = refl
familiesComplete CMNextStep    = refl
