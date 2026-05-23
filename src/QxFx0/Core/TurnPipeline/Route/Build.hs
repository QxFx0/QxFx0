{-# LANGUAGE OverloadedStrings #-}

{-| Route-plan assembly and render handoff after effect resolution. -}
module QxFx0.Core.TurnPipeline.Route.Build
  ( buildRouteTurnPlan
  , routeTurnPlan
  , renderTurnOutput
  ) where

import QxFx0.Core.Intuition (flashThreshold)
import QxFx0.Core.TruthContract (capByTruthContract, capCommitmentStrengthByTruthContract)
import QxFx0.Core.Observability (recordThresholdProbe)
import QxFx0.Core.Legitimacy (legitimacyRecoveryBonus)
import QxFx0.Core.SensePlan (familySenseBundle)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , ShadowPolicy
  , pipelineLocalRecoveryPolicy
  , pipelineRuntimeMode
  , pipelineShadowPolicy
  )
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
import QxFx0.Semantic.Proposition (diagnosticPropositionFamily)
import QxFx0.Types
import QxFx0.Types.ShadowDivergence (ShadowVetoState(..))
import QxFx0.Types.Thresholds
  ( agdaVerificationPenalty
  , legitimacyRecoveryThreshold
  , legitimacyPassThreshold
  , parserLowConfidenceThreshold
  )

buildRouteTurnPlan :: ShadowPolicy -> SystemState -> TurnInput -> TurnSignals -> RouteEffectPlan -> RouteEffectResults -> TurnPlan
buildRouteTurnPlan shadowPolicy ss ti ts effectPlan effectResults =
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
      family0 = srEffectiveFamily shadowResolution
      (family, _, _) = familySenseBundle family0 (tiDialogueCommitmentLedger ti) (tiDialoguePhase ti) (tiDialogueThread ti) (tiSenseVector ti)
      recoveryBonus =
        legitimacyRecoveryBonus
          (scShadowStatus sc == ShadowMatch && not (scShadowHasDivergence sc))
          (rdStrategyFamily rd == Just family)
      newEgo = rdNewEgo rd
      renderStrategy = rdRenderStrategy rd
      renderStyle = adjustRenderStyleForSpeechPolicy (ssSpeechPolicyState ss) (rdRenderStyle rd)
      preRenderTruthStatus = derivePreRenderTruthContractStatus ti sc shadowResolution family
      rmpBase = buildRMPWithTruthContract preRenderTruthStatus family (tiDialogueCommitmentLedger ti) (tiDialoguePhase ti) (tiDialogueThread ti) (tiFrame ti) (tiSenseVector ti) (tiBestTopic ti) newEgo (tiNewTrace ti) (tiNixAvailable ti)
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
        case diagnosticPropositionFamily (ipfPropositionType (tiFrame ti)) of
          Just diagnosticFamily
            | not (srGateTriggered shadowResolution)
                && finalFamily0 /= CMRepair ->
                Just diagnosticFamily
          _ ->
            Nothing
      finalFamily = maybe finalFamily0 id lockedDiagnosticFamily
      (finalFamily', finalSensePlan, finalMicroPlan) = familySenseBundle finalFamily (tiDialogueCommitmentLedger ti) (tiDialoguePhase ti) (tiDialogueThread ti) (tiSenseVector ti)
      finalForce' = forceForFamily finalFamily'
      postLegitTruthStatus = derivePostLegitTruthContractStatus preRenderTruthStatus ti sc shadowResolution legitScore finalFamily'
      rmpAfterLegit =
        rmpAfterLegit0
          { rmpFamily = finalFamily'
          , rmpForce = finalForce'
          , rmpSpeechAct = familyToSpeechAct finalFamily'
          , rmpRelation = familyToRelation finalFamily'
          , rmpEpistemic = capByTruthContract postLegitTruthStatus (rmpEpistemic rmpAfterLegit0)
          , rmpTruthContractStatus = postLegitTruthStatus
          , rmpCommitmentStrength = capCommitmentStrengthByTruthContract postLegitTruthStatus (rmpCommitmentStrength rmpAfterLegit0)
          , rmpSensePlan = finalSensePlan
          , rmpMicroPlan = finalMicroPlan
          }
      rcpFinal =
        if finalFamily' == finalFamily0
          then rcpFinal0
          else (buildRCP finalFamily' rmpAfterLegit) {rcpStyle = rcpStyle rcpFinal0}
      activeScene = inferActiveScene (tiNewTrace ti) (map maTag (asAtoms atomSet)) (ssActiveScene ss) defaultScenes
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
         , tpRmpAfterLegit = rmpAfterLegit
         , tpRcpFinal = rcpFinal
         , tpFinalFamily = finalFamily'
         , tpFinalForce = finalForce'
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
  pure (buildRouteTurnPlan (pipelineShadowPolicy pio) ss ti ts effectPlan effectResults)

renderTurnOutput :: PipelineIO -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> IO TurnArtifacts
renderTurnOutput pio ss ti ts tp = do
  let effectPlan = planRenderEffectsForRuntime (pipelineRuntimeMode pio) (pipelineLocalRecoveryPolicy pio) ss ti ts tp
  effectResults <- resolveRenderEffects pio effectPlan
  pure (buildTurnArtifacts ss ti ts tp effectPlan effectResults)
