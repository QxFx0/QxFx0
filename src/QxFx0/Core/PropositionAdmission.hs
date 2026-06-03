{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.PropositionAdmission
  ( PropositionAdmissionInput(..)
  , PropositionAdmissionDecision(..)
  , AdmittedPropositionFrame(..)
  , admitPropositionFrame
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types
import QxFx0.Types.Thresholds (parserLowConfidenceThreshold)
import qualified Data.Text as T

data PropositionAdmissionInput = PropositionAdmissionInput
  { paiTruthContractStatus :: !TruthContractStatus
  , paiConatusGateFired :: !Bool
  } deriving stock (Eq, Show)

data PropositionAdmissionDecision
  = PadAdmitRaw
  | PadPreserveAmbiguous
  | PadLowerConfidence
  deriving stock (Eq, Show)

data AdmittedPropositionFrame = AdmittedPropositionFrame
  { apfFrame :: !InputPropositionFrame
  , apfDecision :: !PropositionAdmissionDecision
  } deriving stock (Eq, Show)

admitPropositionFrame :: PropositionAdmissionInput -> InputPropositionFrame -> AdmittedPropositionFrame
admitPropositionFrame input frame
  | not (frameAdmissionInScope frame) = AdmittedPropositionFrame frame PadAdmitRaw
  | paiConatusGateFired input && not (frameAlreadyWeakOrAmbiguous frame) =
      AdmittedPropositionFrame (softenFrame "conatus_gate") PadLowerConfidence
  | not (truthContractIsAuthoritative (paiTruthContractStatus input))
      && not (frameAlreadyWeakOrAmbiguous frame) =
      AdmittedPropositionFrame (softenFrame "non_authoritative") PadLowerConfidence
  | paiConatusGateFired input || not (truthContractIsAuthoritative (paiTruthContractStatus input)) =
      AdmittedPropositionFrame (markFrameAmbiguous reasonTag) PadPreserveAmbiguous
  | otherwise = AdmittedPropositionFrame frame PadAdmitRaw
  where
    reasonTag
      | paiConatusGateFired input = "conatus_gate"
      | otherwise = "non_authoritative"

    softenFrame reason =
      let ambiguousFrame = markFrameAmbiguous reason
      in ambiguousFrame { ipfConfidence = min parserLowConfidenceThreshold (ipfConfidence frame) }

    markFrameAmbiguous reason =
      frame
        { ipfSemanticEvidence = ipfSemanticEvidence frame ++ ["proposition_admission=" <> reason]
        }

frameAlreadyWeakOrAmbiguous :: InputPropositionFrame -> Bool
frameAlreadyWeakOrAmbiguous frame =
  ipfConfidence frame <= parserLowConfidenceThreshold
    || ipfPropositionType frame `elem`
         [ "ClarifyQ"
         , "EpistemicQ"
         , "RequestQ"
         , "RepairSignal"
         , "MisunderstandingReport"
         , "ContactSignal"
         ]

frameAdmissionInScope :: InputPropositionFrame -> Bool
frameAdmissionInScope frame =
  ipfPropositionType frame == "SelfStateQ"
    && any (`elem` ["я", "мне", "меня", "мой"]) (T.words (T.toLower (ipfRawText frame)))
