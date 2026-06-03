{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionDistinctionAdmission
  ( PropositionDistinctionAdmissionInput(..)
  , PropositionDistinctionAdmissionDecision(..)
  , RawPropositionDistinctionTrigger(..)
  , AdmittedPropositionDistinctionTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionDistinctionAdmissionInput = PropositionDistinctionAdmissionInput
  { pdaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionDistinctionAdmissionDecision
  = PdadAdmitRaw
  | PdadPreserveAmbiguous
  | PdadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionDistinctionTrigger = RawPropositionDistinctionTrigger
  { rpdtLabel :: !Text
  , rpdtMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionDistinctionTriggers = AdmittedPropositionDistinctionTriggers
  { apdtRawTriggers :: ![RawPropositionDistinctionTrigger]
  , apdtTriggers :: ![RawPropositionDistinctionTrigger]
  , apdtDecision :: !PropositionDistinctionAdmissionDecision
  } deriving stock (Eq, Show)
