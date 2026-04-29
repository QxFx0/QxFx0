{-# LANGUAGE OverloadedStrings, RecordWildCards #-}
{-| Turn-level observability primitives: timings, structured metric logs, and warnings. -}
module QxFx0.Core.Observability
  ( RequestId
  , PhaseTiming(..)
  , TurnMetrics(..)
  , emptyTurnMetrics
  , recordPhase
  , addPhase
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

data TurnMetrics = TurnMetrics
  { tmRequestId    :: !RequestId
  , tmSessionId    :: !Text
  , tmPhases       :: ![PhaseTiming]
  , tmTurnCount    :: !Int
  , tmFamily       :: !Text
  , tmEmbeddingSource :: !Text
  , tmNixStatus    :: !Text
  , tmSafetyStatus :: !Text
  , tmApiHealthy   :: !Bool
  , tmError        :: !(Maybe Text)
  }

emptyTurnMetrics :: RequestId -> Text -> TurnMetrics
emptyTurnMetrics rid sid = TurnMetrics
  { tmRequestId    = rid
  , tmSessionId    = sid
  , tmPhases       = []
  , tmTurnCount    = 0
  , tmFamily       = ""
  , tmEmbeddingSource = ""
  , tmNixStatus    = ""
  , tmSafetyStatus = ""
  , tmApiHealthy   = True
  , tmError        = Nothing
  }

recordPhase :: Text -> UTCTime -> UTCTime -> PhaseTiming
recordPhase = PhaseTiming

addPhase :: PhaseTiming -> TurnMetrics -> TurnMetrics
addPhase pt tm = tm { tmPhases = pt : tmPhases tm }

renderMetricsLog :: TurnMetrics -> Text
renderMetricsLog TurnMetrics{..} = T.intercalate " "
  [ "qxfx0_turn"
  , "request_id=" <> tmRequestId
  , "session_id=" <> tmSessionId
  , "turn=" <> textShow tmTurnCount
  , "family=" <> tmFamily
  , "embedding=" <> tmEmbeddingSource
  , "nix=" <> tmNixStatus
  , "safety=" <> tmSafetyStatus
  , "api_healthy=" <> (if tmApiHealthy then "1" else "0")
  , "phases=" <> T.intercalate "," (map renderPhaseTiming tmPhases)
  , "total_ms=" <> textShow (totalDurationMs tmPhases)
  , case tmError of
      Nothing -> ""
      Just e  -> "error=" <> e
  ]

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

hPutStrLnWarning :: String -> IO ()
hPutStrLnWarning = hPutStrLn stderr
