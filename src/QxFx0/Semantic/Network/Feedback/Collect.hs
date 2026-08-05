{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Feedback.Collect
  ( collectUsedEdges
  , applyDetectedFeedback
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)

import QxFx0.Semantic.Network.Feedback (applyFeedback)
import QxFx0.Semantic.Network.Feedback.Detect (detectUserFeedback)
import QxFx0.Semantic.Network.Types
  ( ActivationArtifact(..)
  , ActivationStep(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )

-- | Collect the semantic edges that were actually traversed by a turn.
--
-- Each 'ActivationStep' records a target node ('asNode') and the node it
-- was reached via ('asVia').  This function looks up @(asVia, asNode)@ in
-- the supplied network and returns the matching edges, deduplicated by
-- their @(seFrom, seTo)@ endpoints and preserving the order of first
-- appearance.
collectUsedEdges :: SemanticNetwork -> [ActivationStep] -> [SemanticEdge]
collectUsedEdges network steps =
  go S.empty steps []
  where
    go _seen [] acc = reverse acc
    go seen (step : rest) acc =
      case M.lookup (asVia step, asNode step) (snEdges network) of
        Just edge
          | let key = (seFrom edge, seTo edge)
          , not (S.member key seen)
          -> go (S.insert key seen) rest (edge : acc)
        _ -> go seen rest acc

-- | Apply detected user feedback to a semantic network in one step.
--
-- This is a thin runtime wrapper over 'detectUserFeedback',
-- 'collectUsedEdges' and 'applyFeedback': it uses the previous rendered
-- activation artifact's captured edges and applies the feedback to
-- the /base/ network (typically the merged network for the new turn).  If
-- the feedback loop is disabled or no marker is found, the base network is
-- returned unchanged.
applyDetectedFeedback :: Bool -> Text -> Maybe ActivationArtifact -> SemanticNetwork -> SemanticNetwork
applyDetectedFeedback feedbackLoopActive raw mArtifact baseNetwork
  | not feedbackLoopActive = baseNetwork
  | otherwise =
      case detectUserFeedback raw of
        Nothing -> baseNetwork
        Just feedback ->
          applyFeedback baseNetwork (maybe [] aaUsedEdges mArtifact) feedback
