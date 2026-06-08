{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterMatchAdmission
  ( LexicalClusterMatchAdmissionInput(..)
  , LexicalClusterMatchAdmissionDecision(..)
  , AdmittedLexicalClusterMatches(..)
  , admitLexicalClusterMatches
  ) where

import QxFx0.Semantic.MeaningAtoms (RawLexicalClusterMatches(..))
import QxFx0.Types
import QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..), admitBySuppressStrong )

data LexicalClusterMatchAdmissionInput = LexicalClusterMatchAdmissionInput
  { lcaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data LexicalClusterMatchAdmissionDecision
  = LcdAdmitRaw
  | LcdPreserveAmbiguous
  | LcdSuppressStrongMatches
  deriving stock (Eq, Show)

data AdmittedLexicalClusterMatches = AdmittedLexicalClusterMatches
  { alcmRawMatches :: !RawLexicalClusterMatches
  , alcmMatches :: !RawLexicalClusterMatches
  , alcmDecision :: !LexicalClusterMatchAdmissionDecision
  } deriving stock (Eq, Show)

matchAlreadySafe :: AtomTag -> Bool
matchAlreadySafe tag =
  case tag of
    Exhaustion _ -> True
    NeedContact _ -> True
    Verification _ -> True
    Anchoring _ -> True
    CustomAtom _ _ -> True
    AffectiveAtom _ _ -> True
    _ -> False

admitLexicalClusterMatches :: LexicalClusterMatchAdmissionInput -> RawLexicalClusterMatches -> AdmittedLexicalClusterMatches
admitLexicalClusterMatches input rawMatches =
  admitBySuppressStrong config input rawMatches
  where
    config = SuppressStrongConfig
      { sscGetTruthContract = lcaiTruthContractStatus
      , sscAllSafe = \rm -> all (matchAlreadySafe . maTag) (rlmClusterAtoms rm ++ rlmLexicalAtoms rm)
      , sscSuppress = \rm -> rm
          { rlmClusterAtoms = filter (matchAlreadySafe . maTag) (rlmClusterAtoms rm)
          , rlmLexicalAtoms = filter (matchAlreadySafe . maTag) (rlmLexicalAtoms rm)
          }
      , sscBuildAdmitted = \_ raw proc dec -> AdmittedLexicalClusterMatches raw proc dec
      , sscDecisionAdmit = LcdAdmitRaw
      , sscDecisionPreserve = LcdPreserveAmbiguous
      , sscDecisionSuppress = LcdSuppressStrongMatches
      }
