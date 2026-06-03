{-# LANGUAGE ScopedTypeVariables, DerivingStrategies #-}
module QxFx0.ExceptionPolicy
  ( tryAsync
  , tryIO
  , tryQxFx0
  , catchIO
  , QxFx0Exception(..)
  , renderQxFx0ExceptionForLog
  , throwQxFx0
  ) where

import Control.Exception (IOException, SomeException, AsyncException, try, catch, fromException, throwIO, Exception)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Persistence (PersistenceStage)

data QxFx0Exception
  = PersistenceError Text
  | PersistenceTxError !PersistenceStage !Text
  | SQLiteError Text
  | RuntimeInitError Text
  | EmbeddingError Text
  | ThresholdParseError Text
  | AgdaGateError Text
  | IdentityRupture !Text
    -- ^ Structural self-identity ('QxFx0.Self.Types.SelfBlanket')
    -- violated. Categorical failure: the running system is no longer
    -- /this system/. Not recoverable in the @PersistenceError@ /
    -- @RuntimeInitError@ sense; the session must be re-bootstrapped
    -- (or, in production, the process restarted). Payload is the
    -- semicolon-joined rendering of one or more
    -- 'QxFx0.Self.Types.BlanketViolation' values.
  | EssenceRupture !Text
    -- ^ Post-commitment 'Plan' violates committed 'EssenceMode'.
    -- Categorical failure: the system has acted contrary to what
    -- it has chosen to be. Not recoverable; the session must abort
    -- the turn (no persistence). Co-located with 'IdentityRupture'
    -- in 'Finalize.Commit'; the two failures are orthogonal.
  deriving stock (Eq)

instance Show QxFx0Exception where
  show = T.unpack . renderQxFx0ExceptionForLog

instance Exception QxFx0Exception

throwQxFx0 :: QxFx0Exception -> IO a
throwQxFx0 = throwIO

renderQxFx0ExceptionForLog :: QxFx0Exception -> Text
renderQxFx0ExceptionForLog ex =
  case ex of
    PersistenceError _ -> T.pack "PersistenceError(<redacted>)"
    PersistenceTxError stage _ -> T.pack "PersistenceTxError(stage=" <> T.pack (show stage) <> T.pack ", detail=<redacted>)"
    SQLiteError _ -> T.pack "SQLiteError(<redacted>)"
    RuntimeInitError _ -> T.pack "RuntimeInitError(<redacted>)"
    EmbeddingError _ -> T.pack "EmbeddingError(<redacted>)"
    ThresholdParseError _ -> T.pack "ThresholdParseError(<redacted>)"
    AgdaGateError _ -> T.pack "AgdaGateError(<redacted>)"
    IdentityRupture _ -> T.pack "IdentityRupture(<redacted>)"
    EssenceRupture _ -> T.pack "EssenceRupture(<redacted>)"

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
