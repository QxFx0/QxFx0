{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionOperationalStatusAdmission
  ( admitPropositionOperationalStatusTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionOperationalStatusAdmission

-- | Admit proposition OperationalStatus triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionOperationalStatusTriggers
  :: PropositionOperationalStatusAdmissionInput
  -> [RawPropositionOperationalStatusTrigger]
  -> AdmittedPropositionOperationalStatusTriggers
admitPropositionOperationalStatusTriggers =
  admitPropositionTriggers operationalStatusAdmissionConfig

operationalStatusAdmissionConfig :: PropositionAdmissionConfig
  PropositionOperationalStatusAdmissionInput
  RawPropositionOperationalStatusTrigger
  AdmittedPropositionOperationalStatusTriggers
  PropositionOperationalStatusAdmissionDecision
operationalStatusAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = posaiTruthContractStatus
  , pacTriggerLabel = rpostLabel
  , pacTriggerMatched = rpostMatched
  , pacSetTriggerMatched = \b t -> t { rpostMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionOperationalStatusTriggers
  , pacDecisionAdmitRaw = PosdAdmitRaw
  , pacDecisionPreserveAmbiguous = PosdPreserveAmbiguous
  , pacDecisionSuppressStrong = PosdSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "subject_present"
  ]
