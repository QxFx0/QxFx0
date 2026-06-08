{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module QxFx0.Observability.Logging
  ( LogLevel(..)
  , LogEntry(..)
  , LogContext
  , emptyContext
  , addContext
  , logDebug
  , logInfo
  , logWarn
  , logError
  , logException
  , formatLogEntry
  ) where

import Data.Aeson (ToJSON(..), object, (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import System.Environment (lookupEnv)
import System.IO (stderr, hPutStrLn)

import QxFx0.ExceptionPolicy (QxFx0Exception, toErrorCode, toLogMessage, renderQxFx0ExceptionForLogDebug)

-- | Log severity levels
data LogLevel
  = LogDebug
  | LogInfo
  | LogWarn
  | LogError
  deriving stock (Eq, Ord, Show)

instance ToJSON LogLevel where
  toJSON LogDebug = "DEBUG"
  toJSON LogInfo  = "INFO"
  toJSON LogWarn  = "WARN"
  toJSON LogError = "ERROR"

-- | Structured log entry
data LogEntry = LogEntry
  { leTimestamp :: !UTCTime
  , leLevel     :: !LogLevel
  , leMessage   :: !Text
  , leContext   :: !(Map Text Text)
  , leErrorCode :: !(Maybe Text)
  } deriving stock (Eq, Show)

instance ToJSON LogEntry where
  toJSON LogEntry{..} = object
    [ "timestamp" .= leTimestamp
    , "level"     .= leLevel
    , "message"   .= leMessage
    , "context"   .= leContext
    , "error_code" .= leErrorCode
    ]

-- | Log context for structured fields
type LogContext = Map Text Text

-- | Empty log context
emptyContext :: LogContext
emptyContext = Map.empty

-- | Add field to log context
addContext :: Text -> Text -> LogContext -> LogContext
addContext = Map.insert

-- | Log debug message
logDebug :: Text -> LogContext -> IO ()
logDebug msg ctx = do
  timestamp <- getCurrentTime
  let entry = LogEntry timestamp LogDebug msg ctx Nothing
  emitLog entry

-- | Log info message
logInfo :: Text -> LogContext -> IO ()
logInfo msg ctx = do
  timestamp <- getCurrentTime
  let entry = LogEntry timestamp LogInfo msg ctx Nothing
  emitLog entry

-- | Log warning message
logWarn :: Text -> LogContext -> IO ()
logWarn msg ctx = do
  timestamp <- getCurrentTime
  let entry = LogEntry timestamp LogWarn msg ctx Nothing
  emitLog entry

-- | Log error message
logError :: Text -> LogContext -> IO ()
logError msg ctx = do
  timestamp <- getCurrentTime
  let entry = LogEntry timestamp LogError msg ctx Nothing
  emitLog entry

-- | Log exception with structured error code.
-- When QXFX0_DEBUG_ERRORS=true, reveals full error details (including
-- PersistenceTxError messages) instead of redacting them.
logException :: QxFx0Exception -> LogContext -> IO ()
logException ex ctx = do
  timestamp <- getCurrentTime
  mDebug <- lookupEnv "QXFX0_DEBUG_ERRORS"
  let debugEnabled = case fmap (T.toLower . T.strip . T.pack) mDebug of
        Just "1"    -> True
        Just "true" -> True
        _           -> False
      message = if debugEnabled
                  then renderQxFx0ExceptionForLogDebug ex
                  else toLogMessage ex
  let entry = LogEntry
        { leTimestamp = timestamp
        , leLevel     = LogError
        , leMessage   = message
        , leContext   = ctx
        , leErrorCode = Just (toErrorCode ex)
        }
  emitLog entry

-- | Format log entry for output (simple text format for now)
formatLogEntry :: LogEntry -> Text
formatLogEntry LogEntry{..} =
  T.pack (show leTimestamp)
  <> " [" <> T.pack (show leLevel) <> "] "
  <> leMessage
  <> (if Map.null leContext then "" else " " <> formatContext leContext)
  <> maybe "" (\code -> " error_code=" <> code) leErrorCode

-- | Format context map
formatContext :: Map Text Text -> Text
formatContext ctx =
  T.intercalate " " $ map (\(k, v) -> k <> "=" <> v) $ Map.toList ctx

-- | Emit log entry to stderr (simple implementation)
emitLog :: LogEntry -> IO ()
emitLog entry = hPutStrLn stderr $ T.unpack $ formatLogEntry entry

