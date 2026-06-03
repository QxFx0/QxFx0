{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionAffectiveSupportPhraseAdmission
  ( admitPropositionAffectiveSupportPhraseTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionAffectiveSupportPhraseAdmission

admitPropositionAffectiveSupportPhraseTriggers
  :: PropositionAffectiveSupportPhraseAdmissionInput
  -> [RawPropositionAffectiveSupportPhraseTrigger]
  -> AdmittedPropositionAffectiveSupportPhraseTriggers
admitPropositionAffectiveSupportPhraseTriggers input rawTriggers
  | truthContractIsAuthoritative (paspaiTruthContractStatus input) =
      AdmittedPropositionAffectiveSupportPhraseTriggers rawTriggers rawTriggers PaspadAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionAffectiveSupportPhraseTriggers rawTriggers rawTriggers PaspadPreserveAmbiguous
  | otherwise =
      AdmittedPropositionAffectiveSupportPhraseTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PaspadSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionAffectiveSupportPhraseTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpaspMatched rawTrigger) || rpaspLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionAffectiveSupportPhraseTrigger -> RawPropositionAffectiveSupportPhraseTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpaspMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "no_strength"
  , "no_energy"
  , "nothing_pleases"
  , "nothing_wanted"
  , "cant_pull_together"
  ]
