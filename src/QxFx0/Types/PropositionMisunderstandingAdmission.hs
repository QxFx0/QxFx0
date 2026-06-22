{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionMisunderstandingAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionMisunderstandingAdmission
  ( PropositionMisunderstandingAdmissionInput, PropositionMisunderstandingAdmissionDecision, RawPropositionMisunderstandingTrigger, AdmittedPropositionMisunderstandingTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionMisunderstandingAdmissionInput = PropositionAdmissionInput
type PropositionMisunderstandingAdmissionDecision = PropositionAdmissionDecision
type RawPropositionMisunderstandingTrigger = RawPropositionTrigger
type AdmittedPropositionMisunderstandingTriggers = AdmittedPropositionTriggers
