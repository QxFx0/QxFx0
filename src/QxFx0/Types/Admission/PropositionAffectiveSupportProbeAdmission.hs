{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionAffectiveSupportProbeAdmission
  ( admitPropositionAffectiveSupportProbeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionAffectiveSupportProbeAdmission

-- | Admit proposition AffectiveSupportProbe triggers using generic admission logic.
-- Refactored from per-module boilerplate to config + safe-labels (P1-1).
admitPropositionAffectiveSupportProbeTriggers
  :: PropositionAffectiveSupportProbeAdmissionInput
  -> [RawPropositionAffectiveSupportProbeTrigger]
  -> AdmittedPropositionAffectiveSupportProbeTriggers
admitPropositionAffectiveSupportProbeTriggers =
  admitPropositionTriggers affectiveSupportProbeAdmissionConfig

affectiveSupportProbeAdmissionConfig :: PropositionAdmissionConfig
  PropositionAffectiveSupportProbeAdmissionInput
  RawPropositionAffectiveSupportProbeTrigger
  AdmittedPropositionAffectiveSupportProbeTriggers
  PropositionAffectiveSupportProbeAdmissionDecision
affectiveSupportProbeAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pasprAiTruthContractStatus
  , pacTriggerLabel = rpasprLabel
  , pacTriggerMatched = rpasprMatched
  , pacSetTriggerMatched = \b t -> t { rpasprMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionAffectiveSupportProbeTriggers
  , pacDecisionAdmitRaw = PasprAdmitRaw
  , pacDecisionPreserveAmbiguous = PasprPreserveAmbiguous
  , pacDecisionSuppressStrong = PasprSuppressStrongProbe
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "question_gate"
  ]
