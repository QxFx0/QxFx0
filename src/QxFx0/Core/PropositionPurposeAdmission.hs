{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionPurposeAdmission
  ( admitPropositionPurposeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionPurposeAdmission

admitPropositionPurposeTriggers
  :: PropositionPurposeAdmissionInput
  -> [RawPropositionPurposeTrigger]
  -> AdmittedPropositionPurposeTriggers
admitPropositionPurposeTriggers input rawTriggers
  | truthContractIsAuthoritative (ppaiTruthContractStatus input) =
      AdmittedPropositionPurposeTriggers rawTriggers rawTriggers PpadAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionPurposeTriggers rawTriggers rawTriggers PpadPreserveAmbiguous
  | otherwise =
      AdmittedPropositionPurposeTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PpadSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionPurposeTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpptMatched rawTrigger) || rpptLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionPurposeTrigger -> RawPropositionPurposeTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpptMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "purpose_subject_guard"
  ]
