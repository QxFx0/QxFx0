{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Support.QuickCheckConfig
Description : Shared QuickCheck configuration for test suites.

Provides an env-configurable 'qcArgs' so CI can reduce 'maxSuccess' for
fast suites (e.g. @QXFX0_QUICKCHECK_MAX_SUCCESS=10@) while local runs keep
the default (100). This solves the CI timeout where 70 property tests x
100 iterations exceeded the 30-second budget.
-}
module Test.Support.QuickCheckConfig
  ( qcArgs
  , qcMaxSuccess
  ) where

import System.Environment (lookupEnv)
import Test.QuickCheck (Args (..), stdArgs)

-- | Default number of QuickCheck iterations when the env var is unset.
defaultMaxSuccess :: Int
defaultMaxSuccess = 100

-- | Read 'QXFX0_QUICKCHECK_MAX_SUCCESS' from the environment, falling back
-- to 'defaultMaxSuccess'.
qcMaxSuccess :: IO Int
qcMaxSuccess = do
  mVal <- lookupEnv "QXFX0_QUICKCHECK_MAX_SUCCESS"
  case mVal of
    Nothing -> pure defaultMaxSuccess
    Just val ->
      case reads val of
        [(n, "")] | n > 0 -> pure n
        _ -> pure defaultMaxSuccess

-- | 'stdArgs' with 'maxSuccess' overridden by the env var.
-- Use this in place of @stdArgs { maxSuccess = N }@ in test helpers.
qcArgs :: IO Args
qcArgs = do
  n <- qcMaxSuccess
  pure stdArgs { maxSuccess = n }
