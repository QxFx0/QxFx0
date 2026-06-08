{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.EarlyFamilyAdmission
  ( EarlyFamilyAdmissionInput(..)
  , EarlyFamilyAdmissionDecision(..)
  , AdmittedEarlyFamily(..)
  , admitEarlyFamilyRecommendation
  ) where

import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Types.Admission.PatternCapClarify
  ( CapClarifyConfig(..), admitByCapClarify )

data EarlyFamilyAdmissionInput = EarlyFamilyAdmissionInput
  { efaiTruthContractStatus :: !TruthContractStatus
  , efaiConatusGateFired :: !Bool
  } deriving stock (Eq, Show)

data EarlyFamilyAdmissionDecision
  = EfdAdmitRaw
  | EfdPreserveAmbiguous
  | EfdCapClarify
  deriving stock (Eq, Show)

data AdmittedEarlyFamily = AdmittedEarlyFamily
  { aefFamily :: !CanonicalMoveFamily
  , aefDecision :: !EarlyFamilyAdmissionDecision
  } deriving stock (Eq, Show)

familyAlreadyWeak :: CanonicalMoveFamily -> Bool
familyAlreadyWeak family = family `elem` [CMClarify, CMRepair, CMAnchor, CMContact]

earlyFamilyAdmissionInScope :: InputPropositionFrame -> Bool
earlyFamilyAdmissionInScope frame =
  ipfPropositionType frame == SelfStateQ
    && ipfConfidence frame < parserHighConfidenceThreshold

admitEarlyFamilyRecommendation :: EarlyFamilyAdmissionInput -> CanonicalMoveFamily -> InputPropositionFrame -> AdmittedEarlyFamily
admitEarlyFamilyRecommendation input family frame =
  admitByCapClarify config input family
  where
    config = CapClarifyConfig
      { cccGetTruthContract = efaiTruthContractStatus
      , cccConatusFired = efaiConatusGateFired
      , cccInScope = \_ _ -> earlyFamilyAdmissionInScope frame
      , cccAllWeak = familyAlreadyWeak
      , cccCapDat = \_ -> CMClarify
      , cccBuildAdmitted = \_ _ proc dec -> AdmittedEarlyFamily proc dec
      , cccDecisionAdmit = EfdAdmitRaw
      , cccDecisionPreserve = EfdPreserveAmbiguous
      , cccDecisionCap = EfdCapClarify
      }
