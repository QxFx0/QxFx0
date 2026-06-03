{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionRepairDirectiveAdmission
  ( admitPropositionRepairDirectiveTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionRepairDirectiveAdmission

admitPropositionRepairDirectiveTriggers
  :: PropositionRepairDirectiveAdmissionInput
  -> [RawPropositionRepairDirectiveTrigger]
  -> AdmittedPropositionRepairDirectiveTriggers
admitPropositionRepairDirectiveTriggers input rawTriggers
  | truthContractIsAuthoritative (prdaiTruthContractStatus input) =
      AdmittedPropositionRepairDirectiveTriggers rawTriggers rawTriggers PrdadAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionRepairDirectiveTriggers rawTriggers rawTriggers PrdadPreserveAmbiguous
  | otherwise =
      AdmittedPropositionRepairDirectiveTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PrdadSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionRepairDirectiveTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rprdMatched rawTrigger) || rprdLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionRepairDirectiveTrigger -> RawPropositionRepairDirectiveTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rprdMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "unclear_token_bag"
  , "template_complaint_plain"
  , "template_complaint_stressed"
  , "confused_en"
  , "not_making_sense_en"
  ]
