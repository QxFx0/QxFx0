{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Suite.NativeSQLiteClose
  ( nativeSQLiteCloseTests
  ) where

import Control.Exception (SomeException, try)
import qualified Data.Text as T
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import Test.Support (freshTestDbPath, queryCount, removeIfExists)

-- | Pins for the total @close@ contract (fast-suite flake 2026-11-10).
--
-- @sqlite3_close@ returns @SQLITE_BUSY@ (rc=5) while the handle still owns
-- prepared statements.  Production code reaches that state whenever a
-- statement sequence is interrupted between @prepare@ and @finalize@
-- (asynchronous cancellation is the common cause).  'NSQL.close' must release
-- the handle anyway and report the leak, never leave it open.
nativeSQLiteCloseTests :: [Test]
nativeSQLiteCloseTests =
  [ testCleanCloseSucceeds
  , testUnfinalizedStatementsListsSql
  , testCloseFinalizesLeakedStatement
  , testCloseFinalizesSeveralLeaks
  , testFailedQueryLeavesNoStatement
  ]

openTempDb :: IO (FilePath, NSQL.Database)
openTempDb = do
  path <- freshTestDbPath "qxfx0_test_native_sqlite_close.db"
  opened <- NSQL.open path
  db <- case opened of
    Left err -> assertFailure ("cannot open close test DB: " <> T.unpack err) >> fail "unreachable"
    Right conn -> pure conn
  pure (path, db)

cleanupDb :: FilePath -> IO ()
cleanupDb path = mapM_ removeIfExists [path, path <> "-wal", path <> "-shm"]

prepareOrFail :: NSQL.Database -> T.Text -> IO NSQL.Statement
prepareOrFail db sql = do
  prepared <- NSQL.prepare db sql
  case prepared of
    Left err -> assertFailure ("prepare failed: " <> T.unpack err) >> fail "unreachable"
    Right stmt -> pure stmt

execOrFail :: NSQL.Database -> T.Text -> IO ()
execOrFail db sql = do
  result <- NSQL.execSql db sql
  case result of
    Left err -> assertFailure ("exec failed: " <> T.unpack err)
    Right _ -> pure ()

-- | B4: the success path is untouched — a clean handle owns no statements and
-- closes without an error.
testCleanCloseSucceeds :: Test
testCleanCloseSucceeds = TestLabel "clean close succeeds and owns no statements" $ TestCase $ do
  (path, db) <- openTempDb
  leaks <- NSQL.unfinalizedStatements db
  assertEqual "a freshly opened handle owns no prepared statements" [] leaks
  execOrFail db "CREATE TABLE close_clean(id INTEGER PRIMARY KEY)"
  closed <- try (NSQL.close db) :: IO (Either SomeException ())
  case closed of
    Left ex -> assertFailure ("close on a clean handle must not fail: " <> show ex)
    Right () -> pure ()
  cleanupDb path

-- | The diagnostic must name the leaked statement, otherwise a rc=5 report is
-- undebuggable (this is what located the worker-side leak).
testUnfinalizedStatementsListsSql :: Test
testUnfinalizedStatementsListsSql = TestLabel "unfinalizedStatements lists the live statement SQL" $ TestCase $ do
  (path, db) <- openTempDb
  stmt <- prepareOrFail db "SELECT 1 AS leaked_probe"
  leaks <- NSQL.unfinalizedStatements db
  assertEqual "exactly one live statement is reported" 1 (length leaks)
  assertBool "the reported text carries the statement SQL"
    (any (T.isInfixOf "leaked_probe") leaks)
  NSQL.finalize stmt
  NSQL.close db
  cleanupDb path

-- | The leak itself: a statement prepared and never finalized (the shape an
-- asynchronous kill leaves behind).  Close must finalize it and release the
-- handle; a reopen must then see the committed schema.
testCloseFinalizesLeakedStatement :: Test
testCloseFinalizesLeakedStatement =
  TestLabel "close finalizes a leaked statement and releases the handle" $ TestCase $ do
    (path, db) <- openTempDb
    stmt <- prepareOrFail db "CREATE TABLE close_leak_probe(id INTEGER PRIMARY KEY, label TEXT)"
    _ <- NSQL.step stmt
    -- Deliberately no finalize: the statement is still attached at close time.
    closed <- try (NSQL.close db) :: IO (Either SomeException ())
    case closed of
      Left ex -> assertFailure ("close must recover from a leaked statement: " <> show ex)
      Right () -> pure ()
    reopened <- NSQL.open path
    db2 <- case reopened of
      Left err -> assertFailure ("reopen after a leaked close failed: " <> T.unpack err) >> fail "unreachable"
      Right conn -> pure conn
    probe <- prepareOrFail db2 "SELECT COUNT(*) FROM sqlite_master WHERE name='close_leak_probe'"
    hasRow <- NSQL.stepRow probe
    assertBool "the schema probe returns a row" hasRow
    found <- NSQL.columnInt probe 0
    NSQL.finalize probe
    assertEqual "the table created before the leaked close is visible" 1 found
    NSQL.close db2
    cleanupDb path

-- | Every leftover is finalized, not just the first one — a cancellation can
-- strand more than one statement.
testCloseFinalizesSeveralLeaks :: Test
testCloseFinalizesSeveralLeaks =
  TestLabel "close finalizes every leaked statement" $ TestCase $ do
    (path, db) <- openTempDb
    _ <- prepareOrFail db "SELECT 1 AS first_leak"
    _ <- prepareOrFail db "SELECT 2 AS second_leak"
    leaks <- NSQL.unfinalizedStatements db
    assertEqual "both statements are reported" 2 (length leaks)
    assertBool "first statement is named" (any (T.isInfixOf "first_leak") leaks)
    assertBool "second statement is named" (any (T.isInfixOf "second_leak") leaks)
    closed <- try (NSQL.close db) :: IO (Either SomeException ())
    case closed of
      Left ex -> assertFailure ("close must recover from several leaks: " <> show ex)
      Right () -> pure ()
    -- The handle is gone: a fresh open of the same file must succeed.
    reopened <- NSQL.open path
    case reopened of
      Left err -> assertFailure ("reopen after leaked close failed: " <> T.unpack err)
      Right db2 -> NSQL.close db2
    -- The leaked pointers are dead now: close finalized them, so they must not
    -- be finalized again here (a double finalize is undefined behaviour).
    cleanupDb path

-- | A query that fails *after* prepare (integer overflow at step) must not
-- strand its statement: 'queryCount' finalizes in @finally@.  Without that
-- hygiene the leaked statement is what makes the enclosing close fail with
-- rc=5 and mask the real error.
testFailedQueryLeavesNoStatement :: Test
testFailedQueryLeavesNoStatement =
  TestLabel "a query that fails at step leaves no statement behind" $ TestCase $ do
    (path, db) <- openTempDb
    failed <- try (queryCount db "SELECT abs(-9223372036854775808)")
      :: IO (Either SomeException Int)
    case failed of
      Right value -> assertFailure ("the overflow probe must fail at step, got " <> show value)
      Left _ -> pure ()
    leaks <- NSQL.unfinalizedStatements db
    assertEqual "the failed query must not strand its statement" [] leaks
    closed <- try (NSQL.close db) :: IO (Either SomeException ())
    case closed of
      Left ex -> assertFailure ("close after a failed query must succeed: " <> show ex)
      Right () -> pure ()
    cleanupDb path
