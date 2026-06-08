{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionRepairDirectiveAdmission
  ( admitPropositionRepairDirectiveTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionRepairDirectiveAdmission

-- | Admit proposition RepairDirective triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionRepairDirectiveTriggers
  :: PropositionRepairDirectiveAdmissionInput
  -> [RawPropositionRepairDirectiveTrigger]
  -> AdmittedPropositionRepairDirectiveTriggers
admitPropositionRepairDirectiveTriggers =
  admitPropositionTriggers repairDirectiveAdmissionConfig

repairDirectiveAdmissionConfig :: PropositionAdmissionConfig
  PropositionRepairDirectiveAdmissionInput
  RawPropositionRepairDirectiveTrigger
  AdmittedPropositionRepairDirectiveTriggers
  PropositionRepairDirectiveAdmissionDecision
repairDirectiveAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = prdaiTruthContractStatus
  , pacTriggerLabel = rprdLabel
  , pacTriggerMatched = rprdMatched
  , pacSetTriggerMatched = \b t -> t { rprdMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionRepairDirectiveTriggers
  , pacDecisionAdmitRaw = PrdadAdmitRaw
  , pacDecisionPreserveAmbiguous = PrdadPreserveAmbiguous
  , pacDecisionSuppressStrong = PrdadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "unclear_token_bag"
  , "template_complaint_plain"
  , "template_complaint_stressed"
  , "confused_en"
  , "not_making_sense_en"
  ]
