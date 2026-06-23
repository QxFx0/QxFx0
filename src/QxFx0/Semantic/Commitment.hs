module QxFx0.Semantic.Commitment
  ( commit
  , commitObservation
  , quarantineObservation
  , promoteMatchingQuarantine
  , revise
  , contradict
  ) where

import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.State.SemanticCommitment

-- | Create a commitment from a parsed observation.
-- No-op if the id already exists in either active or lineage.
commit
  :: CommitmentId
  -> FactualClaimPayload
  -> SemanticCommitmentStore
  -> SemanticCommitmentStore
commit cid payload store
  | HashMap.member cid (scsActive store) = store
  | HashMap.member cid (scsLineage store) = store
  | otherwise = store
      { scsActive  = HashMap.insert cid (payload, ts) (scsActive store)
      , scsLineage = HashMap.insert cid [LineageCommitted ts] (scsLineage store)
      }
  where
    ts = fcpTurnSeq payload

-- | Auto-generate a commitment ID and store the claim.
-- Returns the updated store and the generated id so callers can reference
-- the new commitment without the fragile 'scsNextId - 1' pattern.
commitObservation
  :: FactualClaimPayload
  -> SemanticCommitmentStore
  -> (SemanticCommitmentStore, CommitmentId)
commitObservation payload store =
  let cid = CommitmentId (scsNextId store)
      store' = store { scsNextId = scsNextId store + 1 }
  in (commit cid payload store', cid)

-- | Auto-generate a commitment ID and place the claim in quarantine.
-- Uses the shared 'scsNextId' so active and quarantine ids never collide.
quarantineObservation
  :: FactualClaimPayload
  -> SemanticCommitmentStore
  -> SemanticCommitmentStore
quarantineObservation payload store =
  let cid = CommitmentId (scsNextId store)
      ts  = fcpTurnSeq payload
  in store
       { scsQuarantine = HashMap.insert cid (payload, ts) (scsQuarantine store)
       , scsNextId     = scsNextId store + 1
       }

-- | Promote quarantined claims whose normalized statement matches the given
-- statement into the active store. The active commitment's lineage receives
-- a 'LineagePromoted' entry. Returns the updated store and the count of
-- promoted claims.
promoteMatchingQuarantine
  :: CommitmentId
  -> Text
  -> SemanticCommitmentStore
  -> (SemanticCommitmentStore, Int)
promoteMatchingQuarantine cid statement store =
  let norm = T.toLower . T.strip
      target = norm statement
      matching =
        HashMap.filter (\(payload, _) -> norm (fcpStatement payload) == target)
          (scsQuarantine store)
      promotedCount = HashMap.size matching
      store' = store { scsQuarantine = HashMap.difference (scsQuarantine store) matching }
      store'' = case HashMap.lookup cid (scsActive store') of
        Just (_, ts) ->
          let oldLineage = HashMap.lookupDefault [] cid (scsLineage store')
          in store'
               { scsLineage =
                   HashMap.insert cid (oldLineage ++ [LineagePromoted ts])
                     (scsLineage store')
               }
        Nothing -> store'
  in (store'', promotedCount)

-- | Replace a commitment's content; preserves the id.
revise
  :: CommitmentId
  -> FactualClaimPayload
  -> SemanticCommitmentStore
  -> SemanticCommitmentStore
revise cid newPayload store =
  case HashMap.lookup cid (scsActive store) of
    Nothing -> store
    Just _  ->
      let ts = fcpTurnSeq newPayload
          lineage  = HashMap.lookup cid (scsLineage store)
          newEntry = LineageRevised ts newPayload
      in store
           { scsActive  = HashMap.insert cid (newPayload, ts) (scsActive store)
           , scsLineage = HashMap.insert cid (maybe [newEntry] (++ [newEntry]) lineage) (scsLineage store)
           }

-- | Record a contradiction between two commitments.
contradict
  :: CommitmentId
  -> CommitmentId
  -> ContradictionKind
  -> TurnSeq
  -> SemanticCommitmentStore
  -> SemanticCommitmentStore
contradict left right kind ts store =
  let event = ContradictionEvent left right kind ts
  in store { scsContradictions = event : scsContradictions store }
