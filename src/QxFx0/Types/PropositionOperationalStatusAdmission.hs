{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionOperationalStatusAdmission
  ( PropositionOperationalStatusAdmissionInput(..)
  , PropositionOperationalStatusAdmissionDecision(..)
  , RawPropositionOperationalStatusTrigger(..)
  , AdmittedPropositionOperationalStatusTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionOperationalStatusAdmissionInput = PropositionOperationalStatusAdmissionInput
  { posaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionOperationalStatusAdmissionDecision
  = PosdAdmitRaw
  | PosdPreserveAmbiguous
  | PosdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionOperationalStatusTrigger = RawPropositionOperationalStatusTrigger
  { rpostLabel :: !Text
  , rpostMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionOperationalStatusTriggers = AdmittedPropositionOperationalStatusTriggers
  { apostRawTriggers :: ![RawPropositionOperationalStatusTrigger]
  , apostTriggers :: ![RawPropositionOperationalStatusTrigger]
  , apostDecision :: !PropositionOperationalStatusAdmissionDecision
  } deriving stock (Eq, Show)
