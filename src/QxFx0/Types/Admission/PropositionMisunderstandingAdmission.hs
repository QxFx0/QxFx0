{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionMisunderstandingAdmission
  ( admitPropositionMisunderstandingTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionMisunderstandingAdmission

-- | Admit proposition Misunderstanding triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionMisunderstandingTriggers
  :: PropositionMisunderstandingAdmissionInput
  -> [RawPropositionMisunderstandingTrigger]
  -> AdmittedPropositionMisunderstandingTriggers
admitPropositionMisunderstandingTriggers =
  admitPropositionTriggers misunderstandingAdmissionConfig

misunderstandingAdmissionConfig :: PropositionAdmissionConfig
  PropositionMisunderstandingAdmissionInput
  RawPropositionMisunderstandingTrigger
  AdmittedPropositionMisunderstandingTriggers
  PropositionMisunderstandingAdmissionDecision
misunderstandingAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pmiaiTruthContractStatus
  , pacTriggerLabel = rpmtLabel
  , pacTriggerMatched = rpmtMatched
  , pacSetTriggerMatched = \b t -> t { rpmtMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionMisunderstandingTriggers
  , pacDecisionAdmitRaw = PmAdmitRaw
  , pacDecisionPreserveAmbiguous = PmPreserveAmbiguous
  , pacDecisionSuppressStrong = PmSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "contact_lost_ru"
  , "contact_lost_en"
  , "apology_tokens"
  , "apology_phrase"
  ]
