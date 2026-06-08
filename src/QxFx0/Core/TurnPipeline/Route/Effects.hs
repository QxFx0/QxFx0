{-# LANGUAGE OverloadedStrings #-}

{-|
Description : observer — Route effect planning and concurrent effect resolution. -}
module QxFx0.Core.TurnPipeline.Route.Effects
  ( planRouteEffects
  , resolveRouteEffects
  ) where

import Control.Concurrent.Async (forConcurrently)
import Control.Monad (when)
import qualified Data.Foldable as F
import Data.Maybe (fromMaybe)
import Data.Text (Text)

import QxFx0.Core.Observability (hPutStrLnWarning)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , ShadowResult(..)
  , pipelineRuntimeMode
  , scheduleTurnEffects
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
import QxFx0.Core.TurnPolicy (routeFamilyWithSelfVerdict)
import QxFx0.ExceptionPolicy (QxFx0Exception(..), throwQxFx0)
import QxFx0.Self.Essence (Essence(..), validatePlan)
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
      mCommitment =
        case tiEssence ti of
          EssenceCommitted _ c -> Just c
          EssenceUncommitted _ -> Nothing
      courtesyPred = fmap (\c p -> case validatePlan c p of Right _ -> True; Left _ -> False) mCommitment
      rd =
        routeFamilyWithSelfVerdict
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
          (tiField ti)
          (tiSelfVerdict ti)
          (tiConatusEnergy ti)
          (tiDoubtScore ti)
          courtesyPred
          (tiRetrievedEpisodes ti)
      family = rdFamily rd
      atomTags = map maTag (asAtoms atomSet)
   in RouteEffectPlan
        { repStatic = RouteStatic {rsRoutingDecision = rd}
        , repRouteTurnInput = ti
        , repShadowRequest = RouteReqShadow family (forceForFamily family) atomTags
        , repAgdaRequest = RouteReqAgdaVerify
        }

resolveRouteEffects :: PipelineIO -> RouteEffectPlan -> IO RouteEffectResults
resolveRouteEffects pio effectPlan = do
  let scheduledRequests :: [(Text, TurnEffectRequest)]
      scheduledRequests =
        scheduleTurnEffects pio (tiConatusEnergy (repRouteTurnInput effectPlan))
          ( [ ("shadow", TurnReqShadow family force atomTags)
            | RouteReqShadow family force atomTags <- [repShadowRequest effectPlan]
            ]
         <> [ ("agda", TurnReqAgdaVerify)
            | RouteReqAgdaVerify <- [repAgdaRequest effectPlan]
            ]
          )
  resolved <- forConcurrently scheduledRequests $ \(label, request) -> do
    result <- resolveTurnEffect pio request
    pure (label, result)
  let shadowResult =
        fromMaybe unexpectedShadowResult $ do
          (_, result) <- firstMatch (\(label, _) -> label == "shadow") resolved
          shadowResultFromTurnResult result
      agdaStatus =
        fromMaybe AgdaInvalid $ do
          (_, result) <- firstMatch (\(label, _) -> label == "agda") resolved
          agdaStatusFromTurnResult result
  let agdaReady = agdaVerificationReady agdaStatus
      strictMode = pipelineRuntimeMode pio == RuntimeStrict
      agdaMsg = "agda_status=" <> agdaVerificationStatusText agdaStatus
  when (strictMode && not agdaReady) $
    throwQxFx0 (AgdaGateError agdaMsg)
  when (not agdaReady) $
    hPutStrLnWarning ("Agda R5 verification: " <> agdaVerificationStatusText agdaStatus)
  pure RouteEffectResults
    { rerShadowResult = shadowResult
    , rerAgdaStatus = agdaStatus
    }

shadowResultFromTurnResult :: TurnEffectResult -> Maybe ShadowResult
shadowResultFromTurnResult result =
  case result of
    TurnResShadow datalogVerdict shadowStatus divergence snapshotId diagnostics ->
      Just ShadowResult
        { srDatalogVerdict = datalogVerdict
        , srStatus = shadowStatus
        , srDivergence = divergence
        , srSnapshotId = snapshotId
        , srDiagnostics = diagnostics
        }
    _ ->
      Nothing

agdaStatusFromTurnResult :: TurnEffectResult -> Maybe AgdaVerificationStatus
agdaStatusFromTurnResult result =
  case result of
    TurnResAgdaVerify agdaStatus -> Just agdaStatus
    _ -> Nothing

firstMatch :: (a -> Bool) -> [a] -> Maybe a
firstMatch predicate = go
  where
    go [] = Nothing
    go (x:xs)
      | predicate x = Just x
      | otherwise = go xs

unexpectedShadowResult :: ShadowResult
unexpectedShadowResult =
  ShadowResult
    { srDatalogVerdict = Nothing
    , srStatus = ShadowUnavailable
    , srDivergence = emptyShadowDivergence {sdKind = ShadowBridgeSkew}
    , srSnapshotId = ShadowSnapshotId "shadow:route_unexpected_effect"
    , srDiagnostics = ["unexpected_route_shadow_request"]
    }
