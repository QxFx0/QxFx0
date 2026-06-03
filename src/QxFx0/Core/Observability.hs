{-# LANGUAGE OverloadedStrings, RecordWildCards #-}
{-| Turn-level observability primitives: timings, structured metric logs, and warnings. -}
module QxFx0.Core.Observability
  ( RequestId
  , PhaseTiming(..)
  , ThresholdProbe(..)
  , TurnMetrics(..)
  , emptyTurnMetrics
  , recordPhase
  , addPhase
  , recordThresholdProbe
  , renderMetricsLog
  , logMetrics
  , hPutStrLnWarning
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Data.Time.Clock (UTCTime, diffUTCTime)
import System.IO (hPutStrLn, stderr)
import QxFx0.Types.Text (textShow)

type RequestId = Text

data PhaseTiming = PhaseTiming
  { ptPhase :: !Text
  , ptStart :: !UTCTime
  , ptEnd   :: !UTCTime
  }

data ThresholdProbe = ThresholdProbe
  { thrSignal    :: !Text
  , thrThreshold :: !Double
  , thrFired     :: !Bool
  }

data TurnMetrics = TurnMetrics
  { tmRequestId    :: !RequestId
  , tmSessionId    :: !Text
  , tmPhases       :: ![PhaseTiming]
  , tmThresholds   :: ![ThresholdProbe]
  , tmTurnCount    :: !Int
  , tmFamily       :: !Text
  , tmEmbeddingSource :: !Text
  , tmNixStatus    :: !Text
  , tmSafetyStatus :: !Text
  , tmApiHealthy   :: !Bool
  , tmError        :: !(Maybe Text)
  , tmLearningPressureScore :: !Double
    -- ^ WP6.1: learning-pressure score that drove NeedLexiconExtension [0,1].
  , tmUnknownCountWindow :: !Int
    -- ^ WP6.1: count of unknown-topic mentions in the current window.
  , tmGraftsWindow :: !Int
    -- ^ WP6.1: grafts observed within the current window.
  , tmLexiconNeedTriggerReason :: !Text
    -- ^ WP6.1: telemetry tag explaining why lexicon need was raised or not.
  , tmDedupSkipReason :: !(Maybe Text)
    -- ^ WP3/WP6.1: reason external query was dedup-skipped, if any.
  }

emptyTurnMetrics :: RequestId -> Text -> TurnMetrics
emptyTurnMetrics rid sid = TurnMetrics
  { tmRequestId    = rid
  , tmSessionId    = sid
  , tmPhases       = []
  , tmThresholds   = []
  , tmTurnCount    = 0
  , tmFamily       = ""
  , tmEmbeddingSource = ""
  , tmNixStatus    = ""
  , tmSafetyStatus = ""
  , tmApiHealthy   = True
  , tmError        = Nothing
  , tmLearningPressureScore = 0.0
  , tmUnknownCountWindow = 0
  , tmGraftsWindow = 0
  , tmLexiconNeedTriggerReason = ""
  , tmDedupSkipReason = Nothing
  }

recordPhase :: Text -> UTCTime -> UTCTime -> PhaseTiming
recordPhase = PhaseTiming

addPhase :: PhaseTiming -> TurnMetrics -> TurnMetrics
addPhase pt tm = tm { tmPhases = pt : tmPhases tm }

recordThresholdProbe :: Text -> Double -> Bool -> TurnMetrics -> TurnMetrics
recordThresholdProbe signal threshold fired tm =
  tm
    { tmThresholds =
        ThresholdProbe signal threshold fired : tmThresholds tm
    }

renderMetricsLog :: TurnMetrics -> Text
renderMetricsLog TurnMetrics{..} = T.intercalate " "
  [ "qxfx0_turn"
  , "request_id=" <> sanitizeLogField tmRequestId
  , "session_id=" <> sanitizeLogField tmSessionId
  , "turn=" <> textShow tmTurnCount
  , "family=" <> sanitizeLogField tmFamily
  , "embedding=" <> sanitizeLogField tmEmbeddingSource
  , "nix=" <> sanitizeLogField tmNixStatus
  , "safety=" <> sanitizeLogField tmSafetyStatus
  , "api_healthy=" <> (if tmApiHealthy then "1" else "0")
  , "phases=" <> T.intercalate "," (map renderPhaseTiming tmPhases)
  , "thresholds=" <> T.intercalate "," (map renderThresholdProbe tmThresholds)
  , "total_ms=" <> textShow (totalDurationMs tmPhases)
  , case tmError of
      Nothing -> ""
      Just e  -> "error=" <> sanitizeLogField e
  ]

renderThresholdProbe :: ThresholdProbe -> Text
renderThresholdProbe ThresholdProbe{..} =
  thrSignal
    <> ":"
    <> textShow thrThreshold
    <> ":"
    <> (if thrFired then "1" else "0")

renderPhaseTiming :: PhaseTiming -> Text
renderPhaseTiming PhaseTiming{..} = ptPhase <> ":" <> textShow (phaseDurationMs ptStart ptEnd) <> "ms"

phaseDurationMs :: UTCTime -> UTCTime -> Double
phaseDurationMs start end = realToFrac (diffUTCTime end start) * 1000.0

totalDurationMs :: [PhaseTiming] -> Double
totalDurationMs [] = 0.0
totalDurationMs phases =
  let starts = map ptStart phases
      ends   = map ptEnd phases
  in case (starts, ends) of
       (_:_, _:_) -> phaseDurationMs (minimum starts) (maximum ends)
       _ -> 0.0

logMetrics :: TurnMetrics -> IO ()
-- NOTE: this module is intentionally used from runtime boundaries; direct stderr output stays here
-- to avoid threading an IO logger through pure planning code paths.
logMetrics = T.hPutStrLn stderr . renderMetricsLog

hPutStrLnWarning :: Text -> IO ()
hPutStrLnWarning = T.hPutStrLn stderr

sanitizeLogField :: Text -> Text
sanitizeLogField = T.filter (\c -> c >= ' ' && c <= '~' && c /= '\\' && c /= '\n' && c /= '\r')
