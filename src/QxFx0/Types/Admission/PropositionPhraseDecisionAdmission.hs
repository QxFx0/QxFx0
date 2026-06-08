{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionPhraseDecisionAdmission
  ( PropositionPhraseDecisionAdmissionInput(..)
  , PropositionPhraseDecisionAdmissionDecision(..)
  , RawPropositionPhraseDecision(..)
  , AdmittedPropositionPhraseDecisions(..)
  , admitPropositionPhraseDecisions
  ) where

import Data.Text (Text, pack)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types
import QxFx0.Types.PropositionFallbackAdmission
  ( PropositionPhraseDecisionAdmissionInput(..)
  , PropositionPhraseDecisionAdmissionDecision(..)
  , PropositionFallbackType(..)
  , RawPropositionPhraseDecision(..)
  , AdmittedPropositionPhraseDecisions(..)
  )

admitPropositionPhraseDecisions
  :: PropositionPhraseDecisionAdmissionInput
  -> [RawPropositionPhraseDecision]
  -> AdmittedPropositionPhraseDecisions
admitPropositionPhraseDecisions =
  admitPropositionTriggers phraseDecisionAdmissionConfig

phraseDecisionAdmissionConfig :: PropositionAdmissionConfig
  PropositionPhraseDecisionAdmissionInput
  RawPropositionPhraseDecision
  AdmittedPropositionPhraseDecisions
  PropositionPhraseDecisionAdmissionDecision
phraseDecisionAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = ppdaiTruthContractStatus
  , pacTriggerLabel = \(RawPropositionPhraseDecision pt _ _) -> pack (show pt)
  , pacTriggerMatched = rppdMatched
  , pacSetTriggerMatched = \b t -> t { rppdMatched = b }
  , pacSafeLabels = safeFallbackTypes
  , pacAdmittedCtor = AdmittedPropositionPhraseDecisions
  , pacDecisionAdmitRaw = PpddAdmitRaw
  , pacDecisionPreserveAmbiguous = PpddPreserveAmbiguous
  , pacDecisionSuppressStrong = PpddSuppressStrongDecisions
  }

safeFallbackTypes :: [Text]
safeFallbackTypes =
  [ pack "PfContactSignal"
  , pack "PfAnchorSignal"
  , pack "PfClarifyQ"
  , pack "PfDeepenQ"
  ]
