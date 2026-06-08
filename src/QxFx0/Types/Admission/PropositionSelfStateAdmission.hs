{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionSelfStateAdmission
  ( admitPropositionSelfStateTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionSelfStateAdmission

-- | Admit proposition SelfState triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionSelfStateTriggers
  :: PropositionSelfStateAdmissionInput
  -> [RawPropositionSelfStateTrigger]
  -> AdmittedPropositionSelfStateTriggers
admitPropositionSelfStateTriggers =
  admitPropositionTriggers selfStateAdmissionConfig

selfStateAdmissionConfig :: PropositionAdmissionConfig
  PropositionSelfStateAdmissionInput
  RawPropositionSelfStateTrigger
  AdmittedPropositionSelfStateTriggers
  PropositionSelfStateAdmissionDecision
selfStateAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pssaiTruthContractStatus
  , pacTriggerLabel = rpssLabel
  , pacTriggerMatched = rpssMatched
  , pacSetTriggerMatched = \b t -> t { rpssMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionSelfStateTriggers
  , pacDecisionAdmitRaw = PssadAdmitRaw
  , pacDecisionPreserveAmbiguous = PssadPreserveAmbiguous
  , pacDecisionSuppressStrong = PssadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "generic_what_you_prefix"
  , "generic_self_state_verb"
  , "guard_about_what_plain"
  , "guard_about_what_stressed"
  , "guard_capability_knowhow"
  , "guard_capability_can"
  , "guard_self_knowledge"
  , "guard_identity"
  ]
