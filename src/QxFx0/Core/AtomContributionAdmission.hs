{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.AtomContributionAdmission
  ( AtomContributionAdmissionInput(..)
  , AtomContributionAdmissionDecision(..)
  , AdmittedAtomContributions(..)
  , admitAtomContributions
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types

data AtomContributionAdmissionInput = AtomContributionAdmissionInput
  { acaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data AtomContributionAdmissionDecision
  = AcdAdmitRaw
  | AcdPreserveAmbiguous
  | AcdCapWeakProfile
  deriving stock (Eq, Show)

data AdmittedAtomContributions = AdmittedAtomContributions
  { aacRawAtomSet :: !AtomSet
  , aacAtoms :: ![MeaningAtom]
  , aacDecision :: !AtomContributionAdmissionDecision
  } deriving stock (Eq, Show)

admitAtomContributions :: AtomContributionAdmissionInput -> AtomSet -> AdmittedAtomContributions
admitAtomContributions input atomSet
  | truthContractIsAuthoritative (acaiTruthContractStatus input) =
      AdmittedAtomContributions atomSet rawAtoms AcdAdmitRaw
  | all (atomAlreadyWeak . maTag) rawAtoms =
      AdmittedAtomContributions atomSet rawAtoms AcdPreserveAmbiguous
  | otherwise =
      AdmittedAtomContributions atomSet (filter (atomAlreadyWeak . maTag) rawAtoms) AcdCapWeakProfile
  where
    rawAtoms = asAtoms atomSet

atomAlreadyWeak :: AtomTag -> Bool
atomAlreadyWeak tag =
  case tag of
    Exhaustion _ -> True
    NeedContact _ -> True
    Verification _ -> True
    Anchoring _ -> True
    _ -> False
