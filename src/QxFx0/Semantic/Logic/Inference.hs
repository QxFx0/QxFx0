{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Logical inference over 'SemanticEdge's.
--
-- The engine derives new edges from existing ones using safe, locally
-- verifiable rules.  Every derived edge carries 'ProvenanceDerived' and a
-- 'seLineage' pointing to the parent edges, so its origin can be audited and
-- replayed.
module QxFx0.Semantic.Logic.Inference
  ( InferenceRule(..)
  , inferEdges
  , applyInference
  , applyInferenceUntilFixpoint
  , explainPath
  , inferTransitiveEdges
  , inferSymmetricEdges
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Maybe (fromMaybe, mapMaybe, listToMaybe)
import Data.Sequence (Seq(..), (|>))
import qualified Data.Sequence as Seq
import Data.Text (Text)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeRef
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , edgeRefOf
  )
import QxFx0.Learning.EdgeScore (EdgeScore(..), defaultEdgeScore, computeWeight)

-- | Named inference rule used to produce a derived edge.
data InferenceRule
  = Transitivity  -- ^ A -> B and B -> C ⇒ A -> C
  | Symmetry      -- ^ A -> B and relation is symmetric ⇒ B -> A
  deriving stock (Eq, Show)

-- | Relation types that support transitive chaining.
transitiveRelationTypes :: [RelationType]
transitiveRelationTypes =
  [ RelRequires
  , RelNecessaryFor
  , RelPresupposes
  , RelDependsOn
  , RelEnables
  , RelCauses
  , RelInfluences
  , RelPartOf
  , RelIncludes
  , RelIsA
  , RelStructures
  , RelDetermines
  , RelOrientsToward
  , RelPrecedes
  ]

-- | Relation types that are symmetric.
symmetricRelationTypes :: [RelationType]
symmetricRelationTypes =
  [ RelContrastsWith
  , RelOpposes
  , RelDiffersFrom
  , RelNegates
  , RelNotReducibleTo
  , RelDestroys
  ]

-- | Produce all derived edges from the network without mutating it.
inferEdges :: SemanticNetwork -> [SemanticEdge]
inferEdges net =
  let edges = M.elems (snEdges net)
  in inferTransitiveEdges edges ++ inferSymmetricEdges edges

-- | Add inferred edges to the network.  Existing edges win on conflict.
applyInference :: SemanticNetwork -> SemanticNetwork
applyInference net = applyInferenceWithConfig defaultInferenceConfig net

-- | Configuration that bounds iterative inference to prevent combinatorial
-- explosion.
data InferenceConfig = InferenceConfig
  { icMaxIterations     :: !Int
  , icConfidenceFloor   :: !Double
  , icMaxDerivedEdges   :: !Int
  }

-- | Conservative defaults: up to 5 iterations, no edge below 0.25 confidence,
-- at most 500 derived edges total.
defaultInferenceConfig :: InferenceConfig
defaultInferenceConfig = InferenceConfig
  { icMaxIterations   = 5
  , icConfidenceFloor = 0.25
  , icMaxDerivedEdges = 500
  }

-- | Apply inference rules iteratively until no new edges appear or one of the
-- safety bounds is reached.
applyInferenceUntilFixpoint :: SemanticNetwork -> SemanticNetwork
applyInferenceUntilFixpoint = applyInferenceUntilFixpointWithConfig defaultInferenceConfig

applyInferenceUntilFixpointWithConfig :: InferenceConfig -> SemanticNetwork -> SemanticNetwork
applyInferenceUntilFixpointWithConfig cfg = go 0
  where
    go n net
      | n >= icMaxIterations cfg = net
      | otherwise =
          let net' = applyInferenceWithConfig cfg net
              before = M.size (snEdges net)
              after  = M.size (snEdges net')
          in if after == before
             then net'
             else go (n + 1) net'

-- | Single inference pass with configurable filters.
applyInferenceWithConfig :: InferenceConfig -> SemanticNetwork -> SemanticNetwork
applyInferenceWithConfig cfg net =
  let derived = filter (\e -> seConfidence e >= icConfidenceFloor cfg) (inferEdges net)
      currentDerived = length (filter (\e -> seProvenance e == ProvenanceDerived) (M.elems (snEdges net)))
      availableSlots = max 0 (icMaxDerivedEdges cfg - currentDerived)
      boundedDerived = take availableSlots derived
      insertEdge acc edge =
        let key = (seFrom edge, seTo edge)
        in case M.lookup key (snEdges acc) of
             Nothing ->
               let acc' = acc { snEdges = M.insert key edge (snEdges acc) }
               in acc' { snNodes = S.insert (seFrom edge) (S.insert (seTo edge) (snNodes acc')) }
             Just _ -> acc
  in foldl insertEdge net boundedDerived

-- | Transitive closure for hierarchical relation types.
inferTransitiveEdges :: [SemanticEdge] -> [SemanticEdge]
inferTransitiveEdges edges =
  let byKey = M.fromList [((seFrom e, seTo e), e) | e <- edges]
      stepPairs = [ (e1, e2)
                  | e1 <- edges
                  , e2 <- edges
                  , seTo e1 == seFrom e2
                  , seFrom e1 /= seTo e2
                  , isTransitive e1
                  , isTransitive e2
                  ]
  in mapMaybe (deriveTransitive byKey) stepPairs
  where
    isTransitive e = maybe False (`elem` transitiveRelationTypes) (seRelationType e)

    deriveTransitive :: M.Map (Text, Text) SemanticEdge -> (SemanticEdge, SemanticEdge) -> Maybe SemanticEdge
    deriveTransitive byKey (e1, e2) =
      let key = (seFrom e1, seTo e2)
      in case M.lookup key byKey of
           Just existing | seProvenance existing /= ProvenanceDerived -> Nothing
           _ -> Just $ mkDerivedEdge Transitivity e1 e2

-- | Symmetric completion for contrastive relation types.
inferSymmetricEdges :: [SemanticEdge] -> [SemanticEdge]
inferSymmetricEdges edges =
  let byKey = M.fromList [((seFrom e, seTo e), e) | e <- edges]
  in mapMaybe (deriveSymmetric byKey) edges
  where
    isSymmetric e = maybe False (`elem` symmetricRelationTypes) (seRelationType e)

    deriveSymmetric :: M.Map (Text, Text) SemanticEdge -> SemanticEdge -> Maybe SemanticEdge
    deriveSymmetric byKey edge
      | not (isSymmetric edge) = Nothing
      | otherwise =
          let key = (seTo edge, seFrom edge)
          in case M.lookup key byKey of
               Just existing | seProvenance existing /= ProvenanceDerived -> Nothing
               _ -> Just $ mkDerivedEdge Symmetry edge edge

-- | Build a derived edge from two parent edges and a rule.
mkDerivedEdge :: InferenceRule -> SemanticEdge -> SemanticEdge -> SemanticEdge
mkDerivedEdge rule parent1 parent2 =
  let (from, to) = case rule of
        Transitivity -> (seFrom parent1, seTo parent2)
        Symmetry     -> (seTo parent1, seFrom parent1)
      rt = case rule of
        Transitivity -> combineTransitiveRelation (seRelationType parent1) (seRelationType parent2)
        Symmetry     -> seRelationType parent1
      conf = min (seConfidence parent1) (seConfidence parent2) * 0.8
      score = (defaultEdgeScore (fromMaybe RelRelatedTo rt) ProvenanceDerived)
                { esLLMConfidence = conf
                , esSourceAuthority = 0.7
                }
  in SemanticEdge
       { seFrom          = from
       , seTo            = to
       , seWeight        = computeWeight score
       , seCoOccurrence  = 1
       , seSource        = ExplicitEdge
       , seRelationType  = rt
       , seDomain        = seDomain parent1 <|> seDomain parent2
       , seTemporalScope = seTemporalScope parent1 <|> seTemporalScope parent2
       , seVerb          = Nothing
       , seRationale     = Just (ruleRationale rule parent1 parent2)
       , seCounter       = Nothing
       , seSynthesis     = Nothing
       , seConfidence    = conf
       , seProvenance    = ProvenanceDerived
       , seNamespace     = Just NamespaceSessionLocal
       , seLineage       = Just (normalizeLineage [edgeRefOf parent1, edgeRefOf parent2])
       }

ruleRationale :: InferenceRule -> SemanticEdge -> SemanticEdge -> Text
ruleRationale Transitivity p1 p2 =
  "Derived by transitivity from " <> seFrom p1 <> " -> " <> seTo p1 <> " and " <> seFrom p2 <> " -> " <> seTo p2
ruleRationale Symmetry p _ =
  "Derived by symmetry from " <> seFrom p <> " -> " <> seTo p

combineTransitiveRelation :: Maybe RelationType -> Maybe RelationType -> Maybe RelationType
combineTransitiveRelation (Just a) (Just b)
  | a == b    = Just a
  | otherwise = Just RelRequires
combineTransitiveRelation (Just a) Nothing = Just a
combineTransitiveRelation Nothing (Just b) = Just b
combineTransitiveRelation Nothing Nothing  = Just RelRelatedTo

normalizeLineage :: [EdgeRef] -> [EdgeRef]
normalizeLineage = S.toList . S.fromList

-- | Find a shortest path from source to target through the network edges.
-- Returns the list of edges that form the path, or Nothing if disconnected.
explainPath :: SemanticNetwork -> Text -> Text -> Maybe [SemanticEdge]
explainPath net source target
  | source == target = Just []
  | otherwise = bfs (Seq.singleton (source, Seq.empty)) (S.singleton source)
  where
    bfs :: Seq.Seq (Text, Seq.Seq SemanticEdge) -> S.Set Text -> Maybe [SemanticEdge]
    bfs queue visited =
      case Seq.viewl queue of
        Seq.EmptyL -> Nothing
        (node, path) Seq.:< rest ->
          let neighbors = M.toList $ M.filterWithKey (\(f, _) _ -> f == node) (snEdges net)
              process (k, edge) (q, v, found) =
                let nextNode = seTo edge
                in if S.member nextNode v
                   then (q, v, found)
                   else let newPath = path |> edge
                        in if nextNode == target
                           then (q, v, Just (toList newPath))
                           else (q |> (nextNode, newPath), S.insert nextNode v, found)
              (q', v', found) = foldr process (rest, visited, Nothing) neighbors
          in case found of
               Just p  -> Just p
               Nothing -> bfs q' v'

    toList :: Seq.Seq a -> [a]
    toList = foldr (:) []

-- Local helper shadowing the Prelude definition used for Maybe.
infixr 9 <|>
(<|>) :: Maybe a -> Maybe a -> Maybe a
(<|>) = mplus

mplus :: Maybe a -> Maybe a -> Maybe a
mplus (Just x) _ = Just x
mplus Nothing  y = y
