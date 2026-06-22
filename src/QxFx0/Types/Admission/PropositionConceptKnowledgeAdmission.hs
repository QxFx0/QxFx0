{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionConceptKnowledgeAdmission
  ( admitPropositionConceptKnowledgeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionAdmissionTypes

-- | Admit proposition ConceptKnowledge triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionConceptKnowledgeTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionConceptKnowledgeTriggers =
  admitPropositionTriggers conceptKnowledgeAdmissionConfig

conceptKnowledgeAdmissionConfig :: PropositionAdmissionConfig
  PropositionAdmissionInput
  RawPropositionTrigger
  AdmittedPropositionTriggers
  PropositionAdmissionDecision
conceptKnowledgeAdmissionConfig = PropositionAdmissionConfig
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
  [ "concept_like_noun_guard"
  , "question_suffix_guard"
  ]
