{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionSystemLogicAdmission
  ( admitPropositionSystemLogicTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionSystemLogicAdmission

admitPropositionSystemLogicTriggers
  :: PropositionSystemLogicAdmissionInput
  -> [RawPropositionSystemLogicTrigger]
  -> AdmittedPropositionSystemLogicTriggers
admitPropositionSystemLogicTriggers input rawTriggers
  | truthContractIsAuthoritative (pslaiTruthContractStatus input) =
      AdmittedPropositionSystemLogicTriggers rawTriggers rawTriggers PsldAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionSystemLogicTriggers rawTriggers rawTriggers PsldPreserveAmbiguous
  | otherwise =
      AdmittedPropositionSystemLogicTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PsldSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionSystemLogicTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpslMatched rawTrigger) || rpslLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionSystemLogicTrigger -> RawPropositionSystemLogicTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpslMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "subject_present"
  ]
