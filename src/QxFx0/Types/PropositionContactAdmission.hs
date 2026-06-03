{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionContactAdmission
  ( PropositionContactAdmissionInput(..)
  , PropositionContactAdmissionDecision(..)
  , RawPropositionContactTrigger(..)
  , AdmittedPropositionContactTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionContactAdmissionInput = PropositionContactAdmissionInput
  { pcaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionContactAdmissionDecision
  = PcadAdmitRaw
  | PcadPreserveAmbiguous
  | PcadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionContactTrigger = RawPropositionContactTrigger
  { rpctLabel :: !Text
  , rpctMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionContactTriggers = AdmittedPropositionContactTriggers
  { apctRawTriggers :: ![RawPropositionContactTrigger]
  , apctTriggers :: ![RawPropositionContactTrigger]
  , apctDecision :: !PropositionContactAdmissionDecision
  } deriving stock (Eq, Show)
