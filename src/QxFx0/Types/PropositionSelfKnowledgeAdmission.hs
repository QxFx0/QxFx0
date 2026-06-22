{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionSelfKnowledgeAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionSelfKnowledgeAdmission
  ( PropositionSelfKnowledgeAdmissionInput, PropositionSelfKnowledgeAdmissionDecision, RawPropositionSelfKnowledgeTrigger, AdmittedPropositionSelfKnowledgeTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionSelfKnowledgeAdmissionInput = PropositionAdmissionInput
type PropositionSelfKnowledgeAdmissionDecision = PropositionAdmissionDecision
type RawPropositionSelfKnowledgeTrigger = RawPropositionTrigger
type AdmittedPropositionSelfKnowledgeTriggers = AdmittedPropositionTriggers
