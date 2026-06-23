{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module QxFx0.Observability.Metrics
  ( MetricType(..)
  , Metric(..)
  , MetricRegistry
  , emptyRegistry
  , recordCounter
  , recordGauge
  , recordHistogram
  , recordTiming
  , getMetrics
  , formatMetrics
  ) where

import Data.Aeson (ToJSON(..), FromJSON(..), object, (.=), (.:), withObject, withText)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime, NominalDiffTime)
import Data.IORef (IORef, newIORef, readIORef, modifyIORef')

-- | Metric types
data MetricType
  = Counter    -- ^ Monotonically increasing counter
  | Gauge      -- ^ Point-in-time value
  | Histogram  -- ^ Distribution of values
  | Timing     -- ^ Duration measurements
  deriving stock (Eq, Show)

instance ToJSON MetricType where
  toJSON Counter   = "counter"
  toJSON Gauge     = "gauge"
  toJSON Histogram = "histogram"
  toJSON Timing    = "timing"

instance FromJSON MetricType where
  parseJSON = withText "MetricType" $ \t -> case t of
    "counter"   -> pure Counter
    "gauge"     -> pure Gauge
    "histogram" -> pure Histogram
    "timing"    -> pure Timing
    _           -> fail $ "unknown MetricType: " ++ T.unpack t

-- | Metric data point
data Metric = Metric
  { mName      :: !Text
  , mType      :: !MetricType
  , mValue     :: !Double
  , mTimestamp :: !UTCTime
  , mTags      :: !(Map Text Text)
  } deriving stock (Eq, Show)

instance ToJSON Metric where
  toJSON Metric{..} = object
    [ "name"      .= mName
    , "type"      .= mType
    , "value"     .= mValue
    , "timestamp" .= mTimestamp
    , "tags"      .= mTags
    ]

instance FromJSON Metric where
  parseJSON = withObject "Metric" $ \o ->
    Metric
      <$> o .:  "name"
      <*> o .:  "type"
      <*> o .:  "value"
      <*> o .:  "timestamp"
      <*> o .:  "tags"

-- | In-memory metric registry (simple implementation)
type MetricRegistry = IORef [Metric]

-- | Create empty metric registry
emptyRegistry :: IO MetricRegistry
emptyRegistry = newIORef []

-- | Record counter metric
recordCounter :: MetricRegistry -> Text -> Double -> Map Text Text -> IO ()
recordCounter registry name value tags = do
  timestamp <- getCurrentTime
  let metric = Metric name Counter value timestamp tags
  modifyIORef' registry (metric :)

-- | Record gauge metric
recordGauge :: MetricRegistry -> Text -> Double -> Map Text Text -> IO ()
recordGauge = recordCounter

-- | Record histogram metric
recordHistogram :: MetricRegistry -> Text -> Double -> Map Text Text -> IO ()
recordHistogram = recordCounter

-- | Record timing metric
recordTiming :: MetricRegistry -> Text -> NominalDiffTime -> Map Text Text -> IO ()
recordTiming registry name duration tags = do
  timestamp <- getCurrentTime
  let metric = Metric name Timing (realToFrac duration) timestamp tags
  modifyIORef' registry (metric :)

-- | Get all metrics from registry
getMetrics :: MetricRegistry -> IO [Metric]
getMetrics = readIORef

-- | Format metrics as human-readable text
formatMetrics :: [Metric] -> Text
formatMetrics metrics = T.unlines (map fmtMetric (reverse metrics))
  where
    fmtMetric Metric{..} =
      T.pack (show mTimestamp) <> " [" <> metricTypeText mType <> "] "
      <> mName <> " = " <> T.pack (show mValue)
      <> tagsText mTags
    metricTypeText Counter   = "counter"
    metricTypeText Gauge     = "gauge"
    metricTypeText Histogram = "histogram"
    metricTypeText Timing    = "timing"
    tagsText tags
      | Map.null tags = ""
      | otherwise     = " " <> T.pack (show (Map.toList tags))
