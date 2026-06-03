{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.StructuralAtomAdmission
  ( StructuralAtomAdmissionInput(..)
  , StructuralAtomAdmissionDecision(..)
  , AdmittedStructuralAtoms(..)
  , admitStructuralAtoms
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.MeaningAtoms (RawAtomFindings(..))
import QxFx0.Types

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

admitStructuralAtoms :: StructuralAtomAdmissionInput -> RawAtomFindings -> AdmittedStructuralAtoms
admitStructuralAtoms input rawFindings
  | truthContractIsAuthoritative (saaiTruthContractStatus input) =
      AdmittedStructuralAtoms rawFindings rawFindings SadAdmitRaw
  | all (structuralAlreadySafe . maTag) (rafStructuralAtoms rawFindings) =
      AdmittedStructuralAtoms rawFindings rawFindings SadPreserveAmbiguous
  | otherwise =
      AdmittedStructuralAtoms rawFindings rawFindings { rafStructuralAtoms = [] } SadSuppressSearching

structuralAlreadySafe :: AtomTag -> Bool
structuralAlreadySafe tag =
  case tag of
    Verification _ -> True
    Anchoring _ -> True
    NeedContact _ -> True
    _ -> False
