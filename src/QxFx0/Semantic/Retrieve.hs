module QxFx0.Semantic.Retrieve
  ( retrieve
  , detectCommitmentEngagement
  ) where

import qualified Data.HashMap.Strict as HashMap
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Domain.Atoms (AtomTag(..), MeaningAtom(..), AtomSet(..))
import QxFx0.Types.State.SemanticCommitment

-- | Retrieve active commitments whose statement shares a word overlap
--   with the query (case-insensitive). Returns up to 5 matches.
--   This is intentionally a simple bag-of-words overlap; the closure
--   plan's Package 7 extends retrieval with indexing, episodic memory,
--   and forgetting policy.
retrieve
  :: Text
  -> SemanticCommitmentStore
  -> [FactualClaimPayload]
retrieve query store =
  let queryWords = map T.toLower (T.words query)
      matches = filter (overlaps queryWords) (map fst (HashMap.elems (scsActive store)))
  in take 5 matches
  where
    overlaps qWords payload =
      let stmt = T.toLower (fcpStatement payload)
      in any (`T.isInfixOf` stmt) qWords

-- | Detect whether the current turn engages or contradicts held commitments.
-- Engaged = retrieve overlap with active store; Contradicted = engaged + Contradiction atom.
detectCommitmentEngagement
  :: SemanticCommitmentStore
  -> Text
  -> AtomSet
  -> CommitmentEngagement
detectCommitmentEngagement store inputTopic atomSet =
  let queryWords = map T.toLower (T.words inputTopic)
      active = scsActive store
      engagedPairs =
        filter (\(_, (payload, _)) ->
          let stmt = T.toLower (fcpStatement payload)
          in any (`T.isInfixOf` stmt) queryWords
        ) (HashMap.toList active)
      engagedIds = map fst engagedPairs
      hasContradiction = any (\a -> case maTag a of Contradiction _ _ -> True; _ -> False) (asAtoms atomSet)
  in CommitmentEngagement
       { ceEngaged      = engagedIds
       , ceContradicted = not (null engagedIds) && hasContradiction
       }
