{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Feedback
  ( UserFeedback(..)
  , FeedbackResult(..)
  , applyFeedback
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Data.Text (Text)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network (adjustEdge)
import QxFx0.Semantic.Network.Types

-- | User feedback on a runtime-generated semantic move.
data UserFeedback
  = Accept
  | Challenge Text
  | Clarify Text
  deriving stock (Eq, Show)

-- | Result summary of applying feedback. The lists contain the
-- adjusted original edges and any newly introduced edges.
data FeedbackResult = FeedbackResult
  { frAdjustedEdges :: [SemanticEdge]
  , frAddedEdges    :: [SemanticEdge]
  }
  deriving stock (Eq, Show)

-- | Clamp a value to the unit interval @[0.0, 1.0]@.
clampUnit :: Double -> Double
clampUnit = min 1.0 . max 0.0

-- | Clamp a confidence value to @[0.1, 1.0]@.
clampConfidence :: Double -> Double
clampConfidence = min 1.0 . max 0.1

-- | Apply user feedback to the edges that were used in a turn.
applyFeedback :: SemanticNetwork -> [SemanticEdge] -> UserFeedback -> SemanticNetwork
applyFeedback network usedEdges feedback =
  case feedback of
    Accept           -> foldr applyAccept network usedEdges
    Challenge reason -> foldr (applyChallenge reason) network usedEdges
    Clarify detail   -> foldr (applyClarify detail) network usedEdges

applyAccept :: SemanticEdge -> SemanticNetwork -> SemanticNetwork
applyAccept edge network =
  adjustEdge (seFrom edge, seTo edge)
    (\e -> e { seConfidence = clampUnit (seConfidence e + 0.1) })
    network

applyChallenge :: Text -> SemanticEdge -> SemanticNetwork -> SemanticNetwork
applyChallenge reason edge network =
  let network' = adjustEdge (seFrom edge, seTo edge)
                   (\e -> e { seConfidence = clampConfidence (seConfidence e - 0.15) })
                   network
      reverseKey = (seTo edge, seFrom edge)
      counterEdge = SemanticEdge
        { seFrom         = seTo edge
        , seTo           = seFrom edge
        , seWeight       = 0.3
        , seCoOccurrence = 1
        , seSource       = ExplicitEdge
        , seRelationType = Just RelContrastsWith
        , seVerb         = Nothing
        , seRationale    = Just ("Counter-relation from dialogue feedback: " <> reason)
        , seCounter      = Just reason
        , seSynthesis    = Nothing
        , seConfidence   = 0.3
        , seProvenance   = ProvenanceDialogueFeedback
        , seDomain       = Nothing
        , seTemporalScope = Nothing
        , seNamespace    = Nothing
        , seLineage      = Nothing
        }
  in addEdge reverseKey counterEdge network'

applyClarify :: Text -> SemanticEdge -> SemanticNetwork -> SemanticNetwork
applyClarify detail edge network =
  adjustEdge (seFrom edge, seTo edge)
    (\e -> e { seRationale = updateRationale (seRationale e) })
    network
  where
    updateRationale (Just t) | not (T.null t) = Just (t <> "; " <> detail)
    updateRationale _                          = Just detail

-- | Insert a new edge into the network. If the key already exists,
-- the existing edge is preserved.
addEdge :: (Text, Text) -> SemanticEdge -> SemanticNetwork -> SemanticNetwork
addEdge key edge network =
  network
    { snEdges = M.insertWith (\_new old -> old) key edge (snEdges network)
    , snNodes = S.insert (seFrom edge) (S.insert (seTo edge) (snNodes network))
    }
