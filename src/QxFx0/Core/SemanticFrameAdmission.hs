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

import QxFx0.Semantic.Input.Assemble (buildUtteranceSemanticFrame)
import QxFx0.Semantic.Input.Model (UtteranceSemanticFrame(..), InputRouteHint(..), SemanticTag(..))
import QxFx0.Types
import QxFx0.Types.Thresholds (parserLowConfidenceThreshold)
import QxFx0.Types.Admission.PatternLowerConfidence
  ( LowerConfConfig(..), admitByLowerConfidence )

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

frameAlreadyWeakOrAmbiguous :: UtteranceSemanticFrame -> Bool
frameAlreadyWeakOrAmbiguous frame =
  usfConfidence frame <= parserLowConfidenceThreshold
    || usfAmbiguityLevel frame `elem` ["medium", "high", "constitution_softened"]

frameAdmissionInScope :: SemanticFrameAdmissionInput -> UtteranceSemanticFrame -> Bool
frameAdmissionInScope input frame =
  any (`elem` ["я", "мне", "меня", "мой"]) (T.words (T.toLower (usfRawText frame)))

softenFrame :: SemanticFrameAdmissionInput -> UtteranceSemanticFrame -> UtteranceSemanticFrame
softenFrame input frame =
  let ambiguousFrame = markFrameAmbiguous input frame
      routeHint = usfRouteHint ambiguousFrame
  in ambiguousFrame
      { usfConfidence = min parserLowConfidenceThreshold (usfConfidence frame)
      , usfAmbiguityLevel = "constitution_softened"
      , usfRouteHint = routeHint { irhConfidence = min parserLowConfidenceThreshold (irhConfidence routeHint) }
      }

markFrameAmbiguous :: SemanticFrameAdmissionInput -> UtteranceSemanticFrame -> UtteranceSemanticFrame
markFrameAmbiguous input frame =
  let reason = if sfaiConatusGateFired input then "conatus_gate" else "non_authoritative"
      routeHint = usfRouteHint frame
  in frame
      { usfSemanticCandidates = usfSemanticCandidates frame ++ ["semantic_frame_admission=" <> reason]
      , usfRouteHint = routeHint { irhEvidence = take 8 (irhEvidence routeHint ++ ["semantic_frame_admission=" <> reason]) }
      }

admitSemanticFrame :: SemanticFrameAdmissionInput -> UtteranceSemanticFrame -> AdmittedSemanticFrame
admitSemanticFrame input frame =
  admitByLowerConfidence config input frame
  where
    config = LowerConfConfig
      { lccGetTruthContract = sfaiTruthContractStatus
      , lccConatusFired = sfaiConatusGateFired
      , lccInScope = frameAdmissionInScope
      , lccAlreadyWeak = frameAlreadyWeakOrAmbiguous
      , lccSoften = softenFrame
      , lccMarkAmbiguous = markFrameAmbiguous
      , lccBuildAdmitted = \_ f dec -> AdmittedSemanticFrame f dec
      , lccDecisionAdmit = SfdAdmitRaw
      , lccDecisionPreserve = SfdPreserveAmbiguous
      , lccDecisionLower = SfdLowerConfidence
      }

admitSemanticFrameForInput :: SemanticFrameAdmissionInput -> Text -> AdmittedSemanticFrame
admitSemanticFrameForInput input = admitSemanticFrame input . buildUtteranceSemanticFrame

admittedSemanticFrameConfidence :: AdmittedSemanticFrame -> Double
admittedSemanticFrameConfidence = usfConfidence . asfFrame

admittedSemanticFrameRouteTag :: AdmittedSemanticFrame -> SemanticTag
admittedSemanticFrameRouteTag = irhTag . usfRouteHint . asfFrame

admittedSemanticFrameRouteEvidence :: AdmittedSemanticFrame -> [Text]
admittedSemanticFrameRouteEvidence = irhEvidence . usfRouteHint . asfFrame
