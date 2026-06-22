{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionNextStepAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionNextStepAdmission
  ( PropositionNextStepAdmissionInput, PropositionNextStepAdmissionDecision, RawPropositionNextStepTrigger, AdmittedPropositionNextStepTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionNextStepAdmissionInput = PropositionAdmissionInput
type PropositionNextStepAdmissionDecision = PropositionAdmissionDecision
type RawPropositionNextStepTrigger = RawPropositionTrigger
type AdmittedPropositionNextStepTriggers = AdmittedPropositionTriggers
