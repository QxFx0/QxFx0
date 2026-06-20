{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network
  ( module QxFx0.Semantic.Network.Types
  , buildSemanticNetwork
  , mergeSemanticNetworks
  , activate
  , activateTopic
  , getActivatedAtoms
  , contentDensityGate
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import QxFx0.Core.MeaningGraph (MeaningGraph(..), MeaningEdge(..))
import QxFx0.Semantic.Network.Types

buildSemanticNetwork :: MeaningGraph -> SemanticNetwork
buildSemanticNetwork mg =
  let edges = mgEdges mg
      nodes = S.fromList $ concatMap (\e -> S.toList (meAtoms e)) edges
      edgeMap = M.fromList
        [ ((a1, a2), SemanticEdge a1 a2 (fromIntegral count / fromIntegral maxCount) count ExplicitEdge)
        | e <- edges
        , a1 <- S.toList (meAtoms e)
        , a2 <- S.toList (meAtoms e)
        , a1 /= a2
        , let count = meCount e
        ]
      maxCount = maximum (1 : map meCount edges)
  in SemanticNetwork
    { snNodes = nodes
    , snEdges = edgeMap
    , snActivation = M.empty
    , snDecayRate = 0.5
    , snMaxHops = 3
    }

mergeSemanticNetworks :: SemanticNetwork -> SemanticNetwork -> SemanticNetwork
mergeSemanticNetworks base update =
  SemanticNetwork
    { snNodes = S.union (snNodes base) (snNodes update)
    , snEdges = M.union (snEdges update) (snEdges base)
    , snActivation = M.empty
    , snDecayRate = snDecayRate base
    , snMaxHops = snMaxHops base
    }

activate :: Text -> SemanticNetwork -> SemanticNetwork
activate seed sn =
  let initialActivation = M.singleton seed 1.0
  in spreadActivation sn initialActivation 0

activateTopic :: Set Text -> SemanticNetwork -> SemanticNetwork
activateTopic topicAtoms sn =
  let initialActivation = M.fromList [(atom, 1.0) | atom <- S.toList topicAtoms]
  in spreadActivation sn initialActivation 0

spreadActivation :: SemanticNetwork -> Map Text Double -> Int -> SemanticNetwork
spreadActivation sn activation hopCount
  | hopCount >= snMaxHops sn = sn { snActivation = activation }
  | otherwise =
      let propagated = propagateAll activation sn
          newActivation = M.unionWith max activation propagated
      in if M.size newActivation == M.size activation
         then sn { snActivation = newActivation }
         else spreadActivation sn newActivation (hopCount + 1)

propagateAll :: Map Text Double -> SemanticNetwork -> Map Text Double
propagateAll activation sn =
  M.foldlWithKey' (\acc atom act ->
    M.unionWith max acc (propagateOne atom act sn activation)
  ) M.empty activation

propagateOne :: Text -> Double -> SemanticNetwork -> Map Text Double -> Map Text Double
propagateOne atom act sn activation =
  let neighbors = getNeighbors atom sn
      decay = snDecayRate sn
      newActs = [ (neighbor, act * seWeight edge * decay)
                | (neighbor, edge) <- neighbors
                , not (M.member neighbor activation)
                ]
  in M.fromList newActs

getNeighbors :: Text -> SemanticNetwork -> [(Text, SemanticEdge)]
getNeighbors atom sn =
  [ (seTo e, e)
  | ((from, _), e) <- M.toList (snEdges sn)
  , from == atom
  ]

getActivatedAtoms :: SemanticNetwork -> [(Text, Double)]
getActivatedAtoms sn =
  [ (atom, act)
  | (atom, act) <- M.toList (snActivation sn)
  , act > 0.05
  ]

contentDensityGate :: SemanticNetwork -> Bool
contentDensityGate sn =
  let edgeCount = M.size (snEdges sn)
      nodeCount = S.size (snNodes sn)
  in edgeCount >= 50 && nodeCount >= 15
