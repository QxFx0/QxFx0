{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-|
Proper LP solver for zero-sum mixed-strategy games using the simplex method.

Formulation (primal):
  minimise   sum_i w_i
  subject to sum_i w_i * B_{ij} >= 1   for all j
             w_i >= 0

where B = A + C is the payoff matrix shifted so every entry is > 0.
The optimal mixed strategy is p_i = w_i / sum_i w_i.

We solve the dual problem via the revised simplex tableau,
then recover the primal variables from the objective-row reduced costs.
-}
module QxFx0.Learning.GameTheory.LP
  ( solveMixedStrategy
  ) where

import Data.List (minimumBy)
import Data.Ord (comparing)

epsilon :: Double
epsilon = 1e-9

-- | Solve a zero-sum mixed-strategy LP.
-- Input: payoff matrix A (n rows x m columns).
-- Returns: list of n probabilities summing to 1, or Nothing if degenerate.
solveMixedStrategy :: [[Double]] -> Maybe [Double]
solveMixedStrategy a =
  case a of
    [] -> Nothing
    (row0:_) | null row0 -> Nothing
    (row0:_) ->
      let n = length a
          m = length row0
          rectangular = all ((== m) . length) a
          -- Shift payoffs so every entry >= 1 (guarantees v > 0)
          minA = minimum (concat a)
          shift = if minA < 1.0 then 1.0 - minA else 0.0
          b = map (map (+ shift)) a
          -- Dual problem: max sum_j y_j
          -- s.t. sum_j b_{ij} y_j <= 1 for all i
          -- Build tableau with n constraints, m decision + n slack variables
          nVars = m + n
          -- Objective row: -z + sum y_j = 0  (maximisation convention)
          objRow = replicate m 1.0 ++ replicate n 0.0
          objRHS = 0.0
          -- Constraint rows: sum_j b_{ij} y_j + s_i = 1
          conRows = zipWith (\row i ->
                              take m row ++ replicate i 0.0 ++ [1.0] ++ replicate (n - i - 1) 0.0)
                            b [0..]
          conRHS = replicate n 1.0
          -- Initial basic variables are the slacks (indices m .. m+n-1)
          basic = [m .. m+n-1]
          -- Run simplex (fail-closed: validate tableau dimensions first)
          final = if rectangular && all (\row -> length row == nVars) conRows
                     then simplexLoop nVars conRows conRHS objRow objRHS basic 1000
                     else Nothing
       in case final of
            Nothing -> Nothing
            Just (_, objR, _, bas, _) ->
              let -- Primal variables w_i = - (objective coefficient of slack s_i)
                  w = [ let coeff = if (m + i) `elem` bas then 0.0 else atOrZero objR (m + i)
                        in max 0.0 (-coeff)
                      | i <- [0 .. n-1] ]
                  total = sum w
              in if total > epsilon
                 then Just (map (/ total) w)
                 else Nothing

-- | Simplex tableau iteration.
simplexLoop :: Int                          -- total variables
            -> [[Double]]                   -- constraint rows
            -> [Double]                     -- constraint RHS
            -> [Double]                     -- objective coefficients
            -> Double                       -- objective RHS
            -> [Int]                        -- basic variable per row
            -> Int                          -- max iterations
            -> Maybe ([[Double]], [Double], Double, [Int], [Double])
simplexLoop nVars conRows conRHS objRow objRHS basic limit
  | limit <= 0 = Nothing
  | otherwise =
      let nonBasic = filter (`notElem` basic) [0 .. nVars-1]
          -- Optimality: for maximisation with -z + c^T x = RHS,
          -- optimal when all nonbasic objective coefficients <= 0
          entering = findEntering objRow nonBasic
      in case entering of
           Nothing -> Just (conRows, objRow, objRHS, basic, conRHS)
           Just e ->
              let -- Ratio test: for each row where coeff > 0, RHS / coeff
                  ratios =
                    [ (atOrZero conRHS i / coeff, i)
                    | i <- [0 .. length conRows - 1]
                    , Just row <- [safeIndex conRows i]
                    , let coeff = atOrZero row e
                    , coeff > epsilon
                    ]
              in if null ratios
                 then Nothing  -- unbounded
                 else
                   let (_, l) = minimumBy (comparing fst) ratios
                   in case safeIndex conRows l of
                        Nothing -> Nothing
                        Just pivotRowRaw ->
                          let pivotElem = atOrZero pivotRowRaw e
                          in if pivotElem <= epsilon
                               then Nothing
                               else
                                 let pivotRow = map (/ pivotElem) pivotRowRaw
                                     pivotRHS = atOrZero conRHS l / pivotElem
                                     updateRow row rhs =
                                       let coeff = atOrZero row e
                                           newRow = zipWith (-) row (map (* coeff) pivotRow)
                                           newRHS = rhs - coeff * pivotRHS
                                       in (replaceAt e 0.0 newRow, newRHS)
                                     rebuilt =
                                       [ if i == l
                                           then (pivotRow, pivotRHS)
                                           else updateRow row (atOrZero conRHS i)
                                       | (i, row) <- zip [0 ..] conRows
                                       ]
                                     (conRows', conRHS') = unzip rebuilt
                                     objCoeffE = atOrZero objRow e
                                     newObjRow = zipWith (-) objRow (map (* objCoeffE) pivotRow)
                                     newObjRHS = objRHS - objCoeffE * pivotRHS
                                     newObjRow' = replaceAt e 0.0 newObjRow
                                     basic' = take l basic ++ [e] ++ drop (l + 1) basic
                                 in simplexLoop nVars conRows' conRHS' newObjRow' newObjRHS basic' (limit - 1)

findEntering :: [Double] -> [Int] -> Maybe Int
findEntering objRow nonBasic =
  let candidates = filter (\j -> atOrZero objRow j > epsilon) nonBasic
  in case candidates of
       [] -> Nothing
       js -> Just (minimum js)  -- Bland's rule: smallest index with positive reduced cost

atOrZero :: [Double] -> Int -> Double
atOrZero xs idx = maybe 0.0 id (safeIndex xs idx)

safeIndex :: [a] -> Int -> Maybe a
safeIndex xs idx
  | idx < 0 = Nothing
  | otherwise =
      case drop idx xs of
        y:_ -> Just y
        [] -> Nothing

replaceAt :: Int -> a -> [a] -> [a]
replaceAt idx value xs
  | idx < 0 = xs
  | otherwise =
      case splitAt idx xs of
        (prefix, _ : suffix) -> prefix ++ value : suffix
        _ -> xs
