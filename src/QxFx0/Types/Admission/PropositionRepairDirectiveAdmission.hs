{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionRepairDirectiveAdmission
  ( admitPropositionRepairDirectiveTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionAdmissionTypes

-- | Admit proposition RepairDirective triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionRepairDirectiveTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionRepairDirectiveTriggers =
  admitPropositionTriggers repairDirectiveAdmissionConfig

repairDirectiveAdmissionConfig :: PropositionAdmissionConfig
  PropositionAdmissionInput
  RawPropositionTrigger
  AdmittedPropositionTriggers
  PropositionAdmissionDecision
repairDirectiveAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = paiTruthContractStatus
  , pacTriggerLabel = rptLabel
  , pacTriggerMatched = rptMatched
  , pacSetTriggerMatched = \b t -> t { rptMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionTriggers
  , pacDecisionAdmitRaw = PadAdmitRaw
  , pacDecisionPreserveAmbiguous = PadPreserveAmbiguous
  , pacDecisionSuppressStrong = PadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "unclear_token_bag"
  , "template_complaint_plain"
  , "template_complaint_stressed"
  , "confused_en"
  , "not_making_sense_en"
  ]
