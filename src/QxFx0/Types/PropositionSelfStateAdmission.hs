{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionSelfStateAdmission
  ( PropositionSelfStateAdmissionInput(..)
  , PropositionSelfStateAdmissionDecision(..)
  , RawPropositionSelfStateTrigger(..)
  , AdmittedPropositionSelfStateTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionSelfStateAdmissionInput = PropositionSelfStateAdmissionInput
  { pssaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionSelfStateAdmissionDecision
  = PssadAdmitRaw
  | PssadPreserveAmbiguous
  | PssadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionSelfStateTrigger = RawPropositionSelfStateTrigger
  { rpssLabel :: !Text
  , rpssMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionSelfStateTriggers = AdmittedPropositionSelfStateTriggers
  { apssRawTriggers :: ![RawPropositionSelfStateTrigger]
  , apssTriggers :: ![RawPropositionSelfStateTrigger]
  , apssDecision :: !PropositionSelfStateAdmissionDecision
  } deriving stock (Eq, Show)
