{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Loop
Description : Phase 8 — End-to-end learning loop: transport -> validator -> parser -> sandbox -> graft -> telemetry.

Pure function that takes the current 'SystemState', an external query
result, and returns the updated state plus telemetry.  This is the
vertical-slice integration point: the runtime executes the
'TurnReqExternalQuery' effect elsewhere and feeds the result into
this function at finalize time.

The loop is fail-closed:
- transport error   -> record telemetry, update tool reliability down
- parse failure    -> record telemetry, reliability down
- validation fail  -> quarantine fruit (not graft), reliability down
- sandbox reject   -> record telemetry, reliability down
- sandbox accept   -> graft fruit, update lexicon/morph if provided,
                      reliability up
-}
module QxFx0.Learning.Loop
  ( LearningTelemetry(..)
  , runLearningStep
  , applyExternalLearning
  , emptyLearningTelemetry
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Learning.Calibration (CalibrationLog)
import QxFx0.Learning.Guardrails (GuardrailState)
import QxFx0.Learning.KnowledgeTree
  ( KnowledgeFruit(..)
  , KnowledgeSource(..)
  , KnowledgeTree
  , emptyKnowledgeTree
  , graftFruit
  , quarantineFruit
  )
import QxFx0.Learning.Need (LearningNeed(..), LearningNeedState(..), emptyLearningNeedState)
import QxFx0.Learning.Parser (parseLLMResponseToFruit)
import QxFx0.Learning.Sandbox
  ( SandboxMetrics(..)
  , SandboxRejectReason(..)
  , SandboxResult(..)
  , runSandboxGate
  )
import QxFx0.Learning.Signal (CalibrationSignal(..), SignalComponents(..), computeCalibrationSignal)
import QxFx0.Learning.Tool (ExternalTool(..), ToolDomain(..), selectToolWithReliability, updateToolReliability, defaultAvailableTools)
import QxFx0.Learning.Validator
  ( KnowledgeFruitPayload(..)
  , MorphologyPayload(..)
  , ValidationError(..)
  , validateFruitPayload
  )
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  )
import QxFx0.Core.TurnPipeline.Types (TurnInput(..))
import QxFx0.Types.Decision.Model (ipfRawText)
import QxFx0.Types.State.System (SystemState(..), ssLearningNeedState, ssKnowledgeTree, ssToolReliability, ssMorphology, ssTurnCount)

-- | Telemetry emitted by one learning-loop iteration.
data LearningTelemetry = LearningTelemetry
  { ltQueryType           :: !(Maybe Text)
  , ltExternalTool        :: !(Maybe Text)
  , ltValidationStatus    :: !Text
  , ltSandboxResult       :: !(Maybe Text)
  , ltGraftTurn           :: !(Maybe Int)
  , ltRejectReason        :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

emptyLearningTelemetry :: LearningTelemetry
emptyLearningTelemetry = LearningTelemetry
  { ltQueryType        = Nothing
  , ltExternalTool     = Nothing
  , ltValidationStatus = "not_attempted"
  , ltSandboxResult    = Nothing
  , ltGraftTurn        = Nothing
  , ltRejectReason     = Nothing
  }

-- | Run one learning-step iteration.
--
-- Arguments:
--   * current system state
--   * selected tool (for reliability tracking)
--   * active learning need (for strategy selection)
--   * user query text (for telemetry)
--   * maybe external query result (Nothing = no external call attempted)
--
-- Returns: (updated state, telemetry)
runLearningStep
  :: SystemState
  -> ExternalTool
  -> LearningNeed
  -> Text
  -> Maybe (Either ExternalQueryError ExternalQueryResponse)
  -> (SystemState, LearningTelemetry)
runLearningStep ss tool need query mResult =
  let turn = ssTurnCount ss
      tree0 = ssKnowledgeTree ss
      rel0  = ssToolReliability ss
      morph = ssMorphology ss
      needState = ssLearningNeedState ss

      baseTelemetry = emptyLearningTelemetry
        { ltQueryType    = Just (renderNeedTag need)
        , ltExternalTool = Just (etName tool)
        }

  in case mResult of
    Nothing ->
      -- No external call attempted.
      (ss, baseTelemetry)

    Just (Left err) ->
      -- Transport / API failure: fail-closed, penalise tool.
      let rel1 = updateToolReliability (etName tool) False rel0
          tel  = baseTelemetry
            { ltValidationStatus = "transport_error"
            , ltRejectReason     = Just (renderQueryError err)
            }
      in (ss { ssToolReliability = rel1 }, tel)

    Just (Right resp) ->
      -- Got a response: parse -> validate -> sandbox -> graft.
      case parseLLMResponseToFruit resp of
        Nothing ->
          let rel1 = updateToolReliability (etName tool) False rel0
              tel  = baseTelemetry
                { ltValidationStatus = "invalid_response"
                , ltRejectReason     = Just "parser_rejected_schema_or_text"
                }
          in (ss { ssToolReliability = rel1 }, tel)

        Just payload ->
          case validateFruitPayload payload morph of
            Left valErr ->
              let rel1 = updateToolReliability (etName tool) False rel0
                  fruit = payloadToFruit payload turn False
                  tree1 = quarantineFruit fruit tree0
                  tel   = baseTelemetry
                    { ltValidationStatus = "validation_reject"
                    , ltRejectReason     = Just (renderValidationError valErr)
                    }
              in (ss { ssKnowledgeTree = tree1, ssToolReliability = rel1 }, tel)

            Right validatedPayload ->
              case runSandboxGate ss validatedPayload of
                SandboxReject metrics reason ->
                  let rel1 = updateToolReliability (etName tool) False rel0
                      fruit = payloadToFruit validatedPayload turn False
                      tree1 = quarantineFruit fruit tree0
                      tel   = baseTelemetry
                        { ltValidationStatus = "sandbox_reject"
                        , ltSandboxResult  = Just (renderSandboxMetrics metrics)
                        , ltRejectReason   = Just (renderSandboxRejectReason reason)
                        }
                  in (ss { ssKnowledgeTree = tree1, ssToolReliability = rel1 }, tel)

                SandboxAccept metrics ->
                  let rel1 = updateToolReliability (etName tool) True rel0
                      fruit = payloadToFruit validatedPayload turn True
                      tree1 = graftFruit (renderNeedTag need) fruit tree0
                      -- TODO: merge morphology into ssMorphology when payload has mpCases
                      morph1 = mergeMorphologyPayload morph validatedPayload
                      tel   = baseTelemetry
                        { ltValidationStatus = "accept"
                        , ltSandboxResult    = Just (renderSandboxMetrics metrics)
                        , ltGraftTurn        = Just turn
                        }
                  in ( ss { ssKnowledgeTree = tree1
                          , ssToolReliability = rel1
                          , ssMorphology      = morph1
                          }
                     , tel
                     )

-- | Convert a validated payload into a 'KnowledgeFruit'.
payloadToFruit :: KnowledgeFruitPayload -> Int -> Bool -> KnowledgeFruit
payloadToFruit payload turn validated =
  KnowledgeFruit
    { kfProposition     = kfpProposition payload
    , kfWord            = kfpWord payload
    , kfSource          = kfpSource payload
    , kfValidated       = validated
    , kfConatusDelta    = kfpConatusDelta payload
    , kfPredictiveDelta = kfpPredictiveDelta payload
    , kfGraftedTurn     = if validated then Just turn else Nothing
    , kfObservedTurn    = turn
    }

-- | Merge morphology payload into runtime MorphologyData.
-- This is intentionally shallow: only adds surface forms to
-- prepositional/genitive/nominative maps, never overwrites.
-- 'mdFormsBySurface' is left untouched because 'LexemeForm' construction
-- requires case/number/tier metadata that the LLM payload does not
-- yet provide.
mergeMorphologyPayload :: MorphologyData -> KnowledgeFruitPayload -> MorphologyData
mergeMorphologyPayload morph payload =
  case kfpMorphology payload of
    Nothing -> morph
    Just mp ->
      case mpCases mp of
        Nothing -> morph
        Just cMap ->
          let addForms mOld = M.union (M.mapKeys T.toLower cMap) mOld
          in morph
               { mdNominative     = addForms (mdNominative morph)
               , mdGenitive       = addForms (mdGenitive morph)
               , mdPrepositional  = addForms (mdPrepositional morph)
               }

renderNeedTag :: LearningNeed -> Text
renderNeedTag NeedSalienceCalibration = "NeedSalienceCalibration"
renderNeedTag NeedKeywordEnrichment   = "NeedKeywordEnrichment"
renderNeedTag NeedLexiconExtension      = "NeedLexiconExtension"
renderNeedTag NeedNone                  = "NeedNone"

renderQueryError :: ExternalQueryError -> Text
renderQueryError (EqeNetworkUnavailable t) = T.concat ["network:", t]
renderQueryError (EqeAuthFailure t)        = T.concat ["auth:", t]
renderQueryError (EqeRateLimited t)        = T.concat ["rate_limit:", t]
renderQueryError (EqeServerError t)        = T.concat ["server:", t]
renderQueryError (EqeTimeout t)            = T.concat ["timeout:", t]
renderQueryError (EqeInvalidResponse t)    = T.concat ["invalid:", t]
renderQueryError EqeEmptyResponse          = "empty"

renderValidationError :: ValidationError -> Text
renderValidationError VeEmptyWord = "empty_word"
renderValidationError VeEmptyDefinition = "empty_definition"
renderValidationError (VeDefinitionTooShort a r) =
  T.concat ["too_short:", T.pack (show a), "/", T.pack (show r)]
renderValidationError (VeMorphologyParseFailure t) = T.concat ["morph_parse:", t]
renderValidationError (VeLexiconConflict t) = T.concat ["conflict:", t]
renderValidationError (VeInvalidField f r) = T.concat ["field:", f, "=", r]

renderSandboxMetrics :: SandboxMetrics -> Text
renderSandboxMetrics m =
  T.concat
    [ "conatus=", T.pack (show (sbConatusTrend m))
    , ";unc=", T.pack (show (sbUncertaintyTrend m))
    , ";loop=", T.pack (show (sbRepairLoopFreq m))
    , ";net=", T.pack (show (sbNetScore m))
    ]

renderSandboxRejectReason :: SandboxRejectReason -> Text
renderSandboxRejectReason SbrDegradingConatus   = "degrading_conatus"
renderSandboxRejectReason SbrRisingUncertainty  = "rising_uncertainty"
renderSandboxRejectReason SbrHighRepairLoopRisk = "repair_loop"
renderSandboxRejectReason SbrNegativeNetScore   = "negative_net"
renderSandboxRejectReason SbrMorphologyConflict = "morph_conflict"

-- | Convenience wrapper: apply the learning loop to a system state
-- when an external query result is present.
-- If no result was carried, returns the state unchanged.
applyExternalLearning :: SystemState -> Maybe (Either ExternalQueryError ExternalQueryResponse) -> SystemState
applyExternalLearning ss mResult =
  case mResult of
    Nothing -> ss
    Just result ->
      let needState = ssLearningNeedState ss
          need = lnsCurrentNeed needState
          mTool = selectToolWithReliability need (ssToolReliability ss) defaultAvailableTools
          tool = fromMaybe (ExternalTool "unknown" DomainGeneral 0.5 False) mTool
          queryText = case result of
            Right resp -> eqrToolName resp <> " " <> T.pack (show (eqrLatencyMs resp))
            Left _     -> ""
          (updated, _) = runLearningStep ss tool need queryText (Just result)
      in updated
