{-# LANGUAGE OverloadedStrings #-}

module CLI.Http
  ( handleServeHttp
  ) where

import Control.Monad (filterM, unless)
import Data.Char (toLower)
import Data.List (intercalate)
import qualified Data.List as L
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (getExecutablePath, lookupEnv)
import System.Directory (canonicalizePath, doesDirectoryExist, doesFileExist, getCurrentDirectory)
import System.FilePath ((</>), normalise, splitDirectories, takeDirectory, takeFileName)
import System.Process (callProcess)
import Text.Read (readMaybe)

import Paths_qxfx0 (getDataFileName)
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(RuntimeInitError)
  , throwQxFx0
  , tryIO
  , tryQxFx0
  )
import qualified QxFx0.Resources as Resources

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
  callProcess "python3"
    [ hscScriptPath config
    , "--host", hscHost config
    , "--port", show (hscPort config)
    , "--bin", hscBinaryPath config
    , "--default-session-id", T.unpack (hscDefaultSessionId config)
    ]

resolveHttpServerConfig :: Text -> Maybe Int -> IO HttpServerConfig
resolveHttpServerConfig sessionId mPortOverride = do
  mHost <- lookupEnv "QXFX0_HTTP_HOST"
  mPortEnv <- lookupEnv "QXFX0_HTTP_PORT"
  scriptPath <- resolveHttpRuntimeScript
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

resolveHttpRuntimeScript :: IO FilePath
resolveHttpRuntimeScript = do
  mExplicit <- lookupEnv "QXFX0_HTTP_RUNTIME"
  case mExplicit of
    Just path -> do
      let normalized = normalise path
      exists <- doesFileExist normalized
      if exists
        then validateExplicitScriptPath normalized
        else throwRuntimeInit ("QXFX0_HTTP_RUNTIME points to missing file: " ++ normalized)
    Nothing -> do
      exePath <- getExecutablePath
      dataFileResult <- tryIO (getDataFileName "scripts/http_runtime.py")
      resourcePathsResult <- tryQxFx0 Resources.resolveResourcePaths
      let candidates =
            [ eitherToMaybe (normalise <$> dataFileResult)
            , eitherToMaybe (normalise . (</> "scripts" </> "http_runtime.py") . Resources.rpResourceDir <$> resourcePathsResult)
            , Just (normalise (takeDirectory exePath </> "scripts" </> "http_runtime.py"))
            ]
      resolveExistingScript candidates

resolveExistingScript :: [Maybe FilePath] -> IO FilePath
resolveExistingScript candidates = do
  let materialized = [path | Just path <- candidates]
  pick materialized
  where
    pick [] =
      throwRuntimeInit
        ("Could not locate http_runtime.py; checked: " ++ intercalate ", " [path | Just path <- candidates]
          ++ ". Set QXFX0_HTTP_RUNTIME to an explicit script path.")
    pick (path:rest) = do
      exists <- doesFileExist path
      if exists then pure path else pick rest

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Left _) = Nothing
eitherToMaybe (Right value) = Just value

validateExplicitScriptPath :: FilePath -> IO FilePath
validateExplicitScriptPath path = do
  exePath <- getExecutablePath
  cwd <- getCurrentDirectory
  canonicalPath <- canonicalizePath path
  let scriptName = takeFileName canonicalPath
  if scriptName /= "http_runtime.py"
    then throwRuntimeInit ("QXFX0_HTTP_RUNTIME must point to http_runtime.py, got: " ++ canonicalPath)
    else do
      trustedRoots <- resolveTrustedScriptRoots exePath cwd
      if any (`isPathWithin` canonicalPath) trustedRoots
        then pure canonicalPath
        else
          throwRuntimeInit
            ("QXFX0_HTTP_RUNTIME points outside trusted roots: " ++ canonicalPath)

resolveTrustedScriptRoots :: FilePath -> FilePath -> IO [FilePath]
resolveTrustedScriptRoots exePath cwd = do
  let roots =
        [ takeDirectory exePath
        , takeDirectory exePath </> "scripts"
        , cwd </> "scripts"
        ]
  existing <- filterM doesDirectoryExist roots
  canonical <- mapM canonicalizePath existing
  pure (L.nub canonical)

isPathWithin :: FilePath -> FilePath -> Bool
isPathWithin root candidate =
  let rootParts = splitDirectories (normalise root)
      pathParts = splitDirectories (normalise candidate)
  in rootParts `L.isPrefixOf` pathParts

throwRuntimeInit :: String -> IO a
throwRuntimeInit = throwQxFx0 . RuntimeInitError . T.pack

isLoopbackHost :: String -> Bool
isLoopbackHost host =
  let h = map toLower host
  in h == "127.0.0.1"
     || h == "localhost"
     || h == "::1"
