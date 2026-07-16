{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Learning.RuntimeLLMFeedback
  ( RuntimeLLMOutcome(..)
  , RuntimeLLMFeedbackEvent(..)
  , reinforceRuntimeEdge
  , applyRuntimeLLMFeedback
  , runtimePromotionConfidence
  , runtimePromotionCoOccurrence
  , DecayConfig(..)
  , defaultDecayConfig
  , applyEdgeDecayAndRetire
  ) where

import Data.List (sortOn)
import Data.Text (Text)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import qualified Data.Set as S
import Data.Time.Clock (UTCTime)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , relationTypeWeight
  )

data RuntimeLLMOutcome
  = RloPositive
  | RloNegative
  | RloConflict
  deriving stock (Eq, Show)

data RuntimeLLMFeedbackEvent = RuntimeLLMFeedbackEvent
  { rlfeTopic     :: !Text
  , rlfeEdgeFrom  :: !Text
  , rlfeEdgeTo    :: !Text
  , rlfeOutcome   :: !RuntimeLLMOutcome
  , rlfeTurnId    :: !Int
  , rlfeTimestamp :: !UTCTime
  }
  deriving stock (Eq, Show)

runtimePromotionConfidence :: Double
runtimePromotionConfidence = 0.75

runtimePromotionCoOccurrence :: Int
runtimePromotionCoOccurrence = 3

reinforceRuntimeEdge :: RuntimeLLMOutcome -> SemanticEdge -> Maybe SemanticEdge
reinforceRuntimeEdge outcome edge
  | seProvenance edge /= ProvenanceRuntimeLLM = Just edge
  | otherwise =
      case outcome of
        RloPositive -> Just (promoteIfReady reinforced)
          where
            reinforced = edge
              { seConfidence = min 1.0 (seConfidence edge + 0.05)
              , seCoOccurrence = seCoOccurrence edge + 1
              }
        RloNegative -> Just edge
          { seConfidence = max 0.0 (seConfidence edge - 0.10)
          }
        RloConflict -> Nothing

applyRuntimeLLMFeedback :: RuntimeLLMFeedbackEvent -> SemanticNetwork -> SemanticNetwork
applyRuntimeLLMFeedback event network =
  let key = (rlfeEdgeFrom event, rlfeEdgeTo event)
  in network { snEdges = M.update (reinforceRuntimeEdge (rlfeOutcome event)) key (snEdges network) }

promoteIfReady :: SemanticEdge -> SemanticEdge
promoteIfReady edge
  | seConfidence edge >= runtimePromotionConfidence
      && seCoOccurrence edge >= runtimePromotionCoOccurrence =
      edge { seProvenance = ProvenanceDialogueFeedback }
  | otherwise = edge

-- | Tunable parameters for turn-boundary edge decay / retirement.
data DecayConfig = DecayConfig
  { dcDecayRate        :: !Double  -- ^ multiplicative decay for unused edges
  , dcRetireThreshold  :: !Double  -- ^ confidence below which an edge is removed
  , dcMaxEdges         :: !Int     -- ^ hard cap on runtime edges kept per turn
  }
  deriving stock (Eq, Show)

defaultDecayConfig :: DecayConfig
defaultDecayConfig = DecayConfig
  { dcDecayRate = 0.95
  , dcRetireThreshold = 0.3
  , dcMaxEdges = 500
  }

-- | Apply turn-boundary decay and retirement to runtime-LLM edges.
--
-- * Edges that touch the current topic are considered "used" and skipped.
-- * All other runtime-LLM edges have their confidence multiplied by
--   'dcDecayRate'.
-- * Edges whose confidence drops below 'dcRetireThreshold' are removed.
-- * If the total number of runtime-LLM edges exceeds 'dcMaxEdges',
--   the lowest-confidence edges are removed until the cap is met.
applyEdgeDecayAndRetire :: DecayConfig -> Text -> SemanticNetwork -> SemanticNetwork
applyEdgeDecayAndRetire cfg topic network =
  let decayedEdges = M.mapMaybeWithKey (decayEdge cfg topic) (snEdges network)
      runtimeEdges = M.filter (\e -> seProvenance e == ProvenanceRuntimeLLM) decayedEdges
      prunedEdges = if M.size runtimeEdges > dcMaxEdges cfg
                       then pruneToCap cfg (dcMaxEdges cfg) decayedEdges
                       else decayedEdges
      survivingNodes = S.fromList (concatMap (\e -> [seFrom e, seTo e]) (M.elems prunedEdges))
  in network
      { snEdges = prunedEdges
      , snNodes = S.intersection (snNodes network) survivingNodes
      }

decayEdge :: DecayConfig -> Text -> (Text, Text) -> SemanticEdge -> Maybe SemanticEdge
decayEdge cfg topic key edge
  | seProvenance edge /= ProvenanceRuntimeLLM = Just edge
  | touchesTopic topic key = Just edge
  | otherwise =
      let newConf = seConfidence edge * dcDecayRate cfg
      in if newConf < dcRetireThreshold cfg
            then Nothing
            else Just edge { seConfidence = newConf
                           , seWeight = newConf * relationTypeWeight (fromMaybe RelRelatedTo (seRelationType edge))
                           }

-- | Keep the highest-confidence edges among runtime-LLM edges, leaving
-- non-runtime edges untouched.
pruneToCap :: DecayConfig -> Int -> M.Map (Text, Text) SemanticEdge -> M.Map (Text, Text) SemanticEdge
pruneToCap cfg cap edges =
  let (runtime, other) = M.partition (\e -> seProvenance e == ProvenanceRuntimeLLM) edges
      sorted = M.toList runtime
      keepKeys = S.fromList (map fst (take cap (sortOn (negate . seConfidence . snd) sorted)))
      keptRuntime = M.filterWithKey (\k _ -> S.member k keepKeys) runtime
  in M.union other keptRuntime

touchesTopic :: Text -> (Text, Text) -> Bool
touchesTopic topic (from, to) = from == topic || to == topic
