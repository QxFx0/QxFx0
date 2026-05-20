{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.AtomAccretion
Description : WP3 (GAP3) provisional-atom ontology quarantine and accretion.

When the runtime encounters semantic atoms that do not yet belong to
any canonical cluster, it places them in a provisional quarantine.  A
provisional atom must be observed at least 'defaultProvisionalAtomMinOccurrences'
times across at least 'defaultProvisionalAtomMinTurnSpan' turns before it is
promoted.  Provisional atoms expire after 'defaultProvisionalAtomTTL' turns
without re-observation.  If a provisional atom later collides with a
canonical atom (produced by the existing cluster ontology), it is
removed in favour of the canonical entry.

This module is pure and total; all side effects (state mutation) are
delegated to the caller ('buildNextSystemState').
-}
module QxFx0.Semantic.AtomAccretion
  ( observeNovelAtom
  , promoteProvisionalAtoms
  , decayProvisionalAtoms
  , resolveCollisions
  ) where

import Data.List (find)

import QxFx0.Types.Domain.Atoms
  ( AtomSet(..)
  , AtomTag(..)
  , MeaningAtom(..)
  , ProvisionalAtom(..)
  , defaultProvisionalAtomMinOccurrences
  , defaultProvisionalAtomMinTurnSpan
  , defaultProvisionalAtomTTL
  )

-- | Observe an 'AtomTag' at the given turn.  If the tag already
-- exists in the provisional list (and is not yet promoted), bump its
-- occurrence count and refresh 'paLastSeenTurn'.  If it is promoted,
-- leave it untouched.  If it does not exist, append a new
-- 'ProvisionalAtom' with count 1.
observeNovelAtom
  :: AtomTag
  -> Int
  -> [ProvisionalAtom]
  -> [ProvisionalAtom]
observeNovelAtom tag currentTurn atoms =
  case find (\a -> paTag a == tag) atoms of
    Just existing
      | paPromoted existing -> atoms
      | otherwise ->
          let updated = existing
                { paOccurrences = paOccurrences existing + 1
                , paLastSeenTurn = currentTurn
                }
          in map (\a -> if paTag a == tag then updated else a) atoms
    Nothing ->
      ProvisionalAtom
        { paTag = tag
        , paOccurrences = 1
        , paFirstSeenTurn = currentTurn
        , paLastSeenTurn = currentTurn
        , paPromoted = False
        }
      : atoms

-- | Evaluate provisional atoms for promotion at the given turn.
-- Returns @(remaining provisional atoms, promoted tags)@.
-- Promotion requires:
--
--   * occurrences >= 'defaultProvisionalAtomMinOccurrences'
--   * turn span (last - first) >= 'defaultProvisionalAtomMinTurnSpan'
--
-- Promoted atoms remain in the provisional list with 'paPromoted'
-- set to 'True' so they are not re-evaluated or decayed.
promoteProvisionalAtoms
  :: Int
  -> [ProvisionalAtom]
  -> ([ProvisionalAtom], [AtomTag])
promoteProvisionalAtoms currentTurn atoms =
  let (promoted, remaining) =
        foldr
          (\a (ps, rs) ->
             if not (paPromoted a)
                   && paOccurrences a >= defaultProvisionalAtomMinOccurrences
                   && paLastSeenTurn a - paFirstSeenTurn a >= defaultProvisionalAtomMinTurnSpan
               then (paTag a : ps, a { paPromoted = True, paLastSeenTurn = currentTurn } : rs)
               else (ps, a : rs))
          ([], [])
          atoms
  in (remaining, promoted)

-- | Remove un-promoted provisional atoms whose TTL has expired.
-- TTL is measured from 'paLastSeenTurn'.
decayProvisionalAtoms
  :: Int
  -> [ProvisionalAtom]
  -> [ProvisionalAtom]
decayProvisionalAtoms currentTurn =
  filter
    (\a -> paPromoted a || currentTurn - paLastSeenTurn a <= defaultProvisionalAtomTTL)

-- | Remove provisional atoms whose tag already appears in the
-- canonical 'AtomSet' (collision detection).  The canonical copy
-- wins.  Promoted atoms are retained in the provisional record
-- unless they also collide, in which case they are redundant.
resolveCollisions
  :: AtomSet
  -> [ProvisionalAtom]
  -> [ProvisionalAtom]
resolveCollisions canonical atoms =
  let canonicalTags = map maTag (asAtoms canonical)
  in filter (\a -> paPromoted a || paTag a `notElem` canonicalTags) atoms
