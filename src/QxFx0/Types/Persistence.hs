{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData #-}
module QxFx0.Types.Persistence
  ( PersistenceStage(..)
  , renderPersistenceStage
  , PersistenceDiagnostic(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.State (SystemState)

data PersistenceStage
  = StageStateBlobUpsert
  | StageSessionTouch
  | StageTurnQualityUpsert
  | StageShadowDivergenceInsert
  | StageRollbackTurnQuality
  | StageRollbackShadowDivergence
  | StageTxBegin
  | StageTxCommit
  | StageTxRollback
  | StageUnknown
  deriving stock (Eq, Show)

renderPersistenceStage :: PersistenceStage -> Text
renderPersistenceStage StageStateBlobUpsert       = "state_blob.upsert"
renderPersistenceStage StageSessionTouch          = "session_touch.upsert"
renderPersistenceStage StageTurnQualityUpsert     = "state_projection.upsert"
renderPersistenceStage StageShadowDivergenceInsert = "shadow_divergence.upsert"
renderPersistenceStage StageRollbackTurnQuality    = "state_projection.rollback"
renderPersistenceStage StageRollbackShadowDivergence = "shadow_divergence.rollback"
renderPersistenceStage StageTxBegin               = "tx_begin"
renderPersistenceStage StageTxCommit              = "tx_commit"
renderPersistenceStage StageTxRollback            = "tx_rollback"
renderPersistenceStage StageUnknown                = "unknown"

data PersistenceDiagnostic
  = PdSchemaMissingFields ![Text]
  | PdCorruptDecode
  | PdTransactionBeginFailed
  | PdTransactionCommitFailed
  | PdTransactionRollbackFailed
  | PdSaveFailed !PersistenceStage !(Maybe Text) !(Maybe Text)
  | PdRollbackFailed !PersistenceStage !(Maybe Text) !(Maybe Text)
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
    renderOne (PdSaveFailed stage mTable mSqlite) =
      "save_failed stage=" <> renderPersistenceStage stage
      <> maybe "" (\t -> " table=" <> t) mTable
      <> maybe "" (\e -> " sqlite=\"" <> e <> "\"") mSqlite
    renderOne (PdRollbackFailed stage mTable mSqlite) =
      "rollback_failed stage=" <> renderPersistenceStage stage
      <> maybe "" (\t -> " table=" <> t) mTable
      <> maybe "" (\e -> " sqlite=\"" <> e <> "\"") mSqlite
