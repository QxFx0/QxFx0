{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.Paths
  ( resolveDbPath
  , resolveSessionId
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import System.Environment (lookupEnv)
import System.FilePath ((</>))

resolveSessionId :: IO Text
resolveSessionId = do
  mSessionId <- lookupEnv "QXFX0_SESSION_ID"
  case fmap T.strip (T.pack <$> mSessionId) of
    Just sid | not (T.null sid) -> pure sid
    _ -> do
      now <- getCurrentTime
      pure ("session-" <> T.pack (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" now))

resolveDbPath :: IO FilePath
resolveDbPath = do
  mDbPath <- lookupEnv "QXFX0_DB"
  case mDbPath of
    Just dbPath -> pure dbPath
    Nothing -> do
      mStateDir <- lookupEnv "QXFX0_STATE_DIR"
      stateDir <- case mStateDir of
        Just dir -> pure dir
        Nothing -> do
          mXdgStateHome <- lookupEnv "XDG_STATE_HOME"
          mHome <- lookupEnv "HOME"
          pure $ case mXdgStateHome of
            Just xdgStateHome -> xdgStateHome </> "qxfx0"
            Nothing -> fromMaybe "." ((</> ".local/state/qxfx0") <$> mHome)
      pure (stateDir </> "qxfx0.db")
