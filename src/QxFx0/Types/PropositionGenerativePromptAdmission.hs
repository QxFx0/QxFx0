{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionGenerativePromptAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionGenerativePromptAdmission
  ( PropositionGenerativePromptAdmissionInput, PropositionGenerativePromptAdmissionDecision, RawPropositionGenerativePromptTrigger, AdmittedPropositionGenerativePromptTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionGenerativePromptAdmissionInput = PropositionAdmissionInput
type PropositionGenerativePromptAdmissionDecision = PropositionAdmissionDecision
type RawPropositionGenerativePromptTrigger = RawPropositionTrigger
type AdmittedPropositionGenerativePromptTriggers = AdmittedPropositionTriggers
