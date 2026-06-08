{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionConceptKnowledgeAdmission
  ( admitPropositionConceptKnowledgeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionConceptKnowledgeAdmission

-- | Admit proposition ConceptKnowledge triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionConceptKnowledgeTriggers
  :: PropositionConceptKnowledgeAdmissionInput
  -> [RawPropositionConceptKnowledgeTrigger]
  -> AdmittedPropositionConceptKnowledgeTriggers
admitPropositionConceptKnowledgeTriggers =
  admitPropositionTriggers conceptKnowledgeAdmissionConfig

conceptKnowledgeAdmissionConfig :: PropositionAdmissionConfig
  PropositionConceptKnowledgeAdmissionInput
  RawPropositionConceptKnowledgeTrigger
  AdmittedPropositionConceptKnowledgeTriggers
  PropositionConceptKnowledgeAdmissionDecision
conceptKnowledgeAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pckaiTruthContractStatus
  , pacTriggerLabel = rpckLabel
  , pacTriggerMatched = rpckMatched
  , pacSetTriggerMatched = \b t -> t { rpckMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionConceptKnowledgeTriggers
  , pacDecisionAdmitRaw = PckdAdmitRaw
  , pacDecisionPreserveAmbiguous = PckdPreserveAmbiguous
  , pacDecisionSuppressStrong = PckdSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "concept_like_noun_guard"
  , "question_suffix_guard"
  ]
