{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.RouteHintAdmission
  ( InputRouteType(..)
  , InputRouteHint(..)
  , RouteHintAdmissionInput(..)
  , RouteHintAdmissionDecision(..)
  , AdmittedRouteHint(..)
  , admitRouteHint
  , admitRouteHintForFrame
  , applyAdmittedRouteHint
  , admittedRouteHintTag
  , admittedRouteHintConfidence
  , admittedRouteHintEvidence
  ) where

import QxFx0.Semantic.Input.Model (InputRouteHint(..), InputRouteType(..), SemanticTag(..), UtteranceSemanticFrame(..))
import QxFx0.Types (TruthContractStatus)
import QxFx0.Types.Thresholds (parserLowConfidenceThreshold)
import QxFx0.Types.Admission.PatternLowerConfidence
  ( LowerConfConfig(..), admitByLowerConfidence )

import qualified Data.Text as T

data RouteHintAdmissionInput = RouteHintAdmissionInput
  { rhaiTruthContractStatus :: !TruthContractStatus
  , rhaiConatusGateFired :: !Bool
  , rhaiRawText :: !T.Text
  } deriving stock (Eq, Show)

data RouteHintAdmissionDecision
  = RhdAdmitRaw
  | RhdPreserveAmbiguous
  | RhdLowerConfidence
  deriving stock (Eq, Show)

data AdmittedRouteHint = AdmittedRouteHint
  { arhHint :: !InputRouteHint
  , arhDecision :: !RouteHintAdmissionDecision
  } deriving stock (Eq, Show)

hintAlreadyWeakOrAmbiguous :: InputRouteHint -> Bool
hintAlreadyWeakOrAmbiguous hint =
  irhConfidence hint <= parserLowConfidenceThreshold
    || irhTag hint `elem` [TagUnknown, TagMisunderstanding, TagBoundaryCommand, TagDialogueInvitation]

hintAdmissionInScope :: RouteHintAdmissionInput -> InputRouteHint -> Bool
hintAdmissionInScope input hint =
  irhTag hint `elem` [TagSelfState, TagOpinionQuestion]
    && any (`elem` ["я", "мне", "меня", "мой"]) (T.words (T.toLower (rhaiRawText input)))

softenHint :: RouteHintAdmissionInput -> InputRouteHint -> InputRouteHint
softenHint input hint =
  let ambiguousHint = markHintAmbiguous input hint
  in ambiguousHint
      { irhRuleScore = min parserLowConfidenceThreshold (irhRuleScore hint)
      , irhSemanticScore = min parserLowConfidenceThreshold (irhSemanticScore hint)
      , irhSyntacticScore = min parserLowConfidenceThreshold (irhSyntacticScore hint)
      , irhEmbeddingScore = min parserLowConfidenceThreshold (irhEmbeddingScore hint)
      , irhConfidence = min parserLowConfidenceThreshold (irhConfidence hint)
      }

markHintAmbiguous :: RouteHintAdmissionInput -> InputRouteHint -> InputRouteHint
markHintAmbiguous input hint =
  let reason = if rhaiConatusGateFired input then "conatus_gate" else "non_authoritative"
  in hint
      { irhEvidence = take 8 (irhEvidence hint ++ ["route_hint_admission=" <> reason])
      }

admitRouteHint :: RouteHintAdmissionInput -> InputRouteHint -> AdmittedRouteHint
admitRouteHint input hint =
  admitByLowerConfidence config input hint
  where
    config = LowerConfConfig
      { lccGetTruthContract = rhaiTruthContractStatus
      , lccConatusFired = rhaiConatusGateFired
      , lccInScope = hintAdmissionInScope
      , lccAlreadyWeak = hintAlreadyWeakOrAmbiguous
      , lccSoften = softenHint
      , lccMarkAmbiguous = markHintAmbiguous
      , lccBuildAdmitted = \_ h dec -> AdmittedRouteHint h dec
      , lccDecisionAdmit = RhdAdmitRaw
      , lccDecisionPreserve = RhdPreserveAmbiguous
      , lccDecisionLower = RhdLowerConfidence
      }

admitRouteHintForFrame :: RouteHintAdmissionInput -> UtteranceSemanticFrame -> AdmittedRouteHint
admitRouteHintForFrame input frame = admitRouteHint input (usfRouteHint frame)

applyAdmittedRouteHint :: AdmittedRouteHint -> UtteranceSemanticFrame -> UtteranceSemanticFrame
applyAdmittedRouteHint admitted frame = frame { usfRouteHint = arhHint admitted }

admittedRouteHintTag :: AdmittedRouteHint -> SemanticTag
admittedRouteHintTag = irhTag . arhHint

admittedRouteHintConfidence :: AdmittedRouteHint -> Double
admittedRouteHintConfidence = irhConfidence . arhHint

admittedRouteHintEvidence :: AdmittedRouteHint -> [T.Text]
admittedRouteHintEvidence = irhEvidence . arhHint
