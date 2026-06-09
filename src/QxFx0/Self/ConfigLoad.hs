{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE NoImplicitPrelude #-}

{-|
Module      : QxFx0.Self.ConfigLoad
Description : supplier — Unsafe IO config loader with builtin fallback.

The pattern is taken from 'Runtime/PGFStatus.hs' / 'pgfCacheRef' in
'Runtime/PGF.hs':

  * 'unsafePerformIO' to load a file at program start-up;
  * '{-# NOINLINE #-}' to prevent GHC from inlining the value
    (which would cause repeated or reordered IO);
  * builtin fallback when the file is missing or unparseable.

This is the ONLY module in the 'Self' subtree that performs IO.
All downstream consumers receive pure values and keep their
signatures unchanged.
-}
module QxFx0.Self.ConfigLoad
  ( loadConfigOrBuiltin
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, eitherDecodeStrict)
import qualified Data.ByteString as BS
import GHC.Generics (Generic)
import System.Directory (doesFileExist)
import System.IO (hPutStrLn, stderr)
import System.IO.Unsafe (unsafePerformIO)

import Prelude

-- | Load a JSON config from @path@, or return the @builtin@ default
-- if the file is missing or cannot be parsed.
--
-- The NOINLINE pragma is essential: without it GHC may inline the
-- value and the 'unsafePerformIO' may be executed multiple times or
-- at unexpected points.
loadConfigOrBuiltin :: FromJSON a => FilePath -> a -> a
loadConfigOrBuiltin path builtin = unsafePerformIO $ do
  exists <- doesFileExist path
  if not exists
    then pure builtin
    else do
      bs <- BS.readFile path
      case eitherDecodeStrict bs of
        Right cfg -> pure cfg
        Left err  -> do
          hPutStrLn stderr ("[config] " <> path <> " parse error: " <> err)
          pure builtin
{-# NOINLINE loadConfigOrBuiltin #-}
