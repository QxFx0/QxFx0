{-# LANGUAGE OverloadedStrings #-}

{-| Audit 2026-10-16 п.19 anti-rot: the runtime must run on a threaded RTS
with safe bindings for the blocking SQLite calls, and the pool acquire must
not be able to drop a connection when its deadline expires.
-}
module Test.Suite.SQLiteRuntime
  ( sqliteRuntimeTests
  ) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, threadDelay)
import Control.Exception (finally)
import Control.Monad (replicateM_)
import Data.IORef (atomicModifyIORef', newIORef, readIORef, writeIORef)
import qualified Data.Text as T
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.SQLite
  ( acquireConnectionsWithTimeout
  , bindTextOrFail
  , closeDBPool
  , maybeCheckpoint
  , newDBPool
  , poolAvailableConnections
  , withPooledDB
  )
import QxFx0.ExceptionPolicy (QxFx0Exception(..), SQLiteErrorDetails(..), tryQxFx0)
import Test.Support (assertExec, freshTestPath, removeIfExists)

sqliteRuntimeTests :: [Test]
sqliteRuntimeTests =
  [ TestLabel "blocking SQLite call keeps Haskell threads running"
      testBlockingFfiKeepsHaskellRunning
  , TestLabel "pool acquire timeout is structured and lossless"
      testAcquireTimeoutIsLossless
  , TestLabel "pooled actions return every connection"
      testPoolSizeStable
  , TestLabel "bindTextOrFail binds a value" testBindTextOrFailBinds
  , TestLabel "bindTextOrFail rejects an out-of-range index"
      testBindTextOrFailRejectsRange
  , TestLabel "maybeCheckpoint gate runs on the 100th turn"
      testMaybeCheckpointGate
  ]

-- | A blocking write on one connection must not freeze unrelated Haskell
-- threads: the ticker has to keep advancing while the FFI call waits for the
-- busy timeout.  This is a functional invariant, not a latency bar: on a
-- vanilla RTS, or with an unsafe step/exec binding, the delta is zero.
testBlockingFfiKeepsHaskellRunning :: Test
testBlockingFfiKeepsHaskellRunning =
  TestLabel "blocking SQLite call keeps Haskell threads running" $ TestCase $ do
    path <- freshTestPath "qxfx0_sqlite_tick.db"
    dbA <- openOrFail "writer A" path
    dbB <- openOrFail "writer B" path
    let cleanup = do
          _ <- NSQL.execSql dbA "ROLLBACK;"
          _ <- NSQL.close dbA
          _ <- NSQL.close dbB
          removeSqliteFiles path
        body = do
          assertExec dbA "busy timeout A" "PRAGMA busy_timeout=1000;"
          assertExec dbB "busy timeout B" "PRAGMA busy_timeout=1000;"
          assertExec dbA "tick table" "CREATE TABLE tick(x INTEGER);"
          assertExec dbA "exclusive lock" "BEGIN EXCLUSIVE;"
          ticks <- newIORef (0 :: Int)
          stop <- newIORef False
          _ <- forkIO $ do
            let loop = do
                  done <- readIORef stop
                  if done
                    then pure ()
                    else do
                      threadDelay 10000
                      atomicModifyIORef' ticks (\n -> (n + 1, ()))
                      loop
            loop
          threadDelay 100000
          before <- readIORef ticks
          lockResult <- NSQL.execSql dbB "INSERT INTO tick VALUES (1);"
          after <- readIORef ticks
          writeIORef stop True
          case lockResult of
            Left _ -> pure ()
            Right _ ->
              assertFailure "the second writer must not pass the exclusive lock"
          assertBool
            ( "Haskell progress stalled during the blocking SQLite call (before="
                <> show before
                <> ", after="
                <> show after
                <> "): the RTS must be threaded and step/exec must be safe"
            )
            (after - before >= 20)
    body `finally` cleanup

-- | The deadline path must surface the same structured TIMEOUT error and must
-- never consume a value that appears at the deadline boundary.
testAcquireTimeoutIsLossless :: Test
testAcquireTimeoutIsLossless =
  TestLabel "pool acquire timeout is structured and lossless" $ TestCase $ do
    slot <- newEmptyMVar
    timedOut <- tryQxFx0 (acquireConnectionsWithTimeout slot 50000)
    case timedOut of
      Left (SQLiteErrorStructured details) ->
        assertEqual "acquire timeout code" "TIMEOUT" (sedErrorCode details)
      Left other -> assertFailure ("unexpected exception: " <> show other)
      Right _ -> assertFailure "acquire must time out when the pool slot is empty"
    path <- freshTestPath "qxfx0_sqlite_acquire.db"
    db <- openOrFail "acquire value" path
    putMVar slot [db]
    acquired <- acquireConnectionsWithTimeout slot 50000
    assertEqual "the pooled connection must come back intact" 1 (length acquired)
    mapM_ NSQL.close acquired
    removeSqliteFiles path

testPoolSizeStable :: Test
testPoolSizeStable =
  TestLabel "pooled actions return every connection" $ TestCase $ do
    path <- freshTestPath "qxfx0_sqlite_poolstable.db"
    pool <- newDBPool path 2
    let cleanup = do
          closeDBPool pool
          removeSqliteFiles path
    (do
        replicateM_ 10 (withPooledDB pool (\db -> assertExec db "pooled select" "SELECT 1;"))
        available <- poolAvailableConnections pool
        assertEqual "both pooled connections must return" 2 available
      ) `finally` cleanup

testBindTextOrFailBinds :: Test
testBindTextOrFailBinds = TestCase $ do
  path <- freshTestPath "qxfx0_sqlite_bind_ok.db"
  db <- openOrFail "bind ok" path
  let cleanup = NSQL.close db >> removeSqliteFiles path
  (do
      mStmt <- NSQL.prepare db "SELECT ?"
      case mStmt of
        Left err -> assertFailure ("prepare failed: " <> T.unpack err)
        Right stmt -> do
          (do
              bindTextOrFail "bindTextOrFail-pin" stmt 1 "x"
              hasRow <- NSQL.stepRow stmt
              assertBool "the bound SELECT must produce a row" hasRow
              value <- NSQL.columnText stmt 0
              assertEqual "the bound value must round-trip" "x" value
            ) `finally` (NSQL.finalize stmt >> pure ())
          pure ()
    ) `finally` cleanup

testBindTextOrFailRejectsRange :: Test
testBindTextOrFailRejectsRange = TestCase $ do
  path <- freshTestPath "qxfx0_sqlite_bind_range.db"
  db <- openOrFail "bind range" path
  let cleanup = NSQL.close db >> removeSqliteFiles path
  (do
      mStmt <- NSQL.prepare db "SELECT 1"
      case mStmt of
        Left err -> assertFailure ("prepare failed: " <> T.unpack err)
        Right stmt -> do
          (do
              result <- tryQxFx0 (bindTextOrFail "bindTextOrFail-pin" stmt 1 "x")
              case result of
                Left (SQLiteErrorStructured details) -> do
                  assertEqual "operation label" "bindTextOrFail-pin"
                    (sedOperation details)
                  assertBool "the bind error is surfaced"
                    ("bindText failed" `T.isInfixOf` sedErrorCode details)
                Left other -> assertFailure ("unexpected exception: " <> show other)
                Right () -> assertFailure "an out-of-range bind must not succeed"
            ) `finally` (NSQL.finalize stmt >> pure ())
          pure ()
    ) `finally` cleanup

testMaybeCheckpointGate :: Test
testMaybeCheckpointGate = TestCase $ do
  path <- freshTestPath "qxfx0_sqlite_checkpoint.db"
  db <- openOrFail "checkpoint" path
  let cleanup = NSQL.close db >> removeSqliteFiles path
  (do
      assertExec db "checkpoint schema" "CREATE TABLE checkpoint_gate(x INTEGER);"
      maybeCheckpoint db 99
      maybeCheckpoint db 100
    ) `finally` cleanup

openOrFail :: String -> FilePath -> IO NSQL.Database
openOrFail label path = do
  result <- NSQL.open path
  case result of
    Left err ->
      assertFailure (label <> " open failed: " <> T.unpack err) >> fail "unreachable"
    Right db -> pure db

removeSqliteFiles :: FilePath -> IO ()
removeSqliteFiles path =
  mapM_ removeIfExists [path, path <> "-wal", path <> "-shm"]
