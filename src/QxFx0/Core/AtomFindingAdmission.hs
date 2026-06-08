{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.AtomFindingAdmission
  ( AtomFindingAdmissionInput(..)
  , AtomFindingAdmissionDecision(..)
  , AdmittedAtomFindings(..)
  , admitAtomFindings
  ) where

import QxFx0.Semantic.MeaningAtoms (RawAtomFindings(..))
import QxFx0.Types
import QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..), admitBySuppressStrong )

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

admitAtomFindings :: AtomFindingAdmissionInput -> RawAtomFindings -> AdmittedAtomFindings
admitAtomFindings input rawFindings =
  admitBySuppressStrong config input rawFindings
  where
    config = SuppressStrongConfig
      { sscGetTruthContract = afaiTruthContractStatus
      , sscAllSafe = \rf -> all (findingAlreadySafe . maTag) (rafClusterAtoms rf ++ rafLexicalAtoms rf)
      , sscSuppress = \rf -> rf
          { rafClusterAtoms = filter (findingAlreadySafe . maTag) (rafClusterAtoms rf)
          , rafLexicalAtoms = filter (findingAlreadySafe . maTag) (rafLexicalAtoms rf)
          }
      , sscBuildAdmitted = \_ raw proc dec -> AdmittedAtomFindings raw proc dec
      , sscDecisionAdmit = AfdAdmitRaw
      , sscDecisionPreserve = AfdPreserveAmbiguous
      , sscDecisionSuppress = AfdSuppressStrongFindings
      }
