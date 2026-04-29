{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Canonical schema contract: version, required tables, required columns.
    Used by both read-only health probes and mutating bootstrap path.
-}
module QxFx0.Bridge.SQLite.SchemaContract
  ( currentSchemaVersion
  , schemaContractTables
  , schemaContractColumns
  , SchemaContractResult(..)
  , SchemaVersionStatus(..)
  , checkSchemaContract
  , validateSchemaContractTablesAndColumns
  , readSchemaVersion
  , renderSchemaContractResult
  , tableExists
  , columnMissing
  , isV1Shape
  , isV2Shape
  ) where

import Control.Monad (filterM, foldM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.ExceptionPolicy (tryQxFx0)

currentSchemaVersion :: Int
currentSchemaVersion = 3

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
    SchemaVersionMissingTable -> do
      anyTableExists <- anyM (tableExists db) schemaContractTables
      if not anyTableExists
        then pure SchemaContractFreshBootstrapable
        else do
          v1 <- isV1Shape db
          if v1
            then pure (SchemaContractVersionBehind currentSchemaVersion 1)
            else pure (SchemaContractInconsistent "tables exist but schema_version missing and shape not v1")
    SchemaVersionEmpty -> do
      v1 <- isV1Shape db
      if v1
        then pure (SchemaContractVersionBehind currentSchemaVersion 1)
        else do
          v2 <- isV2Shape db
          if v2
            then pure (SchemaContractOk currentSchemaVersion)
            else pure (SchemaContractInconsistent "schema_version empty and shape not v1 or v2")
    SchemaVersionPresent v
      | v < currentSchemaVersion ->
          pure (SchemaContractVersionBehind currentSchemaVersion v)
      | otherwise ->
          checkTablesAndColumns db

-- | Check tables and columns only, ignoring schema_version.
validateSchemaContractTablesAndColumns :: NSQL.Database -> IO SchemaContractResult
validateSchemaContractTablesAndColumns db = checkTablesAndColumns db

-- | Check that all required tables exist, then required columns, indexes,
--   triggers, and FTS virtual tables.
checkTablesAndColumns :: NSQL.Database -> IO SchemaContractResult
checkTablesAndColumns db = do
  missingTables <- filterM (fmap not . tableExists db) schemaContractTables
  case missingTables of
    (t:_) -> pure (SchemaContractMissingTable t)
    [] -> do
      let checkOne (tbl, cols) = do
            missing <- filterM (columnMissing db tbl) cols
            pure (if null missing then Nothing else Just (tbl, missing))
      badCols <- mapMaybe id <$> mapM checkOne (Map.toList schemaContractColumns)
      case badCols of
        ((tbl, cols):_) -> pure (SchemaContractMissingColumns tbl cols)
        [] -> do
          missingIndexes <- filterM (fmap not . indexExists db) schemaContractIndexes
          case missingIndexes of
            (ix:_) -> pure (SchemaContractMissingIndex ix)
            [] -> do
              missingTriggers <- filterM (fmap not . triggerExists db) schemaContractTriggers
              case missingTriggers of
                (tr:_) -> pure (SchemaContractMissingTrigger tr)
                [] -> do
                  missingFTS <- filterM (fmap not . ftsTableExists db) schemaContractFTS
                  case missingFTS of
                    (fts:_) -> pure (SchemaContractMissingFTS fts)
                    [] -> pure (SchemaContractOk currentSchemaVersion)

readSchemaVersion :: NSQL.Database -> IO SchemaVersionStatus
readSchemaVersion db = do
  schemaVersionTableExists <- tableExists db "schema_version"
  if not schemaVersionTableExists
    then pure SchemaVersionMissingTable
    else do
      mVersion <- readSchemaVersionRow db
      case mVersion of
        Nothing -> pure SchemaVersionEmpty
        Just v  -> pure (SchemaVersionPresent v)

readSchemaVersionRow :: NSQL.Database -> IO (Maybe Int)
readSchemaVersionRow db = do
  mStmt <- NSQL.prepare db "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1"
  case mStmt of
    Left _ -> pure Nothing
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      version <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      _ <- tryQxFx0 (NSQL.finalize stmt)
      if hasRow && version > 0
        then pure (Just version)
        else pure Nothing

-- | True if the database has the turn_quality table but is missing any v2 column.
--   Used to infer a v1-shaped legacy database when the schema_version marker
--   is missing or empty.
isV1Shape :: NSQL.Database -> IO Bool
isV1Shape db = do
  tqExists <- tableExists db "turn_quality"
  if not tqExists
    then pure False
    else do
      missing <- filterM (columnMissing db "turn_quality") v2TurnQualityColumns
      pure (not (null missing))

-- | True if the database has all required tables and all required columns.
--   Used to recognise a v2-complete database that may be missing its version marker.
isV2Shape :: NSQL.Database -> IO Bool
isV2Shape db = do
  result <- checkTablesAndColumns db
  pure $ case result of
    SchemaContractOk _ -> True
    _ -> False

tableExists :: NSQL.Database -> Text -> IO Bool
tableExists db tableName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left _ -> pure False
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 tableName
      hasRow <- NSQL.stepRow stmt
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure hasRow

columnMissing :: NSQL.Database -> Text -> Text -> IO Bool
columnMissing db tableName columnName = do
  let sql = "SELECT 1 FROM pragma_table_info('" <> tableName <> "') WHERE name = ? LIMIT 1"
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left _ -> pure True
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 columnName
      hasRow <- NSQL.stepRow stmt
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure (not hasRow)

indexExists :: NSQL.Database -> Text -> IO Bool
indexExists db indexName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = ? LIMIT 1"
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left _ -> pure False
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 indexName
      hasRow <- NSQL.stepRow stmt
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure hasRow

triggerExists :: NSQL.Database -> Text -> IO Bool
triggerExists db triggerName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'trigger' AND name = ? LIMIT 1"
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left _ -> pure False
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 triggerName
      hasRow <- NSQL.stepRow stmt
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure hasRow

ftsTableExists :: NSQL.Database -> Text -> IO Bool
ftsTableExists db ftsName = do
  let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left _ -> pure False
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 ftsName
      hasRow <- NSQL.stepRow stmt
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure hasRow

anyM :: Monad m => (a -> m Bool) -> [a] -> m Bool
anyM p = foldM (\acc x -> if acc then pure True else p x) False
