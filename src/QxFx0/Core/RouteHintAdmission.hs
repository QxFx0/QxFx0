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

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Semantic.Input.Model (InputRouteHint(..), InputRouteType(..), UtteranceSemanticFrame(..))
import QxFx0.Types (TruthContractStatus)
import QxFx0.Types.Thresholds (parserLowConfidenceThreshold)

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

admitRouteHintForFrame :: RouteHintAdmissionInput -> UtteranceSemanticFrame -> AdmittedRouteHint
admitRouteHintForFrame input frame = admitRouteHint input (usfRouteHint frame)

admitRouteHint :: RouteHintAdmissionInput -> InputRouteHint -> AdmittedRouteHint
admitRouteHint input hint
  | not (hintAdmissionInScope input hint) = AdmittedRouteHint hint RhdAdmitRaw
  | rhaiConatusGateFired input && not (hintAlreadyWeakOrAmbiguous hint) =
      AdmittedRouteHint (softenHint "conatus_gate") RhdLowerConfidence
  | not (truthContractIsAuthoritative (rhaiTruthContractStatus input))
      && not (hintAlreadyWeakOrAmbiguous hint) =
      AdmittedRouteHint (softenHint "non_authoritative") RhdLowerConfidence
  | rhaiConatusGateFired input || not (truthContractIsAuthoritative (rhaiTruthContractStatus input)) =
      AdmittedRouteHint (markHintAmbiguous reasonTag) RhdPreserveAmbiguous
  | otherwise = AdmittedRouteHint hint RhdAdmitRaw
  where
    reasonTag
      | rhaiConatusGateFired input = "conatus_gate"
      | otherwise = "non_authoritative"

    softenHint reason =
      let ambiguousHint = markHintAmbiguous reason
      in ambiguousHint
          { irhRuleScore = min parserLowConfidenceThreshold (irhRuleScore hint)
          , irhSemanticScore = min parserLowConfidenceThreshold (irhSemanticScore hint)
          , irhSyntacticScore = min parserLowConfidenceThreshold (irhSyntacticScore hint)
          , irhEmbeddingScore = min parserLowConfidenceThreshold (irhEmbeddingScore hint)
          , irhConfidence = min parserLowConfidenceThreshold (irhConfidence hint)
          }

    markHintAmbiguous reason =
      hint
        { irhEvidence = take 8 (irhEvidence hint ++ ["route_hint_admission=" <> reason])
        }

hintAlreadyWeakOrAmbiguous :: InputRouteHint -> Bool
hintAlreadyWeakOrAmbiguous hint =
  irhConfidence hint <= parserLowConfidenceThreshold
    || irhTag hint `elem` ["unknown", "misunderstanding", "boundary_command", "dialogue_question"]

hintAdmissionInScope :: RouteHintAdmissionInput -> InputRouteHint -> Bool
hintAdmissionInScope input hint =
  irhTag hint `elem` ["self_state", "opinion_question"]
    && any (`elem` ["я", "мне", "меня", "мой"]) (T.words (T.toLower (rhaiRawText input)))

applyAdmittedRouteHint :: AdmittedRouteHint -> UtteranceSemanticFrame -> UtteranceSemanticFrame
applyAdmittedRouteHint admitted frame = frame { usfRouteHint = arhHint admitted }

admittedRouteHintTag :: AdmittedRouteHint -> T.Text
admittedRouteHintTag = irhTag . arhHint

admittedRouteHintConfidence :: AdmittedRouteHint -> Double
admittedRouteHintConfidence = irhConfidence . arhHint

admittedRouteHintEvidence :: AdmittedRouteHint -> [T.Text]
admittedRouteHintEvidence = irhEvidence . arhHint
