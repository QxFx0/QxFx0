{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Finalize-stage persistence commit, runtime state commit, and post-commit hooks. -}
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
import QxFx0.Core.TurnPipeline.Finalize.Types
import QxFx0.Core.TurnPipeline.Types
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(PersistenceError)
  , throwQxFx0
  , tryAsync
  )
import QxFx0.Types

planFinalizeCommit :: Text -> SystemState -> TurnSignals -> TurnArtifacts -> FinalizePrecommitBundle -> FinalizeCommitPlan
planFinalizeCommit sessionId previousState turnSignals turnArtifacts bundle =
  FinalizeCommitPlan
    { fcpResponseObservation =
        ResponseObservation
          { roSurfaceText = taFinalRendered turnArtifacts
          , roQuestionLike = Guard.gsQuestionLike (taGuardSurface turnArtifacts)
          }
    , fcpPreviewConsciousLoop = tsConsciousLoop' turnSignals
    , fcpPreviewIntuition = tsIntuitionState turnSignals
    , fcpPreviousState = previousState
    , fcpSaveState = fpbNextSs bundle
    , fcpSessionId = sessionId
    , fcpProjection = fpbProjection bundle
    , fcpRewireEventsCount = fpbRewireEventsCount bundle
    }

resolveFinalizeCommit :: PipelineIO -> FinalizeCommitPlan -> IO FinalizeCommitResults
resolveFinalizeCommit pipelineIO commitPlan = do
  unless (fcpRewireEventsCount commitPlan == 0) $
    hPutStrLnWarning ("Dream rewiring: " ++ show (fcpRewireEventsCount commitPlan) ++ " edges adjusted")

  saveStart <- resolveCommitCurrentTime pipelineIO
  saveResult <-
    resolveTurnEffect
      pipelineIO
      (TurnReqSaveState (fcpSaveState commitPlan) (fcpSessionId commitPlan) (Just (fcpProjection commitPlan)))
  savedState <-
    case saveResult of
      TurnResSaveState (Right savedSystemState) -> pure savedSystemState
      TurnResSaveState (Left err) -> throwQxFx0 (PersistenceError ("saveStateWithProjection failed: " <> renderPersistenceDiagnostics [err]))
      _ -> throwQxFx0 (PersistenceError "saveStateWithProjection returned unexpected result")
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
              <> show commitErr)
        Left recoveryErr -> do
          projectionsRollbackSucceeded <- attemptRollbackPersistedProjections pipelineIO commitPlan
          unless projectionsRollbackSucceeded $
            hPutStrLnWarning
              "[warn] rollback of persisted turn projections failed after commit/recovery failure"
          stateRollbackSucceeded <- attemptRollbackPersistedState pipelineIO commitPlan
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
  saveEnd <- resolveCommitCurrentTime pipelineIO
  pure
    FinalizeCommitResults
      { fcrSavedSs = savedState
      , fcrSaveStart = saveStart
      , fcrSaveEnd = saveEnd
      }

buildFinalizeTurnResult :: TurnInput -> TurnSignals -> TurnArtifacts -> FinalizePrecommitBundle -> FinalizeCommitResults -> TurnResult
buildFinalizeTurnResult turnInput turnSignals turnArtifacts bundle commitResults =
  let savedState = fcrSavedSs commitResults
      metricsFinal =
        finalizeMetrics
          turnInput
          turnArtifacts
          (fpbOutcomeFamily bundle)
          (fpbDecision bundle)
          savedState
          (tsApiHealthy turnSignals)
          (fpbFinalSafetyStatus bundle)
          (fcrSaveStart commitResults)
          (fcrSaveEnd commitResults)
   in TurnResult
        { trNextSs = savedState
        , trOutput = fpbOutput bundle
        , trMetrics = metricsFinal
        }

resolveFinalizePostCommit :: TurnMetrics -> IO ()
resolveFinalizePostCommit metrics =
  runBestEffortPostCommit "metrics_log" $
    logMetrics metrics

resolveCommitCurrentTime :: PipelineIO -> IO UTCTime
resolveCommitCurrentTime pipelineIO = do
  result <- resolveTurnEffect pipelineIO TurnReqCurrentTime
  case result of
    TurnResCurrentTime currentTime -> pure currentTime
    _ -> throwQxFx0 (PersistenceError "current time effect returned unexpected result")

runBestEffortPostCommit :: String -> IO a -> IO ()
runBestEffortPostCommit label action = do
  result <- tryAsync action
  case result of
    Left err -> hPutStrLnWarning $ "[warn] post-commit " <> label <> " failed: " <> show err
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
    _ -> throwQxFx0 (PersistenceError "commit runtime state effect returned unexpected result")

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

attemptRollbackPersistedState :: PipelineIO -> FinalizeCommitPlan -> IO Bool
attemptRollbackPersistedState pipelineIO commitPlan = do
  rollbackAttempt <-
    tryAsync
      (resolveTurnEffect
        pipelineIO
        (TurnReqSaveState (fcpPreviousState commitPlan) (fcpSessionId commitPlan) Nothing))
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
                  throwQxFx0 (PersistenceError "test_post_commit_tail_exception")
                _ ->
                  pure ()
        _ ->
          pure ()
    _ ->
      pure ()
