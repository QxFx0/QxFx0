{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionLocationFormationAdmission
  ( admitPropositionLocationFormationTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionLocationFormationAdmission

-- | Admit proposition LocationFormation triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionLocationFormationTriggers
  :: PropositionLocationFormationAdmissionInput
  -> [RawPropositionLocationFormationTrigger]
  -> AdmittedPropositionLocationFormationTriggers
admitPropositionLocationFormationTriggers =
  admitPropositionTriggers locationFormationAdmissionConfig

locationFormationAdmissionConfig :: PropositionAdmissionConfig
  PropositionLocationFormationAdmissionInput
  RawPropositionLocationFormationTrigger
  AdmittedPropositionLocationFormationTriggers
  PropositionLocationFormationAdmissionDecision
locationFormationAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = plfaiTruthContractStatus
  , pacTriggerLabel = rplfLabel
  , pacTriggerMatched = rplfMatched
  , pacSetTriggerMatched = \b t -> t { rplfMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionLocationFormationTriggers
  , pacDecisionAdmitRaw = PlfdAdmitRaw
  , pacDecisionPreserveAmbiguous = PlfdPreserveAmbiguous
  , pacDecisionSuppressStrong = PlfdSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "mental_noun_guard"
  ]
