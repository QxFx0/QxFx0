{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionExploratoryPromptAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionExploratoryPromptAdmission
  ( PropositionExploratoryPromptAdmissionInput, PropositionExploratoryPromptAdmissionDecision, RawPropositionExploratoryPromptTrigger, AdmittedPropositionExploratoryPromptTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionExploratoryPromptAdmissionInput = PropositionAdmissionInput
type PropositionExploratoryPromptAdmissionDecision = PropositionAdmissionDecision
type RawPropositionExploratoryPromptTrigger = RawPropositionTrigger
type AdmittedPropositionExploratoryPromptTriggers = AdmittedPropositionTriggers
