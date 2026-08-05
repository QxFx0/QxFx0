{-# LANGUAGE DeriveGeneric, DerivingStrategies, OverloadedStrings, StrictData #-}
module QxFx0.Types.Persistence
  ( PersistenceStage(..)
  , PersistenceEnvelope(..)
  , StateVersion(..)
  , currentPersistenceEnvelopeVersion
  , corruptStateRepairVersion
  , isCorruptStateRepairVersion
  , renderPersistenceStage
  , PersistenceDiagnostic(..)
  , LoadStateResult(..)
  , renderPersistenceDiagnostics
  ) where

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

-- | Explicit write capability returned only when a persisted blob was read at
-- the given revision and found corrupt. Normal writers must never construct or
-- reinterpret this as turn zero.
corruptStateRepairVersion :: Int -> StateVersion
corruptStateRepairVersion revision = StateVersion revision (-1)

isCorruptStateRepairVersion :: StateVersion -> Bool
isCorruptStateRepairVersion version = stateTurn version == -1

-- | The database revision and turn lineage observed with a loaded state.
-- Writers must present this pair; a revision fetched independently of the
-- state is not a valid write capability.
data StateVersion = StateVersion
  { stateRevision :: !Int
  , stateTurn :: !Int
  } deriving stock (Eq, Show, Generic)

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
