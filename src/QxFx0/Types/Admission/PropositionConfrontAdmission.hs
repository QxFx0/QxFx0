{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionConfrontAdmission
  ( admitPropositionConfrontTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionConfrontAdmission

-- | Admit proposition confront triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionConfrontTriggers
  :: PropositionConfrontAdmissionInput
  -> [RawPropositionConfrontTrigger]
  -> AdmittedPropositionConfrontTriggers
admitPropositionConfrontTriggers =
  admitPropositionTriggers confrontAdmissionConfig

confrontAdmissionConfig :: PropositionAdmissionConfig
  PropositionConfrontAdmissionInput
  RawPropositionConfrontTrigger
  AdmittedPropositionConfrontTriggers
  PropositionConfrontAdmissionDecision
confrontAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pcoaiTruthContractStatus
  , pacTriggerLabel = rpconfLabel
  , pacTriggerMatched = rpconfMatched
  , pacSetTriggerMatched = \b t -> t { rpconfMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionConfrontTriggers
  , pacDecisionAdmitRaw = PcondAdmitRaw
  , pacDecisionPreserveAmbiguous = PcondPreserveAmbiguous
  , pacDecisionSuppressStrong = PcondSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "contradiction_noun"
  , "doubt_marker"
  ]
