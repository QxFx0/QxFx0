{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionMisunderstandingAdmission
  ( PropositionMisunderstandingAdmissionInput(..)
  , PropositionMisunderstandingAdmissionDecision(..)
  , RawPropositionMisunderstandingTrigger(..)
  , AdmittedPropositionMisunderstandingTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionMisunderstandingAdmissionInput = PropositionMisunderstandingAdmissionInput
  { pmiaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionMisunderstandingAdmissionDecision
  = PmAdmitRaw
  | PmPreserveAmbiguous
  | PmSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionMisunderstandingTrigger = RawPropositionMisunderstandingTrigger
  { rpmtLabel :: !Text
  , rpmtMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionMisunderstandingTriggers = AdmittedPropositionMisunderstandingTriggers
  { apmtRawTriggers :: ![RawPropositionMisunderstandingTrigger]
  , apmtTriggers :: ![RawPropositionMisunderstandingTrigger]
  , apmtDecision :: !PropositionMisunderstandingAdmissionDecision
  } deriving stock (Eq, Show)
