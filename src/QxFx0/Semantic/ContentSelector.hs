{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.ContentSelector
  ( module QxFx0.Semantic.ContentSelector.Types
  , buildContentSelector
  , selectPredicates
  , composePredicates
  , composeFromActivation
  , ontologyRelatedTopics
  , ontologyDepthBoost
  , buildTopicAtoms
  , tokenizePredicate
  , scorePred
  ) where

import Data.List (maximumBy, sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import Data.Ord (comparing, Down(..))
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import Data.Vector (Vector)
import qualified Data.Vector as V

import QxFx0.Semantic.Space (tokenizePredicate, SemanticSpace(..), FieldDimension(..), PredicateVector(..), computeFieldAffinity)
import QxFx0.Semantic.Network (SemanticNetwork(..), activateTopicWithField, getActivatedAtoms)
import QxFx0.Semantic.ContentSelector.Types
import QxFx0.Semantic.Content (SemanticPredicate(..))
import QxFx0.Semantic.Ontology (Ontology(..), OntologyNode(..), lookupOntologyNode, lookupSiblings, lookupChildren, lookupCategory)
import QxFx0.Self.Field (Field(..), FieldHeuristics(..), Resonance(..), Atmosphere(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))

buildContentSelector :: SemanticSpace -> Map Text (Set Text) -> Map Text [SemanticPredicate] -> Map Text Text -> Maybe Ontology -> ContentSelector
buildContentSelector space atoms predicates lemmaMap mOntology = ContentSelector space atoms predicates lemmaMap mOntology

selectPredicates :: ContentSelector -> Field -> Text -> Maybe SemanticNetwork -> [SelectedPredicate]
selectPredicates cs field topic mActivatedNetwork =
  case M.lookup topic (csTopicPredicates cs) of
    Nothing -> []
    Just preds ->
      let scored = mapMaybe (scorePred field (csSpace cs) (csLemmaMap cs) mActivatedNetwork) preds
      in case scored of
            [] -> []
            _  -> let (bestPred, bestScore) = maximumBy (comparing snd) scored
                  in [SelectedPredicate topic bestScore [bestPred]]

scorePred :: Field -> SemanticSpace -> Map Text Text -> Maybe SemanticNetwork -> SemanticPredicate -> Maybe (SemanticPredicate, Double)
scorePred field space lemmaMap mNetwork pred =
  let atoms = tokenizePredicate lemmaMap (spRu pred)
      pv = PredicateVector (spRu pred) atoms (buildVector space atoms)
      contribs = [(dim, computeFieldAffinity space dim pv) | dim <- [FdResonance .. FdCounterfactual]]
      baseScore = sum [fieldWeight field dim * s | (dim, s) <- contribs]
      activationBonus = case mNetwork of
        Just an -> let actMap = snActivation an
                       activatedAtoms = S.filter (\a -> M.member a actMap) atoms
                       totalAct = sum [M.findWithDefault 0.0 a actMap | a <- S.toList activatedAtoms]
                   in if S.null atoms then 0.0 else totalAct / fromIntegral (S.size atoms)
        Nothing -> 0.0
      adjustedScore = baseScore * (1.0 + 0.3 * activationBonus)
  in if adjustedScore > 0.1 then Just (pred, adjustedScore) else Nothing

buildVector :: SemanticSpace -> Set Text -> Vector Double
buildVector space atoms =
  let dimCount = ssDimensionCount space
      vec = V.replicate dimCount 0.0
  in foldl (\v atom ->
    case M.lookup atom (ssAtomIndex space) of
      Nothing -> v
      Just idx -> v V.// [(idx, 1.0)]
    ) vec (S.toList atoms)

fieldWeight :: Field -> FieldDimension -> Double
fieldWeight f dim = case dim of
  FdResonance      -> unResonance (fieldResonance f)
  FdAtmosphere     -> atmosphereValence (fieldAtmosphere f)
  FdConfidence     -> unFieldConfidence (fieldConfidence f)
  FdConsolidation  -> unConsolidation (fieldConsolidation f)
  FdCounterfactual -> unCounterfactual (fieldCounterfactual f)

buildTopicAtoms :: Map Text [Text] -> Map Text (Set Text)
buildTopicAtoms = M.map S.fromList

composePredicates :: ContentSelector -> Field -> [SemanticPredicate] -> Maybe SemanticNetwork -> [SemanticPredicate]
composePredicates cs field preds mNetwork =
  case preds of
    [] -> []
    [p] -> [p]
    _ ->
      let scored = mapMaybe (scorePred field (csSpace cs) (csLemmaMap cs) mNetwork) preds
          totalScore = sum (map snd scored)
      in if totalScore < 0.1
         then []
         else
           let threshold = totalScore * 0.3
               filtered = filter (\(_, s) -> s >= threshold) scored
           in map fst filtered

composeFromActivation :: ContentSelector -> Field -> FieldHeuristics -> Text -> SemanticNetwork -> [SemanticPredicate]
composeFromActivation cs field heuristics topic network =
  let topicAtoms = M.findWithDefault S.empty topic (csTopicAtoms cs)
      activatedNetwork = activateTopicWithField field topicAtoms network
      activatedAtoms = S.fromList (map fst (getActivatedAtoms activatedNetwork))
      overlappingTopics = M.keys (M.filter (not . S.null . S.intersection activatedAtoms) (csTopicAtoms cs))
      ontologyTopics = ontologyRelatedTopics cs topic
      candidateTopics = S.toList (S.fromList (overlappingTopics ++ ontologyTopics))
      perTopicPreds = mapMaybe (\t ->
        case M.lookup t (csTopicPredicates cs) of
          Nothing -> Nothing
          Just preds ->
            let scored = mapMaybe (scorePred field (csSpace cs) (csLemmaMap cs) (Just activatedNetwork)) preds
                depthBoost = ontologyDepthBoost cs heuristics t
                boosted = map (\(p, s) -> (p, s * (1.0 + depthBoost))) scored
            in case boosted of
                 [] -> Nothing
                 _ -> let (bestPred, _) = maximumBy (comparing snd) boosted
                      in Just (t, bestPred)
        ) candidateTopics
      totalActivation = sum [snd a | a <- getActivatedAtoms activatedNetwork]
      weightedPreds = map (\(t, p) ->
        let topicAct = sum [snd a | a <- getActivatedAtoms activatedNetwork
                                   , S.member (fst a) (M.findWithDefault S.empty t (csTopicAtoms cs))]
            weight = if totalActivation > 0 then topicAct / totalActivation else 0.0
        in (p, weight)
        ) perTopicPreds
      sortedPreds = sortBy (comparing (Down . snd)) weightedPreds
  in map fst (take 3 sortedPreds)

-- | Collect related topics from the ontology, if one is configured.
-- Returns siblings and children of the queried topic so that
-- 'composeFromActivation' can borrow predicates when the direct
-- topic has weak coverage.
ontologyRelatedTopics :: ContentSelector -> Text -> [Text]
ontologyRelatedTopics cs topic =
  case csOntology cs of
    Nothing -> []
    Just ont ->
      let siblings = lookupSiblings ont topic
          children = lookupChildren ont topic
      in siblings ++ children

-- | Compute the ontology depth boost for predicates from a given topic.
-- When 'fhOntologyDepthBoost' is @0.0@ the result is @0.0@ and scoring
-- is unchanged.  Otherwise deeper ontology nodes receive a larger
-- multiplier.
ontologyDepthBoost :: ContentSelector -> FieldHeuristics -> Text -> Double
ontologyDepthBoost cs heuristics topic =
  let base = fhOntologyDepthBoost heuristics
  in if base == 0.0
       then 0.0
       else case csOntology cs of
              Nothing -> 0.0
              Just ont -> case lookupOntologyNode ont topic of
                            Nothing -> 0.0
                            Just node -> base * fromIntegral (onDepth node)
