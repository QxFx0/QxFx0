{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.SemanticContributionAdmission
  ( SemanticContributionAdmissionInput(..)
  , SemanticContributionAdmissionDecision(..)
  , AdmittedSemanticContributions(..)
  , admitSemanticContributions
  ) where

import QxFx0.Semantic.Logic (RankedFamily)
import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Types.Admission.PatternCapClarify
  ( CapClarifyConfig(..), admitByCapClarify )

data SemanticContributionAdmissionInput = SemanticContributionAdmissionInput
  { scaiTruthContractStatus :: !TruthContractStatus
  , scaiConatusGateFired :: !Bool
  , scaiFrame :: !InputPropositionFrame
  } deriving stock (Eq, Show)

data SemanticContributionAdmissionDecision
  = ScdAdmitRaw
  | ScdPreserveAmbiguous
  | ScdCapClarify
  deriving stock (Eq, Show)

data AdmittedSemanticContributions = AdmittedSemanticContributions
  { ascRawFamilies :: ![RankedFamily]
  , ascFamilies :: ![RankedFamily]
  , ascDecision :: !SemanticContributionAdmissionDecision
  } deriving stock (Eq, Show)

familyAlreadyWeak :: CanonicalMoveFamily -> Bool
familyAlreadyWeak family = family `elem` [CMClarify, CMRepair, CMGround, CMAnchor, CMContact]

contributionAdmissionInScope :: InputPropositionFrame -> Bool
contributionAdmissionInScope frame =
  ipfPropositionType frame == SelfStateQ
    && ipfConfidence frame < parserHighConfidenceThreshold

softenContributions :: [RankedFamily] -> [RankedFamily]
softenContributions = map softenOne
  where
    softenOne (fam, weight)
      | familyAlreadyWeak fam = (fam, weight)
      | otherwise = (CMClarify, weight)

admitSemanticContributions :: SemanticContributionAdmissionInput -> [RankedFamily] -> AdmittedSemanticContributions
admitSemanticContributions input rawFamilies =
  admitByCapClarify config input rawFamilies
  where
    config = CapClarifyConfig
      { cccGetTruthContract = scaiTruthContractStatus
      , cccConatusFired = scaiConatusGateFired
      , cccInScope = \inp _ -> contributionAdmissionInScope (scaiFrame inp)
      , cccAllWeak = all (familyAlreadyWeak . fst)
      , cccCapDat = softenContributions
      , cccBuildAdmitted = \_ raw proc dec -> AdmittedSemanticContributions raw proc dec
      , cccDecisionAdmit = ScdAdmitRaw
      , cccDecisionPreserve = ScdPreserveAmbiguous
      , cccDecisionCap = ScdCapClarify
      }
