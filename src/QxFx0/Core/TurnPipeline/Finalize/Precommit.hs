{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Finalize-stage precommit planning/resolution before persistence commit. -}
module QxFx0.Core.TurnPipeline.Finalize.Precommit
  ( planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  ) where

import Control.Concurrent.Async (forConcurrently)
import Data.Sequence (Seq)
import Data.Text (Text)
import QxFx0.Observability.TraceAnalysis (analyzeTrace, logTraceAnomalies)

import QxFx0.Core.MeaningGraph (recordTransition)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , localRecoveryPolicyText
  , pipelineLocalRecoveryPolicy
  , pipelineRuntimeMode
  , pipelineRuntimeModeText
  , pipelineShadowPolicy
  , scheduleTurnEffects
  , resolveTurnEffect
  , shadowPolicyText
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.TurnPipeline.Finalize.Dream (applyDreamDynamics)
import QxFx0.Core.FMAR (FmarMode(..), readFmarMode)
import QxFx0.Core.TurnPipeline.Finalize.Projection (buildTurnProjection)
import QxFx0.Core.TurnPipeline.Finalize.State
  ( buildFinalOutput
  , buildNextSystemState
  , computeEssenceValidation
  )
import QxFx0.Learning.Loop (applyExternalLearning)
import QxFx0.Core.TurnPipeline.Finalize.Types
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Learning.DialogueDevelopment (applyDialogueDevelopment)
import QxFx0.Self.Perspective (applyPerspectiveOperator)
import QxFx0.Types
import QxFx0.Types.State.SelfState (SelfState(..))

planFinalizePrecommit :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan
planFinalizePrecommit systemState _turnInput _turnSignals turnPlan turnArtifacts =
  let decision = taDecision turnArtifacts
      outcomeFamily = tdFamily decision
      outcomeVerdict = mkVerdict outcomeFamily
      executedOutcome = taExecutedOutcome turnArtifacts
      consecutiveReflect =
        if outcomeFamily == CMReflect
          then ssConsecutiveReflect systemState + 1
          else 0
      transitionWon = etoTransitionWon executedOutcome
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
        , fppCapturedCurrentTime = tiStartTime _turnInput
        , fppConatusEnergy = tiConatusEnergy _turnInput
        , fppIntrospectionRequest = FinalizeReqSemanticIntrospectionEnv
        }

resolveFinalizePrecommit :: PipelineIO -> FinalizePrecommitPlan -> IO FinalizePrecommitResults
resolveFinalizePrecommit pipelineIO plan = do
  let scheduledRequests :: [(Text, TurnEffectRequest)]
      scheduledRequests =
        scheduleTurnEffects pipelineIO (fppConatusEnergy plan)
          [ ("semantic_introspection", TurnReqSemanticIntrospectionEnv)
          , ("warn_morphology", TurnReqReadEnv "QXFX0_WARN_MORPHOLOGY_FALLBACK")
          , ("fmar_mode", TurnReqReadEnv "QXFX0_FMAR")
          ]
  resolved <- forConcurrently scheduledRequests $ \(label, request) -> do
    result <- resolveTurnEffect pipelineIO request
    pure (label, result)
  let semanticIntrospectionEnabled =
        case firstMatch (\(label, _) -> label == "semantic_introspection") resolved of
          Just (_, TurnResSemanticIntrospectionEnv hasIntrospectionEnv) -> hasIntrospectionEnv
          _ -> False
      warnMorphologyFallbackEnabled =
        case firstMatch (\(label, _) -> label == "warn_morphology") resolved of
          Just (_, TurnResReadEnv (Just "1")) -> True
          _ -> False
      fmarMode =
        case firstMatch (\(label, _) -> label == "fmar_mode") resolved of
          Just (_, TurnResReadEnv mraw) -> readFmarMode mraw
          _ -> FmarOff
  pure
    FinalizePrecommitResults
      { fprCurrentTime = fppCapturedCurrentTime plan
      , fprRuntimeMode = pipelineRuntimeModeText (pipelineRuntimeMode pipelineIO)
      , fprShadowPolicy = shadowPolicyText (pipelineShadowPolicy pipelineIO)
      , fprLocalRecoveryPolicy = localRecoveryPolicyText (pipelineLocalRecoveryPolicy pipelineIO)
      , fprSemanticIntrospectionEnabled = semanticIntrospectionEnabled
      , fprWarnMorphologyFallbackEnabled = warnMorphologyFallbackEnabled
      , fprFmarMode = fmarMode
      }

buildFinalizePrecommit :: (Text -> Seq Text -> Seq Text) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan -> FinalizePrecommitResults -> IO FinalizePrecommitBundle
buildFinalizePrecommit updateHistory systemState turnInput turnSignals turnPlan turnArtifacts precommitPlan precommitResults = do
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
      (nextSystemState0, commitmentTrigger, commitDecision) =
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
      -- Phase 8 gap closure: apply external learning-loop result from
      -- the render-phase artifacts (populated by resolveRenderEffects
      -- when a request strategy triggered TurnReqExternalQuery).
      nextSystemState1 = applyExternalLearning nextSystemState0 (taExternalQueryResult turnArtifacts)
      -- Phase 9: apply autonomous exploratory learning-loop result.
      nextSystemState2 = applyExternalLearning nextSystemState1 (taExploratoryQueryResult turnArtifacts)
      -- ADR-0032: record dialogue outcome, speech-policy pressure, and
      -- belief stance after base/external learning state has settled.
      nextSystemState3 = applyDialogueDevelopment systemState nextSystemState2 turnInput turnPlan turnArtifacts
      nextSystemState = applyPerspectiveOperator nextSystemState3 (tiConatusEnergy turnInput) (tiConatusGateFired turnInput) (tiField turnInput)
      projection =
        buildTurnProjection
          (fprRuntimeMode precommitResults)
          (fprShadowPolicy precommitResults)
          (fprLocalRecoveryPolicy precommitResults)
          (fprSemanticIntrospectionEnabled precommitResults)
          (fprWarnMorphologyFallbackEnabled precommitResults)
          (fprFmarMode precommitResults)
          nextSystemState
          turnInput
          turnSignals
          turnPlan
          turnArtifacts
          commitDecision
      wantIntrospection =
        fprSemanticIntrospectionEnabled precommitResults
          || ssOutputMode systemState == SemanticIntrospectionOutput
      replayTrace = tqpReplayTrace projection
  -- Phase 3D: Analyze trace for anomalies and log (moved from buildFinalOutput for IO boundary)
  let traceAnalysis = analyzeTrace replayTrace
  logTraceAnomalies replayTrace traceAnalysis
  let (outputWithIntrospection, finalSafetyStatus) =
        buildFinalOutput wantIntrospection (Just replayTrace) systemState (taGuardSurface turnArtifacts) nextSystemState
  pure FinalizePrecommitBundle
        { fpbNextSs = nextSystemState
        , fpbProjection = projection
        , fpbOutput = outputWithIntrospection
        , fpbFinalSafetyStatus = finalSafetyStatus
        , fpbOutcomeFamily = fsOutcomeFamily static
        , fpbDecision = taDecision turnArtifacts
        , fpbRewireEventsCount = rewireEventsCount
         , fpbEssenceValidation =
             computeEssenceValidation
               turnInput
               turnPlan
               (selfEssence (ssSelfState nextSystemState))
               commitmentTrigger
         , fpbCommitmentTrigger = commitmentTrigger
         }

firstMatch :: (a -> Bool) -> [a] -> Maybe a
firstMatch predicate = go
  where
    go [] = Nothing
    go (x:xs)
      | predicate x = Just x
      | otherwise = go xs
