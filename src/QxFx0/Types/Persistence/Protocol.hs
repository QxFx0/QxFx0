{-# LANGUAGE DeriveGeneric, DerivingStrategies, OverloadedStrings, StrictData #-}

-- | Leaf persistence protocol types shared by the persistence bridge and the
-- exception policy. Kept free of 'SystemState' so exception construction never
-- drags the semantic layer into a module cycle.
module QxFx0.Types.Persistence.Protocol
  ( StateVersion(..)
  , PersistenceStage(..)
  , corruptStateRepairVersion
  , isCorruptStateRepairVersion
  , renderPersistenceStage
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

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

-- | Explicit write capability returned only when a persisted blob was read at
-- the given revision and found corrupt. Normal writers must never construct or
-- reinterpret this as turn zero.
corruptStateRepairVersion :: Int -> StateVersion
corruptStateRepairVersion revision = StateVersion revision (-1)

isCorruptStateRepairVersion :: StateVersion -> Bool
isCorruptStateRepairVersion version = stateTurn version == -1

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
