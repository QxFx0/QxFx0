{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterMatchAdmission
  ( LexicalClusterMatchAdmissionInput(..)
  , LexicalClusterMatchAdmissionDecision(..)
  , AdmittedLexicalClusterMatches(..)
  , admitLexicalClusterMatches
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.MeaningAtoms (RawLexicalClusterMatches(..))
import QxFx0.Types

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

admitLexicalClusterMatches :: LexicalClusterMatchAdmissionInput -> RawLexicalClusterMatches -> AdmittedLexicalClusterMatches
admitLexicalClusterMatches input rawMatches
  | truthContractIsAuthoritative (lcaiTruthContractStatus input) =
      AdmittedLexicalClusterMatches rawMatches rawMatches LcdAdmitRaw
  | all (matchAlreadySafe . maTag) (rlmClusterAtoms rawMatches ++ rlmLexicalAtoms rawMatches) =
      AdmittedLexicalClusterMatches rawMatches rawMatches LcdPreserveAmbiguous
  | otherwise =
      AdmittedLexicalClusterMatches
        rawMatches
        rawMatches
          { rlmClusterAtoms = filter (matchAlreadySafe . maTag) (rlmClusterAtoms rawMatches)
          , rlmLexicalAtoms = filter (matchAlreadySafe . maTag) (rlmLexicalAtoms rawMatches)
          }
        LcdSuppressStrongMatches

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
