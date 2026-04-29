{-# LANGUAGE OverloadedStrings #-}

{-| Route effect planning and concurrent effect resolution. -}
module QxFx0.Core.TurnPipeline.Route.Effects
  ( planRouteEffects
  , resolveRouteEffects
  ) where

import Control.Concurrent.Async (concurrently)
import Control.Monad (when)
import qualified Data.Foldable as F
import qualified Data.Text as T

import QxFx0.Core.Observability (hPutStrLnWarning)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , ShadowResult(..)
  , pipelineRuntimeMode
  , resolveTurnEffect
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.TurnPipeline.Route.Types
  ( RouteEffectPlan(..)
  , RouteEffectRequest(..)
  , RouteEffectResults(..)
  , RouteStatic(..)
  )
import QxFx0.Core.TurnPipeline.Types
  ( RoutingDecision(..)
  , TurnInput(..)
  , TurnSignals(..)
  )
import QxFx0.Core.TurnPolicy (routeFamily)
import QxFx0.ExceptionPolicy (QxFx0Exception(..), throwQxFx0)
import QxFx0.Types
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  , ShadowSnapshotId(..)
  , emptyShadowDivergence
  )

planRouteEffects :: SystemState -> TurnInput -> TurnSignals -> RouteEffectPlan
planRouteEffects ss ti ts =
  let frame = tiFrame ti
      atomSet = tiAtomSet ti
      recommendedFamily = tiRecommendedFamily ti
      intuitPosterior = tsIntuitPosterior ts
      rd =
        routeFamily
          recommendedFamily
          frame
          atomSet
          (tiNextUserState ti)
          ss
          (F.toList (ssHistory ss))
          (ipfRawText frame)
          (tiIsNixBlocked ti)
          (tiBestTopic ti)
          (tsCurrentNarrative ts)
          intuitPosterior
      family = rdFamily rd
      atomTags = map maTag (asAtoms atomSet)
   in RouteEffectPlan
        { repStatic = RouteStatic {rsRoutingDecision = rd}
        , repShadowRequest = RouteReqShadow family (forceForFamily family) atomTags
        , repAgdaRequest = RouteReqAgdaVerify
        }

resolveRouteEffects :: PipelineIO -> RouteEffectPlan -> IO RouteEffectResults
resolveRouteEffects pio effectPlan = do
  (shadowResult, agdaStatus) <-
    concurrently
      (resolveShadowEffect pio (repShadowRequest effectPlan))
      (resolveAgdaEffect pio (repAgdaRequest effectPlan))
  let agdaReady = agdaVerificationReady agdaStatus
      strictMode = pipelineRuntimeMode pio == RuntimeStrict
      agdaMsg = "agda_status=" <> agdaVerificationStatusText agdaStatus
  when (strictMode && not agdaReady) $
    throwQxFx0 (AgdaGateError agdaMsg)
  when (not agdaReady) $
    hPutStrLnWarning ("Agda R5 verification: " ++ T.unpack (agdaVerificationStatusText agdaStatus))
  pure RouteEffectResults
    { rerShadowResult = shadowResult
    , rerAgdaStatus = agdaStatus
    }

resolveShadowEffect :: PipelineIO -> RouteEffectRequest -> IO ShadowResult
resolveShadowEffect pio request =
  case routeRequestToTurnEffect request of
    Just turnRequest -> do
      result <- resolveTurnEffect pio turnRequest
      case result of
        TurnResShadow datalogVerdict shadowStatus divergence snapshotId diagnostics ->
          pure ShadowResult
            { srDatalogVerdict = datalogVerdict
            , srStatus = shadowStatus
            , srDivergence = divergence
            , srSnapshotId = snapshotId
            , srDiagnostics = diagnostics
            }
        _ ->
          pure unexpectedShadowResult
    Nothing ->
      pure unexpectedShadowResult

resolveAgdaEffect :: PipelineIO -> RouteEffectRequest -> IO AgdaVerificationStatus
resolveAgdaEffect pio request =
  case routeRequestToTurnEffect request of
    Just turnRequest -> do
      result <- resolveTurnEffect pio turnRequest
      case result of
        TurnResAgdaVerify agdaStatus -> pure agdaStatus
        _ -> pure AgdaInvalid
    Nothing ->
      pure AgdaInvalid

routeRequestToTurnEffect :: RouteEffectRequest -> Maybe TurnEffectRequest
routeRequestToTurnEffect request =
  case request of
    RouteReqShadow family force atomTags ->
      Just (TurnReqShadow family force atomTags)
    RouteReqAgdaVerify ->
      Just TurnReqAgdaVerify

unexpectedShadowResult :: ShadowResult
unexpectedShadowResult =
  ShadowResult
    { srDatalogVerdict = Nothing
    , srStatus = ShadowUnavailable
    , srDivergence = emptyShadowDivergence {sdKind = ShadowBridgeSkew}
    , srSnapshotId = ShadowSnapshotId "shadow:route_unexpected_effect"
    , srDiagnostics = ["unexpected_route_shadow_request"]
    }
