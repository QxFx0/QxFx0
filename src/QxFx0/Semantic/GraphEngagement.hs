{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.GraphEngagement
Description : Find the system's relationship to a user proposition.

Given a parsed proposition and the runtime graph, finds:
  - Supporting edges (that align with the user's claim)
  - Contradicting edges (that counter the user's claim)
  - Qualifying edges (that refine/nuance the claim)
  - Path between subject and object (for connect mode)
  - Context edges from previous turns

This is the core "orientation" step: the system looks at the graph
and determines its stance relative to what the user said.
-}
module QxFx0.Semantic.GraphEngagement
  ( EngagementResult(..)
  , engageWithProposition
  , findSupporting
  , findContradicting
  , findQualifying
  , findPath
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.List (sortBy, nub, filter, find, isInfixOf)
import Data.Maybe (fromMaybe, mapMaybe, listToMaybe)
import Data.Ord (comparing, Down(..))
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.PropositionParser
import QxFx0.Semantic.DialogueContext

-- | The system's relationship to a user proposition.
data EngagementResult = EngagementResult
  { erSupporting :: ![Relation]    -- edges that align with the claim
  , erContradicting :: ![Relation] -- edges that counter the claim
  , erQualifying :: ![Relation]    -- edges that refine/nuance
  , erPath :: ![Relation]          -- path between subject and object
  , erContext :: ![Relation]       -- edges from previous turns
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Engage with a proposition: find the system's relationship to it.
engageWithProposition :: AtomGraph -> DialogueContext -> ParsedProposition -> EngagementResult
engageWithProposition graph ctx prop =
  let subjectAtom = AtomId (ppSubject prop)
      objectAtom = fmap AtomId (ppObject prop)
      allSubjectRels = graphRelationsFromAtom graph subjectAtom

      -- Find supporting edges (non-counter types that align with claim)
      supporting = findSupporting allSubjectRels (ppClaim prop)

      -- Find contradicting edges (counter types)
      contradicting = findContradicting allSubjectRels

      -- Find qualifying edges (presupposes, requires, includes)
      qualifying = findQualifying allSubjectRels

      -- Find path between subject and object
      path = case objectAtom of
        Just obj -> findPath graph subjectAtom obj
        Nothing -> []

      -- Get context relations from previous turns
      contextRels = filter (not . isUsedRelation ctx)
                  $ getContextRelations ctx

  in EngagementResult
       { erSupporting = take 3 supporting
       , erContradicting = take 2 contradicting
       , erQualifying = take 2 qualifying
       , erPath = path
       , erContext = take 3 contextRels
       }

-- | Find edges that support the user's claim.
-- Non-counter relation types are considered supporting.
findSupporting :: [Relation] -> Maybe Text -> [Relation]
findSupporting rels mClaim =
  let counterTypes = [RelContrastsWith, RelNotReducibleTo, RelIsNot, RelNegates, RelDestroys]
      nonCounter = filter (\r -> relType r `notElem` counterTypes) rels
  in case mClaim of
       Just claim ->
         -- Prefer edges whose text overlaps with the claim
         let scored = sortBy (comparing (\r ->
               negate (overlapScore claim (relRuOriginal r)))) nonCounter
         in scored
       Nothing -> nonCounter

-- | Find edges that contradict the user's claim.
-- Counter relation types: contrasts, not-reducible, is-not, negates, destroys,
-- and limited-by (which qualifies claims about unlimited nature).
findContradicting :: [Relation] -> [Relation]
findContradicting rels =
  let counterTypes = [RelContrastsWith, RelNotReducibleTo, RelIsNot, RelNegates
                     , RelDestroys, RelLimitedBy]
  in filter (\r -> relType r `elem` counterTypes) rels

-- | Find edges that qualify the user's claim.
-- Presupposes, requires, includes — these add nuance without contradicting.
findQualifying :: [Relation] -> [Relation]
findQualifying rels =
  let qualifyTypes = [RelPresupposes, RelRequires, RelIncludes, RelNecessaryFor
                     , RelBuiltThrough, RelReliesOn]
  in filter (\r -> relType r `elem` qualifyTypes) rels

-- | Find a path between two atoms in the graph.
-- BFS up to depth 3. Returns the path as a list of relations.
findPath :: AtomGraph -> AtomId -> AtomId -> [Relation]
findPath graph start target =
  if start == target
    then []
    else bfs graph start target 3 []

-- | BFS helper for path finding.
bfs :: AtomGraph -> AtomId -> AtomId -> Int -> [AtomId] -> [Relation]
bfs graph current target depth visited =
  if depth <= 0 || current `elem` visited
    then []
    else
      let neighbors = graphRelationsFromAtom graph current
          -- Check if any neighbor reaches target
          directHit = find (\r -> relTo r == target) neighbors
      in case directHit of
           Just r -> [r]
           Nothing ->
             -- Try deeper
             let newVisited = current : visited
                 deeper = [ r : bfs graph (relTo r) target (depth - 1) newVisited
                          | r <- neighbors
                          , relTo r `notElem` visited
                          ]
                 validPaths = filter (not . null) deeper
             in case validPaths of
                  (p:_) -> p
                  [] -> []

-- | Calculate overlap score between claim text and relation text.
overlapScore :: Text -> Text -> Double
overlapScore claim relText =
  let claimWords = T.words (T.toLower claim)
      relWords = T.words (T.toLower relText)
      overlap = length [ w | w <- claimWords, w `elem` relWords ]
  in fromIntegral overlap / fromIntegral (max 1 (length claimWords))
