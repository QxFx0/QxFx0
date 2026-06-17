{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData, RankNTypes, LambdaCase #-}
module QxFx0.Bridge.StatePersistence
  ( saveState
  , saveStateExpected
  , saveStateWithProjection
  , saveStateWithProjectionExpected
  , rollbackTurnProjections
  , loadState
  , loadStateRevision
  , stateBlobDiagnostics
  -- Re-exported from QxFx0.Types.Persistence for backward compatibility
  , PersistenceDiagnostic(..)
  , PersistenceStage(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  ) where

import QxFx0.Types.State (SystemState(..), emptySystemState, ssTurnCount)
import QxFx0.Types.State.Perspective (emptyPerspectiveRegistry)
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Types.State.Identity (IdentityState(..))
import QxFx0.Types.State.Semantic (SemanticState(..))
import QxFx0.Types.Thresholds (legitimacyStatusText, scenePressureText)
import QxFx0.Types.Decision (DialogueOutputMode(..), decisionDispositionText, renderStyleText, shadowStatusText, legitimacyReasonText, plannerModeText, parserModeText)
import QxFx0.Types.ShadowDivergence (shadowDivergenceKindText, shadowSnapshotIdText)
import QxFx0.Types.TurnProjection (TurnProjection(..), TurnReplayTrace(..))
import QxFx0.Types.Observability (AuthorityClass(..), TruthContractStatus(..), ReplayProvenanceStatus(..))
import QxFx0.Types.Persistence
  ( PersistenceDiagnostic(..)
  , PersistenceEnvelope(..)
  , PersistenceStage(..)
  , LoadStateResult(..)
  , currentPersistenceEnvelopeVersion
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
import Data.List (intersect)
import QxFx0.ExceptionPolicy (renderQxFx0ExceptionForLog, tryQxFx0, throwQxFx0, QxFx0Exception(..))
import System.Environment (lookupEnv)
import Control.Exception (finally, mask, onException)
import Control.Exception (try)
import Data.Text.Encoding.Error (UnicodeException, lenientDecode)
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

saveStateExpected :: DbRunner -> SystemState -> Text -> Int -> IO (Either PersistenceDiagnostic SystemState)
saveStateExpected withDb ss sessionId expectedRevision = saveStateWithProjectionExpected withDb ss sessionId expectedRevision Nothing

saveStateWithProjection :: DbRunner -> SystemState -> Text -> Maybe TurnProjection -> IO (Either PersistenceDiagnostic SystemState)
saveStateWithProjection withDb ss sessionId mProjection = do
  expectedRevision <- loadStateRevision withDb sessionId
  saveStateWithProjectionExpected withDb ss sessionId expectedRevision mProjection

saveStateWithProjectionExpected :: DbRunner -> SystemState -> Text -> Int -> Maybe TurnProjection -> IO (Either PersistenceDiagnostic SystemState)
saveStateWithProjectionExpected withDb ss sessionId expectedRevision mProjection = do
  logPersistenceCounts "pre_save" ss
  let liveState = ss { ssSessionId = sessionId }
      persistedState = canonicalizePersistedState liveState
      _envelope = PersistenceEnvelope
        { peVersion = currentPersistenceEnvelopeVersion
        , peState = persistedState
        }
  result <- tryQxFx0 $ withDb $ \db -> do
    withImmediateTransaction db $ do
      let jsonBlob = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ persistedState
      bumpStateRevisionCas db sessionId expectedRevision (ssTurnCount ss - 1)
      touchRuntimeSessionActivity db sessionId
      saveKV db sessionId "__system_state__" jsonBlob

      case mProjection of
        Nothing -> pure ()
        Just projection -> do
          persistTurnQuality db sessionId projection
          when (tqpDivergence projection) $
            persistShadowDivergence db sessionId projection

      pure liveState
  case result of
    Left (PersistenceTxError stage msg) -> do
      hPutStrLn stderr $ "[persistence_debug] save_tx_error session=" <> T.unpack sessionId <> " stage=" <> show stage <> " detail=" <> T.unpack msg
      pure (Left (diagnoseSave stage (Just msg)))
    Left (PersistenceConflict sid expected actual priorTurn) -> do
      hPutStrLn stderr $ "[persistence_debug] save_conflict session=" <> T.unpack sid <> " expected_revision=" <> show expected <> " actual_revision=" <> show actual <> " expected_prior_turn=" <> show priorTurn
      pure (Left (PdStateRevisionConflict sid expected actual priorTurn))
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

bumpStateRevisionCas :: NSQL.Database -> Text -> Int -> Int -> IO ()
bumpStateRevisionCas db sessionId expectedRevision expectedPriorTurn = do
  let sql = "UPDATE runtime_sessions SET state_revision = state_revision + 1 WHERE id = ? AND state_revision = ?"
  ts <- prepareTx db "state_revision_cas" sql
  bindTextOrFail ts 1 sessionId
  bindIntOrFail ts 2 expectedRevision
  stepOrFail ts
  changed <- sqliteChanges db
  when (changed /= 1) $ do
    actualRevision <- loadStateRevisionDirect db sessionId
    throwQxFx0 (PersistenceConflict sessionId expectedRevision actualRevision expectedPriorTurn)

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
          decodePersistedState blob >>= \case
            Right ss ->
              case rebuildDerivedViewsAfterLoad ss of
                Right rebuilt -> do
                  -- SLICE-013 truth-contract policy: a non-authoritative persisted
                  -- state is a valid compatibility/provenance state, NOT corruption.
                  -- 'rebuildDerivedViewsAfterLoad' has already demoted restart authority
                  -- (semanticAnchor / lastTurnDecision -> Nothing) for non-authoritative
                  -- contours and rebuilt governed views for authoritative ones, so it is
                  -- safe to restore here regardless of contour, in both strict and
                  -- degraded runtime. Corruption is handled by the decode / governance-
                  -- rebuild failure branches below; the truth-contract marker is preserved
                  -- verbatim. Strict rejects corruption, not compatibility.
                  -- ('PdNonAuthoritativeTruth' is retained for a future contract that
                  -- explicitly declares a non-authoritative blob invalid; it is no longer
                  -- emitted for a merely non-authoritative provenance marker.)
                  logPersistenceCounts "post_load" rebuilt
                  pure (LoadStateRestored rebuilt)
                Left err -> do
                  hPutStrLn stderr $ "[persistence_debug] governance_rebuild_failed session=" <> T.unpack sessionId <> " detail=" <> T.unpack err
                  pure (LoadStateCorrupt [PdCorruptDecode, PdSchemaMissingFields ["governance_rebuild_failed:" <> err]])
            Left decodeErr -> do
              hPutStrLn stderr $ "[persistence_debug] decode_failed session=" <> T.unpack sessionId <> " detail=" <> decodeErr
              pure (LoadStateCorrupt (PdCorruptDecode : stateBlobDiagnostics blob))
        Nothing -> pure LoadStateMissing

loadStateRevision :: DbRunner -> Text -> IO Int
loadStateRevision withDb sessionId = withDb $ \db -> loadStateRevisionDirect db sessionId

-- | Optional backward-compatibility fields: present in the canonical encoding,
-- but read leniently (@.:? .!= default@) so older blobs still decode. Their
-- absence is not a decode failure, but it IS worth surfacing explicitly (the
-- blob predates these fields), which is what this diagnostic reports.
optionalCompatibilityFields :: [Text]
optionalCompatibilityFields =
  [ "lastGuardReport"
  , "dreamState"
  , "intuitionState"
  , "semanticAnchor"
  , "lastTurnDecision"
  ]

stateBlobDiagnostics :: Text -> [PersistenceDiagnostic]
stateBlobDiagnostics blob =
  case Aeson.decode (BL.fromStrict (TE.encodeUtf8 blob)) :: Maybe Aeson.Object of
    Nothing -> []
    Just obj ->
      let missing = filter (\f -> not (KM.member (AK.fromText f) obj)) optionalCompatibilityFields
      in if null missing then [] else [PdSchemaMissingFields missing]

loadKV :: NSQL.Database -> Text -> Text -> IO (Maybe Text)
loadKV db sessionId k = do
  let sql = "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ?"
  withPreparedStatement db sql ("loadKV key=" <> k <> ", session=" <> sessionId) $ \stmt -> do
    _ <- NSQL.bindText stmt 1 sessionId
    _ <- NSQL.bindText stmt 2 k
    hasRow <- NSQL.stepRow stmt
    if hasRow
      then Just <$> NSQL.columnTextLenient stmt 0
      else pure Nothing

persistTurnQuality :: NSQL.Database -> Text -> TurnProjection -> IO ()
persistTurnQuality db sessionId p = do
  let sql = "INSERT INTO turn_quality(session_id, turn, parser_mode, parser_confidence, parser_errors, planner_mode, planner_decision, atom_register, atom_load, scene_pressure, scene_request, scene_stance, render_lane, render_style, legitimacy_status, legitimacy_reason, warranted_mode, decision_disposition, owner_family, owner_force, shadow_status, shadow_snapshot_id, shadow_divergence_kind, shadow_family, shadow_force, shadow_message, replay_trace_json, divergence) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
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

-- | Persisted state keeps only canonical authority plus compatibility-retained
-- fields. Derived governance views and runtime-local carry-over are stripped.
--
-- Truth-contract policy: persistence cleanup NEVER manufactures truth-contract
-- authority. 'ssTruthContractStatus' is preserved verbatim here — an authoritative
-- status (Canonical/Assembled) is never downgraded, and a non-authoritative
-- provenance marker (recovery/fallback/shim/defaulted/legacy/generated) is never
-- upgraded or collapsed into another marker. Authority is only ever earned by an
-- explicit upstream authority step, not by the act of persisting. Restart-authority
-- demotion (semantic anchor / last-turn-decision strip) is the RESTORE path's job
-- ('demoteNonAuthoritativeRestartCarry'), not this SAVE-path cleanup.
canonicalizePersistedState :: SystemState -> SystemState
canonicalizePersistedState ss =
  let selfState' = (ssSelfState ss) { selfPerspectiveRegistry = emptyPerspectiveRegistry }
  in ss
    { ssIdentity = canonicalizePersistedIdentityState (ssIdentity ss)
    , ssSemantic = canonicalizePersistedSemanticState (ssSemantic ss)
    , ssSelfState = selfState'
    , ssGovernanceProjection = ssGovernanceProjection emptySystemState
    , ssOutputMode = DialogueOutput
    , ssGovernanceRuntimeFault = Nothing
    }

-- | Compatibility-only identity fields are cleared before persistence.
-- Canonical identity authority lives in ego/claims/orbital memory; the last
-- guard report is runtime-local carry-over and not persisted as authority.
canonicalizePersistedIdentityState :: IdentityState -> IdentityState
canonicalizePersistedIdentityState ids =
  ids { idsLastGuardReport = Nothing }

-- | Semantic anchor and last turn decision are restart-safe only under
-- authoritative truth contours. They may remain in persisted storage for
-- compatibility/observability, but non-authoritative restart admission must
-- not let them re-enter first-turn behavior as if they were canonical truth.
canonicalizePersistedSemanticState :: SemanticState -> SemanticState
canonicalizePersistedSemanticState = id

-- | Rebuild only fields with an explicit canonical source. Today that is the
-- governance-derived view layer reconstructed from authoritative history.
-- Semantic carry-forward fields without a canonical rebuild source are demoted
-- on non-authoritative restart contours so they do not regain restart
-- authority through bootstrap/hydration.
rebuildDerivedViewsAfterLoad :: SystemState -> Either Text SystemState
rebuildDerivedViewsAfterLoad ss
  | persistedTruthIsAuthoritative (ssTruthContractStatus ss) =
      rebuildGovernedSystemState ss
  | otherwise =
      Right (demoteNonAuthoritativeRestartCarry ss)

demoteNonAuthoritativeRestartCarry :: SystemState -> SystemState
demoteNonAuthoritativeRestartCarry ss =
  ss
    { ssSemantic =
        (ssSemantic ss)
          { semSemanticAnchor = Nothing
          , semLastTurnDecision = Nothing
          }
    }

decodePersistedState :: Text -> IO (Either String SystemState)
decodePersistedState blob = do
  mStrict <- lookupEnv "QXFX0_STRICT_DECODE"
  let strictMode = maybe False (\v -> v == "true" || v == "1") mStrict
      bytes = TE.encodeUtf8 blob
      validateStrict obj
        | not strictMode = Right ()
        | otherwise =
            let allRequiredFields =
                  [ "schemaVersion", "history", "rawInputHistory", "turnCount"
                  , "lastTopic", "lastFamily", "lastForce", "lastLayer"
                  , "lastEmbedding", "consecutiveReflect", "recentFamilies"
                  , "activeScene", "sessionId", "stateOrigin", "ssSelfState"
                  , "morphology", "learningNeedState", "knowledgeTree"
                  , "truthContractStatus", "dialogueOutcomeLearning"
                  , "dialogueThread", "dialogueCommitmentLedger", "dialoguePhase"
                  , "speechPolicyState", "beliefStore", "governanceHistory"
                  ]
                missing = filter (\k -> not (KM.member (AK.fromText k) obj)) allRequiredFields
            in if null missing
               then Right ()
               else Left ("strict_decode_missing_required_fields: " <> show missing)
  -- Canonical write shape is PersistenceEnvelope (versioned state).
  -- Bare top-level SystemState is accepted as a legacy read fallback.
  case Aeson.decode (BL.fromStrict bytes) :: Maybe Aeson.Object of
    Just obj -> do
      case validateStrict obj of
        Left err -> pure (Left err)
        Right () ->
          case Aeson.eitherDecodeStrict bytes of
            Right (PersistenceEnvelope _ ss) -> pure (Right ss)
            Left _ ->
              case Aeson.eitherDecodeStrict bytes of
                Right ss -> pure (Right ss)
                Left e -> pure (Left e)
    Nothing ->
      pure (Left "strict_decode_failed_to_parse_json_object")

loadStateRevisionDirect :: NSQL.Database -> Text -> IO Int
loadStateRevisionDirect db sessionId = do
  let sql = "SELECT state_revision FROM runtime_sessions WHERE id = ?"
  withPreparedStatement db sql ("loadStateRevision session=" <> sessionId) $ \stmt -> do
    _ <- NSQL.bindText stmt 1 sessionId
    hasRow <- NSQL.stepRow stmt
    if hasRow
      then NSQL.columnInt stmt 0
      else pure 0

sqliteChanges :: NSQL.Database -> IO Int
sqliteChanges db =
  withPreparedStatement db "SELECT changes()" "sqlite_changes" $ \stmt -> do
    hasRow <- NSQL.stepRow stmt
    if hasRow then NSQL.columnInt stmt 0 else pure 0

normalizeReplayProvenanceStatus :: ReplayProvenanceStatus -> AuthorityClass -> ReplayProvenanceStatus
normalizeReplayProvenanceStatus replayStatus authority
  | authority `elem` [AuthorityGeneratedArtifact, AuthorityLegacyIncomplete] = ReplayProvenanceLegacyIncomplete
  | otherwise = replayStatus
