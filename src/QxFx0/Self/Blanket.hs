{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Self.Blanket
Description : canonical — Computation of 'SelfBlanket' snapshots from 'SystemState'.

Pure projection from the runtime 'SystemState' to its structural
self-identity snapshot. This is the only sanctioned way to obtain
a 'SelfBlanket'; do not construct values directly outside this
module unless writing tests.

See @docs\/THEORY.md@ §4.1 and 'QxFx0.Self.Types'.
-}
module QxFx0.Self.Blanket
  ( computeSelfBlanket
  ) where

import qualified Data.Map.Strict as Map

import QxFx0.Self.Types (SelfBlanket (..))
import QxFx0.Types
  ( MorphologyData (..)
  , SystemState
  , idsIdentityClaims
  , ssIdentity
  , ssMorphology
  , ssSessionId
  , ssTurnCount
  )

-- | Project a 'SystemState' onto its structural self-identity
-- snapshot. Pure and total. The result depends only on the four
-- fields that participate in the structural invariants
-- ('QxFx0.Self.Types.SelfBlanket') and is otherwise independent
-- of dialogue history, embeddings, observability, or recovery
-- traces.
computeSelfBlanket :: SystemState -> SelfBlanket
computeSelfBlanket ss = SelfBlanket
  { sbSessionId           = ssSessionId ss
  , sbMorphologyTotalSize = morphologyTotalSize (ssMorphology ss)
  , sbIdentityClaimsCount = length (idsIdentityClaims (ssIdentity ss))
  , sbTurnCount           = ssTurnCount ss
  }

-- | Sum of entry counts across all morphology dictionaries.
-- A 'MorphologyData' with zero total entries cannot drive
-- generation and so cannot represent /this system/.
morphologyTotalSize :: MorphologyData -> Int
morphologyTotalSize md =
  Map.size (mdPrepositional md)
    + Map.size (mdGenitive md)
    + Map.size (mdNominative md)
    + Map.size (mdFormsBySurface md)
