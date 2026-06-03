{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionConfrontAdmission
  ( PropositionConfrontAdmissionInput(..)
  , PropositionConfrontAdmissionDecision(..)
  , RawPropositionConfrontTrigger(..)
  , AdmittedPropositionConfrontTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionConfrontAdmissionInput = PropositionConfrontAdmissionInput
  { pcoaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionConfrontAdmissionDecision
  = PcondAdmitRaw
  | PcondPreserveAmbiguous
  | PcondSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionConfrontTrigger = RawPropositionConfrontTrigger
  { rpconfLabel :: !Text
  , rpconfMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionConfrontTriggers = AdmittedPropositionConfrontTriggers
  { apconfRawTriggers :: ![RawPropositionConfrontTrigger]
  , apconfTriggers :: ![RawPropositionConfrontTrigger]
  , apconfDecision :: !PropositionConfrontAdmissionDecision
  } deriving stock (Eq, Show)
