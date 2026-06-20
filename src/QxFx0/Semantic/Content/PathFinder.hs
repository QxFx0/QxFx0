{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Content.PathFinder
Description : Step 3 — Graph path finder for generative composition.

Finds admissible paths through the AtomStore relation graph.
Field-prototypes bias which relation types are preferred, but
Field never mutates the graph — it only ranks paths.

Length 1: topic → relation → object (single predicate)
Length 2: topic → rel1 → intermediate → rel2 → object (chained argument)
Length 3: topic → rel1 → obj1 → rel2 → obj2 → rel3 → obj3 (deep argument)
-}
module QxFx0.Semantic.Content.PathFinder
  ( -- * Types
    RankedPath(..)
  , PathScore(..)
  , FieldProfile(..)
    -- * Path finding
  , findPathsFrom
  , findPathsLength1
  , findPathsLength2
  , findPathsLength3
    -- * Field bias
  , fieldProfileFromField
  , relationTypeBias
  , scorePath
  , rankPaths
  , selectTopPaths
    -- * Composition
  , composeDefinition
  , defaultFieldProfile
  , composeDefinitionWithGates
    -- * Verbalization
  , verbalizePath
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (sortOn, sortBy, groupBy, nubBy)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (comparing, Down(..))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.Base (renderPredicateArgued, SemanticPredicate(..), PredicateRole(..), mkArguedPred)
import QxFx0.Semantic.Content.GeneratedPredicateGate (filterAdmissible, validatePath, GateVerdict(..))

-- ============================================================
-- Types
-- ============================================================

-- | A scored path through the relation graph.
data RankedPath = RankedPath
  { rpProof   :: !PathProof    -- edges traversed
  , rpScore   :: !PathScore    -- how well this path fits the Field
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data PathScore = PathScore
  { psBias       :: !Double    -- field bias sum (higher = more relevant)
  , psLengthPenalty :: !Double -- penalty for longer paths (shorter = better)
  , psTotal      :: !Double    -- psBias - psLengthPenalty
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Simplified Field profile for path ranking.
-- Decoupled from the full Field type to keep PathFinder testable
-- without pulling in the entire Self layer.
data FieldProfile = FieldProfile
  { fpConfidence     :: !Double  -- 0..1, high → prefer claims/verified
  , fpCounterfactual :: !Double  -- 0..1, high → prefer contrasts/differs
  , fpConsolidation  :: !Double  -- 0..1, high → prefer presupposes/requires
  , fpResonance      :: !Double  -- 0..1, high → prefer signals/expresses
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Default neutral profile (no bias).
defaultFieldProfile :: FieldProfile
defaultFieldProfile = FieldProfile 0.5 0.5 0.5 0.5

-- ============================================================
-- Path finding
-- ============================================================

-- | Find all paths from an atom up to maxLen.
-- Returns paths grouped by length (shortest first).
findPathsFrom :: Int -> AtomId -> [RankedPath]
findPathsFrom maxLen start =
  case maxLen of
    1 -> findPathsLength1 start
    2 -> findPathsLength1 start ++ findPathsLength2 start
    3 -> findPathsLength1 start ++ findPathsLength2 start ++ findPathsLength3 start
    _ -> findPathsLength1 start

-- | Length 1: start →rel→ object.
findPathsLength1 :: AtomId -> [RankedPath]
findPathsLength1 start =
  let edges = relationsFromAtom start
  in [ RankedPath (PathProof [e] (relTopic e)) (scorePath defaultFieldProfile [e])
     | e <- edges
     ]

-- | Length 2: start →rel1→ mid →rel2→ object.
-- Skips paths that revisit the start atom (no cycles).
findPathsLength2 :: AtomId -> [RankedPath]
findPathsLength2 start =
  let firstEdges = relationsFromAtom start
      extend e1 =
        let mid = relTo e1
            secondEdges = relationsFromAtom mid
            -- Skip cycles: don't go back to start
            validSecond = filter (\e2 -> relTo e2 /= start) secondEdges
        in [ RankedPath (PathProof [e1, e2] (relTopic e1))
                        (scorePath defaultFieldProfile [e1, e2])
           | e2 <- validSecond
           ]
  in concatMap extend firstEdges

-- | Length 3: start →rel1→ mid1 →rel2→ mid2 →rel3→ object.
findPathsLength3 :: AtomId -> [RankedPath]
findPathsLength3 start =
  let firstEdges = relationsFromAtom start
      extend2 e1 e2 =
        let mid2 = relTo e2
            thirdEdges = relationsFromAtom mid2
            -- Skip cycles: don't revisit start or mid1
            visited = [start, relTo e1]
            validThird = filter (\e3 -> relTo e3 `notElem` visited) thirdEdges
        in [ RankedPath (PathProof [e1, e2, e3] (relTopic e1))
                        (scorePath defaultFieldProfile [e1, e2, e3])
           | e3 <- validThird
           ]
      extend1 e1 =
        let mid1 = relTo e1
            secondEdges = relationsFromAtom mid1
            validSecond = filter (\e2 -> relTo e2 /= start) secondEdges
        in concatMap (extend2 e1) validSecond
  in concatMap extend1 firstEdges

-- ============================================================
-- Field bias
-- ============================================================

-- | Convert from full Field to FieldProfile.
-- This is the only coupling point between PathFinder and Self.Field.
fieldProfileFromField :: Double -> Double -> Double -> Double -> FieldProfile
fieldProfileFromField conf cf consolid reson =
  FieldProfile conf cf consolid reson

-- | Map a relation type to a bias score given the Field profile.
-- Higher = more relevant to the current Field state.
relationTypeBias :: FieldProfile -> RelationType -> Double
relationTypeBias fp rt =
  let conf    = fpConfidence fp
      cf      = fpCounterfactual fp
      consolid = fpConsolidation fp
      reson   = fpResonance fp
  in case rt of
    -- Confidence-favored: assertion, verification, claims
    RelClaims         -> conf * 0.8
    RelVerifiedBy     -> conf * 0.9
    RelMeans          -> conf * 0.6
    RelDenotes        -> conf * 0.5
    RelDetermines     -> conf * 0.7

    -- Counterfactual-favored: contrast, difference, negation
    RelDiffersFrom    -> cf * 0.9
    RelContrastsWith  -> cf * 0.8
    RelNotReducibleTo -> cf * 0.7
    RelIsNot          -> cf * 0.6
    RelNegates        -> cf * 0.8
    RelDestroys       -> cf * 0.5

    -- Consolidation-favored: structure, requirements, presupposes
    RelPresupposes    -> consolid * 0.7
    RelRequires       -> consolid * 0.8
    RelLimitedBy      -> consolid * 0.6
    RelStructures     -> consolid * 0.7
    RelIncludes       -> consolid * 0.5
    RelNecessaryFor   -> consolid * 0.6
    RelPrecedes       -> consolid * 0.4
    RelReliesOn       -> consolid * 0.5

    -- Resonance-favored: expression, signal, emotion
    RelSignals        -> reson * 0.8
    RelExpresses      -> reson * 0.7
    RelEvokes         -> reson * 0.6
    RelSays           -> reson * 0.5
    RelGives          -> reson * 0.5
    RelReveals        -> reson * 0.6
    RelPointsTo       -> reson * 0.5

    -- Transformation (Angst-adjacent): high stakes, change
    RelTransformsInto -> 0.4 * max cf reson
    RelTransforms     -> 0.4 * max consolid reson
    RelCreatedFrom    -> 0.3 * consolid

    -- Direction/action (Conatus-adjacent)
    RelDirectedAt     -> 0.4 * consolid
    RelOrientsToward  -> 0.3 * reson
    RelPrescribes     -> 0.4 * consolid
    RelBuiltThrough   -> 0.3 * consolid
    RelCapableOf      -> 0.3 * conf
    RelCanBe          -> 0.2
    RelMakes          -> 0.3
    RelRecognizes     -> 0.3 * reson
    RelUnifies        -> 0.3 * consolid
    RelConnects       -> 0.3 * consolid
    RelDependsOn      -> 0.3 * consolid
    RelSupports       -> 0.3 * consolid
    RelSets           -> 0.3 * consolid
    RelPreserves      -> 0.3 * consolid
    RelReconstructs   -> 0.3 * consolid
    RelIsA            -> 0.2
    RelNotJustCopies  -> 0.2

    -- Catch-all for any missing constructors
    _                 -> 0.2

-- | Score a path: sum of edge biases minus length penalty.
scorePath :: FieldProfile -> [Relation] -> PathScore
scorePath fp edges =
  let biasSum = sum (map (relationTypeBias fp . relType) edges)
      len = length edges
      penalty = fromIntegral len * 0.15  -- each extra edge costs 0.15
      total = biasSum - penalty
  in PathScore biasSum penalty total

-- ============================================================
-- Ranking and selection
-- ============================================================

-- | Rank paths by score (highest first). Deterministic: ties broken by
-- the first edge's original predicate text (alphabetical).
rankPaths :: [RankedPath] -> [RankedPath]
rankPaths = sortOn (\rp -> (Down (psTotal (rpScore rp)), relRuOriginal (head (ppEdges (rpProof rp)))))

-- | Select top-N paths after ranking and gate filtering.
selectTopPaths :: Int -> FieldProfile -> AtomId -> Int -> [RankedPath]
selectTopPaths n fp start maxLen =
  take n
  $ rankPaths
  $ [ RankedPath (rpProof rp) (scorePath fp (ppEdges (rpProof rp)))
    | rp <- findPathsFrom maxLen start
    , gvOverall (validatePath (rpProof rp))  -- gate filter
    ]

-- ============================================================
-- Composition: build a definition from paths
-- ============================================================

-- | Compose a definition for a topic: find top-N length-1 paths,
-- verbalize each, join with periods. Paths are filtered through gates.
composeDefinition :: FieldProfile -> Int -> AtomId -> Text
composeDefinition fp n topic =
  let paths = selectTopPaths n fp topic 1
      texts = map (verbalizePath . rpProof) paths
  in if null texts
       then ""
       else T.intercalate ". " texts <> "."

-- | Compose with explicit gate verdict for observability.
-- Returns (text, number of paths that passed gates, number rejected).
composeDefinitionWithGates :: FieldProfile -> Int -> AtomId -> (Text, Int, Int)
composeDefinitionWithGates fp n topic =
  let allPaths = findPathsFrom 1 topic
      (passed, rejected) = splitPaths allPaths
      ranked = rankPaths passed
      selected = take n ranked
      texts = map (verbalizePath . rpProof) selected
      text = if null texts then "" else T.intercalate ". " texts <> "."
  in (text, length passed, length rejected)
  where
    splitPaths rps =
      let results = map (\rp -> (rp, validatePath (rpProof rp))) rps
          p = [ rp | (rp, v) <- results, gvOverall v ]
          r = [ rp | (rp, v) <- results, not (gvOverall v) ]
      in (p, r)

-- ============================================================
-- Path verbalization
-- ============================================================

-- | Verbalize a path proof into text.
-- Length 1: single predicate (e.g., "свобода предполагает возможность выбора")
-- Length 2: chained (e.g., "свобода ограничена ответственностью.
--           ответственность требует осознания последствий")
-- Length 3: deep chain.
verbalizePath :: PathProof -> Text
verbalizePath proof =
  T.intercalate ". " (map verbalizeRelation (ppEdges proof))
