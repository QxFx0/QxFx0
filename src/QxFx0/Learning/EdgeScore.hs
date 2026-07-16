{-# LANGUAGE DerivingStrategies #-}

-- | Multi-factor edge scoring for autonomous and runtime learning.
--
-- Replaces the previous uniform heuristic @relationTypeWeight * 0.6@ with a
-- composite score that reflects LLM confidence, source authority, semantic
-- similarity of endpoints, co-occurrence reinforcement, and explicit human
-- validation. The score is capped at 1.0 to keep it compatible with existing
-- weight thresholds across the semantic network.
module QxFx0.Learning.EdgeScore
  ( EdgeScore(..)
  , defaultEdgeScore
  , computeWeight
  , authorityRankDouble
  ) where

import QxFx0.Semantic.Content.AtomStore (RelationType)
import QxFx0.Semantic.Network.Types (EdgeProvenance(..), relationTypeWeight)

-- | Factors that contribute to a 'SemanticEdge' weight.
data EdgeScore = EdgeScore
  { esRelationTypeWeight :: !Double
    -- ^ Base weight determined by the relation type (e.g. presupposition vs
    -- contrast). See 'relationTypeWeight' for canonical values.
  , esLLMConfidence      :: !Double
    -- ^ Normalised confidence reported by the LLM, range [0,1].
  , esSourceAuthority    :: !Double
    -- ^ Authority of the provenance, range [0,1].
  , esSemanticSimilarity :: !Double
    -- ^ Semantic overlap between edge endpoints and seeded ontology, range [0,1].
  , esCoOccurrenceBoost  :: !Double
    -- ^ Additional weight contributed by repeated co-occurrence (e.g. 0.05 per
    -- reinforcement), non-negative.
  , esHumanValidated     :: !Bool
    -- ^ True if the edge was admitted from an explicit human correction.
  }
  deriving stock (Eq, Show)

-- | Convert an 'EdgeProvenance' to an authority score in [0,1].
-- Human corrections are treated as the most authoritative source, followed by
-- curated/self-play edges, then runtime/corpus edges.
authorityRankDouble :: EdgeProvenance -> Double
authorityRankDouble ProvenanceHumanCorrection  = 1.0
authorityRankDouble ProvenanceCurated          = 0.95
authorityRankDouble ProvenanceIngested         = 0.6
authorityRankDouble ProvenanceSelfPlay         = 0.6
authorityRankDouble ProvenanceDerived          = 0.7
authorityRankDouble ProvenanceDialogueFeedback = 0.5
authorityRankDouble ProvenanceRuntimeLLM       = 0.55
authorityRankDouble ProvenanceCorpus           = 0.45
authorityRankDouble ProvenanceSubstrate        = 0.35

-- | Build a default score for an LLM-discovered edge.
defaultEdgeScore :: RelationType -> EdgeProvenance -> EdgeScore
defaultEdgeScore rt prov = EdgeScore
  { esRelationTypeWeight = relationTypeWeight rt
  , esLLMConfidence      = 0.6
  , esSourceAuthority    = authorityRankDouble prov
  , esSemanticSimilarity = 0.7
  , esCoOccurrenceBoost  = 0.0
  , esHumanValidated     = prov == ProvenanceHumanCorrection
  }

-- | Combine all factors into a final edge weight in [0,1].
--
-- The formula is intentionally simple and deterministic:
--   weight = min 1.0 (typeWeight * llmConfidence * authority * similarity *
--                     (1 + coOccurrenceBoost) * humanBoost)
computeWeight :: EdgeScore -> Double
computeWeight es =
  let base  = esRelationTypeWeight es * esLLMConfidence es
      auth  = esSourceAuthority es
      sim   = esSemanticSimilarity es
      cooc  = 1.0 + esCoOccurrenceBoost es
      human = if esHumanValidated es then 1.2 else 1.0
  in min 1.0 (base * auth * sim * cooc * human)
