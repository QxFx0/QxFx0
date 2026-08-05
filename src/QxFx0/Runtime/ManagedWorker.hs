module QxFx0.Runtime.ManagedWorker
  ( ManagedWorker
  , spawnManagedWorker
  , stopManagedWorker
  , waitManagedWorker
  ) where

import Control.Concurrent
  ( MVar
  , ThreadId
  , forkIO
  , forkIOWithUnmask
  , modifyMVar
  , newEmptyMVar
  , newMVar
  , readMVar
  , throwTo
  , tryPutMVar
  )
import Control.Exception (AsyncException(ThreadKilled), finally, mask, mask_)
import Control.Monad (void, when)

-- | A background thread with an observable termination point. Cancellation is
-- sent at most once, while every caller waits for the thread's finalizers.
data ManagedWorker = ManagedWorker
  { mwThreadId :: !ThreadId
  , mwDone :: !(MVar ())
  , mwStopSent :: !(MVar Bool)
  }

spawnManagedWorker :: IO () -> IO ManagedWorker
spawnManagedWorker action = mask_ $ do
  done <- newEmptyMVar
  stopSent <- newMVar False
  threadId <- forkIOWithUnmask $ \restore ->
    restore action `finally` void (tryPutMVar done ())
  pure ManagedWorker
    { mwThreadId = threadId
    , mwDone = done
    , mwStopSent = stopSent
    }

-- | Idempotently request cancellation and join the worker. If the worker is in
-- a masked durable transition, the signaler waits independently while the
-- caller joins the worker's observable finalizer. This avoids a shutdown
-- deadlock when the caller must remain free to let that transition finish.
stopManagedWorker :: ManagedWorker -> IO ()
stopManagedWorker worker = mask $ \_ -> do
  shouldSignal <- modifyMVar (mwStopSent worker) $ \sent ->
    pure (True, not sent)
  when shouldSignal $ void $ forkIO (throwTo (mwThreadId worker) ThreadKilled)
  readMVar (mwDone worker)

waitManagedWorker :: ManagedWorker -> IO ()
waitManagedWorker = readMVar . mwDone
