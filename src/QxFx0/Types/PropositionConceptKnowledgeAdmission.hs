{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionConceptKnowledgeAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionConceptKnowledgeAdmission
  ( PropositionConceptKnowledgeAdmissionInput, PropositionConceptKnowledgeAdmissionDecision, RawPropositionConceptKnowledgeTrigger, AdmittedPropositionConceptKnowledgeTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionConceptKnowledgeAdmissionInput = PropositionAdmissionInput
type PropositionConceptKnowledgeAdmissionDecision = PropositionAdmissionDecision
type RawPropositionConceptKnowledgeTrigger = RawPropositionTrigger
type AdmittedPropositionConceptKnowledgeTriggers = AdmittedPropositionTriggers
