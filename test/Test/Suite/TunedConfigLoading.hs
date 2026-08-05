{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.TunedConfigLoading
Description : Runtime loading of tuned config files with fallback.

Verifies the three-level fallback implemented in
'QxFx0.Runtime.Session.SelfConfig.loadTunedOrDefaultIO':

  * a valid tuned config is used when present;
  * a missing or unparseable tuned config falls back to the base
    config file;
  * when both tuned and base configs are missing or unparseable,
    the builtin default is used.

The tests use a small private dummy config type and unique
per-test temporary paths to avoid GHC CSE sharing two identical
'loadTunedOrDefault' applications.
-}
module Test.Suite.TunedConfigLoading
  ( tunedConfigLoadingTests
  ) where

import Control.Exception (bracket_)
import Data.Aeson (FromJSON, ToJSON, encode)
import qualified Data.ByteString.Lazy as BL
import GHC.Generics (Generic)
import Test.HUnit

import QxFx0.Runtime.Session.SelfConfig (loadTunedOrDefaultIO)
import Test.Support (freshTestPath, removeIfExists)

-- ---------------------------------------------------------------------------
-- Dummy config type
-- ---------------------------------------------------------------------------

-- | Minimal config payload used to exercise the loader chain.
data DummyCfg = DummyCfg
  { dcValue :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

builtinCfg, baseCfg, tunedCfg :: DummyCfg
builtinCfg = DummyCfg 0
baseCfg    = DummyCfg 1
tunedCfg   = DummyCfg 2

-- ---------------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------------

withConfigFiles :: [(FilePath, Maybe BL.ByteString)] -> IO a -> IO a
withConfigFiles files action =
  bracket_
    (mapM_ (\(path, mBs) -> maybe (pure ()) (BL.writeFile path) mBs) files)
    (mapM_ (removeIfExists . fst) files)
    action

-- ---------------------------------------------------------------------------
-- Test cases
-- ---------------------------------------------------------------------------

testTunedValidWins :: Test
testTunedValidWins = TestCase $ do
  tunedPath <- freshTestPath "tuned_config_valid_tuned"
  basePath  <- freshTestPath "tuned_config_valid_base"
  withConfigFiles
    [ (tunedPath, Just (encode tunedCfg))
    , (basePath,  Just (encode baseCfg))
    ] $ do
      result <- loadTunedOrDefaultIO tunedPath basePath builtinCfg
      assertEqual "valid tuned file must be loaded" tunedCfg result

testMissingTunedFallsBackToBase :: Test
testMissingTunedFallsBackToBase = TestCase $ do
  tunedPath <- freshTestPath "tuned_config_missing_tuned"
  basePath  <- freshTestPath "tuned_config_missing_base"
  withConfigFiles
    [ (tunedPath, Nothing)
    , (basePath,  Just (encode baseCfg))
    ] $ do
      result <- loadTunedOrDefaultIO tunedPath basePath builtinCfg
      assertEqual "missing tuned file must fall back to base" baseCfg result

testMalformedTunedFallsBackToBase :: Test
testMalformedTunedFallsBackToBase = TestCase $ do
  tunedPath <- freshTestPath "tuned_config_malformed_tuned"
  basePath  <- freshTestPath "tuned_config_malformed_base"
  withConfigFiles
    [ (tunedPath, Just "not json")
    , (basePath,  Just (encode baseCfg))
    ] $ do
      result <- loadTunedOrDefaultIO tunedPath basePath builtinCfg
      assertEqual "malformed tuned file must fall back to base" baseCfg result

testBothMissingFallsBackToBuiltin :: Test
testBothMissingFallsBackToBuiltin = TestCase $ do
  tunedPath <- freshTestPath "tuned_config_both_missing_tuned"
  basePath  <- freshTestPath "tuned_config_both_missing_base"
  withConfigFiles
    [ (tunedPath, Nothing)
    , (basePath,  Nothing)
    ] $ do
      result <- loadTunedOrDefaultIO tunedPath basePath builtinCfg
      assertEqual "missing tuned and base must fall back to builtin" builtinCfg result

testMissingTunedMalformedBaseFallsBackToBuiltin :: Test
testMissingTunedMalformedBaseFallsBackToBuiltin = TestCase $ do
  tunedPath <- freshTestPath "tuned_config_bad_base_tuned"
  basePath  <- freshTestPath "tuned_config_bad_base_base"
  withConfigFiles
    [ (tunedPath, Nothing)
    , (basePath,  Just "not json")
    ] $ do
      result <- loadTunedOrDefaultIO tunedPath basePath builtinCfg
      assertEqual "malformed base with missing tuned must fall back to builtin"
        builtinCfg result

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

tunedConfigLoadingTests :: [Test]
tunedConfigLoadingTests =
  [ TestLabel "valid tuned file wins" testTunedValidWins
  , TestLabel "missing tuned falls back to base" testMissingTunedFallsBackToBase
  , TestLabel "malformed tuned falls back to base" testMalformedTunedFallsBackToBase
  , TestLabel "both missing fall back to builtin" testBothMissingFallsBackToBuiltin
  , TestLabel "missing tuned and malformed base fall back to builtin"
      testMissingTunedMalformedBaseFallsBackToBuiltin
  ]
