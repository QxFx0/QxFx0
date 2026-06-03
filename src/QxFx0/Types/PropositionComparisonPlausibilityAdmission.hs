{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionComparisonPlausibilityAdmission
  ( PropositionComparisonPlausibilityAdmissionInput(..)
  , PropositionComparisonPlausibilityAdmissionDecision(..)
  , RawPropositionComparisonPlausibilityTrigger(..)
  , AdmittedPropositionComparisonPlausibilityTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionComparisonPlausibilityAdmissionInput = PropositionComparisonPlausibilityAdmissionInput
  { pcpaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionComparisonPlausibilityAdmissionDecision
  = PcpadAdmitRaw
  | PcpadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionComparisonPlausibilityTrigger = RawPropositionComparisonPlausibilityTrigger
  { rpcppLabel :: !Text
  , rpcppMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionComparisonPlausibilityTriggers = AdmittedPropositionComparisonPlausibilityTriggers
  { acppRawTriggers :: ![RawPropositionComparisonPlausibilityTrigger]
  , acppTriggers :: ![RawPropositionComparisonPlausibilityTrigger]
  , acppDecision :: !PropositionComparisonPlausibilityAdmissionDecision
  } deriving stock (Eq, Show)
