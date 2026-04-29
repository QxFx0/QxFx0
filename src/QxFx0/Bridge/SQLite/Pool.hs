{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}

{-| Connection and pool lifecycle helpers for the runtime SQLite backend. -}
module QxFx0.Bridge.SQLite.Pool
  ( QxFx0DB(..)
  , WorkerDBPool
  , newDBPool
  , closeDBPool
  , withDB
  , withPooledDB
  , execOrThrow
  ) where

import Control.Concurrent.MVar (MVar, newMVar, putMVar, takeMVar)
import Control.Exception (finally, mask, mask_, onException, throwIO)
import Data.Text (Text)
import qualified Data.Text as T
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(SQLiteError)
  , tryAsync
  , throwQxFx0
  )
import System.Timeout (timeout)

data QxFx0DB = QxFx0DB
  { qdbPath :: !FilePath
  , qdbConn :: !NSQL.Database
  }

data WorkerDBPool = WorkerDBPool
  { poolMVar :: !(MVar [NSQL.Database])
  , poolPath :: !FilePath
  , poolSize :: !Int
  }

newDBPool :: FilePath -> Int -> IO WorkerDBPool
newDBPool path size = do
  conns <- buildPoolConnections size []
  mvar <- newMVar conns
  pure WorkerDBPool {poolMVar = mvar, poolPath = path, poolSize = size}
  where
    buildPoolConnections 0 acc = pure (reverse acc)
    buildPoolConnections n acc = do
      openResult <- tryAsync (openInitializedConnection path)
      case openResult of
        Right db ->
          buildPoolConnections (n - 1) (db : acc)
        Left ex -> do
          mapM_ safeClose acc
          throwIO ex

closeDBPool :: WorkerDBPool -> IO ()
closeDBPool pool = mask_ $ do
  conns <- takeMVar (poolMVar pool)
  finally
    (mapM_ NSQL.close conns)
    (putMVar (poolMVar pool) [])

withDB :: FilePath -> (NSQL.Database -> IO a) -> IO (Either Text a)
withDB path action = do
  mDb <- NSQL.open path
  case mDb of
    Left err -> pure (Left err)
    Right db ->
      finally
        (do
            result <- tryAsync $ do
              execOrThrow db "PRAGMA journal_mode=WAL;"
              execOrThrow db "PRAGMA foreign_keys=ON;"
              action db
            case result of
              Right value -> pure (Right value)
              Left ex -> pure (Left ("db action failed: " <> T.pack (show ex))))
        (safeClose db)

withPooledDB :: WorkerDBPool -> (NSQL.Database -> IO a) -> IO a
withPooledDB pool action = mask $ \restore -> do
  mConns <- timeout poolAcquireTimeoutMicros (takeMVar (poolMVar pool))
  conns <-
    case mConns of
      Nothing ->
        throwQxFx0
          (SQLiteError
            ("timed out waiting for SQLite pool connection (pool_size="
              <> T.pack (show (poolSize pool))
              <> ")"))
      Just available -> pure available
  withConnections restore conns
  where
    poolAcquireTimeoutMicros :: Int
    poolAcquireTimeoutMicros = 5000000

    withConnections restore [] = do
      db <- openInitializedConnection (poolPath pool)
      finally
        (restore (action db))
        (safeClose db `finally` putMVar (poolMVar pool) [])
    withConnections restore (db : dbs) =
      finally
        (restore (action db))
        (restorePooledConnection db dbs)

    restorePooledConnection db dbs = do
      mDb <- sanitizeForPool db
      case mDb of
        Just cleanDb ->
          putMVar (poolMVar pool) (cleanDb : dbs)
        Nothing ->
          putMVar (poolMVar pool) dbs

    sanitizeForPool db = do
      rollbackResult <- NSQL.execSql db "ROLLBACK;"
      case rollbackResult of
        Right _ ->
          pure (Just db)
        Left err
          | isNoActiveTransactionError err ->
              pure (Just db)
          | otherwise -> do
              safeClose db
              replacement <- tryAsync (openInitializedConnection (poolPath pool))
              case replacement of
                Right freshDb -> pure (Just freshDb)
                Left _ -> pure Nothing

isNoActiveTransactionError :: Text -> Bool
isNoActiveTransactionError err =
  "no transaction is active" `T.isInfixOf` T.toLower err

openInitializedConnection :: FilePath -> IO NSQL.Database
openInitializedConnection path = do
  mDb <- NSQL.open path
  case mDb of
    Left err ->
      throwQxFx0 (SQLiteError err)
    Right db ->
      (do
          execOrThrow db "PRAGMA journal_mode=WAL;"
          execOrThrow db "PRAGMA synchronous=NORMAL;"
          execOrThrow db "PRAGMA foreign_keys=ON;"
          pure db)
      `onException` safeClose db

safeClose :: NSQL.Database -> IO ()
safeClose db = do
  _ <- tryAsync (NSQL.close db)
  pure ()

execOrThrow :: NSQL.Database -> Text -> IO ()
execOrThrow db sql = do
  result <- NSQL.execSql db sql
  case result of
    Left err ->
      throwQxFx0
        (SQLiteError ("sqlite exec failed for `" <> sql <> "`: " <> err))
    Right _ -> pure ()
