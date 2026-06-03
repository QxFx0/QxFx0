{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionGenerativePromptAdmission
  ( PropositionGenerativePromptAdmissionInput(..)
  , PropositionGenerativePromptAdmissionDecision(..)
  , RawPropositionGenerativePromptTrigger(..)
  , AdmittedPropositionGenerativePromptTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionGenerativePromptAdmissionInput = PropositionGenerativePromptAdmissionInput
  { pgpaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionGenerativePromptAdmissionDecision
  = PpgpdAdmitRaw
  | PpgpdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionGenerativePromptTrigger = RawPropositionGenerativePromptTrigger
  { rpgpLabel :: !Text
  , rpgpMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionGenerativePromptTriggers = AdmittedPropositionGenerativePromptTriggers
  { apgpRawTriggers :: ![RawPropositionGenerativePromptTrigger]
  , apgpTriggers :: ![RawPropositionGenerativePromptTrigger]
  , apgpDecision :: !PropositionGenerativePromptAdmissionDecision
  } deriving stock (Eq, Show)
