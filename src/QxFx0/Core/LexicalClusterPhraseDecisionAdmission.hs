{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterPhraseDecisionAdmission
  ( LexicalClusterPhraseDecisionAdmissionInput(..)
  , LexicalClusterPhraseDecisionAdmissionDecision(..)
  , AdmittedLexicalClusterPhraseDecisions(..)
  , admitLexicalClusterPhraseDecisions
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.MeaningAtoms
  ( RawClusterPhraseDecision(..)
  , RawLexicalPhraseDecision(..)
  , RawLexicalClusterPhraseDecisions(..)
  , clusterPhraseDecisionTag
  , lexicalPhraseDecisionTag
  )
import QxFx0.Types

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

admitLexicalClusterPhraseDecisions
  :: LexicalClusterPhraseDecisionAdmissionInput
  -> RawLexicalClusterPhraseDecisions
  -> AdmittedLexicalClusterPhraseDecisions
admitLexicalClusterPhraseDecisions input rawDecisions
  | truthContractIsAuthoritative (lcpdaiTruthContractStatus input) =
      AdmittedLexicalClusterPhraseDecisions rawDecisions rawDecisions LcpddAdmitRaw
  | all clusterDecisionAlreadySafe (rlcpdClusterDecisions rawDecisions)
      && all lexicalDecisionAlreadySafe (rlcpdLexicalDecisions rawDecisions) =
      AdmittedLexicalClusterPhraseDecisions rawDecisions rawDecisions LcpddPreserveAmbiguous
  | otherwise =
      AdmittedLexicalClusterPhraseDecisions
        rawDecisions
        rawDecisions
          { rlcpdClusterDecisions = map softenClusterDecision (rlcpdClusterDecisions rawDecisions)
          , rlcpdLexicalDecisions = map softenLexicalDecision (rlcpdLexicalDecisions rawDecisions)
          }
        LcpddSuppressStrongDecisions

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
