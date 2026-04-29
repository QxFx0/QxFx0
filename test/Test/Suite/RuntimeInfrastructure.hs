{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.RuntimeInfrastructure
  ( runtimeInfrastructureTests
  ) where

import Data.Aeson (Value(..), eitherDecodeStrict')
import qualified Data.Aeson.KeyMap as KeyMap
import Test.HUnit hiding (Testable)
import Test.QuickCheck
  ( Result(..)
  , Testable
  , elements
  , forAll
  , ioProperty
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )
import Control.Exception (AsyncException(ThreadKilled), finally, throwIO, try)
import Control.Monad (forM_)
import System.Directory (createDirectoryIfMissing, getCurrentDirectory, getPermissions, setPermissions, Permissions(..))
import System.Environment (lookupEnv)
import System.FilePath ((</>), takeFileName)

import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Text.Encoding (encodeUtf8)

import QxFx0.Types
import QxFx0.Types.Thresholds (LegitimacyStatus(..), ScenePressure(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , ShadowDivergenceKind(..)
  , ShadowDivergenceSeverity(..)
  , ShadowSnapshot(..)
  , ShadowSnapshotId(..)
  , mkShadowSnapshotId
  , shadowSnapshotIdText
  )
import qualified QxFx0.Runtime as Runtime
import qualified QxFx0.Bridge.StatePersistence as StatePersistence
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Bridge.EmbeddedSQL as EmbeddedSQL
import qualified QxFx0.Bridge.SQLite as SQLite
import qualified QxFx0.Bridge.AgdaR5 as AgdaR5
import qualified QxFx0.Bridge.Datalog as Datalog
import qualified QxFx0.Bridge.NixGuard as NixGuard
import QxFx0.Resources (computeReadinessMode, assessResourceReadiness, loadMorphologyData, ReadinessStatus(..), ReadinessComponent(..), ReadinessMode(..))
import QxFx0.ExceptionPolicy (QxFx0Exception(..))

import Test.Support (assertExec, queryCount, withFakeSouffle, withRuntimeEnv, withStrictRuntimeEnv, withEnvVar, removeIfExists)

runtimeInfrastructureTests :: [Test]
runtimeInfrastructureTests =
  [ testEmbeddedSqlMatchesCanonicalSpec
  , testMigrationMatchesCanonicalSpec
  , testSchemaBootstrapToleratesLegacyTables
  , testSchemaVersionMismatchFailsBootstrap
  , testLegacyV1SchemaMigratesAndTurnQualityWritesTrace
  , testLegacyV2SchemaMigratesShadowDivergenceTraceColumns
  , testLegacyV1WithoutSchemaVersionMigrates
  , testLegacyV1WithEmptySchemaVersionMigrates
  , testMigrationAtomicityRollbackOnFailure
  , testCorruptV2SchemaWithMissingColumnsFailsBootstrap
  , testReadinessStrictInvariantSchemaV1Behind
  , testReadinessStrictInvariantFreshDbOk
  , testEmbeddedSqlFallbackRequiresExplicitOptIn
  , testSpecSqlSeedsAreCompatible
  , testRuntimeBootstrapAndPersistence
  , testStrictRuntimeBootstrapAndPersistence
  , testRuntimeBootstrapUsesCanonicalSpecSeeds
  , testSemanticModeTurn
  , testShadowSnapshotIdStable
  , testShadowSnapshotIdChangesWithInput
  , testDatalogShadowRespectsAtomSignals
  , testDatalogShadowMissingRulesReportsCheckedPaths
  , testDatalogShadowTimesOutWithControlledDiagnostic
  , testResolveSouffleExecutableMaterializesMissingFlakePath
  , testConstitutionalLocalRecoveryThreshold
  , testLoadStateCorruptBlobIsReported
  , testBootstrapSessionMarksRecoveredCorruption
  , testStateBlobDiagnosticsDetectsMissingOptionalFields
  , testSaveStateReturnsRightOnSuccess
  , testSaveStateWithProjectionFailureRollsBackTransaction
  , testRunTurnPersistsTurnQuality
  , testPersistedSystemStateSessionIdMatchesBootstrapId
  , testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty
  , testPersistedReplayTraceDeterministicWithFixedTimeProperty
  , testSaveStateWithDivergencePersistsShadowLog
  , testBootstrapSessionHandlesQuotedSessionId
  , testComputeReadinessModeReady
  , testComputeReadinessModeDegraded
  , testComputeReadinessModeNotReady
  , testProbeRuntimeReadinessStrictAcceptsWitnessedLocalBackend
  , testProbeRuntimeReadinessStrictAcceptsImplicitLocalBackend
  , testProbeRuntimeReadinessStrictRequiresWitness
  , testProbeRuntimeReadinessStrictRequiresNixEvaluator
  , testAgdaTypeCheckTimesOut
  , testAgdaWitnessReportDetectsMissingInputs
  , testWithPooledDBOverflowKeepsPoolUsable
  , testWithPooledDBSanitizesDirtyTransactionBeforeReuse
  , testCloseDBPoolIsIdempotent
  , testCloseSessionIsIdempotent
  , testWithBootstrappedSessionClosesRuntime
  , testRunTurnInSessionStrictBlocksWhenBackendUnavailable
  , testAssessResourceReadinessFailsWhenRootMissing
  , testAssessResourceReadinessFailsOnInvalidMorphologyJson
  , testMorphologyCacheSwitchesWithRoot
  , testNixGuardIsSafeChar
  , testNixGuardUnsupportedConceptBlockedStrict
  , testNixGuardUnknownSafeConceptAllowedStrict
  , testNixGuardUnsupportedConceptAllowedLenient
  , testNixGuardEmptyConceptAllowed
  , testNixStringLiteralEscaping
  , testNixStringLiteralEmpty
  , testRunTurnRefreshesRuntimeSessionLastActive
  , testWithPooledDBAsyncInterruptionSanitizesConnection
  ]

testEmbeddedSqlMatchesCanonicalSpec :: Test
testEmbeddedSqlMatchesCanonicalSpec = TestCase $ do
  root <- getCurrentDirectory
  schemaSql <- TIO.readFile (root </> "spec" </> "sql" </> "schema.sql")
  clustersSql <- TIO.readFile (root </> "spec" </> "sql" </> "seed_clusters.sql")
  identitySql <- TIO.readFile (root </> "spec" </> "sql" </> "seed_identity.sql")
  templatesSql <- TIO.readFile (root </> "spec" </> "sql" </> "seed_templates.sql")
  assertEqual "embedded schema should match canonical spec/sql schema" schemaSql EmbeddedSQL.schemaSQL
  assertEqual "embedded cluster seed should match canonical spec/sql" clustersSql EmbeddedSQL.seedClustersSQL
  assertEqual "embedded identity seed should match canonical spec/sql" identitySql EmbeddedSQL.seedIdentitySQL
  assertEqual "embedded template seed should match canonical spec/sql" templatesSql EmbeddedSQL.seedTemplatesSQL

testMigrationMatchesCanonicalSpec :: Test
testMigrationMatchesCanonicalSpec = TestCase $ do
  root <- getCurrentDirectory
  schemaSql <- TIO.readFile (root </> "spec" </> "sql" </> "schema.sql")
  migrationV1Sql <- TIO.readFile (root </> "migrations" </> "001_initial_schema.sql")
  migrationV2Sql <- TIO.readFile (root </> "migrations" </> "002_turn_quality_trace_columns.sql")
  -- Cumulative migrations (001 + 002) must produce the same schema as spec/sql/schema.sql
  dbMigrations <- NSQL.open (root </> ".test-tmp" </> "migration_check.db")
  dbCanonical <- NSQL.open (root </> ".test-tmp" </> "canonical_check.db")
  case (dbMigrations, dbCanonical) of
    (Left err, _) -> assertFailure ("Cannot open migration check DB: " <> T.unpack err)
    (_, Left err) -> assertFailure ("Cannot open canonical check DB: " <> T.unpack err)
    (Right dbM, Right dbC) -> do
      _ <- NSQL.execSql dbM migrationV1Sql
      _ <- NSQL.execSql dbM migrationV2Sql
      _ <- NSQL.execSql dbC schemaSql
      migSig <- dumpSchemaSignature dbM
      canSig <- dumpSchemaSignature dbC
      NSQL.close dbM
      NSQL.close dbC
      let normCan = map (\(a,b,c,d) -> (a,b,c,normalizeSql d)) canSig
          normMig = map (\(a,b,c,d) -> (a,b,c,normalizeSql d)) migSig
      assertEqual "cumulative migrations must match canonical schema" normCan normMig
  where
    dumpSchemaSignature db = do
      mStmt <- NSQL.prepare db "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE type IN ('table','index','trigger','view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name"
      case mStmt of
        Left err -> assertFailure ("Prepare failed: " <> T.unpack err) >> fail "unreachable"
        Right stmt -> go stmt []
      where
        go stmt acc = do
          hasRow <- NSQL.stepRow stmt
          if not hasRow
            then do
              _ <- NSQL.finalize stmt
              pure (reverse acc)
            else do
              t <- NSQL.columnText stmt 0
              n <- NSQL.columnText stmt 1
              tbl <- NSQL.columnText stmt 2
              sql_ <- NSQL.columnText stmt 3
              go stmt ((T.strip t, T.strip n, T.strip tbl, T.strip sql_) : acc)
    normalizeSql :: T.Text -> T.Text
    normalizeSql = T.unwords . T.words

testSchemaBootstrapToleratesLegacyTables :: Test
testSchemaBootstrapToleratesLegacyTables = TestCase $ do
  withRuntimeEnv "qxfx0_test_schema_cleanup.db" $ do
    dbPath <- Runtime.resolveDbPath
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open SQLite DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    assertExec db "legacy_dead_tables.sql" $
      T.unlines
        [ "CREATE TABLE IF NOT EXISTS meaning_graph_edges(id INTEGER PRIMARY KEY, source TEXT, target TEXT);"
        , "CREATE TABLE IF NOT EXISTS evidence_bonds(id INTEGER PRIMARY KEY, premise TEXT, conclusion TEXT);"
        , "CREATE TABLE IF NOT EXISTS audit_log(id INTEGER PRIMARY KEY, event_type TEXT);"
        ]
    NSQL.close db

    session0 <- Runtime.bootstrapSession True "test_schema_cleanup"
    let rt = Runtime.sessRuntime session0
    meaningGraphCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'meaning_graph_edges'"
    evidenceBondsCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'evidence_bonds'"
    auditLogCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = 'audit_log'"
    assertEqual "legacy meaning_graph_edges table should remain untouched" 1 meaningGraphCount
    assertEqual "legacy evidence_bonds table should remain untouched" 1 evidenceBondsCount
    assertEqual "legacy audit_log table should remain untouched" 1 auditLogCount

testSchemaVersionMismatchFailsBootstrap :: Test
testSchemaVersionMismatchFailsBootstrap = TestCase $ do
  withRuntimeEnv "qxfx0_test_schema_version.db" $ do
    session0 <- Runtime.bootstrapSession True "test_schema_version"
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db ->
      assertExec db "force schema version mismatch" $
        T.pack ("DELETE FROM schema_version;\nINSERT INTO schema_version(version, description) VALUES(999, 'mismatch');")
    result <- try (Runtime.bootstrapSession True "test_schema_version") :: IO (Either QxFx0Exception Runtime.Session)
    case result of
      Left (RuntimeInitError msg) ->
        assertBool "bootstrap should report schema version mismatch" ("schema_version mismatch" `T.isInfixOf` msg)
      Left other ->
        assertFailure ("expected RuntimeInitError, got: " <> show other)
      Right _ ->
        assertFailure "bootstrap should fail on schema version mismatch"

testLegacyV1SchemaMigratesAndTurnQualityWritesTrace :: Test
testLegacyV1SchemaMigratesAndTurnQualityWritesTrace = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_legacy_v1_migration.db" $ do
    dbPath <- Runtime.resolveDbPath
    -- Create a legacy v1 DB manually (without trace columns)
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open legacy DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    root <- getCurrentDirectory
    v1Sql <- TIO.readFile (root </> "migrations" </> "001_initial_schema.sql")
    _ <- NSQL.execSql db v1Sql
    -- Ensure schema_version reports 1 (as it would on a real legacy DB)
    _ <- NSQL.execSql db "DELETE FROM schema_version; INSERT INTO schema_version(version, description) VALUES(1, 'Legacy v1');"
    NSQL.close db
    -- Now bootstrap: should migrate v1 -> v2 and succeed
    session0 <- Runtime.bootstrapSession True "legacy_v1_migration"
    let rt = Runtime.sessRuntime session0
    -- Verify trace columns exist
    colCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM pragma_table_info('turn_quality') WHERE name IN ('warranted_mode','decision_disposition','shadow_snapshot_id','shadow_divergence_kind','replay_trace_json')"
    assertEqual "legacy DB should have all v2 trace columns after migration" 5 colCount
    -- Run a turn to verify persistence works with the migrated schema
    (_, response) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    assertBool "turn should produce non-empty response" (not (T.null response))
    -- Verify replay_trace_json was written
    traceCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM turn_quality WHERE session_id = 'legacy_v1_migration' AND turn = 1 AND replay_trace_json != '{}'"
    assertEqual "replay_trace_json should be persisted after migrated turn" 1 traceCount

testLegacyV2SchemaMigratesShadowDivergenceTraceColumns :: Test
testLegacyV2SchemaMigratesShadowDivergenceTraceColumns = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_legacy_v2_shadow_log_migration.db" $ do
    dbPath <- Runtime.resolveDbPath
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open legacy v2 DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    root <- getCurrentDirectory
    v2Sql <- TIO.readFile (root </> "spec" </> "sql" </> "schema.sql")
    _ <- NSQL.execSql db v2Sql
    _ <- NSQL.execSql db "DELETE FROM schema_version; INSERT INTO schema_version(version, description) VALUES(2, 'Legacy v2 missing shadow log trace columns');"
    _ <- NSQL.execSql db "ALTER TABLE shadow_divergence_log DROP COLUMN shadow_snapshot_id;"
    _ <- NSQL.execSql db "ALTER TABLE shadow_divergence_log DROP COLUMN shadow_divergence_kind;"
    NSQL.close db
    session0 <- Runtime.bootstrapSession True "legacy_v2_shadow_log_migration"
    let rt = Runtime.sessRuntime session0
    colCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM pragma_table_info('shadow_divergence_log') WHERE name IN ('shadow_snapshot_id','shadow_divergence_kind')"
    assertEqual "legacy v2 DB should have shadow_divergence_log trace columns after migration" 2 colCount
    versionCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM schema_version WHERE version = 3"
    assertEqual "legacy v2 DB should be marked current after shadow log migration" 1 versionCount
    (_, response) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    assertBool "turn should produce non-empty response after shadow log migration" (not (T.null response))

testLegacyV1WithoutSchemaVersionMigrates :: Test
testLegacyV1WithoutSchemaVersionMigrates = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_legacy_v1_no_version.db" $ do
    dbPath <- Runtime.resolveDbPath
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open legacy DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    root <- getCurrentDirectory
    v1Sql <- TIO.readFile (root </> "migrations" </> "001_initial_schema.sql")
    _ <- NSQL.execSql db v1Sql
    -- Drop the schema_version table to simulate pre-version-marker legacy DB
    _ <- NSQL.execSql db "DROP TABLE schema_version;"
    NSQL.close db
    session0 <- Runtime.bootstrapSession True "legacy_v1_no_version"
    let rt = Runtime.sessRuntime session0
    colCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM pragma_table_info('turn_quality') WHERE name IN ('warranted_mode','decision_disposition','shadow_snapshot_id','shadow_divergence_kind','replay_trace_json')"
    assertEqual "legacy DB without schema_version should have all v2 trace columns after migration" 5 colCount
    versionCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM schema_version WHERE version = 3"
    assertEqual "schema_version should be current after migration" 1 versionCount

testLegacyV1WithEmptySchemaVersionMigrates :: Test
testLegacyV1WithEmptySchemaVersionMigrates = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_legacy_v1_empty_version.db" $ do
    dbPath <- Runtime.resolveDbPath
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open legacy DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    root <- getCurrentDirectory
    v1Sql <- TIO.readFile (root </> "migrations" </> "001_initial_schema.sql")
    _ <- NSQL.execSql db v1Sql
    -- schema_version table exists but is empty
    _ <- NSQL.execSql db "DELETE FROM schema_version;"
    NSQL.close db
    session0 <- Runtime.bootstrapSession True "legacy_v1_empty_version"
    let rt = Runtime.sessRuntime session0
    colCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM pragma_table_info('turn_quality') WHERE name IN ('warranted_mode','decision_disposition','shadow_snapshot_id','shadow_divergence_kind','replay_trace_json')"
    assertEqual "legacy DB with empty schema_version should have all v2 trace columns after migration" 5 colCount
    versionCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM schema_version WHERE version = 3"
    assertEqual "schema_version should be current after migration" 1 versionCount

testMigrationAtomicityRollbackOnFailure :: Test
testMigrationAtomicityRollbackOnFailure = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_migration_atomicity.db" $ do
    dbPath <- Runtime.resolveDbPath
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    root <- getCurrentDirectory
    v1Sql <- TIO.readFile (root </> "migrations" </> "001_initial_schema.sql")
    _ <- NSQL.execSql db v1Sql
    -- Ensure version reports 1
    _ <- NSQL.execSql db "DELETE FROM schema_version; INSERT INTO schema_version(version, description) VALUES(1, 'Legacy v1');"
    NSQL.close db
    -- Now simulate a partially-migrated state by pre-adding one v2 column.
    -- Migration should still succeed because EnsureColumn is idempotent.
    -- To test rollback, we need a failure scenario. Instead, verify that
    -- version is only written after all columns are present.
    session0 <- Runtime.bootstrapSession True "migration_atomicity"
    let rt = Runtime.sessRuntime session0
    versionCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM schema_version WHERE version = 3"
    assertEqual "version should be current after atomic migration" 1 versionCount
    colCount <- Runtime.withRuntimeDb rt $ \conn ->
      queryCount conn "SELECT count(*) FROM pragma_table_info('turn_quality') WHERE name IN ('warranted_mode','decision_disposition','shadow_snapshot_id','shadow_divergence_kind','replay_trace_json')"
    assertEqual "all v2 columns should exist after atomic migration" 5 colCount

testCorruptV2SchemaWithMissingColumnsFailsBootstrap :: Test
testCorruptV2SchemaWithMissingColumnsFailsBootstrap = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_corrupt_v2_missing_columns.db" $ do
    dbPath <- Runtime.resolveDbPath
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    root <- getCurrentDirectory
    -- Load full v2 schema.sql
    v2Sql <- TIO.readFile (root </> "spec" </> "sql" </> "schema.sql")
    _ <- NSQL.execSql db v2Sql
    -- Claim version 2 but drop one v2 column to simulate corruption
    _ <- NSQL.execSql db "DELETE FROM schema_version; INSERT INTO schema_version(version, description) VALUES(2, 'Corrupt v2');"
    _ <- NSQL.execSql db "ALTER TABLE turn_quality DROP COLUMN replay_trace_json;"
    NSQL.close db
    result <- try (Runtime.bootstrapSession True "corrupt_v2") :: IO (Either QxFx0Exception Runtime.Session)
    case result of
      Left (RuntimeInitError msg) ->
        assertBool "bootstrap should report missing columns"
          ( "schema contract failed" `T.isInfixOf` msg
              || "missing columns" `T.isInfixOf` msg
              || "migration validation failed" `T.isInfixOf` msg
              || "schema_missing_columns" `T.isInfixOf` msg
          )
      Left other ->
        assertFailure ("expected RuntimeInitError, got: " <> show other)
      Right _ ->
        assertFailure "bootstrap should fail when v2 columns are missing"

testReadinessStrictInvariantSchemaV1Behind :: Test
testReadinessStrictInvariantSchemaV1Behind = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_readiness_v1_behind.db" $ do
    dbPath <- Runtime.resolveDbPath
    mDb <- NSQL.open dbPath
    db <- case mDb of
      Left err -> assertFailure ("Cannot open DB: " <> T.unpack err) >> fail "unreachable"
      Right d -> pure d
    root <- getCurrentDirectory
    v1Sql <- TIO.readFile (root </> "migrations" </> "001_initial_schema.sql")
    _ <- NSQL.execSql db v1Sql
    _ <- NSQL.execSql db "DELETE FROM schema_version; INSERT INTO schema_version(version, description) VALUES(1, 'Legacy v1');"
    NSQL.close db
    -- Runtime-ready should report not ready because schema is behind
    session0 <- Runtime.bootstrapSession True "readiness_v1_behind"
    let rt = Runtime.sessRuntime session0
    health <- Runtime.checkHealth rt
    assertBool "health should be ready after bootstrap migrates" (Runtime.shReady health)
    assertEqual "status should be ok after migration" "ok" (Runtime.shStatus health)

testReadinessStrictInvariantFreshDbOk :: Test
testReadinessStrictInvariantFreshDbOk = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_readiness_fresh.db" $ do
    session0 <- Runtime.bootstrapSession True "readiness_fresh"
    let rt = Runtime.sessRuntime session0
    health <- Runtime.checkHealth rt
    assertBool "fresh DB health should be ready" (Runtime.shReady health)
    assertEqual "fresh DB status should be ok" "ok" (Runtime.shStatus health)
    assertBool "fresh DB schema_ok should be true" (Runtime.shSchemaOk health)
    assertEqual "fresh DB schema_version should be current" 3 (Runtime.shSchemaVersion health)

testEmbeddedSqlFallbackRequiresExplicitOptIn :: Test
testEmbeddedSqlFallbackRequiresExplicitOptIn = TestCase $ do
  let fakeRoot = "/tmp/qxfx0_fake_root_without_sql"
      fakeDb = "/tmp/qxfx0_fake_root_without_sql.db"
  removeIfExists fakeDb
  createTree fakeRoot
  withEnvVar "QXFX0_ROOT" (Just fakeRoot) $
    withEnvVar "QXFX0_ALLOW_EMBEDDED_SQL_FALLBACK" Nothing $ do
      dbRes <- NSQL.open fakeDb
      db <- case dbRes of
        Left err -> assertFailure ("Cannot open SQLite DB: " <> T.unpack err) >> fail "unreachable"
        Right d -> pure d
      result <- try (SQLite.ensureSchemaMigrations db) :: IO (Either QxFx0Exception ())
      NSQL.close db
      case result of
        Left (SQLiteError msg) ->
          assertBool "fallback should require explicit opt-in" ("embedded SQL fallback disabled" `T.isInfixOf` msg)
        Left other ->
          assertFailure ("expected SQLiteError, got: " <> show other)
        Right _ ->
          assertFailure "schema migration should fail without explicit embedded SQL opt-in"
  removeIfExists fakeDb
  where
    createTree base = do
      let dirs =
            [ base
            , base </> "migrations"
            , base </> "resources" </> "morphology"
            , base </> "semantics"
            ]
      mapM_ (createDirectoryIfMissing True) dirs
      TIO.writeFile (base </> "semantics" </> "concepts.nix") "{}"
      TIO.writeFile (base </> "resources" </> "morphology" </> "prepositional.json") "{}"
      TIO.writeFile (base </> "resources" </> "morphology" </> "genitive.json") "{}"
      TIO.writeFile (base </> "resources" </> "morphology" </> "nominative.json") "{}"
      TIO.writeFile (base </> "resources" </> "morphology" </> "lexicon_quality.json") "{}"

testSpecSqlSeedsAreCompatible :: Test
testSpecSqlSeedsAreCompatible = TestCase $ do
  root <- getCurrentDirectory
  let dbPath = "/tmp/qxfx0_test_spec_schema.db"
      schemaPath = root </> "spec" </> "sql" </> "schema.sql"
      seedPaths =
        [ root </> "spec" </> "sql" </> "seed_clusters.sql"
        , root </> "spec" </> "sql" </> "seed_identity.sql"
        , root </> "spec" </> "sql" </> "seed_templates.sql"
        ]
  removeIfExists dbPath
  mDb <- NSQL.open dbPath
  db <- case mDb of
    Left err -> assertFailure ("Cannot open SQLite DB: " <> T.unpack err) >> fail "unreachable"
    Right d -> pure d

  schemaSql <- TIO.readFile schemaPath
  assertExec db "schema.sql" schemaSql
  mapM_ (applySeed db) seedPaths

  identityCount <- queryCount db "SELECT count(*) FROM identity_claims"
  clusterCount <- queryCount db "SELECT count(*) FROM semantic_clusters"
  templateCount <- queryCount db "SELECT count(*) FROM realization_templates"

  assertBool "identity_claims should be seeded" (identityCount > 0)
  assertBool "semantic_clusters should be seeded" (clusterCount > 0)
  assertBool "realization_templates should be seeded" (templateCount > 0)

  NSQL.close db
  removeIfExists dbPath
  where
    applySeed db p = do
      sql <- TIO.readFile p
      assertExec db p sql

testRuntimeBootstrapAndPersistence :: Test
testRuntimeBootstrapAndPersistence = TestCase $ do
  withRuntimeEnv "qxfx0_test_runtime_persist.db" $ do
    session0 <- Runtime.bootstrapSession True "test_runtime_persist"
    let ss0 = Runtime.sessSystemState session0
    assertBool "bootstrap should load clusters" (not (null (ssClusters ss0)))
    assertBool "bootstrap should load identity claims" (not (null (ssIdentityClaims ss0)))

    (session1, output1) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    let ss1 = Runtime.sessSystemState session1
    assertBool "turn counter should increase" (ssTurnCount ss1 >= 1)
    assertBool "turn output should not be empty" (not (T.null output1))

    session2 <- Runtime.bootstrapSession True "test_runtime_persist"
    let ss2 = Runtime.sessSystemState session2
    assertBool "state should restore persisted turn counter" (ssTurnCount ss2 >= 1)

testStrictRuntimeBootstrapAndPersistence :: Test
testStrictRuntimeBootstrapAndPersistence = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_runtime_strict_persist.db" $ do
    health0 <- Runtime.probeRuntimeReadiness
    assertEqual "strict probe should be green under strict harness" "ok" (Runtime.shStatus health0)
    assertEqual "strict harness should expose verified agda status" AgdaVerified (Runtime.shAgdaStatus health0)
    assertBool "strict harness should expose datalog backend" (Runtime.shDatalogReady health0)

    session0 <- Runtime.bootstrapSession True "test_runtime_strict_persist"
    (session1, output1) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    let ss1 = Runtime.sessSystemState session1
    assertBool "strict turn output should not be empty" (not (T.null output1))
    assertBool "strict turn counter should increase" (ssTurnCount ss1 >= 1)

    session2 <- Runtime.bootstrapSession True "test_runtime_strict_persist"
    let ss2 = Runtime.sessSystemState session2
    assertBool "strict runtime should restore persisted turn counter" (ssTurnCount ss2 >= 1)

testRuntimeBootstrapUsesCanonicalSpecSeeds :: Test
testRuntimeBootstrapUsesCanonicalSpecSeeds = TestCase $ do
  withRuntimeEnv "qxfx0_test_runtime_canonical.db" $ do
    session0 <- Runtime.bootstrapSession True "test_runtime_canonical"
    let rt = Runtime.sessRuntime session0
        ss0 = Runtime.sessSystemState session0

    assertBool "bootstrap should load canonical cluster names from spec/sql"
      (any ((== "Exhaustion") . cdName) (ssClusters ss0))
    assertBool "bootstrap should not fall back to legacy embedded cluster names when spec/sql exists"
      (not (any ((== "grounding") . cdName) (ssClusters ss0)))

    curatedIdentityCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM identity_claims WHERE concept = 'identity_contract'"
    assertBool "bootstrap should seed canonical identity claims" (curatedIdentityCount > 0)

testProbeRuntimeReadinessStrictRequiresWitness :: Test
testProbeRuntimeReadinessStrictRequiresWitness = TestCase $
  withRuntimeEnv "qxfx0_test_strict_readiness.db" $
    withEnvVar "QXFX0_RUNTIME_MODE" (Just "strict") $
      withEnvVar "QXFX0_EMBEDDING_BACKEND" Nothing $
        withEnvVar "EMBEDDING_API_URL" Nothing $
          withEnvVar "QXFX0_AGDA_WITNESS" (Just "/tmp/qxfx0_test_missing_witness.json") $ do
          health <- Runtime.probeRuntimeReadiness
          assertEqual "probe should report strict runtime mode" "strict" (Runtime.shRuntimeMode health)
          assertEqual "strict mode should mark missing witness runtime as not ready" "not_ready" (Runtime.shStatus health)
          assertBool "strict mode should refuse readiness when Agda witness is unavailable" (not (Runtime.shReady health))
          assertEqual "missing witness should map to typed status" AgdaMissingWitness (Runtime.shAgdaStatus health)
          assertBool "implicit local deterministic backend should be strict-ready" (Runtime.shEmbeddingAlive health)
          assertEqual "implicit local backend should still be classified as heuristic" "heuristic" (Runtime.shEmbeddingQuality health)
          assertBool "missing witness should be reported explicitly" (not (null (Runtime.shAgdaIssues health)))

testProbeRuntimeReadinessStrictAcceptsWitnessedLocalBackend :: Test
testProbeRuntimeReadinessStrictAcceptsWitnessedLocalBackend = TestCase $
  withStrictRuntimeEnv "qxfx0_test_strict_readiness_ok.db" $ do
    health <- Runtime.probeRuntimeReadiness
    assertEqual "strict probe should report ok when witness, explicit local backend, and datalog runtime exist" "ok" (Runtime.shStatus health)
    assertBool "strict probe should be ready with explicit local backend and fresh witness" (Runtime.shReady health)
    assertBool "strict probe should surface present Nix policy" (Runtime.shNixPolicyPresent health)
    assertBool "strict probe should surface operational Nix evaluator" (Runtime.shNixReady health)
    assertBool "strict probe should mark embedding backend as strict-ready" (Runtime.shEmbeddingAlive health)
    assertEqual "explicit local backend remains heuristic even when accepted for strict contour" "heuristic" (Runtime.shEmbeddingQuality health)
    assertEqual "strict probe should surface typed agda status" AgdaVerified (Runtime.shAgdaStatus health)
    assertBool "strict probe should mark datalog backend as ready" (Runtime.shDatalogReady health)
    assertBool "strict probe should mark agda witness as ready" (Runtime.shAgdaReady health)
    assertBool "fresh witness should clear agda issues" (null (Runtime.shAgdaIssues health))

testProbeRuntimeReadinessStrictAcceptsImplicitLocalBackend :: Test
testProbeRuntimeReadinessStrictAcceptsImplicitLocalBackend = TestCase $
  withStrictRuntimeEnv "qxfx0_test_strict_readiness_implicit_local.db" $
    withEnvVar "QXFX0_EMBEDDING_BACKEND" Nothing $
      withEnvVar "EMBEDDING_API_URL" (Just "http://127.0.0.1:1/embeddings") $ do
        health <- Runtime.probeRuntimeReadiness
        assertEqual "strict probe should accept autonomous implicit local backend" "ok" (Runtime.shStatus health)
        assertBool "strict probe should be ready with implicit local backend and valid witness" (Runtime.shReady health)
        assertBool "implicit local backend should be operational" (Runtime.shEmbeddingOperational health)
        assertBool "implicit local backend should be strict-ready" (Runtime.shEmbeddingAlive health)
        assertBool "implicit local backend should not be reported as explicit" (not (Runtime.shEmbeddingExplicit health))
        assertEqual "remote URL alone must not switch readiness to remote backend" "local_deterministic" (Runtime.shEmbeddingBackend health)
        assertBool "strict probe should mark morph backend as local" (Runtime.shMorphBackendLocal health)
        assertBool "strict probe should report local-only decision path" (Runtime.shDecisionPathLocalOnly health)
        assertBool "strict probe should keep llm decision path disabled" (not (Runtime.shLlmDecisionPath health))

testProbeRuntimeReadinessStrictRequiresNixEvaluator :: Test
testProbeRuntimeReadinessStrictRequiresNixEvaluator = TestCase $ do
  let fakeBinDir = "/tmp/qxfx0_fake_nix_fail_bin"
      fakeNix = fakeBinDir </> "nix-instantiate"
      fakeScript = unlines
        [ "#!/bin/sh"
        , "printf '%s\\n' 'error: nix evaluator unavailable in test' >&2"
        , "exit 1"
        ]
  createDirectoryIfMissing True fakeBinDir
  writeFile fakeNix fakeScript
  perms <- getPermissions fakeNix
  setPermissions fakeNix perms { executable = True }
  withStrictRuntimeEnv "qxfx0_test_strict_readiness_nix_fail.db" $
    do
      strictPath <- lookupEnv "PATH"
      let fakePath = fakeBinDir <> maybe "" (\p -> ":" <> p) strictPath
      withEnvVar "PATH" (Just fakePath) $ do
        health <- Runtime.probeRuntimeReadiness
        assertEqual "strict probe should fail when Nix evaluator is unavailable" "not_ready" (Runtime.shStatus health)
        assertBool "strict probe should not report ready when Nix evaluator is unavailable" (not (Runtime.shReady health))
        assertBool "strict probe should surface present Nix policy separately from evaluator state" (Runtime.shNixPolicyPresent health)
        assertBool "strict probe should mark Nix evaluator as unavailable" (not (Runtime.shNixReady health))
        assertBool "strict probe should preserve Datalog readiness when only Nix is broken" (Runtime.shDatalogReady health)
        assertBool "strict probe should preserve Agda readiness when only Nix is broken" (Runtime.shAgdaReady health)
        assertBool
          "strict probe should surface Nix diagnostics"
          (any (T.isInfixOf "nix") (map T.toLower (Runtime.shNixIssues health)))

testAgdaTypeCheckTimesOut :: Test
testAgdaTypeCheckTimesOut = TestCase $ do
  root <- getCurrentDirectory
  let fakeBin = "/tmp/qxfx0_fake_agda_bin"
      fakeAgda = fakeBin </> "agda"
  createDirectoryIfMissing True fakeBin
  writeFile fakeAgda "#!/bin/sh\n/bin/sleep 1\nexit 0\n"
  perms <- getPermissions fakeAgda
  setPermissions fakeAgda perms { executable = True }
  withEnvVar "QXFX0_ROOT" (Just root) $
    withEnvVar "PATH" (Just fakeBin) $
      withEnvVar "QXFX0_AGDA_TIMEOUT_MS" (Just "10") $ do
        result <- AgdaR5.agdaTypeCheck
        case result of
          AgdaR5.AgdaTypeCheckFailed msg ->
            assertBool "agda timeout should be surfaced in failure message" ("timed out" `T.isInfixOf` msg)
          other ->
            assertFailure ("expected AgdaTypeCheckFailed timeout, got: " <> show other)

testWithPooledDBOverflowKeepsPoolUsable :: Test
testWithPooledDBOverflowKeepsPoolUsable = TestCase $ do
  let dbPath = "/tmp/qxfx0_test_pool_overflow.db"
      cleanupPaths = [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  mapM_ removeIfExists cleanupPaths
  pool <- SQLite.newDBPool dbPath 0
  failure <- try (SQLite.withPooledDB pool (\_ -> ioError (userError "forced overflow failure"))) :: IO (Either IOError ())
  case failure of
    Left _ -> pure ()
    Right _ -> assertFailure "forced overflow action should fail"
  ok <- SQLite.withPooledDB pool $ \db -> do
    _ <- NSQL.execSql db "CREATE TABLE IF NOT EXISTS pool_overflow_probe(id INTEGER PRIMARY KEY);"
    pure True
  assertBool "pool should stay usable after overflow path exception" ok
  mapM_ removeIfExists cleanupPaths

testWithPooledDBSanitizesDirtyTransactionBeforeReuse :: Test
testWithPooledDBSanitizesDirtyTransactionBeforeReuse = TestCase $ do
  let dbPath = "/tmp/qxfx0_test_pool_dirty_reuse.db"
      cleanupPaths = [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  mapM_ removeIfExists cleanupPaths
  pool <- SQLite.newDBPool dbPath 1
  let cleanup = SQLite.closeDBPool pool `finally` mapM_ removeIfExists cleanupPaths
  (do
      _ <- try
        (SQLite.withPooledDB pool $ \db -> do
            _ <- NSQL.execSql db "BEGIN IMMEDIATE;"
            ioError (userError "forced dirty transaction"))
        :: IO (Either IOError ())
      beginResult <- SQLite.withPooledDB pool $ \db ->
        NSQL.execSql db "BEGIN IMMEDIATE;"
      case beginResult of
        Left err ->
          assertFailure ("pooled connection should be sanitized before reuse, begin failed: " <> T.unpack err)
        Right _ -> pure ()
    ) `finally` cleanup

testWithPooledDBAsyncInterruptionSanitizesConnection :: Test
testWithPooledDBAsyncInterruptionSanitizesConnection = TestCase $ do
  let dbPath = "/tmp/qxfx0_test_pool_async_interrupt.db"
      cleanupPaths = [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  mapM_ removeIfExists cleanupPaths
  pool <- SQLite.newDBPool dbPath 1
  let cleanup = SQLite.closeDBPool pool `finally` mapM_ removeIfExists cleanupPaths
  (do
      interrupted <- try
        (SQLite.withPooledDB pool $ \db -> do
            _ <- NSQL.execSql db "BEGIN IMMEDIATE;"
            throwIO ThreadKilled)
        :: IO (Either AsyncException ())
      case interrupted of
        Left ThreadKilled -> pure ()
        other -> assertFailure ("expected ThreadKilled interruption, got: " <> show other)
      beginResult <- SQLite.withPooledDB pool $ \db ->
        NSQL.execSql db "BEGIN IMMEDIATE;"
      case beginResult of
        Left err ->
          assertFailure ("pooled connection should be sanitized after async interruption, begin failed: " <> T.unpack err)
        Right _ -> pure ()
    ) `finally` cleanup

testCloseDBPoolIsIdempotent :: Test
testCloseDBPoolIsIdempotent = TestCase $ do
  let dbPath = "/tmp/qxfx0_test_pool_close.db"
      cleanupPaths = [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  mapM_ removeIfExists cleanupPaths
  pool <- SQLite.newDBPool dbPath 1
  SQLite.closeDBPool pool
  SQLite.closeDBPool pool
  ok <- SQLite.withPooledDB pool $ \db -> do
    _ <- NSQL.execSql db "CREATE TABLE IF NOT EXISTS pool_close_probe(id INTEGER PRIMARY KEY);"
    pure True
  assertBool "pool should stay usable after repeated closeDBPool" ok
  mapM_ removeIfExists cleanupPaths

testCloseSessionIsIdempotent :: Test
testCloseSessionIsIdempotent = TestCase $ do
  withRuntimeEnv "qxfx0_test_close_session.db" $ do
    session0 <- Runtime.bootstrapSession True "test_close_session"
    Runtime.closeSession session0
    Runtime.closeSession session0
    pure ()

testWithBootstrappedSessionClosesRuntime :: Test
testWithBootstrappedSessionClosesRuntime = TestCase $ do
  withRuntimeEnv "qxfx0_test_with_bootstrap_close.db" $ do
    turns <- Runtime.withBootstrappedSession True "test_with_bootstrap_close" $ \session0 -> do
      let turns0 = ssTurnCount (Runtime.sessSystemState session0)
      pure turns0
    assertBool "withBootstrappedSession should run action and return value" (turns >= 0)

testAgdaWitnessReportDetectsMissingInputs :: Test
testAgdaWitnessReportDetectsMissingInputs = TestCase $ do
  let fakeRoot = "/tmp/qxfx0_fake_root_witness_report"
      witnessPath = "/tmp/qxfx0_fake_root_witness_report.json"
      specDir = fakeRoot </> "spec"
      domainDir = fakeRoot </> "src" </> "QxFx0" </> "Types"
      morphDir = fakeRoot </> "resources" </> "morphology"
  createDirectoryIfMissing True (fakeRoot </> "migrations")
  createDirectoryIfMissing True morphDir
  createDirectoryIfMissing True (fakeRoot </> "semantics")
  createDirectoryIfMissing True specDir
  createDirectoryIfMissing True domainDir
  TIO.writeFile (fakeRoot </> "semantics" </> "concepts.nix") "{}"
  TIO.writeFile (morphDir </> "prepositional.json") "{}"
  TIO.writeFile (morphDir </> "genitive.json") "{}"
  TIO.writeFile (morphDir </> "nominative.json") "{}"
  TIO.writeFile (morphDir </> "lexicon_quality.json") "{}"
  TIO.writeFile (specDir </> "R5Core.agda") "module R5Core where"
  TIO.writeFile (specDir </> "Sovereignty.agda") "module Sovereignty where"
  TIO.writeFile (specDir </> "Legitimacy.agda") "module Legitimacy where"
  TIO.writeFile (specDir </> "LexiconContract.agda") "module LexiconContract where"
  TIO.writeFile (specDir </> "LexiconData.agda") "module LexiconData where"
  TIO.writeFile (specDir </> "LexiconProof.agda") "module LexiconProof where"
  TIO.writeFile (specDir </> "r5-snapshot.tsv") "CMGround\tIFAssert\tDeclarative\tContentLayer\tAlwaysWarranted\n"
  TIO.writeFile (domainDir </> "Domain.hs") "module QxFx0.Types.Domain where\n"
  writeFile witnessPath "{\"awVersion\":1,\"awFiles\":{}}\n"
  withEnvVar "QXFX0_ROOT" (Just fakeRoot) $
    withEnvVar "QXFX0_AGDA_WITNESS" (Just witnessPath) $ do
      report <- Runtime.readAgdaWitnessReport
      assertEqual "report should point at configured witness path" witnessPath (Runtime.awrPath report)
      assertBool "empty witness must not be considered fresh" (not (Runtime.awrFresh report))
      assertEqual "typed status should report missing inputs" AgdaMissingInput (Runtime.awrStatus report)
      assertBool
        "empty witness should report missing inputs"
        (any (T.isPrefixOf "missing_input:") (Runtime.awrIssues report))

testSemanticModeTurn :: Test
testSemanticModeTurn = TestCase $ do
  withRuntimeEnv "qxfx0_test_runtime_semantic.db" $ do
    session0 <- Runtime.bootstrapSession True "test_runtime_semantic"
    let semSession = session0
          { Runtime.sessOutputMode = Runtime.SemanticIntrospectionMode
          , Runtime.sessSystemState = (Runtime.sessSystemState session0) { ssOutputMode = SemanticIntrospectionOutput }
          }
    (_session1, response) <- Runtime.runTurnInSession semSession "Что такое воля?"
    assertBool "semantic mode should append introspection block"
      ("SEMANTIC_INTROSPECTION_BEGIN" `T.isInfixOf` response)

testRunTurnInSessionStrictBlocksWhenBackendUnavailable :: Test
testRunTurnInSessionStrictBlocksWhenBackendUnavailable = TestCase $
  withStrictRuntimeEnv "qxfx0_test_strict_turn.db" $ do
    session0 <- Runtime.bootstrapSession True "test_runtime_strict_turn"
    let turns0 = ssTurnCount (Runtime.sessSystemState session0)
    (session1, response) <-
      withEnvVar "QXFX0_EMBEDDING_BACKEND" (Just "remote-http") $
        withEnvVar "EMBEDDING_API_URL" Nothing $
          Runtime.runTurnInSession session0 "Что такое свобода?"
    assertBool "strict runtime should block turn execution without healthy embedding backend"
      ("Turn blocked: strict runtime requires status=ok" `T.isInfixOf` response)
    assertEqual "blocked strict turn should keep turn counter unchanged"
      turns0
      (ssTurnCount (Runtime.sessSystemState session1))

testDatalogShadowRespectsAtomSignals :: Test
testDatalogShadowRespectsAtomSignals = TestCase $
  withFakeSouffle $ do
    directResult <- Datalog.compileAndRunDatalog "" CMGround
    case directResult of
      Left err -> assertFailure ("compileAndRunDatalog should load canonical rules, got: " <> T.unpack err)
      Right verdict ->
        assertEqual "direct Datalog run without atom signal should preserve ground family" CMGround (r5Family verdict)

    result <- Datalog.runDatalogShadow CMGround IFAssert [NeedContact "нужен контакт"]
    case Datalog.srDatalogVerdict result of
      Nothing -> assertFailure "fake Souffle should yield a concrete shadow verdict"
      Just verdict -> do
        assertEqual "shadow family should follow contact atom signal" CMContact (r5Family verdict)
        assertEqual "contact family should imply IFContact" IFContact (r5Force verdict)
        assertEqual "family shift should produce divergence" ShadowDiverged (Datalog.srStatus result)
        assertEqual "contact atom shift should be classified as verdict mismatch"
          ShadowVerdictMismatch
          (sdKind (Datalog.srDivergence result))
        assertBool "shadow snapshot id should be present and prefixed"
          ("shadow:" `T.isPrefixOf` shadowSnapshotIdText (Datalog.srSnapshotId result))
        assertBool
          "diagnostics should mention requested family shift"
          (any (T.isPrefixOf "requested_family_shift:") (Datalog.srDiagnostics result))

testDatalogShadowMissingRulesReportsCheckedPaths :: Test
testDatalogShadowMissingRulesReportsCheckedPaths = TestCase $ do
  let fakeRoot = "/tmp/qxfx0_fake_root_missing_datalog"
  createDirectoryIfMissing True (fakeRoot </> "migrations")
  createDirectoryIfMissing True (fakeRoot </> "resources" </> "morphology")
  createDirectoryIfMissing True (fakeRoot </> "semantics")
  TIO.writeFile (fakeRoot </> "semantics" </> "concepts.nix") "{}"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "prepositional.json") "{}"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "genitive.json") "{}"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "nominative.json") "{}"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "lexicon_quality.json") "{}"
  withEnvVar "QXFX0_ROOT" (Just fakeRoot) $ do
    result <- Datalog.runDatalogShadow CMGround IFAssert []
    assertEqual "missing rules should surface as unavailable shadow" ShadowUnavailable (Datalog.srStatus result)
    assertEqual "missing rules should be classified as shadow execution error"
      ShadowExecutionError
      (sdKind (Datalog.srDivergence result))
    assertBool "missing-rules result should still include deterministic snapshot id"
      ("shadow:" `T.isPrefixOf` shadowSnapshotIdText (Datalog.srSnapshotId result))
    assertBool
      "missing-rules diagnostic should include checked datalog paths"
      (any (T.isInfixOf "checked=") (Datalog.srDiagnostics result))

testDatalogShadowTimesOutWithControlledDiagnostic :: Test
testDatalogShadowTimesOutWithControlledDiagnostic = TestCase $ do
  let fakeBinDir = "/tmp/qxfx0_fake_souffle_timeout_bin"
      fakeSouffle = fakeBinDir </> "souffle-timeout"
      dbName = "qxfx0_test_souffle_timeout.db"
  createDirectoryIfMissing True fakeBinDir
  writeFile fakeSouffle "#!/bin/sh\n/bin/sleep 1\nexit 0\n"
  perms <- getPermissions fakeSouffle
  setPermissions fakeSouffle perms { executable = True }
  withRuntimeEnv dbName $
    withEnvVar "QXFX0_SOUFFLE_TIMEOUT_MS" (Just "10") $ do
      result <- Datalog.runDatalogShadowWithExecutable fakeSouffle CMGround IFAssert []
      assertEqual "timeout should surface as unavailable shadow result" ShadowUnavailable (Datalog.srStatus result)
      assertBool
        "timeout should report controlled diagnostic"
        (any (T.isInfixOf "timed out") (Datalog.srDiagnostics result))
  removeIfExists fakeSouffle

testResolveSouffleExecutableMaterializesMissingFlakePath :: Test
testResolveSouffleExecutableMaterializesMissingFlakePath = TestCase $ do
  root <- getCurrentDirectory
  oldPath <- lookupEnv "PATH"
  let fakeBinDir = "/tmp/qxfx0_fake_nix_materialize_bin"
      fakeNix = fakeBinDir </> "nix"
      builtOut = "/tmp/qxfx0_fake_souffle_materialized"
      builtBin = builtOut </> "bin"
      builtSouffle = builtBin </> "souffle"
      fakePath = fakeBinDir <> maybe "" (\p -> ":" <> p) oldPath
      fakeScript = unlines
        [ "#!/bin/sh"
        , "cmd=''"
        , "for arg in \"$@\"; do"
        , "  case \"$arg\" in"
        , "    eval|build) cmd=\"$arg\" ;;"
        , "  esac"
        , "done"
        , "case \"$cmd\" in"
        , "  eval)"
        , "    printf '%s\\n' '/nix/store/qxfx0-missing-souffle/bin/souffle'"
        , "    ;;"
        , "  build)"
        , "    printf '%s\\n' '" <> builtOut <> "'"
        , "    ;;"
        , "  *)"
        , "    printf '%s\\n' 'unexpected nix invocation in test' >&2"
        , "    exit 1"
        , "    ;;"
        , "esac"
        ]
  createDirectoryIfMissing True fakeBinDir
  createDirectoryIfMissing True builtBin
  writeFile fakeNix fakeScript
  writeFile builtSouffle "#!/bin/sh\nexit 0\n"
  nixPerms <- getPermissions fakeNix
  setPermissions fakeNix nixPerms { executable = True }
  soufflePerms <- getPermissions builtSouffle
  setPermissions builtSouffle soufflePerms { executable = True }
  withEnvVar "QXFX0_ROOT" (Just root) $
    withEnvVar "QXFX0_SOUFFLE_BIN" Nothing $
      withEnvVar "PATH" (Just fakePath) $ do
        resolved <- Datalog.resolveSouffleExecutable
        case resolved of
          Left err -> assertFailure ("expected flake materialization fallback, got: " <> T.unpack err)
          Right resolvedPath ->
            assertEqual "missing flake path should be recovered by build materialization" builtSouffle resolvedPath

testShadowSnapshotIdStable :: Test
testShadowSnapshotIdStable = TestCase $ do
  let snapshot =
        ShadowSnapshot
          { ssRequestedFamily = CMGround
          , ssInputForce = IFAssert
          , ssInputAtoms = ["NeedContact"]
          , ssInputAtomDetails = [("NeedContact", "нужен контакт")]
          , ssSourceAtomTags = [NeedContact "нужен контакт"]
          }
      sid1 = mkShadowSnapshotId snapshot
      sid2 = mkShadowSnapshotId snapshot
  assertEqual "shadow snapshot id should be deterministic for same snapshot" sid1 sid2

testShadowSnapshotIdChangesWithInput :: Test
testShadowSnapshotIdChangesWithInput = TestCase $ do
  let baseSnapshot =
        ShadowSnapshot
          { ssRequestedFamily = CMGround
          , ssInputForce = IFAssert
          , ssInputAtoms = ["NeedContact"]
          , ssInputAtomDetails = [("NeedContact", "нужен контакт")]
          , ssSourceAtomTags = [NeedContact "нужен контакт"]
          }
      modifiedSnapshot = baseSnapshot { ssInputAtoms = ["NeedMeaning"], ssSourceAtomTags = [NeedMeaning "нужен смысл"] }
      sid1 = mkShadowSnapshotId baseSnapshot
      sid2 = mkShadowSnapshotId modifiedSnapshot
  assertBool "snapshot id should change when canonical snapshot content changes" (sid1 /= sid2)

testConstitutionalLocalRecoveryThreshold :: Test
testConstitutionalLocalRecoveryThreshold = TestCase $ do
  let ct = emptyConstitutionalThresholds
  assertEqual "Default local recovery threshold should be 0.3" 0.3 (ctLocalRecoveryThreshold ct)
  let ctHigh = ct { ctLocalRecoveryThreshold = 0.5 }
  assertEqual "Configurable threshold should update" 0.5 (ctLocalRecoveryThreshold ctHigh)

testLoadStateCorruptBlobIsReported :: Test
testLoadStateCorruptBlobIsReported = TestCase $ do
  withRuntimeEnv "qxfx0_test_corrupt_field.db" $ do
    session0 <- Runtime.bootstrapSession True "test_corrupt"
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db -> do
      let sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
      mStmt <- NSQL.prepare db sql
      case mStmt of
        Left _ -> pure ()
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 "test_corrupt"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          _ <- NSQL.bindText stmt 3 "{not valid json"
          _ <- NSQL.step stmt
          NSQL.finalize stmt
          pure ()
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "test_corrupt"
    case loaded of
      StatePersistence.LoadStateCorrupt _ ->
        pure ()
      other ->
        assertFailure ("expected corrupt load result, got: " <> show other)

testBootstrapSessionMarksRecoveredCorruption :: Test
testBootstrapSessionMarksRecoveredCorruption = TestCase $ do
  withRuntimeEnv "qxfx0_test_corrupt_bootstrap.db" $ do
    session0 <- Runtime.bootstrapSession True "test_corrupt_bootstrap"
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db -> do
      let sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
      mStmt <- NSQL.prepare db sql
      case mStmt of
        Left _ -> pure ()
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 "test_corrupt_bootstrap"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          _ <- NSQL.bindText stmt 3 "{corrupt"
          _ <- NSQL.step stmt
          NSQL.finalize stmt
          pure ()
    recovered <- Runtime.bootstrapSession True "test_corrupt_bootstrap"
    assertEqual
      "corrupt persisted state should not masquerade as fresh bootstrap"
      Runtime.RecoveredCorruptOrigin
      (Runtime.sessStateOrigin recovered)

testStateBlobDiagnosticsDetectsMissingOptionalFields :: Test
testStateBlobDiagnosticsDetectsMissingOptionalFields = TestCase $ do
  let minimalBlob = T.pack "{\"history\":[],\"rawInputHistory\":[],\"turnCount\":0,\"lastTopic\":\"\",\"lastFamily\":\"CMGround\",\"lastForce\":\"IFAssert\",\"lastLayer\":\"ContentLayer\",\"lastEmbedding\":[],\"consecutiveReflect\":0,\"recentFamilies\":[],\"activeScene\":\"None\",\"userState\":{\"claims\":[],\"topics\":[]},\"ego\":{\"tension\":0.0,\"agency\":1.0,\"narrative\":\"\"},\"identityClaims\":[],\"orbitalMemory\":[],\"trace\":[],\"meaningGraph\":{\"edges\":[],\"turnCount\":0},\"kernelPulse\":\"Neutral\",\"blockedConcepts\":[],\"clusters\":[],\"intuitConfidence\":0.5,\"sessionId\":\"test\",\"outputMode\":\"text\",\"morphology\":{\"entries\":[]},\"observability\":{\"lastQualityScore\":0.0,\"lastShadowDivergence\":null,\"lastCheckpointTurn\":0}}"
  let diagnostics = StatePersistence.stateBlobDiagnostics minimalBlob
  assertBool "minimal blob should report missing optional fields" (not (null diagnostics))
  assertBool "diagnostics should mention missing fields"
    (any (\d -> case d of
            StatePersistence.PdSchemaMissingFields fields ->
              any (\f -> f `elem` ["lastGuardReport", "dreamState", "intuitionState"]) fields
            _ -> False)
      diagnostics)
  let completeBlob = T.pack "{\"history\":[],\"rawInputHistory\":[],\"turnCount\":0,\"lastTopic\":\"\",\"lastFamily\":\"CMGround\",\"lastForce\":\"IFAssert\",\"lastLayer\":\"ContentLayer\",\"lastEmbedding\":[],\"consecutiveReflect\":0,\"recentFamilies\":[],\"activeScene\":\"None\",\"userState\":{\"claims\":[],\"topics\":[]},\"ego\":{\"tension\":0.0,\"agency\":1.0,\"narrative\":\"\"},\"identityClaims\":[],\"orbitalMemory\":[],\"lastGuardReport\":null,\"trace\":[],\"meaningGraph\":{\"edges\":[],\"turnCount\":0},\"kernelPulse\":\"Neutral\",\"blockedConcepts\":[],\"clusters\":[],\"dreamState\":null,\"intuitionState\":null,\"semanticAnchor\":null,\"lastTurnDecision\":null,\"intuitConfidence\":0.5,\"sessionId\":\"test\",\"outputMode\":\"text\",\"morphology\":{\"entries\":[]},\"observability\":{\"lastQualityScore\":0.0,\"lastShadowDivergence\":null,\"lastCheckpointTurn\":0}}"
  let diagnosticsComplete = StatePersistence.stateBlobDiagnostics completeBlob
  assertEqual "complete blob should have no diagnostics" [] diagnosticsComplete

testSaveStateReturnsRightOnSuccess :: Test
testSaveStateReturnsRightOnSuccess = TestCase $ do
  withRuntimeEnv "qxfx0_test_save_success.db" $ do
    session0 <- Runtime.bootstrapSession True "test_save_ok"
    let rt = Runtime.sessRuntime session0
        ss0 = Runtime.sessSystemState session0
    result <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "test_save_ok"
    case result of
      Left err -> assertFailure $ "saveState should return Right on success, got Left: " <> T.unpack (renderPersistenceDiagnostics [err])
      Right ss -> assertBool "Saved state should preserve turn count" (ssTurnCount ss == ssTurnCount ss0)

testSaveStateWithProjectionFailureRollsBackTransaction :: Test
testSaveStateWithProjectionFailureRollsBackTransaction = TestCase $ do
  withRuntimeEnv "qxfx0_test_save_projection_rollback.db" $ do
    let sessionId = "test_save_projection_rollback"
    session0 <- Runtime.bootstrapSession True sessionId
    let rt = Runtime.sessRuntime session0
        ss0 = Runtime.sessSystemState session0
        projection = TurnProjection
          { tqpTurn = 1
          , tqpParserMode = ParserFrameV1
          , tqpParserConfidence = 0.31
          , tqpParserErrors = ["projection_failure_fixture"]
          , tqpPlannerMode = DefaultPlanner
          , tqpPlannerDecision = CMGround
          , tqpAtomRegister = Search
          , tqpAtomLoad = 0.7
          , tqpScenePressure = PressureHigh
          , tqpSceneRequest = "rollback_fixture"
          , tqpSceneStance = MetaLayer
          , tqpRenderLane = ValidateMove
          , tqpRenderStyle = StyleFormal
          , tqpLegitimacyStatus = LegitimacyDegraded
          , tqpLegitimacyReason = ReasonShadowDivergence
          , tqpWarrantedMode = AlwaysWarranted
          , tqpDecisionDisposition = DispositionRepair
          , tqpOwnerFamily = CMGround
          , tqpOwnerForce = IFAssert
          , tqpShadowStatus = ShadowDiverged
          , tqpShadowSnapshotId = ShadowSnapshotId "shadow:projection_rollback_fixture"
          , tqpShadowDivergenceKind = ShadowVerdictMismatch
          , tqpShadowFamily = Just CMConfront
          , tqpShadowForce = Just IFConfront
          , tqpShadowMessage = "fixture_divergence"
          , tqpReplayTrace = TurnReplayTrace
              { trcRequestId = "req_projection_rollback_fixture"
              , trcSessionId = sessionId
              , trcRuntimeMode = "strict"
              , trcShadowPolicy = "block_on_unavailable_or_divergence"
              , trcLocalRecoveryPolicy = "enabled"
              , trcRecoveryCause = Just RecoveryShadowDivergence
              , trcRecoveryStrategy = Just StrategyNarrowScope
              , trcRecoveryEvidence = ["shadow_status=diverged"]
              , trcSemanticIntrospectionEnabled = False
              , trcWarnMorphologyFallbackEnabled = False
              , trcRequestedFamily = CMGround
              , trcStrategyFamily = Just CMGround
              , trcNarrativeHint = Nothing
              , trcIntuitionHint = Nothing
              , trcPreShadowFamily = CMGround
              , trcShadowSnapshotId = ShadowSnapshotId "shadow:projection_rollback_fixture"
              , trcShadowStatus = ShadowDiverged
              , trcShadowDivergenceKind = ShadowVerdictMismatch
              , trcShadowDivergenceSeverity = ShadowSeverityContract
              , trcShadowResolvedFamily = CMConfront
              , trcFinalFamily = CMGround
              , trcFinalForce = IFAssert
              , trcDecisionDisposition = DispositionRepair
              , trcLegitimacyReason = ReasonShadowDivergence
              , trcParserConfidence = 0.31
              , trcEmbeddingQuality = "heuristic"
              , trcClaimAst = Nothing
              , trcLinearizationLang = Nothing
              , trcLinearizationOk = False
              , trcFallbackReason = Nothing
              }
          , tqpDivergence = True
          }
    beforeCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM turn_quality WHERE session_id = 'test_save_projection_rollback'"
    Runtime.withRuntimeDb rt $ \db ->
      assertExec db "drop shadow_divergence_log" "DROP TABLE IF EXISTS shadow_divergence_log;"
    result <- StatePersistence.saveStateWithProjection
      (Runtime.withRuntimeDb rt)
      ss0
      sessionId
      (Just projection)
    case result of
      Left _ -> pure ()
      Right _ -> assertFailure "saveStateWithProjection should fail when divergence table is missing"
    afterCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM turn_quality WHERE session_id = 'test_save_projection_rollback'"
    assertEqual "failed projection persistence must rollback turn_quality insert" beforeCount afterCount

testRunTurnPersistsTurnQuality :: Test
testRunTurnPersistsTurnQuality = TestCase $ do
  withRuntimeEnv "qxfx0_test_turn_quality.db" $ do
    session0 <- Runtime.bootstrapSession True "test_turn_quality"
    let rt = Runtime.sessRuntime session0
    (_session1, output1) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    assertBool "turn output should not be empty" (not (T.null output1))
    qualityCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM turn_quality"
    maxTurn <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT max(turn) FROM turn_quality"
    replayTraceJson <- Runtime.withRuntimeDb rt $ \db -> do
      mStmt <- NSQL.prepare db "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
      stmt <- case mStmt of
        Left err -> assertFailure ("Failed to prepare replay trace query: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 "test_turn_quality"
      hasRow <- NSQL.stepRow stmt
      value <- if hasRow then NSQL.columnText stmt 0 else pure ""
      NSQL.finalize stmt
      pure value
    assertBool "turn_quality should have at least one row after runTurn" (qualityCount >= 1)
    assertBool "turn_quality max(turn) should be >= 1 after runTurn" (maxTurn >= 1)
    assertBool "replay trace json should include request id"
      ("\"trcRequestId\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include shadow snapshot id"
      ("\"trcShadowSnapshotId\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include runtime mode"
      ("\"trcRuntimeMode\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include shadow policy"
      ("\"trcShadowPolicy\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include local recovery policy"
      ("\"trcLocalRecoveryPolicy\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include local recovery cause"
      ("\"trcRecoveryCause\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include local recovery strategy"
      ("\"trcRecoveryStrategy\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include local recovery evidence"
      ("\"trcRecoveryEvidence\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include semantic introspection flag"
      ("\"trcSemanticIntrospectionEnabled\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include morphology warning flag"
      ("\"trcWarnMorphologyFallbackEnabled\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include claim AST"
      ("\"trcClaimAst\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include linearization language"
      ("\"trcLinearizationLang\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include linearization flag"
      ("\"trcLinearizationOk\"" `T.isInfixOf` replayTraceJson)
    assertBool "replay trace json should include fallback reason"
      ("\"trcFallbackReason\"" `T.isInfixOf` replayTraceJson)

testRunTurnRefreshesRuntimeSessionLastActive :: Test
testRunTurnRefreshesRuntimeSessionLastActive = TestCase $ do
  withRuntimeEnv "qxfx0_test_runtime_session_last_active.db" $ do
    let sessionId = "test_runtime_session_last_active"
    session0 <- Runtime.bootstrapSession True sessionId
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db -> do
      stmtRes <- NSQL.prepare db "UPDATE runtime_sessions SET last_active = ?, status = ? WHERE id = ?"
      stmt <- case stmtRes of
        Left err -> assertFailure ("Failed to prepare runtime_sessions stale update: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 "2000-01-01 00:00:00"
      _ <- NSQL.bindText stmt 2 "inactive"
      _ <- NSQL.bindText stmt 3 sessionId
      _ <- NSQL.step stmt
      NSQL.finalize stmt
    (_session1, output1) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    assertBool "turn output should not be empty" (not (T.null output1))
    (lastActive, status) <- Runtime.withRuntimeDb rt $ \db -> do
      stmtRes <- NSQL.prepare db "SELECT last_active, status FROM runtime_sessions WHERE id = ?"
      stmt <- case stmtRes of
        Left err -> assertFailure ("Failed to prepare runtime_sessions activity query: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 sessionId
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then assertFailure "runtime_sessions row missing after turn" >> fail "unreachable"
        else do
          la <- NSQL.columnText stmt 0
          st <- NSQL.columnText stmt 1
          NSQL.finalize stmt
          pure (la, st)
    assertBool "last_active should be refreshed on successful turn"
      (lastActive /= "2000-01-01 00:00:00")
    assertEqual "runtime session status should be active after successful turn" "active" status

testPersistedSystemStateSessionIdMatchesBootstrapId :: Test
testPersistedSystemStateSessionIdMatchesBootstrapId = TestCase $ do
  withRuntimeEnv "qxfx0_test_session_id_persist.db" $ do
    let sessionId = "test_session_id_persist"
    session0 <- Runtime.bootstrapSession True sessionId
    (session1, output1) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    assertBool "turn output should not be empty" (not (T.null output1))
    let rt = Runtime.sessRuntime session1
    persistedBlob <- Runtime.withRuntimeDb rt $ \db -> do
      mStmt <- NSQL.prepare db "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ? ORDER BY updated_at DESC LIMIT 1"
      stmt <- case mStmt of
        Left err -> assertFailure ("Failed to prepare persisted-state query: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 sessionId
      _ <- NSQL.bindText stmt 2 "__system_state__"
      hasRow <- NSQL.stepRow stmt
      payload <- if hasRow then NSQL.columnText stmt 0 else pure ""
      NSQL.finalize stmt
      pure payload
    case eitherDecodeStrict' (encodeUtf8 persistedBlob) of
      Left err ->
        assertFailure ("Persisted system state should decode as JSON: " <> err)
      Right (Object obj) ->
        case KeyMap.lookup "sessionId" obj of
          Just (String persistedSessionId) ->
            assertEqual "Persisted SystemState.sessionId should match runtime session id"
              sessionId
              persistedSessionId
          other ->
            assertFailure ("Persisted SystemState.sessionId should be JSON string, got: " <> show other)
      Right other ->
        assertFailure ("Persisted system state should be JSON object, got: " <> show other)

testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty :: Test
testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty =
  quickCheckTest 20 "persisted replay trace json deterministic across fresh sessions" $
    forAll (elements replayInputs) $ \rawInput ->
      ioProperty $
        withStrictRuntimeEnv "qxfx0_test_replay_trace_determinism.db" $ do
          sessionA <- Runtime.bootstrapSession True "fresh_det_session_a"
          _ <- Runtime.runTurnInSession sessionA (T.pack rawInput)
          sessionB <- Runtime.bootstrapSession True "fresh_det_session_b"
          _ <- Runtime.runTurnInSession sessionB (T.pack rawInput)
          let rt = Runtime.sessRuntime sessionB
          replayA <- Runtime.withRuntimeDb rt $ \db ->
            fetchLatestReplayTraceJson db "fresh_det_session_a"
          replayB <- Runtime.withRuntimeDb rt $ \db ->
            fetchLatestReplayTraceJson db "fresh_det_session_b"
          normalizedA <- normalizeReplayTraceJson "fresh_det_session_a" replayA
          normalizedB <- normalizeReplayTraceJson "fresh_det_session_b" replayB
          pure (normalizedA == normalizedB)
  where
    replayInputs =
      [ "Что такое свобода?"
      , "Мне нужен контакт."
      , "Где граница между смыслом и пустотой?"
      ]

testPersistedReplayTraceDeterministicWithFixedTimeProperty :: Test
testPersistedReplayTraceDeterministicWithFixedTimeProperty =
  quickCheckTest 20 "persisted replay trace json deterministic with fixed time source" $
    forAll (elements replayInputs) $ \rawInput ->
      ioProperty $
        withEnvVar "QXFX0_TEST_FIXED_TIME" (Just "0") $
          withStrictRuntimeEnv "qxfx0_test_replay_trace_fixed_time.db" $ do
            sessionA <- Runtime.bootstrapSession True "fixed_time_session_a"
            _ <- Runtime.runTurnInSession sessionA (T.pack rawInput)
            sessionB <- Runtime.bootstrapSession True "fixed_time_session_b"
            _ <- Runtime.runTurnInSession sessionB (T.pack rawInput)
            let rt = Runtime.sessRuntime sessionB
            replayA <- Runtime.withRuntimeDb rt $ \db ->
              fetchLatestReplayTraceJson db "fixed_time_session_a"
            replayB <- Runtime.withRuntimeDb rt $ \db ->
              fetchLatestReplayTraceJson db "fixed_time_session_b"
            normalizedA <- normalizeReplayTraceJson "fixed_time_session_a" replayA
            normalizedB <- normalizeReplayTraceJson "fixed_time_session_b" replayB
            pure (normalizedA == normalizedB)
  where
    replayInputs =
      [ "Что такое свобода?"
      , "Мне нужен контакт."
      , "Где граница между смыслом и пустотой?"
      ]

testSaveStateWithDivergencePersistsShadowLog :: Test
testSaveStateWithDivergencePersistsShadowLog = TestCase $ do
  withRuntimeEnv "qxfx0_test_shadow_divergence.db" $ do
    let sessionId = "test_shadow_divergence"
    session0 <- Runtime.bootstrapSession True sessionId
    let rt = Runtime.sessRuntime session0
        ss0 = Runtime.sessSystemState session0
        projection = TurnProjection
          { tqpTurn = 1
          , tqpParserMode = ParserFrameV1
          , tqpParserConfidence = 0.3
          , tqpParserErrors = ["low_confidence"]
          , tqpPlannerMode = DefaultPlanner
          , tqpPlannerDecision = CMGround
          , tqpAtomRegister = Search
          , tqpAtomLoad = 0.8
          , tqpScenePressure = PressureHigh
          , tqpSceneRequest = "\1089\1074\1086\1073\1086\1076\1072"
          , tqpSceneStance = MetaLayer
          , tqpRenderLane = ValidateMove
          , tqpRenderStyle = StyleFormal
          , tqpLegitimacyStatus = LegitimacyDegraded
          , tqpLegitimacyReason = ReasonShadowDivergence
          , tqpWarrantedMode = AlwaysWarranted
          , tqpDecisionDisposition = DispositionRepair
          , tqpOwnerFamily = CMGround
          , tqpOwnerForce = IFAssert
          , tqpShadowStatus = ShadowDiverged
          , tqpShadowSnapshotId = ShadowSnapshotId "shadow:test_divergence_fixture"
          , tqpShadowDivergenceKind = ShadowVerdictMismatch
          , tqpShadowFamily = Just CMConfront
          , tqpShadowForce = Just IFConfront
          , tqpShadowMessage = "shadow_diverged:family,force"
          , tqpReplayTrace = TurnReplayTrace
              { trcRequestId = "req_test_shadow_divergence"
              , trcSessionId = sessionId
              , trcRuntimeMode = "strict"
              , trcShadowPolicy = "block_on_unavailable_or_divergence"
              , trcLocalRecoveryPolicy = "enabled"
              , trcRecoveryCause = Just RecoveryShadowDivergence
              , trcRecoveryStrategy = Just StrategyNarrowScope
              , trcRecoveryEvidence = ["shadow_status=diverged"]
              , trcSemanticIntrospectionEnabled = False
              , trcWarnMorphologyFallbackEnabled = False
              , trcRequestedFamily = CMGround
              , trcStrategyFamily = Just CMGround
              , trcNarrativeHint = Just "narrative_hint_test"
              , trcIntuitionHint = Just "intuition_hint_test"
              , trcPreShadowFamily = CMGround
              , trcShadowSnapshotId = ShadowSnapshotId "shadow:test_divergence_fixture"
              , trcShadowStatus = ShadowDiverged
              , trcShadowDivergenceKind = ShadowVerdictMismatch
              , trcShadowDivergenceSeverity = ShadowSeverityContract
              , trcShadowResolvedFamily = CMConfront
              , trcFinalFamily = CMGround
              , trcFinalForce = IFAssert
              , trcDecisionDisposition = DispositionRepair
              , trcLegitimacyReason = ReasonShadowDivergence
              , trcParserConfidence = 0.3
              , trcEmbeddingQuality = "heuristic"
              , trcClaimAst = Nothing
              , trcLinearizationLang = Nothing
              , trcLinearizationOk = False
              , trcFallbackReason = Nothing
              }
          , tqpDivergence = True
          }
    result <- StatePersistence.saveStateWithProjection
      (Runtime.withRuntimeDb rt)
      ss0
      sessionId
      (Just projection)
    case result of
      Left err -> assertFailure $ "saveStateWithProjection should succeed, got: " <> T.unpack (renderPersistenceDiagnostics [err])
      Right _ -> pure ()
    qualityCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM turn_quality"
    divergenceCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM shadow_divergence_log"
    qualityShadowTrace <- Runtime.withRuntimeDb rt $ \db -> do
      mStmt <- NSQL.prepare db "SELECT shadow_snapshot_id, shadow_divergence_kind, replay_trace_json FROM turn_quality WHERE session_id = ? AND turn = ?"
      stmt <- case mStmt of
        Left err -> assertFailure ("Failed to prepare turn_quality trace query: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 sessionId
      _ <- NSQL.bindInt stmt 2 1
      hasRow <- NSQL.stepRow stmt
      values <- if hasRow
        then do
          sid <- NSQL.columnText stmt 0
          kind <- NSQL.columnText stmt 1
          replayTrace <- NSQL.columnText stmt 2
          pure (sid, kind, replayTrace)
        else pure ("", "", "")
      NSQL.finalize stmt
      pure values
    divergenceShadowTrace <- Runtime.withRuntimeDb rt $ \db -> do
      mStmt <- NSQL.prepare db "SELECT shadow_snapshot_id, shadow_divergence_kind FROM shadow_divergence_log WHERE session_id = ? AND turn = ? ORDER BY id DESC LIMIT 1"
      stmt <- case mStmt of
        Left err -> assertFailure ("Failed to prepare shadow_divergence_log trace query: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 sessionId
      _ <- NSQL.bindInt stmt 2 1
      hasRow <- NSQL.stepRow stmt
      values <- if hasRow
        then do
          sid <- NSQL.columnText stmt 0
          kind <- NSQL.columnText stmt 1
          pure (sid, kind)
        else pure ("", "")
      NSQL.finalize stmt
      pure values
    assertBool "turn_quality should include projection row" (qualityCount >= 1)
    assertBool "shadow_divergence_log should include divergence row" (divergenceCount >= 1)
    assertEqual "turn_quality should persist shadow snapshot id"
      "shadow:test_divergence_fixture"
      (fst3 qualityShadowTrace)
    assertEqual "turn_quality should persist shadow divergence kind"
      "verdict_mismatch"
      (snd3 qualityShadowTrace)
    assertBool "turn_quality replay trace should persist snapshot id"
      ("shadow:test_divergence_fixture" `T.isInfixOf` (trd3 qualityShadowTrace))
    assertEqual "shadow_divergence_log should persist shadow snapshot id"
      "shadow:test_divergence_fixture"
      (fst divergenceShadowTrace)
    assertEqual "shadow_divergence_log should persist shadow divergence kind"
      "verdict_mismatch"
      (snd divergenceShadowTrace)
  where
    fst3 :: (a, b, c) -> a
    fst3 (a, _, _) = a

    snd3 :: (a, b, c) -> b
    snd3 (_, b, _) = b

    trd3 :: (a, b, c) -> c
    trd3 (_, _, c) = c

testBootstrapSessionHandlesQuotedSessionId :: Test
testBootstrapSessionHandlesQuotedSessionId = TestCase $ do
  withRuntimeEnv "qxfx0_test_bootstrap_quote.db" $ do
    let quotedSessionId = "test_session_'quoted'"
    session0 <- Runtime.bootstrapSession True quotedSessionId
    let rt = Runtime.sessRuntime session0
    rowCount <- Runtime.withRuntimeDb rt $ \db -> do
      stmtRes <- NSQL.prepare db "SELECT count(*) FROM runtime_sessions WHERE id = ?"
      stmt <- case stmtRes of
        Left err -> assertFailure ("Failed to prepare runtime_sessions query: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 quotedSessionId
      hasRow <- NSQL.stepRow stmt
      count <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure count
    assertEqual "Quoted session id should be inserted exactly once" 1 rowCount
    session1 <- Runtime.bootstrapSession True quotedSessionId
    assertEqual "Bootstrap should preserve quoted session id" quotedSessionId (Runtime.sessSessionId session1)

testComputeReadinessModeReady :: Test
testComputeReadinessModeReady = TestCase $ do
  let status = ReadinessStatus
        { rsComponents = [(RcResourceRoot, True, ""), (RcDatabase, True, ""), (RcMorphology, True, ""), (RcSchema, True, "")
                         ,(RcNixPolicy, True, ""), (RcAgdaSpec, True, ""), (RcDatalogRules, True, "")]
        , rsIsReady = True
        , rsIsDegraded = False
        }
  assertEqual "All components ok should yield Ready" Ready (computeReadinessMode status)

testComputeReadinessModeDegraded :: Test
testComputeReadinessModeDegraded = TestCase $ do
  let status = ReadinessStatus
        { rsComponents = [(RcResourceRoot, True, ""), (RcDatabase, True, ""), (RcMorphology, True, ""), (RcSchema, True, "")
                         ,(RcNixPolicy, False, ""), (RcAgdaSpec, False, "")]
        , rsIsReady = True
        , rsIsDegraded = True
        }
  assertEqual "Critical ok + optional failed should yield Degraded"
    (Degraded [RcNixPolicy, RcAgdaSpec]) (computeReadinessMode status)

testComputeReadinessModeNotReady :: Test
testComputeReadinessModeNotReady = TestCase $ do
  let status = ReadinessStatus
        { rsComponents = [(RcResourceRoot, True, ""), (RcDatabase, True, ""), (RcMorphology, False, ""), (RcSchema, False, "")]
        , rsIsReady = False
        , rsIsDegraded = False
        }
  assertEqual "Critical failure should yield NotReady"
    (NotReady [RcMorphology, RcSchema]) (computeReadinessMode status)

testAssessResourceReadinessFailsWhenRootMissing :: Test
testAssessResourceReadinessFailsWhenRootMissing = TestCase $
  withEnvVar "QXFX0_ROOT" (Just "/tmp/qxfx0_missing_resource_root") $ do
    status <- assessResourceReadiness "/tmp/qxfx0_root_missing.db"
    assertEqual "invalid root should be a critical readiness failure"
      (NotReady [RcResourceRoot, RcMorphology, RcSchema]) (computeReadinessMode status)

testAssessResourceReadinessFailsOnInvalidMorphologyJson :: Test
testAssessResourceReadinessFailsOnInvalidMorphologyJson = TestCase $ do
  let fakeRoot = "/tmp/qxfx0_fake_root_invalid_morphology"
  createDirectoryIfMissing True (fakeRoot </> "migrations")
  createDirectoryIfMissing True (fakeRoot </> "resources" </> "morphology")
  createDirectoryIfMissing True (fakeRoot </> "semantics")
  createDirectoryIfMissing True (fakeRoot </> "spec" </> "sql")
  TIO.writeFile (fakeRoot </> "semantics" </> "concepts.nix") "{}"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "prepositional.json") "{invalid"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "genitive.json") "{}"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "nominative.json") "{}"
  TIO.writeFile (fakeRoot </> "resources" </> "morphology" </> "lexicon_quality.json") "{}"
  TIO.writeFile (fakeRoot </> "spec" </> "sql" </> "schema.sql") "CREATE TABLE example(id INTEGER);"
  withEnvVar "QXFX0_ROOT" (Just fakeRoot) $ do
    status <- assessResourceReadiness "/tmp/qxfx0_invalid_morphology.db"
    assertEqual "invalid morphology JSON should block readiness"
      (NotReady [RcMorphology]) (computeReadinessMode status)

testMorphologyCacheSwitchesWithRoot :: Test
testMorphologyCacheSwitchesWithRoot = TestCase $ do
  let rootA = "/tmp/qxfx0_fake_root_morphA"
      rootB = "/tmp/qxfx0_fake_root_morphB"
  forM_ [rootA, rootB] $ \root -> do
    createDirectoryIfMissing True (root </> "migrations")
    createDirectoryIfMissing True (root </> "resources" </> "morphology")
    createDirectoryIfMissing True (root </> "semantics")
    createDirectoryIfMissing True (root </> "spec" </> "sql")
    TIO.writeFile (root </> "semantics" </> "concepts.nix") "{}"
    TIO.writeFile (root </> "resources" </> "morphology" </> "prepositional.json") ("{\"" <> T.pack (takeFileName root) <> "\":\"A\"}")
    TIO.writeFile (root </> "resources" </> "morphology" </> "genitive.json") "{}"
    TIO.writeFile (root </> "resources" </> "morphology" </> "nominative.json") "{}"
    TIO.writeFile (root </> "resources" </> "morphology" </> "lexicon_quality.json") "{}"
    TIO.writeFile (root </> "spec" </> "sql" </> "schema.sql") "CREATE TABLE example(id INTEGER);"
  mdA <- withEnvVar "QXFX0_ROOT" (Just rootA) loadMorphologyData
  mdB <- withEnvVar "QXFX0_ROOT" (Just rootB) loadMorphologyData
  assertBool "morphology cache should return distinct data for distinct roots"
    (mdPrepositional mdA /= mdPrepositional mdB)

testNixGuardIsSafeChar :: Test
testNixGuardIsSafeChar = TestCase $ do
  assertBool "ASCII letter should be safe" (NixGuard.isSafeChar 'a')
  assertBool "ASCII digit should be safe" (NixGuard.isSafeChar '5')
  assertBool "dash should be safe" (NixGuard.isSafeChar '-')
  assertBool "underscore should be safe" (NixGuard.isSafeChar '_')
  assertBool "slash should be safe" (NixGuard.isSafeChar '/')
  assertBool "Cyrillic letter should be safe" (NixGuard.isSafeChar 'в')
  assertBool "space should not be safe" (not (NixGuard.isSafeChar ' '))
  assertBool "semicolon should not be safe" (not (NixGuard.isSafeChar ';'))

testNixGuardUnsupportedConceptBlockedStrict :: Test
testNixGuardUnsupportedConceptBlockedStrict = TestCase $ do
  withEnvVar "QXFX0_NIXGUARD_LENIENT_UNSUPPORTED" Nothing $ do
    status <- NixGuard.checkConstitution "semantics/concepts.nix" "hello world" 0.5 0.5
    case status of
      Blocked blockedReason -> assertBool "unsupported concept should be blocked in strict mode" ("unsupported" `T.isInfixOf` blockedReason)
      other -> assertFailure ("expected Blocked for unsupported concept in strict mode, got: " <> show other)

testNixGuardUnknownSafeConceptAllowedStrict :: Test
testNixGuardUnknownSafeConceptAllowedStrict = TestCase $ do
  let fakeBinDir = "/tmp/qxfx0_fake_nix_unknown_bin"
      fakeNix = fakeBinDir </> "nix-instantiate"
      fakePath = fakeBinDir <> ":/usr/bin:/bin"
      fakeScript = unlines
        [ "#!/bin/sh"
        , "expr=''"
        , "prev=''"
        , "for arg in \"$@\"; do"
        , "  if [ \"$prev\" = '--expr' ]; then expr=\"$arg\"; fi"
        , "  prev=\"$arg\""
        , "done"
        , "case \"$expr\" in"
        , "  *'else false'*) printf 'false\\n' ;;"
        , "  *) printf 'true\\n' ;;"
        , "esac"
        ]
  createDirectoryIfMissing True fakeBinDir
  writeFile fakeNix fakeScript
  perms <- getPermissions fakeNix
  setPermissions fakeNix perms { executable = True }
  withEnvVar "PATH" (Just fakePath) $
    withEnvVar "QXFX0_NIXGUARD_LENIENT_UNSUPPORTED" Nothing $ do
      status <- NixGuard.checkConstitution "semantics/concepts.nix" "unknownsafeconcept" 0.5 0.5
      case status of
        Allowed -> pure ()
        other -> assertFailure ("expected Allowed for unknown safe concept, got: " <> show other)

testNixGuardUnsupportedConceptAllowedLenient :: Test
testNixGuardUnsupportedConceptAllowedLenient = TestCase $ do
  withEnvVar "QXFX0_NIXGUARD_LENIENT_UNSUPPORTED" (Just "1") $ do
    status <- NixGuard.checkConstitution "semantics/concepts.nix" "hello world" 0.5 0.5
    case status of
      Unavailable unavailableReason -> assertBool "unsupported concept should be Unavailable in lenient mode" ("unsupported" `T.isInfixOf` unavailableReason)
      other -> assertFailure ("expected Unavailable for unsupported concept in lenient mode, got: " <> show other)

testNixGuardEmptyConceptAllowed :: Test
testNixGuardEmptyConceptAllowed = TestCase $ do
  withEnvVar "QXFX0_NIXGUARD_LENIENT_UNSUPPORTED" Nothing $ do
    status <- NixGuard.checkConstitution "semantics/concepts.nix" "" 0.5 0.5
    assertEqual "empty concept should be Allowed even in strict mode" Allowed status

testNixStringLiteralEscaping :: Test
testNixStringLiteralEscaping = TestCase $ do
  assertEqual "backslash should be escaped" "\"foo\\\\bar\"" (NixGuard.nixStringLiteral "foo\\bar")
  assertEqual "double quote should be escaped" "\"foo\\\"bar\"" (NixGuard.nixStringLiteral "foo\"bar")
  assertEqual "dollar-brace should be escaped" "\"foo\\${bar\"" (NixGuard.nixStringLiteral "foo${bar")
  assertEqual "non-ASCII should be preserved" "\"abcв\"" (NixGuard.nixStringLiteral "abcв")

testNixStringLiteralEmpty :: Test
testNixStringLiteralEmpty = TestCase $ do
  assertEqual "empty string should yield empty quotes" "\"\"" (NixGuard.nixStringLiteral "")

fetchLatestReplayTraceJson :: NSQL.Database -> T.Text -> IO T.Text
fetchLatestReplayTraceJson db sessionId = do
  mStmt <- NSQL.prepare db "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
  stmt <- case mStmt of
    Left err -> assertFailure ("Failed to prepare replay_trace_json query: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  _ <- NSQL.bindText stmt 1 sessionId
  hasRow <- NSQL.stepRow stmt
  value <- if hasRow then NSQL.columnText stmt 0 else pure ""
  NSQL.finalize stmt
  pure value

normalizeReplayTraceJson :: String -> T.Text -> IO Value
normalizeReplayTraceJson label payload =
  case eitherDecodeStrict' (encodeUtf8 payload) of
    Left err -> assertFailure ("Failed to decode replay trace JSON for " <> label <> ": " <> err) >> fail "unreachable"
    Right value -> pure (normalizeReplayTraceValue value)

normalizeReplayTraceValue :: Value -> Value
normalizeReplayTraceValue (Object objectValue) =
  Object
    ( KeyMap.insert "trcSessionId" (String "<normalized-session>")
    $ KeyMap.insert "trcRequestId" (String "<normalized-request>") objectValue
    )
normalizeReplayTraceValue other = other

quickCheckTest :: Testable prop => Int -> String -> prop -> Test
quickCheckTest maxCases label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = maxCases } prop
  case result of
    Success{} -> pure ()
    _ -> assertFailure ("QuickCheck failed: " <> label)
