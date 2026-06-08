{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionDistinctionAdmission
  ( admitPropositionDistinctionTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionDistinctionAdmission

-- | Admit proposition Distinction triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionDistinctionTriggers
  :: PropositionDistinctionAdmissionInput
  -> [RawPropositionDistinctionTrigger]
  -> AdmittedPropositionDistinctionTriggers
admitPropositionDistinctionTriggers =
  admitPropositionTriggers distinctionAdmissionConfig

distinctionAdmissionConfig :: PropositionAdmissionConfig
  PropositionDistinctionAdmissionInput
  RawPropositionDistinctionTrigger
  AdmittedPropositionDistinctionTriggers
  PropositionDistinctionAdmissionDecision
distinctionAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pdaiTruthContractStatus
  , pacTriggerLabel = rpdtLabel
  , pacTriggerMatched = rpdtMatched
  , pacSetTriggerMatched = \b t -> t { rpdtMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionDistinctionTriggers
  , pacDecisionAdmitRaw = PdadAdmitRaw
  , pacDecisionPreserveAmbiguous = PdadPreserveAmbiguous
  , pacDecisionSuppressStrong = PdadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "complex_relationship_between_how_differ"
  , "complex_distinguish_then_ground"
  , "complex_how_differ_practical_reasoning"
  , "complex_why_differ"
  , "complex_for_what_purpose_distinguish"
  , "complex_why_distinguish"
  , "from_token_present"
  ]
