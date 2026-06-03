{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionConfrontAdmission
  ( admitPropositionConfrontTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionConfrontAdmission

admitPropositionConfrontTriggers
  :: PropositionConfrontAdmissionInput
  -> [RawPropositionConfrontTrigger]
  -> AdmittedPropositionConfrontTriggers
admitPropositionConfrontTriggers input rawTriggers
  | truthContractIsAuthoritative (pcoaiTruthContractStatus input) =
      AdmittedPropositionConfrontTriggers rawTriggers rawTriggers PcondAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionConfrontTriggers rawTriggers rawTriggers PcondPreserveAmbiguous
  | otherwise =
      AdmittedPropositionConfrontTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PcondSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionConfrontTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpconfMatched rawTrigger) || rpconfLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionConfrontTrigger -> RawPropositionConfrontTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpconfMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "contradiction_noun"
  , "doubt_marker"
  ]
