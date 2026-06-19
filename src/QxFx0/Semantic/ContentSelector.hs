{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.ContentSelector
  ( module QxFx0.Semantic.ContentSelector.Types
  , buildContentSelector
  , selectPredicates
  , composePredicates
  , composeFromActivation
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
import QxFx0.Semantic.Network (SemanticNetwork(..), activateTopic, getActivatedAtoms)
import QxFx0.Semantic.ContentSelector.Types
import QxFx0.Semantic.Content (SemanticPredicate(..))
import QxFx0.Self.Field (Field(..), Resonance(..), Atmosphere(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))

buildContentSelector :: SemanticSpace -> Map Text (Set Text) -> Map Text [SemanticPredicate] -> Map Text Text -> ContentSelector
buildContentSelector space atoms predicates lemmaMap = ContentSelector space atoms predicates lemmaMap

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

composeFromActivation :: ContentSelector -> Field -> Text -> SemanticNetwork -> [SemanticPredicate]
composeFromActivation cs field topic network =
  let topicAtoms = M.findWithDefault S.empty topic (csTopicAtoms cs)
      activatedNetwork = activateTopic topicAtoms network
      activatedAtoms = S.fromList (map fst (getActivatedAtoms activatedNetwork))
      overlappingTopics = M.keys (M.filter (not . S.null . S.intersection activatedAtoms) (csTopicAtoms cs))
      perTopicPreds = mapMaybe (\t ->
        case M.lookup t (csTopicPredicates cs) of
          Nothing -> Nothing
          Just preds ->
            let scored = mapMaybe (scorePred field (csSpace cs) (csLemmaMap cs) (Just activatedNetwork)) preds
            in case scored of
                 [] -> Nothing
                 _ -> let (bestPred, _) = maximumBy (comparing snd) scored
                      in Just (t, bestPred)
        ) overlappingTopics
      totalActivation = sum [snd a | a <- getActivatedAtoms activatedNetwork]
      weightedPreds = map (\(t, p) ->
        let topicAct = sum [snd a | a <- getActivatedAtoms activatedNetwork
                                   , S.member (fst a) (M.findWithDefault S.empty t (csTopicAtoms cs))]
            weight = if totalActivation > 0 then topicAct / totalActivation else 0.0
        in (p, weight)
        ) perTopicPreds
      sortedPreds = sortBy (comparing (Down . snd)) weightedPreds
  in map fst (take 3 sortedPreds)
