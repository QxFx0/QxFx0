{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionComparisonPlausibilityAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionComparisonPlausibilityAdmission
  ( PropositionComparisonPlausibilityAdmissionInput, PropositionComparisonPlausibilityAdmissionDecision, RawPropositionComparisonPlausibilityTrigger, AdmittedPropositionComparisonPlausibilityTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionComparisonPlausibilityAdmissionInput = PropositionAdmissionInput
type PropositionComparisonPlausibilityAdmissionDecision = PropositionAdmissionDecision
type RawPropositionComparisonPlausibilityTrigger = RawPropositionTrigger
type AdmittedPropositionComparisonPlausibilityTriggers = AdmittedPropositionTriggers
