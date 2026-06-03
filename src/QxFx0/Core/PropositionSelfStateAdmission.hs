{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionSelfStateAdmission
  ( admitPropositionSelfStateTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionSelfStateAdmission

admitPropositionSelfStateTriggers
  :: PropositionSelfStateAdmissionInput
  -> [RawPropositionSelfStateTrigger]
  -> AdmittedPropositionSelfStateTriggers
admitPropositionSelfStateTriggers input rawTriggers
  | truthContractIsAuthoritative (pssaiTruthContractStatus input) =
      AdmittedPropositionSelfStateTriggers rawTriggers rawTriggers PssadAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionSelfStateTriggers rawTriggers rawTriggers PssadPreserveAmbiguous
  | otherwise =
      AdmittedPropositionSelfStateTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PssadSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionSelfStateTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpssMatched rawTrigger) || rpssLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionSelfStateTrigger -> RawPropositionSelfStateTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpssMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "generic_what_you_prefix"
  , "generic_self_state_verb"
  , "guard_about_what_plain"
  , "guard_about_what_stressed"
  , "guard_capability_knowhow"
  , "guard_capability_can"
  , "guard_self_knowledge"
  , "guard_identity"
  ]
