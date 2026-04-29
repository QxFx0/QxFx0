{-# LANGUAGE OverloadedStrings #-}

module CLI.Health
  ( handleHealthcheck
  , handleRuntimeReady
  ) where

import Data.Aeson (encode, object)
import Data.Text (Text)
import qualified Data.Text as T

import qualified QxFx0.Runtime as Runtime
import CLI.Protocol (healthJsonPairs)

import qualified Data.ByteString.Lazy.Char8 as BLC

handleHealthcheck :: Text -> IO ()
handleHealthcheck sessionId =
  Runtime.withBootstrappedSession True sessionId $ \session -> do
    let runtime = Runtime.sessRuntime session
    health <- Runtime.checkHealth runtime
    let pairs = healthJsonPairs health sessionId (T.pack (Runtime.sessDbPath session))
    BLC.putStrLn (encode (object pairs))

handleRuntimeReady :: IO ()
handleRuntimeReady = do
  health <- Runtime.probeRuntimeReadiness
  dbPath <- Runtime.resolveDbPath
  let pairs = healthJsonPairs health "runtime-probe" (T.pack dbPath)
  BLC.putStrLn (encode (object pairs))
