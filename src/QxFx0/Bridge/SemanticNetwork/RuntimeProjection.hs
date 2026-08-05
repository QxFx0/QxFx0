{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Bridge.SemanticNetwork.RuntimeProjection
  ( SemanticNetworkDelta
  , ensureRuntimeProjectionSchema
  , persistRuntimeEdge
  , persistRuntimeEdges
  , persistRuntimeEdgesOnConnection
  , corroborateRuntimeEdgeOnConnection
  , deleteRuntimeEdge
  , deleteRuntimeEdgeExact
  , deleteRuntimeEdgeExactConn
  , loadRuntimeEdgeProjection
  , loadAllRuntimeEdges
  , applyProjectionDelta
  , rebuildLearningProjection
  , namespaceText
  ) where

import Control.Applicative ((<|>))
import Control.Monad (join)
import Control.Monad (unless, when)
import Data.Int (Int64)
import Data.List (foldl')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Foreign.C.Types (CInt)
import GHC.Generics (Generic)

import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text.Encoding as TE

import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement
  ( TxStmt
  , txsStmt
  , bindDoubleOrFail
  , bindInt64OrFail
  , bindTextOrFail
  , prepareTx
  , stepOrFail
  , bindNullOrFail
  )
import QxFx0.Semantic.Network.Types
  ( DomainTag(..)
  , EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeRef
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , TemporalScope(..)
  , relationTypeWeight
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Learning.Quarantine (provenanceText)
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , provenanceFromText
  )
import QxFx0.ExceptionPolicy (mkSQLiteError, throwQxFx0)

ensureRuntimeProjectionSchema :: QxFx0DB -> IO ()
ensureRuntimeProjectionSchema db = do
  result <- withDB (qdbPath db) $ \conn -> do
    versions <- prepareTx conn "ensure_runtime_projection_versions"
      "CREATE TABLE IF NOT EXISTS learning_schema_versions (owner TEXT PRIMARY KEY, version INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
    stepOrFail versions
    schema <- prepareTx conn "ensure_runtime_projection_schema"
      "CREATE TABLE IF NOT EXISTS semantic_edges_runtime (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, weight REAL NOT NULL, co_occurrence INTEGER NOT NULL, relation_type TEXT, domain TEXT, temporal_scope TEXT, verb TEXT, rationale TEXT, lineage TEXT, confidence REAL NOT NULL, provenance TEXT NOT NULL, namespace TEXT NOT NULL DEFAULT 'global', session_id TEXT, owner TEXT NOT NULL DEFAULT 'legacy_global')"
    stepOrFail schema
    version <- runtimeProjectionSchemaVersion conn
    when (version > 2) (throwProjectionError "runtime projection schema is newer than this runtime")
    ensureProjectionColumn conn "lineage" "TEXT"
    ensureProjectionColumn conn "session_id" "TEXT"
    ensureProjectionColumn conn "owner" "TEXT"
    -- Explicit legacy policy: rows written before ownership existed are
    -- shared global observations. They must never be guessed into whichever
    -- session happens to run the migration first.
    when (version < 2) $ do
      migrated <- NSQL.execSql conn
        "UPDATE semantic_edges_runtime SET namespace='global', session_id=NULL, owner='legacy_global' WHERE owner IS NULL OR owner=''"
      either throwProjectionError pure migrated
      now <- getCurrentTime
      marker <- prepareTx conn "runtime_projection_schema_version"
        "INSERT INTO learning_schema_versions(owner, version, updated_at) VALUES('runtime_projection', 2, ?) ON CONFLICT(owner) DO UPDATE SET version=excluded.version, updated_at=excluded.updated_at"
      bindInt64OrFail marker 1 (utcMicros now)
      stepOrFail marker
    droppedEdgeIndex <- NSQL.execSql conn "DROP INDEX IF EXISTS idx_runtime_edge"
    either throwProjectionError pure droppedEdgeIndex
    idxEdge <- prepareTx conn "ensure_runtime_projection_idx_edge"
      "CREATE INDEX IF NOT EXISTS idx_runtime_edge ON semantic_edges_runtime(namespace, session_id, owner, edge_from, edge_to)"
    stepOrFail idxEdge
    idxTs <- prepareTx conn "ensure_runtime_projection_idx_ts"
      "CREATE INDEX IF NOT EXISTS idx_runtime_projection_ts ON semantic_edges_runtime(ts DESC)"
    stepOrFail idxTs
  either throwProjectionError pure result

runtimeProjectionSchemaVersion :: NSQL.Database -> IO Int
runtimeProjectionSchemaVersion conn = do
  prepared <- NSQL.prepare conn
    "SELECT version FROM learning_schema_versions WHERE owner='runtime_projection'"
  case prepared of
    Left err -> throwProjectionError err
    Right stmt -> do
      found <- NSQL.stepRow stmt
      version <- if found then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure version

ensureProjectionColumn :: NSQL.Database -> Text -> Text -> IO ()
ensureProjectionColumn conn columnName declaration = do
  prepared <- NSQL.prepare conn
    "SELECT 1 FROM pragma_table_info('semantic_edges_runtime') WHERE name=? LIMIT 1"
  exists <- case prepared of
    Left err -> throwProjectionError err
    Right stmt -> do
      bound <- NSQL.bindText stmt 1 columnName
      either throwProjectionError pure bound
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found
  unless exists $ do
    altered <- NSQL.execSql conn
      ("ALTER TABLE semantic_edges_runtime ADD COLUMN " <> columnName <> " " <> declaration)
    either throwProjectionError pure altered

persistRuntimeEdge :: QxFx0DB -> Text -> SemanticEdge -> IO ()
persistRuntimeEdge db sessionId edge = persistRuntimeEdges db sessionId [edge]

persistRuntimeEdges :: QxFx0DB -> Text -> [SemanticEdge] -> IO ()
persistRuntimeEdges _ _ [] = pure ()
persistRuntimeEdges db sessionId edges = do
  validateSessionOwner sessionId edges
  result <- withDB (qdbPath db) $ \conn -> do
    _ <- NSQL.execSql conn "BEGIN TRANSACTION;"
    persistRuntimeEdgesOnConnection conn sessionId edges
    _ <- NSQL.execSql conn "COMMIT;"
    pure ()
  either throwProjectionError pure result

-- | Insert runtime edges through a caller-owned transaction.  Governed
-- autonomous apply combines this with its events and job finalization.
persistRuntimeEdgesOnConnection :: NSQL.Database -> Text -> [SemanticEdge] -> IO ()
persistRuntimeEdgesOnConnection _ _ [] = pure ()
persistRuntimeEdgesOnConnection conn sessionId edges = do
  validateSessionOwner sessionId edges
  now <- getCurrentTime
  mapM_ (insertOneEdge conn now sessionId) edges

-- | Increment corroboration on the existing runtime edge without inserting a
-- second graph row. The exact relation and namespace are part of the key.
corroborateRuntimeEdgeOnConnection :: NSQL.Database -> Text -> SemanticEdge -> IO ()
corroborateRuntimeEdgeOnConnection conn sessionId edge = do
  validateSessionOwner sessionId [edge]
  now <- getCurrentTime
  stmt <- prepareTx conn "corroborate_runtime_edge"
    "UPDATE semantic_edges_runtime SET ts = ?, co_occurrence = co_occurrence + 1 WHERE id = (SELECT id FROM semantic_edges_runtime WHERE edge_from = ? AND edge_to = ? AND relation_type = ? AND provenance = 'runtime_llm' AND namespace = ? AND owner = ? AND (namespace <> 'session_local' OR session_id = ?) ORDER BY id DESC LIMIT 1)"
  bindInt64OrFail stmt 1 (utcMicros now)
  bindTextOrFail stmt 2 (seFrom edge)
  bindTextOrFail stmt 3 (seTo edge)
  bindTextOrFail stmt 4 (relationTypeText (fromMaybe RelRelatedTo (seRelationType edge)))
  bindTextOrFail stmt 5 (namespaceText (fromMaybe NamespaceSessionLocal (seNamespace edge)))
  bindTextOrFail stmt 6 (edgeOwner sessionId edge)
  bindTextOrFail stmt 7 sessionId
  stepOrFail stmt
  changed <- readChanges conn
  if changed == 1
    then pure ()
    else throwProjectionError "runtime corroboration target edge was not found"

readChanges :: NSQL.Database -> IO Int
readChanges conn = do
  prepared <- NSQL.prepare conn "SELECT changes()"
  case prepared of
    Left err -> throwProjectionError err
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      value <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure value

insertOneEdge :: NSQL.Database -> UTCTime -> Text -> SemanticEdge -> IO ()
insertOneEdge conn now sessionId edge = do
  stmt <- prepareTx conn "insert_runtime_edge"
    "INSERT INTO semantic_edges_runtime (ts, edge_from, edge_to, weight, co_occurrence, relation_type, domain, temporal_scope, verb, rationale, lineage, confidence, provenance, namespace, session_id, owner) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  bindInt64OrFail stmt 1 (utcMicros now)
  bindTextOrFail stmt 2 (seFrom edge)
  bindTextOrFail stmt 3 (seTo edge)
  bindDoubleOrFail stmt 4 (seWeight edge)
  bindInt64OrFail stmt 5 (fromIntegral (seCoOccurrence edge))
  bindMaybeText stmt 6 (fmap relationTypeText (seRelationType edge))
  bindMaybeText stmt 7 (fmap domainText (seDomain edge))
  bindMaybeText stmt 8 (fmap temporalScopeText (seTemporalScope edge))
  bindMaybeText stmt 9 (seVerb edge)
  bindMaybeText stmt 10 (seRationale edge)
  bindMaybeText stmt 11 (fmap lineageToText (seLineage edge))
  bindDoubleOrFail stmt 12 (seConfidence edge)
  bindTextOrFail stmt 13 (provenanceText (seProvenance edge))
  bindTextOrFail stmt 14 (maybe "session_local" namespaceText (seNamespace edge))
  bindMaybeText stmt 15 (edgeSessionId sessionId edge)
  bindTextOrFail stmt 16 (edgeOwner sessionId edge)
  stepOrFail stmt

validateSessionOwner :: Text -> [SemanticEdge] -> IO ()
validateSessionOwner sessionId edges =
  when (T.null (T.strip sessionId) && any isLocal edges) $
    throwProjectionError "session-local runtime edge requires a non-empty session owner"
  where
    isLocal edge = fromMaybe NamespaceSessionLocal (seNamespace edge) /= NamespaceGlobal

edgeSessionId :: Text -> SemanticEdge -> Maybe Text
edgeSessionId sessionId edge =
  case fromMaybe NamespaceSessionLocal (seNamespace edge) of
    NamespaceSessionLocal -> Just sessionId
    _ -> Nothing

edgeOwner :: Text -> SemanticEdge -> Text
edgeOwner sessionId edge =
  case fromMaybe NamespaceSessionLocal (seNamespace edge) of
    NamespaceGlobal -> "global"
    _ -> sessionId

deleteRuntimeEdge :: QxFx0DB -> Text -> Text -> Text -> IO ()
deleteRuntimeEdge db sessionId from to = do
  result <- withDB (qdbPath db) $ \conn -> do
    stmt <- prepareTx conn "delete_runtime_edge"
      "DELETE FROM semantic_edges_runtime WHERE edge_from = ? AND edge_to = ? AND ((namespace='global' AND owner IN ('global','legacy_global')) OR (namespace='session_local' AND session_id=? AND owner=?))"
    bindTextOrFail stmt 1 from
    bindTextOrFail stmt 2 to
    bindTextOrFail stmt 3 sessionId
    bindTextOrFail stmt 4 sessionId
    stepOrFail stmt
  either throwProjectionError pure result

-- | Delete all rows matching a specific (from, to), relation type and namespace.
-- This is required for belief revision so that quarantining a weaker
-- contradictory edge does not also remove the stronger edge.
deleteRuntimeEdgeExact :: QxFx0DB -> Text -> Text -> Text -> RelationType -> EdgeNamespace -> IO ()
deleteRuntimeEdgeExact db sessionId from to rel ns = do
  result <- withDB (qdbPath db) $ \conn -> do
    stmt <- prepareTx conn "delete_runtime_edge_exact"
      "DELETE FROM semantic_edges_runtime WHERE edge_from = ? AND edge_to = ? AND relation_type = ? AND namespace = ? AND owner = ? AND (namespace <> 'session_local' OR session_id = ?)"
    bindTextOrFail stmt 1 from
    bindTextOrFail stmt 2 to
    bindTextOrFail stmt 3 (relationTypeText rel)
    bindTextOrFail stmt 4 (namespaceText ns)
    bindTextOrFail stmt 5 (if ns == NamespaceGlobal then "global" else sessionId)
    bindTextOrFail stmt 6 sessionId
    stepOrFail stmt
  either throwProjectionError pure result

-- | Variant of 'deleteRuntimeEdgeExact' that uses an already-open connection.
-- This avoids a separate connection/transaction that can silently fail to see
-- the latest state when another connection is already open on the same DB.
deleteRuntimeEdgeExactConn :: NSQL.Database -> Text -> Text -> Text -> RelationType -> EdgeNamespace -> IO ()
deleteRuntimeEdgeExactConn conn sessionId from to rel ns = do
  let sql = "DELETE FROM semantic_edges_runtime WHERE edge_from = '" <> T.replace "'" "''" from
            <> "' AND edge_to = '" <> T.replace "'" "''" to
            <> "' AND relation_type = '" <> T.replace "'" "''" (relationTypeText rel)
            <> "' AND namespace = '" <> T.replace "'" "''" (namespaceText ns)
            <> "' AND owner = '" <> T.replace "'" "''" (if ns == NamespaceGlobal then "global" else sessionId)
            <> "' AND (namespace <> 'session_local' OR session_id = '" <> T.replace "'" "''" sessionId <> "')"
  result <- NSQL.execSql conn sql
  either throwProjectionError pure result

loadRuntimeEdgeProjection :: QxFx0DB -> Text -> IO (Map (Text, Text) SemanticEdge)
loadRuntimeEdgeProjection db sessionId = do
  when (T.null (T.strip sessionId)) (throwProjectionError "runtime projection load requires a session id")
  result <- withDB (qdbPath db) $ \conn -> do
    let sql = "SELECT edge_from, edge_to, weight, co_occurrence, relation_type, domain, temporal_scope, verb, rationale, lineage, confidence, provenance, namespace FROM semantic_edges_runtime WHERE namespace='global' OR (namespace='session_local' AND session_id=? AND owner=?) ORDER BY id ASC"
    mStmt <- NSQL.prepare conn sql
    case mStmt of
      Left err -> pure (Left err)
      Right stmt -> do
        _ <- NSQL.bindText stmt 1 sessionId
        _ <- NSQL.bindText stmt 2 sessionId
        rows <- collectRows stmt
        NSQL.finalize stmt
        pure (Right rows)
  either throwProjectionError (either throwProjectionError pure) result

-- | Load every row from the runtime projection table, including multiple
-- rows for the same @(from, to)@ pair.  This is required for contradiction
-- detection and belief revision, where the latest edge per key may hide
-- an older conflicting edge.
loadAllRuntimeEdges :: QxFx0DB -> Text -> IO [SemanticEdge]
loadAllRuntimeEdges db sessionId = do
  when (T.null (T.strip sessionId)) (throwProjectionError "runtime projection load requires a session id")
  result <- withDB (qdbPath db) $ \conn -> do
    let sql = "SELECT edge_from, edge_to, weight, co_occurrence, relation_type, domain, temporal_scope, verb, rationale, lineage, confidence, provenance, namespace FROM semantic_edges_runtime WHERE namespace='global' OR (namespace='session_local' AND session_id=? AND owner=?) ORDER BY id ASC"
    mStmt <- NSQL.prepare conn sql
    case mStmt of
      Left err -> pure (Left err)
      Right stmt -> do
        _ <- NSQL.bindText stmt 1 sessionId
        _ <- NSQL.bindText stmt 2 sessionId
        rows <- collectAllRows stmt []
        NSQL.finalize stmt
        pure (Right rows)
  either throwProjectionError (either throwProjectionError pure) result

collectAllRows :: NSQL.Statement -> [SemanticEdge] -> IO [SemanticEdge]
collectAllRows stmt acc = do
  hasRow <- NSQL.stepRow stmt
  if not hasRow
    then pure (reverse acc)
    else do
      mEdge <- readRow stmt
      case mEdge of
        Nothing -> collectAllRows stmt acc
        Just e  -> collectAllRows stmt (e : acc)

collectRows :: NSQL.Statement -> IO (Map (Text, Text) SemanticEdge)
collectRows stmt = go M.empty
  where
    go acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then pure acc
        else do
          mEdge <- readRow stmt
          go (maybe acc (\e -> M.insert (seFrom e, seTo e) e acc) mEdge)

readRow :: NSQL.Statement -> IO (Maybe SemanticEdge)
readRow stmt = do
  from       <- NSQL.columnText stmt 0
  to         <- NSQL.columnText stmt 1
  weight     <- NSQL.columnDouble stmt 2
  cooc       <- NSQL.columnInt stmt 3
  relT       <- columnTextMaybe stmt 4
  domainT    <- columnTextMaybe stmt 5
  temporalT  <- columnTextMaybe stmt 6
  verb       <- columnTextMaybe stmt 7
  rationale  <- columnTextMaybe stmt 8
  lineageT   <- columnTextMaybe stmt 9
  confidence <- NSQL.columnDouble stmt 10
  provT      <- columnTextMaybe stmt 11
  nsT        <- columnTextMaybe stmt 12
  let rel  = fromMaybe RelPresupposes (join (traverse relationTypeFromText relT))
      dom  = join (traverse domainFromText domainT)
      temp = join (traverse temporalScopeFromText temporalT)
      prov = fromMaybe ProvenanceRuntimeLLM (join (traverse provenanceFromText provT))
      ns   = join (traverse namespaceFromText nsT)
      lineage = join (traverse lineageFromText lineageT)
  pure $ Just SemanticEdge
        { seFrom          = from
        , seTo            = to
        , seWeight        = weight
        , seCoOccurrence  = fromIntegral cooc
        , seSource        = ExplicitEdge
        , seRelationType  = Just rel
        , seDomain        = dom
        , seTemporalScope = temp
        , seVerb          = verb
        , seRationale     = rationale
        , seCounter       = Nothing
        , seSynthesis     = Nothing
        , seConfidence    = confidence
        , seProvenance    = prov
        , seNamespace     = ns
        , seLineage       = lineage
        }

-- | Convert a relation type to its canonical snake_case database text.
relationTypeText :: RelationType -> Text
relationTypeText = T.toLower . T.intercalate "_" . splitCamel . T.drop 3 . T.pack . show
  where
    splitCamel :: Text -> [Text]
    splitCamel = go []
      where
        go acc txt
          | T.null txt = reverse acc
          | otherwise  =
              let (word, rest) = T.span isLowerRest (T.drop 1 txt)
                  first = T.take 1 txt
              in go (T.toLower (first <> word) : acc) rest
        isLowerRest c = c `elem` ['a'..'z'] || c `elem` ['0'..'9']

relationTypeFromText :: Text -> Maybe RelationType
relationTypeFromText t =
  let parts = T.split (== '_') t
      snakeCamel = T.concat (map (\p -> T.toUpper (T.take 1 p) <> T.drop 1 p) parts)
      legacyCamel = T.toUpper (T.take 1 t) <> T.drop 1 t
  in case reads ("Rel" <> T.unpack snakeCamel) of
       [(v, "")] -> Just v
       _ -> case reads ("Rel" <> T.unpack legacyCamel) of
              [(v, "")] -> Just v
              _ -> Nothing

namespaceText :: EdgeNamespace -> Text
namespaceText NamespaceSessionLocal = "session_local"
namespaceText NamespaceUserLocal    = "user_local"
namespaceText NamespaceGlobal       = "global"

namespaceFromText :: Text -> Maybe EdgeNamespace
namespaceFromText t =
  let normalized = T.toLower t
  in case normalized of
       "sessionlocal"  -> Just NamespaceSessionLocal
       "userlocal"     -> Just NamespaceUserLocal
       "global"        -> Just NamespaceGlobal
       "session_local" -> Just NamespaceSessionLocal
       "user_local"    -> Just NamespaceUserLocal
       _               -> Nothing

lineageToText :: [EdgeRef] -> Text
lineageToText refs = TE.decodeUtf8 (BL.toStrict (A.encode refs))

lineageFromText :: Text -> Maybe [EdgeRef]
lineageFromText t =
  case A.eitherDecodeStrict (TE.encodeUtf8 t) :: Either String [EdgeRef] of
    Right refs -> Just refs
    Left _     -> Nothing

domainText :: DomainTag -> Text
domainText DomainOntology             = "ontology"
domainText DomainEthics               = "ethics"
domainText DomainAesthetics           = "aesthetics"
domainText DomainEpistemology         = "epistemology"
domainText DomainPoliticalPhilosophy  = "political_philosophy"
domainText DomainAnthropology         = "anthropology"
domainText DomainMethodology          = "methodology"
domainText DomainLogic                = "logic"
domainText DomainSocialPhilosophy     = "social_philosophy"
domainText DomainPhilosophyOfMind     = "philosophy_of_mind"
domainText DomainArtHistory           = "art_history"
domainText DomainGeneral              = "general"

domainFromText :: Text -> Maybe DomainTag
domainFromText t =
  case T.toLower t of
    "ontology"            -> Just DomainOntology
    "ethics"              -> Just DomainEthics
    "aesthetics"          -> Just DomainAesthetics
    "epistemology"        -> Just DomainEpistemology
    "political_philosophy"-> Just DomainPoliticalPhilosophy
    "anthropology"        -> Just DomainAnthropology
    "methodology"         -> Just DomainMethodology
    "logic"               -> Just DomainLogic
    "social_philosophy"   -> Just DomainSocialPhilosophy
    "philosophy_of_mind"  -> Just DomainPhilosophyOfMind
    "art_history"         -> Just DomainArtHistory
    "general"             -> Just DomainGeneral
    _                     -> Nothing

temporalScopeText :: TemporalScope -> Text
temporalScopeText TemporalPoint        = "point"
temporalScopeText TemporalInterval     = "interval"
temporalScopeText TemporalEternal       = "eternal"
temporalScopeText AncientPeriod        = "ancient"
temporalScopeText ClassicalPeriod      = "classical"
temporalScopeText MedievalPeriod       = "medieval"
temporalScopeText RenaissancePeriod    = "renaissance"
temporalScopeText EarlyModernPeriod    = "early_modern"
temporalScopeText ModernPeriod         = "modern"
temporalScopeText ContemporaryPeriod   = "contemporary"
temporalScopeText TranshistoricalPeriod = "transhistorical"
temporalScopeText (SpecificEra era)    = "era:" <> era

temporalScopeFromText :: Text -> Maybe TemporalScope
temporalScopeFromText t =
  case T.toLower t of
    "ancient"         -> Just AncientPeriod
    "classical"       -> Just ClassicalPeriod
    "medieval"        -> Just MedievalPeriod
    "renaissance"     -> Just RenaissancePeriod
    "early_modern"    -> Just EarlyModernPeriod
    "modern"          -> Just ModernPeriod
    "contemporary"    -> Just ContemporaryPeriod
    "transhistorical" -> Just TranshistoricalPeriod
    _                 ->
      case T.stripPrefix "era:" (T.toLower t) of
        Just era -> Just (SpecificEra era)
        Nothing  -> Nothing

-- | A map of edges to apply on top of a seed network.
type SemanticNetworkDelta = Map (Text, Text) SemanticEdge

-- | Replay a chronological list of learning events to reconstruct the
-- runtime edge projection they represent.  The result is a delta that can
-- be merged into a seed network with 'applyProjectionDelta'.
--
-- Semantics per event kind:
--
-- * 'LlmEdgeProposed' is ignored (proposal only, not yet admitted).
-- * 'EdgeAdmitted' inserts or overwrites the edge.
-- * 'EdgeRejected' removes the edge.
-- * 'EdgeQuarantined' removes the edge.
-- * 'RuntimeFeedbackPositive' / 'EdgePromoted' boost confidence and bump
--   co-occurrence.
-- * 'RuntimeFeedbackNegative' lowers confidence.
-- * 'RuntimeFeedbackConflict' sharply lowers confidence.
-- * 'EdgeDecayed' decays confidence.
-- * 'EdgeRetired' removes the edge.
rebuildLearningProjection :: [LearningEvent] -> SemanticNetworkDelta
rebuildLearningProjection = foldl' applyEvent M.empty
  where
    applyEvent acc event =
      case (leEdgeFrom event, leEdgeTo event) of
        (Just from, Just to) -> applyEdgeEvent from to event acc
        _ -> acc

    applyEdgeEvent from to event acc =
      let key = (from, to)
      in case leKind event of
        LlmEdgeProposed -> acc
        EdgeAdmitted -> M.insert key (eventToEdge event from to) acc
        EdgeCorroborated -> adjustEdge key corroborate acc
        EdgeRejected -> M.delete key acc
        -- A targeted confirmation may quarantine only the incoming conflicting
        -- relation. It must not erase the already admitted target edge during
        -- replay, because no graph mutation happened for that conflict.
        EdgeQuarantined
          | leEvidenceSource event == Just "candidate_targeted_corroboration" -> acc
          | otherwise -> M.delete key acc
        RuntimeFeedbackPositive -> adjustEdge key (boost 0.1) acc
        RuntimeFeedbackNegative -> adjustEdge key (reduce 0.1) acc
        RuntimeFeedbackConflict -> adjustEdge key (reduce 0.25) acc
        EdgePromoted -> adjustEdge key (boost 0.15) acc
        EdgeDecayed -> adjustEdge key decay acc
        EdgeRetired -> M.delete key acc

    eventToEdge event from to =
      let prov = fromMaybe ProvenanceRuntimeLLM (leProvenance event)
          source = if prov == ProvenanceSubstrate then SubstrateEdge else ExplicitEdge
          conf = fromMaybe 0.6 (leConfidence event)
          cooc = fromMaybe 1 (leCoOccurrence event)
          rel = RelRelatedTo
      in SemanticEdge
          { seFrom = from
          , seTo = to
          , seWeight = conf * relationTypeWeight rel
          , seCoOccurrence = cooc
          , seSource = source
          , seRelationType = Just rel
          , seDomain = Nothing
          , seTemporalScope = Nothing
          , seVerb = Nothing
          , seRationale = leReason event
          , seCounter = Nothing
          , seSynthesis = Nothing
          , seConfidence = conf
          , seProvenance = prov
          , seNamespace = Just NamespaceSessionLocal
          , seLineage = Nothing
          }

    adjustEdge key f = M.adjust f key

    boost amount edge =
      let newConf = min 1.0 (seConfidence edge + amount)
      in edge { seConfidence = newConf
              , seWeight = newConf * relationTypeWeight (fromMaybe RelRelatedTo (seRelationType edge))
              , seCoOccurrence = seCoOccurrence edge + 1
               }

    corroborate edge = edge { seCoOccurrence = seCoOccurrence edge + 1 }

    reduce amount edge =
      let newConf = max 0.0 (seConfidence edge - amount)
      in edge { seConfidence = newConf
              , seWeight = newConf * relationTypeWeight (fromMaybe RelRelatedTo (seRelationType edge))
              }

    decay edge =
      let newConf = max 0.0 (seConfidence edge * 0.9)
      in edge { seConfidence = newConf
              , seWeight = newConf * relationTypeWeight (fromMaybe RelRelatedTo (seRelationType edge))
              }

applyProjectionDelta
  :: SemanticNetworkDelta
  -> SemanticNetwork
  -> SemanticNetwork
applyProjectionDelta delta base =
  let seedEdges = snEdges base
      mergedEdges = M.unionWith preferByProvenance seedEdges delta
      mergedNodes = S.fromList (concat [[seFrom e, seTo e] | e <- M.elems mergedEdges])
  in base
      { snNodes = S.union (snNodes base) mergedNodes
      , snEdges = mergedEdges
      }

-- | Provenance precedence for merging a runtime-projection delta into a
-- seed network. Higher value wins. Human corrections are intentionally
-- ranked above curated/seed edges so explicit user corrections always
-- override learned or seeded edges.
provenancePrecedence :: EdgeProvenance -> Int
provenancePrecedence ProvenanceHumanCorrection  = 6
provenancePrecedence ProvenanceCurated          = 5
provenancePrecedence ProvenanceIngested         = 5
provenancePrecedence ProvenanceSelfPlay         = 5
provenancePrecedence ProvenanceDerived          = 4
provenancePrecedence ProvenanceDialogueFeedback = 4
provenancePrecedence ProvenanceCorpus           = 4
provenancePrecedence ProvenanceSubstrate        = 3
provenancePrecedence ProvenanceRuntimeLLM       = 2

preferByProvenance :: SemanticEdge -> SemanticEdge -> SemanticEdge
preferByProvenance baseEdge deltaEdge =
  let provDelta = provenancePrecedence (seProvenance deltaEdge)
      provBase  = provenancePrecedence (seProvenance baseEdge)
      nsDelta   = namespacePrecedence (fromMaybe NamespaceSessionLocal (seNamespace deltaEdge))
      nsBase    = namespacePrecedence (fromMaybe NamespaceSessionLocal (seNamespace baseEdge))
  in if provDelta > provBase || (provDelta == provBase && nsDelta > nsBase)
       then deltaEdge
       else baseEdge

-- | Namespace precedence for multi-session learning. Higher value wins.
namespacePrecedence :: EdgeNamespace -> Int
namespacePrecedence NamespaceGlobal       = 3
namespacePrecedence NamespaceUserLocal    = 2
namespacePrecedence NamespaceSessionLocal = 1

utcMicros :: UTCTime -> Int64
utcMicros = round . (* 1000000) . realToFrac . utcTimeToPOSIXSeconds

bindMaybeText :: TxStmt -> Int -> Maybe Text -> IO ()
bindMaybeText stmt ix = maybe (bindNullOrFail stmt (fromIntegral ix)) (bindTextOrFail stmt (fromIntegral ix))

columnTextMaybe :: NSQL.Statement -> CInt -> IO (Maybe Text)
columnTextMaybe stmt idx = do
  isNull <- NSQL.columnIsNull stmt idx
  if isNull then pure Nothing else Just <$> NSQL.columnText stmt idx

throwProjectionError :: Text -> IO a
throwProjectionError detail =
  throwQxFx0 (mkSQLiteError
    "semantic_network_runtime_projection"
    "RUNTIME_PROJECTION_SQLITE_ERROR"
    (M.singleton "detail" detail))
