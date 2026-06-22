{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionAffectiveSupportPhraseAdmission
  ( admitPropositionAffectiveSupportPhraseTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionAdmissionTypes

-- | Admit proposition AffectiveSupportPhrase triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionAffectiveSupportPhraseTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionAffectiveSupportPhraseTriggers =
  admitPropositionTriggers affectiveSupportPhraseAdmissionConfig

affectiveSupportPhraseAdmissionConfig :: PropositionAdmissionConfig
  PropositionAdmissionInput
  RawPropositionTrigger
  AdmittedPropositionTriggers
  PropositionAdmissionDecision
affectiveSupportPhraseAdmissionConfig = PropositionAdmissionConfig
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
  [ "no_strength"
  , "no_energy"
  , "nothing_pleases"
  , "nothing_wanted"
  , "cant_pull_together"
  ]
