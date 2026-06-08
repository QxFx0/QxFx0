{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionOperationalCauseAdmission
  ( admitPropositionOperationalCauseTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionOperationalCauseAdmission

-- | Admit proposition OperationalCause triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionOperationalCauseTriggers
  :: PropositionOperationalCauseAdmissionInput
  -> [RawPropositionOperationalCauseTrigger]
  -> AdmittedPropositionOperationalCauseTriggers
admitPropositionOperationalCauseTriggers =
  admitPropositionTriggers operationalCauseAdmissionConfig

operationalCauseAdmissionConfig :: PropositionAdmissionConfig
  PropositionOperationalCauseAdmissionInput
  RawPropositionOperationalCauseTrigger
  AdmittedPropositionOperationalCauseTriggers
  PropositionOperationalCauseAdmissionDecision
operationalCauseAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pocaiTruthContractStatus
  , pacTriggerLabel = rpocLabel
  , pacTriggerMatched = rpocMatched
  , pacSetTriggerMatched = \b t -> t { rpocMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionOperationalCauseTriggers
  , pacDecisionAdmitRaw = PocdAdmitRaw
  , pacDecisionPreserveAmbiguous = PocdPreserveAmbiguous
  , pacDecisionSuppressStrong = PocdSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "subject_present"
  ]
