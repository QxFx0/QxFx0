{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData, RankNTypes #-}
module QxFx0.Bridge.StatePersistence
  ( saveState
  , saveStateWithProjection
  , rollbackTurnProjections
  , loadState
  , stateBlobDiagnostics
  -- Re-exported from QxFx0.Types.Persistence for backward compatibility
  , PersistenceDiagnostic(..)
  , PersistenceStage(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  ) where

import QxFx0.Types.State (SystemState(..))
import QxFx0.Types.Thresholds (legitimacyStatusText, scenePressureText)
import QxFx0.Types.Decision (decisionDispositionText, renderStyleText, shadowStatusText, legitimacyReasonText, plannerModeText, parserModeText)
import QxFx0.Types.ShadowDivergence (shadowDivergenceKindText, shadowSnapshotIdText)
import QxFx0.Types.TurnProjection (TurnProjection(..))
import QxFx0.Types.Persistence
  ( PersistenceDiagnostic(..)
  , PersistenceStage(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  )
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement (prepareTx, bindTextOrFail, bindIntOrFail, bindDoubleOrFail, stepOrFail)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import QxFx0.ExceptionPolicy (tryQxFx0, throwQxFx0, QxFx0Exception(..))
import Control.Exception (finally, mask, onException)
import Control.Monad (when)

type DbRunner = forall a. (NSQL.Database -> IO a) -> IO a

saveState :: DbRunner -> SystemState -> Text -> IO (Either PersistenceDiagnostic SystemState)
saveState withDb ss sessionId = saveStateWithProjection withDb ss sessionId Nothing

saveStateWithProjection :: DbRunner -> SystemState -> Text -> Maybe TurnProjection -> IO (Either PersistenceDiagnostic SystemState)
saveStateWithProjection withDb ss sessionId mProjection = do
  let persistedState = ss { ssSessionId = sessionId }
  result <- tryQxFx0 $ withDb $ \db -> do
    withImmediateTransaction db $ do
      let jsonBlob = TE.decodeUtf8With lenientDecode . BL.toStrict . Aeson.encode $ persistedState
      touchRuntimeSessionActivity db sessionId
      saveKV db sessionId "__system_state__" jsonBlob

      case mProjection of
        Nothing -> pure ()
        Just projection -> do
          persistTurnQuality db sessionId projection
          when (tqpDivergence projection) $
            persistShadowDivergence db sessionId projection

      pure persistedState
  case result of
    Left (PersistenceTxError stage msg) -> pure (Left (diagnoseSave stage (Just msg)))
    Left other -> pure (Left (PdSaveFailed StageUnknown Nothing (Just (T.pack (show other)))))
    Right savedSs -> pure $ Right savedSs

rollbackTurnProjections :: DbRunner -> Text -> Int -> IO (Either PersistenceDiagnostic ())
rollbackTurnProjections withDb sessionId stableTurn = do
  result <- tryQxFx0 $ withDb $ \db -> do
    withImmediateTransaction db $ do
      deleteTurnQualityAbove db sessionId stableTurn
      deleteShadowDivergenceAbove db sessionId stableTurn
  case result of
    Left (PersistenceTxError stage msg) -> pure (Left (diagnoseRollback stage (Just msg)))
    Left other -> pure (Left (PdRollbackFailed StageUnknown Nothing (Just (T.pack (show other)))))
    Right () -> pure (Right ())

withImmediateTransaction :: NSQL.Database -> IO a -> IO a
withImmediateTransaction db action = mask $ \restore -> do
  beginResult <- NSQL.execSql db "BEGIN IMMEDIATE;"
  case beginResult of
    Left err ->
      throwQxFx0 (PersistenceTxError StageTxBegin ("tx_begin_failed: " <> err))
    Right _ ->
      pure ()
  result <- restore action `onException` rollbackBestEffort db
  commitResult <- NSQL.execSql db "COMMIT;"
  case commitResult of
    Right _ ->
      pure result
    Left err -> do
      rollbackResult <- NSQL.execSql db "ROLLBACK;"
      case rollbackResult of
        Right _ ->
          throwQxFx0 (PersistenceTxError StageTxCommit ("tx_commit_failed: " <> err))
        Left rbErr ->
          throwQxFx0
            (PersistenceTxError StageTxCommit ("tx_commit_and_rollback_failed: commit=" <> err <> " rollback=" <> rbErr))

rollbackBestEffort :: NSQL.Database -> IO ()
rollbackBestEffort db = do
  _ <- NSQL.execSql db "ROLLBACK;"
  pure ()

saveKV :: NSQL.Database -> Text -> Text -> Text -> IO ()
saveKV db sessionId k v = do
  let sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
  ts <- prepareTx db ("saveKV:" <> k) sql
  bindTextOrFail ts 1 sessionId
  bindTextOrFail ts 2 k
  bindTextOrFail ts 3 v
  stepOrFail ts

touchRuntimeSessionActivity :: NSQL.Database -> Text -> IO ()
touchRuntimeSessionActivity db sessionId = do
  let sql = "UPDATE runtime_sessions SET last_active = datetime('now'), status = 'active' WHERE id = ?"
  ts <- prepareTx db "touchRuntimeSessionActivity" sql
  bindTextOrFail ts 1 sessionId
  stepOrFail ts

loadState :: DbRunner -> Text -> IO LoadStateResult
loadState withDb sessionId = withDb $ \db -> do
  mBlob <- loadKV db sessionId "__system_state__"
  case mBlob of
    Just blob ->
      case Aeson.eitherDecodeStrict (TE.encodeUtf8 blob) of
        Right ss -> pure (LoadStateRestored ss)
        Left _ -> pure (LoadStateCorrupt (PdCorruptDecode : stateBlobDiagnostics blob))
    Nothing -> pure LoadStateMissing

stateBlobDiagnostics :: Text -> [PersistenceDiagnostic]
stateBlobDiagnostics blob =
  case Aeson.decode (BL.fromStrict (TE.encodeUtf8 blob)) :: Maybe Aeson.Object of
    Nothing -> []
    Just obj ->
      let optionalSystemFields =
            [ "lastGuardReport"
            , "dreamState"
            , "intuitionState"
            , "semanticAnchor"
            , "lastTurnDecision"
            ]
          missing = filter (\k -> not (KM.member (AK.fromText k) obj)) optionalSystemFields
      in if null missing
           then []
           else [PdSchemaMissingFields missing]

loadKV :: NSQL.Database -> Text -> Text -> IO (Maybe Text)
loadKV db sessionId k = do
  let sql = "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ?"
  withPreparedStatement db sql ("loadKV key=" <> k <> ", session=" <> sessionId) $ \stmt -> do
    _ <- NSQL.bindText stmt 1 sessionId
    _ <- NSQL.bindText stmt 2 k
    hasRow <- NSQL.stepRow stmt
    if hasRow
      then Just <$> NSQL.columnText stmt 0
      else pure Nothing

persistTurnQuality :: NSQL.Database -> Text -> TurnProjection -> IO ()
persistTurnQuality db sessionId p = do
  let sql = "INSERT OR REPLACE INTO turn_quality(session_id, turn, parser_mode, parser_confidence, parser_errors, planner_mode, planner_decision, atom_register, atom_load, scene_pressure, scene_request, scene_stance, render_lane, render_style, legitimacy_status, legitimacy_reason, warranted_mode, decision_disposition, owner_family, owner_force, shadow_status, shadow_snapshot_id, shadow_divergence_kind, shadow_family, shadow_force, shadow_message, replay_trace_json, divergence) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      replayTraceJson = TE.decodeUtf8With lenientDecode . BL.toStrict . Aeson.encode $ tqpReplayTrace p
  ts <- prepareTx db "turn_quality" sql
  bindTextOrFail ts 1 sessionId
  bindIntOrFail ts 2 (tqpTurn p)
  bindTextOrFail ts 3 (parserModeText (tqpParserMode p))
  bindDoubleOrFail ts 4 (tqpParserConfidence p)
  bindTextOrFail ts 5 (T.intercalate "," (tqpParserErrors p))
  bindTextOrFail ts 6 (plannerModeText (tqpPlannerMode p))
  bindTextOrFail ts 7 (T.pack (show (tqpPlannerDecision p)))
  bindTextOrFail ts 8 (T.pack (show (tqpAtomRegister p)))
  bindDoubleOrFail ts 9 (tqpAtomLoad p)
  bindTextOrFail ts 10 (scenePressureText (tqpScenePressure p))
  bindTextOrFail ts 11 (tqpSceneRequest p)
  bindTextOrFail ts 12 (T.pack (show (tqpSceneStance p)))
  bindTextOrFail ts 13 (T.pack (show (tqpRenderLane p)))
  bindTextOrFail ts 14 (renderStyleText (tqpRenderStyle p))
  bindTextOrFail ts 15 (legitimacyStatusText (tqpLegitimacyStatus p))
  bindTextOrFail ts 16 (legitimacyReasonText (tqpLegitimacyReason p))
  bindTextOrFail ts 17 (T.pack (show (tqpWarrantedMode p)))
  bindTextOrFail ts 18 (decisionDispositionText (tqpDecisionDisposition p))
  bindTextOrFail ts 19 (T.pack (show (tqpOwnerFamily p)))
  bindTextOrFail ts 20 (T.pack (show (tqpOwnerForce p)))
  bindTextOrFail ts 21 (shadowStatusText (tqpShadowStatus p))
  bindTextOrFail ts 22 (shadowSnapshotIdText (tqpShadowSnapshotId p))
  bindTextOrFail ts 23 (shadowDivergenceKindText (tqpShadowDivergenceKind p))
  bindTextOrFail ts 24 (maybe "" (T.pack . show) (tqpShadowFamily p))
  bindTextOrFail ts 25 (maybe "" (T.pack . show) (tqpShadowForce p))
  bindTextOrFail ts 26 (tqpShadowMessage p)
  bindTextOrFail ts 27 replayTraceJson
  bindIntOrFail ts 28 (if tqpDivergence p then 1 else 0)
  stepOrFail ts

persistShadowDivergence :: NSQL.Database -> Text -> TurnProjection -> IO ()
persistShadowDivergence db sessionId p = do
  let sql = "INSERT INTO shadow_divergence_log(session_id, turn, owner_family, owner_force, shadow_status, shadow_snapshot_id, shadow_divergence_kind, shadow_family, shadow_force, shadow_message) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  ts <- prepareTx db "shadow_divergence_log" sql
  bindTextOrFail ts 1 sessionId
  bindIntOrFail ts 2 (tqpTurn p)
  bindTextOrFail ts 3 (T.pack (show (tqpOwnerFamily p)))
  bindTextOrFail ts 4 (T.pack (show (tqpOwnerForce p)))
  bindTextOrFail ts 5 (shadowStatusText (tqpShadowStatus p))
  bindTextOrFail ts 6 (shadowSnapshotIdText (tqpShadowSnapshotId p))
  bindTextOrFail ts 7 (shadowDivergenceKindText (tqpShadowDivergenceKind p))
  bindTextOrFail ts 8 (maybe "" (T.pack . show) (tqpShadowFamily p))
  bindTextOrFail ts 9 (maybe "" (T.pack . show) (tqpShadowForce p))
  bindTextOrFail ts 10 (tqpShadowMessage p)
  stepOrFail ts

deleteTurnQualityAbove :: NSQL.Database -> Text -> Int -> IO ()
deleteTurnQualityAbove db sessionId stableTurn = do
  let sql = "DELETE FROM turn_quality WHERE session_id = ? AND turn > ?"
  ts <- prepareTx db "delete_turn_quality_above" sql
  bindTextOrFail ts 1 sessionId
  bindIntOrFail ts 2 stableTurn
  stepOrFail ts

deleteShadowDivergenceAbove :: NSQL.Database -> Text -> Int -> IO ()
deleteShadowDivergenceAbove db sessionId stableTurn = do
  let sql = "DELETE FROM shadow_divergence_log WHERE session_id = ? AND turn > ?"
  ts <- prepareTx db "delete_shadow_divergence_above" sql
  bindTextOrFail ts 1 sessionId
  bindIntOrFail ts 2 stableTurn
  stepOrFail ts

withPreparedStatement :: NSQL.Database -> Text -> Text -> (NSQL.Statement -> IO a) -> IO a
withPreparedStatement db sql context action = do
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err ->
      throwQxFx0 (PersistenceTxError StageUnknown ("prepare failed for " <> context <> ": " <> err))
    Right stmt ->
      action stmt `finally` finalizeBestEffort stmt

finalizeBestEffort :: NSQL.Statement -> IO ()
finalizeBestEffort stmt = do
  _ <- tryQxFx0 (NSQL.finalize stmt)
  pure ()

diagnoseSave :: PersistenceStage -> Maybe Text -> PersistenceDiagnostic
diagnoseSave StageTxBegin _ = PdTransactionBeginFailed
diagnoseSave StageTxCommit _ = PdTransactionCommitFailed
diagnoseSave StageTxRollback _ = PdTransactionRollbackFailed
diagnoseSave stage mMsg = PdSaveFailed stage Nothing mMsg

diagnoseRollback :: PersistenceStage -> Maybe Text -> PersistenceDiagnostic
diagnoseRollback StageTxBegin _ = PdTransactionBeginFailed
diagnoseRollback StageTxCommit _ = PdTransactionCommitFailed
diagnoseRollback StageTxRollback _ = PdTransactionRollbackFailed
diagnoseRollback stage mMsg = PdRollbackFailed stage Nothing mMsg
