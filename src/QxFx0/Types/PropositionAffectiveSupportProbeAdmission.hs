{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionAffectiveSupportProbeAdmission
  ( PropositionAffectiveSupportProbeAdmissionInput(..)
  , PropositionAffectiveSupportProbeAdmissionDecision(..)
  , RawPropositionAffectiveSupportProbeTrigger(..)
  , AdmittedPropositionAffectiveSupportProbeTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionAffectiveSupportProbeAdmissionInput = PropositionAffectiveSupportProbeAdmissionInput
  { pasprAiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionAffectiveSupportProbeAdmissionDecision
  = PasprAdmitRaw
  | PasprPreserveAmbiguous
  | PasprSuppressStrongProbe
  deriving stock (Eq, Show)

data RawPropositionAffectiveSupportProbeTrigger = RawPropositionAffectiveSupportProbeTrigger
  { rpasprLabel :: !Text
  , rpasprMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionAffectiveSupportProbeTriggers = AdmittedPropositionAffectiveSupportProbeTriggers
  { apasprRawTriggers :: ![RawPropositionAffectiveSupportProbeTrigger]
  , apasprTriggers :: ![RawPropositionAffectiveSupportProbeTrigger]
  , apasprDecision :: !PropositionAffectiveSupportProbeAdmissionDecision
  } deriving stock (Eq, Show)
