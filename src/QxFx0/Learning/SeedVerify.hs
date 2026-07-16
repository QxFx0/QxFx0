{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Verify runtime-LLM discovered edges against a curated seed ontology.
--
-- The verification classifies each discovered edge as:
--
-- * 'SeedMatch'       — the seed already contains a compatible edge for the
--                       same @(from, to)@ pair; confidence/weight are boosted.
-- * 'SeedContradiction' — the seed contains an incompatible/contradictory edge;
--                       the discovered edge is quarantined (very low weight).
-- * 'SeedNovelty'     — no seed edge for the pair; admitted with reduced
--                       confidence until reinforced by feedback.
module QxFx0.Learning.SeedVerify
  ( SeedVerification(..)
  , verifyDiscoveredEdges
  , verifyEdgeAgainstSeed
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T

import QxFx0.Learning.EdgeScore (EdgeScore(..), defaultEdgeScore, computeWeight)
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , EdgeRef
  , EdgeNamespace(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )

-- | Result of verifying one discovered edge against the seed ontology.
data SeedVerification
  = SeedMatch
      { svConfidence :: !Double
      , svWeight     :: !Double
      , svSeedRef    :: ![EdgeRef]
      }
  | SeedContradiction
      { svConfidence :: !Double
      , svWeight     :: !Double
      , svSeedRef    :: ![EdgeRef]
      }
  | SeedNovelty
      { svConfidence :: !Double
      , svWeight     :: !Double
      , svSeedRef    :: ![EdgeRef]
      }
  deriving stock (Eq, Show)

-- | Positive / hierarchical relation types.  These are mutually compatible
-- for seed matching purposes.
positiveRelationTypes :: [RelationType]
positiveRelationTypes =
  [ RelIsA
  , RelRequires
  , RelNecessaryFor
  , RelPresupposes
  , RelDetermines
  , RelIncludes
  , RelPointsTo
  , RelClaims
  , RelVerifiedBy
  , RelSignals
  , RelExpresses
  , RelPreserves
  , RelOrientsToward
  , RelPrescribes
  , RelDenotes
  , RelStructures
  , RelTransforms
  , RelGives
  , RelReveals
  , RelRecognizes
  , RelUnifies
  , RelConnects
  , RelPrecedes
  , RelDependsOn
  , RelEvokes
  , RelMeans
  , RelSays
  , RelDirectedAt
  , RelMakes
  , RelSupports
  , RelSets
  ]

-- | Negative / contrastive relation types.  These contradict positive ones.
negativeRelationTypes :: [RelationType]
negativeRelationTypes =
  [ RelContrastsWith
  , RelNotReducibleTo
  , RelDiffersFrom
  , RelNegates
  , RelDestroys
  ]

isPositive :: RelationType -> Bool
isPositive rt = rt `elem` positiveRelationTypes

isNegative :: RelationType -> Bool
isNegative rt = rt `elem` negativeRelationTypes

-- | Compare two relation types for seed compatibility.
-- Same type is a strong match; two positive types are compatible;
-- mixed positive/negative is a contradiction; otherwise neutral/novelty.
relationCompatibility :: RelationType -> RelationType -> Maybe Bool
relationCompatibility a b
  | a == b = Just True
  | isPositive a && isPositive b = Just True
  | isNegative a && isNegative b = Just True
  | isPositive a && isNegative b = Just False
  | isNegative a && isPositive b = Just False
  | otherwise = Nothing  -- neutral: neither confirms nor contradicts

-- | Build a lineage reference back to a seed edge.
--
-- Identity role, not evaluation role: this reference is used to assert
-- "this discovered edge traces back to that specific seed edge," so it
-- must not manufacture a scope the seed edge never declared. Relation
-- type absence defaults to 'RelRelatedTo' (a legitimate "related, kind
-- unspecified" value — see AGENTS.md on relation-vs-scope defaulting).
-- Namespace absence is a genuine unknown and yields no reference at all:
-- refusing to point is safer than pointing at an invented scope.
seedRefFor :: SemanticEdge -> [EdgeRef]
seedRefFor seedEdge =
  case seNamespace seedEdge of
    Nothing -> []
    Just ns -> [(seFrom seedEdge, seTo seedEdge, maybe RelRelatedTo id (seRelationType seedEdge), ns)]

-- | Verify a single discovered edge against the curated seed network.
verifyEdgeAgainstSeed :: SemanticNetwork -> SemanticEdge -> SeedVerification
verifyEdgeAgainstSeed seed edge =
  let key = (seFrom edge, seTo edge)
      mSeedEdge = M.lookup key (snEdges seed)
  in case mSeedEdge of
       Nothing ->
         -- Novelty: reduce confidence until reinforced.
         SeedNovelty
           { svConfidence = 0.4
           , svWeight     = min 0.35 (seWeight edge)
           , svSeedRef    = []
           }
       Just seedEdge ->
         let discoveredRt = maybe RelRelatedTo id (seRelationType edge)
             seedRt       = maybe RelRelatedTo id (seRelationType seedEdge)
             -- Identity role: a lineage reference must be honest about what
             -- it points to. Relation type absence is a legitimate "relation
             -- exists, kind unspecified" value (defaulted to RelRelatedTo
             -- above). Scope absence is a genuine unknown about provenance
             -- and must not be silently widened to NamespaceGlobal — if the
             -- seed edge's scope is unknown, we refuse to build the
             -- reference rather than assert a scope that was never
             -- verified. See seedRefFor.
             ref = seedRefFor seedEdge
         in case relationCompatibility discoveredRt seedRt of
              Just True ->
                -- Match: boost confidence/weight.
                let conf = 0.85
                    score = (defaultEdgeScore discoveredRt ProvenanceRuntimeLLM)
                              { esLLMConfidence = conf
                              , esSemanticSimilarity = 0.9
                      }
                in SeedMatch
                     { svConfidence = conf
                     , svWeight     = computeWeight score
                     , svSeedRef    = ref
                     }
              Just False ->
                -- Contradiction: quarantine.
                SeedContradiction
                     { svConfidence = 0.1
                     , svWeight     = min 0.15 (seWeight edge)
                     , svSeedRef    = ref
                     }
              Nothing ->
                -- Neutral overlap: keep but do not boost.
                SeedNovelty
                  { svConfidence = seConfidence edge
                  , svWeight     = seWeight edge
                  , svSeedRef    = ref
                  }

-- | Verify all edges of a discovered network against the seed ontology and
-- return a new network with adjusted weights/confidences.
verifyDiscoveredEdges :: SemanticNetwork -> SemanticNetwork -> SemanticNetwork
verifyDiscoveredEdges seed discovered =
  let verifiedEdges = M.mapWithKey (\_ e -> applyVerification e (verifyEdgeAgainstSeed seed e)) (snEdges discovered)
      nodes = S.fromList (concatMap (\e -> [seFrom e, seTo e]) (M.elems verifiedEdges))
  in discovered
       { snNodes = nodes
       , snEdges = verifiedEdges
       }
  where
    applyVerification :: SemanticEdge -> SeedVerification -> SemanticEdge
    applyVerification edge sv =
      let refs = svSeedRef sv
      in edge
           { seConfidence = svConfidence sv
           , seWeight     = svWeight sv
           , seLineage    = if null refs then Nothing else Just refs
           }
