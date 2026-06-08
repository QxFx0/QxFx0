{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionContemplativeTopicAdmission
  ( admitPropositionContemplativeTopicTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionContemplativeTopicAdmission

-- | Admit proposition ContemplativeTopic triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionContemplativeTopicTriggers
  :: PropositionContemplativeTopicAdmissionInput
  -> [RawPropositionContemplativeTopicTrigger]
  -> AdmittedPropositionContemplativeTopicTriggers
admitPropositionContemplativeTopicTriggers =
  admitPropositionTriggers contemplativeTopicAdmissionConfig

contemplativeTopicAdmissionConfig :: PropositionAdmissionConfig
  PropositionContemplativeTopicAdmissionInput
  RawPropositionContemplativeTopicTrigger
  AdmittedPropositionContemplativeTopicTriggers
  PropositionContemplativeTopicAdmissionDecision
contemplativeTopicAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pctaiTruthContractStatus
  , pacTriggerLabel = rpctLabel
  , pacTriggerMatched = rpctMatched
  , pacSetTriggerMatched = \b t -> t { rpctMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionContemplativeTopicTriggers
  , pacDecisionAdmitRaw = PpctdAdmitRaw
  , pacDecisionPreserveAmbiguous = PpctdPreserveAmbiguous
  , pacDecisionSuppressStrong = PpctdSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "bare_self_pronoun"
  ]
