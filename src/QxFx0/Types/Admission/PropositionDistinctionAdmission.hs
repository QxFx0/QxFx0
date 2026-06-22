{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionDistinctionAdmission
  ( admitPropositionDistinctionTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionAdmissionTypes

-- | Admit proposition Distinction triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionDistinctionTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionDistinctionTriggers =
  admitPropositionTriggers distinctionAdmissionConfig

distinctionAdmissionConfig :: PropositionAdmissionConfig
  PropositionAdmissionInput
  RawPropositionTrigger
  AdmittedPropositionTriggers
  PropositionAdmissionDecision
distinctionAdmissionConfig = PropositionAdmissionConfig
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
  [ "complex_relationship_between_how_differ"
  , "complex_distinguish_then_ground"
  , "complex_how_differ_practical_reasoning"
  , "complex_why_differ"
  , "complex_for_what_purpose_distinguish"
  , "complex_why_distinguish"
  , "from_token_present"
  ]
