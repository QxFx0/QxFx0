{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.SemanticFrameAdmission
  ( SemanticFrameAdmissionInput(..)
  , SemanticFrameAdmissionDecision(..)
  , AdmittedSemanticFrame(..)
  , admitSemanticFrame
  , admitSemanticFrameForInput
  , admittedSemanticFrameConfidence
  , admittedSemanticFrameRouteTag
  , admittedSemanticFrameRouteEvidence
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.Input.Assemble (buildUtteranceSemanticFrame)
import QxFx0.Types
import QxFx0.Semantic.Input.Model (UtteranceSemanticFrame(..), InputRouteHint(..))
import QxFx0.Types.Thresholds (parserLowConfidenceThreshold)

import Data.Text (Text)
import qualified Data.Text as T

data SemanticFrameAdmissionInput = SemanticFrameAdmissionInput
  { sfaiTruthContractStatus :: !TruthContractStatus
  , sfaiConatusGateFired :: !Bool
  } deriving stock (Eq, Show)

data SemanticFrameAdmissionDecision
  = SfdAdmitRaw
  | SfdPreserveAmbiguous
  | SfdLowerConfidence
  deriving stock (Eq, Show)

data AdmittedSemanticFrame = AdmittedSemanticFrame
  { asfFrame :: !UtteranceSemanticFrame
  , asfDecision :: !SemanticFrameAdmissionDecision
  } deriving stock (Eq, Show)

admitSemanticFrameForInput :: SemanticFrameAdmissionInput -> Text -> AdmittedSemanticFrame
admitSemanticFrameForInput input = admitSemanticFrame input . buildUtteranceSemanticFrame

admittedSemanticFrameConfidence :: AdmittedSemanticFrame -> Double
admittedSemanticFrameConfidence = usfConfidence . asfFrame

admittedSemanticFrameRouteTag :: AdmittedSemanticFrame -> Text
admittedSemanticFrameRouteTag = irhTag . usfRouteHint . asfFrame

admittedSemanticFrameRouteEvidence :: AdmittedSemanticFrame -> [Text]
admittedSemanticFrameRouteEvidence = irhEvidence . usfRouteHint . asfFrame

admitSemanticFrame :: SemanticFrameAdmissionInput -> UtteranceSemanticFrame -> AdmittedSemanticFrame
admitSemanticFrame input frame
  | not (frameAdmissionInScope frame) = AdmittedSemanticFrame frame SfdAdmitRaw
  | sfaiConatusGateFired input && not (frameAlreadyWeakOrAmbiguous frame) =
      AdmittedSemanticFrame (softenFrame "conatus_gate") SfdLowerConfidence
  | not (truthContractIsAuthoritative (sfaiTruthContractStatus input))
      && not (frameAlreadyWeakOrAmbiguous frame) =
      AdmittedSemanticFrame (softenFrame "non_authoritative") SfdLowerConfidence
  | sfaiConatusGateFired input || not (truthContractIsAuthoritative (sfaiTruthContractStatus input)) =
      AdmittedSemanticFrame (markFrameAmbiguous reasonTag) SfdPreserveAmbiguous
  | otherwise = AdmittedSemanticFrame frame SfdAdmitRaw
  where
    reasonTag
      | sfaiConatusGateFired input = "conatus_gate"
      | otherwise = "non_authoritative"

    softenFrame reason =
      let ambiguousFrame = markFrameAmbiguous reason
          routeHint = usfRouteHint ambiguousFrame
      in ambiguousFrame
          { usfConfidence = min parserLowConfidenceThreshold (usfConfidence frame)
          , usfAmbiguityLevel = "constitution_softened"
          , usfRouteHint = routeHint { irhConfidence = min parserLowConfidenceThreshold (irhConfidence routeHint) }
          }

    markFrameAmbiguous reason =
      let routeHint = usfRouteHint frame
      in frame
          { usfSemanticCandidates = usfSemanticCandidates frame ++ ["semantic_frame_admission=" <> reason]
          , usfRouteHint = routeHint { irhEvidence = take 8 (irhEvidence routeHint ++ ["semantic_frame_admission=" <> reason]) }
          }

frameAlreadyWeakOrAmbiguous :: UtteranceSemanticFrame -> Bool
frameAlreadyWeakOrAmbiguous frame =
  usfConfidence frame <= parserLowConfidenceThreshold
    || usfAmbiguityLevel frame `elem` ["medium", "high", "constitution_softened"]

frameAdmissionInScope :: UtteranceSemanticFrame -> Bool
frameAdmissionInScope frame =
  any (`elem` ["я", "мне", "меня", "мой"]) (T.words (T.toLower (usfRawText frame)))
