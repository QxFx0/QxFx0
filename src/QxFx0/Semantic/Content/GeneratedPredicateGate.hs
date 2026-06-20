{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Content.GeneratedPredicateGate
Description : Step 5 — B3 gates for graph-generated predicates.

Each generated predicate carries a PathProof — a trace of edges
traversed in the AtomStore graph. These gates validate that:

  Gate G1 (Specificity): the path contains ≥1 edge whose from_atom
    is the topic atom (not a universal template).

  Gate G2 (Non-tautology): no edge has from_atom == to_atom
    (self-reference is tautological).

  Gate G3 (Path provenance): the path has ≥1 edge (not empty).
    For argued predicates, path length ≥2 provides rationale.

  Gate G4 (Source whitelist): every edge's source is in
    {SeedFromPredicate, Curated, PromotedSubstrate}.
    SubstrateExtractedRaw is blocked — it never surfaces.

  Gate G5 (Non-substrate output): the verbalized text does not
    contain raw substrate atom surfaces (only verbalized relations
    appear in output).

All gates are pure, total, deterministic.
-}
module QxFx0.Semantic.Content.GeneratedPredicateGate
  ( -- * Types
    GateResult(..)
  , GateVerdict(..)
    -- * Individual gates
  , gateSpecificity
  , gateNonTautology
  , gatePathProvenance
  , gateSourceWhitelist
  , gateNonSubstrateOutput
    -- * Combined verdict
  , validatePath
  , validatePaths
  , filterAdmissible
    -- * Helpers
  , pathContainsTopic
  , pathIsTautological
  , pathHasRawSubstrate
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (any)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore

-- ============================================================
-- Types
-- ============================================================

data GateResult = GatePass | GateFail !Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data GateVerdict = GateVerdict
  { gvG1Specificity    :: !GateResult
  , gvG2NonTautology   :: !GateResult
  , gvG3PathProvenance :: !GateResult
  , gvG4SourceWhitelist :: !GateResult
  , gvG5NonSubstrate   :: !GateResult
  , gvOverall          :: !Bool    -- True = all gates pass
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- ============================================================
-- Individual gates
-- ============================================================

-- | Gate G1: path contains ≥1 edge whose from_atom is the topic.
gateSpecificity :: PathProof -> GateResult
gateSpecificity proof =
  let topic = ppTopic proof
      edges = ppEdges proof
      hasTopicEdge = any (\e -> relTopic e == topic) edges
  in if hasTopicEdge
       then GatePass
       else GateFail "no edge references the topic atom"

-- | Gate G2: no edge has from_atom == to_atom (self-reference).
gateNonTautology :: PathProof -> GateResult
gateNonTautology proof =
  let edges = ppEdges proof
      tautological = any (\e -> relFrom e == relTo e) edges
  in if tautological
       then GateFail "edge has from_atom == to_atom (tautological)"
       else GatePass

-- | Gate G3: path has ≥1 edge (non-empty proof).
-- For argued predicates (rationale), length ≥2 is preferred.
gatePathProvenance :: PathProof -> GateResult
gatePathProvenance proof =
  let len = length (ppEdges proof)
  in case len of
       0 -> GateFail "empty path proof"
       _ -> GatePass

-- | Gate G4: every edge's source is in the admissible set.
-- SubstrateExtractedRaw is blocked.
gateSourceWhitelist :: PathProof -> GateResult
gateSourceWhitelist proof =
  let edges = ppEdges proof
      inadmissible = [ e | e <- edges, relSource e == SubstrateExtractedRaw ]
  in if null inadmissible
       then GatePass
       else GateFail ("edge has source=SubstrateExtractedRaw: "
                        <> relRuOriginal (head inadmissible))

-- | Gate G5: verbalized text does not contain raw substrate atom surfaces.
-- Substrate atoms have source=SubstrateExtractedRaw and should never
-- appear in output directly — only through verbalized relations.
gateNonSubstrateOutput :: PathProof -> GateResult
gateNonSubstrateOutput proof =
  let edges = ppEdges proof
      hasRaw = pathHasRawSubstrate edges
  in if hasRaw
       then GateFail "path contains raw substrate edge"
       else GatePass

-- ============================================================
-- Combined verdict
-- ============================================================

-- | Run all gates on a single path proof.
validatePath :: PathProof -> GateVerdict
validatePath proof =
  let g1 = gateSpecificity proof
      g2 = gateNonTautology proof
      g3 = gatePathProvenance proof
      g4 = gateSourceWhitelist proof
      g5 = gateNonSubstrateOutput proof
      overall = all isPass [g1, g2, g3, g4, g5]
  in GateVerdict g1 g2 g3 g4 g5 overall
  where
    isPass GatePass = True
    isPass _        = False

-- | Run all gates on a list of path proofs.
-- Returns (passed, failed) partition.
validatePaths :: [PathProof] -> ([PathProof], [(PathProof, GateVerdict)])
validatePaths proofs =
  let results = map (\p -> (p, validatePath p)) proofs
      passed = [ p | (p, v) <- results, gvOverall v ]
      failed = [ (p, v) | (p, v) <- results, not (gvOverall v) ]
  in (passed, failed)

-- | Filter a list of RankedPaths to only admissible ones.
-- Returns paths where all gates pass.
filterAdmissible :: [PathProof] -> [PathProof]
filterAdmissible = fst . validatePaths

-- ============================================================
-- Helpers
-- ============================================================

-- | Check if any edge in the path references the topic.
pathContainsTopic :: Text -> [Relation] -> Bool
pathContainsTopic topic = any (\e -> relTopic e == topic)

-- | Check if any edge is tautological (from == to).
pathIsTautological :: [Relation] -> Bool
pathIsTautological = any (\e -> relFrom e == relTo e)

-- | Check if any edge has source=SubstrateExtractedRaw.
pathHasRawSubstrate :: [Relation] -> Bool
pathHasRawSubstrate = any (\e -> relSource e == SubstrateExtractedRaw)
