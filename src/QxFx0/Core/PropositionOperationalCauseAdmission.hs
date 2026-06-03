{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionOperationalCauseAdmission
  ( admitPropositionOperationalCauseTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionOperationalCauseAdmission

admitPropositionOperationalCauseTriggers
  :: PropositionOperationalCauseAdmissionInput
  -> [RawPropositionOperationalCauseTrigger]
  -> AdmittedPropositionOperationalCauseTriggers
admitPropositionOperationalCauseTriggers input rawTriggers
  | truthContractIsAuthoritative (pocaiTruthContractStatus input) =
      AdmittedPropositionOperationalCauseTriggers rawTriggers rawTriggers PocdAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionOperationalCauseTriggers rawTriggers rawTriggers PocdPreserveAmbiguous
  | otherwise =
      AdmittedPropositionOperationalCauseTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PocdSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionOperationalCauseTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpocMatched rawTrigger) || rpocLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionOperationalCauseTrigger -> RawPropositionOperationalCauseTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpocMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "subject_present"
  ]
