{-# LANGUAGE DeriveGeneric, DerivingStrategies, OverloadedStrings, StrictData #-}
module QxFx0.Types.Persistence
  ( PersistenceEnvelope(..)
  , currentPersistenceEnvelopeVersion
  , PersistenceDiagnostic(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  , module QxFx0.Types.Persistence.Protocol
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Persistence.Protocol
import QxFx0.Types.State (SystemState)

data PersistenceEnvelope = PersistenceEnvelope
  { peVersion :: !Int
  , peState :: !SystemState
  } deriving stock (Eq, Show, Generic)

currentPersistenceEnvelopeVersion :: Int
currentPersistenceEnvelopeVersion = 1

data PersistenceDiagnostic
  = PdSchemaMissingFields ![Text]
  | PdCorruptDecode
  | PdTransactionBeginFailed
  | PdTransactionCommitFailed
  | PdTransactionRollbackFailed
  | PdStateVersionConflict !Text !StateVersion !StateVersion
  | PdSaveFailed !PersistenceStage !(Maybe Text) !(Maybe Text)
  | PdRollbackFailed !PersistenceStage !(Maybe Text) !(Maybe Text)
  | PdNonAuthoritativeTruth
  deriving stock (Eq, Show)

data LoadStateResult
  = LoadStateMissing
  | LoadStateRestored !SystemState
  | LoadStateCorrupt ![PersistenceDiagnostic]
  deriving stock (Eq, Show)

renderPersistenceDiagnostics :: [PersistenceDiagnostic] -> Text
renderPersistenceDiagnostics = T.intercalate "; " . map renderOne
  where
    renderOne (PdSchemaMissingFields fields) =
      "state_schema_defaulted_fields:" <> T.intercalate "," fields
    renderOne PdCorruptDecode = "corrupt_decode"
    renderOne PdTransactionBeginFailed = "tx_begin_failed"
    renderOne PdTransactionCommitFailed = "tx_commit_failed"
    renderOne PdTransactionRollbackFailed = "tx_rollback_failed"
    renderOne (PdStateVersionConflict sessionId expected actual) =
      "state_version_conflict session=" <> sessionId
      <> " expected_revision=" <> T.pack (show (stateRevision expected))
      <> " actual_revision=" <> T.pack (show (stateRevision actual))
      <> " expected_turn=" <> T.pack (show (stateTurn expected))
      <> " actual_turn=" <> T.pack (show (stateTurn actual))
    renderOne (PdSaveFailed stage mTable mSqlite) =
      "save_failed stage=" <> renderPersistenceStage stage
      <> maybe "" (\t -> " table=" <> t) mTable
      <> maybe "" (\e -> " sqlite=\"" <> e <> "\"") mSqlite
    renderOne (PdRollbackFailed stage mTable mSqlite) =
      "rollback_failed stage=" <> renderPersistenceStage stage
      <> maybe "" (\t -> " table=" <> t) mTable
      <> maybe "" (\e -> " sqlite=\"" <> e <> "\"") mSqlite
    renderOne PdNonAuthoritativeTruth = "non_authoritative_persisted_state"
