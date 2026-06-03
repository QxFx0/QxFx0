{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionNextStepAdmission
  ( PropositionNextStepAdmissionInput(..)
  , PropositionNextStepAdmissionDecision(..)
  , RawPropositionNextStepTrigger(..)
  , AdmittedPropositionNextStepTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionNextStepAdmissionInput = PropositionNextStepAdmissionInput
  { pnsaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionNextStepAdmissionDecision
  = PnsdAdmitRaw
  | PnsdPreserveAmbiguous
  | PnsdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionNextStepTrigger = RawPropositionNextStepTrigger
  { rpnstLabel :: !Text
  , rpnstMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionNextStepTriggers = AdmittedPropositionNextStepTriggers
  { apnstRawTriggers :: ![RawPropositionNextStepTrigger]
  , apnstTriggers :: ![RawPropositionNextStepTrigger]
  , apnstDecision :: !PropositionNextStepAdmissionDecision
  } deriving stock (Eq, Show)
