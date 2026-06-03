{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionOperationalStatusAdmission
  ( admitPropositionOperationalStatusTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionOperationalStatusAdmission

admitPropositionOperationalStatusTriggers
  :: PropositionOperationalStatusAdmissionInput
  -> [RawPropositionOperationalStatusTrigger]
  -> AdmittedPropositionOperationalStatusTriggers
admitPropositionOperationalStatusTriggers input rawTriggers
  | truthContractIsAuthoritative (posaiTruthContractStatus input) =
      AdmittedPropositionOperationalStatusTriggers rawTriggers rawTriggers PosdAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionOperationalStatusTriggers rawTriggers rawTriggers PosdPreserveAmbiguous
  | otherwise =
      AdmittedPropositionOperationalStatusTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PosdSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionOperationalStatusTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpostMatched rawTrigger) || rpostLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionOperationalStatusTrigger -> RawPropositionOperationalStatusTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpostMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "subject_present"
  ]
