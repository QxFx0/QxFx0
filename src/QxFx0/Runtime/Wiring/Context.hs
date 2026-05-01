{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StrictData #-}
{-# OPTIONS_GHC -Wno-deprecations #-}

{-| Runtime context assembly and cache/session primitives shared by wiring submodules. -}
module QxFx0.Runtime.Wiring.Context
  ( RuntimeCaches(..)
  , RuntimeWorkers(..)
  , RuntimeLocks(..)
  , RuntimeTurnState(..)
  , TurnRuntime(..)
  , RuntimeContext(..)
  , TimeSource
  , initRuntimeContext
  , releaseRuntimeContext
  , withRuntimeSession
  , readApiHealth
  , readEmbeddingHealth
  , withRuntimeDb
  , readConsciousLoop
  , readIntuition
  , modifyConsciousLoop
  , modifyIntuition
  , commitRuntimeTurnState
  , hydrateRuntimeTurnState
  , updateHistoryStrict
  , resolveNixPath
  , resolveSouffleExecutableCached
  ) where

import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Exception (finally, mask, onException)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (Text)
import qualified Data.Sequence as Seq
import qualified Data.Char as Char
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)

import qualified Data.Time.Clock as Clock
import Data.Time.Calendar (Day(ModifiedJulianDay))

import QxFx0.Bridge.AgdaWitness (AgdaWitnessReport)
import qualified QxFx0.Bridge.Datalog as Datalog
import QxFx0.Bridge.NixCache (NixCache, newNixCache)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.SQLite (WorkerDBPool, closeDBPool, newDBPool, withPooledDB)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop(..), ResponseObservation, initialLoop, updateAfterResponse)
import QxFx0.Core.Intuition (IntuitiveState, defaultIntuitiveState)
import QxFx0.Core.SessionLock (SessionLockManager, newSessionLockManager, withSessionLock)
import QxFx0.Resources (getNixGuardPath)
import QxFx0.Runtime.Mode (RuntimeMode, resolveRuntimeMode)
import QxFx0.Semantic.Embedding (APIHealthCache, EmbeddingHealth, checkApiHealth, checkEmbeddingHealth)
import QxFx0.Types (SystemState, ssIntuitionState, ssTurnCount)
import Network.HTTP.Client (Manager, closeManager, defaultManagerSettings, newManager)

data RuntimeCaches = RuntimeCaches
  { rtcHealth :: !APIHealthCache
  , rtcNix    :: !NixCache
  }

data RuntimeWorkers = RuntimeWorkers
  { rtwDbPool :: !WorkerDBPool
  , rtwHttpManager :: !Manager
  }

data RuntimeLocks = RuntimeLocks
  { rtlSession :: !SessionLockManager
  }

data RuntimeTurnState = RuntimeTurnState
  { rtsConsciousLoop :: !ConsciousnessLoop
  , rtsIntuition     :: !IntuitiveState
  }

data TurnRuntime = TurnRuntime
  { rtrState         :: !(MVar RuntimeTurnState)
  , rtrAgdaWitness   :: !(MVar (Maybe AgdaWitnessReport))
  , rtrNixPath       :: !(MVar (Maybe FilePath))
  , rtrSoufflePath   :: !(MVar (Maybe (Either Text FilePath)))
  }

type TimeSource = IO Clock.UTCTime

data RuntimeContext = RuntimeContext
  { rcDbPath     :: !FilePath
  , rcMode       :: !RuntimeMode
  , rcCaches     :: !RuntimeCaches
  , rcWorkers    :: !RuntimeWorkers
  , rcLocks      :: !RuntimeLocks
  , rcTurn       :: !TurnRuntime
  , rcTimeSource :: !TimeSource
  }

initRuntimeContext :: FilePath -> IO RuntimeContext
initRuntimeContext path = mask $ \restore -> do
  runtimeMode <- resolveRuntimeMode
  healthCache <- newMVar Nothing
  nixCache <- newNixCache 300 1000
  dbPool <- newDBPool path 2
  httpManager <- newManager defaultManagerSettings
  timeSource <- resolveTimeSource
  restore (buildRuntimeContext path runtimeMode healthCache nixCache dbPool httpManager timeSource)
    `onException` (closeManager httpManager `finally` closeDBPool dbPool)

resolveTimeSource :: IO TimeSource
resolveTimeSource = do
  mFixed <- lookupEnv "QXFX0_TEST_FIXED_TIME"
  case mFixed of
    Nothing -> pure Clock.getCurrentTime
    Just epochStr ->
      case (reads epochStr :: [(Integer, String)]) of
        [(epochSeconds, "")] -> do
          ref <- newIORef epochSeconds
          pure $ do
            current <- readIORef ref
            writeIORef ref (current + 1)
            pure (Clock.addUTCTime (realToFrac current) (Clock.UTCTime (ModifiedJulianDay 0) 0))
        _ -> pure Clock.getCurrentTime

releaseRuntimeContext :: RuntimeContext -> IO ()
releaseRuntimeContext ctx =
  closeManager (rtwHttpManager (rcWorkers ctx))
    `finally` closeDBPool (rtwDbPool (rcWorkers ctx))

buildRuntimeContext
  :: FilePath
  -> RuntimeMode
  -> APIHealthCache
  -> NixCache
  -> WorkerDBPool
  -> Manager
  -> TimeSource
  -> IO RuntimeContext
buildRuntimeContext path runtimeMode healthCache nixCache dbPool httpManager timeSource = do
  sessionLock <- newSessionLockManager
  runtimeTurnState <- newMVar RuntimeTurnState
    { rtsConsciousLoop = initialLoop
    , rtsIntuition = defaultIntuitiveState
    }
  agdaWitness <- newMVar Nothing
  nixPathVar <- newMVar Nothing
  soufflePathVar <- newMVar Nothing
  pure RuntimeContext
    { rcDbPath = path
    , rcMode = runtimeMode
    , rcCaches = RuntimeCaches
        { rtcHealth = healthCache
        , rtcNix = nixCache
        }
    , rcWorkers = RuntimeWorkers
        { rtwDbPool = dbPool
        , rtwHttpManager = httpManager
        }
    , rcLocks = RuntimeLocks
        { rtlSession = sessionLock
        }
    , rcTurn = TurnRuntime
        { rtrState = runtimeTurnState
        , rtrAgdaWitness = agdaWitness
        , rtrNixPath = nixPathVar
        , rtrSoufflePath = soufflePathVar
        }
    , rcTimeSource = timeSource
    }

withRuntimeSession :: RuntimeContext -> Text -> IO a -> IO a
withRuntimeSession ctx sessionId action = do
  lockEnabled <- readSessionLockFlag
  if lockEnabled
    then withSessionLock (rtlSession (rcLocks ctx)) sessionId action
    else action

readApiHealth :: RuntimeContext -> IO Bool
readApiHealth ctx = checkApiHealth (rtcHealth (rcCaches ctx))

readEmbeddingHealth :: RuntimeContext -> IO EmbeddingHealth
readEmbeddingHealth ctx = checkEmbeddingHealth (rtcHealth (rcCaches ctx))

withRuntimeDb :: RuntimeContext -> (NSQL.Database -> IO a) -> IO a
withRuntimeDb ctx = withPooledDB (rtwDbPool (rcWorkers ctx))

readConsciousLoop :: RuntimeContext -> IO ConsciousnessLoop
readConsciousLoop ctx = rtsConsciousLoop <$> readMVar (rtrState (rcTurn ctx))

readIntuition :: RuntimeContext -> IO IntuitiveState
readIntuition ctx = rtsIntuition <$> readMVar (rtrState (rcTurn ctx))

modifyConsciousLoop :: RuntimeContext -> (ConsciousnessLoop -> IO (ConsciousnessLoop, a)) -> IO a
modifyConsciousLoop ctx f =
  modifyMVar (rtrState (rcTurn ctx)) $ \turnState -> do
    (nextLoop, result) <- f (rtsConsciousLoop turnState)
    pure (turnState { rtsConsciousLoop = nextLoop }, result)

modifyIntuition :: RuntimeContext -> (IntuitiveState -> IO (IntuitiveState, a)) -> IO a
modifyIntuition ctx f =
  modifyMVar (rtrState (rcTurn ctx)) $ \turnState -> do
    (nextIntuition, result) <- f (rtsIntuition turnState)
    pure (turnState { rtsIntuition = nextIntuition }, result)

commitRuntimeTurnState :: RuntimeContext -> ConsciousnessLoop -> IntuitiveState -> ResponseObservation -> IO ()
commitRuntimeTurnState ctx previewLoop previewIntuition observation =
  modifyMVar_ (rtrState (rcTurn ctx)) $ \turnState ->
    pure
      turnState
        { rtsIntuition = previewIntuition
        , rtsConsciousLoop = updateAfterResponse previewLoop observation
        }

hydrateRuntimeTurnState :: RuntimeContext -> SystemState -> IO ()
hydrateRuntimeTurnState ctx ss =
  -- Consciousness loop itself is ephemeral; on restore we re-seed it with persisted turn continuity.
  modifyMVar_ (rtrState (rcTurn ctx)) $ \turnState ->
    pure
      turnState
        { rtsConsciousLoop = initialLoop { clDialogueTurn = ssTurnCount ss }
        , rtsIntuition = maybe defaultIntuitiveState id (ssIntuitionState ss)
        }

updateHistoryStrict :: Text -> Seq.Seq Text -> Seq.Seq Text
updateHistoryStrict !newEntry !history =
  let !updated = newEntry Seq.<| history
      !bounded = Seq.take 50 updated
  in bounded

resolveNixPath :: RuntimeContext -> IO (Maybe FilePath)
resolveNixPath ctx = do
  mStored <- readMVar (rtrNixPath (rcTurn ctx))
  case mStored of
    Just p -> pure (Just p)
    Nothing -> do
      raw <- getNixGuardPath
      exists <- doesFileExist raw
      let result = if exists then Just raw else Nothing
      modifyMVar_ (rtrNixPath (rcTurn ctx)) $ \_ -> pure result
      pure result

resolveSouffleExecutableCached :: RuntimeContext -> IO (Either Text FilePath)
resolveSouffleExecutableCached ctx = do
  cached <- readMVar (rtrSoufflePath (rcTurn ctx))
  case cached of
    Just result -> pure result
    Nothing -> do
      result <- Datalog.resolveSouffleExecutable
      modifyMVar_ (rtrSoufflePath (rcTurn ctx)) $ \_ -> pure (Just result)
      pure result

readSessionLockFlag :: IO Bool
readSessionLockFlag = do
  mVal <- lookupEnv "QXFX0_SESSION_LOCK"
  pure $ case mVal of
    Nothing -> True
    Just raw ->
      case map Char.toLower raw of
        "off" -> False
        "0" -> False
        "on" -> True
        "1" -> True
        _ -> True
