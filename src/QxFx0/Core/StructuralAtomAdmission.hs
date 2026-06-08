{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.StructuralAtomAdmission
  ( StructuralAtomAdmissionInput(..)
  , StructuralAtomAdmissionDecision(..)
  , AdmittedStructuralAtoms(..)
  , admitStructuralAtoms
  ) where

import QxFx0.Semantic.MeaningAtoms (RawAtomFindings(..))
import QxFx0.Types
import QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..), admitBySuppressStrong )

data StructuralAtomAdmissionInput = StructuralAtomAdmissionInput
  { saaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data StructuralAtomAdmissionDecision
  = SadAdmitRaw
  | SadPreserveAmbiguous
  | SadSuppressSearching
  deriving stock (Eq, Show)

data AdmittedStructuralAtoms = AdmittedStructuralAtoms
  { asaRawFindings :: !RawAtomFindings
  , asaFindings :: !RawAtomFindings
  , asaDecision :: !StructuralAtomAdmissionDecision
  } deriving stock (Eq, Show)

structuralAlreadySafe :: AtomTag -> Bool
structuralAlreadySafe tag =
  case tag of
    Verification _ -> True
    Anchoring _ -> True
    NeedContact _ -> True
    _ -> False

admitStructuralAtoms :: StructuralAtomAdmissionInput -> RawAtomFindings -> AdmittedStructuralAtoms
admitStructuralAtoms input rawFindings =
  admitBySuppressStrong config input rawFindings
  where
    config = SuppressStrongConfig
      { sscGetTruthContract = saaiTruthContractStatus
      , sscAllSafe = \rf -> all (structuralAlreadySafe . maTag) (rafStructuralAtoms rf)
      , sscSuppress = \rf -> rf { rafStructuralAtoms = [] }
      , sscBuildAdmitted = \_ raw proc dec -> AdmittedStructuralAtoms raw proc dec
      , sscDecisionAdmit = SadAdmitRaw
      , sscDecisionPreserve = SadPreserveAmbiguous
      , sscDecisionSuppress = SadSuppressSearching
      }
