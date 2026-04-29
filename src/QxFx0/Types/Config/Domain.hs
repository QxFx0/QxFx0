{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Config.Domain
  ( defaultUserTone
  , defaultUserReadiness
  ) where

import Data.Text (Text)

defaultUserTone :: Text
defaultUserTone = "neutral"

defaultUserReadiness :: Double
defaultUserReadiness = 0.5
