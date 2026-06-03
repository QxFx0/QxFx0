{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionSystemLogicAdmission
  ( PropositionSystemLogicAdmissionInput(..)
  , PropositionSystemLogicAdmissionDecision(..)
  , RawPropositionSystemLogicTrigger(..)
  , AdmittedPropositionSystemLogicTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionSystemLogicAdmissionInput = PropositionSystemLogicAdmissionInput
  { pslaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionSystemLogicAdmissionDecision
  = PsldAdmitRaw
  | PsldPreserveAmbiguous
  | PsldSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionSystemLogicTrigger = RawPropositionSystemLogicTrigger
  { rpslLabel :: !Text
  , rpslMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionSystemLogicTriggers = AdmittedPropositionSystemLogicTriggers
  { apslRawTriggers :: ![RawPropositionSystemLogicTrigger]
  , apslTriggers :: ![RawPropositionSystemLogicTrigger]
  , apslDecision :: !PropositionSystemLogicAdmissionDecision
  } deriving stock (Eq, Show)
