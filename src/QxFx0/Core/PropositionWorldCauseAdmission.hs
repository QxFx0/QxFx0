{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionWorldCauseAdmission
  ( admitPropositionWorldCauseTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionWorldCauseAdmission

admitPropositionWorldCauseTriggers
  :: PropositionWorldCauseAdmissionInput
  -> [RawPropositionWorldCauseTrigger]
  -> AdmittedPropositionWorldCauseTriggers
admitPropositionWorldCauseTriggers input rawTriggers
  | truthContractIsAuthoritative (pwcaiTruthContractStatus input) =
      AdmittedPropositionWorldCauseTriggers rawTriggers rawTriggers PwcAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionWorldCauseTriggers rawTriggers rawTriggers PwcPreserveAmbiguous
  | otherwise =
      AdmittedPropositionWorldCauseTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PwcSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionWorldCauseTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpwcMatched rawTrigger) || rpwcLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionWorldCauseTrigger -> RawPropositionWorldCauseTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpwcMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "world_noun_guard"
  ]
