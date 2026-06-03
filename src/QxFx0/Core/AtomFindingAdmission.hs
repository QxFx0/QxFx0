{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.AtomFindingAdmission
  ( AtomFindingAdmissionInput(..)
  , AtomFindingAdmissionDecision(..)
  , AdmittedAtomFindings(..)
  , admitAtomFindings
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.MeaningAtoms (RawAtomFindings(..))
import QxFx0.Types

data AtomFindingAdmissionInput = AtomFindingAdmissionInput
  { afaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data AtomFindingAdmissionDecision
  = AfdAdmitRaw
  | AfdPreserveAmbiguous
  | AfdSuppressStrongFindings
  deriving stock (Eq, Show)

data AdmittedAtomFindings = AdmittedAtomFindings
  { aafRawFindings :: !RawAtomFindings
  , aafFindings :: !RawAtomFindings
  , aafDecision :: !AtomFindingAdmissionDecision
  } deriving stock (Eq, Show)

admitAtomFindings :: AtomFindingAdmissionInput -> RawAtomFindings -> AdmittedAtomFindings
admitAtomFindings input rawFindings
  | truthContractIsAuthoritative (afaiTruthContractStatus input) =
      AdmittedAtomFindings rawFindings rawFindings AfdAdmitRaw
  | all (findingAlreadySafe . maTag) (rafClusterAtoms rawFindings ++ rafLexicalAtoms rawFindings) =
      AdmittedAtomFindings rawFindings rawFindings AfdPreserveAmbiguous
  | otherwise =
      AdmittedAtomFindings
        rawFindings
        rawFindings
          { rafClusterAtoms = filter (findingAlreadySafe . maTag) (rafClusterAtoms rawFindings)
          , rafLexicalAtoms = filter (findingAlreadySafe . maTag) (rafLexicalAtoms rawFindings)
          }
        AfdSuppressStrongFindings

findingAlreadySafe :: AtomTag -> Bool
findingAlreadySafe tag =
  case tag of
    Exhaustion _ -> True
    NeedContact _ -> True
    Verification _ -> True
    Anchoring _ -> True
    CustomAtom _ _ -> True
    AffectiveAtom _ _ -> True
    _ -> False
