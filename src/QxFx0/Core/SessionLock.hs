{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-| Per-session critical section registry for serializing concurrent turn execution. -}
module QxFx0.Core.SessionLock
  ( SessionLockManager
  , SessionLockStats(..)
  , newSessionLockManager
  , newSessionLockManagerWithCap
  , withSessionLock
  , withSessionLockPaused
  , sessionLockStats
  , sessionLockOverflowShardIndex
  , sessionLockOverflowShardCount
  ) where

import Control.Concurrent.MVar (MVar, newMVar, withMVar, tryReadMVar)
import Control.Concurrent.STM (STM, TVar, atomically, newTVarIO, readTVar, modifyTVar')
import Control.Exception (finally, mask)
import Control.Monad (replicateM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.List (sortOn)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

-- | A tracked session lock.  'slePins' counts acquisitions that have
-- passed the registry but not yet released: an entry with a positive
-- pin count must not be evicted, otherwise the evictor could remove
-- the lock between its issuance and its acquisition and a second call
-- for the same session would create a new, independent lock.
-- 'sleOverflow' marks a transient entry whose lock is a shared overflow
-- shard; the entry is removed when its last pin is released.
data SessionLockEntry = SessionLockEntry
  { sleLock :: !(MVar ())
  , sleLastUsed :: !Int
  , slePins :: !Int
  , sleOverflow :: !Bool
  }

data SessionLockManager = SessionLockManager
  { slmLocks :: !(TVar (Map Text SessionLockEntry))
  , slmOverflowShards :: ![MVar ()]
  , slmMaxTrackedLocks :: !Int
  , slmAccessCounter :: !(TVar Int)
  , slmEvictionCount :: !(TVar Int)
  }

data SessionLockStats = SessionLockStats
  { slsTrackedLocks :: !Int
    -- ^ Tracked entries, including active overflow entries (transient).
  , slsMaxTrackedLocks :: !Int
  , slsOverflowActive :: !Bool
  , slsPinnedLocks :: !Int
  , slsEvictions :: !Int
  } deriving stock (Eq, Show)

newSessionLockManager :: IO SessionLockManager
newSessionLockManager = resolveMaxTrackedLocks >>= newSessionLockManagerWithCap

-- | Constructor with an explicit cap (test seam): the production entry
-- point resolves the cap from the environment first.
newSessionLockManagerWithCap :: Int -> IO SessionLockManager
newSessionLockManagerWithCap cap = do
  locks <- newTVarIO Map.empty
  overflowShards <- replicateM sessionLockOverflowShardCount (newMVar ())
  accessCounter <- newTVarIO 0
  evictionCount <- newTVarIO 0
  pure SessionLockManager
    { slmLocks = locks
    , slmOverflowShards = overflowShards
    , slmMaxTrackedLocks = max 1 cap
    , slmAccessCounter = accessCounter
    , slmEvictionCount = evictionCount
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
withSessionLock mgr sessionId = withSessionLockPaused mgr sessionId (pure ())

-- | Test seam: runs the hook after the registry step (which pins the
-- entry) and before acquiring the MVar.  Production 'withSessionLock'
-- passes an empty hook; the hook exists so the eviction race can be
-- reproduced deterministically.
withSessionLockPaused :: SessionLockManager -> Text -> IO () -> IO a -> IO a
withSessionLockPaused mgr sessionId beforeAcquire action =
  mask $ \restore -> do
    (lock, mPinned) <- acquireSessionLock mgr sessionId
    let release = maybe (pure ()) (releaseSessionLock mgr) mPinned
    restore (beforeAcquire >> withMVar lock (\_ -> action)) `finally` release

sessionLockStats :: SessionLockManager -> IO SessionLockStats
sessionLockStats mgr = atomically $ do
  locks <- readTVar (slmLocks mgr)
  evictions <- readTVar (slmEvictionCount mgr)
  let tracked = Map.size locks
      maxTracked = slmMaxTrackedLocks mgr
  pure
    SessionLockStats
      { slsTrackedLocks = tracked
      , slsMaxTrackedLocks = maxTracked
      , slsOverflowActive = tracked >= maxTracked
      , slsPinnedLocks = sum (map slePins (Map.elems locks))
      , slsEvictions = evictions
      }

-- | Acquire the session lock and pin its tracked entry in one atomic
-- step.  The pin closes the eviction window between issuance and
-- acquisition (audit 2026-10-16 п.27): the evictor only removes
-- entries with no pins, so a lock that is about to be used cannot be
-- replaced by a fresh one.
acquireSessionLock :: SessionLockManager -> Text -> IO (MVar (), Maybe Text)
acquireSessionLock mgr sessionId = do
  stamp <- nextAccessStamp mgr
  mExisting <- atomically $ do
    locks <- readTVar (slmLocks mgr)
    case Map.lookup sessionId locks of
      Just entry -> do
        modifyTVar' (slmLocks mgr) (Map.adjust (pinEntry stamp) sessionId)
        pure (Just (sleLock entry))
      Nothing -> pure Nothing
  case mExisting of
    Just lock -> pure (lock, Just sessionId)
    Nothing -> do
      newLock <- newMVar ()
      inserted <- atomically (insertTracked mgr sessionId newLock stamp)
      case inserted of
        Just lock -> pure (lock, Just sessionId)
        Nothing -> do
          evicted <- evictFreeTrackedLock mgr sessionId newLock stamp
          case evicted of
            Just lock -> pure (lock, Just sessionId)
            Nothing -> do
              -- Room may have appeared between the failed insertion and
              -- the failed eviction (another evictor won the race).
              retried <- atomically (insertTracked mgr sessionId newLock stamp)
              case retried of
                Just lock -> pure (lock, Just sessionId)
                Nothing -> do
                  hPutStrLn stderr $ "session_lock_overflow: session=" <> T.unpack sessionId <> " cap=" <> show (slmMaxTrackedLocks mgr)
                  case pickOverflowShard mgr sessionId of
                    Just shard -> do
                      -- Register the overflow acquisition in the same registry:
                      -- otherwise a concurrent caller for this session can
                      -- insert a tracked entry (when room appears) and run in
                      -- parallel with the shard holder (audit п.27 addendum).
                      lock <- atomically (pinOrInsertOverflow mgr sessionId shard stamp)
                      pure (lock, Just sessionId)
                    -- Unreachable from 'newSessionLockManagerWithCap', but a
                    -- fresh per-session lock is the safe fallback (no sharing).
                    Nothing -> do
                      hPutStrLn stderr $ "session_lock_overflow_no_shards: session=" <> T.unpack sessionId
                      pure (newLock, Nothing)

pinEntry :: Int -> SessionLockEntry -> SessionLockEntry
pinEntry stamp entry =
  entry { sleLastUsed = stamp, slePins = slePins entry + 1 }

-- | Insert a new tracked entry with one pin, or pin an existing entry
-- if a concurrent caller registered the session first.
insertTracked :: SessionLockManager -> Text -> MVar () -> Int -> STM (Maybe (MVar ()))
insertTracked mgr sessionId newLock stamp = do
  locks <- readTVar (slmLocks mgr)
  case Map.lookup sessionId locks of
    Just entry -> do
      modifyTVar' (slmLocks mgr) (Map.adjust (pinEntry stamp) sessionId)
      pure (Just (sleLock entry))
    Nothing ->
      if Map.size locks >= slmMaxTrackedLocks mgr
        then pure Nothing
        else do
          modifyTVar' (slmLocks mgr)
            (Map.insert sessionId (SessionLockEntry newLock stamp 1 False))
          pure (Just newLock)

-- | Overflow acquisition: pin the session's existing entry if a
-- concurrent caller registered it, otherwise register the shard as this
-- session's lock (above the cap) and pin it.  The change and the session
-- check share one STM transaction, so a tracked insert and an overflow
-- insert for the same session cannot both succeed.
pinOrInsertOverflow :: SessionLockManager -> Text -> MVar () -> Int -> STM (MVar ())
pinOrInsertOverflow mgr sessionId shard stamp = do
  locks <- readTVar (slmLocks mgr)
  case Map.lookup sessionId locks of
    Just entry -> do
      modifyTVar' (slmLocks mgr) (Map.adjust (pinEntry stamp) sessionId)
      pure (sleLock entry)
    Nothing -> do
      modifyTVar' (slmLocks mgr)
        (Map.insert sessionId (SessionLockEntry shard stamp 1 True))
      pure shard

releaseSessionLock :: SessionLockManager -> Text -> IO ()
releaseSessionLock mgr sessionId = atomically $ do
  locks <- readTVar (slmLocks mgr)
  case Map.lookup sessionId locks of
    Just entry
      | sleOverflow entry && slePins entry <= 1 ->
          modifyTVar' (slmLocks mgr) (Map.delete sessionId)
      | otherwise ->
          modifyTVar' (slmLocks mgr)
            (Map.adjust (\current -> current { slePins = max 0 (slePins current - 1) }) sessionId)
    Nothing -> pure ()

nextAccessStamp :: SessionLockManager -> IO Int
nextAccessStamp mgr = atomically $ do
  current <- readTVar (slmAccessCounter mgr)
  let next = current + 1
  modifyTVar' (slmAccessCounter mgr) (const next)
  pure next

evictFreeTrackedLock :: SessionLockManager -> Text -> MVar () -> Int -> IO (Maybe (MVar ()))
evictFreeTrackedLock mgr sessionId newLock stamp = do
  snapshot <- atomically $ readTVar (slmLocks mgr)
  let candidates =
        sortOn (sleLastUsed . snd)
          [ entry | entry@(_, locked) <- Map.toList snapshot, slePins locked == 0 ]
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
              -- A concurrent caller registered this session first:
              -- pin its entry instead of handing out a second lock.
              (Just existing, _) -> do
                modifyTVar' (slmLocks mgr) (Map.adjust (pinEntry stamp) sessionId)
                pure (Just (sleLock existing))
              (Nothing, Just currentVictim)
                | slePins currentVictim == 0
                , sleLastUsed currentVictim == sleLastUsed victimEntry
                , Map.size locks >= slmMaxTrackedLocks mgr -> do
                    modifyTVar' (slmLocks mgr)
                      (Map.insert sessionId (SessionLockEntry newLock stamp 1 False) . Map.delete victimId)
                    modifyTVar' (slmEvictionCount mgr) (+ 1)
                    pure (Just newLock)
              _ -> pure Nothing
          case result of
            Just lock -> pure (Just lock)
            Nothing -> tryCandidates rest

pickOverflowShard :: SessionLockManager -> Text -> Maybe (MVar ())
pickOverflowShard mgr sessionId =
  case slmOverflowShards mgr of
    -- Total: the empty case is unreachable from 'newSessionLockManager'
    -- (fixed 64 shards) but must not throw if it ever happens.
    [] -> Nothing
    shards -> Just (shards !! (sessionLockOverflowShardIndex sessionId `mod` length shards))

sessionLockOverflowShardCount :: Int
sessionLockOverflowShardCount = 64

sessionLockOverflowShardIndex :: Text -> Int
sessionLockOverflowShardIndex = T.foldl' step 5381
  where
    step acc ch = acc * 33 + fromEnum ch
