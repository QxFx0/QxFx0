{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionMisunderstandingAdmission
  ( admitPropositionMisunderstandingTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionMisunderstandingAdmission

admitPropositionMisunderstandingTriggers
  :: PropositionMisunderstandingAdmissionInput
  -> [RawPropositionMisunderstandingTrigger]
  -> AdmittedPropositionMisunderstandingTriggers
admitPropositionMisunderstandingTriggers input rawTriggers
  | truthContractIsAuthoritative (pmiaiTruthContractStatus input) =
      AdmittedPropositionMisunderstandingTriggers rawTriggers rawTriggers PmAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionMisunderstandingTriggers rawTriggers rawTriggers PmPreserveAmbiguous
  | otherwise =
      AdmittedPropositionMisunderstandingTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PmSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionMisunderstandingTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpmtMatched rawTrigger) || rpmtLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionMisunderstandingTrigger -> RawPropositionMisunderstandingTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpmtMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "contact_lost_ru"
  , "contact_lost_en"
  , "apology_tokens"
  , "apology_phrase"
  ]
