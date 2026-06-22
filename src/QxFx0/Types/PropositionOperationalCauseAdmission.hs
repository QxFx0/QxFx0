{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionOperationalCauseAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionOperationalCauseAdmission
  ( PropositionOperationalCauseAdmissionInput, PropositionOperationalCauseAdmissionDecision, RawPropositionOperationalCauseTrigger, AdmittedPropositionOperationalCauseTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionOperationalCauseAdmissionInput = PropositionAdmissionInput
type PropositionOperationalCauseAdmissionDecision = PropositionAdmissionDecision
type RawPropositionOperationalCauseTrigger = RawPropositionTrigger
type AdmittedPropositionOperationalCauseTriggers = AdmittedPropositionTriggers
