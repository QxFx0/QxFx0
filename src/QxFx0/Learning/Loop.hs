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

import QxFx0.Learning.Calibration (CalibrationId(..), CalibrationLog)
import QxFx0.Learning.Guardrails (GuardrailState, recordAcceptance, recordProposalSubmission, recordRejection)
import QxFx0.Learning.KnowledgeTree
  ( KnowledgeFruit(..)
  , KnowledgeSource(..)
  , KnowledgeTree
  , emptyKnowledgeTree
  , graftFruit
  , quarantineFruit
  , ktBranches
  , ktQuarantine
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
import QxFx0.Types.Domain.Atoms (MorphologyData(..), LexemeForm(..), LexemeCase(..), LexemeNumber(..), SourceTier(..))
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  , renderFallbackReason
  )
import QxFx0.Core.TurnPipeline.Types (TurnInput(..))
import QxFx0.Types.Decision.Model (ipfRawText)
import QxFx0.Types.State.System (SystemState(..), ssGuardrailState, ssLearningNeedState, ssKnowledgeTree, ssToolReliability, ssMorphology, ssTurnCount)
import QxFx0.Types.State.System (appendAdaptiveMutationRecords)
import QxFx0.Types.State.AdaptiveMutation
  ( AdaptiveDecision(..)
  , AdaptiveMutationKind(..)
  , AdaptiveMutationRecord(..)
  , EvidenceStrength(..)
  )
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Invariants (checkInitialBlanket)
import QxFx0.Self.Conatus (computeConatusEnergy, ceScalar)

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
          records =
            [ toolReliabilityMutation turn (etName tool) False (renderQueryError err)
            ]
          tel  = baseTelemetry
            { ltValidationStatus = case err of
                EqeFallback _ -> "fallback_non_authoritative"
                _ -> "transport_error"
            , ltRejectReason     = Just (renderQueryError err)
            }
      in (appendAdaptiveMutationRecords records (ss { ssToolReliability = rel1 }), tel)

    Just (Right resp) ->
      -- Got a response: parse -> validate -> sandbox -> graft.
      let preProxy = conatusProxyFromState ss
      in case parseLLMResponseToFruit resp of
        Nothing ->
          let rel1 = updateToolReliability (etName tool) False rel0
              records =
                [ toolReliabilityMutation turn (etName tool) False "parser_rejected_schema_or_text"
                ]
              tel  = baseTelemetry
                { ltValidationStatus = "invalid_response"
                , ltRejectReason     = Just "parser_rejected_schema_or_text"
                }
          in (appendAdaptiveMutationRecords records (ss { ssToolReliability = rel1 }), tel)

        Just payload ->
          case validateFruitPayload payload morph of
            Left valErr ->
              let rel1 = updateToolReliability (etName tool) False rel0
                  ss1  = ss { ssKnowledgeTree = tree0, ssToolReliability = rel1 }
                  -- ss1 does not yet contain the quarantined fruit; add 0.01 proxy for tree growth
                  postProxy = conatusProxyFromState ss1 + 0.01
                  fruit = payloadToFruit payload turn False (postProxy - preProxy)
                  tree1 = quarantineFruit fruit tree0
                  ss2   = ss1 { ssKnowledgeTree = tree1 }
                  reason = renderValidationError valErr
                  records =
                    [ toolReliabilityMutation turn (etName tool) False reason
                    , knowledgeTreeMutation turn MutKnowledgeTree AdaptiveQuarantined EvidenceStrong "external_learning:validation_reject" reason
                    ]
                  tel   = baseTelemetry
                    { ltValidationStatus = "validation_reject"
                    , ltRejectReason     = Just reason
                    }
              in (appendAdaptiveMutationRecords records ss2, tel)

            Right validatedPayload ->
              case runSandboxGate ss validatedPayload of
                SandboxReject metrics reason ->
                  let rel1 = updateToolReliability (etName tool) False rel0
                      ss1  = ss { ssKnowledgeTree = tree0, ssToolReliability = rel1 }
                      postProxy = conatusProxyFromState ss1
                      fruit = payloadToFruit validatedPayload turn True (postProxy - preProxy)
                      tree1 = quarantineFruit fruit tree0
                      ss2   = ss1 { ssKnowledgeTree = tree1 }
                      reasonText = renderSandboxRejectReason reason
                      records =
                        [ toolReliabilityMutation turn (etName tool) False reasonText
                        , knowledgeTreeMutation turn MutKnowledgeTree AdaptiveQuarantined EvidenceStrong "external_learning:sandbox_reject" reasonText
                        ]
                      tel   = baseTelemetry
                        { ltValidationStatus = "sandbox_reject"
                        , ltSandboxResult  = Just (renderSandboxMetrics metrics)
                        , ltRejectReason   = Just reasonText
                        }
                  in (appendAdaptiveMutationRecords records ss2, tel)

                SandboxAccept metrics ->
                  let rel1 = updateToolReliability (etName tool) True rel0
                      morph1 = mergeMorphologyPayload morph validatedPayload
                      ss1  = ss { ssKnowledgeTree = tree0, ssToolReliability = rel1, ssMorphology = morph1 }
                      postProxy = conatusProxyFromState ss1 + 0.01
                      fruit = payloadToFruit validatedPayload turn True (postProxy - preProxy)
                      tree1 = graftFruit (renderNeedTag need) fruit tree0
                      ss2   = ss1 { ssKnowledgeTree = tree1 }
                      records =
                        [ toolReliabilityMutation turn (etName tool) True "sandbox_accept"
                        , knowledgeTreeMutation turn MutKnowledgeTree AdaptiveAccepted EvidenceStrong "external_learning:graft" (renderNeedTag need)
                        ]
                      tel   = baseTelemetry
                        { ltValidationStatus = "accept"
                        , ltSandboxResult    = Just (renderSandboxMetrics metrics)
                        , ltGraftTurn        = Just turn
                        }
                  in (appendAdaptiveMutationRecords records ss2, tel)

-- | Compute a proxy Conatus scalar from the current SystemState.
-- Includes the actual ConatusEnergy from SelfBlanket plus a small
-- knowledge-tree-size term so that graft/quarantine changes are visible.
conatusProxyFromState :: SystemState -> Double
conatusProxyFromState s =
  let blanket = computeSelfBlanket s
      violations = checkInitialBlanket blanket
      energy = ceScalar (computeConatusEnergy blanket violations)
      tree = ssKnowledgeTree s
      treeSize = sum (map length (M.elems (ktBranches tree))) + length (ktQuarantine tree)
  in energy + 0.01 * fromIntegral treeSize

-- | Convert a validated payload into a 'KnowledgeFruit'.
-- The conatus delta is derived from actual state change (pre vs post)
-- rather than trusting the external payload.
payloadToFruit :: KnowledgeFruitPayload -> Int -> Bool -> Double -> KnowledgeFruit
payloadToFruit payload turn validated conatusDelta =
  KnowledgeFruit
    { kfProposition     = kfpProposition payload
    , kfWord            = kfpWord payload
    , kfSource          = kfpSource payload
    , kfValidated       = validated
    , kfConatusDelta    = conatusDelta
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
          let normalizedWord = T.toLower (T.strip (kfpWord payload))
              normalizedCases = M.mapKeys T.toLower cMap
              applyCase key selector currentMap =
                case M.lookup key normalizedCases of
                  Just surfaceValue | not (T.null (T.strip surfaceValue)) -> M.insert normalizedWord (T.toLower (T.strip surfaceValue)) currentMap
                  _ -> currentMap
              newSurfaceForms = learnedSurfaceForms normalizedWord normalizedCases
              mergedSurfaceForms = M.unionWith (++) newSurfaceForms (mdFormsBySurface morph)
          in morph
               { mdNominative     = applyCase "nom" id (mdNominative morph)
               , mdGenitive       = applyCase "gen" id (mdGenitive morph)
               , mdPrepositional  = applyCase "prep" id (mdPrepositional morph)
                , mdFormsBySurface = mergedSurfaceForms
                }

learnedSurfaceForms :: Text -> M.Map Text Text -> M.Map Text [LexemeForm]
learnedSurfaceForms lemma casesMap =
  M.fromListWith (++)
    [ (surfaceValue, [mkForm lexCase surfaceValue])
    | (caseKey, surfaceValueRaw) <- M.toList casesMap
    , let surfaceValue = T.toLower (T.strip surfaceValueRaw)
    , not (T.null surfaceValue)
    , Just lexCase <- [learnedLexemeCase caseKey]
    ]
  where
    mkForm lexCase surfaceValue =
      LexemeForm
        { lfSurface = surfaceValue
        , lfLemma = lemma
        , lfPOS = "noun"
        , lfCase = lexCase
        , lfNumber = SingularNumber
        , lfTier = AutoCoverageTier
        , lfQuality = 0.55
        }

learnedLexemeCase :: Text -> Maybe LexemeCase
learnedLexemeCase rawCase =
  case T.toLower (T.strip rawCase) of
    "nom" -> Just NominativeCase
    "nominative" -> Just NominativeCase
    "gen" -> Just GenitiveCase
    "genitive" -> Just GenitiveCase
    "dat" -> Just DativeCase
    "dative" -> Just DativeCase
    "acc" -> Just AccusativeCase
    "accusative" -> Just AccusativeCase
    "ins" -> Just InstrumentalCase
    "instrumental" -> Just InstrumentalCase
    "prep" -> Just PrepositionalCase
    "prepositional" -> Just PrepositionalCase
    _ -> Nothing

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
renderQueryError (EqeFallback reason)      = T.concat ["fallback:", renderFallbackReason reason]
renderQueryError EqeEmptyResponse          = "empty"

renderValidationError :: ValidationError -> Text
renderValidationError VeEmptyWord = "empty_word"
renderValidationError VeEmptyDefinition = "empty_definition"
renderValidationError (VeDefinitionTooShort a r) =
  T.concat ["too_short:", T.pack (show a), "/", T.pack (show r)]
renderValidationError VeSemanticallyEmpty = "semantically_empty"
renderValidationError (VeMorphologyParseFailure t) = T.concat ["morph_parse:", t]
renderValidationError (VeLexiconConflict t) = T.concat ["conflict:", t]
renderValidationError (VeInvalidSchema t) = T.concat ["schema:", t]
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

toolReliabilityMutation :: Int -> Text -> Bool -> Text -> AdaptiveMutationRecord
toolReliabilityMutation turn toolName accepted reason = AdaptiveMutationRecord
  { amrTurnId = turn
  , amrKind = MutToolReliability
  , amrCause = if accepted then "tool_reliability:accepted" else "tool_reliability:rejected"
  , amrEvidence = ["tool=" <> toolName, "reason=" <> reason]
  , amrEvidenceStrength = EvidenceStrong
  , amrConfidence = 0.80
  , amrBoundedDelta = Just (if accepted then 0.05 else 0.10)
  , amrDecision = if accepted then AdaptiveAccepted else AdaptiveRejected
  }

knowledgeTreeMutation
  :: Int
  -> AdaptiveMutationKind
  -> AdaptiveDecision
  -> EvidenceStrength
  -> Text
  -> Text
  -> AdaptiveMutationRecord
knowledgeTreeMutation turn kind decision strength cause evidence = AdaptiveMutationRecord
  { amrTurnId = turn
  , amrKind = kind
  , amrCause = cause
  , amrEvidence = [evidence]
  , amrEvidenceStrength = strength
  , amrConfidence = 0.80
  , amrBoundedDelta = Just 1.0
  , amrDecision = decision
  }

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
          turn = ssTurnCount ss
          proposalId = CalibrationId turn
          submittedGuard = recordProposalSubmission (ssGuardrailState ss) turn proposalId
          ssSubmitted = ss { ssGuardrailState = submittedGuard }
          queryText = case result of
            Right resp -> eqrToolName resp <> " " <> T.pack (show (eqrLatencyMs resp))
            Left _     -> ""
          (updated, telemetry) = runLearningStep ssSubmitted tool need queryText (Just result)
          finalizedGuard =
            case ltValidationStatus telemetry of
              "accept" -> recordAcceptance (ssGuardrailState updated)
              "not_attempted" -> ssGuardrailState updated
              _ -> recordRejection (ssGuardrailState updated) turn
      in updated { ssGuardrailState = finalizedGuard }
