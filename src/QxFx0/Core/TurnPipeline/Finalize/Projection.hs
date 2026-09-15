{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : observer — Finalize-stage turn replay trace projection and serialization. -}

module QxFx0.Core.TurnPipeline.Finalize.Projection
  ( buildTurnProjection
  , turnInputSalience
  , activatedConcepts
  , missingPredicateConcepts
  ) where

import Control.Applicative ((<|>))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision)
import QxFx0.Core.TurnRouting.Cascade (commitmentFamilyHint)
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Core.TopicDrift.Pressure (buildDreamOutcome)
import QxFx0.Core.Observability
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Self.SelfDivergence (windowMeanDivergence)
import QxFx0.Types.Self.SelfDivergence (SelfDivergenceE(..))
import QxFx0.Core.TruthContract
  ( normalizedReplayProvenanceStatus
  , replayProvenanceStatusForOutcome
  , truthContractIsAuthoritative
  )
import QxFx0.Types.Evidence (EvidenceAdmissibility)
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Learning.Guardrails (ExternalActionDecisionReason(..), ExternalActionDecisionTrace(..), ExternalActionKind(..))
import QxFx0.Semantic.Content (DefinitionContent(..))
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
import QxFx0.Types.RuntimeRegime (rrFamilyDivergenceActive, rrMathVersion, rrRglMorphologyActive)
import QxFx0.Types.State.SemanticCommitment (CommitmentEngagement(..), scsActive, scsQuarantine)
import QxFx0.Semantic.Network.Types (ActivationArtifact(..), ActivationStep(..), EdgeSource(..))
import QxFx0.Safety.CrisisGuard (crisisResourceVersion)
import QxFx0.Types.Safety.Crisis
  ( CrisisCause(..)
  , CrisisGuardTrace(..)
  , ProtocolVerdict(..)
  , crisisCauseCategory
  , crisisCauseTag
  , crisisCategoryTag
  , protocolBCause
  )
import QxFx0.Types.User.R5
  ( UserR5State(..)
  , UserR5Trace(..)
  , defaultUserConatusWeights
  , r5EncoderVersion
  , r5ResidualWindowMean
  , u5Baseline
  , u5DivergenceWindow
  , userConatusScore
  )
import QxFx0.Types.Semantic.MoveGraph
  ( OntologicalMovePlan(..)
  , OntologicalMoveTrace(..)
  , ontologicalMoveTag
  )
import qualified Data.Sequence as Seq
import qualified Data.Foldable as F
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
import QxFx0.Types.RuntimeMode (RuntimeMode(..))

turnInputSalience :: TurnInput -> Salience
turnInputSalience = svSalience . tiSelfVerdict

-- | P0.2: concepts whose activation value exceeded the reporting threshold.
-- Source of truth is the activation artifact consumed by selection.
activatedConcepts :: Maybe ActivationArtifact -> [Text]
activatedConcepts Nothing = []
activatedConcepts (Just artifact) =
  M.keys (M.filter (>= 0.05) (aaActivation artifact))

-- | P0.2: subset of activated concepts that have no surface predicate in the
-- definition corpus.  Drives the GAPS.md curation backlog.
missingPredicateConcepts :: M.Map Text DefinitionContent -> Maybe ActivationArtifact -> [Text]
missingPredicateConcepts corpus mNet =
  filter (not . (`M.member` corpus)) (activatedConcepts mNet)

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
  :: RuntimeMode
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
  -> EvidenceAdmissibility
  -> TurnProjection
buildTurnProjection runtimeMode shadowPolicy localRecoveryPolicy semanticIntrospectionEnabled warnMorphologyFallbackEnabled fmarMode nextSs ti ts tp ta commitDecision promotedCount commitmentEngagement evidenceAdmissibility =
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
        | tiFrame ti == parseProposition (ipfRawText (tiFrame ti)) = PsOk
        | parserAdmissionAdjusted = PsConstitutionAdmitted
        | otherwise = PsDegraded "frame_runtime_mismatch"
      parserDegradationReason =
        case parserStatus of
          PsOk -> Nothing
          PsConstitutionAdmitted -> Just "constitution_interpretation_admission"
          PsDegraded _ -> Just "frame_runtime_mismatch"
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
            | DegradedRuntime <- runtimeMode ->
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
      -- Read the live session regime, not the static default, so replay
      -- reflects the regime actually governing this turn (restored sessions
      -- may carry a different persisted regime).
      liveRegime = ssCurrentRegime nextSs
      familyDivergenceOccurred = if rrFamilyDivergenceActive liveRegime
                                   then Just (tpPreShadowFamily tp /= tpFamily tp)
                                   else Nothing
      -- Concept v3 §2: protocol projection for the crisis trace.
      mProtocolCause = protocolBCause (tiUserProtocol ti)
      protocolBFired = case tiUserProtocol ti of
        ProtocolB _ -> True
        ProtocolA  -> False
      outsideFromProtocol = case mProtocolCause of
        Just (CrisisContourExit _) -> True
        _                          -> False
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
      overlayPredicateIds =
        case ssCuratedOverlay nextSs of
          Nothing -> []
          Just overlay ->
            [ predicateId
            | surface <- taEmittedPredicates ta
            , Just predicateId <- [M.lookup (T.toLower (T.strip surface)) (corPredicateIdsBySurface overlay)]
            ]
      activationArtifact = taActivationArtifact ta
      activationSteps = maybe Seq.empty aaSteps activationArtifact
      substrateSteps = filter ((== SubstrateEdge) . asSource) (F.toList activationSteps)
      substrateActivated = S.toList (S.fromList (map asNode substrateSteps))
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
          , trcEssenceResetEvent = selfLastEssenceResetEvent (ssSelfState nextSs)
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
          , trcDreamPressureCandidateKinds = map (T.pack . show . dccKind) (doCorrectionCandidates dreamOutcome)
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
          , trcSelfDivergenceTotal =
              sdeTotalDivergence <$> selfLastDivergence (ssSelfState nextSs)
          , trcSelfDivergencePenalty = tiSelfDivergencePenalty ti
          , trcSelfDivergenceWindowMean =
              let w = selfDivergenceWindow (ssSelfState nextSs)
              in if null w then Nothing else Just (windowMeanDivergence w)
          , trcSelfDivergencePredictionActive = maybe False (const True) (tiSelfPrediction ti)
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
          , trcRegimeVersion = rrMathVersion liveRegime
          , trcFamilyDivergenceActive = rrFamilyDivergenceActive liveRegime
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
           , trcCommitmentMatchKind = ceMatchKind commitmentEngagement
           , trcCommitmentFamilyHint = commitmentFamilyHint commitmentEngagement
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
          , trcMorphologyVersion = if rrRglMorphologyActive (ssCurrentRegime nextSs) then 1 else 0
          , trcEffectSnapshot = Just EffectSnapshot
              { esApiHealthy = tsApiHealthy ts
              }
          , trcEvidenceAdmissibility = evidenceAdmissibility
          , trcIntentType = extractIntentTag (taDerivationTags ta)
          , trcFrameType = extractFrameTag (taDerivationTags ta)
          , trcContentSource = extractContentSourceTag (taDerivationTags ta)
          , trcAnalogicalSource = extractAnalogicalSourceTag (taDerivationTags ta)
          , trcSubstrateActivated = substrateActivated
          , trcSubstrateEdgesUsed = length substrateSteps
          , trcActivationSteps = activationSteps
          -- Hops = the deepest substrate hop reached in the activation
          -- walk (0 = seeds only), NOT the traversal count — that is
          -- trcSubstrateEdgesUsed.  Previously both fields carried the
          -- same number (audit P1-3 duplicate).
          , trcSubstrateHops =
              if null substrateSteps then 0 else maximum (map asHop substrateSteps)
          , trcActivatedConcepts = activatedConcepts activationArtifact
          , trcMissingPredicates = missingPredicateConcepts (ssDefinitionCorpus nextSs) activationArtifact
          , trcEmittedPredicates = taEmittedPredicates ta
          , trcCuratedOverlayVersion = corVersion <$> ssCuratedOverlay nextSs
          , trcOverlayPredicateIds = overlayPredicateIds
          , trcOverlayContentUsed = not (null overlayPredicateIds)
           , trcSelectorDiagnostics = taSelectorDiagnostics ta
           , trcResponsePlan = taResponsePlan ta
           , trcUserRegime = Just UserRegimeTrace
               { urtCrisis = CrisisGuardTrace
                   { cgtProtocolB = protocolBFired
                   , cgtCause = crisisCauseTag <$> mProtocolCause
                   , cgtCategory = crisisCategoryTag <$> (mProtocolCause >>= crisisCauseCategory)
                   , cgtResourceVersion = if protocolBFired then crisisResourceVersion else 0
                   }
               , urtUserR5 = UserR5Trace
                   { ur5Resonance = r5Resonance (tiUserR5 ti)
                   , ur5Atmosphere = r5Atmosphere (tiUserR5 ti)
                   , ur5Confidence = r5Confidence (tiUserR5 ti)
                   , ur5Consolidation = r5Consolidation (tiUserR5 ti)
                   , ur5Counterfactual = r5Counterfactual (tiUserR5 ti)
                   , ur5ConatusScore = userConatusScore defaultUserConatusWeights (tiUserR5 ti)
                   , ur5Baseline = u5Baseline (ssUserR5Contour nextSs)
                   , ur5OutsideContour = outsideFromProtocol
                   , ur5PredictionError = tiUserPredictionError ti
                   , ur5WindowMean =
                       r5ResidualWindowMean (u5DivergenceWindow (ssUserR5Contour nextSs))
                   }
               , urtOntologicalVector = tiOntologicalVector ti
               -- Audit 2026-09-15: the move never renders under
               -- Protocol B (the crisis surface overrides every other
               -- surface), so the trace must not claim one fired.
               -- 'Nothing' here means "no move led this turn".
               , urtOntologicalMove =
                   if protocolBFired then Nothing else
                     OntologicalMoveTrace
                       <$> (ontologicalMoveTag . ompMove <$> tpOntologicalMove tp)
                       <*> (ompDistanceBefore <$> tpOntologicalMove tp)
                       <*> (ompDistanceAfter <$> tpOntologicalMove tp)
                       <*> (ompAffirmGatePassed <$> tpOntologicalMove tp)
               , urtEncoderVersion = r5EncoderVersion
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

-- | Extract intent type from derivation tags (M4-SEMANTIC-CORE-003).
-- Tags are formatted as "intent=IntentDefine ..." — extract the intent constructor name.
extractIntentTag :: [Text] -> Maybe Text
extractIntentTag tags =
  case filter (T.isPrefixOf "intent=") tags of
    (tag:_) -> Just (T.drop 8 tag)
    []      -> Nothing

-- | Extract frame type from derivation tags (M4-SEMANTIC-CORE-003).
-- Tags are formatted as "frame=definition" — extract the frame type name.
extractFrameTag :: [Text] -> Maybe Text
extractFrameTag tags =
  case filter (T.isPrefixOf "frame=") tags of
    (tag:_) -> Just (T.drop 6 tag)
    []      -> Nothing

-- | Extract content source from derivation tags (M4-SEMANTIC-CORE-003 Phase C).
-- Tags are formatted as "content_source=covered_exact" etc.
extractContentSourceTag :: [Text] -> Maybe Text
extractContentSourceTag tags =
  case filter (T.isPrefixOf "content_source=") tags of
    (tag:_) -> Just (T.drop 15 tag)
    []      -> Nothing

-- | Extract analogical source topic from derivation tags.
-- Tags are formatted as "analogical_source=TOPIC".
extractAnalogicalSourceTag :: [Text] -> Maybe Text
extractAnalogicalSourceTag tags =
  case filter (T.isPrefixOf "analogical_source=") tags of
    (tag:_) -> Just (T.drop 18 tag)
    []      -> Nothing
