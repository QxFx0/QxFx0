{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Finalize-stage precommit planning/resolution before persistence commit.

P1.1 note: the feedback write to @resources/config/tuned_relation_weights.jsonl@
still happens below for offline analysis, but the runtime now also reads the
same file as a weight overlay during session bootstrap (see
'QxFx0.Semantic.Network.Seed.Select.loadRelationWeightOverlay').  Persisted
'SystemState' is the authoritative carrier of learned weights; the JSONL file
is a secondary, inspectable mirror. -}
module QxFx0.Core.TurnPipeline.Finalize.Precommit
  ( planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  ) where

import Control.Concurrent.Async (forConcurrently)
import Data.Sequence (Seq)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import QxFx0.Observability.TraceAnalysis (analyzeTrace, logTraceAnomalies)

import QxFx0.Core.MeaningGraph (recordTransition)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , localRecoveryPolicyText
  , pipelineLocalRecoveryPolicy
  , pipelineRuntimeMode
  , pipelineRuntimeModeAsRuntimeMode
  , pipelineShadowPolicy
  , scheduleTurnEffects
  , resolveTurnEffect
  , shadowPolicyText
  )
import QxFx0.Core.TurnPipeline.EffectLabel (PipelineEffectLabel(..))
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
import QxFx0.Core.EvidenceAdmissibility (classifyEvidenceIO)
import QxFx0.Types.Evidence (EvidenceAdmissibility(..))
import QxFx0.ExceptionPolicy (QxFx0Exception(..))
import QxFx0.Types.Decision (TurnDecision(..))
import qualified Data.Text as T
import Control.Monad (when)
import Control.Exception (throwIO)
import System.Environment (lookupEnv)
import QxFx0.Types
import QxFx0.Types.Domain.Atoms (maText, asAtoms)
import QxFx0.Core.TurnPipeline.Types (tiAtomSet)
import QxFx0.Render.Authority (AuthoritySurface(..))
import QxFx0.Types.State.SemanticCommitment (FactualClaimPayload(..))
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Semantic.Network.Feedback.Persist (persistFeedbackNetwork)

-- | Read the runtime feedback-loop flag.
--
-- The feedback loop is now opt-in: it defaults to 'False' and is only
-- enabled when @QXFX0_FEEDBACK_LOOP@ is set to one of @"1"@, @"true"@,
-- @"yes"@ or @"enable"@. Any other value is treated as disabled.
readFeedbackLoopActive :: IO Bool
readFeedbackLoopActive = do
  mEnv <- lookupEnv "QXFX0_FEEDBACK_LOOP"
  pure $ maybe False (\raw -> T.toLower (T.pack raw) `elem` ["1", "true", "yes", "enable"]) mEnv

planFinalizePrecommit :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan
planFinalizePrecommit systemState turnInput _turnSignals turnPlan turnArtifacts =
  let decision = taDecision turnArtifacts
      outcomeFamily = tdFamily decision
      outcomeVerdict = mkVerdict outcomeFamily
      executedOutcome = taExecutedOutcome turnArtifacts
      consecutiveReflect =
        if outcomeFamily == CMReflect
          then ssConsecutiveReflect systemState + 1
          else 0
      transitionWon = etoTransitionWon executedOutcome
      turnAtoms :: Set Text
      turnAtoms = S.fromList $ map maText (asAtoms (tiAtomSet turnInput))
      meaningGraphBase =
        recordTransition
          turnAtoms
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
        , fppCapturedCurrentTime = tiStartTime turnInput
        , fppConatusEnergy = tiConatusEnergy turnInput
        , fppIntrospectionRequest = FinalizeReqSemanticIntrospectionEnv
        }

resolveFinalizePrecommit :: PipelineIO -> FinalizePrecommitPlan -> IO FinalizePrecommitResults
resolveFinalizePrecommit pipelineIO plan = do
  let scheduledRequests :: [(PipelineEffectLabel, TurnEffectRequest)]
      scheduledRequests =
        scheduleTurnEffects pipelineIO (fppConatusEnergy plan)
          [ (PelSemanticIntrospection, TurnReqSemanticIntrospectionEnv)
          , (PelWarnMorphology, TurnReqReadEnv "QXFX0_WARN_MORPHOLOGY_FALLBACK")
          , (PelFmarMode, TurnReqReadEnv "QXFX0_FMAR")
          ]
  resolved <- forConcurrently scheduledRequests $ \(label, request) -> do
    result <- resolveTurnEffect pipelineIO request
    pure (label, result)
  let semanticIntrospectionEnabled =
        case lookup PelSemanticIntrospection resolved of
          Just (TurnResSemanticIntrospectionEnv hasIntrospectionEnv) -> hasIntrospectionEnv
          _ -> False
      warnMorphologyFallbackEnabled =
        case lookup PelWarnMorphology resolved of
          Just (TurnResReadEnv (Just "1")) -> True
          _ -> False
      fmarMode =
        case lookup PelFmarMode resolved of
          Just (TurnResReadEnv mraw) -> readFmarMode mraw
          _ -> FmarOff
  pure
    FinalizePrecommitResults
      { fprCurrentTime = fppCapturedCurrentTime plan
      , fprRuntimeMode = pipelineRuntimeModeAsRuntimeMode (pipelineRuntimeMode pipelineIO)
      , fprShadowPolicy = shadowPolicyText (pipelineShadowPolicy pipelineIO)
      , fprLocalRecoveryPolicy = localRecoveryPolicyText (pipelineLocalRecoveryPolicy pipelineIO)
      , fprSemanticIntrospectionEnabled = semanticIntrospectionEnabled
      , fprWarnMorphologyFallbackEnabled = warnMorphologyFallbackEnabled
      , fprFmarMode = fmarMode
      }

buildFinalizePrecommit :: (Text -> Seq Text -> Seq Text) -> (AuthoritySurface -> IO (Maybe FactualClaimPayload)) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan -> FinalizePrecommitResults -> IO FinalizePrecommitBundle
buildFinalizePrecommit updateHistory parseAuthSurface systemState turnInput turnSignals turnPlan turnArtifacts precommitPlan precommitResults = do
  feedbackLoopActive <- readFeedbackLoopActive
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
  mClaimPayload <- parseAuthSurface (AuthoritySurface (taFinalRendered turnArtifacts))
  let (nextSystemState0, commitmentTrigger, commitDecision, promotedCount) =
        buildNextSystemState
          updateHistory
          mClaimPayload
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
          feedbackLoopActive
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
  when (feedbackLoopActive && ssSemanticNetwork nextSystemState /= ssSemanticNetwork systemState) $
    -- P1.1: keep writing the JSONL mirror for offline analysis.  The
    -- authoritative learned weights live in persisted 'SystemState' and are
    -- reloaded via 'loadRelationWeightOverlay' in bootstrap.
    persistFeedbackNetwork
      "resources/config/tuned_relation_weights.jsonl"
      (ssSemanticNetwork systemState)
      (ssSemanticNetwork nextSystemState)
  let guardStatus = tdGuardStatus (taDecision turnArtifacts)
  evidenceAdmissibility <- classifyEvidenceIO guardStatus
  when (evidenceAdmissibility == EvidenceInadmissible) $
    throwIO (EvidenceInadmissibleFailure $
      "governed-evidence mode: guard Unavailable, evidence inadmissible. Guard reason: "
      <> T.pack (show guardStatus))
  let projection =
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
          promotedCount
          (tpCommitmentEngagement turnPlan)
          evidenceAdmissibility
      wantIntrospection =
        fprSemanticIntrospectionEnabled precommitResults
          || ssOutputMode systemState == SemanticIntrospectionOutput
      replayTrace = tqpReplayTrace projection
  -- Phase 3D: Analyze trace for anomalies and log (moved from buildFinalOutput for IO boundary)
  let traceAnalysis = analyzeTrace replayTrace
  logTraceAnomalies replayTrace traceAnalysis
  let (outputWithIntrospection, finalSafetyStatus) =
        buildFinalOutput wantIntrospection replayTrace systemState (taGuardSurface turnArtifacts) nextSystemState
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

