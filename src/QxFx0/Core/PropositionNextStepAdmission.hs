{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionNextStepAdmission
  ( admitPropositionNextStepTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionNextStepAdmission

admitPropositionNextStepTriggers
  :: PropositionNextStepAdmissionInput
  -> [RawPropositionNextStepTrigger]
  -> AdmittedPropositionNextStepTriggers
admitPropositionNextStepTriggers input rawTriggers
  | truthContractIsAuthoritative (pnsaiTruthContractStatus input) =
      AdmittedPropositionNextStepTriggers rawTriggers rawTriggers PnsdAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionNextStepTriggers rawTriggers rawTriggers PnsdPreserveAmbiguous
  | otherwise =
      AdmittedPropositionNextStepTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PnsdSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionNextStepTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpnstMatched rawTrigger) || rpnstLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionNextStepTrigger -> RawPropositionNextStepTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpnstMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "direct_text_short"
  ]
