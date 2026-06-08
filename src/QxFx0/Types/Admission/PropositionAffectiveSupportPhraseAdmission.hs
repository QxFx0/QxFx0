{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionAffectiveSupportPhraseAdmission
  ( admitPropositionAffectiveSupportPhraseTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionAffectiveSupportPhraseAdmission

-- | Admit proposition AffectiveSupportPhrase triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionAffectiveSupportPhraseTriggers
  :: PropositionAffectiveSupportPhraseAdmissionInput
  -> [RawPropositionAffectiveSupportPhraseTrigger]
  -> AdmittedPropositionAffectiveSupportPhraseTriggers
admitPropositionAffectiveSupportPhraseTriggers =
  admitPropositionTriggers affectiveSupportPhraseAdmissionConfig

affectiveSupportPhraseAdmissionConfig :: PropositionAdmissionConfig
  PropositionAffectiveSupportPhraseAdmissionInput
  RawPropositionAffectiveSupportPhraseTrigger
  AdmittedPropositionAffectiveSupportPhraseTriggers
  PropositionAffectiveSupportPhraseAdmissionDecision
affectiveSupportPhraseAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = paspaiTruthContractStatus
  , pacTriggerLabel = rpaspLabel
  , pacTriggerMatched = rpaspMatched
  , pacSetTriggerMatched = \b t -> t { rpaspMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionAffectiveSupportPhraseTriggers
  , pacDecisionAdmitRaw = PaspadAdmitRaw
  , pacDecisionPreserveAmbiguous = PaspadPreserveAmbiguous
  , pacDecisionSuppressStrong = PaspadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "no_strength"
  , "no_energy"
  , "nothing_pleases"
  , "nothing_wanted"
  , "cant_pull_together"
  ]
