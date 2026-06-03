{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionContactAdmission
  ( admitPropositionContactTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionContactAdmission

admitPropositionContactTriggers
  :: PropositionContactAdmissionInput
  -> [RawPropositionContactTrigger]
  -> AdmittedPropositionContactTriggers
admitPropositionContactTriggers input rawTriggers
  | truthContractIsAuthoritative (pcaiTruthContractStatus input) =
      AdmittedPropositionContactTriggers rawTriggers rawTriggers PcadAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionContactTriggers rawTriggers rawTriggers PcadPreserveAmbiguous
  | otherwise =
      AdmittedPropositionContactTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PcadSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionContactTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpctMatched rawTrigger) || rpctLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionContactTrigger -> RawPropositionContactTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpctMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "farewell"
  , "gratitude"
  , "greeting"
  , "brief_contact_probe"
  ]
