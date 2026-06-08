{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.AtomExtractionAdmission
  ( AtomExtractionAdmissionInput(..)
  , AtomExtractionAdmissionDecision(..)
  , AdmittedAtomAvailability(..)
  , admitAtomAvailability
  ) where

import QxFx0.Types
import QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..), admitBySuppressStrong )

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

admitAtomAvailability :: AtomExtractionAdmissionInput -> AtomSet -> AdmittedAtomAvailability
admitAtomAvailability input atomSet =
  admitBySuppressStrong config input atomSet
  where
    rawAtoms = asAtoms atomSet
    config = SuppressStrongConfig
      { sscGetTruthContract = aeaiTruthContractStatus
      , sscAllSafe = \_ -> all (atomExtractionAlreadySafe . maTag) rawAtoms
      , sscSuppress = \_ -> atomSet { asAtoms = filter (atomExtractionAlreadySafe . maTag) rawAtoms }
      , sscBuildAdmitted = \_ raw proc dec -> AdmittedAtomAvailability raw (asAtoms proc) dec
      , sscDecisionAdmit = AedAdmitRaw
      , sscDecisionPreserve = AedPreserveAmbiguous
      , sscDecisionSuppress = AedSuppressStrongFindings
      }
