{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionAffectiveSupportPhraseAdmission
  ( PropositionAffectiveSupportPhraseAdmissionInput(..)
  , PropositionAffectiveSupportPhraseAdmissionDecision(..)
  , RawPropositionAffectiveSupportPhraseTrigger(..)
  , AdmittedPropositionAffectiveSupportPhraseTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionAffectiveSupportPhraseAdmissionInput = PropositionAffectiveSupportPhraseAdmissionInput
  { paspaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionAffectiveSupportPhraseAdmissionDecision
  = PaspadAdmitRaw
  | PaspadPreserveAmbiguous
  | PaspadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionAffectiveSupportPhraseTrigger = RawPropositionAffectiveSupportPhraseTrigger
  { rpaspLabel :: !Text
  , rpaspMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionAffectiveSupportPhraseTriggers = AdmittedPropositionAffectiveSupportPhraseTriggers
  { apaspRawTriggers :: ![RawPropositionAffectiveSupportPhraseTrigger]
  , apaspTriggers :: ![RawPropositionAffectiveSupportPhraseTrigger]
  , apaspDecision :: !PropositionAffectiveSupportPhraseAdmissionDecision
  } deriving stock (Eq, Show)
