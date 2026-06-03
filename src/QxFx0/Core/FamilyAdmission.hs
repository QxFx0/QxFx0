{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.FamilyAdmission
  ( FamilyAdmissionInput(..)
  , FamilyAdmissionDecision(..)
  , AdmittedFamily(..)
  , admitFamilyCrystallization
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Self.Salience (SelfVerdict(..), Salience(..), SalienceDriver(..))
import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)

data FamilyAdmissionInput = FamilyAdmissionInput
  { faiTruthContractStatus :: !TruthContractStatus
  , faiSelfVerdict :: !SelfVerdict
  } deriving stock (Eq, Show)

data FamilyAdmissionDecision
  = FadAdmitRaw
  | FadPreserveAmbiguous
  | FadCapClarify
  deriving stock (Eq, Show)

data AdmittedFamily = AdmittedFamily
  { afFamily :: !CanonicalMoveFamily
  , afDecision :: !FamilyAdmissionDecision
  } deriving stock (Eq, Show)

admitFamilyCrystallization :: FamilyAdmissionInput -> CanonicalMoveFamily -> InputPropositionFrame -> AdmittedFamily
admitFamilyCrystallization input family frame
  | not (familyAdmissionInScope frame) = AdmittedFamily family FadAdmitRaw
  | conatusGate && not (familyAlreadyWeak family) = AdmittedFamily CMClarify FadCapClarify
  | not (truthContractIsAuthoritative (faiTruthContractStatus input))
      && not (familyAlreadyWeak family) = AdmittedFamily CMClarify FadCapClarify
  | conatusGate || not (truthContractIsAuthoritative (faiTruthContractStatus input)) =
      AdmittedFamily family FadPreserveAmbiguous
  | otherwise = AdmittedFamily family FadAdmitRaw
  where
    conatusGate = salienceDriver (svSalience (faiSelfVerdict input)) == DrivenByConatusGate

familyAlreadyWeak :: CanonicalMoveFamily -> Bool
familyAlreadyWeak family = family `elem` [CMClarify, CMRepair, CMAnchor, CMContact]

familyAdmissionInScope :: InputPropositionFrame -> Bool
familyAdmissionInScope frame =
  ipfPropositionType frame == "SelfStateQ"
    && ipfConfidence frame < parserHighConfidenceThreshold
