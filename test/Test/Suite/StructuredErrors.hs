{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-| Comprehensive test suite for Phase 3B structured error migration.
    
    Tests all four structured error types and their helper functions:
    - PersistenceErrorStructured
    - RuntimeInitErrorStructured
    - EmbeddingErrorStructured
    - SQLiteErrorStructured
    
    Verifies:
    - Helper functions create correct structures
    - Conversion functions (toErrorCode, toLogMessage) work properly
    - Errors can be caught and handled
    - Backward compatibility with legacy constructors
    - Edge cases (empty context, large context)
-}
module Test.Suite.StructuredErrors
  ( structuredErrorsTests
  ) where

import Test.HUnit
import Control.Exception (try, throwIO, catch)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.ExceptionPolicy
import QxFx0.Types.Persistence (PersistenceStage(..))

structuredErrorsTests :: [Test]
structuredErrorsTests =
  [ TestLabel "Helper Functions" $ TestList
      [ TestLabel "mkPersistenceError creates valid structure" testMkPersistenceError
      , TestLabel "mkRuntimeInitError creates valid structure" testMkRuntimeInitError
      , TestLabel "mkEmbeddingError creates valid structure" testMkEmbeddingError
      , TestLabel "mkSQLiteError creates valid structure" testMkSQLiteError
      ]
  , TestLabel "Conversion Functions" $ TestList
      [ TestLabel "toErrorCode returns correct codes" testToErrorCode
      , TestLabel "toLogMessage formats correctly" testToLogMessage
      , TestLabel "Structured errors contain all required fields" testStructureCompleteness
      , TestLabel "Context map serializes correctly" testContextSerialization
      ]
  , TestLabel "Integration" $ TestList
      [ TestLabel "PersistenceErrorStructured can be caught" testPersistenceCatchable
      , TestLabel "RuntimeInitErrorStructured can be caught" testRuntimeInitCatchable
      , TestLabel "EmbeddingErrorStructured can be caught" testEmbeddingCatchable
      , TestLabel "SQLiteErrorStructured can be caught" testSQLiteCatchable
      ]
  , TestLabel "Backward Compatibility" $ TestList
      [ TestLabel "Legacy constructors work for pattern matching" testOldConstructorsWork
      , TestLabel "Existing handlers work with both old and new" testExistingHandlers
      ]
  , TestLabel "Edge Cases" $ TestList
      [ TestLabel "Empty context map is handled correctly" testEmptyContext
      , TestLabel "Large context map is handled correctly" testLargeContext
      ]
  ]

-- ============================================================================
-- Helper Functions Tests
-- ============================================================================

testMkPersistenceError :: Test
testMkPersistenceError = TestCase $ do
  let ctx = Map.fromList [("session_id", "test-123"), ("turn", "42")]
      err = mkPersistenceError StageStateBlobUpsert "upsert_state" "PERSIST_001" ctx
  
  case err of
    PersistenceErrorStructured details -> do
      assertEqual "Stage should match" StageStateBlobUpsert (pedStage details)
      assertEqual "Operation should match" "upsert_state" (pedOperation details)
      assertEqual "Error code should match" "PERSIST_001" (pedErrorCode details)
      assertEqual "Context should match" ctx (pedContext details)
    _ -> assertFailure "Expected PersistenceErrorStructured"

testMkRuntimeInitError :: Test
testMkRuntimeInitError = TestCase $ do
  let ctx = Map.fromList [("config_path", "/etc/qxfx0.conf"), ("phase", "bootstrap")]
      err = mkRuntimeInitError "database" "connect" "INIT_DB_001" ctx
  
  case err of
    RuntimeInitErrorStructured details -> do
      assertEqual "Component should match" "database" (riedComponent details)
      assertEqual "Operation should match" "connect" (riedOperation details)
      assertEqual "Error code should match" "INIT_DB_001" (riedErrorCode details)
      assertEqual "Context should match" ctx (riedContext details)
    _ -> assertFailure "Expected RuntimeInitErrorStructured"

testMkEmbeddingError :: Test
testMkEmbeddingError = TestCase $ do
  let ctx = Map.fromList [("model", "text-embedding-3-small"), ("input_length", "512")]
      err = mkEmbeddingError "openai" "embed_text" "EMBED_TIMEOUT" ctx
  
  case err of
    EmbeddingErrorStructured details -> do
      assertEqual "Backend should match" "openai" (eedBackend details)
      assertEqual "Operation should match" "embed_text" (eedOperation details)
      assertEqual "Error code should match" "EMBED_TIMEOUT" (eedErrorCode details)
      assertEqual "Context should match" ctx (eedContext details)
    _ -> assertFailure "Expected EmbeddingErrorStructured"

testMkSQLiteError :: Test
testMkSQLiteError = TestCase $ do
  let ctx = Map.fromList [("query", "SELECT * FROM sessions"), ("db_path", "/tmp/test.db")]
      err = mkSQLiteError "execute_query" "SQLITE_BUSY" ctx
  
  case err of
    SQLiteErrorStructured details -> do
      assertEqual "Operation should match" "execute_query" (sedOperation details)
      assertEqual "Error code should match" "SQLITE_BUSY" (sedErrorCode details)
      assertEqual "Context should match" ctx (sedContext details)
    _ -> assertFailure "Expected SQLiteErrorStructured"

-- ============================================================================
-- Conversion Functions Tests
-- ============================================================================

testToErrorCode :: Test
testToErrorCode = TestCase $ do
  -- Test structured errors
  let persistErr = mkPersistenceError StageStateBlobUpsert "op" "PERSIST_001" Map.empty
  assertEqual "PersistenceErrorStructured code" "PERSIST_001" (toErrorCode persistErr)
  
  let runtimeErr = mkRuntimeInitError "comp" "op" "INIT_002" Map.empty
  assertEqual "RuntimeInitErrorStructured code" "INIT_002" (toErrorCode runtimeErr)
  
  let embedErr = mkEmbeddingError "backend" "op" "EMBED_003" Map.empty
  assertEqual "EmbeddingErrorStructured code" "EMBED_003" (toErrorCode embedErr)
  
  let sqliteErr = mkSQLiteError "op" "SQLITE_004" Map.empty
  assertEqual "SQLiteErrorStructured code" "SQLITE_004" (toErrorCode sqliteErr)
  
  -- Test legacy errors
  assertEqual "Legacy PersistenceError code" "PERSISTENCE_ERROR" 
    (toErrorCode (PersistenceError "msg"))
  assertEqual "Legacy RuntimeInitError code" "RUNTIME_INIT_ERROR" 
    (toErrorCode (RuntimeInitError "msg"))
  assertEqual "Legacy EmbeddingError code" "EMBEDDING_ERROR" 
    (toErrorCode (EmbeddingError "msg"))
  assertEqual "Legacy SQLiteError code" "SQLITE_ERROR" 
    (toErrorCode (SQLiteError "msg"))
  
  -- Test other error types
  assertEqual "IdentityRupture code" "IDENTITY_RUPTURE" 
    (toErrorCode (IdentityRupture "violation"))
  assertEqual "EssenceRupture code" "ESSENCE_RUPTURE" 
    (toErrorCode (EssenceRupture "violation"))

testToLogMessage :: Test
testToLogMessage = TestCase $ do
  let ctx = Map.fromList [("key", "value")]
      persistErr = mkPersistenceError StageStateBlobUpsert "test_op" "TEST_001" ctx
      msg = toLogMessage persistErr
  
  -- Check that message contains key components
  assertBool "Message should contain 'PersistenceError'" 
    ("PersistenceError" `T.isInfixOf` msg)
  assertBool "Message should contain stage" 
    ("StageStateBlobUpsert" `T.isInfixOf` msg)
  assertBool "Message should contain operation" 
    ("test_op" `T.isInfixOf` msg)
  assertBool "Message should contain error code" 
    ("TEST_001" `T.isInfixOf` msg)
  assertBool "Message should redact context" 
    ("<redacted>" `T.isInfixOf` msg)
  assertBool "Message should NOT leak context values" 
    (not ("value" `T.isInfixOf` msg))

testStructureCompleteness :: Test
testStructureCompleteness = TestCase $ do
  let ctx = Map.fromList [("field1", "val1"), ("field2", "val2")]
  
  -- PersistenceErrorStructured
  let persistErr = mkPersistenceError StageTurnQualityUpsert "op1" "CODE1" ctx
  case persistErr of
    PersistenceErrorStructured details -> do
      assertEqual "Stage should be set" StageTurnQualityUpsert (pedStage details)
      assertBool "Operation should be set" (not (T.null (pedOperation details)))
      assertBool "Error code should be set" (not (T.null (pedErrorCode details)))
      assertEqual "Context should be preserved" 2 (Map.size (pedContext details))
    _ -> assertFailure "Wrong constructor"
  
  -- RuntimeInitErrorStructured
  let runtimeErr = mkRuntimeInitError "comp1" "op2" "CODE2" ctx
  case runtimeErr of
    RuntimeInitErrorStructured details -> do
      assertBool "Component should be set" (not (T.null (riedComponent details)))
      assertBool "Operation should be set" (not (T.null (riedOperation details)))
      assertBool "Error code should be set" (not (T.null (riedErrorCode details)))
      assertEqual "Context should be preserved" 2 (Map.size (riedContext details))
    _ -> assertFailure "Wrong constructor"

testContextSerialization :: Test
testContextSerialization = TestCase $ do
  let ctx = Map.fromList 
        [ ("unicode_key", "значение")
        , ("special_chars", "!@#$%^&*()")
        , ("empty", "")
        , ("number", "42")
        ]
      err = mkSQLiteError "test_op" "TEST_CODE" ctx
  
  case err of
    SQLiteErrorStructured details -> do
      let retrievedCtx = sedContext details
      assertEqual "Context size" 4 (Map.size retrievedCtx)
      assertEqual "Unicode value" (Just "значение") (Map.lookup "unicode_key" retrievedCtx)
      assertEqual "Special chars" (Just "!@#$%^&*()") (Map.lookup "special_chars" retrievedCtx)
      assertEqual "Empty value" (Just "") (Map.lookup "empty" retrievedCtx)
      assertEqual "Number value" (Just "42") (Map.lookup "number" retrievedCtx)
    _ -> assertFailure "Wrong constructor"

-- ============================================================================
-- Integration Tests
-- ============================================================================

testPersistenceCatchable :: Test
testPersistenceCatchable = TestCase $ do
  let ctx = Map.fromList [("test", "integration")]
      err = mkPersistenceError StageSessionTouch "touch" "CATCH_TEST" ctx
  
  result <- try (throwIO err) :: IO (Either QxFx0Exception ())
  case result of
    Left caughtErr -> do
      assertEqual "Error code should match" "CATCH_TEST" (toErrorCode caughtErr)
      case caughtErr of
        PersistenceErrorStructured details ->
          assertEqual "Operation should match" "touch" (pedOperation details)
        _ -> assertFailure "Caught wrong error type"
    Right _ -> assertFailure "Exception was not thrown"

testRuntimeInitCatchable :: Test
testRuntimeInitCatchable = TestCase $ do
  let ctx = Map.fromList [("component", "test")]
      err = mkRuntimeInitError "test_comp" "init" "INIT_CATCH" ctx
  
  result <- try (throwIO err) :: IO (Either QxFx0Exception ())
  case result of
    Left caughtErr -> do
      assertEqual "Error code should match" "INIT_CATCH" (toErrorCode caughtErr)
      case caughtErr of
        RuntimeInitErrorStructured details ->
          assertEqual "Component should match" "test_comp" (riedComponent details)
        _ -> assertFailure "Caught wrong error type"
    Right _ -> assertFailure "Exception was not thrown"

testEmbeddingCatchable :: Test
testEmbeddingCatchable = TestCase $ do
  let ctx = Map.fromList [("backend", "test")]
      err = mkEmbeddingError "test_backend" "embed" "EMBED_CATCH" ctx
  
  result <- try (throwIO err) :: IO (Either QxFx0Exception ())
  case result of
    Left caughtErr -> do
      assertEqual "Error code should match" "EMBED_CATCH" (toErrorCode caughtErr)
      case caughtErr of
        EmbeddingErrorStructured details ->
          assertEqual "Backend should match" "test_backend" (eedBackend details)
        _ -> assertFailure "Caught wrong error type"
    Right _ -> assertFailure "Exception was not thrown"

testSQLiteCatchable :: Test
testSQLiteCatchable = TestCase $ do
  let ctx = Map.fromList [("operation", "test")]
      err = mkSQLiteError "test_query" "SQLITE_CATCH" ctx
  
  result <- try (throwIO err) :: IO (Either QxFx0Exception ())
  case result of
    Left caughtErr -> do
      assertEqual "Error code should match" "SQLITE_CATCH" (toErrorCode caughtErr)
      case caughtErr of
        SQLiteErrorStructured details ->
          assertEqual "Operation should match" "test_query" (sedOperation details)
        _ -> assertFailure "Caught wrong error type"
    Right _ -> assertFailure "Exception was not thrown"

-- ============================================================================
-- Backward Compatibility Tests
-- ============================================================================

testOldConstructorsWork :: Test
testOldConstructorsWork = TestCase $ do
  let legacyPersist = PersistenceError "legacy message"
      legacyRuntime = RuntimeInitError "legacy init"
      legacyEmbed = EmbeddingError "legacy embed"
      legacySQLite = SQLiteError "legacy sqlite"
  
  -- Pattern matching should work
  case legacyPersist of
    PersistenceError msg -> assertEqual "Legacy persist message" "legacy message" msg
    _ -> assertFailure "Pattern match failed"
  
  case legacyRuntime of
    RuntimeInitError msg -> assertEqual "Legacy runtime message" "legacy init" msg
    _ -> assertFailure "Pattern match failed"
  
  case legacyEmbed of
    EmbeddingError msg -> assertEqual "Legacy embed message" "legacy embed" msg
    _ -> assertFailure "Pattern match failed"
  
  case legacySQLite of
    SQLiteError msg -> assertEqual "Legacy sqlite message" "legacy sqlite" msg
    _ -> assertFailure "Pattern match failed"

testExistingHandlers :: Test
testExistingHandlers = TestCase $ do
  -- Simulate a handler that catches QxFx0Exception
  let handler :: QxFx0Exception -> IO Text
      handler ex = pure (toErrorCode ex)
  
  -- Test with legacy error
  code1 <- catch (throwIO (PersistenceError "test")) handler
  assertBool "Legacy error should be catchable" (not (T.null code1))
  
  -- Test with structured error
  let structErr = mkPersistenceError StageStateBlobUpsert "op" "STRUCT_001" Map.empty
  code2 <- catch (throwIO structErr) handler
  assertEqual "Structured error code" "STRUCT_001" code2
  
  -- Both should be caught by the same handler
  assertBool "Handler should work for both types" 
    (not (T.null code1) && not (T.null code2))

-- ============================================================================
-- Edge Cases Tests
-- ============================================================================

testEmptyContext :: Test
testEmptyContext = TestCase $ do
  let err = mkSQLiteError "test_op" "EMPTY_CTX" Map.empty
  
  case err of
    SQLiteErrorStructured details -> do
      assertEqual "Context should be empty" 0 (Map.size (sedContext details))
      let msg = toLogMessage err
      assertBool "Message should still be valid" (not (T.null msg))
    _ -> assertFailure "Wrong constructor"

testLargeContext :: Test
testLargeContext = TestCase $ do
  let largeCtx = Map.fromList 
        [ ("key" <> T.pack (show i), "value" <> T.pack (show i)) 
        | i <- [1..100 :: Int]
        ]
      err = mkRuntimeInitError "comp" "op" "LARGE_CTX" largeCtx
  
  case err of
    RuntimeInitErrorStructured details -> do
      assertEqual "Context size" 100 (Map.size (riedContext details))
      -- Verify a few random entries
      assertEqual "Key 1" (Just "value1") (Map.lookup "key1" (riedContext details))
      assertEqual "Key 50" (Just "value50") (Map.lookup "key50" (riedContext details))
      assertEqual "Key 100" (Just "value100") (Map.lookup "key100" (riedContext details))
      
      -- Log message should still be reasonable length (context is redacted)
      let msg = toLogMessage err
      assertBool "Message should be reasonable length" (T.length msg < 500)
    _ -> assertFailure "Wrong constructor"

