{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Assembly
Description : canonical — the system's own meaning assemblies (v1 skeleton).

An 'Assembly' composes two 'PredicateTerm's ('QxFx0.Semantic.Composition')
through a shared bridge concept.  This is the assembly unit the operator
chose (COMPOSER_DESIGN.md decision 1): the head-concept of one term plus both relation sets
both, provenance of the pair.

Status (2026-09-17): SHADOW ONLY.  No runtime calls 'assemblePair';
'selectPredicates' and the plan builders are untouched.  Wiring needs a
'selectorMathVersion' bump plus a corpus win on human-labelled
'assembly_pairs' (decision: 'assembly_coherent' + 'assembly_grounded',
no hop cap — rating decides, decision 2–3).

Bridge rule (total, deterministic): assemble iff the source terms share
a concept AND differ (same topic + equal term is rejected, the G2
non-tautology analogue).  No shared concept means 'Nothing' — no bridge
is invented.  Network BFS and 'PathProof' wiring are the next phase;
the skeleton records 'asmPathLen = 1' (shared atom) and never bypasses
'GeneratedPredicateGate.validatePath'.

Prose is deliberately NOT produced here: 'assemblyProposition' exposes
head-concept + relation pairs in lemma form; inflection belongs to the
shim\/realizer phase.  Any assembly surface is non-corpus by
construction, so 'isCorpusPredicate' is False and the landed
honest-generation framing («Гипотеза:») applies automatically.
-}
module QxFx0.Semantic.Assembly
  ( -- * Assembly
    Assembly(..)
  , assemblePair
    -- * Proposition view (lemma form, no prose)
  , assemblyProposition
  , assemblyConcepts
    -- * Diagnostics
  , assemblySourceOverlap
    -- * Rating labels (schema reference)
  , assemblyRatingLabels
  ) where

import Control.DeepSeq (NFData)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Semantic.Composition
  ( PredicateTerm(..)
  , jaccardBaseline
  )

-- | A composed meaning: the term, its two sources, the bridge.
data Assembly = Assembly
  { asmTerm    :: !PredicateTerm
    -- ^ Composed term: head-concept of A (B's if A headless), union of
    -- relations\/modifiers, negation OR (never silently affirm a
    -- negated source; over-negation bias is calibration-open).
  , asmSources :: ![(Text, Text)]
    -- ^ Exactly two (topic, surface) provenance pairs.
  , asmBridge  :: !Text
    -- ^ The shared concept that licenses the composition.
  , asmPathLen :: !Int
    -- ^ Skeleton: always 1 (shared atom).  Network BFS fills real
    -- lengths in the wiring phase; no cap is imposed (rating decides).
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Rating labels for the future 'assembly_pairs' corpus stratum.
-- Two labels per operator decision 2; each in {0,1,2}.
assemblyRatingLabels :: [Text]
assemblyRatingLabels = ["assembly_coherent", "assembly_grounded"]

-- | All concepts of a term: head-concept + relation verbs\/objects + modifiers.
assemblyConcepts :: PredicateTerm -> Set Text
assemblyConcepts t =
  S.fromList ([h | Just h <- [ptHead t]]
              ++ [v | (v, _) <- S.toList (ptRels t)]
              ++ [o | (_, o) <- S.toList (ptRels t)]
              ++ S.toList (ptMods t))

-- | Compose two sourced terms through a shared bridge concept.
-- Total: 'Nothing' when there is no bridge or the sources are
-- identical (same topic and equal term).  Deterministic: the bridge
-- is the lexicographically smallest shared concept.
assemblePair
  :: (Text, Text, PredicateTerm)
  -- ^ (topic, surface, term) of source A (head-concept donor)
  -> (Text, Text, PredicateTerm)
  -- ^ (topic, surface, term) of source B
  -> Maybe Assembly
assemblePair (topicA, surfaceA, termA) (topicB, surfaceB, termB)
  | topicA == topicB && termA == termB = Nothing
  | S.null shared = Nothing
  | otherwise =
      let bridge = S.findMin shared
          composed = PredicateTerm
            { ptHead = case ptHead termA of
                         Just h  -> Just h
                         Nothing -> ptHead termB
            , ptRels = S.union (ptRels termA) (ptRels termB)
            , ptMods = S.union (ptMods termA) (ptMods termB)
            , ptNeg  = ptNeg termA || ptNeg termB
            }
      in Just Assembly
           { asmTerm    = composed
           , asmSources = [(topicA, surfaceA), (topicB, surfaceB)]
           , asmBridge  = bridge
           , asmPathLen = 1
           }
  where
    shared = S.intersection (assemblyConcepts termA) (assemblyConcepts termB)

-- | Structured proposition view: head-concept + relation pairs in lemma form.
-- Not prose: inflection happens in the realizer phase.
assemblyProposition :: Assembly -> (Maybe Text, [(Text, Text)])
assemblyProposition asm =
  (ptHead (asmTerm asm), S.toList (ptRels (asmTerm asm)))

-- | Structural self-check used by tests: an assembly must stay close
-- to both sources (shared bridge guarantees overlap, but the union
-- can dilute — this quotes the dilution on the Jaccard baseline).
assemblySourceOverlap :: Assembly -> PredicateTerm -> PredicateTerm -> (Double, Double)
assemblySourceOverlap asm termA termB =
  ( jaccardBaseline (asmTerm asm) termA
  , jaccardBaseline (asmTerm asm) termB
  )
