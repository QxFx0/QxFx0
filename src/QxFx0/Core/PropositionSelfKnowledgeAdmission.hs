{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionSelfKnowledgeAdmission
  ( admitPropositionSelfKnowledgeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionSelfKnowledgeAdmission

admitPropositionSelfKnowledgeTriggers
  :: PropositionSelfKnowledgeAdmissionInput
  -> [RawPropositionSelfKnowledgeTrigger]
  -> AdmittedPropositionSelfKnowledgeTriggers
admitPropositionSelfKnowledgeTriggers input rawTriggers
  | truthContractIsAuthoritative (pskaiTruthContractStatus input) =
      AdmittedPropositionSelfKnowledgeTriggers rawTriggers rawTriggers PskdAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionSelfKnowledgeTriggers rawTriggers rawTriggers PskdPreserveAmbiguous
  | otherwise =
      AdmittedPropositionSelfKnowledgeTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PskdSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionSelfKnowledgeTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpskMatched rawTrigger) || rpskLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionSelfKnowledgeTrigger -> RawPropositionSelfKnowledgeTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpskMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "single_thought_subject_guard"
  ]
