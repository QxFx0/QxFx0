{-# OPTIONS --without-K #-}

module Sovereignty where

-- Sovereignty specification sketch.
-- This file encodes constitutional validity predicates and constructor sync,
-- but is not positioned as a completed end-to-end formal proof layer.

open import Agda.Builtin.Bool
open import Agda.Builtin.String
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

data ⊥ : Set where
data ⊤ : Set where
  tt : ⊤

infixr 4 _,_
record _×_ (A B : Set) : Set where
  constructor _,_
  field
    fst : A
    snd : B
open _×_ public

infix 4 _≡_
data _≡_ {A : Set} (x : A) : A → Set where
  refl : x ≡ x

record SubjectState : Set where
  constructor subjectState
  field
    agencyWithinBounds : Bool
    tensionWithinBounds : Bool
open SubjectState public

IsLegitimate : SubjectState → CanonicalMoveFamily → Set
IsLegitimate s CMGround      = agencyWithinBounds s ≡ true
IsLegitimate s CMDefine      = agencyWithinBounds s ≡ true
IsLegitimate s CMDistinguish = agencyWithinBounds s ≡ true
IsLegitimate s CMReflect     = ⊤
IsLegitimate s CMDescribe    = agencyWithinBounds s ≡ true
IsLegitimate s CMPurpose     = agencyWithinBounds s ≡ true
IsLegitimate s CMHypothesis  = ⊤
IsLegitimate s CMRepair      = ⊤
IsLegitimate s CMContact     = ⊤
IsLegitimate s CMAnchor      = (agencyWithinBounds s ≡ true) × (tensionWithinBounds s ≡ true)
IsLegitimate s CMClarify     = ⊤
IsLegitimate s CMDeepen      = ⊤
IsLegitimate s CMConfront    = ⊥
IsLegitimate s CMNextStep    = ⊤

record Response (s : SubjectState) (f : CanonicalMoveFamily) : Set where
  field
    family : CanonicalMoveFamily
    legitimate : IsLegitimate s f
    content : String
open Response public

baseline-legitimacy : (s : SubjectState) → IsLegitimate s CMClarify
baseline-legitimacy s = tt

confront-never-legitimate : (s : SubjectState) → IsLegitimate s CMConfront → ⊥
confront-never-legitimate s ()

anchor-requires-bounds
  : (s : SubjectState)
  → IsLegitimate s CMAnchor
  → (agencyWithinBounds s ≡ true) × (tensionWithinBounds s ≡ true)
anchor-requires-bounds s proof = proof
