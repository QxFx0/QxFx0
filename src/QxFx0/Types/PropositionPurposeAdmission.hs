{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionPurposeAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionPurposeAdmission
  ( PropositionPurposeAdmissionInput, PropositionPurposeAdmissionDecision, RawPropositionPurposeTrigger, AdmittedPropositionPurposeTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionPurposeAdmissionInput = PropositionAdmissionInput
type PropositionPurposeAdmissionDecision = PropositionAdmissionDecision
type RawPropositionPurposeTrigger = RawPropositionTrigger
type AdmittedPropositionPurposeTriggers = AdmittedPropositionTriggers
