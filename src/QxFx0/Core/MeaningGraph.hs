{-# LANGUAGE OverloadedStrings, DeriveGeneric #-}
{-| Transition graph for response strategy reuse and dream-cycle rewiring. -}
module QxFx0.Core.MeaningGraph
  ( ResonanceBand(..)
  , PressureBand(..)
  , DepthBand(..)
  , DensityBand(..)
  , MeaningState(..)
  , MeaningStateId
  , meaningStateId
  , toDepthBand
  , ResponseDepth(..)
  , ResponseStance(..)
  , ConvMove(..)
  , ResponseStrategy(..)
  , MeaningEdge(..)
  , MeaningGraph(..)
  , emptyMeaningGraph
  , recordTransition
  , predictStrategy
  , rewireMeaningGraphForDreamCycle
  , successRate
  , defaultStrategy
  , graphStats
  ) where

import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime)
import QxFx0.Types
  ( ConvMove(..)
  , DensityBand(..)
  , DepthBand(..)
  , MeaningEdge(..)
  , MeaningGraph(..)
  , MeaningState(..)
  , MeaningStateId
  , PressureBand(..)
  , ResonanceBand(..)
  , ResponseDepth(..)
  , ResponseStance(..)
  , ResponseStrategy(..)
  )
import QxFx0.Types.Text (textShow)
import QxFx0.Types.Thresholds
  ( meaningGraphDreamBiasLimit
  , meaningGraphRoutingThreshold
  )

-- | Stable identifier for a meaning state used as graph node key.
meaningStateId :: MeaningState -> MeaningStateId
meaningStateId ms = concat
  [ show (msResonance ms), "_"
  , show (msPressure ms), "_"
  , show (msDepth ms)
  ]

toDepthBand :: Int -> DepthBand
toDepthBand d
  | d <= 1    = DepthShallow
  | d == 2    = DepthMech
  | d == 3    = DepthPattern
  | otherwise = DepthAxiom

emptyMeaningGraph :: MeaningGraph
emptyMeaningGraph = MeaningGraph [] 0

maxEdges :: Int
maxEdges = 300

successRate :: MeaningEdge -> Double
successRate e
  | meCount e == 0 = 0.0
  | otherwise       = fromIntegral (meWins e) / fromIntegral (meCount e)

-- | Record one observed transition and update edge counters.
recordTransition :: MeaningState -> MeaningState -> ResponseStrategy -> Bool -> MeaningGraph -> MeaningGraph
recordTransition fromState toState strat win g =
  let fid = meaningStateId fromState
      tid = meaningStateId toState
      mEdge = find (\e -> meFromId e == fid && meToId e == tid) (mgEdges g)
  in case mEdge of
       Just edge ->
         let updated = edge
               { meCount = meCount edge + 1
               , meWins  = meWins edge + if win then 1 else 0
               }
         in g { mgEdges = replaceEdge (mgEdges g) updated }
       Nothing ->
         let newEdge = MeaningEdge
               { meFromId = fid
               , meToId = tid
               , meFrom = fromState
               , meTo = toState
               , meStrategy = strat
               , meCount = 1
               , meWins = if win then 1 else 0
               , meDreamBias = 0.0
               , meLastRewiredAt = Nothing
               }
         in g { mgEdges = take maxEdges (newEdge : mgEdges g)
              , mgTurnCount = mgTurnCount g + 1 }

replaceEdge :: [MeaningEdge] -> MeaningEdge -> [MeaningEdge]
replaceEdge edges newE = map (\e -> if meFromId e == meFromId newE && meToId e == meToId newE then newE else e) edges

-- | Predict a reusable strategy when the edge routing score is above threshold.
predictStrategy :: MeaningState -> MeaningState -> MeaningGraph -> Maybe ResponseStrategy
predictStrategy fromState toState g =
  let fid = meaningStateId fromState
      tid = meaningStateId toState
  in case find (\e -> meFromId e == fid && meToId e == tid) (mgEdges g) of
     Just edge
        | edgeRoutingScore edge > meaningGraphRoutingThreshold -> Just (meStrategy edge)
        | otherwise -> Nothing
     Nothing -> Nothing

-- | Apply dream-cycle deltas to edge biases and return emitted rewire events.
rewireMeaningGraphForDreamCycle :: UTCTime -> [(MeaningEdge, Double)] -> MeaningGraph -> (MeaningGraph, [Text])
rewireMeaningGraphForDreamCycle now edgeDeltas g =
  let (newEdges, events) = unzip (map (rewireMeaningEdge now) edgeDeltas)
      g' = g { mgEdges = mergeEdges (mgEdges g) newEdges }
  in (g', concat events)

rewireMeaningEdge :: UTCTime -> (MeaningEdge, Double) -> (MeaningEdge, [Text])
rewireMeaningEdge now (edge, delta) =
  let newBias = clampSymmetric meaningGraphDreamBiasLimit (meDreamBias edge + delta)
      actualDelta = newBias - meDreamBias edge
      edge' = edge
        { meDreamBias = newBias
        , meLastRewiredAt = Just now
        }
      event = if abs actualDelta > 1e-6
              then [T.pack (meFromId edge) <> "->" <> T.pack (meToId edge) <> " bias:" <> textShow newBias]
              else []
  in (edge', event)

mergeEdges :: [MeaningEdge] -> [MeaningEdge] -> [MeaningEdge]
mergeEdges existing newEdges = foldl (\es ne -> replaceEdge es ne) existing newEdges

defaultStrategy :: MeaningState -> ResponseStrategy
defaultStrategy ms = ResponseStrategy
  { rsDepth    = case msResonance ms of ResonanceHigh -> DeepResp; ResonanceMed -> ModerateResp; ResonanceLow -> ShallowResp
  , rsStance   = case msPressure ms of PressHeavy -> HoldStance; PressLight -> AcknowledgeStance; PressNone -> OpenStance
  , rsMove     = case msPressure ms of PressHeavy -> CounterMove; PressLight -> ReframeMove; PressNone -> ValidateMove
  , rsDensityT = case msDepth ms of DepthShallow -> DensityMed; DepthMech -> DensityMed; DepthPattern -> DensityHigh; DepthAxiom -> DensityHigh
  }

graphStats :: MeaningGraph -> Text
graphStats mg =
  let nEdges = length (mgEdges mg)
      avgRate = if nEdges == 0 then 0.0 else sum (map successRate (mgEdges mg)) / fromIntegral nEdges
  in textShow nEdges <> " edges, avg success " <> textShow avgRate

edgeRoutingScore :: MeaningEdge -> Double
edgeRoutingScore edge = successRate edge + meDreamBias edge

clampSymmetric :: Double -> Double -> Double
clampSymmetric limit v = max (-limit) (min limit v)
