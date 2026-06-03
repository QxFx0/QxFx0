{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionLocationFormationAdmission
  ( admitPropositionLocationFormationTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionLocationFormationAdmission

admitPropositionLocationFormationTriggers
  :: PropositionLocationFormationAdmissionInput
  -> [RawPropositionLocationFormationTrigger]
  -> AdmittedPropositionLocationFormationTriggers
admitPropositionLocationFormationTriggers input rawTriggers
  | truthContractIsAuthoritative (plfaiTruthContractStatus input) =
      AdmittedPropositionLocationFormationTriggers rawTriggers rawTriggers PlfdAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionLocationFormationTriggers rawTriggers rawTriggers PlfdPreserveAmbiguous
  | otherwise =
      AdmittedPropositionLocationFormationTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PlfdSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionLocationFormationTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rplfMatched rawTrigger) || rplfLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionLocationFormationTrigger -> RawPropositionLocationFormationTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rplfMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "mental_noun_guard"
  ]
