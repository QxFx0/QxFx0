{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionDialogueInvitationAdmission
Description : Re-export of canonical proposition admission types (C4.3 consolidation)

This module now re-exports types from PropositionAdmissionTypes.hs.
All field accessors use canonical names (rptLabel, rptMatched, etc.).
-}
module QxFx0.Types.PropositionDialogueInvitationAdmission
  ( PropositionDialogueInvitationAdmissionInput, PropositionDialogueInvitationAdmissionDecision, RawPropositionDialogueInvitationTrigger, AdmittedPropositionDialogueInvitationTriggers
  ) where

import QxFx0.Types.PropositionAdmissionTypes

type PropositionDialogueInvitationAdmissionInput = PropositionAdmissionInput
type PropositionDialogueInvitationAdmissionDecision = PropositionAdmissionDecision
type RawPropositionDialogueInvitationTrigger = RawPropositionTrigger
type AdmittedPropositionDialogueInvitationTriggers = AdmittedPropositionTriggers
