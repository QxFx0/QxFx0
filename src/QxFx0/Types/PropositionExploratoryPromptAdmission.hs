{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionExploratoryPromptAdmission
  ( PropositionExploratoryPromptAdmissionInput(..)
  , PropositionExploratoryPromptAdmissionDecision(..)
  , RawPropositionExploratoryPromptTrigger(..)
  , AdmittedPropositionExploratoryPromptTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionExploratoryPromptAdmissionInput = PropositionExploratoryPromptAdmissionInput
  { peptaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionExploratoryPromptAdmissionDecision
  = PpeptdAdmitRaw
  | PpeptdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionExploratoryPromptTrigger = RawPropositionExploratoryPromptTrigger
  { rpeptLabel :: !Text
  , rpeptMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionExploratoryPromptTriggers = AdmittedPropositionExploratoryPromptTriggers
  { apeptRawTriggers :: ![RawPropositionExploratoryPromptTrigger]
  , apeptTriggers :: ![RawPropositionExploratoryPromptTrigger]
  , apeptDecision :: !PropositionExploratoryPromptAdmissionDecision
  } deriving stock (Eq, Show)
