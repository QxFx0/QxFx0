{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionContactAdmission
  ( admitPropositionContactTriggers
  ) where

import Data.Text (Text)
import QxFx0.Types.Admission.GenericPropositionAdmission
import QxFx0.Types.PropositionContactAdmission

-- | Admit proposition contact triggers using generic admission logic.
-- Refactored from 43-line boilerplate to 4-line config (P1-1).
admitPropositionContactTriggers
  :: PropositionContactAdmissionInput
  -> [RawPropositionContactTrigger]
  -> AdmittedPropositionContactTriggers
admitPropositionContactTriggers =
  admitPropositionTriggers contactAdmissionConfig

contactAdmissionConfig :: PropositionAdmissionConfig
  PropositionContactAdmissionInput
  RawPropositionContactTrigger
  AdmittedPropositionContactTriggers
  PropositionContactAdmissionDecision
contactAdmissionConfig = PropositionAdmissionConfig
  { pacGetTruthContract = pcaiTruthContractStatus
  , pacTriggerLabel = rpctLabel
  , pacTriggerMatched = rpctMatched
  , pacSetTriggerMatched = \b t -> t { rpctMatched = b }
  , pacSafeLabels = safeTriggerLabels
  , pacAdmittedCtor = AdmittedPropositionContactTriggers
  , pacDecisionAdmitRaw = PcadAdmitRaw
  , pacDecisionPreserveAmbiguous = PcadPreserveAmbiguous
  , pacDecisionSuppressStrong = PcadSuppressStrongTriggers
  }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "farewell"
  , "gratitude"
  , "greeting"
  , "brief_contact_probe"
  ]
