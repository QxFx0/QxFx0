{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionOperationalStatusAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionOperationalStatusAdmission
  ( PropositionOperationalStatusAdmissionInput, PropositionOperationalStatusAdmissionDecision, RawPropositionOperationalStatusTrigger, AdmittedPropositionOperationalStatusTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionOperationalStatusAdmissionInput = PropositionAdmissionInput
type PropositionOperationalStatusAdmissionDecision = PropositionAdmissionDecision
type RawPropositionOperationalStatusTrigger = RawPropositionTrigger
type AdmittedPropositionOperationalStatusTriggers = AdmittedPropositionTriggers
