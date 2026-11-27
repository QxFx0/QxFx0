{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Self.ConatusContour
Description : canonical — pure computation of the four self-maintenance facts.

The contour is observational: it is computed once per turn and written to
the replay trace (@trcConatusContour@).  Nothing in routing, recovery or
rendering reads it.  The 2026-11-23 P4 pre-registration chose this shape
deliberately: an ablation hook on a write-only field is provably inert,
so the per-component hooks are deferred until a consumer exists.

See @docs\/closure\/P4_STATE_INTEGRITY_PREREG_2026-11-23.md@.
-}
module QxFx0.Self.ConatusContour
  ( computeConatusContour
  , crisisPackAvailable
  ) where

import QxFx0.Self.Essence (Essence(..))
import QxFx0.Types.Recovery (LocalRecoveryCause)
import QxFx0.Types.Safety.Crisis (CrisisResources(..))
import QxFx0.Types.Self.ConatusContour
  ( BlanketIntegrity(..)
  , ConatusContour(..)
  )

-- | Assemble the contour from facts the turn already carries.  Pure and
-- total.
computeConatusContour
  :: Int                      -- ^ blanket-violation count
  -> Maybe LocalRecoveryCause -- ^ local-recovery cause, if one fired
  -> Essence                  -- ^ post-turn essence
  -> Bool                     -- ^ crisis pack availability
  -> ConatusContour
computeConatusContour violationCount mRecovery essence crisisAvailable =
  ConatusContour
    { ctcBlanketIntegrity = BlanketIntegrity
        { biInvariantsHold = violationCount == 0
        , biViolationCount = violationCount
        }
    , ctcRecoveryEvents = maybe [] pure mRecovery
    , ctcEssenceCommitments = case essence of
        EssenceCommitted _ _ -> 1
        EssenceUncommitted _ -> 0
    , ctcCrisisAvailability = crisisAvailable
    }

-- | A crisis pack is available when it carries a positive version and at
-- least one resource line.  The pack is static and compiled in, so this
-- is @True@ on every healthy build; the check is a guard against an
-- empty resource table, not a runtime health probe.
crisisPackAvailable :: CrisisResources -> Bool
crisisPackAvailable resources =
  crVersion resources > 0 && not (null (crLines resources))
