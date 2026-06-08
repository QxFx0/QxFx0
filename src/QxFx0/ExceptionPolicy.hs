{-# LANGUAGE ScopedTypeVariables, DerivingStrategies #-}
module QxFx0.ExceptionPolicy
  ( tryAsync
  , tryIO
  , tryQxFx0
  , catchIO
  , QxFx0Exception(..)
  , PersistenceErrorDetails(..)
  , RuntimeInitErrorDetails(..)
  , EmbeddingErrorDetails(..)
  , SQLiteErrorDetails(..)
  , PGFError(..)
  , renderQxFx0ExceptionForLog
  , renderQxFx0ExceptionForLogDebug
  , throwQxFx0
  , toErrorCode
  , toLogMessage
  , mkPersistenceError
  , mkRuntimeInitError
  , mkEmbeddingError
  , mkSQLiteError
  ) where

import Control.Exception (IOException, SomeException, AsyncException, try, catch, fromException, throwIO, Exception)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Persistence (PersistenceStage)

-- | Structured error details for persistence failures
data PersistenceErrorDetails = PersistenceErrorDetails
  { pedStage :: !PersistenceStage
  , pedOperation :: !Text
  , pedContext :: !(Map Text Text)
  , pedErrorCode :: !Text
  } deriving stock (Eq, Show)

-- | Structured error details for runtime initialization failures
data RuntimeInitErrorDetails = RuntimeInitErrorDetails
  { riedComponent :: !Text
  , riedOperation :: !Text
  , riedContext :: !(Map Text Text)
  , riedErrorCode :: !Text
  } deriving stock (Eq, Show)

-- | Structured error details for embedding backend failures
data EmbeddingErrorDetails = EmbeddingErrorDetails
  { eedBackend :: !Text
  , eedOperation :: !Text
  , eedContext :: !(Map Text Text)
  , eedErrorCode :: !Text
  } deriving stock (Eq, Show)

-- | Structured error details for SQLite failures
data SQLiteErrorDetails = SQLiteErrorDetails
  { sedOperation :: !Text
  , sedContext :: !(Map Text Text)
  , sedErrorCode :: !Text
  } deriving stock (Eq, Show)

-- | Structured PGF-specific errors for grammatical framework operations
data PGFError
  = PGFFileNotFound FilePath
  | PGFParseError Text
  | PGFLinearizationError Text
  | PGFIOError IOException
  deriving stock (Show, Eq)

instance Exception PGFError

-- P2-3: the four @*Error Text@ / @*ErrorStructured@ pairs below are a
-- deliberate, retained compatibility surface, NOT a forgotten half-migration.
-- Construction has migrated to the structured forms (see 'mkPersistenceError',
-- 'mkRuntimeInitError', 'mkEmbeddingError', 'mkSQLiteError'). The flat @Text@
-- constructors are kept because they are load-bearing on the CONSUMER side:
-- the test contract (CoreBehavior, StatePersistence, RuntimeInfrastructure)
-- pattern-matches them as expected results, and 'toErrorCode'/'toLogMessage'
-- handle both. Full retirement requires rewriting those test expectations and
-- is deferred. Do not add NEW flat-form construction sites — use the @mk*@
-- helpers.
data QxFx0Exception
  = PersistenceError Text
  | PersistenceErrorStructured !PersistenceErrorDetails
  | PersistenceTxError !PersistenceStage !Text
  | PersistenceConflict !Text !Int !Int !Int
  | SQLiteError Text
  | SQLiteErrorStructured !SQLiteErrorDetails
  | RuntimeInitError Text
  | RuntimeInitErrorStructured !RuntimeInitErrorDetails
  | EmbeddingError Text
  | EmbeddingErrorStructured !EmbeddingErrorDetails
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
  | StateInvariantViolation !Text
    -- ^ System state invariant violated during turn pipeline.
    -- Indicates a programming error or corrupted state that prevents
    -- safe continuation of the turn. The turn should be aborted and
    -- the system should attempt graceful degradation.
  deriving stock (Eq)

instance Show QxFx0Exception where
  show = T.unpack . renderQxFx0ExceptionForLog

instance Exception QxFx0Exception

throwQxFx0 :: QxFx0Exception -> IO a
throwQxFx0 = throwIO

-- | Extract error code from exception for structured logging
toErrorCode :: QxFx0Exception -> Text
toErrorCode ex =
  case ex of
    PersistenceError _ -> T.pack "PERSISTENCE_ERROR"
    PersistenceErrorStructured details -> pedErrorCode details
    PersistenceTxError _ _ -> T.pack "PERSISTENCE_TX_ERROR"
    PersistenceConflict _ _ _ _ -> T.pack "PERSISTENCE_CONFLICT"
    SQLiteError _ -> T.pack "SQLITE_ERROR"
    SQLiteErrorStructured details -> sedErrorCode details
    RuntimeInitError _ -> T.pack "RUNTIME_INIT_ERROR"
    RuntimeInitErrorStructured details -> riedErrorCode details
    EmbeddingError _ -> T.pack "EMBEDDING_ERROR"
    EmbeddingErrorStructured details -> eedErrorCode details
    ThresholdParseError _ -> T.pack "THRESHOLD_PARSE_ERROR"
    AgdaGateError _ -> T.pack "AGDA_GATE_ERROR"
    IdentityRupture _ -> T.pack "IDENTITY_RUPTURE"
    EssenceRupture _ -> T.pack "ESSENCE_RUPTURE"
    StateInvariantViolation _ -> T.pack "STATE_INVARIANT_VIOLATION"

-- | Extract human-readable log message from exception
toLogMessage :: QxFx0Exception -> Text
toLogMessage = renderQxFx0ExceptionForLog

-- | Helper: create structured persistence error
mkPersistenceError :: PersistenceStage -> Text -> Text -> Map Text Text -> QxFx0Exception
mkPersistenceError stage operation errorCode context =
  PersistenceErrorStructured $ PersistenceErrorDetails
    { pedStage = stage
    , pedOperation = operation
    , pedContext = context
    , pedErrorCode = errorCode
    }

-- | Helper: create structured runtime init error
mkRuntimeInitError :: Text -> Text -> Text -> Map Text Text -> QxFx0Exception
mkRuntimeInitError component operation errorCode context =
  RuntimeInitErrorStructured $ RuntimeInitErrorDetails
    { riedComponent = component
    , riedOperation = operation
    , riedContext = context
    , riedErrorCode = errorCode
    }

-- | Helper: create structured embedding error
mkEmbeddingError :: Text -> Text -> Text -> Map Text Text -> QxFx0Exception
mkEmbeddingError backend operation errorCode context =
  EmbeddingErrorStructured $ EmbeddingErrorDetails
    { eedBackend = backend
    , eedOperation = operation
    , eedContext = context
    , eedErrorCode = errorCode
    }

-- | Helper: create structured SQLite error
mkSQLiteError :: Text -> Text -> Map Text Text -> QxFx0Exception
mkSQLiteError operation errorCode context =
  SQLiteErrorStructured $ SQLiteErrorDetails
    { sedOperation = operation
    , sedContext = context
    , sedErrorCode = errorCode
    }

renderQxFx0ExceptionForLog :: QxFx0Exception -> Text
renderQxFx0ExceptionForLog ex =
  case ex of
    PersistenceError _ -> T.pack "PersistenceError(<redacted>)"
    PersistenceErrorStructured details ->
      T.pack "PersistenceError(stage=" <> T.pack (show (pedStage details))
      <> T.pack ", operation=" <> pedOperation details
      <> T.pack ", code=" <> pedErrorCode details
      <> T.pack ", context=<redacted>)"
    PersistenceTxError stage _ -> T.pack "PersistenceTxError(stage=" <> T.pack (show stage) <> T.pack ", detail=<redacted>)"
    PersistenceConflict sid expected actual priorTurn ->
      T.pack "PersistenceConflict(session=" <> sid
      <> T.pack ", expected_revision=" <> T.pack (show expected)
      <> T.pack ", actual_revision=" <> T.pack (show actual)
      <> T.pack ", expected_prior_turn=" <> T.pack (show priorTurn)
      <> T.pack ")"
    SQLiteError _ -> T.pack "SQLiteError(<redacted>)"
    SQLiteErrorStructured details ->
      T.pack "SQLiteError(operation=" <> sedOperation details
      <> T.pack ", code=" <> sedErrorCode details
      <> T.pack ", context=<redacted>)"
    RuntimeInitError _ -> T.pack "RuntimeInitError(<redacted>)"
    RuntimeInitErrorStructured details ->
      T.pack "RuntimeInitError(component=" <> riedComponent details
      <> T.pack ", operation=" <> riedOperation details
      <> T.pack ", code=" <> riedErrorCode details
      <> T.pack ", context=<redacted>)"
    EmbeddingError _ -> T.pack "EmbeddingError(<redacted>)"
    EmbeddingErrorStructured details ->
      T.pack "EmbeddingError(backend=" <> eedBackend details
      <> T.pack ", operation=" <> eedOperation details
      <> T.pack ", code=" <> eedErrorCode details
      <> T.pack ", context=<redacted>)"
    ThresholdParseError _ -> T.pack "ThresholdParseError(<redacted>)"
    AgdaGateError _ -> T.pack "AgdaGateError(<redacted>)"
    IdentityRupture _ -> T.pack "IdentityRupture(<redacted>)"
    EssenceRupture _ -> T.pack "EssenceRupture(<redacted>)"
    StateInvariantViolation msg -> T.pack "StateInvariantViolation(" <> msg <> T.pack ")"

-- | Debug variant: reveals full error details for PersistenceTxError
-- (and other detail-redacted constructors) when the caller opts in.
-- Gated by QXFX0_DEBUG_ERRORS=true in the logging layer.
renderQxFx0ExceptionForLogDebug :: QxFx0Exception -> Text
renderQxFx0ExceptionForLogDebug ex =
  case ex of
    PersistenceTxError stage msg -> T.pack "PersistenceTxError(stage=" <> T.pack (show stage) <> T.pack ", detail=" <> msg <> T.pack ")"
    SQLiteError msg -> T.pack "SQLiteError(" <> msg <> T.pack ")"
    PersistenceError msg -> T.pack "PersistenceError(" <> msg <> T.pack ")"
    RuntimeInitError msg -> T.pack "RuntimeInitError(" <> msg <> T.pack ")"
    EmbeddingError msg -> T.pack "EmbeddingError(" <> msg <> T.pack ")"
    _ -> renderQxFx0ExceptionForLog ex

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
