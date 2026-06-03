{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionPurposeAdmission
  ( PropositionPurposeAdmissionInput(..)
  , PropositionPurposeAdmissionDecision(..)
  , RawPropositionPurposeTrigger(..)
  , AdmittedPropositionPurposeTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionPurposeAdmissionInput = PropositionPurposeAdmissionInput
  { ppaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionPurposeAdmissionDecision
  = PpadAdmitRaw
  | PpadPreserveAmbiguous
  | PpadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionPurposeTrigger = RawPropositionPurposeTrigger
  { rpptLabel :: !Text
  , rpptMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionPurposeTriggers = AdmittedPropositionPurposeTriggers
  { apptRawTriggers :: ![RawPropositionPurposeTrigger]
  , apptTriggers :: ![RawPropositionPurposeTrigger]
  , apptDecision :: !PropositionPurposeAdmissionDecision
  } deriving stock (Eq, Show)
