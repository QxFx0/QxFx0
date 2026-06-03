{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionOperationalCauseAdmission
  ( PropositionOperationalCauseAdmissionInput(..)
  , PropositionOperationalCauseAdmissionDecision(..)
  , RawPropositionOperationalCauseTrigger(..)
  , AdmittedPropositionOperationalCauseTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionOperationalCauseAdmissionInput = PropositionOperationalCauseAdmissionInput
  { pocaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionOperationalCauseAdmissionDecision
  = PocdAdmitRaw
  | PocdPreserveAmbiguous
  | PocdSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionOperationalCauseTrigger = RawPropositionOperationalCauseTrigger
  { rpocLabel :: !Text
  , rpocMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionOperationalCauseTriggers = AdmittedPropositionOperationalCauseTriggers
  { apocRawTriggers :: ![RawPropositionOperationalCauseTrigger]
  , apocTriggers :: ![RawPropositionOperationalCauseTrigger]
  , apocDecision :: !PropositionOperationalCauseAdmissionDecision
  } deriving stock (Eq, Show)
