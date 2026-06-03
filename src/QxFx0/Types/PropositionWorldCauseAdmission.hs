{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionWorldCauseAdmission
  ( PropositionWorldCauseAdmissionInput(..)
  , PropositionWorldCauseAdmissionDecision(..)
  , RawPropositionWorldCauseTrigger(..)
  , AdmittedPropositionWorldCauseTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionWorldCauseAdmissionInput = PropositionWorldCauseAdmissionInput
  { pwcaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionWorldCauseAdmissionDecision
  = PwcAdmitRaw
  | PwcPreserveAmbiguous
  | PwcSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionWorldCauseTrigger = RawPropositionWorldCauseTrigger
  { rpwcLabel :: !Text
  , rpwcMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionWorldCauseTriggers = AdmittedPropositionWorldCauseTriggers
  { apwcRawTriggers :: ![RawPropositionWorldCauseTrigger]
  , apwcTriggers :: ![RawPropositionWorldCauseTrigger]
  , apwcDecision :: !PropositionWorldCauseAdmissionDecision
  } deriving stock (Eq, Show)
