{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Learning.Events
  ( LearningEventKind(..)
  , LearningEventSource(..)
  , LearningEvent(..)
  , RuntimeEvidence(..)
  , learningEventKindText
  , learningEventSourceText
  , learningEventKindFromText
  , learningEventSourceFromText
  , provenanceFromText
  , ensureLearningEventsSchema
  , recordLearningEvent
  , recordLearningEvents
  , recordLearningEventsOnConnection
  , insertLearningEventsOnConnection
  , loadLearningEvents
  , loadLearningEventsFiltered
  , loadRuntimeEvidenceOnConnection
  , diffRuntimeFeedbackEvents
  ) where

import Control.DeepSeq (NFData)
import Control.Exception (SomeException, catch)
import Control.Monad (join, unless)
import Data.Aeson (FromJSON, ToJSON)
import Data.Int (Int64)
import Data.Maybe (isJust)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Foreign.C.Types (CInt)
import GHC.Generics (Generic)

import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement
  ( TxStmt
  , txsStmt
  , bindDoubleOrFail
  , bindInt64OrFail
  , bindNullOrFail
  , bindTextOrFail
  , prepareTx
  , stepOrFail
  )
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )
import QxFx0.Learning.Quarantine (provenanceText)

data LearningEventKind
  = LlmEdgeProposed
  | EdgeAdmitted
  | EdgeCorroborated
  | EdgeRejected
  | EdgeQuarantined
  | RuntimeFeedbackPositive
  | RuntimeFeedbackNegative
  | RuntimeFeedbackConflict
  | EdgePromoted
  | EdgeDecayed
  | EdgeRetired
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data LearningEventSource
  = LesAutonomousApply
  | LesWorker
  | LesRuntimeFeedback
  | LesHumanCorrection
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data LearningEvent = LearningEvent
  { leTimestamp      :: !UTCTime
  , leSessionId      :: !(Maybe Text)
  , leTurnSeq        :: !(Maybe Int)
  , leRequestId      :: !Text
  , leTopic          :: !Text
  , leKind           :: !LearningEventKind
  , leSource         :: !LearningEventSource
  , leEdgeFrom       :: !(Maybe Text)
  , leEdgeTo         :: !(Maybe Text)
  , leProvenance     :: !(Maybe EdgeProvenance)
  , leConfidence     :: !(Maybe Double)
  , leCoOccurrence   :: !(Maybe Int)
  , leReason         :: !(Maybe Text)
  , lePromptHash     :: !(Maybe Text)
  , leResponseHash   :: !(Maybe Text)
  , leModel          :: !(Maybe Text)
  , leParserDecision :: !(Maybe Text)
  , leAdmissionDecision :: !(Maybe Text)
  , leEvidenceSource :: !(Maybe Text)
  , leEdgeNamespace  :: !(Maybe EdgeNamespace)
  , leEdgeOwner      :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Provider evidence that has crossed the governed runtime admission path.
-- Request and response identities are kept separate from structural graph
-- lineage so corroboration cannot be inferred from an edge row alone.
data RuntimeEvidence = RuntimeEvidence
  { reEdgeFrom     :: !Text
  , reEdgeTo       :: !Text
  , reRelationType :: !Text
  , reRequestId    :: !Text
  , reResponseHash :: !Text
  , rePromptHash :: !Text
  , reModel :: !Text
  , reParserDecision :: !Text
  , reAdmissionDecision :: !Text
  , reEvidenceSource :: !Text
  , reEventTimestamp :: !Int64
  , reNamespace :: !Text
  , reSessionId :: !(Maybe Text)
  , reOwner :: !Text
  }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

learningEventKindText :: LearningEventKind -> Text
learningEventKindText LlmEdgeProposed = "llm_edge_proposed"
learningEventKindText EdgeAdmitted = "edge_admitted"
learningEventKindText EdgeCorroborated = "edge_corroborated"
learningEventKindText EdgeRejected = "edge_rejected"
learningEventKindText EdgeQuarantined = "edge_quarantined"
learningEventKindText RuntimeFeedbackPositive = "runtime_feedback_positive"
learningEventKindText RuntimeFeedbackNegative = "runtime_feedback_negative"
learningEventKindText RuntimeFeedbackConflict = "runtime_feedback_conflict"
learningEventKindText EdgePromoted = "edge_promoted"
learningEventKindText EdgeDecayed = "edge_decayed"
learningEventKindText EdgeRetired = "edge_retired"

learningEventSourceText :: LearningEventSource -> Text
learningEventSourceText LesAutonomousApply = "autonomous_apply"
learningEventSourceText LesWorker = "worker"
learningEventSourceText LesRuntimeFeedback = "runtime_feedback"
learningEventSourceText LesHumanCorrection = "human_correction"

learningEventKindFromText :: Text -> Maybe LearningEventKind
learningEventKindFromText t = lookup t
  [ (learningEventKindText k, k)
  | k <-
       [ LlmEdgeProposed, EdgeAdmitted, EdgeCorroborated, EdgeRejected, EdgeQuarantined
      , RuntimeFeedbackPositive, RuntimeFeedbackNegative, RuntimeFeedbackConflict
      , EdgePromoted, EdgeDecayed, EdgeRetired
      ]
  ]

learningEventSourceFromText :: Text -> Maybe LearningEventSource
learningEventSourceFromText t = lookup t
  [ (learningEventSourceText s, s)
  | s <- [LesAutonomousApply, LesWorker, LesRuntimeFeedback, LesHumanCorrection]
  ]

provenanceFromText :: Text -> Maybe EdgeProvenance
provenanceFromText t = lookup t
  [ (provenanceText p, p)
  | p <-
      [ ProvenanceCurated, ProvenanceCorpus, ProvenanceSubstrate, ProvenanceIngested
      , ProvenanceRuntimeLLM, ProvenanceSelfPlay, ProvenanceDialogueFeedback
      , ProvenanceHumanCorrection, ProvenanceDerived
      ]
  ]

ensureLearningEventsSchema :: QxFx0DB -> IO ()
ensureLearningEventsSchema db = do
  result <- withDB (qdbPath db) $ \conn -> do
    schema <- prepareTx conn "ensure_learning_events_schema"
      "CREATE TABLE IF NOT EXISTS learning_events (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, session_id TEXT, turn_seq INTEGER, request_id TEXT NOT NULL, topic TEXT NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL, edge_from TEXT, edge_to TEXT, provenance TEXT, confidence REAL, co_occurrence INTEGER, reason TEXT, prompt_hash TEXT, response_hash TEXT, model TEXT, parser_decision TEXT, admission_decision TEXT, evidence_source TEXT, edge_namespace TEXT, edge_owner TEXT)"
    stepOrFail schema
    mapM_ (ensureNullableColumn conn "learning_events")
      [ ("model", "TEXT")
      , ("parser_decision", "TEXT")
      , ("admission_decision", "TEXT")
      , ("evidence_source", "TEXT")
      , ("edge_namespace", "TEXT")
      , ("edge_owner", "TEXT")
      ]
    idxTs <- prepareTx conn "ensure_learning_events_idx_ts"
      "CREATE INDEX IF NOT EXISTS idx_learning_events_ts ON learning_events(ts)"
    stepOrFail idxTs
    idxTopic <- prepareTx conn "ensure_learning_events_idx_topic"
      "CREATE INDEX IF NOT EXISTS idx_learning_events_topic ON learning_events(topic)"
    stepOrFail idxTopic
    idxEdge <- prepareTx conn "ensure_learning_events_idx_edge"
      "CREATE INDEX IF NOT EXISTS idx_learning_events_edge ON learning_events(edge_from, edge_to)"
    stepOrFail idxEdge
  either (fail . T.unpack) pure result

-- | Module-owned schema evolution for additive audit fields. Existing event
-- rows remain readable but cannot satisfy promotion's complete-lineage gate.
ensureNullableColumn :: NSQL.Database -> Text -> (Text, Text) -> IO ()
ensureNullableColumn conn tableName (columnName, columnType) = do
  prepared <- NSQL.prepare conn
    ("SELECT 1 FROM pragma_table_info('" <> tableName <> "') WHERE name = ? LIMIT 1")
  exists <- case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 columnName
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found
  unless exists $ do
    altered <- NSQL.execSql conn
      ("ALTER TABLE " <> tableName <> " ADD COLUMN " <> columnName <> " " <> columnType)
    either (fail . T.unpack) pure altered

recordLearningEvent :: QxFx0DB -> LearningEvent -> IO ()
recordLearningEvent db event = recordLearningEvents db [event]

-- | Append many learning events in a single connection and transaction.
--
-- Unlike calling 'recordLearningEvent' repeatedly (which opens a connection
-- per event), this opens the database once, wraps the inserts in a
-- transaction, and reuses one prepared statement. This keeps the per-turn
-- cost bounded to O(1) connections even when a turn reinforces many runtime
-- edges, which matters for long-running autonomous-learning workloads.
recordLearningEvents :: QxFx0DB -> [LearningEvent] -> IO ()
recordLearningEvents _ [] = pure ()
recordLearningEvents db events = do
  outer <- withDB (qdbPath db) $ \conn -> insertEventsIntoConnection conn events
  either (fail . T.unpack) pure (join outer)

-- | Append many learning events using an already-open connection. This avoids
-- opening a second SQLite connection, which is unsafe when the caller already
-- holds an open connection to the same database.
recordLearningEventsOnConnection :: NSQL.Database -> [LearningEvent] -> IO ()
recordLearningEventsOnConnection _ [] = pure ()
recordLearningEventsOnConnection conn events = do
  result <- insertEventsIntoConnection conn events
  either (fail . T.unpack) pure result

insertEventsIntoConnection :: NSQL.Database -> [LearningEvent] -> IO (Either Text ())
insertEventsIntoConnection conn events = do
  beginResult <- NSQL.execSql conn "BEGIN TRANSACTION;"
  case beginResult of
    Left err -> pure (Left err)
    Right () -> do
      insertResult <- tryInsertEvents conn
      case insertResult of
        Left err -> do
          _ <- NSQL.execSql conn "ROLLBACK;"
          pure (Left err)
        Right () -> NSQL.execSql conn "COMMIT;"
  where
    tryInsertEvents c = (Right <$> insertLearningEventsOnConnection c events) `catch` \e -> pure (Left (T.pack (show (e :: SomeException))))

-- | Insert events without opening or committing a transaction.  Intended for
-- callers which already own the broader atomic persistence boundary.
insertLearningEventsOnConnection :: NSQL.Database -> [LearningEvent] -> IO ()
insertLearningEventsOnConnection conn = mapM_ (insertOneEvent conn)

insertOneEvent :: NSQL.Database -> LearningEvent -> IO ()
insertOneEvent c event = do
  stmt <- prepareTx c "insert_learning_event"
    "INSERT INTO learning_events (ts, session_id, turn_seq, request_id, topic, kind, source, edge_from, edge_to, provenance, confidence, co_occurrence, reason, prompt_hash, response_hash, model, parser_decision, admission_decision, evidence_source, edge_namespace, edge_owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  bindInt64OrFail stmt 1 (utcMicros (leTimestamp event))
  bindMaybeText stmt 2 (leSessionId event)
  bindMaybeInt stmt 3 (leTurnSeq event)
  bindTextOrFail stmt 4 (leRequestId event)
  bindTextOrFail stmt 5 (leTopic event)
  bindTextOrFail stmt 6 (learningEventKindText (leKind event))
  bindTextOrFail stmt 7 (learningEventSourceText (leSource event))
  bindMaybeText stmt 8 (leEdgeFrom event)
  bindMaybeText stmt 9 (leEdgeTo event)
  bindMaybeText stmt 10 (provenanceText <$> leProvenance event)
  bindMaybeDouble stmt 11 (leConfidence event)
  bindMaybeInt stmt 12 (leCoOccurrence event)
  bindMaybeText stmt 13 (leReason event)
  bindMaybeText stmt 14 (lePromptHash event)
  bindMaybeText stmt 15 (leResponseHash event)
  bindMaybeText stmt 16 (leModel event)
  bindMaybeText stmt 17 (leParserDecision event)
  bindMaybeText stmt 18 (leAdmissionDecision event)
  bindMaybeText stmt 19 (leEvidenceSource event)
  bindMaybeText stmt 20 (namespaceText <$> leEdgeNamespace event)
  bindMaybeText stmt 21 (leEdgeOwner event)
  stepOrFail stmt

bindMaybeText :: TxStmt -> Int -> Maybe Text -> IO ()
bindMaybeText stmt ix = maybe (bindNullOrFail stmt (fromIntegral ix)) (bindTextOrFail stmt (fromIntegral ix))

bindMaybeInt :: TxStmt -> Int -> Maybe Int -> IO ()
bindMaybeInt stmt ix = maybe (bindNullOrFail stmt (fromIntegral ix)) (bindInt64OrFail stmt (fromIntegral ix) . fromIntegral)

bindMaybeDouble :: TxStmt -> Int -> Maybe Double -> IO ()
bindMaybeDouble stmt ix = maybe (bindNullOrFail stmt (fromIntegral ix)) (bindDoubleOrFail stmt (fromIntegral ix))

utcMicros :: UTCTime -> Int64
utcMicros = round . (* 1000000) . realToFrac . utcTimeToPOSIXSeconds

microsToUtc :: Int64 -> UTCTime
microsToUtc = posixSecondsToUTCTime . (/ 1000000) . fromIntegral

-- | Load the most recent learning events (ordered oldest -> newest), capped
-- by the supplied limit. Rows whose kind/source cannot be parsed are skipped.
loadLearningEvents :: QxFx0DB -> Int -> IO [LearningEvent]
loadLearningEvents db limit = loadLearningEventsFiltered db limit Nothing

-- | Load learning events ordered oldest -> newest, optionally filtered by
-- topic and capped by a limit. When 'topic' is 'Nothing' all events are
-- returned (respecting 'limit'). Rows whose kind/source cannot be parsed are
-- skipped. This is the read side used by inspection tooling (e.g. the
-- @--learning-events@ CLI) and the eventual L2 replay builder.
loadLearningEventsFiltered :: QxFx0DB -> Int -> Maybe Text -> IO [LearningEvent]
loadLearningEventsFiltered db limit mTopic = do
  result <- withDB (qdbPath db) $ \conn -> do
    let (whereSql, topicArg) =
          case mTopic of
            Nothing -> ("", Nothing)
            Just t  -> (" WHERE topic = ?", Just t)
        sql = "SELECT ts, session_id, turn_seq, request_id, topic, kind, source, edge_from, edge_to, provenance, confidence, co_occurrence, reason, prompt_hash, response_hash, model, parser_decision, admission_decision, evidence_source, edge_namespace, edge_owner FROM learning_events"
                <> whereSql <> " ORDER BY id DESC LIMIT ?"
    mStmt <- NSQL.prepare conn sql
    case mStmt of
      Left err -> pure (Left err)
      Right stmt -> do
        case topicArg of
          Nothing  -> pure ()
          Just t   -> NSQL.bindText stmt 1 t >>= either (fail . T.unpack) pure
        _ <- NSQL.bindInt64 stmt (if isJust topicArg then 2 else 1) (fromIntegral (max 0 limit))
        rows <- collectRows stmt
        NSQL.finalize stmt
        pure (Right rows)
  either (fail . T.unpack) pure (join result)

-- | Load complete provider evidence already admitted or corroborated for the
-- runtime graph. Incomplete legacy rows are intentionally excluded.
loadRuntimeEvidenceOnConnection :: NSQL.Database -> IO [RuntimeEvidence]
loadRuntimeEvidenceOnConnection conn = do
  prepared <- NSQL.prepare conn
    "SELECT edge_from, edge_to, request_id, response_hash, reason, prompt_hash, model, parser_decision, admission_decision, evidence_source, ts, COALESCE(edge_namespace, CASE WHEN session_id IS NULL THEN 'global' ELSE 'session_local' END), session_id, COALESCE(edge_owner, CASE WHEN session_id IS NULL THEN 'legacy_global' ELSE session_id END) FROM learning_events WHERE kind IN ('edge_admitted', 'edge_corroborated') AND admission_decision IN ('runtime_admitted', 'runtime_corroborated') AND request_id <> '' AND prompt_hash IS NOT NULL AND prompt_hash <> '' AND response_hash IS NOT NULL AND response_hash <> '' AND model IS NOT NULL AND model <> '' AND parser_decision IS NOT NULL AND parser_decision <> '' AND evidence_source IS NOT NULL AND evidence_source <> ''"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> collectRuntimeEvidence stmt []
  where
    collectRuntimeEvidence stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          mFrom <- columnTextMaybe stmt 0
          mTo <- columnTextMaybe stmt 1
          requestId <- NSQL.columnText stmt 2
          responseHash <- NSQL.columnText stmt 3
          mReason <- columnTextMaybe stmt 4
          promptHash <- NSQL.columnText stmt 5
          model <- NSQL.columnText stmt 6
          parserDecision <- NSQL.columnText stmt 7
          admissionDecision <- NSQL.columnText stmt 8
          evidenceSource <- NSQL.columnText stmt 9
          eventTimestamp <- NSQL.columnInt64 stmt 10
          namespace <- NSQL.columnText stmt 11
          sessionId <- columnTextMaybe stmt 12
          owner <- NSQL.columnText stmt 13
          let mRelation = mReason >>= relationTypeFromReason
          case (mFrom, mTo, mRelation) of
            (Just edgeFrom, Just edgeTo, Just relationType) ->
              collectRuntimeEvidence stmt
                (RuntimeEvidence edgeFrom edgeTo relationType requestId responseHash promptHash model parserDecision admissionDecision evidenceSource eventTimestamp namespace sessionId owner : acc)
            _ -> collectRuntimeEvidence stmt acc

    relationTypeFromReason reason =
      let marker = "relation_type="
          (_, suffix) = T.breakOn marker reason
      in if T.null suffix
           then Nothing
           else Just (T.takeWhile (/= ';') (T.drop (T.length marker) suffix))

readRow :: NSQL.Statement -> IO (Maybe LearningEvent)
readRow stmt = do
  ts        <- NSQL.columnInt64 stmt 0
  sessionId <- columnTextMaybe stmt 1
  turnSeq   <- NSQL.columnIntMaybe stmt 2
  requestId <- NSQL.columnText stmt 3
  topic     <- NSQL.columnText stmt 4
  kindT     <- NSQL.columnText stmt 5
  sourceT   <- NSQL.columnText stmt 6
  edgeFrom  <- columnTextMaybe stmt 7
  edgeTo    <- columnTextMaybe stmt 8
  provT     <- columnTextMaybe stmt 9
  conf      <- NSQL.columnDoubleMaybe stmt 10
  coOcc     <- NSQL.columnIntMaybe stmt 11
  reason    <- columnTextMaybe stmt 12
  promptH   <- columnTextMaybe stmt 13
  responseH <- columnTextMaybe stmt 14
  model     <- columnTextMaybe stmt 15
  parserDecision <- columnTextMaybe stmt 16
  admissionDecision <- columnTextMaybe stmt 17
  evidenceSource <- columnTextMaybe stmt 18
  edgeNamespace <- columnTextMaybe stmt 19
  edgeOwner <- columnTextMaybe stmt 20
  pure $ do
    kind   <- learningEventKindFromText kindT
    source <- learningEventSourceFromText sourceT
    Just LearningEvent
      { leTimestamp    = microsToUtc (fromIntegral ts)
      , leSessionId    = sessionId
      , leTurnSeq      = turnSeq
      , leRequestId    = requestId
      , leTopic        = topic
      , leKind         = kind
      , leSource       = source
      , leEdgeFrom     = edgeFrom
      , leEdgeTo       = edgeTo
      , leProvenance   = provT >>= provenanceFromText
      , leConfidence   = conf
      , leCoOccurrence = coOcc
      , leReason       = reason
      , lePromptHash   = promptH
      , leResponseHash = responseH
      , leModel = model
      , leParserDecision = parserDecision
      , leAdmissionDecision = admissionDecision
      , leEvidenceSource = evidenceSource
      , leEdgeNamespace = edgeNamespace >>= namespaceFromText
      , leEdgeOwner = edgeOwner
        }

collectRows :: NSQL.Statement -> IO [LearningEvent]
collectRows stmt = go []
  where
    go acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then pure acc
        else do
          mEvent <- readRow stmt
          go (maybe acc (: acc) mEvent)

columnTextMaybe :: NSQL.Statement -> CInt -> IO (Maybe Text)
columnTextMaybe stmt idx = do
  isNull <- NSQL.columnIsNull stmt idx
  if isNull then pure Nothing else Just <$> NSQL.columnText stmt idx

-- | Derive runtime-feedback learning events from the pre/post semantic
-- networks of a single turn. This is the pure core of the L1 runtime-feedback
-- wiring: it inspects every edge that was 'ProvenanceRuntimeLLM' before the
-- turn and classifies how the turn changed it, without touching the pure
-- finalize boundary. The IO layer (see 'QxFx0.Runtime.Engine') records the
-- resulting events after the turn commits.
--
-- Classification (per pre-turn runtime-LLM edge, keyed by endpoints):
--
--   * edge removed          -> 'RuntimeFeedbackConflict'
--   * promoted to feedback  -> 'RuntimeFeedbackPositive' + 'EdgePromoted'
--   * co-occurrence rose     -> 'RuntimeFeedbackPositive'
--   * confidence fell        -> 'RuntimeFeedbackNegative'
--   * provenance changed via merge (neither runtime-LLM nor dialogue-feedback)
--     -> ignored (not a feedback outcome)
diffRuntimeFeedbackEvents
  :: UTCTime        -- ^ event timestamp
  -> Maybe Text     -- ^ session id
  -> Maybe Int      -- ^ turn sequence
  -> Text           -- ^ request id
  -> Text           -- ^ topic
  -> SemanticNetwork -- ^ pre-turn network
  -> SemanticNetwork -- ^ post-turn network
  -> [LearningEvent]
diffRuntimeFeedbackEvents ts sessionId turnSeq requestId topic before after =
  concatMap classify (M.toList (snEdges before))
  where
    afterEdges = snEdges after

    classify (key, pre)
      | seProvenance pre /= ProvenanceRuntimeLLM = []
      | otherwise =
          case M.lookup key afterEdges of
            Nothing ->
              [mkEvent RuntimeFeedbackConflict pre (Just "edge_removed_conflict")]
            Just post
              | seProvenance post == ProvenanceDialogueFeedback ->
                  [ mkEvent RuntimeFeedbackPositive post Nothing
                  , mkEvent EdgePromoted post (Just "runtime_llm_to_dialogue_feedback")
                  ]
              | seProvenance post /= ProvenanceRuntimeLLM -> []
              | seCoOccurrence post > seCoOccurrence pre ->
                  [mkEvent RuntimeFeedbackPositive post Nothing]
              | seConfidence post < seConfidence pre ->
                  [mkEvent RuntimeFeedbackNegative post Nothing]
              | otherwise -> []

    mkEvent kind edge reason = LearningEvent
      { leTimestamp    = ts
      , leSessionId    = sessionId
      , leTurnSeq      = turnSeq
      , leRequestId    = requestId
      , leTopic        = topic
      , leKind         = kind
      , leSource       = LesRuntimeFeedback
      , leEdgeFrom     = Just (seFrom edge)
      , leEdgeTo       = Just (seTo edge)
      , leProvenance   = Just (seProvenance edge)
      , leConfidence   = Just (seConfidence edge)
      , leCoOccurrence = Just (seCoOccurrence edge)
      , leReason       = reason
      , lePromptHash   = Nothing
      , leResponseHash = Nothing
      , leModel = Nothing
      , leParserDecision = Nothing
      , leAdmissionDecision = Nothing
      , leEvidenceSource = Nothing
      , leEdgeNamespace = seNamespace edge
      , leEdgeOwner = sessionId
      }

namespaceText :: EdgeNamespace -> Text
namespaceText NamespaceSessionLocal = "session_local"
namespaceText NamespaceUserLocal = "user_local"
namespaceText NamespaceGlobal = "global"

namespaceFromText :: Text -> Maybe EdgeNamespace
namespaceFromText "session_local" = Just NamespaceSessionLocal
namespaceFromText "user_local" = Just NamespaceUserLocal
namespaceFromText "global" = Just NamespaceGlobal
namespaceFromText _ = Nothing
