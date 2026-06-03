{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.InterpretationAdmission
  ( InterpretationAdmissionInput(..)
  , InterpretationAdmissionDecision(..)
  , AdmittedInterpretation(..)
  , admitInterpretationCandidate
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)

import Data.Text (Text)

data InterpretationAdmissionInput = InterpretationAdmissionInput
  { iaiTruthContractStatus :: !TruthContractStatus
  , iaiConatusGateFired :: !Bool
  } deriving stock (Eq, Show)

data InterpretationAdmissionDecision
  = IadAdmitRaw
  | IadPreserveAmbiguous
  | IadCapClarify
  | IadFallbackClarify
  deriving stock (Eq, Show)

data AdmittedInterpretation = AdmittedInterpretation
  { aiRecommendedFamily :: !CanonicalMoveFamily
  , aiFrame :: !InputPropositionFrame
  , aiDecision :: !InterpretationAdmissionDecision
  } deriving stock (Eq, Show)

admitInterpretationCandidate :: InterpretationAdmissionInput -> CanonicalMoveFamily -> InputPropositionFrame -> AdmittedInterpretation
admitInterpretationCandidate input recommendedFamily frame
  | iaiConatusGateFired input && ipfConfidence frame < parserHighConfidenceThreshold =
      if interpretationAlreadyWeakOrAmbiguous recommendedFamily frame
        then AdmittedInterpretation recommendedFamily frame IadPreserveAmbiguous
        else narrowed "conatus_gate" IadFallbackClarify
  | not (truthContractIsAuthoritative (iaiTruthContractStatus input))
      && ipfConfidence frame < parserHighConfidenceThreshold =
      if interpretationAlreadyWeakOrAmbiguous recommendedFamily frame
        then AdmittedInterpretation recommendedFamily frame IadPreserveAmbiguous
        else narrowed "non_authoritative" IadCapClarify
  | otherwise = AdmittedInterpretation recommendedFamily frame IadAdmitRaw
  where
    narrowed reason decision =
      let clarifyFamily = CMClarify
          clarifyFrame =
            frame
              { ipfCanonicalFamily = clarifyFamily
              , ipfPropositionType = "ClarifyQ"
              , ipfSemanticEvidence = ipfSemanticEvidence frame ++ ["interpretation_admission=" <> reason]
              }
      in AdmittedInterpretation clarifyFamily clarifyFrame decision

interpretationAlreadyWeakOrAmbiguous :: CanonicalMoveFamily -> InputPropositionFrame -> Bool
interpretationAlreadyWeakOrAmbiguous recommendedFamily frame =
  recommendedFamily `elem` [CMClarify, CMRepair, CMAnchor, CMContact]
    || ipfCanonicalFamily frame `elem` [CMClarify, CMRepair, CMAnchor, CMContact]
    || ipfPropositionType frame `elem`
         [ "ClarifyQ"
         , "EpistemicQ"
         , "RequestQ"
         , "RepairSignal"
         , "MisunderstandingReport"
         , "ContactSignal"
         ]
