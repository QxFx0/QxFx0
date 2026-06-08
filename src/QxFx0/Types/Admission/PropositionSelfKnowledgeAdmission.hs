{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionSelfKnowledgeAdmission
  ( admitPropositionSelfKnowledgeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionSelfKnowledgeAdmission

-- | Admit proposition SelfKnowledge triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionSelfKnowledgeTriggers
  :: PropositionSelfKnowledgeAdmissionInput
  -> [RawPropositionSelfKnowledgeTrigger]
  -> AdmittedPropositionSelfKnowledgeTriggers
admitPropositionSelfKnowledgeTriggers =
  admitPropositionTriggers selfKnowledgeAdmissionConfig

selfKnowledgeAdmissionConfig :: PropositionAdmissionConfig
  PropositionSelfKnowledgeAdmissionInput
  RawPropositionSelfKnowledgeTrigger
  AdmittedPropositionSelfKnowledgeTriggers
  PropositionSelfKnowledgeAdmissionDecision
selfKnowledgeAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pskaiTruthContractStatus
  , pacTriggerLabel = rpskLabel
  , pacTriggerMatched = rpskMatched
  , pacSetTriggerMatched = \b t -> t { rpskMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionSelfKnowledgeTriggers
  , pacDecisionAdmitRaw = PskdAdmitRaw
  , pacDecisionPreserveAmbiguous = PskdPreserveAmbiguous
  , pacDecisionSuppressStrong = PskdSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "single_thought_subject_guard"
  ]
