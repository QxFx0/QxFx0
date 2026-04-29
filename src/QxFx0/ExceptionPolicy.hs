{-# LANGUAGE ScopedTypeVariables, DerivingStrategies #-}
module QxFx0.ExceptionPolicy
  ( tryAsync
  , tryIO
  , tryQxFx0
  , catchIO
  , QxFx0Exception(..)
  , throwQxFx0
  ) where

import Control.Exception (IOException, SomeException, AsyncException, try, catch, fromException, throwIO, Exception)
import Data.Text (Text)

import QxFx0.Types.Persistence (PersistenceStage)

data QxFx0Exception
  = PersistenceError Text
  | PersistenceTxError !PersistenceStage !Text
  | SQLiteError Text
  | RuntimeInitError Text
  | EmbeddingError Text
  | ThresholdParseError Text
  | AgdaGateError Text
  deriving stock (Eq, Show)

instance Exception QxFx0Exception

throwQxFx0 :: QxFx0Exception -> IO a
throwQxFx0 = throwIO

tryAsync :: IO a -> IO (Either SomeException a)
tryAsync action = do
  result <- try action
  case result of
    Left se -> case fromException se of
      Just (_ :: AsyncException) -> throwIO se
      Nothing -> pure (Left se)
    Right v -> pure (Right v)

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

tryQxFx0 :: IO a -> IO (Either QxFx0Exception a)
tryQxFx0 = try

catchIO :: IO a -> (IOException -> IO a) -> IO a
catchIO = catch
