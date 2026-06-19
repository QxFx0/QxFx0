{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Revision
  ( RevisedCommitment(..)
  , ResolutionType(..)
  , SynthesizedResolution(..)
  , revisePosition
  , applyRevisionDecision
  , synthesizeResolution
  ) where

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)
import Data.Set (Set)
import qualified Data.Set as S
import qualified Data.HashMap.Strict as HashMap
import Data.Text (Text)
import Data.Map.Strict (Map)
import QxFx0.Types.State.SemanticCommitment
import QxFx0.Self.Conatus (ConatusEnergy, ceScalar)
import QxFx0.Semantic.Space (tokenizePredicate)
import QxFx0.Types.State.Stance (StanceDefense(..), StanceState(..), stanceConfidence, emptyStanceDefense)
import QxFx0.Semantic.Stance (defendOrAdapt, Collapse(..))

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

-- | Type of contradiction resolution.
data ResolutionType
  = Conjunction     -- ^ "X, и вместе с тем Y" (>=2 shared atoms)
  | Irreducible     -- ^ "X и Y несовместимы в текущей рамке" (<2 shared atoms)
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Synthesized resolution of contradictory commitments.
data SynthesizedResolution = SynthesizedResolution
  { srType      :: !ResolutionType
  , srStatement :: !Text
  , srPayload   :: !FactualClaimPayload
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Synthesize a resolution from two contradictory commitments.
-- Returns Conjunction if >=2 shared atoms, Irreducible otherwise.
synthesizeResolution :: Map Text Text -> FactualClaimPayload -> FactualClaimPayload -> Maybe SynthesizedResolution
synthesizeResolution lemmaMap old new =
  let oldAtoms = tokenizePredicate lemmaMap (fcpStatement old)
      newAtoms = tokenizePredicate lemmaMap (fcpStatement new)
      shared   = S.intersection oldAtoms newAtoms
      combined = fcpStatement old <> ", и вместе с тем " <> fcpStatement new
      irred    = fcpStatement old <> " и " <> fcpStatement new <> " несовместимы в текущей рамке"
  in if S.size shared >= 2
     then Just SynthesizedResolution
       { srType = Conjunction
       , srStatement = combined
       , srPayload = FactualClaimPayload
           { fcpStatement = combined
           , fcpConfidence = 0.5
           , fcpOrigin = OriginSynthetic
           , fcpTurnSeq = fcpTurnSeq new
           , fcpDeps = []
           , fcpTopic = fcpTopic new
           }
       }
     else Just SynthesizedResolution
       { srType = Irreducible
       , srStatement = irred
       , srPayload = FactualClaimPayload
           { fcpStatement = irred
           , fcpConfidence = 0.3
           , fcpOrigin = OriginSynthetic
           , fcpTurnSeq = fcpTurnSeq new
           , fcpDeps = []
           , fcpTopic = fcpTopic new
           }
       }

-- | Determine revision action based on stance defense state (v3.0 pentagon).
--
-- This is now a wrapper around defendOrAdapt that maps StanceDefense back to
-- RevisedCommitment for backward compatibility with applyRevisionDecision.
--
-- Pentagon transitions:
-- - StanceHeld + weak challenge → StanceHeld → RcRetained
-- - StanceHeld + strong challenge → StanceDoubted → RcRetained (defending)
-- - StanceDoubted + strong challenge → StanceRevised → RcRevised
-- - StanceDoubted + low conatus → CollapseConatusExhausted → RcQuarantined
-- - StanceRevised → AdversaryClassified → RcRetained (exit defense cycle)
revisePosition
  :: CommitmentId
  -> ContradictionKind
  -> StanceDefense
  -> ConatusEnergy
  -> Set Text  -- ^ Atoms from user's challenge
  -> Either Collapse RevisedCommitment
revisePosition cid kind sd conatus challengeAtoms =
  case defendOrAdapt sd conatus challengeAtoms of
    Left collapse -> Left collapse
    Right newSd ->
      let newStance = sdStance newSd
      in case newStance of
           StanceRevised _ -> Right $ RcRevised cid kind
           StanceDoubted _ -> Right $ RcRetained cid kind  -- defending, not yet revised
           StanceHeld _ -> Right $ RcRetained cid kind     -- successfully defended

-- | Apply a revision decision to the commitment store.
-- RcQuarantined: move from active to quarantine.
-- RcRevised: reduce confidence by 0.9, record LineageRevised and ContradictionEvent.
--   If newPayload is provided, synthesize a resolution and add it as a new commitment.
-- RcRetained: no action.
applyRevisionDecision
  :: Map Text Text
  -> TurnSeq
  -> SemanticCommitmentStore
  -> Maybe FactualClaimPayload
  -> RevisedCommitment
  -> SemanticCommitmentStore
applyRevisionDecision _lemmaMap ts store _mNewPayload (RcQuarantined cid _kind) =
  case HashMap.lookup cid (scsActive store) of
    Nothing -> store
    Just entry ->
      store
        { scsActive = HashMap.delete cid (scsActive store)
        , scsQuarantine = HashMap.insert cid entry (scsQuarantine store)
        }
applyRevisionDecision lemmaMap ts store mNewPayload (RcRevised cid kind) =
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
          mResolution = case mNewPayload of
            Just newPayload -> synthesizeResolution lemmaMap payload newPayload
            Nothing -> Nothing
          nextCid = CommitmentId (scsNextId store)
          storeWithNextId = store { scsNextId = scsNextId store + 1 }
          storeWithResolution = case mResolution of
            Just resolution ->
              let resMeta = (srPayload resolution, meta)
              in storeWithNextId
                { scsActive = HashMap.insert nextCid resMeta (scsActive storeWithNextId)
                , scsLineage = HashMap.insert nextCid [LineageCommitted ts] (scsLineage storeWithNextId)
                }
            Nothing -> storeWithNextId
      in storeWithResolution
        { scsActive = HashMap.insert cid (revisedPayload, meta) (scsActive storeWithResolution)
        , scsLineage = HashMap.insert cid (oldLineage ++ [LineageRevised ts revisedPayload]) (scsLineage storeWithResolution)
        , scsContradictions = revisionEvent : scsContradictions storeWithResolution
        }
applyRevisionDecision _lemmaMap _ts _store _mNewPayload (RcRetained _cid _kind) = _store
