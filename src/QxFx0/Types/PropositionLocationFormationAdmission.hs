{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionLocationFormationAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionLocationFormationAdmission
  ( PropositionLocationFormationAdmissionInput, PropositionLocationFormationAdmissionDecision, RawPropositionLocationFormationTrigger, AdmittedPropositionLocationFormationTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionLocationFormationAdmissionInput = PropositionAdmissionInput
type PropositionLocationFormationAdmissionDecision = PropositionAdmissionDecision
type RawPropositionLocationFormationTrigger = RawPropositionTrigger
type AdmittedPropositionLocationFormationTriggers = AdmittedPropositionTriggers
