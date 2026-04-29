{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.Mode
  ( RuntimeMode(..)
  , resolveRuntimeMode
  , runtimeModeText
  , isStrictRuntimeMode
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)

data RuntimeMode
  = DegradedRuntime
  | StrictRuntime
  deriving stock (Eq, Show)

resolveRuntimeMode :: IO RuntimeMode
resolveRuntimeMode = do
  mMode <- lookupEnv "QXFX0_RUNTIME_MODE"
  pure $ case fmap (T.toLower . T.strip . T.pack) mMode of
    Just "degraded" -> DegradedRuntime
    Just "test-degraded" -> DegradedRuntime
    Just "strict" -> StrictRuntime
    Just "clockwork" -> StrictRuntime
    _ -> StrictRuntime

runtimeModeText :: RuntimeMode -> Text
runtimeModeText DegradedRuntime = "degraded"
runtimeModeText StrictRuntime = "strict"

isStrictRuntimeMode :: RuntimeMode -> Bool
isStrictRuntimeMode StrictRuntime = True
isStrictRuntimeMode DegradedRuntime = False
