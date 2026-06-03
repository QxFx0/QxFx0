{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.SemanticLogicAdmission
  ( SemanticLogicAdmissionInput(..)
  , SemanticLogicAdmissionDecision(..)
  , AdmittedSemanticLogic(..)
  , admitSemanticLogicWeighting
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.Logic (RankedFamily)
import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)

data SemanticLogicAdmissionInput = SemanticLogicAdmissionInput
  { slaiTruthContractStatus :: !TruthContractStatus
  , slaiConatusGateFired :: !Bool
  , slaiFrame :: !InputPropositionFrame
  } deriving stock (Eq, Show)

data SemanticLogicAdmissionDecision
  = SldAdmitRaw
  | SldPreserveAmbiguous
  | SldCapClarify
  deriving stock (Eq, Show)

data AdmittedSemanticLogic = AdmittedSemanticLogic
  { aslRawFamilies :: ![RankedFamily]
  , aslFamilies :: ![RankedFamily]
  , aslDecision :: !SemanticLogicAdmissionDecision
  } deriving stock (Eq, Show)

admitSemanticLogicWeighting :: SemanticLogicAdmissionInput -> [RankedFamily] -> AdmittedSemanticLogic
admitSemanticLogicWeighting input rawFamilies =
  case rawFamilies of
    [] -> AdmittedSemanticLogic [] [] SldAdmitRaw
    ((fam, weight):rest)
      | not (weightingAdmissionInScope (slaiFrame input)) -> AdmittedSemanticLogic rawFamilies rawFamilies SldAdmitRaw
      | truthContractIsAuthoritative (slaiTruthContractStatus input) && not (slaiConatusGateFired input) ->
          AdmittedSemanticLogic rawFamilies rawFamilies SldAdmitRaw
      | familyAlreadyWeak fam -> AdmittedSemanticLogic rawFamilies rawFamilies SldPreserveAmbiguous
      | otherwise -> AdmittedSemanticLogic rawFamilies ((CMClarify, weight):rest) SldCapClarify

familyAlreadyWeak :: CanonicalMoveFamily -> Bool
familyAlreadyWeak family = family `elem` [CMClarify, CMRepair, CMGround, CMAnchor, CMContact]

weightingAdmissionInScope :: InputPropositionFrame -> Bool
weightingAdmissionInScope frame =
  ipfPropositionType frame == "SelfStateQ"
    && ipfConfidence frame < parserHighConfidenceThreshold
