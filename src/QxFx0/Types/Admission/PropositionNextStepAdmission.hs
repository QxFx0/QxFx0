{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionNextStepAdmission
  ( admitPropositionNextStepTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionNextStepAdmission

-- | Admit proposition NextStep triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionNextStepTriggers
  :: PropositionNextStepAdmissionInput
  -> [RawPropositionNextStepTrigger]
  -> AdmittedPropositionNextStepTriggers
admitPropositionNextStepTriggers =
  admitPropositionTriggers nextStepAdmissionConfig

nextStepAdmissionConfig :: PropositionAdmissionConfig
  PropositionNextStepAdmissionInput
  RawPropositionNextStepTrigger
  AdmittedPropositionNextStepTriggers
  PropositionNextStepAdmissionDecision
nextStepAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pnsaiTruthContractStatus
  , pacTriggerLabel = rpnstLabel
  , pacTriggerMatched = rpnstMatched
  , pacSetTriggerMatched = \b t -> t { rpnstMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionNextStepTriggers
  , pacDecisionAdmitRaw = PnsdAdmitRaw
  , pacDecisionPreserveAmbiguous = PnsdPreserveAmbiguous
  , pacDecisionSuppressStrong = PnsdSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "direct_text_short"
  ]
