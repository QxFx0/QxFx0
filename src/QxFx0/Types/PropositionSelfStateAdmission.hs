{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionSelfStateAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionSelfStateAdmission
  ( PropositionSelfStateAdmissionInput, PropositionSelfStateAdmissionDecision, RawPropositionSelfStateTrigger, AdmittedPropositionSelfStateTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionSelfStateAdmissionInput = PropositionAdmissionInput
type PropositionSelfStateAdmissionDecision = PropositionAdmissionDecision
type RawPropositionSelfStateTrigger = RawPropositionTrigger
type AdmittedPropositionSelfStateTriggers = AdmittedPropositionTriggers
