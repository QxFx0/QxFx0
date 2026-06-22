{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionRepairDirectiveAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionRepairDirectiveAdmission
  ( PropositionRepairDirectiveAdmissionInput, PropositionRepairDirectiveAdmissionDecision, RawPropositionRepairDirectiveTrigger, AdmittedPropositionRepairDirectiveTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionRepairDirectiveAdmissionInput = PropositionAdmissionInput
type PropositionRepairDirectiveAdmissionDecision = PropositionAdmissionDecision
type RawPropositionRepairDirectiveTrigger = RawPropositionTrigger
type AdmittedPropositionRepairDirectiveTriggers = AdmittedPropositionTriggers
