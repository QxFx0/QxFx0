{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Dynamic active learning by detecting coverage gaps in the runtime
-- semantic network.
--
-- A coverage gap is a pair of concepts that are not directly connected but
-- share multiple common neighbours.  Such pairs are likely missing links and
-- are good candidates for the next LLM-discovery query.
module QxFx0.Learning.ActiveCoverageGap
  ( CoverageGap(..)
  , GapConfig(..)
  , defaultGapConfig
  , findCoverageGaps
  , findCoverageGapsWithConfig
  ) where

import Control.Applicative ((<|>))
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Network.Types (SemanticEdge(..), SemanticNetwork(..))

-- | A candidate (from, to) pair with a score and human-readable reason.
data CoverageGap = CoverageGap
  { cgFrom   :: !Text
  , cgTo     :: !Text
  , cgScore  :: !Double
  , cgReason :: !Text
  } deriving stock (Eq, Show)

-- | Tunable parameters for gap detection.
data GapConfig = GapConfig
  { gcMinCommonNeighbors :: !Int    -- ^ Minimum number of shared neighbours.
  , gcScoreThreshold     :: !Double -- ^ Minimum gap score to report.
  , gcMaxResults         :: !Int    -- ^ Maximum number of gaps to return.
  }

defaultGapConfig :: GapConfig
defaultGapConfig = GapConfig
  { gcMinCommonNeighbors = 2
  , gcScoreThreshold     = 0.2
  , gcMaxResults         = 10
  }

-- | Find coverage gaps using default configuration.
findCoverageGaps :: [SemanticEdge] -> [CoverageGap]
findCoverageGaps = findCoverageGapsWithConfig defaultGapConfig

-- | Find coverage gaps using explicit configuration.
findCoverageGapsWithConfig :: GapConfig -> [SemanticEdge] -> [CoverageGap]
findCoverageGapsWithConfig cfg edges =
  let net = edgesToNetwork edges
      nodes = S.toList (snNodes net)
      pairs = [ (a, b)
              | a <- nodes
              , b <- nodes
              , a < b
              , not (hasDirectEdge net a b)
              ]
      scored = mapMaybe (scoreGap cfg net) pairs
      sorted = reverse $ M.toList $ M.fromListWith keepHigherScore
                 [ ((cgFrom g, cgTo g), g) | g <- scored ]
      ranked = take (gcMaxResults cfg) $ map snd sorted
  in ranked

-- | Keep the gap with the higher score when collapsing duplicates.
keepHigherScore :: CoverageGap -> CoverageGap -> CoverageGap
keepHigherScore g1 g2 = if cgScore g1 >= cgScore g2 then g1 else g2

-- | Build a 'SemanticNetwork' from an edge list.  Multiple edges for the same
-- (from, to) are merged by keeping the one with highest confidence.
edgesToNetwork :: [SemanticEdge] -> SemanticNetwork
edgesToNetwork edges =
  let insertBest acc e =
        let key = (seFrom e, seTo e)
        in case M.lookup key acc of
             Nothing -> M.insert key e acc
             Just e0 -> if seConfidence e > seConfidence e0
                        then M.insert key e acc
                        else acc
      bestEdges = M.elems $ foldl insertBest M.empty edges
  in SemanticNetwork
       { snNodes = S.fromList $ concatMap (\e -> [seFrom e, seTo e]) bestEdges
       , snEdges = M.fromList [((seFrom e, seTo e), e) | e <- bestEdges]
       , snActivation = M.empty
       , snDecayRate = 0.5
       , snMaxHops = 3
       , snActivationLog = mempty
       }

-- | Check whether a direct edge exists in either direction.
hasDirectEdge :: SemanticNetwork -> Text -> Text -> Bool
hasDirectEdge net a b =
  M.member (a, b) (snEdges net) || M.member (b, a) (snEdges net)

-- | Score a candidate pair.  Returns 'Nothing' if it does not meet the
-- configured thresholds.
scoreGap :: GapConfig -> SemanticNetwork -> (Text, Text) -> Maybe CoverageGap
scoreGap cfg net (a, b) =
  let outsA = outNeighbors net a
      outsB = outNeighbors net b
      -- Common out-neighbours: nodes reachable from both a and b.
      commonOut = M.keysSet (M.intersection outsA outsB)
      -- Common in-neighbours: nodes that reach both a and b.
      insA = inNeighbors net a
      insB = inNeighbors net b
      commonIn = M.keysSet (M.intersection insA insB)
      common = S.toList (commonOut `S.union` commonIn)
      contributions = map (contribution outsA outsB insA insB) common
      total = sum contributions
  in if length common >= gcMinCommonNeighbors cfg && total >= gcScoreThreshold cfg
     then Just CoverageGap
            { cgFrom   = a
            , cgTo     = b
            , cgScore  = total
            , cgReason = "share " <> T.pack (show (length common))
                       <> " neighbour(s): " <> T.intercalate ", " (take 5 common)
            }
     else Nothing

outNeighbors :: SemanticNetwork -> Text -> M.Map Text SemanticEdge
outNeighbors net a =
  M.fromList [ (seTo e, e)
             | e <- M.elems (snEdges net)
             , seFrom e == a
             ]

inNeighbors :: SemanticNetwork -> Text -> M.Map Text SemanticEdge
inNeighbors net b =
  M.fromList [ (seFrom e, e)
             | e <- M.elems (snEdges net)
             , seTo e == b
             ]

-- | Contribution of a single common neighbour to the gap score.
contribution
  :: M.Map Text SemanticEdge   -- ^ out-neighbours of A
  -> M.Map Text SemanticEdge   -- ^ out-neighbours of B
  -> M.Map Text SemanticEdge   -- ^ in-neighbours of A
  -> M.Map Text SemanticEdge   -- ^ in-neighbours of B
  -> Text                      -- ^ common neighbour
  -> Double
contribution outsA outsB insA insB neighbor =
  let fromOut = do eA <- M.lookup neighbor outsA
                   eB <- M.lookup neighbor outsB
                   pure (min (seConfidence eA) (seConfidence eB))
      fromIn  = do eA <- M.lookup neighbor insA
                   eB <- M.lookup neighbor insB
                   pure (min (seConfidence eA) (seConfidence eB))
  in fromMaybe 0 (fromOut <|> fromIn)
