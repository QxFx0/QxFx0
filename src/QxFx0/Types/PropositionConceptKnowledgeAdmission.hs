{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionConceptKnowledgeAdmission
  ( PropositionConceptKnowledgeAdmissionInput(..)
  , PropositionConceptKnowledgeAdmissionDecision(..)
  , RawPropositionConceptKnowledgeTrigger(..)
  , AdmittedPropositionConceptKnowledgeTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionConceptKnowledgeAdmissionInput = PropositionConceptKnowledgeAdmissionInput
  { pckaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionConceptKnowledgeAdmissionDecision
  = PckdAdmitRaw
  | PckdPreserveAmbiguous
  | PckdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionConceptKnowledgeTrigger = RawPropositionConceptKnowledgeTrigger
  { rpckLabel :: !Text
  , rpckMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionConceptKnowledgeTriggers = AdmittedPropositionConceptKnowledgeTriggers
  { apckRawTriggers :: ![RawPropositionConceptKnowledgeTrigger]
  , apckTriggers :: ![RawPropositionConceptKnowledgeTrigger]
  , apckDecision :: !PropositionConceptKnowledgeAdmissionDecision
  } deriving stock (Eq, Show)
