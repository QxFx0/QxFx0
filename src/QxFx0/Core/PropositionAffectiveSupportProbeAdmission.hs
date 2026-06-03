{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionAffectiveSupportProbeAdmission
  ( admitPropositionAffectiveSupportProbeTriggers
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionAffectiveSupportProbeAdmission

admitPropositionAffectiveSupportProbeTriggers
  :: PropositionAffectiveSupportProbeAdmissionInput
  -> [RawPropositionAffectiveSupportProbeTrigger]
  -> AdmittedPropositionAffectiveSupportProbeTriggers
admitPropositionAffectiveSupportProbeTriggers input rawTriggers
  | truthContractIsAuthoritative (pasprAiTruthContractStatus input) =
      AdmittedPropositionAffectiveSupportProbeTriggers rawTriggers rawTriggers PasprAdmitRaw
  | all triggerAlreadySafe rawTriggers =
      AdmittedPropositionAffectiveSupportProbeTriggers rawTriggers rawTriggers PasprPreserveAmbiguous
  | otherwise =
      AdmittedPropositionAffectiveSupportProbeTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PasprSuppressStrongProbe

triggerAlreadySafe :: RawPropositionAffectiveSupportProbeTrigger -> Bool
triggerAlreadySafe rawTrigger =
  not (rpasprMatched rawTrigger) || rpasprLabel rawTrigger `elem` safeTriggerLabels

softenTrigger :: RawPropositionAffectiveSupportProbeTrigger -> RawPropositionAffectiveSupportProbeTrigger
softenTrigger rawTrigger
  | triggerAlreadySafe rawTrigger = rawTrigger
  | otherwise = rawTrigger { rpasprMatched = False }

safeTriggerLabels :: [Text]
safeTriggerLabels =
  [ "question_gate"
  ]
