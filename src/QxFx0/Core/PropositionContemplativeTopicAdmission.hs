{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionContemplativeTopicAdmission
  ( admitPropositionContemplativeTopicTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionContemplativeTopicAdmission

admitPropositionContemplativeTopicTriggers
  :: PropositionContemplativeTopicAdmissionInput
  -> [RawPropositionContemplativeTopicTrigger]
  -> AdmittedPropositionContemplativeTopicTriggers
admitPropositionContemplativeTopicTriggers input rawTriggers
  | truthContractIsAuthoritative (pctaiTruthContractStatus input) =
      AdmittedPropositionContemplativeTopicTriggers rawTriggers rawTriggers PpctdAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionContemplativeTopicTriggers rawTriggers rawTriggers PpctdPreserveAmbiguous
  | otherwise =
      AdmittedPropositionContemplativeTopicTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PpctdSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionContemplativeTopicTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpctMatched rawTrigger) || rpctLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionContemplativeTopicTrigger -> RawPropositionContemplativeTopicTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpctMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "bare_self_pronoun"
  ]
