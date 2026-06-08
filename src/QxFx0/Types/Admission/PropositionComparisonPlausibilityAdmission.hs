{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionComparisonPlausibilityAdmission
  ( admitPropositionComparisonPlausibilityTriggers
  ) where

import QxFx0.Types.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionComparisonPlausibilityAdmission

admitPropositionComparisonPlausibilityTriggers
  :: PropositionComparisonPlausibilityAdmissionInput
  -> [RawPropositionComparisonPlausibilityTrigger]
  -> AdmittedPropositionComparisonPlausibilityTriggers
admitPropositionComparisonPlausibilityTriggers input rawTriggers
  | truthContractIsAuthoritative (pcpaiTruthContractStatus input) =
      AdmittedPropositionComparisonPlausibilityTriggers rawTriggers rawTriggers PcpadAdmitRaw
  | otherwise =
      AdmittedPropositionComparisonPlausibilityTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PcpadSuppressStrongTriggers

softenTrigger :: RawPropositionComparisonPlausibilityTrigger -> RawPropositionComparisonPlausibilityTrigger
softenTrigger rawTrigger
  | rpcppMatched rawTrigger = rawTrigger { rpcppMatched = False }
  | otherwise = rawTrigger
