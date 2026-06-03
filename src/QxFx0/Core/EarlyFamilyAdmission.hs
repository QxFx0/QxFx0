{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.EarlyFamilyAdmission
  ( EarlyFamilyAdmissionInput(..)
  , EarlyFamilyAdmissionDecision(..)
  , AdmittedEarlyFamily(..)
  , admitEarlyFamilyRecommendation
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)

data EarlyFamilyAdmissionInput = EarlyFamilyAdmissionInput
  { efaiTruthContractStatus :: !TruthContractStatus
  , efaiConatusGateFired :: !Bool
  } deriving stock (Eq, Show)

data EarlyFamilyAdmissionDecision
  = EfdAdmitRaw
  | EfdPreserveAmbiguous
  | EfdCapClarify
  deriving stock (Eq, Show)

data AdmittedEarlyFamily = AdmittedEarlyFamily
  { aefFamily :: !CanonicalMoveFamily
  , aefDecision :: !EarlyFamilyAdmissionDecision
  } deriving stock (Eq, Show)

admitEarlyFamilyRecommendation :: EarlyFamilyAdmissionInput -> CanonicalMoveFamily -> InputPropositionFrame -> AdmittedEarlyFamily
admitEarlyFamilyRecommendation input family frame
  | not (earlyFamilyAdmissionInScope frame) = AdmittedEarlyFamily family EfdAdmitRaw
  | efaiConatusGateFired input && not (familyAlreadyWeak family) = AdmittedEarlyFamily CMClarify EfdCapClarify
  | not (truthContractIsAuthoritative (efaiTruthContractStatus input))
      && not (familyAlreadyWeak family) = AdmittedEarlyFamily CMClarify EfdCapClarify
  | efaiConatusGateFired input || not (truthContractIsAuthoritative (efaiTruthContractStatus input)) =
      AdmittedEarlyFamily family EfdPreserveAmbiguous
  | otherwise = AdmittedEarlyFamily family EfdAdmitRaw

familyAlreadyWeak :: CanonicalMoveFamily -> Bool
familyAlreadyWeak family = family `elem` [CMClarify, CMRepair, CMAnchor, CMContact]

earlyFamilyAdmissionInScope :: InputPropositionFrame -> Bool
earlyFamilyAdmissionInScope frame =
  ipfPropositionType frame == "SelfStateQ"
    && ipfConfidence frame < parserHighConfidenceThreshold
