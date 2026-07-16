{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Learning.CircuitBreaker
  ( PendingBreakerCloseQueue
  , newPendingBreakerCloseQueue
  , enqueueBreakerSideQueue
  , dequeueBreakerCloseQueue
  , drainPendingBreakerQueue
  , spawnBreakerWatcher
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM (TQueue, TVar, atomically, modifyTVar', newTQueue, newTVar, readTVar, tryReadTQueue, writeTQueue)
import Control.Monad (forever, void, when)
import Data.IORef (IORef, readIORef)
import Data.Time.Clock (getCurrentTime)

import QxFx0.Learning.Autonomous
  ( CircuitBreakerState
  , LearningQueue
  , LearningTask
  , enqueueLearningTask
  , isCircuitOpen
  )

data PendingBreakerCloseQueue = PendingBreakerCloseQueue
  { pbqTQueue :: !(TQueue LearningTask)
  , pbqSize   :: !(TVar Int)
  , pbqCap    :: !Int
  }

newPendingBreakerCloseQueue :: Int -> IO PendingBreakerCloseQueue
newPendingBreakerCloseQueue cap = atomically $ do
  q <- newTQueue
  sz <- newTVar 0
  pure PendingBreakerCloseQueue { pbqTQueue = q, pbqSize = sz, pbqCap = max 0 cap }

enqueueBreakerSideQueue :: PendingBreakerCloseQueue -> LearningTask -> IO Bool
enqueueBreakerSideQueue q task = atomically $ do
  sz <- readTVar (pbqSize q)
  if sz >= pbqCap q
    then pure False
    else do
      writeTQueue (pbqTQueue q) task
      modifyTVar' (pbqSize q) (+ 1)
      pure True

dequeueBreakerCloseQueue :: PendingBreakerCloseQueue -> IO (Maybe LearningTask)
dequeueBreakerCloseQueue q = atomically $ do
  mt <- tryReadTQueue (pbqTQueue q)
  case mt of
    Just _ -> modifyTVar' (pbqSize q) (max 0 . subtract 1) >> pure mt
    Nothing -> pure Nothing

drainPendingBreakerQueue :: PendingBreakerCloseQueue -> LearningQueue -> IO Int
drainPendingBreakerQueue sq mainQ = loop 0
  where
    loop n = do
      mt <- dequeueBreakerCloseQueue sq
      case mt of
        Nothing -> pure n
        Just task -> do
          ok <- enqueueLearningTask mainQ task
          if ok
            then loop (n + 1)
            else do
              _ <- enqueueBreakerSideQueue sq task
              pure n

spawnBreakerWatcher :: IORef CircuitBreakerState -> PendingBreakerCloseQueue -> LearningQueue -> IO ()
spawnBreakerWatcher cbRef sq mainQ = void . forkIO . forever $ do
  threadDelay (30 * 1000 * 1000)
  cb <- readIORef cbRef
  now <- getCurrentTime
  when (not (isCircuitOpen cb now)) $
    void (drainPendingBreakerQueue sq mainQ)
-- dummy comment
