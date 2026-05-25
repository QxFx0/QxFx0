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

import QxFx0.Types.State
  ( StatePersistenceSnapshot(..)
  , SystemState(..)
  , preparePersistenceSnapshot
  , runtimeContinuationState
  , ssTurnCount
  )
import QxFx0.Types.Thresholds (legitimacyStatusText, scenePressureText)
import QxFx0.Types.Decision (decisionDispositionText, renderStyleText, shadowStatusText, legitimacyReasonText, plannerModeText, parserModeText)
import QxFx0.Types.ShadowDivergence (shadowDivergenceKindText, shadowSnapshotIdText)
import QxFx0.Types.TurnProjection (TurnProjection(..), TurnReplayTrace(..))
import QxFx0.Types.Observability (AuthorityClass(..), TruthContractStatus(..), ReplayProvenanceStatus(..))
import QxFx0.Types.Persistence
  ( PersistenceDiagnostic(..)
  , PersistenceStage(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  )
import QxFx0.Learning.KnowledgeTree (KnowledgeTree(..))
import QxFx0.Learning.Calibration (CalibrationLog(..))
import QxFx0.Learning.Guardrails (GuardrailState(..))
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement (prepareTx, bindTextOrFail, bindIntOrFail, bindInt64OrFail, bindDoubleOrFail, stepOrFail)
import QxFx0.Governance.Replay (rebuildGovernedSystemState)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import QxFx0.ExceptionPolicy (renderQxFx0ExceptionForLog, tryQxFx0, throwQxFx0, QxFx0Exception(..))
import Control.Exception (finally, mask, onException)
import Control.Exception (try)
import Data.Text.Encoding.Error (UnicodeException)
import Control.Monad (when)
import System.IO (hPutStrLn, stderr)

type DbRunner = forall a. (NSQL.Database -> IO a) -> IO a

-- | Emit a stderr trace line with counts of persisted learning artefacts.
logPersistenceCounts :: String -> SystemState -> IO ()
logPersistenceCounts label ss = do
  let tree = ssKnowledgeTree ss
      branchesFruits = sum (map length (M.elems (ktBranches tree)))
      quarantineFruits = length (ktQuarantine tree)
      morph = ssMorphology ss
      calibCount = length (unCalibrationLog (ssCalibrationLog ss))
      guardQuarantine = length (gsQuarantine (ssGuardrailState ss))
  hPutStrLn stderr $ concat
    [ "[persistence_trace] ", label
    , " session_id=", T.unpack (ssSessionId ss)
    , " turn_count=", show (ssTurnCount ss)
    , " ktree_branches_fruits=", show branchesFruits
    , " ktree_quarantine=", show quarantineFruits
    , " ktree_grafted=", show (ktGraftedCount tree)
    , " ktree_pruned=", show (ktPrunedCount tree)
    , " morph_prep=", show (M.size (mdPrepositional morph))
    , " morph_gen=", show (M.size (mdGenitive morph))
    , " morph_nom=", show (M.size (mdNominative morph))
    , " morph_surface=", show (M.size (mdFormsBySurface morph))
    , " calib_log=", show calibCount
    , " guard_quarantine=", show guardQuarantine
    ]

saveState :: DbRunner -> SystemState -> Text -> IO (Either PersistenceDiagnostic SystemState)
saveState withDb ss sessionId = saveStateWithProjection withDb ss sessionId Nothing

saveStateWithProjection :: DbRunner -> SystemState -> Text -> Maybe TurnProjection -> IO (Either PersistenceDiagnostic SystemState)
saveStateWithProjection withDb ss sessionId mProjection = do
  logPersistenceCounts "pre_save" ss
  let persistenceSnapshot = preparePersistenceSnapshot sessionId ss
      persistedState = spsCanonicalState persistenceSnapshot
      runtimeState = spsRuntimeContinuation persistenceSnapshot
  result <- tryQxFx0 $ withDb $ \db -> do
    withImmediateTransaction db $ do
      touchRuntimeSessionActivity db sessionId
      persistSystemBlob db sessionId persistedState
      persistTurnArtifacts db sessionId mProjection

      pure runtimeState
  case result of
    Left (PersistenceTxError stage msg) -> do
      hPutStrLn stderr $ "[persistence_debug] save_tx_error session=" <> T.unpack sessionId <> " stage=" <> show stage <> " detail=" <> T.unpack msg
      pure (Left (diagnoseSave stage (Just msg)))
    Left other -> do
      hPutStrLn stderr $ "[persistence_debug] save_unknown_qxfx0_exception session=" <> T.unpack sessionId <> " detail=" <> T.unpack (renderQxFx0ExceptionForLog other)
      pure (Left (PdSaveFailed StageUnknown Nothing (Just (renderQxFx0ExceptionForLog other))))
    Right savedSs -> pure $ Right savedSs

rollbackTurnProjections :: DbRunner -> Text -> Int -> IO (Either PersistenceDiagnostic ())
rollbackTurnProjections withDb sessionId stableTurn = do
  result <- tryQxFx0 $ withDb $ \db -> do
    withImmediateTransaction db $ do
      deleteTurnQualityAbove db sessionId stableTurn
      deleteShadowDivergenceAbove db sessionId stableTurn
  case result of
    Left (PersistenceTxError stage msg) -> pure (Left (diagnoseRollback stage (Just msg)))
    Left other -> pure (Left (PdRollbackFailed StageUnknown Nothing (Just (renderQxFx0ExceptionForLog other))))
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
  mBlobResult <- try (loadKV db sessionId "__system_state__") :: IO (Either UnicodeException (Maybe Text))
  case mBlobResult of
    Left err -> do
      hPutStrLn stderr $ "[persistence_debug] load_unicode_exception session=" <> T.unpack sessionId <> " detail=" <> show err
      pure (LoadStateCorrupt [PdCorruptDecode])
    Right mBlob ->
      case mBlob of
        Just blob ->
          case Aeson.eitherDecodeStrict (TE.encodeUtf8 blob) of
            Right ss ->
              if persistedTruthIsAuthoritative (ssTruthContractStatus ss)
                then do
                  case rebuildGovernedSystemState ss of
                    Right rebuilt -> do
                      let restored = runtimeContinuationState sessionId rebuilt
                      logPersistenceCounts "post_load" restored
                      pure (LoadStateRestored restored)
                    Left err -> do
                      hPutStrLn stderr $ "[persistence_debug] governance_rebuild_failed session=" <> T.unpack sessionId <> " detail=" <> T.unpack err
                      pure (LoadStateCorrupt [PdCorruptDecode, PdSchemaMissingFields ["governance_rebuild_failed:" <> err]])
                else do
                  hPutStrLn stderr $ "[persistence_debug] non_authoritative_persisted_state session=" <> T.unpack sessionId
                  pure (LoadStateCorrupt [PdCorruptDecode, PdSchemaMissingFields ["non_authoritative_persisted_state"]])
            Left decodeErr -> do
              hPutStrLn stderr $ "[persistence_debug] decode_failed session=" <> T.unpack sessionId <> " detail=" <> decodeErr
              pure (LoadStateCorrupt (PdCorruptDecode : stateBlobDiagnostics blob))
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
      replayTrace0 = tqpReplayTrace p
      replayAuthority = fromMaybe AuthorityLegacyIncomplete (trcAuthorityClass replayTrace0)
      replayTrace =
        replayTrace0
          { trcReplayProvenanceStatus =
              normalizeReplayProvenanceStatus (trcReplayProvenanceStatus replayTrace0) replayAuthority
          }
      replayTraceJson = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ replayTrace
  ts <- prepareTx db "turn_quality" sql
  bindTextOrFail ts 1 sessionId
  bindInt64OrFail ts 2 (fromIntegral (tqpTurn p))
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

persistSystemBlob :: NSQL.Database -> Text -> SystemState -> IO ()
persistSystemBlob db sessionId persistedState = do
  let jsonBlob = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ persistedState
  saveKV db sessionId "__system_state__" jsonBlob

persistTurnArtifacts :: NSQL.Database -> Text -> Maybe TurnProjection -> IO ()
persistTurnArtifacts _ _ Nothing = pure ()
persistTurnArtifacts db sessionId (Just projection) = do
  persistTurnQuality db sessionId projection
  when (tqpDivergence projection) $
    persistShadowDivergence db sessionId projection

persistShadowDivergence :: NSQL.Database -> Text -> TurnProjection -> IO ()
persistShadowDivergence db sessionId p = do
  let sql = "INSERT INTO shadow_divergence_log(session_id, turn, owner_family, owner_force, shadow_status, shadow_snapshot_id, shadow_divergence_kind, shadow_family, shadow_force, shadow_message) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  ts <- prepareTx db "shadow_divergence_log" sql
  bindTextOrFail ts 1 sessionId
  bindInt64OrFail ts 2 (fromIntegral (tqpTurn p))
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
  bindInt64OrFail ts 2 (fromIntegral stableTurn)
  stepOrFail ts

deleteShadowDivergenceAbove :: NSQL.Database -> Text -> Int -> IO ()
deleteShadowDivergenceAbove db sessionId stableTurn = do
  let sql = "DELETE FROM shadow_divergence_log WHERE session_id = ? AND turn > ?"
  ts <- prepareTx db "delete_shadow_divergence_above" sql
  bindTextOrFail ts 1 sessionId
  bindInt64OrFail ts 2 (fromIntegral stableTurn)
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

persistedTruthIsAuthoritative :: TruthContractStatus -> Bool
persistedTruthIsAuthoritative CanonicalSurfacePreserved = True
persistedTruthIsAuthoritative AssembledSurfacePreserved = True
persistedTruthIsAuthoritative _ = False

normalizeReplayProvenanceStatus :: ReplayProvenanceStatus -> AuthorityClass -> ReplayProvenanceStatus
normalizeReplayProvenanceStatus replayStatus authority
  | authority `elem` [AuthorityGeneratedArtifact, AuthorityLegacyIncomplete] = ReplayProvenanceLegacyIncomplete
  | otherwise = replayStatus
