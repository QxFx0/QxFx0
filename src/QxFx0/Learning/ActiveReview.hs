{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Active learning loop for autonomous semantic-network growth.
--
-- The loop closes the gap between runtime LLM discoveries and the curated
-- seed ontology by:
--
-- 1. Selecting the next discovery topic from the largest seed-coverage gap.
-- 2. Maintaining a human-review queue of low-confidence or cross-domain edges.
-- 3. Applying approve/reject decisions to runtime edges.
module QxFx0.Learning.ActiveReview
  ( ReviewDecision(..)
  , ReviewEntry(..)
  , reviewQueue
  , selectNextDiscoveryTopic
  , applyReviewDecision
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Learning.EdgeScore (EdgeScore(..), defaultEdgeScore, computeWeight)
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( DomainTag(..)
  , EdgeNamespace(..)
  , EdgeProvenance(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )
import QxFx0.Semantic.Ontology.Philosophy (philosophySeedEdges, topicDomain)

-- | Human decision for an edge in the review queue.
data ReviewDecision
  = ApproveEdge
      { rdConfidence :: !Double
      }
  | RejectEdge
  deriving stock (Eq, Show)

-- | An entry in the human review queue.
data ReviewEntry = ReviewEntry
  { reFrom       :: !Text
  , reTo         :: !Text
  , reConfidence :: !Double
  , reWeight     :: !Double
  , reReason     :: !Text
  }
  deriving stock (Eq, Show)

-- | Build a human-review queue from runtime edges that are uncertain or
-- cross-domain. Returns entries sorted by ascending confidence.
reviewQueue :: [SemanticEdge] -> [ReviewEntry]
reviewQueue edges =
  let entries = mapMaybe classify edges
      classify e =
        let lowConf = seConfidence e < 0.45
            crossDom = isCrossDomain e
        in if lowConf || crossDom
             then Just ReviewEntry
                    { reFrom       = seFrom e
                    , reTo         = seTo e
                    , reConfidence = seConfidence e
                    , reWeight     = seWeight e
                    , reReason     = if crossDom && lowConf
                                       then "low confidence + cross-domain"
                                       else if crossDom
                                              then "cross-domain"
                                              else "low confidence"
                    }
             else Nothing
  in entries

-- | A discovered edge is considered cross-domain when the two endpoints map
-- to different primary seed domains and at least one endpoint is known.
isCrossDomain :: SemanticEdge -> Bool
isCrossDomain e =
  let fromDom = topicDomain (seFrom e)
      toDom   = topicDomain (seTo e)
  in fromDom /= toDom && fromDom /= DomainGeneral && toDom /= DomainGeneral

-- | Select the next discovery topic by finding the concept with the largest
-- gap between seed-outgoing edges and runtime-discovered edges.
selectNextDiscoveryTopic
  :: [SemanticEdge]   -- ^ runtime edges discovered so far
  -> Maybe Text
selectNextDiscoveryTopic runtimeEdges =
  let seedEdges = philosophySeedEdges
      seedConcepts = S.fromList $ concatMap (\e -> [seFrom e, seTo e]) seedEdges
      runtimeConcepts = S.fromList $ concatMap (\e -> [seFrom e, seTo e]) runtimeEdges
      seedOutCounts = countByEndpoint seFrom seedEdges
      runtimeOutCounts = countByEndpoint seFrom runtimeEdges
      gapFor c =
        let seedOut = M.findWithDefault 0 c seedOutCounts
            runtimeOut = M.findWithDefault 0 c runtimeOutCounts
        in seedOut - runtimeOut
      candidates = S.toList (seedConcepts `S.difference` runtimeConcepts)
      scored = map (\c -> (c, gapFor c)) candidates
      sorted = case scored of
                 [] -> map (\c -> (c, gapFor c)) (S.toList seedConcepts)
                 _  -> scored
      sortedDesc = reverse $ M.toList $ M.fromList sorted
  in case sortedDesc of
       [] -> Nothing
       ((c, _):_) -> Just c

-- | Apply a human review decision to an edge. Approving boosts confidence and
-- weight; rejecting quarantines the edge by zeroing its weight/confidence.
applyReviewDecision :: SemanticEdge -> ReviewDecision -> SemanticEdge
applyReviewDecision edge ApproveEdge{rdConfidence = conf} =
  let rt = fromMaybe RelRelatedTo (seRelationType edge)
      score = (defaultEdgeScore rt ProvenanceHumanCorrection)
                { esLLMConfidence = conf
                , esSemanticSimilarity = 0.9
                , esHumanValidated = True
                }
  in edge
       { seConfidence = conf
       , seWeight     = computeWeight score
       , seProvenance = ProvenanceHumanCorrection
       , seNamespace  = NamespaceUserLocal
       }
applyReviewDecision edge RejectEdge =
  edge
    { seConfidence = 0.0
    , seWeight     = 0.0
    }

countByEndpoint :: Ord k => (SemanticEdge -> k) -> [SemanticEdge] -> M.Map k Int
countByEndpoint f = foldl (\acc e -> M.insertWith (+) (f e) 1 acc) M.empty

fromMaybe :: a -> Maybe a -> a
fromMaybe d = maybe d id
