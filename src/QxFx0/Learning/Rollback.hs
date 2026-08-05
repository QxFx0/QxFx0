{-# LANGUAGE OverloadedStrings #-}

-- | Explicit rollback for externally proposed learning. Rollback is
-- request-scoped and only removes runtime-projection evidence attributable to
-- that request's exact relation and ownership scope.
module QxFx0.Learning.Rollback
  ( rollbackLearningRequest
  ) where

import Control.Exception (mask_, onException)
import Control.Monad (forM, unless)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)

import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement
  ( TxStmt
  , bindInt64OrFail
  , bindTextOrFail
  , prepareTx
  , stepOrFail
  , txsStmt
  )
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , LearningEventSource(..)
  , ensureLearningEventsSchema
  , insertLearningEventsOnConnection
  )
import QxFx0.Semantic.Network.Types (EdgeNamespace(..))

data RollbackShape = RollbackShape
  { rsTopic :: !Text
  , rsSessionId :: !(Maybe Text)
  , rsFrom :: !Text
  , rsTo :: !Text
  , rsRelation :: !Text
  , rsNamespace :: !Text
  , rsOwner :: !Text
  , rsContributions :: !Int
  }

-- | Retire every exact admission/corroboration contribution from one request.
-- There is no history cap. Projection mutation and retirement audit records
-- share one immediate transaction, so a crash cannot expose half a rollback.
rollbackLearningRequest :: QxFx0DB -> Text -> IO Int
rollbackLearningRequest db requestId = do
  ensureLearningEventsSchema db
  result <- withDB (qdbPath db) $ \conn -> withImmediateTransaction conn $ do
    shapes <- loadRequestShapes conn requestId
    now <- getCurrentTime
    retired <- forM shapes $ \shape -> do
      alreadyRetired <- shapeAlreadyRetired conn requestId shape
      if alreadyRetired
        then pure Nothing
        else do
          remaining <- countIndependentEvidence conn requestId shape
          if remaining == 0
            then deleteProjectionShape conn shape
            else subtractProjectionContributions conn shape
          pure (Just LearningEvent
            { leTimestamp = now
            , leSessionId = rsSessionId shape
            , leTurnSeq = Nothing
            , leRequestId = requestId
            , leTopic = rsTopic shape
            , leKind = EdgeRetired
            , leSource = LesHumanCorrection
            , leEdgeFrom = Just (rsFrom shape)
            , leEdgeTo = Just (rsTo shape)
            , leProvenance = Nothing
            , leConfidence = Nothing
            , leCoOccurrence = Nothing
            , leReason = Just (rollbackReason (rsRelation shape))
            , lePromptHash = Nothing
            , leResponseHash = Nothing
            , leModel = Nothing
            , leParserDecision = Nothing
            , leAdmissionDecision = Just "operator_rollback"
            , leEvidenceSource = Just "human_operator"
            , leEdgeNamespace = namespaceFromText (rsNamespace shape)
            , leEdgeOwner = Just (rsOwner shape)
            })
    let events = [event | Just event <- retired]
    insertLearningEventsOnConnection conn events
    pure (length events)
  either (fail . T.unpack) pure result

loadRequestShapes :: NSQL.Database -> Text -> IO [RollbackShape]
loadRequestShapes conn requestId = do
  prepared <- NSQL.prepare conn
    "SELECT topic, session_id, edge_from, edge_to, reason, COALESCE(edge_namespace, CASE WHEN session_id IS NULL THEN 'global' ELSE 'session_local' END), COALESCE(edge_owner, CASE WHEN session_id IS NULL THEN 'legacy_global' ELSE session_id END) FROM learning_events WHERE request_id=? AND kind IN ('edge_admitted','edge_corroborated') AND edge_from IS NOT NULL AND edge_to IS NOT NULL ORDER BY id ASC"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 requestId
      rows <- collect stmt []
      pure (M.elems (M.fromListWith combine [(shapeKey row, row) | row <- rows]))
  where
    collect stmt acc = do
      found <- NSQL.stepRow stmt
      if not found
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          topic <- NSQL.columnText stmt 0
          sessionId <- columnTextMaybe stmt 1
          edgeFrom <- NSQL.columnText stmt 2
          edgeTo <- NSQL.columnText stmt 3
          reason <- fromMaybe "" <$> columnTextMaybe stmt 4
          namespace <- NSQL.columnText stmt 5
          owner <- NSQL.columnText stmt 6
          case relationTypeFromReason reason of
            Nothing -> collect stmt acc
            Just relation -> collect stmt
              (RollbackShape topic sessionId edgeFrom edgeTo relation namespace owner 1 : acc)
    combine newer older = older
      { rsContributions = rsContributions older + rsContributions newer }

shapeKey :: RollbackShape -> (Text, Text, Text, Text, Text, Text)
shapeKey shape =
  ( rsFrom shape, rsTo shape, rsRelation shape, rsNamespace shape
  , fromMaybe "" (rsSessionId shape), rsOwner shape
  )

shapeAlreadyRetired :: NSQL.Database -> Text -> RollbackShape -> IO Bool
shapeAlreadyRetired conn requestId shape = do
  stmt <- prepareShapeQuery conn "rollback_shape_already_retired"
    "SELECT COUNT(*) FROM learning_events WHERE request_id=? AND kind='edge_retired' AND admission_decision='operator_rollback' AND edge_from=? AND edge_to=? AND reason=? AND COALESCE(edge_namespace, CASE WHEN session_id IS NULL THEN 'global' ELSE 'session_local' END)=? AND COALESCE(edge_owner, CASE WHEN session_id IS NULL THEN 'legacy_global' ELSE session_id END)=? AND COALESCE(session_id,'')=?"
    requestId shape
  found <- NSQL.stepRow (txsStmt stmt)
  count <- if found then NSQL.columnInt (txsStmt stmt) 0 else pure 0
  NSQL.finalize (txsStmt stmt)
  pure (count > 0)

countIndependentEvidence :: NSQL.Database -> Text -> RollbackShape -> IO Int
countIndependentEvidence conn requestId shape = do
  stmt <- prepareShapeQuery conn "rollback_independent_evidence"
    "SELECT COUNT(*) FROM learning_events le WHERE le.request_id<>? AND le.kind IN ('edge_admitted','edge_corroborated') AND le.edge_from=? AND le.edge_to=? AND instr(COALESCE(le.reason,''), ?)>0 AND COALESCE(le.edge_namespace, CASE WHEN le.session_id IS NULL THEN 'global' ELSE 'session_local' END)=? AND COALESCE(le.edge_owner, CASE WHEN le.session_id IS NULL THEN 'legacy_global' ELSE le.session_id END)=? AND COALESCE(le.session_id,'')=? AND NOT EXISTS (SELECT 1 FROM learning_events rr WHERE rr.request_id=le.request_id AND rr.kind='edge_retired' AND rr.admission_decision='operator_rollback' AND rr.edge_from=le.edge_from AND rr.edge_to=le.edge_to AND rr.reason=? AND COALESCE(rr.edge_namespace, CASE WHEN rr.session_id IS NULL THEN 'global' ELSE 'session_local' END)=COALESCE(le.edge_namespace, CASE WHEN le.session_id IS NULL THEN 'global' ELSE 'session_local' END) AND COALESCE(rr.edge_owner, CASE WHEN rr.session_id IS NULL THEN 'legacy_global' ELSE rr.session_id END)=COALESCE(le.edge_owner, CASE WHEN le.session_id IS NULL THEN 'legacy_global' ELSE le.session_id END) AND COALESCE(rr.session_id,'')=COALESCE(le.session_id,''))"
    requestId shape
  bindTextOrFail stmt 8 (rollbackReason (rsRelation shape))
  found <- NSQL.stepRow (txsStmt stmt)
  count <- if found then NSQL.columnInt (txsStmt stmt) 0 else pure 0
  NSQL.finalize (txsStmt stmt)
  pure count

prepareShapeQuery :: NSQL.Database -> Text -> Text -> Text -> RollbackShape -> IO TxStmt
prepareShapeQuery conn label sql requestId shape = do
  stmt <- prepareTx conn label sql
  bindTextOrFail stmt 1 requestId
  bindTextOrFail stmt 2 (rsFrom shape)
  bindTextOrFail stmt 3 (rsTo shape)
  bindTextOrFail stmt 4 (if "instr(" `T.isInfixOf` sql then relationMarker (rsRelation shape) else rollbackReason (rsRelation shape))
  bindTextOrFail stmt 5 (rsNamespace shape)
  bindTextOrFail stmt 6 (rsOwner shape)
  bindTextOrFail stmt 7 (fromMaybe "" (rsSessionId shape))
  pure stmt

deleteProjectionShape :: NSQL.Database -> RollbackShape -> IO ()
deleteProjectionShape conn shape = do
  stmt <- projectionShapeStatement conn "rollback_projection_delete"
    "DELETE FROM semantic_edges_runtime WHERE edge_from=? AND edge_to=? AND relation_type=? AND namespace=? AND owner=? AND COALESCE(session_id,'')=?"
    shape
  stepOrFail stmt

subtractProjectionContributions :: NSQL.Database -> RollbackShape -> IO ()
subtractProjectionContributions conn shape = do
  stmt <- projectionShapeStatement conn "rollback_projection_subtract"
    "UPDATE semantic_edges_runtime SET co_occurrence=MAX(1, co_occurrence-?) WHERE edge_from=? AND edge_to=? AND relation_type=? AND namespace=? AND owner=? AND COALESCE(session_id,'')=?"
    shape
  -- Shift the shape bindings right for the leading contribution count.
  bindInt64OrFail stmt 1 (fromIntegral (rsContributions shape))
  bindTextOrFail stmt 2 (rsFrom shape)
  bindTextOrFail stmt 3 (rsTo shape)
  bindTextOrFail stmt 4 (rsRelation shape)
  bindTextOrFail stmt 5 (rsNamespace shape)
  bindTextOrFail stmt 6 (rsOwner shape)
  bindTextOrFail stmt 7 (fromMaybe "" (rsSessionId shape))
  stepOrFail stmt

projectionShapeStatement :: NSQL.Database -> Text -> Text -> RollbackShape -> IO TxStmt
projectionShapeStatement conn label sql shape = do
  stmt <- prepareTx conn label sql
  unless ("co_occurrence-?" `T.isInfixOf` sql) $ do
    bindTextOrFail stmt 1 (rsFrom shape)
    bindTextOrFail stmt 2 (rsTo shape)
    bindTextOrFail stmt 3 (rsRelation shape)
    bindTextOrFail stmt 4 (rsNamespace shape)
    bindTextOrFail stmt 5 (rsOwner shape)
    bindTextOrFail stmt 6 (fromMaybe "" (rsSessionId shape))
  pure stmt

relationTypeFromReason :: Text -> Maybe Text
relationTypeFromReason reason =
  let marker = "relation_type="
      (_, suffix) = T.breakOn marker reason
  in if T.null suffix
       then Nothing
       else Just (T.takeWhile (/= ';') (T.drop (T.length marker) suffix))

relationMarker :: Text -> Text
relationMarker relation = "relation_type=" <> relation

rollbackReason :: Text -> Text
rollbackReason relation = "explicit_learning_request_rollback;" <> relationMarker relation

namespaceFromText :: Text -> Maybe EdgeNamespace
namespaceFromText "global" = Just NamespaceGlobal
namespaceFromText "user_local" = Just NamespaceUserLocal
namespaceFromText "session_local" = Just NamespaceSessionLocal
namespaceFromText _ = Nothing

columnTextMaybe :: NSQL.Statement -> Int -> IO (Maybe Text)
columnTextMaybe stmt index = do
  isNull <- NSQL.columnIsNull stmt (fromIntegral index)
  if isNull then pure Nothing else Just <$> NSQL.columnText stmt (fromIntegral index)

withImmediateTransaction :: NSQL.Database -> IO a -> IO a
withImmediateTransaction conn action = mask_ $ do
  begun <- NSQL.execSql conn "BEGIN IMMEDIATE;"
  either (fail . T.unpack) pure begun
  value <- action `onException` rollbackBestEffort conn
  committed <- NSQL.execSql conn "COMMIT;"
  case committed of
    Right () -> pure value
    Left err -> rollbackBestEffort conn >> fail (T.unpack err)

rollbackBestEffort :: NSQL.Database -> IO ()
rollbackBestEffort conn = do
  _ <- NSQL.execSql conn "ROLLBACK;"
  pure ()
