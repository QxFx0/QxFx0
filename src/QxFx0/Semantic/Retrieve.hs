module QxFx0.Semantic.Retrieve
  ( retrieve
  ) where

import qualified Data.HashMap.Strict as HashMap
import Data.Text (Text)
import qualified Data.Text as T

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
