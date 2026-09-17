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
    -- * Graph wiring (PathFinder + gate, v4)
  , assembleViaGraph
    -- * Relation-type verb map (frozen v1)
  , relTypeVerb
    -- * Selection endorsement (selector math v5)
  , assemblyEndorsementBonus
  , endorseComposition
    -- * Verbalization (v1, hypothesis-marked)
  , verbalizeAssembly
    -- * Utterance selection (render phase)
  , utterableAssembly
    -- * Rating labels (schema reference)
  , assemblyRatingLabels
  ) where

import Control.DeepSeq (NFData)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import qualified Data.List as L
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Ord (comparing)

import QxFx0.Semantic.Composition
  ( PredicateTerm(..)
  , jaccardBaseline
  , parsePredicateTerm
  )
import QxFx0.Semantic.Content.PathFinder
  ( AtomGraph
  , RankedPath(..)
  , PathScore(..)
  , findPathsFrom
  )
import QxFx0.Semantic.Content.GeneratedPredicateGate
  ( validatePath
  , GateVerdict(..)
  )
import QxFx0.Types.Semantic.AtomGraph
  ( AtomId(..)
  , PathProof(..)
  , Relation(..)
  , RelationType(..)
  )
import QxFx0.Types.Semantic.ContentSelector (ContentSelector(..))
import QxFx0.Types.Semantic.Content (SemanticPredicate(..))

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

-- ---------------------------------------------------------------------------
-- Graph wiring (selector math v4)
-- ---------------------------------------------------------------------------

-- | Compose through the atom graph: the skeleton shared-concept bridge
-- is still required, and additionally at least one 'PathFinder' path
-- (up to 3 edges, the API cap — rating decides quality within it,
-- decision 3) must run from A's atoms into B's atoms AND pass
-- 'validatePath' (G1–G5, source whitelist included).  The gate is
-- never bypassed: an unvalidated path yields no assembly, however
-- tempting the term-level bridge.
--
-- Results are ranked by (path length, path score) and capped at 4.
-- Pure, total, deterministic.
--
-- Two bridge kinds (operator decision 3: no hop cap imposed by the
-- composer; 'findPathsFrom' contributes up to 3 edges and rating
-- decides quality within that):
--
-- * direct: the skeleton shared-concept bridge; the atom-graph path
--   only has to reach B's atoms (it certifies the topics connect);
-- * mediated: no shared concept — instead a validated path runs from
--   a concept of A to a concept of B, and the path edges contribute
--   their (verb, object) pairs to the composed term.  This is genuine
--   multi-hop composition, still gated end to end.
assembleViaGraph
  :: AtomGraph
  -> Set Text
  -- ^ Atoms of topic A (lemmas; lowercased variants tried as well).
  -> Set Text
  -- ^ Atoms of topic B.
  -> (Text, Text, PredicateTerm)
  -- ^ Sourced term A (head donor).
  -> (Text, Text, PredicateTerm)
  -- ^ Sourced term B.
  -> [(Assembly, PathProof, Double)]
assembleViaGraph graph atomsA atomsB srcA@(topicA, surfaceA, termA) srcB@(topicB, surfaceB, termB) =
  take 4 (L.sortBy (comparing (\(_, proof, s) -> (length (ppEdges proof), negate s)))
    (direct ++ mediated))
  where
    starts = take 8 (L.sort (S.toList (S.fromList
      [ AtomId a | x <- S.toList atomsA, a <- [x, T.toLower x] ])))
    lowersB = S.fromList
      [ b | x <- S.toList atomsB, b <- [x, T.toLower x] ]
    -- Perf bound (documented, not a quality gate): shortest paths
    -- first, bounded per start; the graph is finite and small.
    allPaths = concatMap (take 40 . findPathsFrom graph 3) starts
    admittedPaths =
      [ (rpProof p, psTotal (rpScore p))
      | p <- allPaths
      , gvOverall (validatePath (rpProof p))
      ]
    -- Direct: skeleton bridge + any validated path reaching B.
    direct =
      case assemblePair srcA srcB of
        Nothing -> []
        Just asm ->
          [ (asm, proof, s)
          | (proof, s) <- admittedPaths
          , pathReaches lowersB proof
          ]
    -- Mediated: validated path from a concept of A to a concept of B.
    mediated =
      [ ( Assembly
            { asmTerm = PredicateTerm
                { ptHead = case ptHead termA of
                             Just h  -> Just h
                             Nothing -> ptHead termB
                , ptRels = S.unions
                    [ ptRels termA
                    , ptRels termB
                    , S.fromList
                        [ (v, o)
                        | e <- ppEdges proof
                        , let v = fromMaybe (relTypeVerb (relType e)) (relVerbText e)
                        , let o = relObjectText e
                        , not (T.null v) && not (T.null o)
                        ]
                    ]
                , ptMods = S.union (ptMods termA) (ptMods termB)
                , ptNeg  = ptNeg termA || ptNeg termB
                }
            , asmSources = [(topicA, surfaceA), (topicB, surfaceB)]
            , asmBridge = cA <> "\8594" <> cB
            , asmPathLen = length (ppEdges proof)
            }
        , proof, s )
      | cA <- L.sort (S.toList (assemblyConcepts termA))
      , cB <- L.sort (S.toList (assemblyConcepts termB))
      , cA /= cB
      , (proof, s) <- pathsBetween cA cB
      ]
    pathsBetween cA cB =
      take 1
        [ (proof, s)
        | start <- [AtomId cA, AtomId (T.toLower cA)]
        , p <- take 40 (findPathsFrom graph 3 start)
        , let proof = rpProof p
        , gvOverall (validatePath proof)
        , pathReaches (S.fromList [cB, T.toLower cB]) proof
        -- The mediated path must still land in topic B's atoms:
        -- reaching the bare concept is not enough.
        , pathReaches lowersB proof
        , let s = psTotal (rpScore p)
        ]
    pathReaches targets proof =
      any (\(AtomId t) -> t `S.member` targets || T.toLower t `S.member` targets)
          [ relTo e | e <- ppEdges proof ]

-- ---------------------------------------------------------------------------
-- Relation-type verb map (frozen v1)
-- ---------------------------------------------------------------------------

-- | Seed path edges leave 'relVerbText' empty (the @rel@ helper), so
-- mediated assemblies would carry relations without verbs.  This total
-- frozen map fills the gap ONLY inside assembly composition — seed
-- data, verbalizers and GF paths are untouched (zero effect on
-- existing surfaces).  Extension is a math-version change, same
-- discipline as 'relationLexicon'.
relTypeVerb :: RelationType -> Text
relTypeVerb relType = case relType of
  RelPresupposes    -> "предполагать"
  RelLimitedBy      -> "ограничивать"
  RelRequires       -> "требовать"
  RelClaims         -> "утверждать"
  RelVerifiedBy     -> "подтверждать"
  RelSignals        -> "свидетельствовать"
  RelTransformsInto -> "превращать"
  RelExpresses      -> "выражать"
  RelDiffersFrom    -> "отличать"
  RelRelatedTo      -> "связывать"
  RelDirectedAt     -> "направлять"
  RelPreserves      -> "сохранять"
  RelOrientsToward  -> "ориентировать"
  RelPrescribes     -> "предписывать"
  RelBuiltThrough   -> "строить"
  RelDenotes        -> "обозначать"
  RelStructures     -> "структурировать"
  RelDetermines     -> "определять"
  RelTransforms     -> "преобразовывать"
  RelGives          -> "давать"
  RelReveals        -> "раскрывать"
  RelRecognizes     -> "признавать"
  RelUnifies        -> "объединять"
  RelConnects       -> "соединять"
  RelPrecedes       -> "предшествовать"
  RelDependsOn      -> "зависеть"
  RelIncludes       -> "включать"
  RelNecessaryFor   -> "требоваться"
  RelEvokes         -> "вызывать"
  RelMeans          -> "означать"
  RelSays           -> "говорить"
  RelNegates        -> "отрицать"
  RelContrastsWith  -> "противопоставлять"
  RelNotReducibleTo -> "не сводить"
  RelIsNot          -> "не являться"
  RelCapableOf      -> "мочь"
  RelCreatedFrom    -> "создавать"
  RelReliesOn       -> "опираться"
  RelCanBe          -> "мочь быть"
  RelDestroys       -> "разрушать"
  RelPointsTo       -> "указывать"
  RelMakes          -> "делать"
  RelIsA            -> "являться"
  RelReconstructs   -> "восстанавливать"
  RelSupports       -> "поддерживать"
  RelSets           -> "задавать"
  RelNotJustCopies  -> "не копировать"
  RelEnables        -> "позволять"
  RelCauses         -> "причинять"
  RelInfluences     -> "влиять"
  RelPartOf         -> "входить"
  RelOpposes        -> "противостоять"

-- ---------------------------------------------------------------------------
-- Selection endorsement (selector math v5)
-- ---------------------------------------------------------------------------

-- | Hand-set v1 endorsement bonus (calibration group 3 밝기; pinned in
-- @data\/calibration\/ranges.json@, codomain [0,1]).  An endorsed
-- topic's composition weight grows by this flat bonus, applied
-- max-once per topic — endorsement is a nudge, never a stacking
-- campaign.  Changing the default requires a math-version bump.
assemblyEndorsementBonus :: Double
assemblyEndorsementBonus = 0.15

-- | Boost composition weights for topics covered by a gate-passing
-- assembly with the query topic.  Runtime proxy of the human
-- coherent==2 verdict (calibration: R+L2 without coveredness —
-- precision 0.61, recall 1.00, zero incoherent admitted on 35 pairs):
-- the composed term carries non-empty relations AND the validated
-- path is at most 2 edges.  Topics without a query entry pass
-- through untouched.  Pure, total, deterministic.
endorseComposition
  :: AtomGraph
  -> ContentSelector
  -> Text
  -- ^ Query topic.
  -> [(Text, SemanticPredicate, Double, Double)]
  -- ^ (topic, predicate, score, weight) per-topic winners.
  -> [(Text, SemanticPredicate, Double, Double)]
endorseComposition graph cs queryTopic entries =
  case queryEntry of
    Nothing -> entries
    Just (qTopic, qPred, _qScore, _qWeight) ->
      let qTerm = parsePredicateTerm (csLemmaMap cs) (spRu qPred)
          qAtoms = atomsOf qTopic
          endorsedTopics = S.fromList
            [ t
            | (t, pred_, _s, _w) <- entries
            , t /= qTopic
            , let term = parsePredicateTerm (csLemmaMap cs) (spRu pred_)
            , (asm, proof, _score) <- assembleViaGraph graph
                qAtoms (atomsOf t)
                (qTopic, spRu qPred, qTerm) (t, spRu pred_, term)
            , gateAdmits proof (asmTerm asm)
            ]
      in [ if t `S.member` endorsedTopics || t == qTopic && not (S.null endorsedTopics)
             then (t, p, s, w + assemblyEndorsementBonus)
             else (t, p, s, w)
         | (t, p, s, w) <- entries ]
  where
    atomsOf t = M.findWithDefault S.empty t (csTopicAtoms cs)
    queryEntry = listToMaybe
      [ e | e@(t, _p, _s, _w) <- entries, t == queryTopic ]
    gateAdmits proof term =
      not (S.null (ptRels term)) && length (ppEdges proof) <= 2

-- ---------------------------------------------------------------------------
-- Verbalization (v1, hypothesis-marked)
-- ---------------------------------------------------------------------------

-- | Render an assembly as an explicit construction.  Deliberately NOT
-- fluent prose: verbs stay infinitive (no conjugation tables exist —
-- morphology is nouns-only) and both source surfaces are cited as
-- grounds.  Form: «{head} — {bridge}-связь: {verb} {obj}; …;
-- основания: {surfA} + {surfB}».  Fluency is the realizer's future
-- job; honesty (marked construction + cited grounds) is today's.
-- Total, deterministic.  Empty relations render as head + bridge only.
verbalizeAssembly :: Assembly -> Text
verbalizeAssembly asm =
  let (mHead, rels) = assemblyProposition asm
      (surfA, surfB) = case asmSources asm of
        [(_, a), (_, b)] -> (a, b)
        ss               -> case (listToMaybe ss, listToMaybe (reverse ss)) of
                              (Just (_, a), Just (_, b)) -> (a, b)
                              _                          -> ("", "")
      headPart = case mHead of
                   Just h  -> h
                   Nothing -> asmBridge asm
      relPart = case rels of
                  [] -> ""
                  _  -> ": " <> T.intercalate "; " [ v <> " " <> o | (v, o) <- rels ]
      bridgePart = " — " <> asmBridge asm <> "-связь"
  in headPart <> bridgePart <> relPart
       <> ". Основания: " <> surfA <> " + " <> surfB

-- ---------------------------------------------------------------------------
-- Utterance selection (render phase)
-- ---------------------------------------------------------------------------

-- | Top-1 utterable assembly over composed winners, R+L2-gated
-- (composed relations non-empty, validated path at most 2 edges —
-- the measured proxy of coherent==2 with zero incoherent admitted).
-- Returns 'Nothing' when no pair qualifies: silence over invention.
-- Pure, total, deterministic.  The caller renders the result through
-- 'verbalizeAssembly' under the landed hypothesis framing.
utterableAssembly
  :: AtomGraph
  -> ContentSelector
  -> Text
  -- ^ Query topic.
  -> [(Text, Text)]
  -- ^ Composed winners as (topic, surface) pairs.
  -> Maybe Assembly
utterableAssembly graph cs query pairs =
  let lemmaMap = csLemmaMap cs
      atomsOf t = M.findWithDefault S.empty t (csTopicAtoms cs)
      byTopic = M.toList (M.fromListWith (++)
        [ (t, [surf]) | (t, surf) <- pairs ])
      querySurfs = take 2 (concatMap snd (filter ((== query) . fst) byTopic))
      others = take 4
        [ (t, take 2 surfs)
        | (t, surfs) <- byTopic, t /= query ]
      attempt (surfA, surfB, other) =
        let termA = parsePredicateTerm lemmaMap surfA
            termB = parsePredicateTerm lemmaMap surfB
        in [ (asm, proof, score)
           | (asm, proof, score) <- assembleViaGraph graph
               (atomsOf query) (atomsOf other)
               (query, surfA, termA) (other, surfB, termB)
           , not (S.null (ptRels (asmTerm asm)))
           , length (ppEdges proof) <= 2
           ]
      ranked = L.sortBy (comparing (\(_, proof, s) -> (length (ppEdges proof), negate s)))
        [ r | surfA <- querySurfs, (other, surfsB) <- others
        , surfB <- surfsB, r <- attempt (surfA, surfB, other) ]
  in case ranked of
       ((asm, _proof, _score) : _) -> Just asm
       []                          -> Nothing
