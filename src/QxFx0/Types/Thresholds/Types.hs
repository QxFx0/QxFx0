{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Thresholds.Types
  ( DepthMode(..)
  , depthModeText
  , parseDepthModeText
  , ScenePressure(..)
  , scenePressureText
  , LegitimacyStatus(..)
  , legitimacyStatusText
  , clamp01
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), Value(String), withText)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

data DepthMode
  = SurfaceDepth
  | MediumDepth
  | DeepDepth
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData)

depthModeText :: DepthMode -> Text
depthModeText SurfaceDepth = "surface"
depthModeText MediumDepth = "medium"
depthModeText DeepDepth = "deep"

parseDepthModeText :: Text -> Maybe DepthMode
parseDepthModeText txt = case T.toLower (T.strip txt) of
  "surface" -> Just SurfaceDepth
  "medium" -> Just MediumDepth
  "deep" -> Just DeepDepth
  _ -> Nothing

instance ToJSON DepthMode where
  toJSON = String . depthModeText

instance FromJSON DepthMode where
  parseJSON = withText "DepthMode" $ \txt ->
    case parseDepthModeText txt of
      Just mode -> pure mode
      Nothing -> fail ("unknown DepthMode: " ++ T.unpack txt)

data ScenePressure
  = PressureLow
  | PressureMedium
  | PressureHigh
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

scenePressureText :: ScenePressure -> Text
scenePressureText PressureLow = "low"
scenePressureText PressureMedium = "medium"
scenePressureText PressureHigh = "high"

instance ToJSON ScenePressure where
  toJSON = String . scenePressureText

instance FromJSON ScenePressure where
  parseJSON = withText "ScenePressure" $ \txt ->
    case T.toLower (T.strip txt) of
      "low" -> pure PressureLow
      "medium" -> pure PressureMedium
      "high" -> pure PressureHigh
      _ -> fail ("unknown ScenePressure: " ++ T.unpack txt)

data LegitimacyStatus
  = LegitimacyPass
  | LegitimacyDegraded
  | LegitimacyRecovery
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

legitimacyStatusText :: LegitimacyStatus -> Text
legitimacyStatusText LegitimacyPass = "pass"
legitimacyStatusText LegitimacyDegraded = "degraded"
legitimacyStatusText LegitimacyRecovery = "recovery"

instance ToJSON LegitimacyStatus where
  toJSON = String . legitimacyStatusText

instance FromJSON LegitimacyStatus where
  parseJSON = withText "LegitimacyStatus" $ \txt ->
    case T.toLower (T.strip txt) of
      "pass" -> pure LegitimacyPass
      "degraded" -> pure LegitimacyDegraded
      "recovery" -> pure LegitimacyRecovery
      _ -> fail ("unknown LegitimacyStatus: " ++ T.unpack txt)

clamp01 :: Double -> Double
clamp01 = max 0.0 . min 1.0
