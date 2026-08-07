{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.ContentSelector
  ( module QxFx0.Semantic.ContentSelector.Types
  , buildContentSelector
  , selectPredicates
  , selectPredicatesWithDiagnostics
  , composePredicates
  , composeFromActivation
  , composeFromActivationWithDiagnostics
  , composeFromArtifactWithDiagnostics
  , buildSelectorActivationArtifact
  , predicateAtomsForSelector
  , ontologyRelatedTopics
  , ontologyDepthBoost
  , buildTopicAtoms
  , tokenizePredicate
  , scorePred
  , buildVector
  ) where

import Data.List (maximumBy, sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe, listToMaybe)
import Data.Ord (comparing, Down(..))
import Data.Set (Set)
import qualified Data.Set as S
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import Data.Vector (Vector)
import qualified Data.Vector as V

import QxFx0.Semantic.Space (tokenizePredicate, SemanticSpace(..), FieldDimension(..), PredicateVector(..), computeFieldAffinity)
import QxFx0.Semantic.Network (SemanticNetwork(..), activateTopicWithField, getActivatedAtoms, activateArtifact, ActivationArtifact(..), activationArtifactNetwork)
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
            [] -> [SelectedPredicate topic 0.0 [head preds]]
            _  -> let (bestPred, bestScore) = maximumBy (comparing snd) scored
                  in [SelectedPredicate topic bestScore [bestPred]]

-- | Same selection as 'selectPredicates', plus one diagnostic per candidate
-- predicate in the topic pool.  Diagnostics carry field affinity, activation
-- bonus, topic relevance, OOV atoms and the policy/math versions so that
-- gate evaluation and overlay audits can reconstruct why a predicate was
-- admitted or dropped.
selectPredicatesWithDiagnostics
  :: ContentSelector
  -> Field
  -> Text
  -> Maybe SemanticNetwork
  -> ([SelectedPredicate], [SelectorDiagnostic])
selectPredicatesWithDiagnostics cs field topic mActivatedNetwork =
  case M.lookup topic (csTopicPredicates cs) of
    Nothing -> ([], [])
    Just preds ->
      let detailed =
            [ (pred, atoms, baseScore, rawAffinity, bonus, adjustedScore)
            | pred <- preds
            , let atoms = tokenizePredicate (csLemmaMap cs) (spRu pred)
            , let pv = PredicateVector (spRu pred) atoms (buildVector (csSpace cs) atoms)
            , let contribs = [(dim, computeFieldAffinity (csSpace cs) dim pv) | dim <- [FdResonance .. FdCounterfactual]]
            , let rawAffinity = sum [s | (_, s) <- contribs]
            , let baseScore = sum [fieldWeight field dim * s | (dim, s) <- contribs]
            , let bonus = case mActivatedNetwork of
                            Just an ->
                              let actMap = snActivation an
                                  activatedAtoms = S.filter (\a -> M.member a actMap) atoms
                                  totalAct = sum [M.findWithDefault 0.0 a actMap | a <- S.toList activatedAtoms]
                              in if S.null atoms then 0.0 else totalAct / fromIntegral (S.size atoms)
                            Nothing -> 0.0
            , let adjustedScore = baseScore * (1.0 + 0.3 * bonus)
            ]
          qualified = [ (predicate, atoms, base, rawAffinity, bonus, adjustedScore)
                      | (predicate, atoms, base, rawAffinity, bonus, adjustedScore) <- detailed
                      , adjustedScore > 0.1
                      ]
          selection = case qualified of
            [] -> []
            _
              | (bestPred, _, _, _, _, bestScore) <-
                  maximumBy (comparing (\(_, _, _, _, _, s) -> s)) qualified
              -> [SelectedPredicate topic bestScore [bestPred]]
          primarySurface = case selection of
            (sel : _) -> case spPredicates sel of
              (p : _) -> Just (spRu p)
              []      -> Nothing
            _            -> Nothing
          primaryAtoms = case selection of
            (sel : _) -> case spPredicates sel of
              (p : _) -> tokenizePredicate (csLemmaMap cs) (spRu p)
              []      -> S.empty
            []            -> S.empty
          diagnostics = map (mkDiagnostic primarySurface primaryAtoms) detailed
      in (selection, diagnostics)
  where
    oovAtoms atoms = S.toList (S.filter (\a -> not (M.member a (ssAtomIndex (csSpace cs)))) atoms)
    mkDiagnostic primarySurface primaryAtoms
      (predicate, atoms, baseScore, rawAffinity, bonus, adjustedScore) =
        let surface = spRu predicate
            oov = oovAtoms atoms
            topicRelevance = if spTopicForm predicate == topic then 1.0 else 0.0
            isPrimaryEntry = Just surface == primarySurface
            isSecondaryEntry = not isPrimaryEntry && topicRelevance > 0.0
            marginalGain = if isSecondaryEntry
                             then let extra = S.size (S.difference atoms primaryAtoms)
                                      denom = S.size atoms
                                  in if denom == 0 then 0.0 else fromIntegral extra / fromIntegral denom
                             else 0.0
            reason = if isPrimaryEntry then "selected_primary"
                     else if isSecondaryEntry then "selected_secondary_semantic_gain"
                     else "below_semantic_threshold"
        in SelectorDiagnostic
             topic topic (Just surface) (Just adjustedScore) (isPrimaryEntry || isSecondaryEntry) reason
             (Just topicRelevance) (Just baseScore) (Just rawAffinity) (Just bonus)
             (Just 0.0) (Just oov) (Just marginalGain)
             (Just selectorPolicyVersion) (Just selectorMathVersion)

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

-- | Compute the atom set for a predicate's Russian surface using a lemma map.
-- Used to build topic-to-atom indexes for the selector overlay.
predicateAtomsForSelector :: Map Text Text -> SemanticPredicate -> Set Text
predicateAtomsForSelector lemmaMap pred = tokenizePredicate lemmaMap (spRu pred)

-- | Run activation for a set of topics and materialize an immutable
-- 'ActivationArtifact' (see 'activateArtifact' in 'QxFx0.Semantic.Network').
buildSelectorActivationArtifact :: ContentSelector -> Field -> [Text] -> SemanticNetwork -> ActivationArtifact
buildSelectorActivationArtifact cs field topics network =
  let topicAtoms = S.unions [M.findWithDefault S.empty t (csTopicAtoms cs) | t <- topics]
  in activateArtifact topics field topicAtoms network

-- | Diagnostics variant of 'composeFromActivation'.  When the topic exists in
-- the corpus but no route can be activated (no overlapping topic atoms and no
-- ontology siblings), a single surface-less diagnostic with reason
-- @topic_not_activated_or_ontology_related@ is emitted and selection is empty.
composeFromActivationWithDiagnostics
  :: ContentSelector
  -> Field
  -> FieldHeuristics
  -> Text
  -> SemanticNetwork
  -> ([SemanticPredicate], [SelectorDiagnostic])
composeFromActivationWithDiagnostics cs field heuristics topic network =
  let topicAtoms = M.findWithDefault S.empty topic (csTopicAtoms cs)
      activatedNetwork = activateTopicWithField field topicAtoms network
  in composeFromActivationSnapshot cs field heuristics topic (snActivation activatedNetwork)

-- | Shared composition core over an already-computed activation snapshot.
-- Candidate topics overlap the activated atoms; the best predicate per topic
-- is scored against a network view whose activation is the supplied map.
composeFromActivationSnapshot
  :: ContentSelector
  -> Field
  -> FieldHeuristics
  -> Text
  -> Map Text Double
  -> ([SemanticPredicate], [SelectorDiagnostic])
composeFromActivationSnapshot cs field heuristics topic actMap =
  let activatedAtoms = S.fromList
        [ a | (a, v) <- M.toList actMap, v > 0.05 ]
      overlapping =
        M.keys (M.filter (not . S.null . S.intersection activatedAtoms) (csTopicAtoms cs))
      ontologyCast = ontologyRelatedTopics cs topic
      candidateTopics = S.toList (S.fromList (overlapping ++ ontologyCast))
      activatedNetwork = SemanticNetwork
        { snNodes = S.fromList (M.keys actMap)
        , snEdges = M.empty
        , snActivation = actMap
        , snDecayRate = 0.5
        , snMaxHops = 0
        , snActivationLog = Seq.empty
        }
  in if null candidateTopics
       then ([], [noRouteDiagnostic topic])
       else
         let perTopicPreds = mapMaybe (composeBestForActivation cs field heuristics activatedNetwork)
                                      candidateTopics
             totalActivation = sum [ v | (_, v) <- M.toList actMap ]
             weighted = map
               (\ (t, p, s) ->
                 let topicAct = sum
                       [ v | (a, v) <- M.toList actMap
                       , S.member a (M.findWithDefault S.empty t (csTopicAtoms cs)) ]
                     weight = if totalActivation > 0
                                then topicAct / totalActivation
                                else 0.0
                 in (t, p, s, weight)
               ) perTopicPreds
             top3 = take 3 (sortBy (comparing (Down . (\(_, _, _, w) -> w))) weighted)
             composition = map (\ (_, p, _, _) -> p) top3
             selectedKeys = [ (t, spRu p) | (t, p, _, _) <- top3 ]
             winnerDiagnostics = concat
               [ let surface = spRu p
                     chosen = (t, surface) `elem` selectedKeys
                 in [ SelectorDiagnostic topic t (Just surface) (Just s) chosen
                        (if chosen then "selected_composition_predicate" else "not_in_composition_top_3")
                        (Just 1.0) (Just s) (Just w) (Just 0.0)
                        (Just (ontologyDepthBoost cs heuristics t)) Nothing (Just 0.0)
                        Nothing (Just selectorMathVersion) ]
               | (t, p, s, w) <- weighted ]
             -- Every predicate in the candidate pool must appear in the
             -- diagnostics, including predicates that lost the per-topic
             -- competition. This preserves the promotion/overlay contract:
             -- a non-selected predicate is attributed with an explicit loss
             -- reason instead of disappearing from the trace.
             poolDiagnostics = concat
               [ [ let chosen = (t, spRu p) `elem` selectedKeys
                       slotReason = if chosen
                                      then "selected_composition_predicate"
                                      else "not_in_composition_top_3"
                   in SelectorDiagnostic topic t (Just (spRu p)) (Just 0.0) chosen
                        slotReason
                        (Just 1.0) (Just 0.0) (Just 0.0) (Just 0.0)
                        (Just (ontologyDepthBoost cs heuristics t)) Nothing (Just 0.0)
                        Nothing (Just selectorMathVersion)
                 | p <- M.findWithDefault [] t (csTopicPredicates cs)
                 , let key = (t, spRu p)
                 , not (key `elem` selectedKeys) ]
               | t <- candidateTopics ]
         in (composition, winnerDiagnostics ++ poolDiagnostics)
  where
    noRouteDiagnostic t =
      SelectorDiagnostic t t Nothing Nothing False
        "topic_not_activated_or_ontology_related"
        Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- | Pick the best scored predicate for a candidate topic inside an already
-- activated network, applying the ontology depth boost.
-- When the field space cannot discriminate any predicate (e.g. an empty
-- semantic space in minimal fixtures), the directly activated seed topic is
-- still allowed to surface its canonical predicate: the topic's own atoms are
-- part of the activation, so composing it is deterministic and emits the
-- topic's own framing predicate rather than dropping the topic silently.
composeBestForActivation
  :: ContentSelector
  -> Field
  -> FieldHeuristics
  -> SemanticNetwork
  -> Text
  -> Maybe (Text, SemanticPredicate, Double)
composeBestForActivation cs field heuristics activatedNetwork t =
  case M.lookup t (csTopicPredicates cs) of
    Nothing -> Nothing
    Just [] -> Nothing
    Just preds ->
      case mapMaybe (scorePred field (csSpace cs) (csLemmaMap cs) (Just activatedNetwork)) preds of
        [] ->
          let topicActivation = sum
                [ v
                | (a, v) <- M.toList (snActivation activatedNetwork)
                , S.member a (M.findWithDefault S.empty t (csTopicAtoms cs))
                ]
          in if topicActivation > 0.05
               then let depthBoost = ontologyDepthBoost cs heuristics t
                        p = head preds
                    in Just (t, p, 0.3 * (1.0 + depthBoost))
               else Nothing
        scored ->
          let depthBoost = ontologyDepthBoost cs heuristics t
              boosted = map (\ (p, s) -> (p, s * (1.0 + depthBoost))) scored
              (bestPred, bestScore) = maximumBy (comparing snd) boosted
          in Just (t, bestPred, bestScore)

-- | Compose from an already-materialized activation artifact (the evaluated
-- network view), reusing a shared diagnostic pipeline that consumes the
-- precomputed activation rather than re-spreading from a zero-hop view.
composeFromArtifactWithDiagnostics
  :: ContentSelector
  -> Field
  -> FieldHeuristics
  -> Text
  -> ActivationArtifact
  -> ([SemanticPredicate], [SelectorDiagnostic])
composeFromArtifactWithDiagnostics cs field heuristics topic artifact =
  composeFromActivationSnapshot cs field heuristics topic (aaActivation artifact)

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
