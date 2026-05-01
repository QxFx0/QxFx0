{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-| Per-session critical section registry for serializing concurrent turn execution. -}
module QxFx0.Core.SessionLock
  ( SessionLockManager
  , SessionLockStats(..)
  , newSessionLockManager
  , withSessionLock
  , sessionLockStats
  ) where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVar, modifyTVar')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

data SessionLockManager = SessionLockManager
  { slmLocks :: !(TVar (Map Text (MVar ())))
  , slmOverflowLock :: !(MVar ())
  , slmMaxTrackedLocks :: !Int
  }

data SessionLockStats = SessionLockStats
  { slsTrackedLocks :: !Int
  , slsMaxTrackedLocks :: !Int
  , slsOverflowActive :: !Bool
  } deriving stock (Eq, Show)

newSessionLockManager :: IO SessionLockManager
newSessionLockManager = do
  locks <- newTVarIO Map.empty
  overflowLock <- newMVar ()
  cap <- resolveMaxTrackedLocks
  pure SessionLockManager
    { slmLocks = locks
    , slmOverflowLock = overflowLock
    , slmMaxTrackedLocks = cap
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
  mExisting <- atomically $ do
    locks <- readTVar (slmLocks mgr)
    pure $ Map.lookup sessionId locks
  case mExisting of
    Just lock -> pure lock
    Nothing -> do
      newLock <- newMVar ()
      result <- atomically $ do
        locks <- readTVar (slmLocks mgr)
        case Map.lookup sessionId locks of
          Just existing -> pure (Right existing)
          Nothing ->
            if Map.size locks >= slmMaxTrackedLocks mgr
              then pure (Left (Map.size locks))
              else do
                modifyTVar' (slmLocks mgr) (Map.insert sessionId newLock)
                pure (Right newLock)
      case result of
        Right lock -> pure lock
        Left tracked -> do
          hPutStrLn stderr $ "session_lock_overflow: session=" <> T.unpack sessionId <> " tracked=" <> show tracked <> " cap=" <> show (slmMaxTrackedLocks mgr)
          pure (slmOverflowLock mgr)
