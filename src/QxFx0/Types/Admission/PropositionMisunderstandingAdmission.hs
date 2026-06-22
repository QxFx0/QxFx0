{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionMisunderstandingAdmission
  ( admitPropositionMisunderstandingTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionAdmissionTypes

-- | Admit proposition Misunderstanding triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionMisunderstandingTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionMisunderstandingTriggers =
  admitPropositionTriggers misunderstandingAdmissionConfig

misunderstandingAdmissionConfig :: PropositionAdmissionConfig
  PropositionAdmissionInput
  RawPropositionTrigger
  AdmittedPropositionTriggers
  PropositionAdmissionDecision
misunderstandingAdmissionConfig = PropositionAdmissionConfig
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
  [ "contact_lost_ru"
  , "contact_lost_en"
  , "apology_tokens"
  , "apology_phrase"
  ]
