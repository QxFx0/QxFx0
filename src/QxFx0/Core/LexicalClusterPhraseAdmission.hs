{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.LexicalClusterPhraseAdmission
  ( LexicalClusterPhraseAdmissionInput(..)
  , LexicalClusterPhraseAdmissionDecision(..)
  , AdmittedLexicalClusterPhraseContainment(..)
  , admitLexicalClusterPhraseContainment
  ) where

import QxFx0.Semantic.MeaningAtoms
  ( RawClusterPhraseContainment(..)
  , RawLexicalPhraseContainment(..)
  , RawLexicalClusterPhraseContainment(..)
  , clusterPhraseContainmentTag
  , lexicalPhraseContainmentTag
  )
import QxFx0.Types
import QxFx0.Types.Admission.PatternSuppressStrong
  ( SuppressStrongConfig(..), admitBySuppressStrong )

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

clusterPhraseAlreadySafe :: RawClusterPhraseContainment -> Bool
clusterPhraseAlreadySafe = tagAlreadySafe . clusterPhraseContainmentTag

lexicalPhraseAlreadySafe :: RawLexicalPhraseContainment -> Bool
lexicalPhraseAlreadySafe rawContainment =
  maybe True tagAlreadySafe (lexicalPhraseContainmentTag rawContainment)

admitLexicalClusterPhraseContainment
  :: LexicalClusterPhraseAdmissionInput
  -> RawLexicalClusterPhraseContainment
  -> AdmittedLexicalClusterPhraseContainment
admitLexicalClusterPhraseContainment input rawContainment =
  admitBySuppressStrong config input rawContainment
  where
    config = SuppressStrongConfig
      { sscGetTruthContract = lcpaiTruthContractStatus
      , sscAllSafe = \rc -> all clusterPhraseAlreadySafe (rlcpcClusterContainment rc)
                            && all lexicalPhraseAlreadySafe (rlcpcLexicalContainment rc)
      , sscSuppress = \rc -> rc
          { rlcpcClusterContainment = filter clusterPhraseAlreadySafe (rlcpcClusterContainment rc)
          , rlcpcLexicalContainment = filter lexicalPhraseAlreadySafe (rlcpcLexicalContainment rc)
          }
      , sscBuildAdmitted = \_ raw proc dec -> AdmittedLexicalClusterPhraseContainment raw proc dec
      , sscDecisionAdmit = LpdAdmitRaw
      , sscDecisionPreserve = LpdPreserveAmbiguous
      , sscDecisionSuppress = LpdSuppressStrongContainment
      }
