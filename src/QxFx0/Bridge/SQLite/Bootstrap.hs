{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Schema bootstrap, migration runner, and seed loading for the runtime SQLite backend. -}
module QxFx0.Bridge.SQLite.Bootstrap
  ( currentSchemaVersion
  , ensureSchemaMigrations
  ) where

import Control.Exception (IOException, finally)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
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
  , ProbeOutcome(..)
  , renderSchemaContractResult
  , columnExists
  , isV1Shape
  , isV2Shape
  )
import qualified Data.Map.Strict as Map
import QxFx0.ExceptionPolicy
  ( catchIO
  , mkSQLiteError
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
import System.Environment (lookupEnv)

currentSchemaDescription :: Text
currentSchemaDescription = "Runtime schema v4: runtime_sessions.state_revision for optimistic-concurrency revision tracking"

ensureSchemaMigrations :: NSQL.Database -> IO ()
ensureSchemaMigrations db = do
  sqlSet <- loadBootstrapSqlSet
  -- 1. Run canonical schema (IF NOT EXISTS — safe for old and new DBs)
  execBootstrapSql db ("schema.sql", bootstrapSchema sqlSet)
  -- 2. Determine current version state and act accordingly.
  -- A failed probe (audit 2026-10-16 п.23) is an error, never a
  -- version fact: it must not stamp a version, migrate, or seed.
  let throwProbeError probeErr =
        throwQxFx0 (mkSQLiteError "schema_probe_failed" probeErr Map.empty)
      resolveUnversioned = do
        isV1 <- isV1Shape db
        case isV1 of
          Left probeErr -> throwProbeError probeErr
          Right True -> do
            runPendingMigrations db 1
            seedAfterMigration sqlSet db
          Right False -> do
            isV2 <- isV2Shape db
            case isV2 of
              Left probeErr -> throwProbeError probeErr
              Right _ -> do
                -- v2-complete database missing its marker, or a fresh
                -- database: stamp the current version and seed.
                insertSchemaVersion db currentSchemaVersion currentSchemaDescription
                seedAfterMigration sqlSet db
  versionStatus <- readSchemaVersion db
  case versionStatus of
    SchemaVersionProbeError probeErr ->
      throwProbeError probeErr
    SchemaVersionMissingTable -> resolveUnversioned
    SchemaVersionEmpty -> resolveUnversioned
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
            (mkSQLiteError
              "schema_version_check"
              "VERSION_MISMATCH"
              (Map.fromList
                [ ("expected", T.pack (show currentSchemaVersion))
                , ("found", T.pack (show v))
                ]))
  -- 3. Post-bootstrap validation
  contractResult <- checkSchemaContract db
  case contractResult of
    SchemaContractOk _ -> pure ()
    SchemaContractFreshBootstrapable -> pure ()
    SchemaContractVersionBehind expected actual ->
      throwQxFx0 (mkSQLiteError
        "schema_contract"
        "VERSION_BEHIND"
        (Map.fromList [("expected", T.pack (show expected)), ("actual", T.pack (show actual))]))
    SchemaContractMissingTable t ->
      throwQxFx0 (mkSQLiteError "schema_contract" "MISSING_TABLE" (Map.singleton "table" t))
    SchemaContractMissingColumns t cols ->
      throwQxFx0 (mkSQLiteError
        "schema_contract"
        "MISSING_COLUMNS"
        (Map.fromList [("table", t), ("columns", T.intercalate ", " cols)]))
    SchemaContractMissingIndex ix ->
      throwQxFx0 (mkSQLiteError "schema_contract" "MISSING_INDEX" (Map.singleton "index" ix))
    SchemaContractMissingTrigger tr ->
      throwQxFx0 (mkSQLiteError "schema_contract" "MISSING_TRIGGER" (Map.singleton "trigger" tr))
    SchemaContractMissingFTS fts ->
      throwQxFx0 (mkSQLiteError "schema_contract" "MISSING_FTS" (Map.singleton "fts_table" fts))
    SchemaContractInconsistent reason ->
      throwQxFx0 (mkSQLiteError "schema_contract" "INCONSISTENT" (Map.singleton "reason" reason))
    SchemaContractQueryFailed msg ->
      throwQxFx0 (mkSQLiteError "schema_contract" "QUERY_FAILED" (Map.singleton "message" msg))

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
loadSqlFileOrFallback path fallback =
  TIO.readFile path `catchIO` onFailure
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
        (mkSQLiteError
          "embedded_sql_fallback"
          "FALLBACK_DISABLED"
          (Map.singleton "reason" reason))

-- | Stamp the version marker.  Audit 2026-10-16 п.22: bind/step/finalize
-- results are checked — a failed INSERT is an error, not a silent success
-- with no version row.
insertSchemaVersion :: NSQL.Database -> Int -> Text -> IO ()
insertSchemaVersion db version description = do
  mStmt <- NSQL.prepare db "INSERT OR REPLACE INTO schema_version(version, description) VALUES(?, ?)"
  case mStmt of
    Left err -> throwQxFx0 (mkSQLiteError "schema_version_insert" err Map.empty)
    Right stmt -> do
      bindVersion <- NSQL.bindInt stmt 1 version
      bindDescription <- NSQL.bindText stmt 2 description
      stepResult <- NSQL.step stmt
      finalizeResult <- tryQxFx0 (NSQL.finalize stmt)
      let firstFailure =
            case bindVersion of
              Left err -> Just err
              Right () -> case bindDescription of
                Left err -> Just err
                Right () -> case stepResult of
                  Left err -> Just err
                  Right _ -> Nothing
      case firstFailure of
        Just err -> throwQxFx0 (mkSQLiteError "schema_version_insert" err Map.empty)
        Nothing -> case finalizeResult of
          Left err -> throwQxFx0 err
          Right () -> pure ()

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
      throwQxFx0 (mkSQLiteError "migration_tx_begin" err Map.empty)
    Right _ ->
      pure ()
  -- Audit 2026-10-16 п.22: rollback only while the transaction is still
  -- open — never after a successful COMMIT.
  txClosedRef <- newIORef False
  flip finally (rollbackIfOpen txClosedRef db) $ do
    -- Run migration steps
    mapM_ (runMigrationStep db) steps
    -- Validate before committing
    contractResult <- validateSchemaContractTablesAndColumns db
    case contractResult of
      SchemaContractOk _ -> do
        insertSchemaVersion db currentSchemaVersion currentSchemaDescription
        commitResult <- NSQL.execSql db "COMMIT;"
        case commitResult of
          Left err ->
            throwQxFx0 (mkSQLiteError "migration_tx_commit" err Map.empty)
          Right _ ->
            writeIORef txClosedRef True
      other -> do
        rollbackResult <- NSQL.execSql db "ROLLBACK;"
        case rollbackResult of
          Left rbErr ->
            throwQxFx0 (mkSQLiteError
              "migration_validation"
              "VALIDATION_FAILED_ROLLBACK_FAILED"
              (Map.fromList
                [ ("validation_error", renderSchemaContractResult other)
                , ("rollback_error", rbErr)
                ]))
          Right _ -> do
            writeIORef txClosedRef True
            throwQxFx0 (mkSQLiteError
              "migration_validation"
              "VALIDATION_FAILED"
              (Map.singleton "error" (renderSchemaContractResult other)))

-- | Best-effort rollback for the exception path; skipped when the
-- transaction has already been committed or explicitly rolled back.
rollbackIfOpen :: IORef Bool -> NSQL.Database -> IO ()
rollbackIfOpen txClosedRef db = do
  txClosed <- readIORef txClosedRef
  if txClosed
    then pure ()
    else do
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
      , if fromVersion < 4
          then
            [ EnsureColumn "runtime_sessions" "state_revision" "INTEGER NOT NULL DEFAULT 0"
            ]
          else []
      ]

runMigrationStep :: NSQL.Database -> MigrationStep -> IO ()
runMigrationStep db step = case step of
  EnsureColumn table col def -> do
    probe <- columnExists db table col
    case probe of
      ProbeFound -> pure ()
      ProbeFailed probeErr ->
        throwQxFx0
          (mkSQLiteError
            "schema_probe_failed"
            probeErr
            (Map.fromList [("table", table), ("column", col)]))
      ProbeNotFound -> do
        let sql = "ALTER TABLE " <> table <> " ADD COLUMN " <> col <> " " <> def
        result <- NSQL.execSql db sql
        case result of
          Left err ->
            throwQxFx0
              (mkSQLiteError
                "migration_ensure_column"
                err
                (Map.fromList [("table", table), ("column", col)]))
          Right _ -> pure ()

execBootstrapSql :: NSQL.Database -> (FilePath, Text) -> IO ()
execBootstrapSql db (label, sqlText) = do
  result <- NSQL.execSql db sqlText
  case result of
    Left err -> throwQxFx0 (mkSQLiteError "bootstrap_sql" err (Map.singleton "label" (T.pack label)))
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
        (mkSQLiteError
          "bootstrap_seed"
          "UNSUPPORTED_TABLE"
          (Map.singleton "table_name" tableName))

tableHasRows :: NSQL.Database -> Text -> IO Bool
tableHasRows db sql = do
  withPreparedStatement db sql "tableHasRows query" NSQL.stepRow

withPreparedStatement :: NSQL.Database -> Text -> Text -> (NSQL.Statement -> IO a) -> IO a
withPreparedStatement db sql context action = do
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err ->
      throwQxFx0 (mkSQLiteError "prepare" err (Map.singleton "context" context))
    Right stmt ->
      action stmt `finally` finalizeBestEffort stmt

finalizeBestEffort :: NSQL.Statement -> IO ()
finalizeBestEffort stmt = do
  _ <- tryQxFx0 (NSQL.finalize stmt)
  pure ()
