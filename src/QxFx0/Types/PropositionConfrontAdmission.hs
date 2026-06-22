{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionConfrontAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionConfrontAdmission
  ( PropositionConfrontAdmissionInput, PropositionConfrontAdmissionDecision, RawPropositionConfrontTrigger, AdmittedPropositionConfrontTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionConfrontAdmissionInput = PropositionAdmissionInput
type PropositionConfrontAdmissionDecision = PropositionAdmissionDecision
type RawPropositionConfrontTrigger = RawPropositionTrigger
type AdmittedPropositionConfrontTriggers = AdmittedPropositionTriggers
