{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.PropositionAdmissionTypes
Description : Canonical proposition admission types (C4.3 consolidation)

Replaces 22 structurally identical Proposition*Admission type modules with
a single set of canonical types. Each specific module now re-exports these
types as type synonyms.
-}
module QxFx0.Types.PropositionAdmissionTypes
  ( PropositionAdmissionInput(..)
  , PropositionAdmissionDecision(..)
  , RawPropositionTrigger(..)
  , AdmittedPropositionTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionAdmissionInput = PropositionAdmissionInput
  { paiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionAdmissionDecision
  = PadAdmitRaw
  | PadPreserveAmbiguous
  | PadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionTrigger = RawPropositionTrigger
  { rptLabel :: !Text
  , rptMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionTriggers = AdmittedPropositionTriggers
  { aptRawTriggers :: ![RawPropositionTrigger]
  , aptTriggers :: ![RawPropositionTrigger]
  , aptDecision :: !PropositionAdmissionDecision
  } deriving stock (Eq, Show)
