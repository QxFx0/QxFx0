{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionSystemLogicAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionSystemLogicAdmission
  ( PropositionSystemLogicAdmissionInput, PropositionSystemLogicAdmissionDecision, RawPropositionSystemLogicTrigger, AdmittedPropositionSystemLogicTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionSystemLogicAdmissionInput = PropositionAdmissionInput
type PropositionSystemLogicAdmissionDecision = PropositionAdmissionDecision
type RawPropositionSystemLogicTrigger = RawPropositionTrigger
type AdmittedPropositionSystemLogicTriggers = AdmittedPropositionTriggers
