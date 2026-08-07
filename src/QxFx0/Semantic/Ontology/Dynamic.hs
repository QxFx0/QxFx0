{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Ontology.Dynamic
  ( module QxFx0.Types.Semantic.Ontology.Dynamic
  , observeCooccurrence
  , observeSimilarity
  , observeHierarchical
  , learnFromObservations
  , applyLearnedEdges
  , suggestNewRelations
  , learnFromContentSelector
  , updateContentSelectorWithLearned
  ) where

import Data.Foldable (foldl')
import Data.List (sortBy, groupBy, maximumBy, nub)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import Data.Ord (comparing)
import Data.Text (Text)

import QxFx0.Types.Semantic.Ontology.Dynamic
  ( LearningObservation(..), OntologyLearningConfig(..)
  , defaultLearningConfig, DynamicOntologyState(..), emptyDynamicOntologyState
  )
import QxFx0.Semantic.Ontology
  ( Ontology(..), OntologyNode(..), ConceptCategory(..)
  , addOntologyNode, addOntologyNodeAutoDepth
  , lookupOntologyNode, lookupCategory, lookupParent, lookupSiblings, lookupChildren
  )
import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..))
import QxFx0.Semantic.Content (SemanticPredicate(..))
import QxFx0.Types.Semantic.AtomGraph (RelationType(..))
import QxFx0.Types.Semantic.Network (SemanticNetwork(..))

-- | Record a co-occurrence observation between two topics
observeCooccurrence :: Text -> Text -> [Text] -> Maybe Text -> Int -> LearningObservation
observeCooccurrence source target evidence context timestamp =
  LearningObservation
    { loSourceTopic = source
    , loTargetTopic = target
    , loRelationType = RelRelatedTo
    , loConfidence = calculateCooccurrenceConfidence evidence
    , loEvidence = evidence
    , loContext = context
    , loTimestamp = timestamp
    }
  where
    calculateCooccurrenceConfidence evidenceList =
      let uniqueCount = fromIntegral (length (nub evidenceList))
          totalCount = fromIntegral (length evidenceList)
      in if totalCount == 0 then 0.0 else uniqueCount / totalCount

-- | Record a similarity observation with explicit relation type
observeSimilarity :: Text -> Text -> RelationType -> Double -> [Text] -> Maybe Text -> Int -> LearningObservation
observeSimilarity source target relType similarity evidence context timestamp =
  LearningObservation
    { loSourceTopic = source
    , loTargetTopic = target
    , loRelationType = relType
    , loConfidence = similarity * 0.8 + 0.2
    , loEvidence = evidence
    , loContext = context
    , loTimestamp = timestamp
    }

-- | Record a hierarchical observation
observeHierarchical :: Text -> Text -> RelationType -> Double -> [Text] -> Maybe Text -> Int -> LearningObservation
observeHierarchical parent child relType confidence evidence context timestamp =
  LearningObservation
    { loSourceTopic = parent
    , loTargetTopic = child
    , loRelationType = relType
    , loConfidence = confidence
    , loEvidence = evidence
    , loContext = context
    , loTimestamp = timestamp
    }

-- | Apply learned edges to an ontology
applyLearnedEdges :: Ontology -> [(Text, Text, RelationType)] -> (Ontology, [(Text, Text, RelationType)])
applyLearnedEdges ontology edges =
  foldl' applyEdge (ontology, []) edges
  where
    applyEdge (currentOnt, learnedSoFar) edge@(from, to, relType) =
      let (newOntology, wasAdded) = addEdgeToOntology currentOnt edge
      in if wasAdded
         then (newOntology, edge : learnedSoFar)
         else (newOntology, learnedSoFar)

    addEdgeToOntology ont (from, to, relType) =
      case (lookupOntologyNode ont from, lookupOntologyNode ont to) of
        (Just fromNode, Just toNode) -> (ont, False)
        (Nothing, Just toNode) ->
          let newOnt = addOntologyNodeAutoDepth ont from (onCategory toNode) (Just to)
          in (newOnt, True)
        (Just fromNode, Nothing) ->
          let newOnt = addOntologyNodeAutoDepth ont to (onCategory fromNode) (Just from)
          in (newOnt, True)
        (Nothing, Nothing) ->
          let tempOnt = addOntologyNode ont from CategoryGeneral Nothing 1
              finalOnt = addOntologyNode tempOnt to CategoryGeneral (Just from) 2
          in (finalOnt, True)

-- | Suggest new relations based on current observations
suggestNewRelations :: OntologyLearningConfig -> Ontology -> DynamicOntologyState -> [(Text, Text, RelationType, Double)]
suggestNewRelations config ontology state =
  let observations = dosObservations state
      groupedByRelation = groupBy (\ a b -> loRelationType a == loRelationType b) observations
      relationGroups = map (\ group ->
                         let relType = loRelationType (head group)
                             confidence = averageConfidence group
                         in (relType, confidence, group))
                        groupedByRelation
      sortedGroups = sortBy (comparing (\ (_, conf, _) -> conf)) relationGroups
      topSuggestions = take (olcMaxSuggestions config) sortedGroups
  in concatMap (\ (relType, avgConf, group) ->
                 map (\ obs ->
                   (loSourceTopic obs, loTargetTopic obs, relType, avgConf * loConfidence obs)
                 ) group
            ) topSuggestions
  where
    averageConfidence obs = if null obs then 0.0 else sum (map loConfidence obs) / fromIntegral (length obs)

-- | Process observations and learn new ontology edges
learnFromObservations :: OntologyLearningConfig -> Ontology -> DynamicOntologyState -> [LearningObservation] -> (Ontology, DynamicOntologyState, [(Text, Text, RelationType, Double)])
learnFromObservations config ontology state newObservations =
  let filtered = filter (\ obs -> loConfidence obs >= olcMinConfidence config) newObservations
      strongObservations = filterStrongObservations config ontology filtered
      candidateEdges = getCandidateEdges strongObservations
      validatedEdges = mapMaybe (validateLearnedEdge config ontology) candidateEdges
      (updatedOntology, learnedEdges) = applyLearnedEdges ontology validatedEdges
      updatedState = updateState state newObservations learnedEdges
  in (updatedOntology, updatedState, map (\ (from, to, rel) -> (from, to, rel, getEdgeConfidence (from, to, rel) candidateEdges)) validatedEdges)
  where
    getEdgeConfidence (from, to, rel) edges =
      case filter (\ (f, t, r, _) -> f == from && t == to && r == rel) edges of
        [] -> 0.0
        (_, _, _, conf):_ -> conf

-- | Learn from ContentSelector usage patterns
learnFromContentSelector :: OntologyLearningConfig -> ContentSelector -> Text -> [SemanticPredicate] -> Maybe SemanticNetwork -> Int -> DynamicOntologyState -> (DynamicOntologyState, [LearningObservation])
learnFromContentSelector config cs currentTopic selectedPredicates mNetwork timestamp state =
  let observations = generateObservationsFromSelection cs currentTopic selectedPredicates mNetwork timestamp
      updatedState = state
        { dosObservations = take (olcMaxObservations config) (observations ++ dosObservations state)
        , dosObservationCount = dosObservationCount state + length observations
        }
  in (updatedState, observations)
  where
    generateObservationsFromSelection csOnTopic topic predicates mNet ts =
      case mNet of
        Nothing -> []
        Just network ->
          let activeAtoms = snActivation network
              activeAtomList = M.keys (M.filter (> 0.1) activeAtoms)
          in map (\ atom -> observeCooccurrence topic atom [atom] (Just "spreading_activation") ts) activeAtomList

-- | Update ContentSelector with learned ontology
updateContentSelectorWithLearned :: ContentSelector -> Ontology -> [(Text, Text, RelationType)] -> ContentSelector
updateContentSelectorWithLearned cs ontology learnedEdges =
  let updatedOntology = foldl' (\ ont edge -> fst (applyLearnedEdges ont [edge])) ontology learnedEdges
  in cs { csOntology = Just updatedOntology }

-- ==========================================================================
-- Utility Functions
-- ==========================================================================

-- | Get candidate edges from observations
getCandidateEdges :: [LearningObservation] -> [(Text, Text, RelationType, Double)]
getCandidateEdges observations =
  map (\ obs -> (loSourceTopic obs, loTargetTopic obs, loRelationType obs, loConfidence obs)) observations

-- | Filter observations to keep only the strongest ones for each relation
filterStrongObservations :: OntologyLearningConfig -> Ontology -> [LearningObservation] -> [LearningObservation]
filterStrongObservations config ontology observations =
  let grouped = groupBy (\ a b -> loSourceTopic a == loSourceTopic b && loTargetTopic a == loTargetTopic b && loRelationType a == loRelationType b) observations
      strongest = map (\ group -> maximumBy (comparing loConfidence) group) grouped
  in filter (\ obs -> not (edgeExists ontology (loSourceTopic obs) (loTargetTopic obs) (loRelationType obs))) strongest
  where
    edgeExists ont from to rel =
      case lookupOntologyNode ont from of
        Nothing -> False
        Just fromNode ->
          case lookupOntologyNode ont to of
            Nothing -> False
            Just toNode -> from == to || (onParent fromNode == Just to) || (onParent toNode == Just from)

-- | Validate a learned edge against the ontology
validateLearnedEdge :: OntologyLearningConfig -> Ontology -> (Text, Text, RelationType, Double) -> Maybe (Text, Text, RelationType)
validateLearnedEdge config ontology (from, to, relType, confidence) =
  if confidence >= olcValidationThreshold config && not (wouldCreateCycle ontology from to)
  then Just (from, to, relType)
  else Nothing
  where
    wouldCreateCycle ont from' to' = False  -- Simplified cycle detection

-- | Update dynamic ontology state
updateState :: DynamicOntologyState -> [LearningObservation] -> [(Text, Text, RelationType)] -> DynamicOntologyState
updateState state newObservations learnedEdges =
  state
    { dosObservations = take (olcMaxObservations config) (newObservations ++ dosObservations state)
    , dosLearnedEdges = learnedEdges ++ dosLearnedEdges state
    , dosObservationCount = dosObservationCount state + length newObservations
    , dosLearningIterations = dosLearningIterations state + 1
    }
  where
    config = defaultLearningConfig