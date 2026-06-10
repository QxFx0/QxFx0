{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : observer — Finalize-stage turn replay trace projection and serialization. -}

module QxFx0.Core.TurnPipeline.Finalize.Projection
  ( buildTurnProjection
  , turnInputSalience
  ) where

import Control.Applicative ((<|>))
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision)
import QxFx0.Core.TurnRouting.Cascade (commitmentFamilyHint)
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Core.TopicDrift.Pressure (buildDreamOutcome)
import QxFx0.Core.Observability
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Core.TruthContract
  ( normalizedReplayProvenanceStatus
  , replayProvenanceStatusForOutcome
  , truthContractIsAuthoritative
  )
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Learning.Guardrails (ExternalActionDecisionReason(..), ExternalActionDecisionTrace(..), ExternalActionKind(..))
import QxFx0.Semantic.Embedding (embeddingQualityText)
import QxFx0.Semantic.Proposition (parseProposition)
import QxFx0.Semantic.Sense (rspChosenOperator, rspInputVector, rspPreservedAxes, svAnchor, unSemanticNodeId)
import QxFx0.Self.Deliberation
  ( renderAgreement
  , renderNarrativeTone
  , renderReconcileRule
  , delibTrace
  , delibReconciled
  , dtRule
  , dtAgreement
  , dtDivergence
  , planNarrativeTone
  )
import QxFx0.Self.Essence
  ( Essence(..)
  , EssenceMode(..)
  , EssenceTrajectory(..)
  , EssenceCommitment(..)
  , renderCommitmentTrigger
  , renderEssenceMode
  )
import QxFx0.Memory.Episodic (EpisodicStore(..), EpisodicEvent(..), EpisodicQuery, EpisodicId, ReuseAnnotation, episodicRecallActive, recallForTrace)
import QxFx0.Self.Perspective (buildActivePerspectiveProjections)
import QxFx0.Self.Salience (Salience(..), renderSalienceDriver, svSalience)
import QxFx0.Self.Field
  ( fieldCounterfactual, fieldConfidence, unCounterfactual, unFieldConfidence
  , fieldAtmosphere, atmosphereValence, atmosphereArousal, affectDecoupledActive )
import QxFx0.Core.Bayesian (maxBelief, dominantIntent, userModelActive)
import QxFx0.Semantic.Logic (derivedInferenceActive, deriveAtoms)
import QxFx0.Core.ContentCluster (computeContentSaliency, contentSalienceActive)
import QxFx0.Types.CognitiveSignals (CognitiveSignals)
import qualified QxFx0.Types.CognitiveSignals as CS
import QxFx0.Types
import QxFx0.Types.Config.Dream (defaultDreamPressureRegime)
import QxFx0.Types.ExternalQuery (renderExternalQueryError)
import QxFx0.Types.RuntimeRegime (defaultRuntimeRegime, rrFamilyDivergenceActive, rrMathVersion, rrRglMorphologyActive)
import QxFx0.Types.State.SemanticCommitment (CommitmentEngagement(..), scsActive, scsQuarantine)
import qualified Data.HashMap.Strict as HashMap
import QxFx0.Types.Thresholds
  ( LegitimacyStatus(..)
  , ScenePressure(..)
  , legitimacyPassThreshold
  , legitimacyRecoveryThreshold
  , parserLowConfidenceThreshold
  , scenePressureLowThreshold
  , scenePressureMediumThreshold
  )

turnInputSalience :: TurnInput -> Salience
turnInputSalience = svSalience . tiSelfVerdict

-- | WP-S: compute the shared derived-signal bundle once. The single point
-- where counterfactual entropy, field confidence, shadow disagreement, and the
-- user-model posterior peak are derived; WP-D / WP-E read this rather than
-- re-deriving from 'Field' / shadow status / posterior independently.
buildCognitiveSignals :: TurnInput -> TurnPlan -> SystemState -> CognitiveSignals
buildCognitiveSignals ti tp nextSs = CS.CognitiveSignals
  { CS.csCounterfactualEntropy = unCounterfactual (fieldCounterfactual (tiField ti))
  , CS.csFieldConfidence       = unFieldConfidence (fieldConfidence (tiField ti))
  , CS.csShadowDisagreement    = tpShadowGateTriggered tp
  , CS.csMaxPosterior          = maxBelief (ssUserModel nextSs)
  , CS.csContentSaliency       = computeContentSaliency (ssMeaningGraph nextSs)
  }

buildTurnProjection
  :: Text
  -> Text
  -> Text
  -> Bool
  -> Bool
  -> FmarMode
  -> SystemState
  -> TurnInput
  -> TurnSignals
  -> TurnPlan
  -> TurnArtifacts
  -> CommitmentStoreAdmissionDecision
  -> Int
  -> CommitmentEngagement
  -> TurnProjection
buildTurnProjection runtimeMode shadowPolicy localRecoveryPolicy semanticIntrospectionEnabled warnMorphologyFallbackEnabled fmarMode nextSs ti ts tp ta commitDecision promotedCount commitmentEngagement =
  let decision = taDecision ta
      dreamOutcome = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
      executedOutcome = taExecutedOutcome ta
      executedFamily = etoFamily executedOutcome
      executedForce = etoForce executedOutcome
      parserConfidence = ipfConfidence (tiFrame ti)
      parserErrors = if parserConfidence < parserLowConfidenceThreshold then ["low_confidence"] else []
      parserBackend = "local_rule_based"
      parserAdmissionAdjusted = any (\tag -> T.isPrefixOf "interpretation_admission=" tag || T.isPrefixOf "proposition_admission=" tag || T.isInfixOf "semantic_frame_admission=" tag || T.isInfixOf "route_hint_admission=" tag) (ipfSemanticEvidence (tiFrame ti))
      parserStatus
        | tiFrame ti == parseProposition (ipfRawText (tiFrame ti)) = "ok"
        | parserAdmissionAdjusted = "constitution_admitted"
        | otherwise = "degraded"
      parserDegradationReason
        | parserStatus == "ok" = Nothing
        | parserStatus == "constitution_admitted" = Just "constitution_interpretation_admission"
        | otherwise = Just "frame_runtime_mismatch"
      parserLatencyMs = 0
      scenePressure
        | asLoad (tiAtomSet ti) <= scenePressureLowThreshold = PressureLow
        | asLoad (tiAtomSet ti) <= scenePressureMediumThreshold = PressureMedium
        | otherwise = PressureHigh
      legitScore = tpLegitScore tp
      legitimacyStatus
        | legitScore >= legitimacyPassThreshold = LegitimacyPass
        | legitScore >= legitimacyRecoveryThreshold = LegitimacyDegraded
        | otherwise = LegitimacyRecovery
      legitimacyReason
        | tpShadowGateTriggered tp = ReasonShadowDivergence
        | tpShadowStatus tp == ShadowUnavailable = ReasonShadowUnavailable
        | parserConfidence < parserLowConfidenceThreshold = ReasonLowParserConfidence
        | otherwise = ReasonOk
      ownerFamily = executedFamily
      ownerForce = executedForce
      warrantedMode = warrantedForFamily ownerFamily
      legitimacyOutcome = classifyLegitimacyOutcome legitimacyStatus legitimacyReason warrantedMode (tpShadowStatus tp) (tpShadowDivergenceSeverity tp)
      requestId = tmRequestId (tiMetrics ti)
      sessionId = tmSessionId (tiMetrics ti)
      intuitionHint = ifDirective <$> tsFlash ts
      (recoveryCause, recoveryStrategy, recoveryEvidence) =
        case taLocalRecoveryCause ta of
          Just cause ->
            (Just cause, taLocalRecoveryStrategy ta, taLocalRecoveryEvidence ta)
          Nothing
            | runtimeMode == "degraded" ->
                (Nothing, Nothing, ["runtime_mode=degraded"])
          Nothing ->
            (Nothing, Nothing, [])
      traceSalience = turnInputSalience ti
      postEssence = selfEssence (ssSelfState nextSs)
      perspectiveProjections = buildActivePerspectiveProjections (selfPerspectiveRegistry (ssSelfState nextSs))
      learningVerdict = deriveLearningReplayVerdict nextSs ta
      -- P8: Audit trail visibility fields
      doubtScore = if tiDoubtScore ti > 0 then Just (tiDoubtScore ti) else Nothing
      episodicRetrievalCount = if episodicRecallActive && not (null (tiRetrievedEpisodes ti))
                                 then Just (length (tiRetrievedEpisodes ti))
                                 else Nothing
      contentSaliencyDominantCluster = if contentSalienceActive
                                         then Just 0  -- Placeholder: dominant cluster from csContentSaliency
                                         else Nothing
      moodValence = Just (atmosphereValence (fieldAtmosphere (tiField ti)))
      moodArousal = Just (atmosphereArousal (fieldAtmosphere (tiField ti)))
      affectDecoupled = affectDecoupledActive
      persistentMood = ssMood nextSs
      (userModelTopIntent, userModelConfidence) =
        case dominantIntent (ssUserModel nextSs) of
          Just intent | userModelActive ->
            let intentText = T.pack (show intent)
                confidence = maxBelief (ssUserModel nextSs)
            in (Just intentText, Just confidence)
          _ -> (Nothing, Nothing)
      derivedInferenceCount = if derivedInferenceActive
                                then Just (length (deriveAtoms (asAtoms (tiAtomSet ti))))
                                else Nothing
      familyDivergenceOccurred = if rrFamilyDivergenceActive defaultRuntimeRegime
                                   then Just (tpPreShadowFamily tp /= tpFamily tp)
                                   else Nothing
      (modeTag, committedFlag, angst, triggerTag) =
        case postEssence of
          EssenceUncommitted t ->
            ( Just (renderEssenceMode EssenceWitnessing)
            , Just False
            , Just (etAngstLevel t)
            , Nothing
            )
          EssenceCommitted t c ->
            ( Just (renderEssenceMode (ecMode c))
            , Just True
            , Just (etAngstLevel t)
            , Just (renderCommitmentTrigger (ecTrigger c))
            )
      replayTrace =
        TurnReplayTrace
          { trcRequestId = requestId
          , trcSessionId = sessionId
          , trcRuntimeMode = runtimeMode
          , trcShadowPolicy = shadowPolicy
          , trcLocalRecoveryPolicy = localRecoveryPolicy
          , trcRecoveryCause = recoveryCause
          , trcRecoveryStrategy = recoveryStrategy
          , trcRecoveryEvidence = recoveryEvidence
          , trcSemanticIntrospectionEnabled = semanticIntrospectionEnabled
          , trcWarnMorphologyFallbackEnabled = warnMorphologyFallbackEnabled
          , trcRequestedFamily = tiRecommendedFamily ti
          , trcStrategyFamily = tpStrategyFamily tp
          , trcNarrativeHint = tsNarrativeFragment ts
          , trcIntuitionHint = intuitionHint
          , trcPreShadowFamily = tpPreShadowFamily tp
          , trcShadowSnapshotId = tpShadowSnapshotId tp
          , trcShadowStatus = tpShadowStatus tp
          , trcShadowDivergenceKind = tpShadowDivergenceKind tp
          , trcShadowDivergenceSeverity = tpShadowDivergenceSeverity tp
          , trcShadowResolvedFamily = tpFamily tp
          , trcFinalFamily = executedFamily
          , trcFinalForce = executedForce
          , trcDecisionDisposition = loDisposition legitimacyOutcome
          , trcLegitimacyReason = legitimacyReason
          , trcParserConfidence = parserConfidence
          , trcParserBackend = parserBackend
          , trcParserStatus = parserStatus
          , trcParserDegradationReason = parserDegradationReason
          , trcParserLatencyMs = parserLatencyMs
          , trcEmbeddingQuality = embeddingQualityText (tiEmbeddingQuality ti)
          , trcClaimAst = taClaimAst ta
          , trcPreSafetyRenderedRaw = taPreSafetyRendered ta
          , trcRenderedAfterRebind = taRendered ta
          , trcLinearizationLang = taLinearizationLang ta
          , trcLinearizationOk = taLinearizationOk ta
          , trcFallbackReason = taLinearizationFallbackReason ta
          , trcContractProvenance = Just (etoContractProvenance executedOutcome)
          , trcSurfaceProvenance = Just (etoSurfaceProvenance executedOutcome)
          , trcAuthorityClass = Just (etoAuthorityClass executedOutcome)
          , trcTruthContractStatus = etoTruthContractStatus executedOutcome
          , trcResponseSurfaceKind = Just (etoResponseSurfaceKind executedOutcome)
          , trcAssemblyPath = Just (etoAssemblyPath executedOutcome)
          , trcArtifactManifest = Just (etoArtifactManifest executedOutcome)
          , trcReplayProvenanceStatus = normalizedReplayProvenanceStatus (replayProvenanceStatusForOutcome executedOutcome) (etoAuthorityClass executedOutcome)
          , trcDerivationTags = taDerivationTags ta
          , trcSalienceDriver = renderSalienceDriver (salienceDriver traceSalience)
          , trcSalienceHolisticBias = salienceHolisticBias traceSalience
          , trcSalienceConfidence = salienceConfidence traceSalience
          , trcDeliberationRule = tpDeliberation tp >>= \d -> Just (renderReconcileRule (dtRule (delibTrace d)))
          , trcDeliberationAgreement = tpDeliberation tp >>= \d -> Just (renderAgreement (dtAgreement (delibTrace d)))
          , trcDeliberationDivergence = tpDeliberation tp >>= \d -> Just (dtDivergence (delibTrace d))
          , trcDeliberationNarrativeTone = tpDeliberation tp >>= \d -> Just (renderNarrativeTone (planNarrativeTone (delibReconciled d)))
          , trcEssenceMode = modeTag
          , trcEssenceCommitted = committedFlag
          , trcEssenceAngstLevel = angst
          , trcEssenceTrigger = triggerTag
          , trcLearningQueryType =
              case (taExternalQueryResult ta, taExploratoryQueryResult ta) of
                (Nothing, Nothing) -> Nothing
                (Just _, Nothing) -> Just "request_concept"
                (Nothing, Just _) -> Just "exploratory"
                (Just _, Just _) -> Just "both"
          , trcExternalTool =
              case taExternalQueryResult ta of
                Just (Right resp) -> Just (eqrToolName resp)
                _ -> case taExploratoryQueryResult ta of
                       Just (Right resp) -> Just (eqrToolName resp)
                       _ -> Nothing
          , trcLearningValidationStatus = Just (lrvStatus learningVerdict)
          , trcLearningSandboxResult = lrvSandboxResult learningVerdict
          , trcLearningGraftTurn = lrvGraftTurn learningVerdict
          , trcLearningRejectReason = lrvRejectReason learningVerdict
          , trcExternalActionReason = fmap (renderExternalActionDecisionReason . eadtReason) (taExternalActionDecisionTrace ta)
          , trcExternalActionNeed = fmap eadtNeedTagText (taExternalActionDecisionTrace ta)
          , trcPreActorFailureEvent = derivePreActorFailureEvent ta
          , trcSenseAnchor = unSemanticNodeId (svAnchor (rspInputVector (rmpSensePlan (tpRmpAfterLegit tp))))
          , trcSenseOperator = Just (rspChosenOperator (rmpSensePlan (tpRmpAfterLegit tp)))
          , trcSensePreservedAxes = rspPreservedAxes (rmpSensePlan (tpRmpAfterLegit tp))
          , trcDialogueFocus = dtCurrentFocus (tiDialogueThread ti)
          , trcDialogueFocusBefore = dtCurrentFocus (tiDialogueThread ti)
          , trcDialogueFocusAfter = dtCurrentFocus (ssDialogueThread nextSs)
          , trcDialoguePhase = tiDialoguePhase ti
          , trcDialoguePhaseBefore = tiDialoguePhase ti
          , trcDialoguePhaseAfter = ssDialoguePhase nextSs
          , trcDialogueCommitmentCount = length (dclItems (tiDialogueCommitmentLedger ti))
          , trcDialogueCommitmentCountBefore = length (dclItems (tiDialogueCommitmentLedger ti))
          , trcDialogueCommitmentCountAfter = length (dclItems (ssDialogueCommitmentLedger nextSs))
          , trcMicroPlanMoves = mpRhetoricalMoves (rmpMicroPlan (tpRmpAfterLegit tp))
          , trcMicroPlanExplicitness = mpExplicitness (rmpMicroPlan (tpRmpAfterLegit tp))
          , trcDreamPressureDatalogClass = Just (T.pack (show (dpClass (doDatalogPressure dreamOutcome))))
          , trcDreamPressureIntuitionClass = Just (T.pack (show (inpClass (doIntuitionPressure dreamOutcome))))
          , trcDreamPressureAgreement = Just (T.pack (show (drpAgreement (doDreamPressure dreamOutcome))))
          , trcDreamPressureStrength = Just (drpStrength (doDreamPressure dreamOutcome))
          , trcDreamPressureCandidateThresholdFired = Just (not (null (doCorrectionCandidates dreamOutcome)))
          , trcDreamPressureCandidateKinds = map dccKind (doCorrectionCandidates dreamOutcome)
          , trcDreamPressureBiasApplied = Just (vecNorm (doBias dreamOutcome) > 1e-9)
          , trcDreamCandidateLifecycleStatuses = map renderDreamCandidateDecisionStatus (doCandidateDecisions dreamOutcome)
          , trcDreamCandidateDecisionReasons = map renderDreamCandidateDecisionReasonText (doCandidateDecisions dreamOutcome)
          , trcDreamCandidateApplied = Just (vecNorm (doAppliedBias dreamOutcome) > 1e-9)
          , trcPerspectiveProjection =
              case perspectiveProjections of
                projection:_ -> Just projection
                [] -> Nothing
          , trcPerspectiveProjections = perspectiveProjections
          , trcConatusEnergy = tiConatusEnergy ti
          , trcConatusGateFired = tiConatusGateFired ti
          , trcField = tiField ti
          , trcIdentityClaims = ssIdentityClaims nextSs
          , trcEpisodicEncoding = case ssEpisodic nextSs of
              Just store -> map eeId (foldr (:) [] (Seq.reverse (Seq.take 2 (esEvents store))))
              Nothing    -> []
          , trcEpisodicRetrieval =
              if episodicRecallActive
                then recallForTrace (ssEpisodic nextSs)
                else Nothing
          , trcEpisodicForgetting = (0, Nothing)
          , trcRegimeVersion = rrMathVersion defaultRuntimeRegime
          , trcFamilyDivergenceActive = rrFamilyDivergenceActive defaultRuntimeRegime
           , trcSemanticCommitmentCount = case ssSemanticCommitments nextSs of
               Nothing    -> 0
               Just store -> HashMap.size (scsActive store)
            , trcQuarantinedCommitmentCount = case ssSemanticCommitments nextSs of
                Nothing    -> 0
                Just store -> HashMap.size (scsQuarantine store)
            , trcPromotedFromQuarantineCount = promotedCount
           , trcCommitmentStoreDecision = commitDecision
           , trcCommitmentEngaged = length (ceEngaged commitmentEngagement)
           , trcCommitmentContradicted = ceContradicted commitmentEngagement
           , trcCommitmentFamilyHint = commitmentFamilyHint (tpCommitmentEngagement tp)
           , trcCognitiveSignals = buildCognitiveSignals ti tp nextSs
          , trcDoubtScore = doubtScore
          , trcEpisodicRetrievalCount = episodicRetrievalCount
          , trcContentSaliencyDominantCluster = contentSaliencyDominantCluster
          , trcMoodValence = moodValence
          , trcMoodArousal = moodArousal
          , trcAffectDecoupled = affectDecoupled
          , trcMood = persistentMood
          , trcUserModelTopIntent = userModelTopIntent
          , trcUserModelConfidence = userModelConfidence
          , trcDerivedInferenceCount = derivedInferenceCount
          , trcFamilyDivergenceOccurred = familyDivergenceOccurred
          , trcFmarDetectorFamily = mdDetectorFamily <$> tpFmarDirective tp
          , trcFmarFamily = mdFamily <$> tpFmarDirective tp
          , trcFmarFamiliesMatch =
              (\d -> mdDetectorFamily d == mdFamily d) <$> tpFmarDirective tp
          , trcFmarFieldDistance = mdFieldDistance <$> tpFmarDirective tp
          , trcFmarMode = case fmarMode of
              FmarOff -> Nothing
              _      -> Just fmarMode
          , trcFamilyDerivationChain = tpFamilyDerivationChain tp
          , trcGenerationTrace = taGenerationTrace ta
          -- R4: read the live turn regime, not the static default, so replay
          -- reflects the morphology path actually used this turn.
          -- (Note: 'trcRegimeVersion'/'trcFamilyDivergenceActive' above still
          -- read defaultRuntimeRegime — same latent issue, left for a separate
          -- pass to avoid changing math-version semantics here.)
          , trcMorphologyVersion = if rrRglMorphologyActive (ssCurrentRegime nextSs) then 1 else 0
          , trcEffectSnapshot = Just EffectSnapshot
              { esApiHealthy = tsApiHealthy ts
              }
           }
  in TurnProjection
      { tqpTurn = ssTurnCount nextSs
      , tqpParserMode = ParserFrameV1
      , tqpParserConfidence = parserConfidence
      , tqpParserErrors = parserErrors
      , tqpPlannerMode = case tpPrincipledModePair tp of Just _ -> PrincipledPlanner; Nothing -> DefaultPlanner
      , tqpPlannerDecision = executedFamily
      , tqpAtomRegister = asRegister (tiAtomSet ti)
      , tqpAtomLoad = asLoad (tiAtomSet ti)
      , tqpScenePressure = scenePressure
      , tqpSceneRequest = tiBestTopic ti
      , tqpSceneStance = usNeedLayer (tiNextUserState ti)
      , tqpRenderLane = rsMove (tdRenderStrategy decision)
      , tqpRenderStyle = tdRenderStyle decision
      , tqpLegitimacyStatus = legitimacyStatus
      , tqpLegitimacyReason = legitimacyReason
      , tqpWarrantedMode = warrantedMode
      , tqpDecisionDisposition = loDisposition legitimacyOutcome
      , tqpOwnerFamily = ownerFamily
      , tqpOwnerForce = ownerForce
      , tqpShadowStatus = tpShadowStatus tp
      , tqpShadowSnapshotId = tpShadowSnapshotId tp
      , tqpShadowDivergenceKind = tpShadowDivergenceKind tp
      , tqpShadowFamily = tpShadowFamily tp
      , tqpShadowForce = tpShadowForce tp
      , tqpShadowMessage = tpShadowMessage tp
      , tqpReplayTrace = replayTrace
      , tqpDivergence = tpShadowDivergence tp
      }

data LearningReplayVerdict = LearningReplayVerdict
  { lrvStatus :: !Text
  , lrvSandboxResult :: !(Maybe Text)
  , lrvGraftTurn :: !(Maybe Int)
  , lrvRejectReason :: !(Maybe Text)
  }

derivePreActorFailureEvent :: TurnArtifacts -> Maybe PreActorFailureEvent
derivePreActorFailureEvent ta =
  case requestOrExploratoryAttempt of
    Just (actionKind, Left err) ->
      Just PreActorFailureEvent
        { pafeKind =
            case err of
              EqeFallback _ -> PreActorFallbackNonAuthoritative
              _ -> PreActorTransportFailure
        , pafeActionKind = renderExternalActionKind actionKind
        , pafeReason = renderExternalQueryError err
        }
    Just (_, Right _) -> Nothing
    Nothing ->
      case taExternalActionDecisionTrace ta of
        Just trace | eadtReason trace == DeniedNoExecutableTool ->
          Just PreActorFailureEvent
            { pafeKind = PreActorNoExecutableTool
            , pafeActionKind = renderExternalActionKind (eadtKind trace)
            , pafeReason = renderExternalActionDecisionReason (eadtReason trace)
            }
        _ -> Nothing
  where
    requestOrExploratoryAttempt =
      fmap (\res -> (RequestDrivenExternalAction, res)) (taExternalQueryResult ta)
        <|> fmap (\res -> (ExploratoryExternalAction, res)) (taExploratoryQueryResult ta)

deriveLearningReplayVerdict :: SystemState -> TurnArtifacts -> LearningReplayVerdict
deriveLearningReplayVerdict nextSs ta =
  case firstAttempt of
    Nothing -> LearningReplayVerdict "not_attempted" Nothing Nothing Nothing
    Just (Left err) ->
      LearningReplayVerdict
        { lrvStatus = case err of
            EqeFallback _ -> "fallback_non_authoritative"
            _ -> "transport_error"
        , lrvSandboxResult = Nothing
        , lrvGraftTurn = Nothing
        , lrvRejectReason = Just (renderExternalQueryError err)
        }
    Just (Right _) ->
      case () of
        _ | not authoritativeTurn -> LearningReplayVerdict "observed_non_authoritative" (firstCauseEvidence "sandbox_accept") Nothing (Just "truth_contract_ceiling_non_authoritative")
          | any isGraft currentTurnRecords -> LearningReplayVerdict "accept" (firstCauseEvidence "sandbox_accept") (Just currentTurn) Nothing
          | any isSandboxReject currentTurnRecords -> LearningReplayVerdict "sandbox_reject" (firstMutationEvidence "external_learning:sandbox_reject") Nothing (firstMutationEvidence "external_learning:sandbox_reject")
          | any isValidationReject currentTurnRecords -> LearningReplayVerdict "validation_reject" Nothing Nothing (firstMutationEvidence "external_learning:validation_reject")
          | any isParserReject currentTurnRecords -> LearningReplayVerdict "invalid_response" Nothing Nothing (Just "parser_rejected_schema_or_text")
          | otherwise -> LearningReplayVerdict "observed_non_authoritative" Nothing Nothing (Just "learning_outcome_unresolved")
  where
    authoritativeTurn = truthContractIsAuthoritative (taTruthContractStatus ta)
    currentTurn = ssTurnCount nextSs
    currentTurnRecords = filter ((== currentTurn) . amrTurnId) (ssAdaptiveMutationLog nextSs)
    firstAttempt = taExternalQueryResult ta <|> taExploratoryQueryResult ta
    isGraft record = amrCause record == "external_learning:graft" && amrDecision record == AdaptiveAccepted
    isSandboxReject record = amrCause record == "external_learning:sandbox_reject"
    isValidationReject record = amrCause record == "external_learning:validation_reject"
    isParserReject record = amrCause record == "tool_reliability:rejected" && any (== "reason=parser_rejected_schema_or_text") (amrEvidence record)
    firstMutationEvidence cause =
      case [ evidence | record <- currentTurnRecords, amrCause record == cause, evidence:_ <- [amrEvidence record] ] of
        value:_ -> Just value
        [] -> Nothing
    firstCauseEvidence reason =
      case [ evidence | record <- currentTurnRecords, any (== ("reason=" <> reason)) (amrEvidence record), evidence:_ <- [amrEvidence record] ] of
        value:_ -> Just value
        [] -> Nothing

renderDreamCandidateDecisionStatus :: DreamCandidateDecision -> Text
renderDreamCandidateDecisionStatus decision =
  case decision of
    DreamCandidateAccepted _ -> "accepted"
    DreamCandidateRejected _ -> "rejected"
    DreamCandidateQuarantined _ -> "quarantined"

renderDreamCandidateDecisionReason :: DreamCandidateDecisionReason -> Text
renderDreamCandidateDecisionReason reason =
  case reason of
    DCDRNoPressure -> "no_pressure"
    DCDRUnavailableOnly -> "unavailable_only"
    DCDRAdvisoryMismatchOnly -> "advisory_mismatch_only"
    DCDRAlternativeFamilyPressure -> "alternative_family_pressure"
    DCDRConflictAgreement -> "conflict_agreement"
    DCDRSymbolicOnlyAgreement -> "symbolic_only_agreement"
    DCDRAffectiveOnlyAgreement -> "affective_only_agreement"
    DCDRNoneCandidateObservedOnly -> "none_candidate_observed_only"
    DCDRSymbolicCandidateObservedOnly -> "symbolic_candidate_observed_only"
    DCDRAffectiveCandidateObservedOnly -> "affective_candidate_observed_only"
    DCDRConflictCandidateObservedOnly -> "conflict_candidate_observed_only"
    DCDRUnsupportedCandidateKind -> "unsupported_candidate_kind"
    DCDRAcceptedSafetyGraphBias -> "accepted_safety_graph_bias"
    DCDRAcceptedContractGraphBias -> "accepted_contract_graph_bias"
    DCDRAcceptedGateEscalationGraphBias -> "accepted_gate_escalation_graph_bias"
    DCDRThresholdNotReached -> "threshold_not_reached"

renderDreamCandidateDecisionReasonText :: DreamCandidateDecision -> Text
renderDreamCandidateDecisionReasonText decision =
  case decision of
    DreamCandidateAccepted accepted -> renderDreamCandidateDecisionReason (adcReason accepted)
    DreamCandidateRejected rejected -> renderDreamCandidateDecisionReason (rdcReason rejected)
    DreamCandidateQuarantined quarantined -> renderDreamCandidateDecisionReason (qdcReason quarantined)

renderExternalActionDecisionReason :: ExternalActionDecisionReason -> Text
renderExternalActionDecisionReason reason =
  case reason of
    AllowedRequestDriven -> "allowed_request_driven"
    AllowedExploratory -> "allowed_exploratory"
    DeniedGuardrailRateLimit -> "guardrail_rate_limit"
    DeniedGuardrailCircuitBreaker -> "guardrail_circuit_breaker"
    DeniedNoEligibleNeed -> "no_eligible_need"
    DeniedNoExecutableTool -> "no_executable_tool"
    DeniedNoActionSelected -> "no_action_selected"

renderExternalActionKind :: ExternalActionKind -> Text
renderExternalActionKind actionKind =
  case actionKind of
    RequestDrivenExternalAction -> "request_driven"
    ExploratoryExternalAction -> "exploratory"

eadtNeedTagText :: ExternalActionDecisionTrace -> Text
eadtNeedTagText trace = maybe "none" id (eadtNeedTag trace)
