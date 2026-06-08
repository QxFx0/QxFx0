{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionWorldCauseAdmission
  ( admitPropositionWorldCauseTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionWorldCauseAdmission

-- | Admit proposition world-cause triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionWorldCauseTriggers
  :: PropositionWorldCauseAdmissionInput
  -> [RawPropositionWorldCauseTrigger]
  -> AdmittedPropositionWorldCauseTriggers
admitPropositionWorldCauseTriggers =
  admitPropositionTriggers worldCauseAdmissionConfig

worldCauseAdmissionConfig :: PropositionAdmissionConfig
  PropositionWorldCauseAdmissionInput
  RawPropositionWorldCauseTrigger
  AdmittedPropositionWorldCauseTriggers
  PropositionWorldCauseAdmissionDecision
worldCauseAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pwcaiTruthContractStatus
  , pacTriggerLabel = rpwcLabel
  , pacTriggerMatched = rpwcMatched
  , pacSetTriggerMatched = \b t -> t { rpwcMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionWorldCauseTriggers
  , pacDecisionAdmitRaw = PwcAdmitRaw
  , pacDecisionPreserveAmbiguous = PwcPreserveAmbiguous
  , pacDecisionSuppressStrong = PwcSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "world_noun_guard"
  ]
