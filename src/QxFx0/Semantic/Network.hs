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
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
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
    , snActivationLog = Seq.empty
    }

mergeSemanticNetworks :: SemanticNetwork -> SemanticNetwork -> SemanticNetwork
mergeSemanticNetworks base update =
  SemanticNetwork
    { snNodes = S.union (snNodes base) (snNodes update)
    , snEdges = M.union (snEdges update) (snEdges base)
    , snActivation = M.empty
    , snDecayRate = snDecayRate base
    , snMaxHops = snMaxHops base
    , snActivationLog = Seq.empty
    }

activate :: Text -> SemanticNetwork -> SemanticNetwork
activate seed sn =
  let initialActivation = M.singleton seed 1.0
      step0 = ActivationStep seed ExplicitEdge seed 0 1.0
  in spreadActivation (sn { snActivationLog = Seq.singleton step0 }) initialActivation 0

activateTopic :: Set Text -> SemanticNetwork -> SemanticNetwork
activateTopic topicAtoms sn =
  let initialActivation = M.fromList [(atom, 1.0) | atom <- S.toList topicAtoms]
      steps0 = Seq.fromList [ ActivationStep atom ExplicitEdge atom 0 1.0 | atom <- S.toList topicAtoms ]
  in spreadActivation (sn { snActivationLog = steps0 }) initialActivation 0

spreadActivation :: SemanticNetwork -> Map Text Double -> Int -> SemanticNetwork
spreadActivation sn activation hopCount
  | hopCount >= snMaxHops sn = sn { snActivation = activation }
  | otherwise =
      let newSteps = buildSteps activation sn (hopCount + 1)
          newActs = M.fromList [(asNode s, asWeight s) | s <- newSteps]
          merged = M.unionWith max activation newActs
      in if M.size merged == M.size activation
         then sn { snActivation = merged }
         else spreadActivation
                (sn { snActivationLog = snActivationLog sn <> Seq.fromList newSteps })
                merged
                (hopCount + 1)

buildSteps :: Map Text Double -> SemanticNetwork -> Int -> [ActivationStep]
buildSteps activation sn hop =
  [ ActivationStep neighbor (seSource edge) atom hop weight
  | (atom, act) <- M.toList activation
  , (neighbor, edge) <- getNeighbors atom sn
  , not (M.member neighbor activation)
  , let weight = act * seWeight edge * snDecayRate sn
  ]

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
