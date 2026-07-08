{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.Mode
  ( RuntimeMode(..)
  , resolveRuntimeMode
  , runtimeModeText
  , isStrictRuntimeMode
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), withText)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import System.Environment (lookupEnv)

data RuntimeMode
  = DegradedRuntime
  | StrictRuntime
  deriving stock (Eq, Show, Generic)

instance ToJSON RuntimeMode where
  toJSON DegradedRuntime = String "degraded"
  toJSON StrictRuntime = String "strict"

instance FromJSON RuntimeMode where
  parseJSON = withText "RuntimeMode" $ \t ->
    case T.toLower (T.strip t) of
      "degraded" -> pure DegradedRuntime
      "strict"   -> pure StrictRuntime
      _          -> fail ("Unknown RuntimeMode: " <> T.unpack t)

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

-- | Render a 'RuntimeMode' to its canonical string representation.
-- Use this for logging, CLI output, or external serialization only;
-- dispatch code should pattern-match on the 'RuntimeMode' constructors.
runtimeModeText :: RuntimeMode -> Text
runtimeModeText DegradedRuntime = "degraded"
runtimeModeText StrictRuntime = "strict"

isStrictRuntimeMode :: RuntimeMode -> Bool
isStrictRuntimeMode StrictRuntime = True
isStrictRuntimeMode DegradedRuntime = False
