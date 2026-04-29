{-# LANGUAGE OverloadedStrings #-}

module CLI.State
  ( handleStateJson
  ) where

import Data.Aeson (encode, object)
import Data.Text (Text)

import qualified QxFx0.Runtime as Runtime
import CLI.Protocol (stateJsonPairs)

import qualified Data.ByteString.Lazy.Char8 as BLC

handleStateJson :: Text -> IO ()
handleStateJson sessionId =
  Runtime.withBootstrappedSession True sessionId $ \session -> do
    let pairs = stateJsonPairs session
    BLC.putStrLn (encode (object pairs))
