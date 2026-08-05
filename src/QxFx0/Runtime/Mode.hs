{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.Mode
  ( RuntimeMode(..)
  , resolveRuntimeMode
  , runtimeModeText
  , isStrictRuntimeMode
  ) where

import qualified Data.Text as T
import System.Environment (lookupEnv)

import QxFx0.Types.RuntimeMode
  ( RuntimeMode(..)
  , isStrictRuntimeMode
  , runtimeModeText
  )

resolveRuntimeMode :: IO RuntimeMode
resolveRuntimeMode = do
  mMode <- lookupEnv "QXFX0_RUNTIME_MODE"
  pure $ case fmap (T.toLower . T.strip . T.pack) mMode of
    Just "degraded" -> DegradedRuntime
    Just "degraded-local" -> DegradedRuntime
    Just "test-degraded" -> DegradedRuntime
    Just "strict" -> StrictRuntime
    Just "clockwork" -> StrictRuntime
    _ -> StrictRuntime
