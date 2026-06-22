{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionAffectiveSupportProbeAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionAffectiveSupportProbeAdmission
  ( PropositionAffectiveSupportProbeAdmissionInput, PropositionAffectiveSupportProbeAdmissionDecision, RawPropositionAffectiveSupportProbeTrigger, AdmittedPropositionAffectiveSupportProbeTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionAffectiveSupportProbeAdmissionInput = PropositionAdmissionInput
type PropositionAffectiveSupportProbeAdmissionDecision = PropositionAdmissionDecision
type RawPropositionAffectiveSupportProbeTrigger = RawPropositionTrigger
type AdmittedPropositionAffectiveSupportProbeTriggers = AdmittedPropositionTriggers
