{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionSelfKnowledgeAdmission
  ( PropositionSelfKnowledgeAdmissionInput(..)
  , PropositionSelfKnowledgeAdmissionDecision(..)
  , RawPropositionSelfKnowledgeTrigger(..)
  , AdmittedPropositionSelfKnowledgeTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionSelfKnowledgeAdmissionInput = PropositionSelfKnowledgeAdmissionInput
  { pskaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionSelfKnowledgeAdmissionDecision
  = PskdAdmitRaw
  | PskdPreserveAmbiguous
  | PskdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionSelfKnowledgeTrigger = RawPropositionSelfKnowledgeTrigger
  { rpskLabel :: !Text
  , rpskMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionSelfKnowledgeTriggers = AdmittedPropositionSelfKnowledgeTriggers
  { apskRawTriggers :: ![RawPropositionSelfKnowledgeTrigger]
  , apskTriggers :: ![RawPropositionSelfKnowledgeTrigger]
  , apskDecision :: !PropositionSelfKnowledgeAdmissionDecision
  } deriving stock (Eq, Show)
