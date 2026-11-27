{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Types.Self.ConatusContour
Description : canonical — typed carriers for the four self-maintenance facts.

The contour is the only place where the name "Conatus" survives the
2026-11-23 P4 rename.  It does not carry a scalar or a vitality claim:
it records four facts the turn already knows — whether the structural
blanket held, which local-recovery cause (if any) fired, whether an
essence commitment is active, and whether the crisis resource pack is
available.

See @docs\/closure\/P4_STATE_INTEGRITY_PREREG_2026-11-23.md@.
-}
module QxFx0.Types.Self.ConatusContour
  ( BlanketIntegrity(..)
  , ConatusContour(..)
  ) where

import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Types.Recovery (LocalRecoveryCause)

-- | Whether the structural blanket invariants held this turn, and how
-- many violations were reported.  A non-zero count aborts the turn in
-- 'QxFx0.Core.TurnPipeline.Finalize.Commit', so a persisted turn is
-- expected to carry @0@; the field makes a violation machine-visible
-- if that contract ever changes.
data BlanketIntegrity = BlanketIntegrity
  { biInvariantsHold :: !Bool
  , biViolationCount :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

-- | The four self-maintenance facts of one turn.
data ConatusContour = ConatusContour
  { ctcBlanketIntegrity   :: !BlanketIntegrity
  , ctcRecoveryEvents     :: ![LocalRecoveryCause]
    -- ^ The local-recovery cause that fired this turn, if any.  The
    --   same fact is recorded top-level as @trcRecoveryCause@.
  , ctcEssenceCommitments :: !Int
    -- ^ @1@ when the post-turn essence is committed, @0@ otherwise.
  , ctcCrisisAvailability :: !Bool
    -- ^ Whether the versioned crisis resource pack is present and
    --   non-empty.  The hard gate is lexical and cannot be
    --   unavailable; the field makes that structural fact visible.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)
