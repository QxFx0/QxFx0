{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterHitAdmission
  ( LexicalClusterHitAdmissionInput(..)
  , LexicalClusterHitAdmissionDecision(..)
  , AdmittedLexicalClusterHits(..)
  , admitLexicalClusterHits
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.MeaningAtoms (RawClusterHit(..), RawLexicalClusterHits(..), RawLexicalHit(..))
import QxFx0.Types

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

admitLexicalClusterHits :: LexicalClusterHitAdmissionInput -> RawLexicalClusterHits -> AdmittedLexicalClusterHits
admitLexicalClusterHits input rawHits
  | truthContractIsAuthoritative (lchaiTruthContractStatus input) =
      AdmittedLexicalClusterHits rawHits rawHits LchdAdmitRaw
  | all rawHitAlreadySafe (rlchClusterHits rawHits) && all rawLexicalHitAlreadySafe (rlchLexicalHits rawHits) =
      AdmittedLexicalClusterHits rawHits rawHits LchdPreserveAmbiguous
  | otherwise =
      AdmittedLexicalClusterHits
        rawHits
        rawHits
          { rlchClusterHits = filter rawHitAlreadySafe (rlchClusterHits rawHits)
          , rlchLexicalHits = filter rawLexicalHitAlreadySafe (rlchLexicalHits rawHits)
          }
        LchdSuppressStrongHits

rawHitAlreadySafe :: RawClusterHit -> Bool
rawHitAlreadySafe = tagAlreadySafe . rchTag

rawLexicalHitAlreadySafe :: RawLexicalHit -> Bool
rawLexicalHitAlreadySafe = tagAlreadySafe . rlhTag

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
