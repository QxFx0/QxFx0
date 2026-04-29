{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Schema bootstrap, migration runner, and seed loading for the runtime SQLite backend. -}
module QxFx0.Bridge.SQLite.Bootstrap
  ( currentSchemaVersion
  , ensureSchemaMigrations
  ) where

import Control.Exception (IOException, finally)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import QxFx0.Bridge.EmbeddedSQL (schemaSQL, seedClustersSQL, seedIdentitySQL, seedTemplatesSQL)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.SQLite.SchemaContract
  ( currentSchemaVersion
  , checkSchemaContract
  , validateSchemaContractTablesAndColumns
  , readSchemaVersion
  , SchemaContractResult(..)
  , SchemaVersionStatus(..)
  , renderSchemaContractResult
  , columnMissing
  , isV1Shape
  , isV2Shape
  )
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(SQLiteError)
  , catchIO
  , throwQxFx0
  , tryQxFx0
  )
import QxFx0.Resources
  ( resolveResourcePaths
  , rpSchemaSql
  , rpSeedClusters
  , rpSeedIdentity
  , rpSeedTemplates
  )
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)

currentSchemaDescription :: Text
currentSchemaDescription = "Runtime schema v3: shadow_divergence_log trace columns (shadow_snapshot_id, shadow_divergence_kind)"

ensureSchemaMigrations :: NSQL.Database -> IO ()
ensureSchemaMigrations db = do
  sqlSet <- loadBootstrapSqlSet
  -- 1. Run canonical schema (IF NOT EXISTS — safe for old and new DBs)
  execBootstrapSql db ("schema.sql", bootstrapSchema sqlSet)
  -- 2. Determine current version state and act accordingly
  versionStatus <- readSchemaVersion db
  case versionStatus of
    SchemaVersionMissingTable -> do
      isV1 <- isV1Shape db
      if isV1
        then do
          runPendingMigrations db 1
          seedAfterMigration sqlSet db
        else do
          isV2 <- isV2Shape db
          if isV2
            then do
              insertSchemaVersion db currentSchemaVersion currentSchemaDescription
              seedAfterMigration sqlSet db
            else do
              -- Fresh DB: no tables and no schema_version
              insertSchemaVersion db currentSchemaVersion currentSchemaDescription
              seedAfterMigration sqlSet db
    SchemaVersionEmpty -> do
      isV1 <- isV1Shape db
      if isV1
        then do
          runPendingMigrations db 1
          seedAfterMigration sqlSet db
        else do
          isV2 <- isV2Shape db
          if isV2
            then do
              insertSchemaVersion db currentSchemaVersion currentSchemaDescription
              seedAfterMigration sqlSet db
            else
              throwQxFx0
                (SQLiteError "schema_version table exists but is empty, and database shape is not v1 or v2")
    SchemaVersionPresent 1 -> do
      runPendingMigrations db 1
      seedAfterMigration sqlSet db
    SchemaVersionPresent v
      | v == currentSchemaVersion ->
          pure ()
      | v < currentSchemaVersion -> do
          runPendingMigrations db v
          seedAfterMigration sqlSet db
      | otherwise ->
          throwQxFx0
            (SQLiteError $
              "schema_version mismatch: expected "
                <> T.pack (show currentSchemaVersion)
                <> ", found "
                <> T.pack (show v)
                <> ". Downgrade is not supported.")
  -- 3. Post-bootstrap validation
  contractResult <- checkSchemaContract db
  case contractResult of
    SchemaContractOk _ -> pure ()
    SchemaContractFreshBootstrapable -> pure ()
    SchemaContractVersionBehind expected actual ->
      throwQxFx0 (SQLiteError $
        "schema version behind: expected " <> T.pack (show expected)
        <> ", found " <> T.pack (show actual))
    SchemaContractMissingTable t ->
      throwQxFx0 (SQLiteError $ "schema contract failed: missing table " <> t)
    SchemaContractMissingColumns t cols ->
      throwQxFx0 (SQLiteError $
        "schema contract failed: table " <> t <> " missing columns: "
        <> T.intercalate ", " cols)
    SchemaContractMissingIndex ix ->
      throwQxFx0 (SQLiteError $ "schema contract failed: missing index " <> ix)
    SchemaContractMissingTrigger tr ->
      throwQxFx0 (SQLiteError $ "schema contract failed: missing trigger " <> tr)
    SchemaContractMissingFTS fts ->
      throwQxFx0 (SQLiteError $ "schema contract failed: missing fts table " <> fts)
    SchemaContractInconsistent reason ->
      throwQxFx0 (SQLiteError $ "schema contract inconsistent: " <> reason)
    SchemaContractQueryFailed msg ->
      throwQxFx0 (SQLiteError $ "schema contract query failed: " <> msg)

seedAfterMigration :: BootstrapSqlSet -> NSQL.Database -> IO ()
seedAfterMigration sqlSet db = do
  seedBootstrapSql db "semantic_clusters" ("seed_clusters.sql", bootstrapClusters sqlSet)
  seedBootstrapSql db "realization_templates" ("seed_templates.sql", bootstrapTemplates sqlSet)
  seedBootstrapSql db "identity_claims" ("seed_identity.sql", bootstrapIdentity sqlSet)

data BootstrapSqlSet = BootstrapSqlSet
  { bootstrapSchema :: !Text
  , bootstrapClusters :: !Text
  , bootstrapTemplates :: !Text
  , bootstrapIdentity :: !Text
  }

loadBootstrapSqlSet :: IO BootstrapSqlSet
loadBootstrapSqlSet = do
  pathsResult <- tryQxFx0 resolveResourcePaths
  case pathsResult of
    Left err ->
      allowEmbeddedSqlFallback
        ("resolveResourcePaths failed: " <> T.pack (show err))
        fallbackBootstrapSqlSet
    Right paths ->
      BootstrapSqlSet
        <$> loadSqlFileOrFallback (rpSchemaSql paths) schemaSQL
        <*> loadSqlFileOrFallback (rpSeedClusters paths) seedClustersSQL
        <*> loadSqlFileOrFallback (rpSeedTemplates paths) seedTemplatesSQL
        <*> loadSqlFileOrFallback (rpSeedIdentity paths) seedIdentitySQL

fallbackBootstrapSqlSet :: BootstrapSqlSet
fallbackBootstrapSqlSet =
  BootstrapSqlSet
    { bootstrapSchema = schemaSQL
    , bootstrapClusters = seedClustersSQL
    , bootstrapTemplates = seedTemplatesSQL
    , bootstrapIdentity = seedIdentitySQL
    }

loadSqlFileOrFallback :: FilePath -> Text -> IO Text
loadSqlFileOrFallback path fallback = do
  exists <- doesFileExist path
  if exists
    then TIO.readFile path `catchIO` onFailure
    else allowEmbeddedSqlFallback ("SQL file not found: " <> T.pack path) fallback
  where
    onFailure :: IOException -> IO Text
    onFailure err =
      allowEmbeddedSqlFallback
        ("SQL file read failed: " <> T.pack path <> " (" <> T.pack (show err) <> ")")
        fallback

allowEmbeddedSqlFallback :: Text -> a -> IO a
allowEmbeddedSqlFallback reason fallbackValue = do
  mFallback <- lookupEnv "QXFX0_ALLOW_EMBEDDED_SQL_FALLBACK"
  case mFallback of
    Just "1" -> pure fallbackValue
    _ ->
      throwQxFx0
        (SQLiteError $
          "embedded SQL fallback disabled; canonical spec/sql is required: " <> reason
        )

insertSchemaVersion :: NSQL.Database -> Int -> Text -> IO ()
insertSchemaVersion db version description = do
  mStmt <- NSQL.prepare db "INSERT OR REPLACE INTO schema_version(version, description) VALUES(?, ?)"
  case mStmt of
    Left err -> throwQxFx0 (SQLiteError $ "schema version insert prepare failed: " <> err)
    Right stmt -> do
      _ <- NSQL.bindInt stmt 1 version
      _ <- NSQL.bindText stmt 2 description
      _ <- NSQL.step stmt
      _ <- tryQxFx0 (NSQL.finalize stmt)
      pure ()

-- | Explicit, idempotent migration step.
data MigrationStep
  = EnsureColumn !Text !Text !Text       -- ^ table, column, definition
  deriving stock (Eq, Show)

-- | Run all pending migrations from (currentVersion + 1) up to currentSchemaVersion.
--   Wrapped in a transaction: version marker is only committed after validation succeeds.
runPendingMigrations :: NSQL.Database -> Int -> IO ()
runPendingMigrations db currentVersion = do
  let steps = resolveMigrationSteps currentVersion
  beginResult <- NSQL.execSql db "BEGIN IMMEDIATE;"
  case beginResult of
    Left err ->
      throwQxFx0 (SQLiteError $ "migration tx begin failed: " <> err)
    Right _ ->
      pure ()
  -- Run migration steps
  flip finally (rollbackOnException db) $ do
    mapM_ (runMigrationStep db) steps
    -- Validate before committing
    contractResult <- validateSchemaContractTablesAndColumns db
    case contractResult of
      SchemaContractOk _ -> do
        insertSchemaVersion db currentSchemaVersion currentSchemaDescription
        commitResult <- NSQL.execSql db "COMMIT;"
        case commitResult of
          Left err ->
            throwQxFx0 (SQLiteError $ "migration tx commit failed: " <> err)
          Right _ ->
            pure ()
      other -> do
        rollbackResult <- NSQL.execSql db "ROLLBACK;"
        case rollbackResult of
          Left rbErr ->
            throwQxFx0 (SQLiteError $
              "migration validation failed: " <> renderSchemaContractResult other
              <> "; rollback also failed: " <> rbErr)
          Right _ ->
            throwQxFx0 (SQLiteError $
              "migration validation failed: " <> renderSchemaContractResult other)

rollbackOnException :: NSQL.Database -> IO ()
rollbackOnException db = do
  _ <- NSQL.execSql db "ROLLBACK;"
  pure ()

resolveMigrationSteps :: Int -> [MigrationStep]
resolveMigrationSteps fromVersion
  = concat
      [ if fromVersion < 2
          then
            [ EnsureColumn "turn_quality" "warranted_mode" "TEXT NOT NULL DEFAULT 'ConditionallyWarranted'"
            , EnsureColumn "turn_quality" "decision_disposition" "TEXT NOT NULL DEFAULT 'advisory'"
            , EnsureColumn "turn_quality" "shadow_snapshot_id" "TEXT NOT NULL DEFAULT ''"
            , EnsureColumn "turn_quality" "shadow_divergence_kind" "TEXT NOT NULL DEFAULT 'none'"
            , EnsureColumn "turn_quality" "replay_trace_json" "TEXT NOT NULL DEFAULT '{}'"
            ]
          else []
      , if fromVersion < 3
          then
            [ EnsureColumn "shadow_divergence_log" "shadow_snapshot_id" "TEXT NOT NULL DEFAULT ''"
            , EnsureColumn "shadow_divergence_log" "shadow_divergence_kind" "TEXT NOT NULL DEFAULT 'none'"
            ]
          else []
      ]

runMigrationStep :: NSQL.Database -> MigrationStep -> IO ()
runMigrationStep db step = case step of
  EnsureColumn table col def -> do
    missing <- columnMissing db table col
    if missing
      then do
        let sql = "ALTER TABLE " <> table <> " ADD COLUMN " <> col <> " " <> def
        result <- NSQL.execSql db sql
        case result of
          Left err ->
            throwQxFx0
              (SQLiteError $
                "migration_failed stage=ensure_column table=" <> table
                <> " column=" <> col <> " sqlite=" <> err)
          Right _ -> pure ()
      else pure ()

execBootstrapSql :: NSQL.Database -> (FilePath, Text) -> IO ()
execBootstrapSql db (label, sqlText) = do
  result <- NSQL.execSql db sqlText
  case result of
    Left err -> throwQxFx0 (SQLiteError $ T.pack ("bootstrap SQL failed for " <> label <> ": ") <> err)
    Right _ -> pure ()

seedBootstrapSql :: NSQL.Database -> Text -> (FilePath, Text) -> IO ()
seedBootstrapSql db tableName payload = do
  query <- tableHasRowsQuery tableName
  hasRows <- tableHasRows db query
  if hasRows
    then pure ()
    else execBootstrapSql db payload

tableHasRowsQuery :: Text -> IO Text
tableHasRowsQuery tableName =
  case tableName of
    "semantic_clusters" -> pure "SELECT 1 FROM semantic_clusters LIMIT 1"
    "realization_templates" -> pure "SELECT 1 FROM realization_templates LIMIT 1"
    "identity_claims" -> pure "SELECT 1 FROM identity_claims LIMIT 1"
    _ ->
      throwQxFx0
        (SQLiteError
          ("unsupported bootstrap seed table name: " <> tableName))

tableHasRows :: NSQL.Database -> Text -> IO Bool
tableHasRows db sql = do
  withPreparedStatement db sql "tableHasRows query" NSQL.stepRow

withPreparedStatement :: NSQL.Database -> Text -> Text -> (NSQL.Statement -> IO a) -> IO a
withPreparedStatement db sql context action = do
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err ->
      throwQxFx0 (SQLiteError (context <> " prepare failed: " <> err))
    Right stmt ->
      action stmt `finally` finalizeBestEffort stmt

finalizeBestEffort :: NSQL.Statement -> IO ()
finalizeBestEffort stmt = do
  _ <- tryQxFx0 (NSQL.finalize stmt)
  pure ()
