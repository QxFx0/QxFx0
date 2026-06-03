{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionDistinctionAdmission
  ( admitPropositionDistinctionTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionDistinctionAdmission

admitPropositionDistinctionTriggers
  :: PropositionDistinctionAdmissionInput
  -> [RawPropositionDistinctionTrigger]
  -> AdmittedPropositionDistinctionTriggers
admitPropositionDistinctionTriggers input rawTriggers
  | truthContractIsAuthoritative (pdaiTruthContractStatus input) =
      AdmittedPropositionDistinctionTriggers rawTriggers rawTriggers PdadAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionDistinctionTriggers rawTriggers rawTriggers PdadPreserveAmbiguous
  | otherwise =
      AdmittedPropositionDistinctionTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PdadSuppressStrongTriggers

triggerAlreadySafe :: RawPropositionDistinctionTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpdtMatched rawTrigger) || rpdtLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionDistinctionTrigger -> RawPropositionDistinctionTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpdtMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "complex_relationship_between_how_differ"
  , "complex_distinguish_then_ground"
  , "complex_how_differ_practical_reasoning"
  , "complex_why_differ"
  , "complex_for_what_purpose_distinguish"
  , "complex_why_distinguish"
  , "from_token_present"
  ]
