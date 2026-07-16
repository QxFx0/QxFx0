{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Contradiction-driven belief revision over 'SemanticEdge' lists.
--
-- The runtime projection table may contain multiple edges for the same
-- @(from, to)@ pair (e.g. a discovery edge and a later human correction).
-- When two such edges have opposite relation polarity, the weaker edge is
-- decayed.  If it falls below a confidence threshold it is removed.  The
-- weakening is propagated to derived edges that reference the weakened
-- parent in their 'seLineage'.
module QxFx0.Semantic.Logic.BeliefRevision
  ( Contradiction(..)
  , Resolution(..)
  , ResolutionAction(..)
  , detectContradictions
  , resolveContradictions
  , resolveContradictionsWithConfig
  , defaultRevisionConfig
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeRef
  , SemanticEdge(..)
  , edgeRefOf
  )

-- | A pair of edges that contradict each other on the same (from, to).
data Contradiction = Contradiction
  { cStronger :: !SemanticEdge
  , cWeaker   :: !SemanticEdge
  } deriving stock (Eq, Show)

-- | Action taken to resolve a contradiction.
data ResolutionAction
  = Weakened !Double     -- ^ Confidence reduced to the given value.
  | Quarantined         -- ^ Edge removed from the active network.
  deriving stock (Eq, Show)

-- | Record of a resolved contradiction.
data Resolution = Resolution
  { rEdgeFrom :: !Text
  , rEdgeTo   :: !Text
  , rAction   :: !ResolutionAction
  , rReason   :: !Text
  , rWeaker   :: !SemanticEdge
  } deriving stock (Eq, Show)

-- | Tunable parameters for belief revision.
data RevisionConfig = RevisionConfig
  { rcWeakenPenalty       :: !Double  -- ^ Amount to subtract from weaker edge confidence.
  , rcQuarantineThreshold :: !Double -- ^ Confidence below which the edge is removed.
  }

defaultRevisionConfig :: RevisionConfig
defaultRevisionConfig = RevisionConfig
  { rcWeakenPenalty       = 0.3
  , rcQuarantineThreshold = 0.25
  }

positiveRelationTypes :: [RelationType]
positiveRelationTypes =
  [ RelIsA, RelRequires, RelNecessaryFor, RelPresupposes, RelDetermines
  , RelIncludes, RelEnables, RelPointsTo, RelClaims, RelVerifiedBy
  , RelSignals, RelExpresses, RelPreserves, RelOrientsToward, RelPrescribes
  , RelDenotes, RelStructures, RelTransforms, RelGives, RelReveals
  , RelRecognizes, RelUnifies, RelConnects, RelPrecedes, RelDependsOn
  , RelEvokes, RelMeans, RelSays, RelDirectedAt, RelMakes
  , RelSupports, RelSets, RelCauses, RelInfluences, RelPartOf
  ]

negativeRelationTypes :: [RelationType]
negativeRelationTypes =
  [ RelContrastsWith, RelOpposes, RelNotReducibleTo, RelDiffersFrom
  , RelNegates, RelDestroys
  ]

isPositive :: RelationType -> Bool
isPositive rt = rt `elem` positiveRelationTypes

isNegative :: RelationType -> Bool
isNegative rt = rt `elem` negativeRelationTypes

-- | Detect all direct contradictions in an edge list: same (from, to),
-- opposite relation polarity, different concrete edges.
detectContradictions :: [SemanticEdge] -> [Contradiction]
detectContradictions edges =
  let pairs = [ (e1, e2)
              | e1 <- edges
              , e2 <- edges
              , e1 /= e2
              , (seFrom e1, seTo e1) == (seFrom e2, seTo e2)
              , seRelationType e1 /= seRelationType e2
              , maybe False isPositive (seRelationType e1)
              , maybe False isNegative (seRelationType e2)
              ]
  in mapMaybe toContradiction pairs
  where
    toContradiction :: (SemanticEdge, SemanticEdge) -> Maybe Contradiction
    toContradiction (e1, e2)
      | seConfidence e1 >= seConfidence e2 = Just (Contradiction e1 e2)
      | otherwise                          = Just (Contradiction e2 e1)

-- | Resolve contradictions using default configuration.
resolveContradictions :: [SemanticEdge] -> ([SemanticEdge], [Resolution])
resolveContradictions = resolveContradictionsWithConfig defaultRevisionConfig

-- | Resolve contradictions with explicit configuration.
resolveContradictionsWithConfig :: RevisionConfig -> [SemanticEdge] -> ([SemanticEdge], [Resolution])
resolveContradictionsWithConfig cfg edges =
  let contradictions = detectContradictions edges
      -- Index edges by a simple stable key so we can mark survivors.
      edgeMap = M.fromList (zip [(0 :: Int)..] edges)
      (edgeMap', resols) = foldl (resolveOne cfg) (edgeMap, []) contradictions
  in (M.elems edgeMap', resols)

resolveOne :: RevisionConfig -> (M.Map Int SemanticEdge, [Resolution]) -> Contradiction -> (M.Map Int SemanticEdge, [Resolution])
resolveOne cfg (edgeMap, resols) contradiction =
  let strongKey = findKey edgeMap (cStronger contradiction)
      weakKey   = findKey edgeMap (cWeaker contradiction)
      weakEdge  = cWeaker contradiction
      strongEdge = cStronger contradiction
  in case (strongKey, weakKey) of
       (Just sk, Just wk) | sk == wk -> (edgeMap, resols)
       (Just _sk, Just wk) ->
         case applyWeakening cfg weakEdge of
           Nothing ->
             let edgeMap' = M.delete wk edgeMap
                 res      = Resolution (seFrom weakEdge) (seTo weakEdge) Quarantined
                             ("Contradiction with " <> seFrom strongEdge <> " -> " <> seTo strongEdge)
                             weakEdge
                 edgeMap'' = propagateRemoval weakEdge edgeMap'
             in (edgeMap'', res : resols)
           Just edge' ->
             let edgeMap' = M.insert wk edge' edgeMap
                 res      = Resolution (seFrom weakEdge) (seTo weakEdge) (Weakened (seConfidence edge'))
                             ("Contradiction with " <> seFrom strongEdge <> " -> " <> seTo strongEdge)
                             weakEdge
                 edgeMap'' = propagateWeakening weakEdge edge' edgeMap'
             in (edgeMap'', res : resols)
       _ -> (edgeMap, resols)

findKey :: M.Map Int SemanticEdge -> SemanticEdge -> Maybe Int
findKey edgeMap target =
  case [ k | (k, v) <- M.toList edgeMap, v == target ] of
    (k:_) -> Just k
    []    -> Nothing

applyWeakening :: RevisionConfig -> SemanticEdge -> Maybe SemanticEdge
applyWeakening cfg edge =
  let newConf = seConfidence edge - rcWeakenPenalty cfg
  in if newConf < rcQuarantineThreshold cfg
     then Nothing
     else Just edge { seConfidence = newConf, seWeight = seWeight edge * 0.8 }

lineageRefs :: SemanticEdge -> [EdgeRef]
lineageRefs e = maybe [] id (seLineage e)

-- | Weaken derived edges that have the given parent in their lineage.
propagateWeakening :: SemanticEdge -> SemanticEdge -> M.Map Int SemanticEdge -> M.Map Int SemanticEdge
propagateWeakening parent weakened edgeMap =
  let parentRef = edgeRefOf parent
      adjust e
        | seProvenance e /= ProvenanceDerived = e
        | not (parentRef `elem` lineageRefs e) = e
        | otherwise =
            let newConf = min (seConfidence weakened) (seConfidence e) * 0.9
            in e { seConfidence = newConf, seWeight = seWeight e * 0.9 }
  in M.map adjust edgeMap

-- | Remove derived edges that depend on a removed parent.
propagateRemoval :: SemanticEdge -> M.Map Int SemanticEdge -> M.Map Int SemanticEdge
propagateRemoval parent edgeMap =
  let parentRef = edgeRefOf parent
      keep e
        | seProvenance e /= ProvenanceDerived = True
        | otherwise = not (parentRef `elem` lineageRefs e)
  in M.filter keep edgeMap
