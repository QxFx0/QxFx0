{-# LANGUAGE DeriveGeneric, DerivingStrategies, OverloadedStrings, StrictData #-}
module QxFx0.Types.Persistence
  ( PersistenceStage(..)
  , PersistenceEnvelope(..)
  , currentPersistenceEnvelopeVersion
  , renderPersistenceStage
  , PersistenceDiagnostic(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  ) where

import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.State (SystemState)

data PersistenceEnvelope = PersistenceEnvelope
  { peVersion :: !Int
  , peState :: !SystemState
  } deriving stock (Eq, Show, Generic)

currentPersistenceEnvelopeVersion :: Int
currentPersistenceEnvelopeVersion = 1

instance ToJSON PersistenceEnvelope where
  toJSON envelope = object
    [ "persistenceEnvelopeVersion" .= peVersion envelope
    , "state" .= peState envelope
    ]

instance FromJSON PersistenceEnvelope where
  parseJSON = withObject "PersistenceEnvelope" $ \o ->
    PersistenceEnvelope
      <$> o .: "persistenceEnvelopeVersion"
      <*> o .: "state"

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
  | PdStateRevisionConflict !Text !Int !Int !Int
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
    renderOne (PdStateRevisionConflict sessionId expectedRevision actualRevision expectedPriorTurn) =
      "state_revision_conflict session=" <> sessionId
      <> " expected_revision=" <> T.pack (show expectedRevision)
      <> " actual_revision=" <> T.pack (show actualRevision)
      <> " expected_prior_turn=" <> T.pack (show expectedPriorTurn)
    renderOne (PdSaveFailed stage mTable mSqlite) =
      "save_failed stage=" <> renderPersistenceStage stage
      <> maybe "" (\t -> " table=" <> t) mTable
      <> maybe "" (\e -> " sqlite=\"" <> e <> "\"") mSqlite
    renderOne (PdRollbackFailed stage mTable mSqlite) =
      "rollback_failed stage=" <> renderPersistenceStage stage
      <> maybe "" (\t -> " table=" <> t) mTable
      <> maybe "" (\e -> " sqlite=\"" <> e <> "\"") mSqlite
