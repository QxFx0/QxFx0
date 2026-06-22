{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionDistinctionAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionDistinctionAdmission
  ( PropositionDistinctionAdmissionInput, PropositionDistinctionAdmissionDecision, RawPropositionDistinctionTrigger, AdmittedPropositionDistinctionTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionDistinctionAdmissionInput = PropositionAdmissionInput
type PropositionDistinctionAdmissionDecision = PropositionAdmissionDecision
type RawPropositionDistinctionTrigger = RawPropositionTrigger
type AdmittedPropositionDistinctionTriggers = AdmittedPropositionTriggers
