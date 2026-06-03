{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionContemplativeTopicAdmission
  ( PropositionContemplativeTopicAdmissionInput(..)
  , PropositionContemplativeTopicAdmissionDecision(..)
  , RawPropositionContemplativeTopicTrigger(..)
  , AdmittedPropositionContemplativeTopicTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionContemplativeTopicAdmissionInput = PropositionContemplativeTopicAdmissionInput
  { pctaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionContemplativeTopicAdmissionDecision
  = PpctdAdmitRaw
  | PpctdPreserveAmbiguous
  | PpctdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionContemplativeTopicTrigger = RawPropositionContemplativeTopicTrigger
  { rpctLabel :: !Text
  , rpctMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionContemplativeTopicTriggers = AdmittedPropositionContemplativeTopicTriggers
  { apctRawTriggers :: ![RawPropositionContemplativeTopicTrigger]
  , apctTriggers :: ![RawPropositionContemplativeTopicTrigger]
  , apctDecision :: !PropositionContemplativeTopicAdmissionDecision
  } deriving stock (Eq, Show)
