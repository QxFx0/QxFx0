{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module CLI.Worker
  ( runWorkerStdio
  ) where

import CLI.Protocol (WorkerCommand(..), decodeWorkerCommand, healthJsonPairs, stateJsonPairs)
import CLI.Turn (attachRuntimeDiagnostics, runTurnJsonInSession)
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(RuntimeInitError)
  , catchIO
  , throwQxFx0
  , tryAsync
  )

import Control.Exception (AsyncException(ThreadKilled), fromException, throwIO)
import Control.Monad (unless, when)
import Data.Aeson (ToJSON, Value, encode, object, (.=))
import Data.Char (isAlphaNum)
import Data.List (isPrefixOf)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Render.Text (textShow)
import qualified Data.Text.IO as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , doesDirectoryExist
  )
import System.Environment (lookupEnv)
import System.FilePath ((</>), isAbsolute, normalise, splitDirectories, takeDirectory, takeFileName)
import System.IO (BufferMode(..), hClose, hGetLine, hIsEOF, hPutStr, hSetBuffering, stdin, stdout)
import System.Posix.Files (ownerReadMode, ownerWriteMode, unionFileModes)
import System.Posix.IO (OpenFileFlags(creat, exclusive, nofollow), OpenMode(WriteOnly), defaultFileFlags, fdToHandle, openFd)
import System.Posix.Types (FileMode)

import qualified QxFx0.Runtime as Runtime

import qualified Data.ByteString.Lazy as BL

data LiveWorkerState = LiveWorkerState
  { lwsSession :: !Runtime.Session
  , lwsRuntimeEpoch :: !Text
  , lwsRuntimeTurnIndex :: !Int
  , lwsCrashAfterAcceptOnceFile :: !(Maybe FilePath)
  , lwsTurnErrorAfterAcceptOnceFile :: !(Maybe FilePath)
  }

workerModeTag :: Text
workerModeTag = "persistent_stdio"

runWorkerStdio :: Text -> IO ()
runWorkerStdio sessionId = do
  hSetBuffering stdout LineBuffering
  Runtime.withBootstrappedSession True sessionId $ \session0 -> do
    runtimeEpoch <- mkRuntimeEpoch sessionId
    crashAfterAcceptOnceFile <- resolveCrashAfterAcceptHook
    turnErrorAfterAcceptOnceFile <- resolveTurnErrorAfterAcceptHook
    loop LiveWorkerState
      { lwsSession = session0
      , lwsRuntimeEpoch = runtimeEpoch
      , lwsRuntimeTurnIndex = 0
      , lwsCrashAfterAcceptOnceFile = crashAfterAcceptOnceFile
      , lwsTurnErrorAfterAcceptOnceFile = turnErrorAfterAcceptOnceFile
      }
  where
    loop :: LiveWorkerState -> IO ()
    loop state = do
      isEof <- hIsEOF stdin
      unless isEof $ do
        line <- T.pack <$> hGetLine stdin
        case decodeWorkerCommand line of
          Left err -> do
            T.putStrLn (workerError err)
            loop state
          Right cmd -> do
            result <- tryAsync (handleWorkerCommand state cmd)
            case result of
              Right (nextState, shouldStop) ->
                unless shouldStop (loop nextState)
              Left err
                | isTurnCommand cmd ->
                    case fromException err of
                      Just ThreadKilled -> throwIO ThreadKilled
                      _ -> do
                        T.putStrLn (workerErrorWithCode "worker_turn_exception" (textShow err))
                        pure ()
                | otherwise -> do
                    T.putStrLn (workerError (textShow err))
                    loop state

isTurnCommand :: WorkerCommand -> Bool
isTurnCommand WorkerTurn{} = True
isTurnCommand _ = False

handleWorkerCommand :: LiveWorkerState -> WorkerCommand -> IO (LiveWorkerState, Bool)
handleWorkerCommand state@LiveWorkerState{..} = \case
  WorkerShutdown -> do
    T.putStrLn (workerStatus lwsRuntimeEpoch lwsRuntimeTurnIndex "ok" "shutdown")
    pure (state, True)
  WorkerPing -> do
    T.putStrLn (workerStatus lwsRuntimeEpoch lwsRuntimeTurnIndex "ok" "pong")
    pure (state, False)
  WorkerHealth sid
    | sid /= Runtime.sessSessionId lwsSession -> do
        T.putStrLn (workerError ("worker/session mismatch: " <> sid))
        pure (state, False)
    | otherwise -> do
        health <- Runtime.checkHealth (Runtime.sessRuntime lwsSession)
        T.putStrLn (encodeAsText (healthResponse lwsSession lwsRuntimeEpoch lwsRuntimeTurnIndex health))
        pure (state, False)
  WorkerState sid
    | sid /= Runtime.sessSessionId lwsSession -> do
        T.putStrLn (workerError ("worker/session mismatch: " <> sid))
        pure (state, False)
    | otherwise -> do
        T.putStrLn (encodeAsText (stateResponse lwsSession lwsRuntimeEpoch lwsRuntimeTurnIndex))
        pure (state, False)
  WorkerTurn sid outputMode inputTxt
    | sid /= Runtime.sessSessionId lwsSession -> do
        T.putStrLn (workerError ("worker/session mismatch: " <> sid))
        pure (state, False)
    | otherwise -> do
        shouldCrashAfterAccept <- consumeCrashAfterAcceptHook lwsCrashAfterAcceptOnceFile
        when shouldCrashAfterAccept (throwIO ThreadKilled)
        shouldThrowTurnError <- consumeTurnErrorAfterAcceptHook lwsTurnErrorAfterAcceptOnceFile
        when shouldThrowTurnError (throwQxFx0 (RuntimeInitError "test_worker_turn_exception_after_accept"))
        (nextSession, turnResponse0) <- runTurnJsonInSession lwsSession outputMode inputTxt
        let nextTurnIndex = lwsRuntimeTurnIndex + 1
            turnResponse = attachRuntimeDiagnostics lwsRuntimeEpoch nextTurnIndex workerModeTag turnResponse0
        T.putStrLn (encodeAsText turnResponse)
        pure
          ( state
              { lwsSession = nextSession
              , lwsRuntimeTurnIndex = nextTurnIndex
              }
          , False
          )

resolveCrashAfterAcceptHook :: IO (Maybe FilePath)
resolveCrashAfterAcceptHook = do
  testMode <- lookupEnv "QXFX0_TEST_MODE"
  case testMode of
    Just _ -> do
      mMarkerPath <- lookupEnv "QXFX0_TEST_WORKER_CRASH_AFTER_ACCEPT_ONCE_FILE"
      case fmap T.strip (T.pack <$> mMarkerPath) of
        Just markerPath | not (T.null markerPath) -> resolveTrustedMarkerPath (T.unpack markerPath)
        _ -> pure Nothing
    Nothing -> pure Nothing

consumeCrashAfterAcceptHook :: Maybe FilePath -> IO Bool
consumeCrashAfterAcceptHook Nothing = pure False
consumeCrashAfterAcceptHook (Just markerPath) = markMarkerOnce markerPath

resolveTurnErrorAfterAcceptHook :: IO (Maybe FilePath)
resolveTurnErrorAfterAcceptHook = do
  testMode <- lookupEnv "QXFX0_TEST_MODE"
  case testMode of
    Just _ -> do
      mMarkerPath <- lookupEnv "QXFX0_TEST_WORKER_TURN_ERROR_AFTER_ACCEPT_ONCE_FILE"
      case fmap T.strip (T.pack <$> mMarkerPath) of
        Just markerPath | not (T.null markerPath) -> resolveTrustedMarkerPath (T.unpack markerPath)
        _ -> pure Nothing
    Nothing -> pure Nothing

consumeTurnErrorAfterAcceptHook :: Maybe FilePath -> IO Bool
consumeTurnErrorAfterAcceptHook Nothing = pure False
consumeTurnErrorAfterAcceptHook (Just markerPath) = markMarkerOnce markerPath

mkRuntimeEpoch :: Text -> IO Text
mkRuntimeEpoch sessionId = do
  micros <- floor . (* 1000000) <$> getPOSIXTime :: IO Integer
  pure ("rt-" <> sessionId <> "-" <> textShow micros)

stateResponse :: Runtime.Session -> Text -> Int -> Value
stateResponse session runtimeEpoch runtimeTurnIndex =
  object $
    stateJsonPairs session
    ++ [ "runtime_epoch" .= runtimeEpoch
       , "runtime_turn_index" .= runtimeTurnIndex
       , "worker_mode" .= workerModeTag
       ]

healthResponse :: Runtime.Session -> Text -> Int -> Runtime.SystemHealth -> Value
healthResponse session runtimeEpoch runtimeTurnIndex health =
  object $
    healthJsonPairs health (Runtime.sessSessionId session) (T.pack (Runtime.sessDbPath session))
    ++ [ "runtime_epoch" .= runtimeEpoch
       , "runtime_turn_index" .= runtimeTurnIndex
       , "worker_mode" .= workerModeTag
       ]

workerStatus :: Text -> Int -> Text -> Text -> Text
workerStatus runtimeEpoch runtimeTurnIndex status message =
  encodeAsText $
    object
      [ "status" .= status
      , "message" .= message
      , "runtime_epoch" .= runtimeEpoch
      , "runtime_turn_index" .= runtimeTurnIndex
      , "worker_mode" .= workerModeTag
      ]

workerError :: Text -> Text
workerError = workerErrorWithCode "worker_command_error"

workerErrorWithCode :: Text -> Text -> Text
workerErrorWithCode errCode message =
  encodeAsText $
    object
      [ "status" .= ("error" :: Text)
      , "error" .= errCode
      , "message" .= message
      ]

encodeAsText :: ToJSON a => a -> Text
encodeAsText = TE.decodeUtf8With lenientDecode . BL.toStrict . encode

resolveTrustedMarkerPath :: FilePath -> IO (Maybe FilePath)
resolveTrustedMarkerPath rawPath = do
  let normalized = normalise (dropWhile (== ' ') rawPath)
  stateDir <- resolveStateDir
  createDirectoryIfMissing True stateDir
  canonicalStateDir <- canonicalizePath stateDir
  canonicalTmp <- canonicalizePath "/tmp"
  if null normalized
    then pure Nothing
    else
      if isAbsolute normalized
        then resolveAbsoluteMarkerPath canonicalTmp canonicalStateDir normalized
        else
          pure $
            if isSafeRelativeMarker normalized
              then Just (canonicalStateDir </> "test-hooks" </> takeFileName normalized)
              else Nothing

resolveStateDir :: IO FilePath
resolveStateDir = do
  mStateDir <- lookupEnv "QXFX0_STATE_DIR"
  pure $ case fmap normalise mStateDir of
    Just path | not (null path) -> path
    _ -> "/tmp/qxfx0"

resolveAbsoluteMarkerPath :: FilePath -> FilePath -> FilePath -> IO (Maybe FilePath)
resolveAbsoluteMarkerPath canonicalTmp canonicalStateDir absoluteCandidate = do
  let parentDir = takeDirectory absoluteCandidate
      markerName = takeFileName absoluteCandidate
  parentExists <- doesDirectoryExist parentDir
  if not parentExists || not (isSafeRelativeMarker markerName)
    then pure Nothing
    else do
      canonicalParent <- canonicalizePath parentDir
      let canonicalCandidate = canonicalParent </> markerName
      pure $
        if isPathWithin canonicalTmp canonicalCandidate || isPathWithin canonicalStateDir canonicalCandidate
          then Just canonicalCandidate
          else Nothing

isPathWithin :: FilePath -> FilePath -> Bool
isPathWithin root candidate =
  let rootParts = splitDirectories (normalise root)
      pathParts = splitDirectories (normalise candidate)
  in rootParts `isPrefixOf` pathParts

isSafeRelativeMarker :: FilePath -> Bool
isSafeRelativeMarker relPath =
  relPath == takeFileName relPath
    && not (null relPath)
    && all isMarkerChar relPath

isMarkerChar :: Char -> Bool
isMarkerChar c = isAlphaNum c || c `elem` ("._-" :: String)

markMarkerOnce :: FilePath -> IO Bool
markMarkerOnce path = do
  createDirectoryIfMissing True (takeDirectory path)
  catchIO
    (do fd <- openFd path WriteOnly defaultFileFlags
          { exclusive = True
          , nofollow = True
          , creat = Just markerFileMode
          }
        handle <- fdToHandle fd
        hPutStr handle "triggered\n"
        hClose handle
        pure True)
    (\_ -> pure False)

markerFileMode :: FileMode
markerFileMode = ownerReadMode `unionFileModes` ownerWriteMode
