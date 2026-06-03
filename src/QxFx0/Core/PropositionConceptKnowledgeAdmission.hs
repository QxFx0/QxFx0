{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionConceptKnowledgeAdmission
  ( admitPropositionConceptKnowledgeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionConceptKnowledgeAdmission

admitPropositionConceptKnowledgeTriggers
  :: PropositionConceptKnowledgeAdmissionInput
  -> [RawPropositionConceptKnowledgeTrigger]
  -> AdmittedPropositionConceptKnowledgeTriggers
admitPropositionConceptKnowledgeTriggers input rawTriggers
  | truthContractIsAuthoritative (pckaiTruthContractStatus input) =
      AdmittedPropositionConceptKnowledgeTriggers rawTriggers rawTriggers PckdAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionConceptKnowledgeTriggers rawTriggers rawTriggers PckdPreserveAmbiguous
  | otherwise =
      AdmittedPropositionConceptKnowledgeTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PckdSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionConceptKnowledgeTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpckMatched rawTrigger) || rpckLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionConceptKnowledgeTrigger -> RawPropositionConceptKnowledgeTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpckMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "concept_like_noun_guard"
  , "question_suffix_guard"
  ]
