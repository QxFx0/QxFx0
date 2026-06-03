{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module CLI.Http
  ( handleServeHttp
  ) where

import Control.Exception (IOException, catch)
import Control.Monad (unless)
import Data.Char (toLower)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getExecutablePath, lookupEnv)
import System.Process (callProcess)
import Text.Read (readMaybe)

import QxFx0.ExceptionPolicy
  ( QxFx0Exception(RuntimeInitError)
  , throwQxFx0
  )
import QxFx0.Resources (resolveHttpRuntimeScriptPath)

data HttpServerConfig = HttpServerConfig
  { hscHost :: !String
  , hscPort :: !Int
  , hscDefaultSessionId :: !Text
  , hscScriptPath :: !FilePath
  , hscBinaryPath :: !FilePath
  }

handleServeHttp :: Text -> [String] -> IO ()
handleServeHttp sessionId portArgs = do
  let mPortOverride = case portArgs of
        (p:_) -> readMaybe p :: Maybe Int
        _ -> Nothing
  config <- resolveHttpServerConfig sessionId mPortOverride
  let args =
        [ hscScriptPath config
        , "--host", hscHost config
        , "--port", show (hscPort config)
        , "--bin", hscBinaryPath config
        , "--default-session-id", T.unpack (hscDefaultSessionId config)
        ]
  callProcess "python3" args
    `catch` \(exc :: IOException) ->
      throwRuntimeInit ("HTTP sidecar launcher failed: " <> show exc)

resolveHttpServerConfig :: Text -> Maybe Int -> IO HttpServerConfig
resolveHttpServerConfig sessionId mPortOverride = do
  mHost <- lookupEnv "QXFX0_HTTP_HOST"
  mPortEnv <- lookupEnv "QXFX0_HTTP_PORT"
  scriptPath <- resolveHttpRuntimeScriptPath
  binaryPath <- getExecutablePath
  let host = fromMaybe "127.0.0.1" mHost
      portFromEnv = mPortEnv >>= readMaybe
      port = fromMaybe (fromMaybe 8080 portFromEnv) mPortOverride
  unless (isLoopbackHost host) $ do
    mAllow <- lookupEnv "QXFX0_ALLOW_NON_LOOPBACK_HTTP"
    case mAllow of
      Just "1" -> pure ()
      _ -> throwRuntimeInit ("HTTP sidecar non-loopback bind (" <> host <> ") requires QXFX0_ALLOW_NON_LOOPBACK_HTTP=1; use reverse proxy for TLS")
  pure HttpServerConfig
    { hscHost = host
    , hscPort = port
    , hscDefaultSessionId = sessionId
    , hscScriptPath = scriptPath
    , hscBinaryPath = binaryPath
    }

throwRuntimeInit :: String -> IO a
throwRuntimeInit = throwQxFx0 . RuntimeInitError . T.pack

isLoopbackHost :: String -> Bool
isLoopbackHost host =
  let h = map toLower host
  in h == "127.0.0.1"
     || h == "localhost"
     || h == "::1"
