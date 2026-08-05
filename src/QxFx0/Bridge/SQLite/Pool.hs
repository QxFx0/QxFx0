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

import Control.Concurrent (ThreadId, myThreadId, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar, newMVar, putMVar, takeMVar)
import Control.Exception (finally, mask, mask_, onException, throwIO)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import System.IO (hPutStrLn, stderr)
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(PersistenceTxError, SQLiteErrorStructured)
  , SQLiteErrorDetails(..)
  , catchIO
  , mkSQLiteError
  , tryAsync
  , tryQxFx0
  , throwQxFx0
  )
import System.Timeout (timeout)
import System.IO.Unsafe (unsafePerformIO)

data QxFx0DB = QxFx0DB
  { qdbPath :: !FilePath
  , qdbConn :: !NSQL.Database
  }

data WorkerDBPool = WorkerDBPool
  { poolMVar :: !(MVar [NSQL.Database])
  , poolPath :: !FilePath
  , poolSize :: !Int
  }

-- | SQLite permits only one writer.  Autonomous audit, worker, and governed
-- apply all use 'withDB', so serialize their local process actions before
-- relying on SQLite's cross-process busy handling.  A process-global lock is
-- deliberate here: it protects a single state database without widening any
-- domain authority or changing transaction contents.
databaseActionLock :: MVar (Maybe (ThreadId, Int))
{-# NOINLINE databaseActionLock #-}
databaseActionLock = unsafePerformIO (newMVar Nothing)

-- | Serialize all local SQLite actions while permitting the same thread to
-- re-enter the lock.  Bootstrap uses a pooled connection and, in a few
-- compatibility paths, invokes a helper implemented with 'withDB' inside it;
-- a plain MVar would deadlock there.
withDatabaseActionLock :: IO a -> IO a
withDatabaseActionLock action = mask $ \restore -> do
  owner <- myThreadId
  acquireDatabaseActionLock owner
  value <- restore action `onException` releaseDatabaseActionLock owner
  releaseDatabaseActionLock owner
  pure value

acquireDatabaseActionLock :: ThreadId -> IO ()
acquireDatabaseActionLock owner = do
  acquired <- modifyMVar databaseActionLock $ \state ->
    case state of
      Nothing -> pure (Just (owner, 1), True)
      Just (heldBy, depth)
        | heldBy == owner -> pure (Just (heldBy, depth + 1), True)
        | otherwise -> pure (state, False)
  if acquired
    then pure ()
    else threadDelay 1000 >> acquireDatabaseActionLock owner

releaseDatabaseActionLock :: ThreadId -> IO ()
releaseDatabaseActionLock owner =
  modifyMVar databaseActionLock $ \state ->
    case state of
      Just (heldBy, depth)
        | heldBy == owner && depth > 1 -> pure (Just (heldBy, depth - 1), ())
        | heldBy == owner -> pure (Nothing, ())
      _ -> pure (state, ())

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
  results <- mapM (tryAsync . NSQL.close) conns
    `finally` putMVar (poolMVar pool) []
  case [err | Left err <- results] of
    err : _ -> throwIO err
    [] -> pure ()

withDB :: FilePath -> (NSQL.Database -> IO a) -> IO (Either Text a)
withDB path action = withDatabaseActionLock runOnce
  where
    runOnce = do
      mDb <- NSQL.open path
      case mDb of
        Left err -> pure (Left err)
        Right db ->
          finally
            (catchIO
              (do
                qxfx0Result <- tryQxFx0 $ do
                  -- journal_mode changes need an exclusive lock.  Bootstrap and
                  -- pooled connections establish WAL once; repeating it for each
                  -- worker write races normal turn transactions.
                  execOrThrow db "PRAGMA busy_timeout=5000;"
                  execOrThrow db "PRAGMA foreign_keys=ON;"
                  action db
                case qxfx0Result of
                  Right value -> pure (Right value)
                  Left ex -> pure (Left (renderDbActionFailure ex)))
              (\err -> pure (Left ("db action failed: " <> T.pack (show err)))))
            (safeClose db)

renderDbActionFailure :: QxFx0Exception -> Text
renderDbActionFailure ex =
  case ex of
    SQLiteErrorStructured details -> "db action failed: " <> sedErrorCode details
    PersistenceTxError stage msg ->
      "db action failed: stage=" <> T.pack (show stage) <> ": " <> msg
    _ -> "db action failed"

withPooledDB :: WorkerDBPool -> (NSQL.Database -> IO a) -> IO a
withPooledDB pool action = withDatabaseActionLock $ mask $ \restore -> do
  mConns <- timeout poolAcquireTimeoutMicros (takeMVar (poolMVar pool))
  conns <-
    case mConns of
      Nothing ->
        throwQxFx0
          (mkSQLiteError
            "pool_acquire"
            "TIMEOUT"
            (Map.singleton "pool_size" (T.pack (show (poolSize pool)))))
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
                Left e -> hPutStrLn stderr ("[sqlite_pool] connection replacement failed: " <> show e) >> pure Nothing

isNoActiveTransactionError :: Text -> Bool
isNoActiveTransactionError err =
  "no transaction is active" `T.isInfixOf` T.toLower err

openInitializedConnection :: FilePath -> IO NSQL.Database
openInitializedConnection path = do
  mDb <- NSQL.open path
  case mDb of
    Left err ->
      throwQxFx0 (mkSQLiteError "open" err Map.empty)
    Right db ->
      (do
          execOrThrow db "PRAGMA journal_mode=WAL;"
          execOrThrow db "PRAGMA busy_timeout=5000;"
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
        (mkSQLiteError "exec" err (Map.singleton "sql" sql))
    Right _ -> pure ()
