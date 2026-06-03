{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-| Per-session critical section registry for serializing concurrent turn execution. -}
module QxFx0.Core.SessionLock
  ( SessionLockManager
  , SessionLockStats(..)
  , newSessionLockManager
  , withSessionLock
  , sessionLockStats
  , sessionLockOverflowShardIndex
  , sessionLockOverflowShardCount
  ) where

import Control.Concurrent.MVar (MVar, newMVar, withMVar, tryReadMVar)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, modifyTVar')
import Control.Monad (replicateM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.List (sortOn)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

data SessionLockEntry = SessionLockEntry
  { sleLock :: !(MVar ())
  , sleLastUsed :: !Int
  }

data SessionLockManager = SessionLockManager
  { slmLocks :: !(TVar (Map Text SessionLockEntry))
  , slmOverflowShards :: ![MVar ()]
  , slmMaxTrackedLocks :: !Int
  , slmAccessCounter :: !(TVar Int)
  }

data SessionLockStats = SessionLockStats
  { slsTrackedLocks :: !Int
  , slsMaxTrackedLocks :: !Int
  , slsOverflowActive :: !Bool
  } deriving stock (Eq, Show)

newSessionLockManager :: IO SessionLockManager
newSessionLockManager = do
  locks <- newTVarIO Map.empty
  overflowShards <- replicateM sessionLockOverflowShardCount (newMVar ())
  accessCounter <- newTVarIO 0
  cap <- resolveMaxTrackedLocks
  pure SessionLockManager
    { slmLocks = locks
    , slmOverflowShards = overflowShards
    , slmMaxTrackedLocks = cap
    , slmAccessCounter = accessCounter
    }

resolveMaxTrackedLocks :: IO Int
resolveMaxTrackedLocks = do
  mEnv <- lookupEnv "QXFX0_MAX_SESSION_LOCKS"
  case mEnv of
    Nothing -> pure defaultMaxTrackedLocks
    Just raw ->
      case reads raw of
        [(n, "")] | n > 0 -> pure n
        _ -> do
          hPutStrLn stderr $ "QXFX0_MAX_SESSION_LOCKS invalid (" <> raw <> "), using default " <> show defaultMaxTrackedLocks
          pure defaultMaxTrackedLocks

defaultMaxTrackedLocks :: Int
defaultMaxTrackedLocks = 4096

withSessionLock :: SessionLockManager -> Text -> IO a -> IO a
withSessionLock mgr sessionId action = do
  lock <- getOrCreateLock mgr sessionId
  withMVar lock (\_ -> action)

sessionLockStats :: SessionLockManager -> IO SessionLockStats
sessionLockStats mgr = atomically $ do
  locks <- readTVar (slmLocks mgr)
  let tracked = Map.size locks
      maxTracked = slmMaxTrackedLocks mgr
  pure
    SessionLockStats
      { slsTrackedLocks = tracked
      , slsMaxTrackedLocks = maxTracked
      , slsOverflowActive = tracked >= maxTracked
      }

getOrCreateLock :: SessionLockManager -> Text -> IO (MVar ())
getOrCreateLock mgr sessionId = do
  stamp <- nextAccessStamp mgr
  mExisting <- atomically $ do
    locks <- readTVar (slmLocks mgr)
    case Map.lookup sessionId locks of
      Just entry -> do
        modifyTVar' (slmLocks mgr) (Map.adjust (\entry' -> entry' { sleLastUsed = stamp }) sessionId)
        pure (Just (sleLock entry))
      Nothing -> pure Nothing
  case mExisting of
    Just lock -> pure lock
    Nothing -> do
      newLock <- newMVar ()
      result <- atomically $ do
        locks <- readTVar (slmLocks mgr)
        case Map.lookup sessionId locks of
          Just existing -> pure (Just (sleLock existing))
          Nothing ->
            if Map.size locks >= slmMaxTrackedLocks mgr
              then pure Nothing
              else do
                modifyTVar' (slmLocks mgr) (Map.insert sessionId (SessionLockEntry newLock stamp))
                pure (Just newLock)
      case result of
        Just lock -> pure lock
        Nothing -> do
          evicted <- evictFreeTrackedLock mgr sessionId newLock stamp
          case evicted of
            Just lock -> pure lock
            Nothing -> do
              hPutStrLn stderr $ "session_lock_overflow: session=" <> T.unpack sessionId <> " tracked=" <> show (slmMaxTrackedLocks mgr) <> " cap=" <> show (slmMaxTrackedLocks mgr)
              pure (pickOverflowShard mgr sessionId)

nextAccessStamp :: SessionLockManager -> IO Int
nextAccessStamp mgr = atomically $ do
  current <- readTVar (slmAccessCounter mgr)
  let next = current + 1
  modifyTVar' (slmAccessCounter mgr) (const next)
  pure next

evictFreeTrackedLock :: SessionLockManager -> Text -> MVar () -> Int -> IO (Maybe (MVar ()))
evictFreeTrackedLock mgr sessionId newLock stamp = do
  snapshot <- atomically $ readTVar (slmLocks mgr)
  let candidates = reverse (sortOn (sleLastUsed . snd) (Map.toList snapshot))
  tryCandidates candidates
  where
    tryCandidates [] = pure Nothing
    tryCandidates ((victimId, victimEntry) : rest) = do
      free <- tryReadMVar (sleLock victimEntry)
      case free of
        Nothing -> tryCandidates rest
        Just _ -> do
          result <- atomically $ do
            locks <- readTVar (slmLocks mgr)
            case (Map.lookup sessionId locks, Map.lookup victimId locks) of
              (Just existing, _) -> pure (Just (sleLock existing))
              (Nothing, Just currentVictim)
                | sleLastUsed currentVictim == sleLastUsed victimEntry && Map.size locks >= slmMaxTrackedLocks mgr -> do
                    modifyTVar' (slmLocks mgr) (Map.insert sessionId (SessionLockEntry newLock stamp) . Map.delete victimId)
                    pure (Just newLock)
              _ -> pure Nothing
          case result of
            Just lock -> pure (Just lock)
            Nothing -> tryCandidates rest

pickOverflowShard :: SessionLockManager -> Text -> MVar ()
pickOverflowShard mgr sessionId =
  let shards = slmOverflowShards mgr
      idx = sessionLockOverflowShardIndex sessionId `mod` max 1 (length shards)
  in shards !! idx

sessionLockOverflowShardCount :: Int
sessionLockOverflowShardCount = 8

sessionLockOverflowShardIndex :: Text -> Int
sessionLockOverflowShardIndex = T.foldl' step 5381
  where
    step acc ch = acc * 33 + fromEnum ch
