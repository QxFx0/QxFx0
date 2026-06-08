{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionPurposeAdmission
  ( admitPropositionPurposeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionPurposeAdmission

-- | Admit proposition Purpose triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionPurposeTriggers
  :: PropositionPurposeAdmissionInput
  -> [RawPropositionPurposeTrigger]
  -> AdmittedPropositionPurposeTriggers
admitPropositionPurposeTriggers =
  admitPropositionTriggers purposeAdmissionConfig

purposeAdmissionConfig :: PropositionAdmissionConfig
  PropositionPurposeAdmissionInput
  RawPropositionPurposeTrigger
  AdmittedPropositionPurposeTriggers
  PropositionPurposeAdmissionDecision
purposeAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = ppaiTruthContractStatus
  , pacTriggerLabel = rpptLabel
  , pacTriggerMatched = rpptMatched
  , pacSetTriggerMatched = \b t -> t { rpptMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionPurposeTriggers
  , pacDecisionAdmitRaw = PpadAdmitRaw
  , pacDecisionPreserveAmbiguous = PpadPreserveAmbiguous
  , pacDecisionSuppressStrong = PpadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "purpose_subject_guard"
  ]
