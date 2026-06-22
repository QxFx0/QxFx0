{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionContemplativeTopicAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionContemplativeTopicAdmission
  ( PropositionContemplativeTopicAdmissionInput, PropositionContemplativeTopicAdmissionDecision, RawPropositionContemplativeTopicTrigger, AdmittedPropositionContemplativeTopicTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionContemplativeTopicAdmissionInput = PropositionAdmissionInput
type PropositionContemplativeTopicAdmissionDecision = PropositionAdmissionDecision
type RawPropositionContemplativeTopicTrigger = RawPropositionTrigger
type AdmittedPropositionContemplativeTopicTriggers = AdmittedPropositionTriggers
