{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-|
Experimental spectral analysis via inverse iteration for the Fiedler vector.

Not wired into the production turn pipeline. Topic routing in production uses
Dijkstra geodesics ('QxFx0.Core.TopicTransition'). Kept for extended scientific
contour experiments only.

Pure-Haskell spectral analysis via inverse iteration for the Fiedler vector.
No external C dependencies (hmatrix/BLAS/LAPACK removed).

The Laplacian is built as a dense [[Double]] matrix.
Fiedler value ≈ λ₂ is estimated via Rayleigh quotient on the
inverse-iteration eigenvector.  Sufficient for graphs with <500 nodes.
-}
module QxFx0.Core.Spectral
  ( laplacianMatrix
  , fiedlerValue
  , fiedlerVector
  , detectClusters
  , ClusterInsight(..)
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.List (foldl', sortBy)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Observability (MeaningGraph(..), MeaningEdge(..), MeaningStateId)

data ClusterInsight
  = NoClusters
  | TwoClusters [Text] [Text] Double
  deriving stock (Eq, Show)

buildAdjacencyMap :: MeaningGraph -> Map MeaningStateId (Map MeaningStateId Double)
buildAdjacencyMap mg =
  foldl' addEdge M.empty (mgEdges mg)
  where
    addEdge acc e =
      let w = fromIntegral (meCount e)
      in M.insertWith (M.unionWith (+)) (meFromId e) (M.singleton (meToId e) w) acc

allNodes :: Map MeaningStateId (Map MeaningStateId Double) -> [MeaningStateId]
allNodes adj = M.keys (M.union adj (M.unions (map (\m -> M.fromList [(k, M.empty) | k <- M.keys m]) (M.elems adj))))

laplacianMatrix :: MeaningGraph -> [(MeaningStateId, [(MeaningStateId, Double)])]
laplacianMatrix mg =
  let adj = buildAdjacencyMap mg
      nodes = allNodes adj
      degreeMap = M.map (sum . M.elems) adj
  in map (buildRow adj nodes degreeMap) nodes
  where
    buildRow adj nodes degreeMap node =
      let degree = M.findWithDefault 0.0 node degreeMap
          neighbors = M.findWithDefault M.empty node adj
          row = map (\other ->
                if node == other
                then degree
                else negate (M.findWithDefault 0.0 other neighbors))
                nodes
      in (node, zip nodes row)

buildDenseLaplacian :: MeaningGraph -> ([[Double]], [MeaningStateId])
buildDenseLaplacian mg =
  let adj = buildAdjacencyMap mg
      nodes = allNodes adj
      n = length nodes
      row node =
        let neighbors = M.findWithDefault M.empty node adj
            degree = sum (M.elems neighbors)
        in [ if i == j then degree
             else negate (M.findWithDefault 0.0 (nodes !! j) neighbors)
           | let i = maybe (-1) id (M.lookup node (M.fromList (zip nodes [0..])))
           , j <- [0..n-1] ]
  in (map row nodes, nodes)

type Vec = [Double]

dot :: Vec -> Vec -> Double
dot a b = sum (zipWith (*) a b)

scale :: Double -> Vec -> Vec
scale s = map (* s)

addVec :: Vec -> Vec -> Vec
addVec = zipWith (+)

subVec :: Vec -> Vec -> Vec
subVec = zipWith (-)

norm2 :: Vec -> Double
norm2 v = sqrt (dot v v)

normalize :: Vec -> Vec
normalize v = let n = norm2 v in if n < 1e-10 then replicate (length v) 0.0 else scale (1.0 / n) v

matVecMul :: [[Double]] -> Vec -> Vec
matVecMul mat v = map (dot v) mat

jacobiSolve :: [[Double]] -> Vec -> Int -> Vec
jacobiSolve mat rhs maxIter = go (replicate n 0.0) maxIter
  where
    n = length rhs
    diag = [ mat !! i !! i | i <- [0..n-1] ]
    go _ 0 = replicate n 0.0
    go x k =
      let xNew = [ let diagElem = diag !! i
                   in if diagElem > 1e-15
                      then (rhs !! i + sum [ mat !! i !! j * x !! j
                                           | j <- [0..n-1], j /= i ])
                           / diagElem
                      else 0.0
                 | i <- [0..n-1]
                 ]
      in go xNew (k - 1)

inverseIteration :: [[Double]] -> Int -> (Double, Vec)
inverseIteration mat maxIter =
  let n = length mat
      diag = map (\i -> mat !! i !! i) [0..n-1]
      shift = minimum diag * 0.99
      shifted = [ [ mat !! i !! j - (if i == j then shift else 0.0)
                  | j <- [0..n-1] ] | i <- [0..n-1] ]
      initVec = take n (cycle [1.0, -1.0])
      go v 0 = (rayleigh mat v, v)
      go v k =
        let rhs = jacobiSolve shifted v 20
            v' = normalize rhs
        in go v' (k - 1)
  in go (normalize initVec) maxIter

rayleigh :: [[Double]] -> Vec -> Double
rayleigh mat v =
  let n2 = norm2 v
  in if n2 < 1e-15 then 0.0 else dot v (matVecMul mat v) / (n2 * n2)

fiedlerValue :: MeaningGraph -> Double
fiedlerValue mg =
  let (mat, nodes) = buildDenseLaplacian mg
      n = length nodes
  in if n <= 1 then 0.0 else fst (inverseIteration mat 30)

fiedlerVector :: MeaningGraph -> [(MeaningStateId, Double)]
fiedlerVector mg =
  let (mat, nodes) = buildDenseLaplacian mg
      n = length nodes
  in if n <= 1
     then zip nodes (repeat 0.0)
     else let (_, vec) = inverseIteration mat 30
          in zip nodes vec

detectClusters :: MeaningGraph -> ClusterInsight
detectClusters mg =
  let fv = fiedlerValue mg
      threshold = 0.1
  in if fv >= threshold
     then NoClusters
     else let vec = fiedlerVector mg
              cluster1 = [T.pack node | (node, v) <- vec, v > 0]
              cluster2 = [T.pack node | (node, v) <- vec, v <= 0]
          in TwoClusters cluster1 cluster2 fv
