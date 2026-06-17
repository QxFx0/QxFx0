{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Description : observer — Finalize-stage persistence commit, runtime state commit, and post-commit hooks. -}
module QxFx0.Core.TurnPipeline.Finalize.Commit
  ( planFinalizeCommit
  , resolveFinalizeCommit
  , buildFinalizeTurnResult
  , resolveFinalizePostCommit
  ) where

import Control.Monad (unless)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)

import qualified QxFx0.Core.Guard as Guard
import QxFx0.Core.ConsciousnessLoop (ResponseObservation(..))
import QxFx0.Core.Observability
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , resolveTurnEffect
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.TurnPipeline.Finalize.State (finalizeMetrics)
import QxFx0.Types.TurnProjection (tqpReplayTrace, trcCommitmentContradicted)
import QxFx0.Core.TurnPipeline.Finalize.Types
import QxFx0.Core.TurnPipeline.Types
import qualified Data.Map.Strict as Map
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(EssenceRupture, IdentityRupture, PersistenceError)
  , mkPersistenceError
  , renderQxFx0ExceptionForLog
  , throwQxFx0
  , tryAsync
  )
import QxFx0.Types.Persistence (PersistenceDiagnostic(..), PersistenceStage(StageStateBlobUpsert, StageUnknown))
import QxFx0.Self.Essence (EssenceViolation, renderEssenceViolation)
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Invariants (checkBlanketTransition, renderBlanketViolations)
import QxFx0.Types
import QxFx0.Core.TurnPipeline.Types (RenderedTurn(..))
import System.IO (hPutStrLn, stderr)

planFinalizeCommit :: Text -> SystemState -> TurnInput -> TurnSignals -> TurnArtifacts -> FinalizePrecommitBundle -> FinalizeCommitPlan
planFinalizeCommit sessionId previousState turnInput turnSignals turnArtifacts bundle =
  FinalizeCommitPlan
    { fcpResponseObservation =
        ResponseObservation
          { roSurfaceText = taFinalRendered turnArtifacts
          , roQuestionLike = Guard.gsQuestionLike (taGuardSurface turnArtifacts)
          }
    , fcpPreviewConsciousLoop = tsConsciousLoop' turnSignals
    , fcpPreviewIntuition = tsIntuitionState turnSignals
    , fcpCapturedCurrentTime = tiStartTime turnInput
    , fcpPreviousState = previousState
    , fcpSaveState = fpbNextSs bundle
    , fcpSessionId = sessionId
    , fcpProjection = fpbProjection bundle
    , fcpRewireEventsCount = fpbRewireEventsCount bundle
    , fcpEssenceValidation = fpbEssenceValidation bundle
    }

resolveFinalizeCommit :: PipelineIO -> Int -> FinalizeCommitPlan -> IO FinalizeCommitResults
resolveFinalizeCommit pipelineIO expectedRevision commitPlan = do
  unless (fcpRewireEventsCount commitPlan == 0) $
    hPutStrLnWarning ("Dream rewiring: " <> T.pack (show (fcpRewireEventsCount commitPlan)) <> " edges adjusted")

  -- Phase 1: verify that the prepared next-state preserves the
  -- system's structural self-identity relative to the previous state
  -- (see docs/THEORY.md §4.1). A rupture here means we are about to
  -- persist a state that is no longer /this system/ — fail fast
  -- before touching persistence rather than corrupt the snapshot.
  case checkBlanketTransition
         (computeSelfBlanket (fcpPreviousState commitPlan))
         (computeSelfBlanket (fcpSaveState commitPlan)) of
    []         -> pure ()
    violations ->
      throwQxFx0 (IdentityRupture ("commit: " <> renderBlanketViolations violations))

  -- Phase 10: post-commitment essence guard.  Co-located with
  -- 'IdentityRupture' above; both abort the turn before persistence.
  case fcpEssenceValidation commitPlan of
    Right () -> pure ()
    Left v   -> throwQxFx0
                  (EssenceRupture ("commit: " <> renderEssenceViolation v))

  let saveStart = fcpCapturedCurrentTime commitPlan
  saveResult <-
    resolveTurnEffect
      pipelineIO
      (TurnReqSaveState (fcpSaveState commitPlan) (fcpSessionId commitPlan) expectedRevision (Just (fcpProjection commitPlan)))
  savedState <-
    case saveResult of
      TurnResSaveState (Right savedSystemState) -> pure savedSystemState
      TurnResSaveState (Left err) -> do
        hPutStrLn stderr $ "[persistence_debug] finalize_save_failed session=" <> T.unpack (fcpSessionId commitPlan) <> " detail=" <> T.unpack (renderPersistenceDiagnostics [err])
        case err of
          PdStateRevisionConflict sid expected actual priorTurn ->
            throwQxFx0 (mkPersistenceError
              StageStateBlobUpsert
              (T.pack "saveStateWithProjection")
              (T.pack "PERSISTENCE_CONFLICT")
              (Map.fromList
                [ (T.pack "session_id", sid)
                , (T.pack "expected_revision", T.pack (show expected))
                , (T.pack "actual_revision", T.pack (show actual))
                , (T.pack "expected_prior_turn", T.pack (show priorTurn))
                ]))
          _ ->
            throwQxFx0 (mkPersistenceError
              StageStateBlobUpsert
              (T.pack "saveStateWithProjection")
              (T.pack "PERSISTENCE_SAVE_FAILED")
              (Map.fromList [(T.pack "session_id", fcpSessionId commitPlan), (T.pack "detail", renderPersistenceDiagnostics [err])]))
      _ -> do
        hPutStrLn stderr $ "[persistence_debug] finalize_save_unexpected_effect session=" <> T.unpack (fcpSessionId commitPlan)
        throwQxFx0 (mkPersistenceError
          StageStateBlobUpsert
          (T.pack "saveStateWithProjection")
          (T.pack "PERSISTENCE_UNEXPECTED_EFFECT")
          (Map.fromList [(T.pack "session_id", fcpSessionId commitPlan)]))
  commitAttempt <-
    tryAsync (attemptCommitRuntimeState pipelineIO commitPlan (fcpPreviewIntuition commitPlan))
  case commitAttempt of
    Right () ->
      pure ()
    Left commitErr -> do
      recoveryAttempt <- tryAsync (recoverRuntimeTurnState pipelineIO commitPlan savedState)
      case recoveryAttempt of
        Right () ->
          hPutStrLnWarning
            ("[warn] commit runtime state failed after save; state re-hydrated from persisted snapshot: "
              <> T.pack (show commitErr))
        Left recoveryErr -> do
          projectionsRollbackSucceeded <- attemptRollbackPersistedProjections pipelineIO commitPlan
          unless projectionsRollbackSucceeded $
            hPutStrLnWarning
              "[warn] rollback of persisted turn projections failed after commit/recovery failure"
          stateRollbackSucceeded <- attemptRollbackPersistedState pipelineIO (expectedRevision + 1) commitPlan
          unless stateRollbackSucceeded $
            hPutStrLnWarning
              "[warn] rollback to previous persisted state failed after commit/recovery failure"
          let projectionsRollbackText = if projectionsRollbackSucceeded then "ok" else "failed"
              stateRollbackText = if stateRollbackSucceeded then "ok" else "failed"
          throwQxFx0
            (PersistenceError
              ("commit runtime state failed after saveState: "
                <> T.pack (show commitErr)
                <> "; recovery failed: "
                <> T.pack (show recoveryErr)
                <> "; projections rollback="
                <> projectionsRollbackText
                <> "; state rollback="
                <> stateRollbackText))
  runBestEffortPostCommit "housekeeping" $ do
    maybeInjectPostCommitTailException pipelineIO
    _ <- resolveTurnEffect pipelineIO (TurnReqCheckpoint (ssTurnCount savedState))
    pure ()
  let saveEnd = fcpCapturedCurrentTime commitPlan
  pure
    FinalizeCommitResults
      { fcrSavedSs = savedState
      , fcrSaveStart = saveStart
      , fcrSaveEnd = saveEnd
      }

buildFinalizeTurnResult :: RenderedTurn -> FinalizePrecommitBundle -> FinalizeCommitResults -> TurnResult
buildFinalizeTurnResult rendered bundle commitResults =
  let RenderedTurn turnInput turnSignals _turnPlan turnArtifacts = rendered
      savedState = fcrSavedSs commitResults
      commitContradicted = trcCommitmentContradicted (tqpReplayTrace (fpbProjection bundle))
      metricsFinal =
        (finalizeMetrics
          turnInput
          turnArtifacts
          (fpbOutcomeFamily bundle)
          (fpbDecision bundle)
          savedState
          (tsApiHealthy turnSignals)
          (fpbFinalSafetyStatus bundle)
          (fcrSaveStart commitResults)
          (fcrSaveEnd commitResults))
          { tmCommitmentContradicted = commitContradicted }
   in TurnResult
        { trRendered = rendered
        , trNextSs = savedState
        , trOutput = fpbOutput bundle
        , trMetrics = metricsFinal
        }

resolveFinalizePostCommit :: TurnMetrics -> IO ()
resolveFinalizePostCommit metrics =
  runBestEffortPostCommit "metrics_log" $
    logMetrics metrics

runBestEffortPostCommit :: Text -> IO a -> IO ()
runBestEffortPostCommit label action = do
  result <- tryAsync action
  case result of
    Left err -> hPutStrLnWarning $ "[warn] post-commit " <> label <> " failed: " <> T.pack (show err)
    Right _ -> pure ()

attemptCommitRuntimeState :: PipelineIO -> FinalizeCommitPlan -> IntuitiveState -> IO ()
attemptCommitRuntimeState pipelineIO commitPlan previewIntuition = do
  commitResult <-
    resolveTurnEffect
      pipelineIO
      (TurnReqCommitRuntimeState
        (fcpPreviewConsciousLoop commitPlan)
        previewIntuition
        (fcpResponseObservation commitPlan))
  case commitResult of
    TurnResCommitRuntimeState -> pure ()
    _ -> do
      hPutStrLn stderr $ "[persistence_debug] commit_runtime_state_unexpected_effect session=" <> T.unpack (fcpSessionId commitPlan)
      throwQxFx0 (mkPersistenceError
        StageUnknown
        (T.pack "commitRuntimeState")
        (T.pack "PERSISTENCE_UNEXPECTED_EFFECT")
        (Map.fromList [(T.pack "session_id", fcpSessionId commitPlan)]))

recoverRuntimeTurnState :: PipelineIO -> FinalizeCommitPlan -> SystemState -> IO ()
recoverRuntimeTurnState pipelineIO commitPlan savedState =
  attemptCommitRuntimeState
    pipelineIO
    commitPlan
    (maybe (fcpPreviewIntuition commitPlan) id (ssIntuitionState savedState))

attemptRollbackPersistedProjections :: PipelineIO -> FinalizeCommitPlan -> IO Bool
attemptRollbackPersistedProjections pipelineIO commitPlan = do
  rollbackAttempt <-
    tryAsync
      (resolveTurnEffect
        pipelineIO
        (TurnReqRollbackTurnProjections (fcpSessionId commitPlan) (ssTurnCount (fcpPreviousState commitPlan))))
  case rollbackAttempt of
    Left _ ->
      pure False
    Right (TurnResRollbackTurnProjections (Right ())) ->
      pure True
    Right _ ->
      pure False

attemptRollbackPersistedState :: PipelineIO -> Int -> FinalizeCommitPlan -> IO Bool
attemptRollbackPersistedState pipelineIO expectedRevision commitPlan = do
  rollbackAttempt <-
    tryAsync
      (resolveTurnEffect
        pipelineIO
        (TurnReqSaveState (fcpPreviousState commitPlan) (fcpSessionId commitPlan) expectedRevision Nothing))
  case rollbackAttempt of
    Left _ ->
      pure False
    Right (TurnResSaveState (Right _)) ->
      pure True
    Right _ ->
      pure False

maybeInjectPostCommitTailException :: PipelineIO -> IO ()
maybeInjectPostCommitTailException pipelineIO = do
  testModeResult <- resolveTurnEffect pipelineIO (TurnReqReadEnv "QXFX0_TEST_MODE")
  case testModeResult of
    TurnResReadEnv (Just "1") -> do
      markerPathResult <-
        resolveTurnEffect pipelineIO (TurnReqReadEnv "QXFX0_TEST_POST_COMMIT_TAIL_EXCEPTION_ONCE_FILE")
      case markerPathResult of
        TurnResReadEnv (Just pathTextRaw) ->
          let pathText = T.strip pathTextRaw
          in unless (T.null pathText) $ do
              markResult <- resolveTurnEffect pipelineIO (TurnReqTestMarkOnceFile pathText)
              case markResult of
                TurnResTestMarkOnceFile True ->
                  throwQxFx0 (mkPersistenceError
                    StageUnknown
                    (T.pack "test_post_commit_tail")
                    (T.pack "TEST_POST_COMMIT_EXCEPTION")
                    Map.empty)
                _ ->
                  pure ()
        _ ->
          pure ()
    _ ->
      pure ()
