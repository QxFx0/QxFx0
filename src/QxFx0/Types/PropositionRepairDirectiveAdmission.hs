{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionRepairDirectiveAdmission
  ( PropositionRepairDirectiveAdmissionInput(..)
  , PropositionRepairDirectiveAdmissionDecision(..)
  , RawPropositionRepairDirectiveTrigger(..)
  , AdmittedPropositionRepairDirectiveTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionRepairDirectiveAdmissionInput = PropositionRepairDirectiveAdmissionInput
  { prdaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionRepairDirectiveAdmissionDecision
  = PrdadAdmitRaw
  | PrdadPreserveAmbiguous
  | PrdadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionRepairDirectiveTrigger = RawPropositionRepairDirectiveTrigger
  { rprdLabel :: !Text
  , rprdMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionRepairDirectiveTriggers = AdmittedPropositionRepairDirectiveTriggers
  { aprdRawTriggers :: ![RawPropositionRepairDirectiveTrigger]
  , aprdTriggers :: ![RawPropositionRepairDirectiveTrigger]
  , aprdDecision :: !PropositionRepairDirectiveAdmissionDecision
  } deriving stock (Eq, Show)
