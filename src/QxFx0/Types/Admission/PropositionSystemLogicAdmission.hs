{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionSystemLogicAdmission
  ( admitPropositionSystemLogicTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionSystemLogicAdmission

-- | Admit proposition SystemLogic triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionSystemLogicTriggers
  :: PropositionSystemLogicAdmissionInput
  -> [RawPropositionSystemLogicTrigger]
  -> AdmittedPropositionSystemLogicTriggers
admitPropositionSystemLogicTriggers =
  admitPropositionTriggers systemLogicAdmissionConfig

systemLogicAdmissionConfig :: PropositionAdmissionConfig
  PropositionSystemLogicAdmissionInput
  RawPropositionSystemLogicTrigger
  AdmittedPropositionSystemLogicTriggers
  PropositionSystemLogicAdmissionDecision
systemLogicAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pslaiTruthContractStatus
  , pacTriggerLabel = rpslLabel
  , pacTriggerMatched = rpslMatched
  , pacSetTriggerMatched = \b t -> t { rpslMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionSystemLogicTriggers
  , pacDecisionAdmitRaw = PsldAdmitRaw
  , pacDecisionPreserveAmbiguous = PsldPreserveAmbiguous
  , pacDecisionSuppressStrong = PsldSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "subject_present"
  ]
