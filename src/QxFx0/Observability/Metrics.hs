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

import Data.Aeson (ToJSON(..), object, (.=))
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

-- | Metric data point
data Metric = Metric
  { mName      :: !Text
  , mType      :: !MetricType
  , mValue     :: !Double
  , mTimestamp :: !UTCTime
  , mTags      :: !(Map Text Text)
  } deriving (Eq, Show)

instance ToJSON Metric where
  toJSON Metric{..} = object
    [ "name"      .= mName
    , "type"      .= mType
    , "value"     .= mValue
    , "timestamp" .= mTimestamp
    , "tags"      .= mTags
    ]

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
recordGauge registry name value tags = do
  timestamp <- getCurrentTime
  let metric = Metric name Gauge value timestamp tags
  modifyIORef' registry (metric :)

-- | Record histogram metric
recordHistogram :: MetricRegistry -> Text -> Double -> Map Text Text -> IO ()
recordHistogram registry name value tags = do
  timestamp <- getCurrentTime
  let metric = Metric name Histogram value timestamp tags
  modifyIORef' registry (metric :)

-- | Record timing metric (duration in seconds)
recordTiming :: MetricRegistry -> Text -> NominalDiffTime -> Map Text Text -> IO ()
recordTiming registry name duration tags = do
  timestamp <- getCurrentTime
  let value = realToFrac duration :: Double
  let metric = Metric name Timing value timestamp tags
  modifyIORef' registry (metric :)

-- | Get all recorded metrics
getMetrics :: MetricRegistry -> IO [Metric]
getMetrics = readIORef

-- | Format metrics for output (simple text format)
formatMetrics :: [Metric] -> Text
formatMetrics metrics =
  T.intercalate "\n" $ map formatMetric metrics
  where
    formatMetric Metric{..} =
      mName
      <> "{" <> formatTags mTags <> "}"
      <> " " <> T.pack (show mValue)
      <> " [" <> T.pack (show mType) <> "]"
      <> " @ " <> T.pack (show mTimestamp)
    
    formatTags tags =
      T.intercalate "," $ map (\(k, v) -> k <> "=" <> v) $ Map.toList tags

-- | Helper: measure execution time of an action
measureTime :: IO a -> IO (a, NominalDiffTime)
measureTime action = do
  start <- getCurrentTime
  result <- action
  end <- getCurrentTime
  let duration = diffUTCTime end start
  pure (result, duration)

