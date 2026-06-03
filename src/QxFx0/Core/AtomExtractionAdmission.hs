{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.AtomExtractionAdmission
  ( AtomExtractionAdmissionInput(..)
  , AtomExtractionAdmissionDecision(..)
  , AdmittedAtomAvailability(..)
  , admitAtomAvailability
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types

data AtomExtractionAdmissionInput = AtomExtractionAdmissionInput
  { aeaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data AtomExtractionAdmissionDecision
  = AedAdmitRaw
  | AedPreserveAmbiguous
  | AedSuppressStrongFindings
  deriving stock (Eq, Show)

data AdmittedAtomAvailability = AdmittedAtomAvailability
  { aaaRawAtomSet :: !AtomSet
  , aaaAtoms :: ![MeaningAtom]
  , aaaDecision :: !AtomExtractionAdmissionDecision
  } deriving stock (Eq, Show)

admitAtomAvailability :: AtomExtractionAdmissionInput -> AtomSet -> AdmittedAtomAvailability
admitAtomAvailability input atomSet
  | truthContractIsAuthoritative (aeaiTruthContractStatus input) =
      AdmittedAtomAvailability atomSet rawAtoms AedAdmitRaw
  | all (atomExtractionAlreadySafe . maTag) rawAtoms =
      AdmittedAtomAvailability atomSet rawAtoms AedPreserveAmbiguous
  | otherwise =
      AdmittedAtomAvailability atomSet (filter (atomExtractionAlreadySafe . maTag) rawAtoms) AedSuppressStrongFindings
  where
    rawAtoms = asAtoms atomSet

atomExtractionAlreadySafe :: AtomTag -> Bool
atomExtractionAlreadySafe tag =
  case tag of
    Exhaustion _ -> True
    NeedContact _ -> True
    Verification _ -> True
    Anchoring _ -> True
    CustomAtom _ _ -> True
    AffectiveAtom _ _ -> True
    _ -> False
