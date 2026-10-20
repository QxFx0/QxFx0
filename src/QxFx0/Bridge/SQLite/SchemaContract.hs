{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Canonical schema contract: version, required tables, required columns.
    Used by both read-only health probes and mutating bootstrap path.
-}
module QxFx0.Bridge.SQLite.SchemaContract
  ( currentSchemaVersion
  , schemaContractTables
  , schemaContractColumns
  , schemaContractIndexes
  , schemaContractTriggers
  , schemaContractFTS
  , SchemaContractResult(..)
  , SchemaVersionStatus(..)
  , ProbeOutcome(..)
  , checkSchemaContract
  , validateSchemaContractTablesAndColumns
  , readSchemaVersion
  , renderSchemaContractResult
  , tableExists
  , columnExists
  , isV1Shape
  , isV2Shape
  ) where

import Control.Monad (forM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.ExceptionPolicy (tryQxFx0)

currentSchemaVersion :: Int
currentSchemaVersion = 4

-- | Tables that must exist for the runtime to function.
schemaContractTables :: [Text]
schemaContractTables =
  [ "schema_version"
  , "identity_claims"
  , "semantic_clusters"
  , "realization_templates"
  , "runtime_sessions"
  , "dialogue_state"
  , "turn_quality"
  , "shadow_divergence_log"
  ]

-- | Required columns per table (only non-obvious / migration-added).
schemaContractColumns :: Map Text [Text]
schemaContractColumns = Map.fromList
  [ ( "turn_quality"
    , [ "warranted_mode"
      , "decision_disposition"
      , "shadow_snapshot_id"
      , "shadow_divergence_kind"
      , "replay_trace_json"
      ]
    )
  , ( "shadow_divergence_log"
    , [ "shadow_snapshot_id"
      , "shadow_divergence_kind"
      ]
    )
  , ( "runtime_sessions"
    , [ "state_revision"
      ]
    )
  ]

-- | Columns that identify a v1-shaped DB (i.e. missing in v1, present in v2).
v2TurnQualityColumns :: [Text]
v2TurnQualityColumns =
  [ "warranted_mode"
  , "decision_disposition"
  , "shadow_snapshot_id"
  , "shadow_divergence_kind"
  , "replay_trace_json"
  ]

-- | Required indexes.
schemaContractIndexes :: [Text]
schemaContractIndexes =
  [ "idx_identity_concept"
  , "idx_identity_topic"
  , "idx_templates_move"
  , "idx_clusters_name"
  , "idx_dialogue_state_session"
  , "idx_turn_quality_session_turn"
  , "idx_turn_quality_divergence"
  , "idx_shadow_divergence_session_turn"
  ]

-- | Required triggers.
schemaContractTriggers :: [Text]
schemaContractTriggers =
  [ "identity_claims_ai"
  , "identity_claims_ad"
  ]

-- | Required FTS virtual tables.
schemaContractFTS :: [Text]
schemaContractFTS =
  [ "identity_claims_fts"
  ]

data SchemaContractResult
  = SchemaContractOk !Int
  | SchemaContractFreshBootstrapable
  | SchemaContractVersionBehind !Int !Int   -- ^ expected, actual
  | SchemaContractMissingTable !Text
  | SchemaContractMissingColumns !Text ![Text]
  | SchemaContractMissingIndex !Text
  | SchemaContractMissingTrigger !Text
  | SchemaContractMissingFTS !Text
  | SchemaContractInconsistent !Text
  | SchemaContractQueryFailed !Text
  deriving stock (Eq, Show)

data SchemaVersionStatus
  = SchemaVersionMissingTable
  | SchemaVersionEmpty
  | SchemaVersionPresent !Int
  | SchemaVersionProbeError !Text
  deriving stock (Eq, Show)

-- | Three-valued outcome of a schema probe (audit 2026-10-16 п.23).
-- A failed probe must never be reported as \"the object is absent\":
-- callers decide differently for absence and for a broken probe.
data ProbeOutcome
  = ProbeFound
  | ProbeNotFound
  | ProbeFailed !Text
  deriving stock (Eq, Show)

renderSchemaContractResult :: SchemaContractResult -> Text
renderSchemaContractResult (SchemaContractOk v) =
  "schema_ok version=" <> T.pack (show v)
renderSchemaContractResult SchemaContractFreshBootstrapable =
  "schema_bootstrapable_fresh_db"
renderSchemaContractResult (SchemaContractVersionBehind expected actual) =
  "schema_version_behind expected=" <> T.pack (show expected)
  <> " actual=" <> T.pack (show actual)
renderSchemaContractResult (SchemaContractMissingTable t) =
  "schema_missing_table " <> t
renderSchemaContractResult (SchemaContractMissingColumns t cols) =
  "schema_missing_columns table=" <> t
  <> " columns=" <> T.intercalate "," cols
renderSchemaContractResult (SchemaContractMissingIndex ix) =
  "schema_missing_index " <> ix
renderSchemaContractResult (SchemaContractMissingTrigger tr) =
  "schema_missing_trigger " <> tr
renderSchemaContractResult (SchemaContractMissingFTS fts) =
  "schema_missing_fts " <> fts
renderSchemaContractResult (SchemaContractInconsistent reason) =
  "schema_inconsistent " <> reason
renderSchemaContractResult (SchemaContractQueryFailed msg) =
  "schema_query_failed " <> msg

-- | Read-only schema contract check.  Does NOT mutate the database.
checkSchemaContract :: NSQL.Database -> IO SchemaContractResult
checkSchemaContract db = do
  versionStatus <- readSchemaVersion db
  case versionStatus of
    SchemaVersionProbeError msg -> pure (SchemaContractQueryFailed msg)
    SchemaVersionMissingTable -> do
      tableProbes <- probeAll (tableExists db) schemaContractTables
      case tableProbes of
        Left e -> pure (SchemaContractQueryFailed e)
        Right probes
          | not (ProbeFound `elem` probes) -> pure SchemaContractFreshBootstrapable
          | otherwise -> do
              v1 <- isV1Shape db
              case v1 of
                Left e -> pure (SchemaContractQueryFailed e)
                Right True -> pure (SchemaContractVersionBehind currentSchemaVersion 1)
                Right False -> pure (SchemaContractInconsistent "tables exist but schema_version missing and shape not v1")
    SchemaVersionEmpty -> do
      v1 <- isV1Shape db
      case v1 of
        Left e -> pure (SchemaContractQueryFailed e)
        Right True -> pure (SchemaContractVersionBehind currentSchemaVersion 1)
        Right False -> do
          v2 <- isV2Shape db
          case v2 of
            Left e -> pure (SchemaContractQueryFailed e)
            Right True -> pure (SchemaContractOk currentSchemaVersion)
            Right False -> pure (SchemaContractInconsistent "schema_version empty and shape not v1 or v2")
    SchemaVersionPresent v
      | v < currentSchemaVersion ->
          pure (SchemaContractVersionBehind currentSchemaVersion v)
      | otherwise ->
          checkTablesAndColumns db

-- | Check tables and columns only, ignoring schema_version.
validateSchemaContractTablesAndColumns :: NSQL.Database -> IO SchemaContractResult
validateSchemaContractTablesAndColumns db = checkTablesAndColumns db

-- | Check that all required tables exist, then required columns, indexes,
--   triggers, and FTS virtual tables.  Probe failures surface as
--   'SchemaContractQueryFailed' and never masquerade as a missing object.
checkTablesAndColumns :: NSQL.Database -> IO SchemaContractResult
checkTablesAndColumns db = do
  tableProbes <- probeAll (tableExists db) schemaContractTables
  case tableProbes of
    Left e -> pure (SchemaContractQueryFailed e)
    Right tableResults ->
      case [t | (t, ProbeNotFound) <- zip schemaContractTables tableResults] of
        (t:_) -> pure (SchemaContractMissingTable t)
        [] -> do
          columnProbes <- forM (Map.toList schemaContractColumns) $ \(tbl, cols) -> do
            colResults <- probeAll (columnExists db tbl) cols
            pure (tbl, cols, colResults)
          case [e | (_, _, Left e) <- columnProbes] of
            (e:_) -> pure (SchemaContractQueryFailed e)
            [] ->
              case [ (tbl, [c | (c, ProbeNotFound) <- zip cols colResults])
                   | (tbl, cols, Right colResults) <- columnProbes
                   , ProbeNotFound `elem` colResults
                   ] of
                ((tbl, cols):_) -> pure (SchemaContractMissingColumns tbl cols)
                [] -> do
                  indexProbes <- probeAll (indexExists db) schemaContractIndexes
                  case indexProbes of
                    Left e -> pure (SchemaContractQueryFailed e)
                    Right indexResults ->
                      case [ix | (ix, ProbeNotFound) <- zip schemaContractIndexes indexResults] of
                        (ix:_) -> pure (SchemaContractMissingIndex ix)
                        [] -> do
                          triggerProbes <- probeAll (triggerExists db) schemaContractTriggers
                          case triggerProbes of
                            Left e -> pure (SchemaContractQueryFailed e)
                            Right triggerResults ->
                              case [tr | (tr, ProbeNotFound) <- zip schemaContractTriggers triggerResults] of
                                (tr:_) -> pure (SchemaContractMissingTrigger tr)
                                [] -> do
                                  ftsProbes <- probeAll (ftsTableExists db) schemaContractFTS
                                  case ftsProbes of
                                    Left e -> pure (SchemaContractQueryFailed e)
                                    Right ftsResults ->
                                      case [fts | (fts, ProbeNotFound) <- zip schemaContractFTS ftsResults] of
                                        (fts:_) -> pure (SchemaContractMissingFTS fts)
                                        [] -> pure (SchemaContractOk currentSchemaVersion)

readSchemaVersion :: NSQL.Database -> IO SchemaVersionStatus
readSchemaVersion db = do
  schemaVersionTableProbe <- tableExists db "schema_version"
  case schemaVersionTableProbe of
    ProbeFailed e -> pure (SchemaVersionProbeError e)
    ProbeNotFound -> pure SchemaVersionMissingTable
    ProbeFound -> do
      rowResult <- readSchemaVersionRow db
      case rowResult of
        Left e -> pure (SchemaVersionProbeError e)
        Right Nothing -> pure SchemaVersionEmpty
        Right (Just v)  -> pure (SchemaVersionPresent v)

-- | Read the highest version row: 'Right Nothing' = the probe ran and the
-- table is empty; 'Left' = the probe itself failed.
readSchemaVersionRow :: NSQL.Database -> IO (Either Text (Maybe Int))
readSchemaVersionRow db = do
  mStmt <- NSQL.prepare db "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1"
  case mStmt of
    Left e -> pure (Left ("readSchemaVersionRow: " <> e))
    Right stmt -> do
      rowResult <- NSQL.stepHasRow stmt
      versionResult <- case rowResult of
        Left e -> pure (Left ("readSchemaVersionRow: " <> e))
        Right False -> pure (Right Nothing)
        Right True -> do
          version <- NSQL.columnInt stmt 0
          pure (Right (if version > 0 then Just version else Nothing))
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure versionResult

-- | True if the database has the turn_quality table but is missing any v2 column.
--   Used to infer a v1-shaped legacy database when the schema_version marker
--   is missing or empty.  'Left' = the shape could not be established.
isV1Shape :: NSQL.Database -> IO (Either Text Bool)
isV1Shape db = do
  tqProbe <- tableExists db "turn_quality"
  case tqProbe of
    ProbeFailed e -> pure (Left e)
    ProbeNotFound -> pure (Right False)
    ProbeFound -> do
      columnProbes <- probeAll (columnExists db "turn_quality") v2TurnQualityColumns
      pure (fmap (ProbeNotFound `elem`) columnProbes)

-- | True if the database has all required tables and all required columns.
--   Used to recognise a v2-complete database that may be missing its version
--   marker.  'Left' = the probe failed (never treat that as \"not v2\").
isV2Shape :: NSQL.Database -> IO (Either Text Bool)
isV2Shape db = do
  result <- checkTablesAndColumns db
  pure $ case result of
    SchemaContractOk _ -> Right True
    SchemaContractQueryFailed msg -> Left msg
    _ -> Right False

-- | Probe for a named object in sqlite_master.  A probe that cannot run
-- reports 'ProbeFailed' with the SQLite error, never a silent absence.
tableExists :: NSQL.Database -> Text -> IO ProbeOutcome
tableExists db tableName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
  probeOne db "tableExists" sql tableName

columnExists :: NSQL.Database -> Text -> Text -> IO ProbeOutcome
columnExists db tableName columnName = do
  let sql = "SELECT 1 FROM pragma_table_info('" <> tableName <> "') WHERE name = ? LIMIT 1"
  probeOne db "columnExists" sql columnName

indexExists :: NSQL.Database -> Text -> IO ProbeOutcome
indexExists db indexName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ? LIMIT 1"
  probeOne db "indexExists" sql indexName

triggerExists :: NSQL.Database -> Text -> IO ProbeOutcome
triggerExists db triggerName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = ? LIMIT 1"
  probeOne db "triggerExists" sql triggerName

ftsTableExists :: NSQL.Database -> Text -> IO ProbeOutcome
ftsTableExists db ftsName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
  probeOne db "ftsTableExists" sql ftsName

-- | Run a single-value existence probe.  Prepare/bind/step failures are
-- returned as 'ProbeFailed'; finalize stays best-effort (resource release
-- is not part of the probe answer).
probeOne :: NSQL.Database -> Text -> Text -> Text -> IO ProbeOutcome
probeOne db label sql value = do
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left e -> pure (ProbeFailed (label <> ": " <> e))
    Right stmt -> do
      bindResult <- NSQL.bindText stmt 1 value
      outcome <- case bindResult of
        Left e -> pure (ProbeFailed (label <> ": " <> e))
        Right () -> do
          rowResult <- NSQL.stepHasRow stmt
          pure $ case rowResult of
            Left e -> ProbeFailed (label <> ": " <> e)
            Right True -> ProbeFound
            Right False -> ProbeNotFound
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure outcome

-- | Run a homogeneous probe list, aborting on the first probe failure.
probeAll :: (a -> IO ProbeOutcome) -> [a] -> IO (Either Text [ProbeOutcome])
probeAll probe = go []
  where
    go acc [] = pure (Right (reverse acc))
    go acc (x:xs) = do
      outcome <- probe x
      case outcome of
        ProbeFailed e -> pure (Left e)
        other -> go (other : acc) xs
