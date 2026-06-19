{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Space
  ( module QxFx0.Semantic.Space.Types
  , buildPredicateVector
  , computeFieldAffinity
  , buildSemanticSpace
  , buildFactVectors
  , tokenizePredicate
  , cosineSimilarity
  , cosineDistance
  , projectAtoms
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Vector (Vector)
import qualified Data.Vector as V

import QxFx0.Semantic.Network (SemanticNetwork(..))
import QxFx0.Semantic.Space.Types
import QxFx0.Semantic.Morphology (normalizeToken)
import QxFx0.Types.State.SemanticCommitment (CommitmentId(..), SemanticCommitmentStore(..), SemanticCommitment(..), FactualClaimPayload(..))

buildPredicateVector :: SemanticNetwork -> Text -> Set Text -> PredicateVector
buildPredicateVector sn predicateId atoms =
  let dimCount = S.size (snNodes sn)
      atomIndex = M.fromList $ zip (S.toList (snNodes sn)) [0..]
  in PredicateVector predicateId atoms (buildPredicateVec atomIndex dimCount atoms)

buildPredicateVec :: Map Text Int -> Int -> Set Text -> Vector Double
buildPredicateVec atomIndex dimCount atoms =
  let vec = V.replicate dimCount 0.0
  in foldl (\v atom ->
    case M.lookup atom atomIndex of
      Nothing -> v
      Just idx -> v V.// [(idx, 1.0)]
    ) vec (S.toList atoms)

computeFieldAffinity :: SemanticSpace -> FieldDimension -> PredicateVector -> Double
computeFieldAffinity space dim pv =
  case M.lookup dim (ssPrototypes space) of
    Nothing -> 0.0
    Just prototype ->
      let dotProduct = V.sum $ V.zipWith (*) (pvVector pv) (dpVector prototype)
          normPV = sqrt $ V.sum $ V.map (^2) (pvVector pv)
          normProto = sqrt $ V.sum $ V.map (^2) (dpVector prototype)
      in if normPV == 0 || normProto == 0
         then 0.0
         else dotProduct / (normPV * normProto)

buildSemanticSpace :: SemanticNetwork -> Map Text (Set Text) -> SemanticSpace
buildSemanticSpace sn topicAtoms =
  let nodeList = S.toList (snNodes sn)
      atomIndex = M.fromList $ zip nodeList [0..]
      dimCount = length nodeList
      prototypes = buildPrototypes atomIndex dimCount
      predicateVecs = M.fromList
        [ (topic, PredicateVector topic atoms (buildPredicateVec atomIndex dimCount atoms))
        | (topic, atoms) <- M.toList topicAtoms
        ]
  in SemanticSpace
    { ssDimensionCount = dimCount
    , ssAtomIndex = atomIndex
    , ssPrototypes = prototypes
    , ssPredicateVectors = predicateVecs
    , ssFactVectors = M.empty
    }

buildPrototypes :: Map Text Int -> Int -> Map FieldDimension DimensionPrototype
buildPrototypes atomIndex dimCount =
  M.fromList
    [ (dim, DimensionPrototype dim atoms (buildPrototypeVector atomIndex dimCount atoms))
    | (dim, atomList) <- M.toList fieldDimensionPrototypes
    , let atoms = S.fromList atomList
    ]

buildPrototypeVector :: Map Text Int -> Int -> Set Text -> Vector Double
buildPrototypeVector atomIndex dimCount atoms =
  let vec = V.replicate dimCount 0.0
  in foldl (\v atom ->
    case M.lookup atom atomIndex of
      Nothing -> v
      Just idx -> v V.// [(idx, 1.0)]
    ) vec (S.toList atoms)

cosineSimilarity :: AtomVector -> AtomVector -> Double
cosineSimilarity (AtomVector v1) (AtomVector v2) =
  let dot = V.sum (V.zipWith (*) v1 v2)
      n1 = sqrt (V.sum (V.map (^2) v1))
      n2 = sqrt (V.sum (V.map (^2) v2))
  in if n1 == 0 || n2 == 0 then 0 else dot / (n1 * n2)

cosineDistance :: AtomVector -> AtomVector -> Double
cosineDistance v1 v2 = 1.0 - cosineSimilarity v1 v2

-- | Build fact vectors from CommitmentStore for geometric classification.
-- Extracts all active commitments, tokenizes their statements,
-- and projects them into the semantic space.
buildFactVectors :: Map Text Text -> SemanticSpace -> SemanticCommitmentStore -> Map CommitmentId AtomVector
buildFactVectors lemmaMap space store =
  M.fromList
    [ (cid, projectAtoms (tokenizePredicate lemmaMap (fcpStatement payload)) space)
    | (cid, (payload, _)) <- HashMap.toList (scsActive store)
    ]

-- | Project a set of atoms into an AtomVector in the semantic space.
-- Each atom present in the space gets value 1.0, others 0.0.
projectAtoms :: Set Text -> SemanticSpace -> AtomVector
projectAtoms atoms space =
  let dimCount = ssDimensionCount space
      vec = V.replicate dimCount 0.0
      vec' = foldl (\v atom ->
        case M.lookup atom (ssAtomIndex space) of
          Nothing -> v
          Just idx -> v V.// [(idx, 1.0)]
        ) vec (S.toList atoms)
  in AtomVector vec'

-- | Extract content words from a Russian predicate, filtering stop words and normalizing via lemma map.
-- Used to bridge predicate text to graph atoms for ContentSelector.
tokenizePredicate :: Map Text Text -> Text -> Set Text
tokenizePredicate lemmaMap text =
  let words = T.words (T.toLower text)
      filtered = filter (\w -> T.length w > 3 && not (isStopWord w)) words
      normalized = map (normalizeToken lemmaMap) filtered
  in S.fromList normalized
  where
    isStopWord :: Text -> Bool
    isStopWord w = w `elem`
      [ "это", "есть", "является", "быть", "было", "будет"
      , "и", "или", "но", "а", "в", "на", "с", "по", "для"
      , "что", "как", "когда", "где", "кто", "который", "которая"
      , "не", "ни", "же", "ли", "бы", "то", "так", "только"
      , "может", "могут", "должен", "должна", "должно"
      , "через", "между", "перед", "после", "при", "во", "со"
      , "the", "and", "or", "but", "is", "are", "was", "were"
      , "of", "to", "in", "on", "at", "for", "with", "by"
      , "that", "which", "who", "when", "where", "how"
      ]

