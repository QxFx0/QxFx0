{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module CLI.Http
  ( handleServeHttp
  ) where

import Control.Exception (IOException, catch)
import Control.Monad (unless)
import Data.Char (toLower)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getExecutablePath, lookupEnv)
import System.IO (hPutStrLn, stderr)
import System.Posix.Process (executeFile)
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

-- | Parse the CLI arguments that follow --serve-http. We support both the
-- positional-port form (`--serve-http 9170`) and option form (`--serve-http
-- --port 9170 --host 127.0.0.1 ...`). All options not consumed here are passed
-- through to the Python sidecar script.
partitionServeArgs :: [String] -> (Maybe String, Maybe String, Maybe String, Maybe String, [String])
partitionServeArgs = go (Nothing, Nothing, Nothing, Nothing, [])
  where
    go :: (Maybe String, Maybe String, Maybe String, Maybe String, [String]) -> [String] -> (Maybe String, Maybe String, Maybe String, Maybe String, [String])
    go acc [] = acc
    go (h, p, b, d, o) (x:y:rest)
      | x == "--host" = go (Just y, p, b, d, o) rest
      | x == "--port" = go (h, Just y, b, d, o) rest
      | x == "--bin" = go (h, p, Just y, d, o) rest
      | x == "--default-session-id" = go (h, p, b, Just y, o) rest
    go (h, p, b, d, o) (x:rest) = go (h, p, b, d, o ++ [x]) rest

handleServeHttp :: Text -> [String] -> IO ()
handleServeHttp sessionId portArgs0 = do
  let (mHostOverride, mPortOverrideStr, mBinOverride, mDefaultSessionOverride, otherArgs) =
        partitionServeArgs portArgs0
      mPositionalPort = listToMaybe otherArgs >>= readMaybe
      mPortOverride = (mPortOverrideStr >>= readMaybe) <|> mPositionalPort
      scriptExtraArgs = case otherArgs of
        (p:rest) | Just (_ :: Int) <- readMaybe p -> rest
        _ -> otherArgs
  config <- resolveHttpServerConfig sessionId mPortOverride mHostOverride
  let args =
        [ "--host", hscHost config
        , "--port", show (hscPort config)
        , "--bin", fromMaybe (hscBinaryPath config) mBinOverride
        , "--default-session-id", fromMaybe (T.unpack (hscDefaultSessionId config)) mDefaultSessionOverride
        ] ++ scriptExtraArgs
  executeFile "python3" True (hscScriptPath config : args) Nothing
    `catch` \(exc :: IOException) ->
      throwRuntimeInit ("HTTP sidecar launcher failed: " <> show exc)

resolveHttpServerConfig :: Text -> Maybe Int -> Maybe String -> IO HttpServerConfig
resolveHttpServerConfig sessionId mPortOverride mHostOverride = do
  mHost <- lookupEnv "QXFX0_HTTP_HOST"
  mPortEnv <- lookupEnv "QXFX0_HTTP_PORT"
  scriptPath <- resolveHttpRuntimeScriptPath
  binaryPath <- getExecutablePath
  let host = fromMaybe "127.0.0.1" (mHostOverride <|> mHost)
      portFromEnv = mPortEnv >>= readMaybe
      port = fromMaybe (fromMaybe 8080 portFromEnv) mPortOverride
  unless (isLoopbackHost host) $ do
    mAllow <- lookupEnv "QXFX0_ALLOW_NON_LOOPBACK_HTTP"
    case mAllow of
      Just "1" -> pure ()
      _ -> throwRuntimeInit ("HTTP sidecar non-loopback bind (" <> host <> ") requires QXFX0_ALLOW_NON_LOOPBACK_HTTP=1; event=non_loopback_bind_requires_opt_in")
  pure HttpServerConfig
    { hscHost = host
    , hscPort = port
    , hscDefaultSessionId = sessionId
    , hscScriptPath = scriptPath
    , hscBinaryPath = binaryPath
    }

throwRuntimeInit :: String -> IO a
throwRuntimeInit msg = do
  hPutStrLn stderr msg
  throwQxFx0 (RuntimeInitError (T.pack msg))

isLoopbackHost :: String -> Bool
isLoopbackHost host =
  let h = map toLower host
  in h == "127.0.0.1"
     || h == "localhost"
     || h == "::1"

(<|>) :: Maybe a -> Maybe a -> Maybe a
Just a <|> _ = Just a
Nothing <|> b = b
infixr 5 <|>
