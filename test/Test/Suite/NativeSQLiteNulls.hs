{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.NativeSQLiteNulls
  ( nativeSQLiteNullsTests
  ) where

import qualified Data.Text as T
import System.Directory (removeFile)
import Control.Exception (try)
import System.IO.Error (isDoesNotExistError)
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL

nativeSQLiteNullsTests :: [Test]
nativeSQLiteNullsTests =
  [ testColumnIntMaybeDistinguishesNull
  , testColumnDoubleMaybeDistinguishesNull
  , testColumnIntNullBackwardCompatibility
  , testColumnDoubleNullBackwardCompatibility
  ]

tempDbPath :: FilePath
tempDbPath = "qxfx0_test_native_sqlite_nulls.db"

withTempDb :: (NSQL.Database -> IO a) -> IO a
withTempDb action = do
  _ <- tryRemoveTempDb
  result <- NSQL.withDatabase tempDbPath action
  case result of
    Left err -> assertFailure ("failed to open temp database: " <> T.unpack err)
    Right a -> pure a

tryRemoveTempDb :: IO ()
tryRemoveTempDb = do
  result <- try (removeFile tempDbPath)
  case result of
    Left e | isDoesNotExistError e -> pure ()
    Left _ -> pure ()
    Right () -> pure ()

exec :: NSQL.Database -> T.Text -> IO ()
exec db sql = do
  result <- NSQL.execSql db sql
  case result of
    Left err -> assertFailure ("exec failed: " <> T.unpack err)
    Right () -> pure ()

insertFixture :: NSQL.Database -> Maybe Int -> Maybe Double -> IO ()
insertFixture db mIntVal mDoubleVal = do
  mStmt <- NSQL.prepare db "INSERT INTO nulls_test(int_col, real_col) VALUES(?, ?)"
  stmt <- case mStmt of
    Left err -> assertFailure ("prepare insert failed: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  case mIntVal of
    Nothing -> pure ()
    Just v -> do
      _ <- NSQL.bindInt stmt 1 v
      pure ()
  case mDoubleVal of
    Nothing -> pure ()
    Just v -> do
      _ <- NSQL.bindDouble stmt 2 v
      pure ()
  _ <- NSQL.step stmt
  NSQL.finalize stmt

testColumnIntMaybeDistinguishesNull :: Test
testColumnIntMaybeDistinguishesNull = TestCase $ withTempDb $ \db -> do
  exec db "CREATE TABLE nulls_test(id INTEGER PRIMARY KEY, int_col INTEGER, real_col REAL)"
  insertFixture db (Just 42) (Just 3.14)
  insertFixture db Nothing Nothing

  mStmt <- NSQL.prepare db "SELECT int_col FROM nulls_test ORDER BY id"
  stmt <- case mStmt of
    Left err -> assertFailure ("prepare select failed: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s

  -- First row: non-NULL integer.
  hasRow1 <- NSQL.stepRow stmt
  assertBool "expected first row" hasRow1
  intMaybe1 <- NSQL.columnIntMaybe stmt 0
  assertEqual "non-NULL integer should read as Just value"
    (Just 42) intMaybe1

  -- Second row: NULL integer.
  hasRow2 <- NSQL.stepRow stmt
  assertBool "expected second row" hasRow2
  intMaybe2 <- NSQL.columnIntMaybe stmt 0
  assertEqual "NULL integer should read as Nothing"
    Nothing intMaybe2

  NSQL.finalize stmt

testColumnDoubleMaybeDistinguishesNull :: Test
testColumnDoubleMaybeDistinguishesNull = TestCase $ withTempDb $ \db -> do
  exec db "CREATE TABLE nulls_test(id INTEGER PRIMARY KEY, int_col INTEGER, real_col REAL)"
  insertFixture db (Just 0) (Just 2.71)
  insertFixture db Nothing Nothing

  mStmt <- NSQL.prepare db "SELECT real_col FROM nulls_test ORDER BY id"
  stmt <- case mStmt of
    Left err -> assertFailure ("prepare select failed: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s

  -- First row: non-NULL real.
  hasRow1 <- NSQL.stepRow stmt
  assertBool "expected first row" hasRow1
  doubleMaybe1 <- NSQL.columnDoubleMaybe stmt 0
  assertEqual "non-NULL real should read as Just value"
    (Just 2.71) doubleMaybe1

  -- Second row: NULL real.
  hasRow2 <- NSQL.stepRow stmt
  assertBool "expected second row" hasRow2
  doubleMaybe2 <- NSQL.columnDoubleMaybe stmt 0
  assertEqual "NULL real should read as Nothing"
    Nothing doubleMaybe2

  NSQL.finalize stmt

testColumnIntNullBackwardCompatibility :: Test
testColumnIntNullBackwardCompatibility = TestCase $ withTempDb $ \db -> do
  exec db "CREATE TABLE nulls_test(id INTEGER PRIMARY KEY, int_col INTEGER, real_col REAL)"
  insertFixture db Nothing Nothing

  mStmt <- NSQL.prepare db "SELECT int_col FROM nulls_test"
  stmt <- case mStmt of
    Left err -> assertFailure ("prepare select failed: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  hasRow <- NSQL.stepRow stmt
  assertBool "expected a row" hasRow
  intVal <- NSQL.columnInt stmt 0
  assertEqual "legacy columnInt must return 0 for NULL"
    0 intVal
  NSQL.finalize stmt

testColumnDoubleNullBackwardCompatibility :: Test
testColumnDoubleNullBackwardCompatibility = TestCase $ withTempDb $ \db -> do
  exec db "CREATE TABLE nulls_test(id INTEGER PRIMARY KEY, int_col INTEGER, real_col REAL)"
  insertFixture db Nothing Nothing

  mStmt <- NSQL.prepare db "SELECT real_col FROM nulls_test"
  stmt <- case mStmt of
    Left err -> assertFailure ("prepare select failed: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  hasRow <- NSQL.stepRow stmt
  assertBool "expected a row" hasRow
  doubleVal <- NSQL.columnDouble stmt 0
  assertEqual "legacy columnDouble must return 0.0 for NULL"
    0.0 doubleVal
  NSQL.finalize stmt
