{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterHitAdmission
  ( LexicalClusterHitAdmissionInput(..)
  , LexicalClusterHitAdmissionDecision(..)
  , AdmittedLexicalClusterHits(..)
  , admitLexicalClusterHits
  ) where

import QxFx0.Semantic.MeaningAtoms (RawClusterHit(..), RawLexicalClusterHits(..), RawLexicalHit(..))
import QxFx0.Types
import QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..), admitBySuppressStrong )

data LexicalClusterHitAdmissionInput = LexicalClusterHitAdmissionInput
  { lchaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data LexicalClusterHitAdmissionDecision
  = LchdAdmitRaw
  | LchdPreserveAmbiguous
  | LchdSuppressStrongHits
  deriving stock (Eq, Show)

data AdmittedLexicalClusterHits = AdmittedLexicalClusterHits
  { alchRawHits :: !RawLexicalClusterHits
  , alchHits :: !RawLexicalClusterHits
  , alchDecision :: !LexicalClusterHitAdmissionDecision
  } deriving stock (Eq, Show)

tagAlreadySafe :: AtomTag -> Bool
tagAlreadySafe tag =
  case tag of
    Exhaustion _ -> True
    NeedContact _ -> True
    Verification _ -> True
    Anchoring _ -> True
    CustomAtom _ _ -> True
    AffectiveAtom _ _ -> True
    _ -> False

rawHitAlreadySafe :: RawClusterHit -> Bool
rawHitAlreadySafe = tagAlreadySafe . rchTag

rawLexicalHitAlreadySafe :: RawLexicalHit -> Bool
rawLexicalHitAlreadySafe = tagAlreadySafe . rlhTag

admitLexicalClusterHits :: LexicalClusterHitAdmissionInput -> RawLexicalClusterHits -> AdmittedLexicalClusterHits
admitLexicalClusterHits input rawHits =
  admitBySuppressStrong config input rawHits
  where
    config = SuppressStrongConfig
      { sscGetTruthContract = lchaiTruthContractStatus
      , sscAllSafe = \rh -> all rawHitAlreadySafe (rlchClusterHits rh) && all rawLexicalHitAlreadySafe (rlchLexicalHits rh)
      , sscSuppress = \rh -> rh
          { rlchClusterHits = filter rawHitAlreadySafe (rlchClusterHits rh)
          , rlchLexicalHits = filter rawLexicalHitAlreadySafe (rlchLexicalHits rh)
          }
      , sscBuildAdmitted = \_ raw proc dec -> AdmittedLexicalClusterHits raw proc dec
      , sscDecisionAdmit = LchdAdmitRaw
      , sscDecisionPreserve = LchdPreserveAmbiguous
      , sscDecisionSuppress = LchdSuppressStrongHits
      }
