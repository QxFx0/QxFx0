{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionLocationFormationAdmission
  ( PropositionLocationFormationAdmissionInput(..)
  , PropositionLocationFormationAdmissionDecision(..)
  , RawPropositionLocationFormationTrigger(..)
  , AdmittedPropositionLocationFormationTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionLocationFormationAdmissionInput = PropositionLocationFormationAdmissionInput
  { plfaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionLocationFormationAdmissionDecision
  = PlfdAdmitRaw
  | PlfdPreserveAmbiguous
  | PlfdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionLocationFormationTrigger = RawPropositionLocationFormationTrigger
  { rplfLabel :: !Text
  , rplfMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionLocationFormationTriggers = AdmittedPropositionLocationFormationTriggers
  { aplfRawTriggers :: ![RawPropositionLocationFormationTrigger]
  , aplfTriggers :: ![RawPropositionLocationFormationTrigger]
  , aplfDecision :: !PropositionLocationFormationAdmissionDecision
  } deriving stock (Eq, Show)
