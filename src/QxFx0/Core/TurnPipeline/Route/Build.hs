{-# LANGUAGE OverloadedStrings #-}

{-|
Description : observer — Route-plan assembly and render handoff after effect resolution. -}
module QxFx0.Core.TurnPipeline.Route.Build
  ( buildRouteTurnPlan
  , readFmarModeIO
  ) where

import QxFx0.Core.Intuition (flashThreshold)
import QxFx0.Core.TruthContract (capByTruthContract, capCommitmentStrengthByTruthContract)
import QxFx0.Core.Observability (recordThresholdProbe)
import QxFx0.Core.Legitimacy (legitimacyRecoveryBonus)
import QxFx0.Core.SensePlan (familySenseBundle)
import QxFx0.Core.ResponseContentAdmission
  ( ResponseContentAdmissionInput(..)
  , ResponseContentAdmissionDecision(..)
  , AdmittedResponseContent(..)
  , admitResponseContent
  )
import QxFx0.Core.FMAR
  ( FmarMode (..)
  , computeAdaptivePosition
  , fmarSelectFamily
  , isFmarActive
  , readFmarMode
  )
import QxFx0.Self.FamilyTargets (FamilyTarget(..), familyTargetFor, familyTargets, fieldDistance)
import QxFx0.Self.Field
  ( Atmosphere(..)
  , Field(..)
  , FieldConfidence(..)
  , Consolidation(..)
  , Counterfactual(..)
  , Resonance(..)
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  )
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , ShadowPolicy
  , pipelineLocalRecoveryPolicy
  , pipelineRuntimeMode
  , pipelineShadowPolicy
  , resolveTurnEffect
  )
import QxFx0.Core.TurnPipeline.Effects (TurnEffectRequest(..), TurnEffectResult(..))
import QxFx0.Core.TurnPlanning (buildRCP, buildRMPWithTruthContract)
import QxFx0.Core.TurnRender (applyRenderStrategyWithTruthContract)
import QxFx0.Core.TurnPipeline.Route.Effects
  ( planRouteEffects
  , resolveRouteEffects
  )
import QxFx0.Core.TurnPipeline.Route.Render
  ( buildTurnArtifacts
  , planRenderEffectsForRuntime
  , resolveRenderEffects
  )
import QxFx0.Core.TurnPipeline.Route.Shadow
  ( ShadowContext(..)
  , ShadowResolution(..)
  , computeShadowContext
  , resolveShadowFamily
  )
import QxFx0.Core.TurnPipeline.Route.Types
  ( RouteEffectPlan(..)
  , RouteEffectResults(..)
  , RouteStatic(..)
  )
import QxFx0.Core.TurnPipeline.Types
  ( RoutingDecision(..)
  , TurnArtifacts
  , TurnInput(..)
  , TurnPlan(..)
  , TurnSignals(..)
  )
import QxFx0.Learning.DialogueDevelopment (adjustRenderStyleForSpeechPolicy)
import QxFx0.Core.TurnPolicy
import QxFx0.Semantic.SemanticScene (defaultScenes, inferActiveScene)
import QxFx0.Semantic.Proposition (diagnosticPropositionFamily, diagnosticPropositionFamilyTyped)
import QxFx0.Semantic.Retrieve (detectCommitmentEngagement)
import QxFx0.Types
import QxFx0.Types.State.SemanticCommitment (CommitmentEngagement(..), MatchKind(..))
import QxFx0.Types.ShadowDivergence (ShadowVetoState(..))
import QxFx0.Types.Thresholds
  ( agdaVerificationPenalty
  , legitimacyRecoveryThreshold
  , legitimacyPassThreshold
  , parserLowConfidenceThreshold
  )
import QxFx0.Types.Anomaly (Anomaly(..), AnomalySurface(..), AnomalyTrace(..))
import Data.Text (Text)
import qualified Data.Text as T

buildRouteTurnPlan :: FmarMode -> ShadowPolicy -> Maybe Anomaly -> Bool -> SystemState -> TurnInput -> TurnSignals -> RouteEffectPlan -> RouteEffectResults -> TurnPlan
buildRouteTurnPlan fmarMode shadowPolicy mAnomaly semanticFirstDisabled ss ti ts effectPlan effectResults =
  let atomSet = tiAtomSet ti
      intuitPosterior = tsIntuitPosterior ts
      rd = rsRoutingDecision (repStatic effectPlan)
      sc =
        computeShadowContext
          (rerShadowResult effectResults)
          (tiFrame ti)
          (tiNewTrace ti)
          intuitPosterior
          (tiEmbeddingQuality ti)
          (tiEmbSimilarity ti)
          (tsApiHealthy ts)
      shadowResolution0 = resolveShadowFamily shadowPolicy (rdFamily rd) sc
      -- WP2 (GAP2): bounded shadow-veto anti-loop.
      -- If the shadow gate has triggered more than 'maxVetosPerWindow'
      -- times within 'vetoWindowTurns', bypass the veto to prevent
      -- infinite oscillation and emit exhaustion telemetry.
      maxVetosPerWindow = 3
      vetoWindowTurns = 10
      currentTurn = ssTurnCount ss
      oldVetoState = ssShadowVetoState ss
      windowExpired = currentTurn - svsWindowStart oldVetoState > vetoWindowTurns
      (vetoCount, windowStart) =
        if windowExpired
          then (0, currentTurn)
          else (svsCount oldVetoState, svsWindowStart oldVetoState)
      (shadowResolution, vetoExhausted, newVetoCount, newWindowStart) =
        if srGateTriggered shadowResolution0
          then if vetoCount >= maxVetosPerWindow
                 then (shadowResolution0 { srGateTriggered = False }, True, vetoCount, windowStart)
                 else (shadowResolution0, False, vetoCount + 1, windowStart)
          else (shadowResolution0, False, vetoCount, windowStart)
      family0 = if hasChallengeMarker (ipfRawText (tiFrame ti))
        then CMConfront
        else srEffectiveFamily shadowResolution
      (family, _, _) = familySenseBundle family0 (tiDialogueCommitmentLedger ti) (tiDialoguePhase ti) (tiDialogueThread ti) (tiSenseVector ti) (tiDoubtScore ti)
      recoveryBonus =
        legitimacyRecoveryBonus
          (scShadowStatus sc == ShadowMatch && not (scShadowHasDivergence sc))
          (rdStrategyFamily rd == Just family)
      newEgo = rdNewEgo rd
      renderStrategy = rdRenderStrategy rd
      renderStyle = adjustRenderStyleForSpeechPolicy (ssSpeechPolicyState ss) (rdRenderStyle rd)
      preRenderTruthStatus = derivePreRenderTruthContractStatus ti sc shadowResolution family
      rmpBase = buildRMPWithTruthContract preRenderTruthStatus family (tiDialogueCommitmentLedger ti) (tiDialoguePhase ti) (tiDialogueThread ti) (tiFrame ti) (tiSenseVector ti) (tiBestTopic ti) newEgo (tiNewTrace ti) (tiNixAvailable ti) (tiDoubtScore ti)
      rmp0 = applyRenderStrategyWithTruthContract preRenderTruthStatus family renderStrategy rmpBase
      rcp0 = (buildRCP family rmp0) {rcpStyle = renderStyle}
      rmp1 = modulateRMPWithNarrative (tsNarrativeFragment ts) rmp0
      rcp1 =
        case tsFlash ts of
          Just flash -> modulateRCPWithFlash (ifOverridesAll flash) rcp0
          Nothing -> rcp0
      agdaStatus = rerAgdaStatus effectResults
      agdaOk = agdaVerificationReady agdaStatus
      legitPreAgda = min 1.0 (scAdjustedBaseLegit sc + recoveryBonus)
      legitInput =
        if agdaOk
          then legitPreAgda
          else max 0.0 (legitPreAgda - agdaVerificationPenalty)
      (legitScore, rmpAfterLegit0, rcpFinal0, finalFamily0, _finalForce0) =
        applyLegitimacyToPlans legitInput family rmp1 rcp1 renderStyle
      lockedDiagnosticFamily =
        case diagnosticPropositionFamilyTyped (ipfPropositionType (tiFrame ti)) of
          Just diagnosticFamily
            | not (srGateTriggered shadowResolution)
                && finalFamily0 /= CMRepair ->
                Just diagnosticFamily
          _ ->
            Nothing
      finalFamily = maybe finalFamily0 id lockedDiagnosticFamily
      (cascadeFamily, cascadeSensePlan, cascadeMicroPlan) = familySenseBundle finalFamily (tiDialogueCommitmentLedger ti) (tiDialoguePhase ti) (tiDialogueThread ti) (tiSenseVector ti) (tiDoubtScore ti)

      -- FMAR Phase-4+7: override cascade family when Field-driven routing is active.
      fmarActive = isFmarActive fmarMode
      fmarPos = computeAdaptivePosition (tiField ti) (rdToMs rd) (tiConatusEnergy ti)
      fmarFamily
        | fmarActive = fmarSelectFamily fmarPos (tiRecommendedFamily ti) familyTargets
        | otherwise  = cascadeFamily  -- unused when inactive, kept for totality
      renderingFamily = case fmarMode of
        FmarLive -> fmarFamily
        _        -> cascadeFamily
      renderingForce = forceForFamily renderingFamily
      familyDerivationChain =
        [ TurnFamilyDerivationStep "routing" (rdFamily rd)
        , TurnFamilyDerivationStep "shadow" (srEffectiveFamily shadowResolution)
        , TurnFamilyDerivationStep "sense_bundle" family
        , TurnFamilyDerivationStep "legitimacy" finalFamily0
        ]
        <> maybe [] (\df -> [TurnFamilyDerivationStep "diagnostic_lock" df]) lockedDiagnosticFamily
        <> [ TurnFamilyDerivationStep "post_diagnostic" finalFamily
           , TurnFamilyDerivationStep "cascade" cascadeFamily
           ]
        <> [ TurnFamilyDerivationStep "fmar" fmarFamily | fmarActive ]
        <> [ TurnFamilyDerivationStep "rendering" renderingFamily
           ]
      (_, renderingSensePlan, renderingMicroPlan) = case fmarMode of
        FmarLive -> familySenseBundle renderingFamily (tiDialogueCommitmentLedger ti) (tiDialoguePhase ti) (tiDialogueThread ti) (tiSenseVector ti) (tiDoubtScore ti)
        _        -> (cascadeFamily, cascadeSensePlan, cascadeMicroPlan)

      postLegitTruthStatus = derivePostLegitTruthContractStatus preRenderTruthStatus ti sc shadowResolution legitScore renderingFamily
      rmpAfterLegit =
        rmpAfterLegit0
          { rmpFamily = renderingFamily
          , rmpForce = renderingForce
          , rmpSpeechAct = familyToSpeechAct renderingFamily
          , rmpRelation = familyToRelation renderingFamily
          , rmpEpistemic = capByTruthContract postLegitTruthStatus (rmpEpistemic rmpAfterLegit0)
          , rmpTruthContractStatus = postLegitTruthStatus
          , rmpCommitmentStrength = capCommitmentStrengthByTruthContract postLegitTruthStatus (rmpCommitmentStrength rmpAfterLegit0)
          , rmpSensePlan = renderingSensePlan
          , rmpMicroPlan = renderingMicroPlan
          }
      rcpFinal =
        if renderingFamily == finalFamily0
          then rcpFinal0
          else (buildRCP renderingFamily rmpAfterLegit) {rcpStyle = rcpStyle rcpFinal0}

      -- CTS-41: constitution-aware response content admission
      admissionInput = ResponseContentAdmissionInput
        { rcaiTruthContractStatus      = postLegitTruthStatus
        , rcaiShadowDivergenceSeverity = scShadowDivergenceSeverity sc
        , rcaiLegitScore               = legitScore
        }
      AdmittedResponseContent arcDecision arcRmp arcRcp =
        admitResponseContent admissionInput rmpAfterLegit rcpFinal

      -- FMAR directive for trace (shadow or live)
      fmarDirective
        | fmarActive = Just (MeaningDirective
            { mdFamily            = fmarFamily
            , mdDetectorFamily    = cascadeFamily
            , mdFieldDelta        = fieldDelta (ftTargetField (familyTargetFor fmarFamily)) (tiField ti)
            , mdForce             = forceForFamily fmarFamily
            , mdClause            = clauseFormForIF (forceForFamily fmarFamily)
            , mdLayer             = layerForFamily fmarFamily
            , mdWarranted         = warrantedForFamily fmarFamily
            , mdConatusGateOk     = not (tiConatusGateFired ti)
            , mdRescueUsed        = tiConatusGateFired ti
            , mdFieldDistance     = fieldDistance fmarPos (ftTargetField (familyTargetFor fmarFamily))
            , mdAbstractionBudget = 0
            , mdMaxWordsHint      = 0
            })
        | otherwise = Nothing

      activeScene = inferActiveScene (tiNewTrace ti) (map maTag (asAtoms atomSet)) (ssActiveScene ss) defaultScenes
      commitmentEngagement =
        case ssSemanticCommitments ss of
          Just store -> detectCommitmentEngagement store (tiBestTopic ti) atomSet
          Nothing    -> CommitmentEngagement [] False NoMatch
      metricsWithThresholds =
        recordThresholdProbe "shadow_gate" 1.0 (srGateTriggered shadowResolution)
          . recordThresholdProbe "legitimacy_pass" legitimacyPassThreshold
              (legitScore >= legitimacyPassThreshold)
          . recordThresholdProbe "parser_low_confidence" parserLowConfidenceThreshold
              (ipfConfidence (tiFrame ti) < parserLowConfidenceThreshold)
          . recordThresholdProbe "intuition_flash" flashThreshold
              (intuitPosterior >= flashThreshold)
          $ tiMetrics ti
    in TurnPlan
          { tpRouting = rd
          , tpFamily = family
          , tpRenderStyle = renderStyleText renderStyle
          , tpRmpAfterLegit = arcRmp
          , tpRcpFinal = arcRcp
          , tpFinalFamily = renderingFamily
          , tpFinalForce = renderingForce
          , tpLegitScore = legitScore
          , tpActiveScene = activeScene
          , tpShadowStatus = scShadowStatus sc
          , tpShadowDivergence = scShadowHasDivergence sc
          , tpShadowDivergenceKind = scShadowDivergenceKind sc
          , tpShadowDivergenceSeverity = scShadowDivergenceSeverity sc
           , tpShadowGateTriggered = srGateTriggered shadowResolution
           , tpShadowSnapshotId = scShadowSnapshotId sc
           , tpShadowFamily = scShadowFamily sc
           , tpShadowForce = scShadowForce sc
           , tpShadowMessage =
               if vetoExhausted
                 then scShadowMessage sc <> "|shadow_veto_exhausted"
                 else scShadowMessage sc
           , tpShadowVetoState = ShadowVetoState newVetoCount newWindowStart
           , tpMetrics = metricsWithThresholds
            , tpDeliberation = rdDeliberation rd
            , tpFmarDirective = fmarDirective
            , tpFamilyDerivationChain = familyDerivationChain
            , tpResponseAdmission = arcDecision
            , tpCommitmentEngagement = commitmentEngagement
            , tpAnomalySurface = fmap aSurface mAnomaly
            , tpAnomalyTrace = fmap aTrace mAnomaly
            , tpSemanticFirstDisabled = semanticFirstDisabled
            }

derivePreRenderTruthContractStatus :: TurnInput -> ShadowContext -> ShadowResolution -> CanonicalMoveFamily -> TruthContractStatus
derivePreRenderTruthContractStatus ti sc shadowResolution family
  | tiConatusGateFired ti = NonExpansiveRecoverySurface
  | srGateTriggered shadowResolution = NonExpansiveRecoverySurface
  | family == CMRepair = NonExpansiveRecoverySurface
  | scShadowStatus sc `elem` [ShadowDiverged, ShadowUnavailable] = ExplicitFallbackSurface
  | scShadowHasDivergence sc = ExplicitFallbackSurface
  | ipfConfidence (tiFrame ti) < parserLowConfidenceThreshold = ExplicitFallbackSurface
  | not (tiNixAvailable ti) = ExplicitFallbackSurface
  | otherwise = AssembledSurfacePreserved

derivePostLegitTruthContractStatus :: TruthContractStatus -> TurnInput -> ShadowContext -> ShadowResolution -> Double -> CanonicalMoveFamily -> TruthContractStatus
derivePostLegitTruthContractStatus preTruthStatus ti sc shadowResolution legitScore family
  | family == CMRepair = NonExpansiveRecoverySurface
  | srGateTriggered shadowResolution = NonExpansiveRecoverySurface
  | scShadowStatus sc `elem` [ShadowDiverged, ShadowUnavailable] = ExplicitFallbackSurface
  | scShadowHasDivergence sc = ExplicitFallbackSurface
  | ipfConfidence (tiFrame ti) < parserLowConfidenceThreshold = ExplicitFallbackSurface
  | legitScore < legitimacyRecoveryThreshold = NonExpansiveRecoverySurface
  | legitScore < legitimacyPassThreshold = ExplicitFallbackSurface
  | otherwise = preTruthStatus

routeTurnPlan :: PipelineIO -> SystemState -> TurnInput -> TurnSignals -> IO TurnPlan
routeTurnPlan pio ss ti ts = do
  let effectPlan = planRouteEffects ss ti ts
  effectResults <- resolveRouteEffects pio effectPlan
  fmarMode <- readFmarModeIO pio
  mSemanticDisable <- resolveTurnEffect pio (TurnReqReadEnv "QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST")
  let semanticFirstDisabled = case mSemanticDisable of
        TurnResReadEnv (Just "1") -> True
        _ -> False
  pure (buildRouteTurnPlan fmarMode (pipelineShadowPolicy pio) Nothing semanticFirstDisabled ss ti ts effectPlan effectResults)

-- | Read 'QXFX0_FMAR' once via the pipeline IO boundary and parse it into
-- an 'FmarMode'. Mirrors 'shouldUseGfRuntime' in the render stage.
readFmarModeIO :: PipelineIO -> IO FmarMode
readFmarModeIO pio = do
  result <- resolveTurnEffect pio (TurnReqReadEnv "QXFX0_FMAR")
  case result of
    TurnResReadEnv mraw -> pure (readFmarMode mraw)
    _                   -> pure FmarOff

-- | Component-wise @target − current@ over the five Field components,
-- clamped to each component's valid range by the smart constructors.
fieldDelta :: Field -> Field -> Field
fieldDelta target current =
  Field
    { fieldResonance      = mkResonance
        (unResonance (fieldResonance target) - unResonance (fieldResonance current))
    , fieldAtmosphere     = mkAtmosphere
        (atmosphereValence (fieldAtmosphere target) - atmosphereValence (fieldAtmosphere current))
        (atmosphereArousal (fieldAtmosphere target) - atmosphereArousal (fieldAtmosphere current))
    , fieldConfidence     = mkFieldConfidence
        (unFieldConfidence (fieldConfidence target) - unFieldConfidence (fieldConfidence current))
    , fieldConsolidation  = mkConsolidation
        (unConsolidation (fieldConsolidation target) - unConsolidation (fieldConsolidation current))
    , fieldCounterfactual = mkCounterfactual
        (unCounterfactual (fieldCounterfactual target) - unCounterfactual (fieldCounterfactual current))
    }

hasChallengeMarker :: Text -> Bool
hasChallengeMarker input =
  let lowered = T.toLower input
  in any (`T.isInfixOf` lowered)
       [ "разве", "не согласен", "не согласна", "противореч", "неверно"
       , "ошибаешься", "не прав", "спорю", "возраж", "сомневаюсь"
       , "ты говоришь", "оспариваю"
       ]

renderTurnOutput :: PipelineIO -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> IO TurnArtifacts
renderTurnOutput pio ss ti ts tp = do
  let effectPlan = planRenderEffectsForRuntime (pipelineRuntimeMode pio) (pipelineLocalRecoveryPolicy pio) ss ti ts tp
  effectResults <- resolveRenderEffects pio effectPlan
  pure (buildTurnArtifacts ss ti ts tp effectPlan effectResults)
