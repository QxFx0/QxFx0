{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.SemanticContributionAdmission
  ( SemanticContributionAdmissionInput(..)
  , SemanticContributionAdmissionDecision(..)
  , AdmittedSemanticContributions(..)
  , admitSemanticContributions
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.Logic (RankedFamily)
import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)

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

admitSemanticContributions :: SemanticContributionAdmissionInput -> [RankedFamily] -> AdmittedSemanticContributions
admitSemanticContributions input rawFamilies
  | not (contributionAdmissionInScope (scaiFrame input)) =
      AdmittedSemanticContributions rawFamilies rawFamilies ScdAdmitRaw
  | truthContractIsAuthoritative (scaiTruthContractStatus input) && not (scaiConatusGateFired input) =
      AdmittedSemanticContributions rawFamilies rawFamilies ScdAdmitRaw
  | all (familyAlreadyWeak . fst) rawFamilies =
      AdmittedSemanticContributions rawFamilies rawFamilies ScdPreserveAmbiguous
  | otherwise =
      AdmittedSemanticContributions rawFamilies (softenContributions rawFamilies) ScdCapClarify

softenContributions :: [RankedFamily] -> [RankedFamily]
softenContributions = map softenOne
  where
    softenOne (fam, weight)
      | familyAlreadyWeak fam = (fam, weight)
      | otherwise = (CMClarify, weight)

familyAlreadyWeak :: CanonicalMoveFamily -> Bool
familyAlreadyWeak family = family `elem` [CMClarify, CMRepair, CMGround, CMAnchor, CMContact]

contributionAdmissionInScope :: InputPropositionFrame -> Bool
contributionAdmissionInScope frame =
  ipfPropositionType frame == "SelfStateQ"
    && ipfConfidence frame < parserHighConfidenceThreshold
