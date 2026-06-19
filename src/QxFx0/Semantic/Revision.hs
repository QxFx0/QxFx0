{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Semantic.Revision
  ( RevisedCommitment(..)
  , revisePosition
  , applyRevisionDecision
  ) where

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)
import qualified Data.HashMap.Strict as HashMap
import QxFx0.Types.State.SemanticCommitment (CommitmentId, ContradictionKind, SemanticCommitmentStore(..), TurnSeq, LineageEvent(..), ContradictionEvent(..), FactualClaimPayload(..))
import QxFx0.Self.Conatus (ConatusEnergy, ceScalar)

-- | Result of contradiction-driven revision.
data RevisedCommitment
  = RcRevised !CommitmentId !ContradictionKind
    -- ^ High angst → flexible position, revise the commitment
  | RcQuarantined !CommitmentId !ContradictionKind
    -- ^ Low conatus → weak position, quarantine the commitment
  | RcRetained !CommitmentId !ContradictionKind
    -- ^ Stable state → retain the commitment despite contradiction
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Determine revision action based on self-state.
--
-- Decision thresholds:
-- - angst > 0.7 → RcRevised (high anxiety → flexibility)
-- - conatus < 5.0 → RcQuarantined (weak energy → quarantine)
-- - otherwise → RcRetained (stable → retain)
revisePosition
  :: CommitmentId
  -> ContradictionKind
  -> Double  -- ^ angst level
  -> ConatusEnergy
  -> RevisedCommitment
revisePosition cid kind angst conatus
  | angst > 0.7 = RcRevised cid kind
  | ceScalar conatus < 5.0 = RcQuarantined cid kind
  | otherwise = RcRetained cid kind

-- | Apply a revision decision to the commitment store.
-- RcQuarantined: move from active to quarantine.
-- RcRevised: reduce confidence by 0.9, record LineageRevised and ContradictionEvent.
-- RcRetained: no action.
applyRevisionDecision
  :: TurnSeq
  -> SemanticCommitmentStore
  -> RevisedCommitment
  -> SemanticCommitmentStore
applyRevisionDecision ts store (RcQuarantined cid _kind) =
  case HashMap.lookup cid (scsActive store) of
    Nothing -> store
    Just entry ->
      store
        { scsActive = HashMap.delete cid (scsActive store)
        , scsQuarantine = HashMap.insert cid entry (scsQuarantine store)
        }
applyRevisionDecision ts store (RcRevised cid kind) =
  case HashMap.lookup cid (scsActive store) of
    Nothing -> store
    Just (payload, meta) ->
      let revisedPayload = payload { fcpConfidence = fcpConfidence payload * 0.9 }
          oldLineage = HashMap.lookupDefault [] cid (scsLineage store)
          revisionEvent = ContradictionEvent
            { ceLeft = cid
            , ceRight = cid
            , ceKind = kind
            , ceTurnSeq = ts
            }
      in store
        { scsActive = HashMap.insert cid (revisedPayload, meta) (scsActive store)
        , scsLineage = HashMap.insert cid (oldLineage ++ [LineageRevised ts revisedPayload]) (scsLineage store)
        , scsContradictions = revisionEvent : scsContradictions store
        }
applyRevisionDecision _ts store (RcRetained _cid _kind) = store
