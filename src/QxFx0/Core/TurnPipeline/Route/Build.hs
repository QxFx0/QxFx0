{-# LANGUAGE OverloadedStrings #-}

{-| Route-plan assembly and render handoff after effect resolution. -}
module QxFx0.Core.TurnPipeline.Route.Build
  ( buildRouteTurnPlan
  , routeTurnPlan
  , renderTurnOutput
  ) where

import QxFx0.Core.Intuition (IntuitiveFlash(..))
import QxFx0.Core.Legitimacy (legitimacyRecoveryBonus)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , ShadowPolicy
  , pipelineLocalRecoveryPolicy
  , pipelineRuntimeMode
  , pipelineShadowPolicy
  )
import QxFx0.Core.TurnPlanning (buildRCP, buildRMP)
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
import QxFx0.Core.TurnPolicy
import QxFx0.Core.Semantic.SemanticScene (defaultScenes, inferActiveScene)
import QxFx0.Core.Semantic.Proposition (diagnosticPropositionFamily)
import QxFx0.Types
import QxFx0.Types.Thresholds (agdaVerificationPenalty)

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
      shadowResolution = resolveShadowFamily shadowPolicy (rdFamily rd) sc
      family = srEffectiveFamily shadowResolution
      recoveryBonus =
        legitimacyRecoveryBonus
          (scShadowStatus sc == ShadowMatch && not (scShadowHasDivergence sc))
          (rdStrategyFamily rd == Just family)
      newEgo = rdNewEgo rd
      renderStrategy = rdRenderStrategy rd
      renderStyle = rdRenderStyle rd
      rmpBase = buildRMP family (tiFrame ti) (tiBestTopic ti) newEgo (tiNewTrace ti) (tiNixAvailable ti)
      rmp0 = applyRenderStrategy family renderStrategy rmpBase
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
      finalForce = forceForFamily finalFamily
      rmpAfterLegit =
        rmpAfterLegit0
          { rmpFamily = finalFamily
          , rmpForce = finalForce
          }
      rcpFinal =
        if finalFamily == finalFamily0
          then rcpFinal0
          else (buildRCP finalFamily rmpAfterLegit) {rcpStyle = rcpStyle rcpFinal0}
      activeScene = inferActiveScene (tiNewTrace ti) (map maTag (asAtoms atomSet)) (ssActiveScene ss) defaultScenes
   in TurnPlan
        { tpFamily = family
        , tpNewEgo = newEgo
        , tpIdentitySignal = rdIdentitySignal rd
        , tpGuardReport = rdGuardReport rd
        , tpSemanticAnchor = rdSemanticAnchor rd
        , tpRenderStrategy = renderStrategy
        , tpRenderStyle = renderStyleText renderStyle
        , tpPrincipledMode =
            case (rdPressure rd, rdPrincipledMode rd) of
              (Just p, Just pmr) -> Just (p, pmr)
              _ -> Nothing
        , tpUpdatedOrbital = rdUpdatedOrbital rd
        , tpFromMs = rdFromMs rd
        , tpToMs = rdToMs rd
        , tpStrategyFamily = rdStrategyFamily rd
        , tpPreShadowFamily = rdFamily rd
        , tpRmpAfterLegit = rmpAfterLegit
        , tpRcpFinal = rcpFinal
        , tpFinalFamily = finalFamily
        , tpFinalForce = finalForce
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
        , tpShadowMessage = scShadowMessage sc
        , tpMetrics = tiMetrics ti
        }

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
