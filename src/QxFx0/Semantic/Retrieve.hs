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

-- | Detect whether the current turn engages or contradicts held commitments.
-- Engaged = significant word overlap (whole-word, threshold ≥1) with active store.
-- Contradicted = engaged + presence of Contradiction atom in the turn.
--
-- SEAM-2 Phase 1: replaced isInfixOf with word-set overlap + significance threshold.
-- SEAM-2 Phase 2 will scope the contradiction to the engaged topic.
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
      hasContradiction = any (\a -> case maTag a of Contradiction _ _ -> True; _ -> False) (asAtoms atomSet)
  in CommitmentEngagement
       { ceEngaged      = engagedIds
       , ceContradicted = not (null engagedIds) && hasContradiction
       }
