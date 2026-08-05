{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Types
  ( SemanticEdge(..)
  , EdgeSource(..)
  , SemanticNetwork(..)
  , ActivationArtifact(..)
  , ActivationStep(..)
  , EdgeProvenance(..)
  , DomainTag(..)
  , EdgeNamespace(..)
  , EdgeRef
  , TemporalScope(..)
  , semanticEdge
  , emptySemanticNetwork
  , relationTypeWeight
  , calibrateRelationTypeWeight
  , sweepRelationTypeWeights
  , edgeRefOf
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.Text (Text)

import QxFx0.Types.Semantic.AtomGraph (RelationType(..))
import QxFx0.Types.Semantic.Network

-- | Build a lineage reference from a semantic edge.
-- Identity role: constructs a reference for lineage tracking.
-- Relation type absence defaults to 'RelRelatedTo' (legitimate unspecified kind).
-- Namespace absence defaults to 'NamespaceSessionLocal' (conservative minimum scope).
edgeRefOf :: SemanticEdge -> EdgeRef
edgeRefOf e =
  ( seFrom e
  , seTo e
  , fromMaybe RelRelatedTo (seRelationType e)
  , fromMaybe NamespaceSessionLocal (seNamespace e)
  )

-- | Convenience constructor for edges that do not carry rich relation
-- semantics. Optional fields are left empty, confidence is 1.0, and
-- provenance is inferred from the edge source.
semanticEdge :: Text -> Text -> Double -> Int -> EdgeSource -> SemanticEdge
semanticEdge from to weight cooc source =
  SemanticEdge from to weight cooc source Nothing Nothing Nothing Nothing Nothing 1.0 provenance Nothing Nothing Nothing Nothing
  where
    provenance = case source of
      ExplicitEdge  -> ProvenanceCorpus
      SubstrateEdge -> ProvenanceSubstrate

emptySemanticNetwork :: SemanticNetwork
emptySemanticNetwork = SemanticNetwork
  { snNodes = S.empty
  , snEdges = M.empty
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = Seq.empty
  }

-- | Calibrate a relation-type weight from corpus statistics.
--
-- Takes a map of observed counts per relation type (for example,
-- co-occurrence counts from successful turns) and returns a weight in
-- the range @[0.3, 1.0]@. High-count types are boosted; low-count types
-- are reduced. Types not present in the statistics map receive the
-- default weight 0.5. When all observed counts are identical the
-- midpoint weight 0.65 is returned.
calibrateRelationTypeWeight :: Map RelationType Double -> RelationType -> Double
calibrateRelationTypeWeight stats rt =
  case M.lookup rt stats of
    Nothing -> 0.5
    Just count ->
      let counts = M.elems stats
          minC   = minimum counts
          maxC   = maximum counts
      in if minC == maxC
           then 0.65
           else 0.3 + (count - minC) / (maxC - minC) * 0.7

-- | Normalize a list of per-type counts into weights in @[0.0, 1.0]@.
--
-- The lowest count maps to 0.0, the highest to 1.0, and all others are
-- placed linearly in between. When all counts are identical every type
-- receives 0.5. An empty list yields an empty map.
sweepRelationTypeWeights :: [(RelationType, Double)] -> Map RelationType Double
sweepRelationTypeWeights pairs =
  let countsMap = M.fromList pairs
      counts    = M.elems countsMap
  in case counts of
       [] -> M.empty
       _  ->
         let minC = minimum counts
             maxC = maximum counts
         in if minC == maxC
              then M.map (const 0.5) countsMap
              else M.map (\c -> (c - minC) / (maxC - minC)) countsMap

-- | Base weight for a 'RelationType' in the range @[0.1, 1.0]@.
-- Hierarchical and strong relations receive the highest weights;
-- causal links are slightly lower; contrast/negation relations are
-- moderate; weak associative relations are lower still. Any relation
-- type not explicitly mapped defaults to 0.5.
relationTypeWeight :: RelationType -> Double
relationTypeWeight rt = case rt of
  -- Hierarchical / strong relations
  RelIsA            -> 1.0
  RelRequires       -> 0.95
  RelDetermines     -> 0.95
  RelPresupposes    -> 1.0
  -- Causal / strong links
  RelEvokes         -> 0.85
  RelDependsOn      -> 0.8
  RelNecessaryFor   -> 0.9
  -- Contrast / negation
  RelNegates        -> 0.7
  RelContrastsWith  -> 0.7
  RelIsNot          -> 0.7
  RelNotReducibleTo -> 0.75
  -- Weak / associative
  RelRelatedTo      -> 0.45
  RelCanBe          -> 0.4
  RelCapableOf      -> 0.4
  -- Default for all remaining relation types
  _                 -> 0.5
