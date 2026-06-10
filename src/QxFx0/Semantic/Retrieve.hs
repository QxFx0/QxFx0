{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Retrieve
  ( retrieve
  , detectCommitmentEngagement
  ) where

import qualified Data.HashMap.Strict as HashMap
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Domain.Atoms (AtomTag(..), MeaningAtom(..), AtomSet(..))
import QxFx0.Types.State.SemanticCommitment

-- | Minimal hard-coded stop words (Russian + English articles/prepositions).
--   Kept small and explicit per SEAM-2 spec: "список держать маленьким и явным".
stopWords :: Set.Set Text
stopWords = Set.fromList
  [ "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "of", "for"
  , "и", "или", "но", "в", "на", "к", "с", "по", "за", "от", "для", "о", "об"
  , "это", "тот", "та", "то", "который", "которая", "которое"
  , "is", "are", "was", "were", "be", "been", "being"
  , "есть", "был", "была", "было", "были"
  ]

-- | Engagement threshold: number of significant shared words required.
--   SEAM-2 starts at 1 significant word (length ≥3).
engagementThreshold :: Int
engagementThreshold = 1

-- | Extract significant words from a text: lower-case, split on non-alphanumeric,
--   drop empty, drop ≤2 chars, drop stop words.
significantWords :: Text -> Set.Set Text
significantWords t =
  let raw = T.words (T.map (\c -> if isAlnum c then c else ' ') (T.toLower t))
      filtered = filter (\w -> T.length w >= 3 && not (Set.member w stopWords)) raw
  in Set.fromList filtered
  where
    isAlnum c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
             || (c >= '0' && c <= '9') || c >= '\x0400' && c <= '\x04FF'

-- | Word-set overlap between two texts. Returns the number of significant
--   shared words (for observability) and a Bool for the threshold.
wordSetOverlap :: Text -> Text -> (Int, Bool)
wordSetOverlap topic stmt =
  let topicWords = significantWords topic
      stmtWords  = significantWords stmt
      shared     = Set.intersection topicWords stmtWords
      count      = Set.size shared
  in (count, count >= engagementThreshold)

-- | Retrieve active commitments whose statement shares significant word overlap
--   with the query (case-insensitive, whole-word, threshold ≥1).
--   Returns up to 5 matches.
retrieve
  :: Text
  -> SemanticCommitmentStore
  -> [FactualClaimPayload]
retrieve query store =
  let matches = filter (overlaps query) (map fst (HashMap.elems (scsActive store)))
  in take 5 matches
  where
    overlaps q payload = snd (wordSetOverlap q (fcpStatement payload))

-- | A contradiction token is considered "poor" (uninformative) if it is the literal
--   "amplified" or too short (≤2 chars). Poor tokens cannot be scoped to a claim
--   and trigger a weak fallback.
isPoorToken :: Text -> Bool
isPoorToken tok = tok == "amplified" || T.length tok <= 2

-- | Detect whether the current turn engages or contradicts held commitments.
-- Engaged = significant word overlap (whole-word, threshold ≥1) with active store.
-- Contradicted = engaged AND (contradiction atom scoped to engaged claim OR poor-token fallback).
--
-- SEAM-2 Phase 1: word-set overlap + significance threshold.
-- SEAM-2 Phase 2: scope contradiction to the engaged topic (cross-topic FP fix).
detectCommitmentEngagement
  :: SemanticCommitmentStore
  -> Text
  -> AtomSet
  -> CommitmentEngagement
detectCommitmentEngagement store inputTopic atomSet =
  let active = scsActive store
      engagedPairs =
        filter (\(_, (payload, _)) ->
          snd (wordSetOverlap inputTopic (fcpStatement payload))
        ) (HashMap.toList active)
      engagedIds = map fst engagedPairs
      engagedPayloads = map (fst . snd) engagedPairs
      contradictionAtoms = filter (\a -> case maTag a of Contradiction _ _ -> True; _ -> False) (asAtoms atomSet)
      -- Strong: contradiction token shares significant words with an engaged claim.
      contradictionScoped = any (\atom ->
        case maTag atom of
          Contradiction tokL tokR ->
            any (\payload ->
                let stmt = fcpStatement payload
                in  snd (wordSetOverlap tokL stmt)
                 || snd (wordSetOverlap tokR stmt)
            ) engagedPayloads
          _ -> False
        ) contradictionAtoms
      -- Weak fallback: contradiction atom exists but only carries poor tokens.
      hasPoorContradiction = any (\atom ->
        case maTag atom of
          Contradiction tokL tokR -> isPoorToken tokL && isPoorToken tokR
          _ -> False
        ) contradictionAtoms
      matchKind
        | null engagedIds = NoMatch
        | not (null engagedIds) && contradictionScoped = ContradictedStrong
        | not (null engagedIds) && hasPoorContradiction = ContradictedWeak
        | otherwise = EngagedOnly
  in CommitmentEngagement
       { ceEngaged      = engagedIds
       , ceContradicted = not (null engagedIds) && (contradictionScoped || hasPoorContradiction)
       , ceMatchKind    = matchKind
       }
