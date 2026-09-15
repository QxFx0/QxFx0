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
import Data.Time.Clock (UTCTime, getCurrentTime)

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
import QxFx0.Types.Persistence
  ( PersistenceDiagnostic(..)
  , PersistenceStage(StageStateBlobUpsert, StageUnknown)
  , StateVersion(..)
  )
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
    , fcpFeedbackMirrorPending = fpbFeedbackMirrorPending bundle
    , fcpEssenceValidation = fpbEssenceValidation bundle
    }

resolveFinalizeCommit :: PipelineIO -> StateVersion -> FinalizeCommitPlan -> IO FinalizeCommitResults
resolveFinalizeCommit pipelineIO expectedVersion commitPlan = do
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

  -- Audit 2026-09-15: wall-clock the persistence window honestly.
  -- The previous code stamped both ends with the turn-start capture,
  -- so every persist phase reported 0ms.
  saveStart <- getCurrentTime
  saveResult <-
    resolveTurnEffect
      pipelineIO
      (TurnReqSaveState (fcpSaveState commitPlan) (fcpSessionId commitPlan) expectedVersion (Just (fcpProjection commitPlan)))
  savedState <-
    case saveResult of
      TurnResSaveState (Right savedSystemState) -> pure savedSystemState
      TurnResSaveState (Left err) -> do
        hPutStrLn stderr $ "[persistence_debug] finalize_save_failed session=" <> T.unpack (fcpSessionId commitPlan) <> " detail=" <> T.unpack (renderPersistenceDiagnostics [err])
        case err of
          PdStateVersionConflict sid expected actual ->
            throwQxFx0 (mkPersistenceError
              StageStateBlobUpsert
              (T.pack "saveStateWithProjectionExpected")
              (T.pack "PERSISTENCE_CONFLICT")
              (Map.fromList
                [ (T.pack "session_id", sid)
                , (T.pack "expected_revision", T.pack (show (stateRevision expected)))
                , (T.pack "actual_revision", T.pack (show (stateRevision actual)))
                , (T.pack "expected_turn", T.pack (show (stateTurn expected)))
                , (T.pack "actual_turn", T.pack (show (stateTurn actual)))
                ]))
          _ ->
            throwQxFx0 (mkPersistenceError
              StageStateBlobUpsert
              (T.pack "saveStateWithProjectionExpected")
              (T.pack "PERSISTENCE_SAVE_FAILED")
              (Map.fromList [(T.pack "session_id", fcpSessionId commitPlan), (T.pack "detail", renderPersistenceDiagnostics [err])]))
      _ -> do
        hPutStrLn stderr $ "[persistence_debug] finalize_save_unexpected_effect session=" <> T.unpack (fcpSessionId commitPlan)
        throwQxFx0 (mkPersistenceError
          StageStateBlobUpsert
          (T.pack "saveStateWithProjectionExpected")
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
          rollbackSucceeded <- attemptRollbackPersistedTurn
            pipelineIO
            (StateVersion (stateRevision expectedVersion + 1) (ssTurnCount (fcpSaveState commitPlan)))
            commitPlan
          unless rollbackSucceeded $
            hPutStrLnWarning
              "[warn] atomic rollback of persisted state and turn projections failed after commit/recovery failure"
          let rollbackText = if rollbackSucceeded then "ok" else "failed"
          throwQxFx0
            (PersistenceError
              ("commit runtime state failed after saveState: "
                <> T.pack (show commitErr)
                <> "; recovery failed: "
                <> T.pack (show recoveryErr)
                <> "; atomic persistence rollback="
                <> rollbackText))
  if fcpFeedbackMirrorPending commitPlan
    then runBestEffortPostCommit "feedback_mirror" $ do
      _ <- resolveTurnEffect pipelineIO
        (TurnReqPersistFeedbackMirror
          (ssSemanticNetwork (fcpPreviousState commitPlan))
          (ssSemanticNetwork savedState))
      pure ()
    else pure ()
  runBestEffortPostCommit "housekeeping" $ do
    maybeInjectPostCommitTailException pipelineIO
    _ <- resolveTurnEffect pipelineIO (TurnReqCheckpoint (ssTurnCount savedState))
    pure ()
  saveEnd <- getCurrentTime
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

attemptRollbackPersistedTurn :: PipelineIO -> StateVersion -> FinalizeCommitPlan -> IO Bool
attemptRollbackPersistedTurn pipelineIO expectedVersion commitPlan = do
  rollbackAttempt <-
    tryAsync
      (resolveTurnEffect
        pipelineIO
        (TurnReqRollbackCommittedTurn
          (fcpPreviousState commitPlan)
          (fcpSessionId commitPlan)
          expectedVersion
          (ssTurnCount (fcpPreviousState commitPlan))))
  case rollbackAttempt of
    Left err ->
      hPutStrLn stderr ("[rollback] atomic persisted-turn rollback failed: " <> show err) >> pure False
    Right (TurnResRollbackCommittedTurn (Right ())) ->
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
