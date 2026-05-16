{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Self.Invariants
Description : Pure invariant checks over 'SelfBlanket' snapshots.

Two check operators are provided:

* 'checkInitialBlanket' for the post-bootstrap state (no previous
  blanket exists yet); and
* 'checkBlanketTransition' for any commit-time transition between
  a previous and a current blanket.

Both functions are pure and return the (possibly empty) list of
'BlanketViolation' values produced. An empty list means the
invariants hold; a non-empty list is a structural self-identity
failure ('QxFx0.ExceptionPolicy.IdentityRupture').

See @docs\/THEORY.md@ §4.1.
-}
module QxFx0.Self.Invariants
  ( checkInitialBlanket
  , checkBlanketTransition
  , renderBlanketViolations
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Self.Types
  ( BlanketViolation (..)
  , SelfBlanket (..)
  , renderBlanketViolation
  )

-- | Check the invariants that must hold for a freshly bootstrapped
-- system, with no prior 'SelfBlanket' to compare against.
--
-- Currently enforces:
--
-- * 'BlanketEmptySession' — the session identifier must be non-empty
-- * 'BlanketEmptyMorphology' — at least one morphology entry must
--   be loaded
--
-- Returns @[]@ on success.
checkInitialBlanket :: SelfBlanket -> [BlanketViolation]
checkInitialBlanket sb =
  [ BlanketEmptySession    | T.null (sbSessionId sb)              ]
  <> [ BlanketEmptyMorphology | sbMorphologyTotalSize sb <= 0       ]

-- | Check the invariants that must hold across a commit-time
-- transition from a previous 'SelfBlanket' to a current one.
--
-- Currently enforces (in addition to all checks from
-- 'checkInitialBlanket' applied to the current blanket):
--
-- * 'BlanketSessionChanged' — the session identifier must not change
-- * 'BlanketTurnRegressed' — turn count must be non-decreasing
-- * 'BlanketIdentityErased' — identity-claim count must be
--   non-decreasing
--
-- Returns @[]@ on success.
checkBlanketTransition :: SelfBlanket -> SelfBlanket -> [BlanketViolation]
checkBlanketTransition prev cur =
  checkInitialBlanket cur
    <> [ BlanketSessionChanged (sbSessionId prev) (sbSessionId cur)
       | sbSessionId prev /= sbSessionId cur
       ]
    <> [ BlanketTurnRegressed (sbTurnCount prev) (sbTurnCount cur)
       | sbTurnCount cur < sbTurnCount prev
       ]
    <> [ BlanketIdentityErased (sbIdentityClaimsCount prev) (sbIdentityClaimsCount cur)
       | sbIdentityClaimsCount cur < sbIdentityClaimsCount prev
       ]

-- | Render a list of violations to a single semicolon-separated
-- diagnostic line, suitable for an
-- 'QxFx0.ExceptionPolicy.IdentityRupture' payload.
renderBlanketViolations :: [BlanketViolation] -> Text
renderBlanketViolations = T.intercalate "; " . map renderBlanketViolation
