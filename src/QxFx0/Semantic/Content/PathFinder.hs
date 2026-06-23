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
  , AtomGraph(..)
  , GeneratedSurface(..)
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
    -- * Verbalization
  , verbalizePath
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (sortOn, sortBy, groupBy, nubBy)
import Data.Maybe (fromMaybe, mapMaybe, isJust, isNothing)
import Data.Ord (comparing, Down(..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.Base (renderPredicateArgued, SemanticPredicate(..), PredicateRole(..), mkArguedPred)
import QxFx0.Semantic.Content.GeneratedPredicateGate (validatePath, GateVerdict(..))
import QxFx0.Lexicon.Inflection (instrumentalForm)
import QxFx0.Types (MorphologyData)
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

-- | Find all paths from an atom up to maxLen in a specific graph.
findPathsFrom :: AtomGraph -> Int -> AtomId -> [RankedPath]
findPathsFrom graph maxLen start =
  case maxLen of
    1 -> findPathsLength1 graph start
    2 -> findPathsLength1 graph start ++ findPathsLength2 graph start
    3 -> findPathsLength1 graph start ++ findPathsLength2 graph start ++ findPathsLength3 graph start
    _ -> findPathsLength1 graph start

-- | Length 1: start →rel→ object.
findPathsLength1 :: AtomGraph -> AtomId -> [RankedPath]
findPathsLength1 graph start =
  let edges = graphRelationsFromAtom graph start
  in [ RankedPath (PathProof [e] (relTopic e)) (scorePath defaultFieldProfile [e])
     | e <- edges
     ]

-- | Length 2: start →rel1→ mid →rel2→ object.
findPathsLength2 :: AtomGraph -> AtomId -> [RankedPath]
findPathsLength2 graph start =
  let firstEdges = graphRelationsFromAtom graph start
      extend e1 =
        let mid = relTo e1
            secondEdges = graphRelationsFromAtom graph mid
            validSecond = filter (\e2 -> relTo e2 /= start) secondEdges
        in [ RankedPath (PathProof [e1, e2] (relTopic e1))
                        (scorePath defaultFieldProfile [e1, e2])
           | e2 <- validSecond
           ]
  in concatMap extend firstEdges

-- | Length 3: start →rel1→ mid1 →rel2→ mid2 →rel3→ object.
findPathsLength3 :: AtomGraph -> AtomId -> [RankedPath]
findPathsLength3 graph start =
  let firstEdges = graphRelationsFromAtom graph start
      extend2 e1 e2 =
        let mid2 = relTo e2
            thirdEdges = graphRelationsFromAtom graph mid2
            visited = [start, relTo e1]
            validThird = filter (\e3 -> relTo e3 `notElem` visited) thirdEdges
        in [ RankedPath (PathProof [e1, e2, e3] (relTopic e1))
                        (scorePath defaultFieldProfile [e1, e2, e3])
           | e3 <- validThird
           ]
      extend1 e1 =
        let mid1 = relTo e1
            secondEdges = graphRelationsFromAtom graph mid1
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
-- Paths with relRationale get a bonus (they have real argumentation).
rankPaths :: [RankedPath] -> [RankedPath]
rankPaths = sortOn (\rp ->
  ( Down (psTotal (rpScore rp) + rationaleBonus rp)
  , case ppEdges (rpProof rp) of (e:_) -> relRuOriginal e; [] -> ""
  ))
  where
    rationaleBonus rp =
      case ppEdges (rpProof rp) of
        (e:_) -> if isJust (relRationale e) then 2.0 else 0.0
        [] -> 0.0

-- | Select top-N paths after ranking and gate filtering.
-- Prioritizes relations with relRationale (real argumentation) over
-- bare relations (no rationale = no "Потому что" = weaker answer).
selectTopPaths :: Int -> FieldProfile -> AtomGraph -> AtomId -> Int -> [RankedPath]
selectTopPaths n fp graph start maxLen =
  take n
  $ rankPaths
  $ [ RankedPath (rpProof rp) (scorePath fp (ppEdges (rpProof rp)))
    | rp <- findPathsFrom graph maxLen start
    , gvOverall (validatePath (rpProof rp))
    ]

-- ============================================================
-- Composition: build a definition from paths
-- ============================================================

-- | Compose a definition for a topic using a specific graph.
-- Returns GeneratedSurface with text, path proofs, and provenance.
composeDefinition :: MorphologyData -> FieldProfile -> Int -> AtomGraph -> AtomId -> GeneratedSurface
composeDefinition morph fp n graph topic =
  let paths = selectTopPaths n fp graph topic 1
      (texts, usedTexts) = composePredicatesDedup fp graph topic (concatMap (map relRuOriginal . ppEdges . rpProof) paths) paths
      firstEdges = case paths of (rp:_) -> ppEdges (rpProof rp); [] -> []
      counterPaths = findCounterPaths graph topic firstEdges
      counterText = case counterPaths of
        (rp3:_) -> verbalizePath (rpProof rp3)
        [] -> ""
      bestRationale = case texts of
        (t:_) -> extractRationale t
        [] -> ""
      synthesisText = buildSynthesis morph firstEdges bestRationale
      fullText = if null texts
        then ""
        else T.intercalate ". " texts
          <> (if T.null counterText then "" else ". Но " <> counterText)
          <> (if T.null synthesisText then "" else ". Именно поэтому " <> synthesisText)
          <> "."
      -- Collect all edges from all paths + counter for gate validation
      allProofs = map rpProof paths
                     ++ map rpProof counterPaths
      allEdges = concatMap ppEdges allProofs
      allSources = map relSource allEdges
      -- Validate all edges through gates
      AtomId topicText = topic
      combinedProof = PathProof allEdges topicText
      gateVerdict = validatePath combinedProof
  in if gvOverall gateVerdict
       then GeneratedSurface fullText allProofs allSources (fromIntegral (length allProofs))
       else GeneratedSurface "" [] [] 0

-- | Compose predicates with deduplication: track all used edge texts
-- and exclude them from subsequent rationale searches.
composePredicatesDedup :: FieldProfile -> AtomGraph -> AtomId -> [Text] -> [RankedPath] -> ([Text], [Text])
composePredicatesDedup fp graph topic initialUsed paths =
  go paths initialUsed []
  where
    go [] _ acc = (reverse acc, initialUsed)
    go (rp:rps) used acc =
      let (text, newUsed) = composeOneWithRationaleDedup fp graph topic used rp
      in go rps newUsed (text : acc)

composeOneWithRationaleDedup :: FieldProfile -> AtomGraph -> AtomId -> [Text] -> RankedPath -> (Text, [Text])
composeOneWithRationaleDedup fp graph topic usedTexts rp =
  let mainText = verbalizePath (rpProof rp)
      mainEdges = ppEdges (rpProof rp)
      mainEdgeTexts = map relRuOriginal mainEdges
      objAtom = case mainEdges of (e:_) -> relTo e; [] -> topic
      -- Exclude both already-used and current main edge texts
      excluded = usedTexts ++ mainEdgeTexts
      -- Find rationale: length-2 path from objAtom, excluding used edges
      objPaths = selectTopPaths 3 fp graph objAtom 2
      rationaleText = case [ verbalizePath (rpProof p)
                           | p <- objPaths
                           , not (any (\e -> relRuOriginal e `elem` excluded)
                                      (ppEdges (rpProof p)))
                           ] of
        (t:_) -> t
        [] -> ""
      -- Fallback: length-2 from topic, excluding used and main edges
      fallbackRationale = if T.null rationaleText
                            then case [ verbalizePath (rpProof p)
                                      | p <- selectTopPaths 5 fp graph topic 2
                                      , let firstEdge = case ppEdges (rpProof p) of (e:_) -> Just e; [] -> Nothing
                                      , firstEdge /= Nothing
                                      , case mainEdges of (m:_) -> Just m /= firstEdge; [] -> False
                                      , not (any (\e -> relRuOriginal e `elem` excluded)
                                                 (ppEdges (rpProof p)))
                                      ] of
                                   (t:_) -> t
                                   [] -> ""
                            else ""
      chosenRationale = if not (T.null rationaleText) then rationaleText
                        else fallbackRationale
      newText = mainText
        <> (if not (T.null chosenRationale) then ". Потому что " <> chosenRationale else "")
      -- Track all edge texts used in this predicate + rationale
      newUsed = usedTexts ++ mainEdgeTexts
                  ++ (if not (T.null chosenRationale)
                      then extractEdgeTexts chosenRationale
                      else [])
  in (newText, newUsed)

-- | Extract edge texts from a rationale string (heuristic: split by periods).
extractEdgeTexts :: Text -> [Text]
extractEdgeTexts text = filter (not . T.null) (T.splitOn ". " text)

-- | Extract rationale text from a composed predicate string.
-- Looks for "Потому что " segment.
extractRationale :: Text -> Text
extractRationale text =
  case T.breakOn "Потому что " text of
    (_, rest) | not (T.null rest) -> T.drop (T.length "Потому что ") rest
    _ -> ""

-- | Find counter-paths: relations from the topic that contrast with the main edge.
findCounterPaths :: AtomGraph -> AtomId -> [Relation] -> [RankedPath]
findCounterPaths graph topic mainEdges =
  let mainTypes = map relType mainEdges
      counterTypes = [RelContrastsWith, RelDiffersFrom, RelNotReducibleTo, RelIsNot, RelNegates]
      allRels = graphRelationsFromAtom graph topic
      -- Only keep edges that are NOT the same as main edges
      -- and are counter-typed
      counterRels = [ r | r <- allRels
                         , relType r `elem` counterTypes
                         , relRuOriginal r `notElem` map relRuOriginal mainEdges
                         ]
  in [ RankedPath (PathProof [r] (relTopic r))
                    (scorePath (FieldProfile 0.5 1.0 0.5 0.5) [r])
     | r <- counterRels
     ]

-- | Build synthesis text from the main edge and rationale.
-- Uses instrumental case for both topic and object via Lexicon.Inflection.
buildSynthesis :: MorphologyData -> [Relation] -> Text -> Text
buildSynthesis morph mainEdges rationale =
  case mainEdges of
    (e:_) ->
      let topicInstr = case M.lookup (relFrom e) atomStore of
            Just a  -> instrumentalForm morph (atomDisplay a)
            Nothing -> instrumentalForm morph (relTopic e)
          objInstr = case M.lookup (relTo e) atomStore of
            Just a | atomCategory a == CatTopic -> instrumentalForm morph (atomDisplay a)
            _ -> instrumentalForm morph (stripPreposition (relObjectText e))
      in if T.null rationale
           then ""
           else "различие между " <> topicInstr <> " и " <> objInstr <> " — в самой претензии"
    [] -> ""

-- | Strip leading preposition from object text.
-- "с ответственностью" → "ответственностью"
-- "на соответствие" → "соответствие"
-- "об угрозе" → "угрозе"
stripPreposition :: Text -> Text
stripPreposition text =
  let prepositions = ["с ", "со ", "на ", "об ", "от ", "к ", "из ", "через ", "для "]
      stripped = foldr (\prep acc -> if prep `T.isPrefixOf` T.toLower text
                                      then T.drop (T.length prep) text
                                      else acc) text prepositions
  in if stripped /= text then stripped else text


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
