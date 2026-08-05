{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.RuntimeMode
  ( RuntimeMode(..)
  , runtimeModeText
  , isStrictRuntimeMode
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value(..), withText)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

data RuntimeMode = DegradedRuntime | StrictRuntime
  deriving stock (Eq, Show, Generic)

instance ToJSON RuntimeMode where
  toJSON DegradedRuntime = String "degraded"
  toJSON StrictRuntime = String "strict"

instance FromJSON RuntimeMode where
  parseJSON = withText "RuntimeMode" $ \t -> case T.toLower (T.strip t) of
    "degraded" -> pure DegradedRuntime
    "strict" -> pure StrictRuntime
    _ -> fail ("Unknown RuntimeMode: " <> T.unpack t)

runtimeModeText :: RuntimeMode -> Text
runtimeModeText DegradedRuntime = "degraded"
runtimeModeText StrictRuntime = "strict"

isStrictRuntimeMode :: RuntimeMode -> Bool
isStrictRuntimeMode StrictRuntime = True
isStrictRuntimeMode DegradedRuntime = False
