{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Finalize-stage precommit planning/resolution before persistence commit. -}
module QxFx0.Core.TurnPipeline.Finalize.Precommit
  ( planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  ) where

import Control.Concurrent.Async (concurrently)
import Data.Sequence (Seq)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)

import QxFx0.Core.MeaningGraph (recordTransition)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , localRecoveryPolicyText
  , pipelineLocalRecoveryPolicy
  , pipelineRuntimeMode
  , pipelineRuntimeModeText
  , pipelineShadowPolicy
  , resolveTurnEffect
  , shadowPolicyText
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.TurnPipeline.Finalize.Dream (applyDreamDynamics)
import QxFx0.Core.TurnPipeline.Finalize.State
  ( buildFinalOutput
  , buildNextSystemState
  , buildTurnProjection
  )
import QxFx0.Core.TurnPipeline.Finalize.Types
import QxFx0.Core.TurnPipeline.Types
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(PersistenceError)
  , throwQxFx0
  )
import QxFx0.Types

planFinalizePrecommit :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan
planFinalizePrecommit systemState _turnInput _turnSignals turnPlan turnArtifacts =
  let decision = taDecision turnArtifacts
      outcomeFamily = tdFamily decision
      outcomeVerdict = mkVerdict outcomeFamily
      consecutiveReflect =
        if outcomeFamily == CMReflect
          then ssConsecutiveReflect systemState + 1
          else 0
      transitionWon =
        case taSurfaceProv turnArtifacts of
          FromRecovery -> False
          _ -> tpStrategyFamily turnPlan == Just (rmpFamily (tpRmpAfterLegit turnPlan))
      meaningGraphBase =
        recordTransition
          (tpFromMs turnPlan)
          (tpToMs turnPlan)
          (tpRenderStrategy turnPlan)
          transitionWon
          (ssMeaningGraph systemState)
      static =
        FinalizeStatic
          { fsOutcomeFamily = outcomeFamily
          , fsOutcomeVerdict = outcomeVerdict
          , fsConsecReflect = consecutiveReflect
          , fsTransitionWon = transitionWon
          , fsMeaningGraphBase = meaningGraphBase
          }
   in FinalizePrecommitPlan
        { fppStatic = static
        , fppCurrentTimeRequest = FinalizeReqCurrentTime
        , fppIntrospectionRequest = FinalizeReqSemanticIntrospectionEnv
        }

resolveFinalizePrecommit :: PipelineIO -> FinalizePrecommitPlan -> IO FinalizePrecommitResults
resolveFinalizePrecommit pipelineIO plan = do
  (currentTime, (semanticIntrospectionEnabled, warnMorphologyFallbackEnabled)) <-
    concurrently
      (resolveCurrentTime pipelineIO plan)
      ( concurrently
          (resolveIntrospectionEnv pipelineIO plan)
          (resolveWarnMorphologyFallbackEnv pipelineIO plan)
      )
  pure
    FinalizePrecommitResults
      { fprCurrentTime = currentTime
      , fprRuntimeMode = pipelineRuntimeModeText (pipelineRuntimeMode pipelineIO)
      , fprShadowPolicy = shadowPolicyText (pipelineShadowPolicy pipelineIO)
      , fprLocalRecoveryPolicy = localRecoveryPolicyText (pipelineLocalRecoveryPolicy pipelineIO)
      , fprSemanticIntrospectionEnabled = semanticIntrospectionEnabled
      , fprWarnMorphologyFallbackEnabled = warnMorphologyFallbackEnabled
      }

buildFinalizePrecommit :: (Text -> Seq Text -> Seq Text) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan -> FinalizePrecommitResults -> FinalizePrecommitBundle
buildFinalizePrecommit updateHistory systemState turnInput turnSignals turnPlan turnArtifacts precommitPlan precommitResults =
  let static = fppStatic precommitPlan
      (newDreamState, newMeaningGraph, rewireEventsCount) =
        applyDreamDynamics
          (fprCurrentTime precommitResults)
          systemState
          turnInput
          turnSignals
          turnPlan
          turnArtifacts
          (fsMeaningGraphBase static)
      nextSystemState =
        buildNextSystemState
          updateHistory
          systemState
          turnInput
          turnSignals
          turnPlan
          turnArtifacts
          newDreamState
          newMeaningGraph
          (fsOutcomeFamily static)
          (fsOutcomeVerdict static)
          (fsConsecReflect static)
      projection =
        buildTurnProjection
          (fprRuntimeMode precommitResults)
          (fprShadowPolicy precommitResults)
          (fprLocalRecoveryPolicy precommitResults)
          (fprSemanticIntrospectionEnabled precommitResults)
          (fprWarnMorphologyFallbackEnabled precommitResults)
          nextSystemState
          turnInput
          turnSignals
          turnPlan
          turnArtifacts
      wantIntrospection =
        fprSemanticIntrospectionEnabled precommitResults
          || ssOutputMode systemState == SemanticIntrospectionOutput
      (outputWithIntrospection, finalSafetyStatus) =
        buildFinalOutput wantIntrospection systemState (taGuardSurface turnArtifacts) nextSystemState
   in FinalizePrecommitBundle
        { fpbNextSs = nextSystemState
        , fpbProjection = projection
        , fpbOutput = outputWithIntrospection
        , fpbFinalSafetyStatus = finalSafetyStatus
        , fpbOutcomeFamily = fsOutcomeFamily static
        , fpbDecision = taDecision turnArtifacts
        , fpbRewireEventsCount = rewireEventsCount
        }

resolveCurrentTime :: PipelineIO -> FinalizePrecommitPlan -> IO UTCTime
resolveCurrentTime pipelineIO plan =
  case finalizePrecommitRequestToTurnEffect (fppCurrentTimeRequest plan) of
    Just _ -> do
      result <- resolveTurnEffect pipelineIO TurnReqCurrentTime
      case result of
        TurnResCurrentTime currentTime -> pure currentTime
        _ -> throwQxFx0 (PersistenceError "current time effect returned unexpected result")
    Nothing ->
      throwQxFx0 (PersistenceError "missing current time request")

resolveIntrospectionEnv :: PipelineIO -> FinalizePrecommitPlan -> IO Bool
resolveIntrospectionEnv pipelineIO plan =
  case finalizePrecommitRequestToTurnEffect (fppIntrospectionRequest plan) of
    Just _ -> do
      result <- resolveTurnEffect pipelineIO TurnReqSemanticIntrospectionEnv
      case result of
        TurnResSemanticIntrospectionEnv hasIntrospectionEnv -> pure hasIntrospectionEnv
        _ -> pure False
    Nothing ->
      pure False

resolveWarnMorphologyFallbackEnv :: PipelineIO -> FinalizePrecommitPlan -> IO Bool
resolveWarnMorphologyFallbackEnv pipelineIO plan =
  case finalizePrecommitRequestToTurnEffect (fppIntrospectionRequest plan) of
    Just _ -> do
      result <- resolveTurnEffect pipelineIO (TurnReqReadEnv "QXFX0_WARN_MORPHOLOGY_FALLBACK")
      case result of
        TurnResReadEnv (Just "1") -> pure True
        TurnResReadEnv _ -> pure False
        _ -> pure False
    Nothing ->
      pure False

finalizePrecommitRequestToTurnEffect :: FinalizePrecommitRequest -> Maybe TurnEffectRequest
finalizePrecommitRequestToTurnEffect request =
  case request of
    FinalizeReqCurrentTime -> Just TurnReqCurrentTime
    FinalizeReqSemanticIntrospectionEnv -> Just TurnReqSemanticIntrospectionEnv
