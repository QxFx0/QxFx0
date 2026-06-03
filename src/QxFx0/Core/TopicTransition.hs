{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-| Geodesic topic routing via Dijkstra shortest path. -}
module QxFx0.Core.TopicTransition
  ( geodesicDistance
  , geodesicRouter
  , GeodesicPlan(..)
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import qualified Data.List as L
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Observability (GeodesicPlan(..), MeaningGraph(..), MeaningEdge(..), MeaningStateId)

buildAdjacency :: MeaningGraph -> Map MeaningStateId (Map MeaningStateId Double)
buildAdjacency mg =
  let outgoing = L.foldl' addEdge M.empty (mgEdges mg)
  in outgoing
  where
    addEdge acc e =
      let w = fromIntegral (meCount e)
      in M.insertWith (M.unionWith (+)) (meFromId e) (M.singleton (meToId e) w) acc

shortestPath :: Map MeaningStateId (Map MeaningStateId Double) -> MeaningStateId -> MeaningStateId -> Double
shortestPath adj start goal = go M.empty (M.singleton start 0.0)
  where
    go visited dists
      | M.null unvisited = 1.0 / 0.0
      | current == goal  = currentDist
      | otherwise =
          let nbrs = M.findWithDefault M.empty current adj
              visited' = M.insert current currentDist visited
              dists' = M.delete current dists
              dists'' = M.foldlWithKey' updateDist dists' nbrs
          in go visited' dists''
      where
        unvisited = M.difference dists visited
        (current, currentDist) = L.minimumBy (comparing snd) (M.toList unvisited)
        updateDist d neighbor weight =
          let edgeDist = 1.0 / max weight 1e-10
              newDist = currentDist + edgeDist
          in M.insertWith min neighbor newDist d

geodesicDistance :: MeaningGraph -> Text -> Text -> Double
geodesicDistance mg fromTopic toTopic
  | fromTopic == toTopic = 0.0
  | otherwise =
      let adj = buildAdjacency mg
          fromId = T.unpack fromTopic
          toId   = T.unpack toTopic
      in if M.member fromId adj && M.member toId adj
         then shortestPath adj fromId toId
         else 1.0 / 0.0

geodesicRouter :: MeaningGraph -> Text -> Text -> [Text] -> GeodesicPlan
geodesicRouter mg fromTopic toTopic recentTopics =
  let dist = geodesicDistance mg fromTopic toTopic
      threshold = 3.0
  in if dist <= threshold || isInfinite dist
     then DirectJump
     else let adj = buildAdjacency mg
              fromId = T.unpack fromTopic
              toId   = T.unpack toTopic
              fromNeighbors = M.keys (M.findWithDefault M.empty fromId adj)
              bridges = filter (\bridge -> M.member toId (M.findWithDefault M.empty bridge adj)) fromNeighbors
              recentIds = map T.unpack recentTopics
              fresh = filter (`notElem` recentIds) bridges
           in if null fresh
              then DirectJump
              else BridgedJump (take 2 (map T.pack fresh))
