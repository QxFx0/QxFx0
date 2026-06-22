{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionContactAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionContactAdmission
  ( PropositionContactAdmissionInput, PropositionContactAdmissionDecision, RawPropositionContactTrigger, AdmittedPropositionContactTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionContactAdmissionInput = PropositionAdmissionInput
type PropositionContactAdmissionDecision = PropositionAdmissionDecision
type RawPropositionContactTrigger = RawPropositionTrigger
type AdmittedPropositionContactTriggers = AdmittedPropositionTriggers
