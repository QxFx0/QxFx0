{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterPhraseDecisionAdmission
  ( LexicalClusterPhraseDecisionAdmissionInput(..)
  , LexicalClusterPhraseDecisionAdmissionDecision(..)
  , AdmittedLexicalClusterPhraseDecisions(..)
  , admitLexicalClusterPhraseDecisions
  ) where

import QxFx0.Semantic.MeaningAtoms
  ( RawClusterPhraseDecision(..)
  , RawLexicalPhraseDecision(..)
  , RawLexicalClusterPhraseDecisions(..)
  , clusterPhraseDecisionTag
  , lexicalPhraseDecisionTag
  )
import QxFx0.Types
import QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..), admitBySuppressStrong )

data LexicalClusterPhraseDecisionAdmissionInput = LexicalClusterPhraseDecisionAdmissionInput
  { lcpdaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data LexicalClusterPhraseDecisionAdmissionDecision
  = LcpddAdmitRaw
  | LcpddPreserveAmbiguous
  | LcpddSuppressStrongDecisions
  deriving stock (Eq, Show)

data AdmittedLexicalClusterPhraseDecisions = AdmittedLexicalClusterPhraseDecisions
  { alcpdRawDecisions :: !RawLexicalClusterPhraseDecisions
  , alcpdDecisions :: !RawLexicalClusterPhraseDecisions
  , alcpdDecision :: !LexicalClusterPhraseDecisionAdmissionDecision
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

clusterDecisionAlreadySafe :: RawClusterPhraseDecision -> Bool
clusterDecisionAlreadySafe rawDecision =
  not (rcpdMatched rawDecision) || tagAlreadySafe (clusterPhraseDecisionTag rawDecision)

lexicalDecisionAlreadySafe :: RawLexicalPhraseDecision -> Bool
lexicalDecisionAlreadySafe rawDecision =
  not (rlpdMatched rawDecision) || maybe True tagAlreadySafe (lexicalPhraseDecisionTag rawDecision)

softenClusterDecision :: RawClusterPhraseDecision -> RawClusterPhraseDecision
softenClusterDecision rawDecision
  | clusterDecisionAlreadySafe rawDecision = rawDecision
  | otherwise = rawDecision { rcpdMatched = False }

softenLexicalDecision :: RawLexicalPhraseDecision -> RawLexicalPhraseDecision
softenLexicalDecision rawDecision
  | lexicalDecisionAlreadySafe rawDecision = rawDecision
  | otherwise = rawDecision { rlpdMatched = False }

admitLexicalClusterPhraseDecisions
  :: LexicalClusterPhraseDecisionAdmissionInput
  -> RawLexicalClusterPhraseDecisions
  -> AdmittedLexicalClusterPhraseDecisions
admitLexicalClusterPhraseDecisions input rawDecisions =
  admitBySuppressStrong config input rawDecisions
  where
    config = SuppressStrongConfig
      { sscGetTruthContract = lcpdaiTruthContractStatus
      , sscAllSafe = \rd -> all clusterDecisionAlreadySafe (rlcpdClusterDecisions rd)
                              && all lexicalDecisionAlreadySafe (rlcpdLexicalDecisions rd)
      , sscSuppress = \rd -> rd
          { rlcpdClusterDecisions = map softenClusterDecision (rlcpdClusterDecisions rd)
          , rlcpdLexicalDecisions = map softenLexicalDecision (rlcpdLexicalDecisions rd)
          }
      , sscBuildAdmitted = \_ raw proc dec -> AdmittedLexicalClusterPhraseDecisions raw proc dec
      , sscDecisionAdmit = LcpddAdmitRaw
      , sscDecisionPreserve = LcpddPreserveAmbiguous
      , sscDecisionSuppress = LcpddSuppressStrongDecisions
      }
