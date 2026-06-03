{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterPhraseAdmission
  ( LexicalClusterPhraseAdmissionInput(..)
  , LexicalClusterPhraseAdmissionDecision(..)
  , AdmittedLexicalClusterPhraseContainment(..)
  , admitLexicalClusterPhraseContainment
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.MeaningAtoms
  ( RawClusterPhraseContainment(..)
  , RawLexicalPhraseContainment(..)
  , RawLexicalClusterPhraseContainment(..)
  , clusterPhraseContainmentTag
  , lexicalPhraseContainmentTag
  )
import QxFx0.Types

data LexicalClusterPhraseAdmissionInput = LexicalClusterPhraseAdmissionInput
  { lcpaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data LexicalClusterPhraseAdmissionDecision
  = LpdAdmitRaw
  | LpdPreserveAmbiguous
  | LpdSuppressStrongContainment
  deriving stock (Eq, Show)

data AdmittedLexicalClusterPhraseContainment = AdmittedLexicalClusterPhraseContainment
  { alcpRawContainment :: !RawLexicalClusterPhraseContainment
  , alcpContainment :: !RawLexicalClusterPhraseContainment
  , alcpDecision :: !LexicalClusterPhraseAdmissionDecision
  } deriving stock (Eq, Show)

admitLexicalClusterPhraseContainment
  :: LexicalClusterPhraseAdmissionInput
  -> RawLexicalClusterPhraseContainment
  -> AdmittedLexicalClusterPhraseContainment
admitLexicalClusterPhraseContainment input rawContainment
  | truthContractIsAuthoritative (lcpaiTruthContractStatus input) =
      AdmittedLexicalClusterPhraseContainment rawContainment rawContainment LpdAdmitRaw
  | all clusterPhraseAlreadySafe (rlcpcClusterContainment rawContainment)
      && all lexicalPhraseAlreadySafe (rlcpcLexicalContainment rawContainment) =
      AdmittedLexicalClusterPhraseContainment rawContainment rawContainment LpdPreserveAmbiguous
  | otherwise =
      AdmittedLexicalClusterPhraseContainment
        rawContainment
        rawContainment
          { rlcpcClusterContainment = filter clusterPhraseAlreadySafe (rlcpcClusterContainment rawContainment)
          , rlcpcLexicalContainment = filter lexicalPhraseAlreadySafe (rlcpcLexicalContainment rawContainment)
          }
        LpdSuppressStrongContainment

clusterPhraseAlreadySafe :: RawClusterPhraseContainment -> Bool
clusterPhraseAlreadySafe = tagAlreadySafe . clusterPhraseContainmentTag

lexicalPhraseAlreadySafe :: RawLexicalPhraseContainment -> Bool
lexicalPhraseAlreadySafe rawContainment =
  maybe True tagAlreadySafe (lexicalPhraseContainmentTag rawContainment)

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
