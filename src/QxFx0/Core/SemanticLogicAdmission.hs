{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.SemanticLogicAdmission
  ( SemanticLogicAdmissionInput(..)
  , SemanticLogicAdmissionDecision(..)
  , AdmittedSemanticLogic(..)
  , admitSemanticLogicWeighting
  ) where

import QxFx0.Semantic.Logic (RankedFamily)
import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Types.Admission.PatternCapClarify
  ( CapClarifyConfig(..), admitByCapClarify )

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

familyAlreadyWeak :: CanonicalMoveFamily -> Bool
familyAlreadyWeak family = family `elem` [CMClarify, CMRepair, CMGround, CMAnchor, CMContact]

weightingAdmissionInScope :: InputPropositionFrame -> Bool
weightingAdmissionInScope frame =
  ipfPropositionType frame == SelfStateQ
    && ipfConfidence frame < parserHighConfidenceThreshold

admitSemanticLogicWeighting :: SemanticLogicAdmissionInput -> [RankedFamily] -> AdmittedSemanticLogic
admitSemanticLogicWeighting input rawFamilies =
  case rawFamilies of
    [] -> AdmittedSemanticLogic [] [] SldAdmitRaw
    ((fam, weight):rest) ->
      admitByCapClarify config input rawFamilies
  where
    config = CapClarifyConfig
      { cccGetTruthContract = slaiTruthContractStatus
      , cccConatusFired = slaiConatusGateFired
      , cccInScope = \inp _ -> weightingAdmissionInScope (slaiFrame inp)
      , cccAllWeak = \dat -> case dat of
          ((fam, _):_) -> familyAlreadyWeak fam
          [] -> True
      , cccCapDat = \dat -> case dat of
          ((_, weight):rest) -> (CMClarify, weight):rest
          [] -> []
      , cccBuildAdmitted = \_ raw proc dec -> AdmittedSemanticLogic raw proc dec
      , cccDecisionAdmit = SldAdmitRaw
      , cccDecisionPreserve = SldPreserveAmbiguous
      , cccDecisionCap = SldCapClarify
      }
