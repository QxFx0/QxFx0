{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionAffectiveSupportPhraseAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionAffectiveSupportPhraseAdmission
  ( PropositionAffectiveSupportPhraseAdmissionInput, PropositionAffectiveSupportPhraseAdmissionDecision, RawPropositionAffectiveSupportPhraseTrigger, AdmittedPropositionAffectiveSupportPhraseTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionAffectiveSupportPhraseAdmissionInput = PropositionAdmissionInput
type PropositionAffectiveSupportPhraseAdmissionDecision = PropositionAdmissionDecision
type RawPropositionAffectiveSupportPhraseTrigger = RawPropositionTrigger
type AdmittedPropositionAffectiveSupportPhraseTriggers = AdmittedPropositionTriggers
