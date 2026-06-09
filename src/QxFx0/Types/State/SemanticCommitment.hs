{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Types.State.SemanticCommitment
  ( SemanticCommitment(..)
  , FactualClaimPayload(..)
  , CommitmentId(..)
  , CommitmentOrigin(..)
  , TurnSeq(..)
  , SemanticCommitmentStore(..)
  , LineageEvent(..)
  , ContradictionEvent(..)
  , RetractionReason(..)
  , ContradictionKind(..)
  , emptySemanticCommitmentStore
  , quarantinedClaims
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HashMap
import Data.Hashable (Hashable)
import Data.Text (Text)
import GHC.Generics (Generic)

-- | Monotonic turn counter scoped to a session.
newtype TurnSeq = TurnSeq { unTurnSeq :: Int }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Hashable, NFData, ToJSON, FromJSON)

-- | Unique commitment identifier within a session.
newtype CommitmentId = CommitmentId { unCommitmentId :: Int }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Hashable, NFData, ToJSON, FromJSON)

-- | Where a commitment originated.
data CommitmentOrigin
  = OriginParser !Text
  | OriginDialogueOutcome !Int
  | OriginManual
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | One commitment class in the Σ-type: a factual claim.
data SemanticCommitment
  = FactualClaim !FactualClaimPayload
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Payload of a factual claim commitment.
data FactualClaimPayload = FactualClaimPayload
  { fcpStatement  :: !Text
  , fcpConfidence :: !Double
  , fcpOrigin     :: !CommitmentOrigin
  , fcpTurnSeq    :: !TurnSeq
  , fcpDeps       :: ![CommitmentId]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Reason for retraction.
data RetractionReason
  = RetractionUserDenied
  | RetractionParserContradiction
  | RetractionOutOfScope
  | RetractionSuperseded
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Kind of contradiction between two commitments.
data ContradictionKind
  = ContradictionStatement
  | ContradictionScope
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | An event in a commitment's lineage.
data LineageEvent
  = LineageCommitted !TurnSeq
  | LineageRevised !TurnSeq !FactualClaimPayload
  | LineageRetracted !TurnSeq !RetractionReason
  | LineagePromoted !TurnSeq
    -- ^ CTS-44: promoted from quarantine to active on this turn.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | A recorded contradiction between two commitments.
data ContradictionEvent = ContradictionEvent
  { ceLeft    :: !CommitmentId
  , ceRight   :: !CommitmentId
  , ceKind    :: !ContradictionKind
  , ceTurnSeq :: !TurnSeq
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | The commitment store.
data SemanticCommitmentStore = SemanticCommitmentStore
  { scsActive     :: !(HashMap CommitmentId (FactualClaimPayload, TurnSeq))
  , scsQuarantine :: !(HashMap CommitmentId (FactualClaimPayload, TurnSeq))
  , scsLineage    :: !(HashMap CommitmentId [LineageEvent])
  , scsContradictions :: ![ContradictionEvent]
  , scsNextId     :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SemanticCommitmentStore where
  toJSON store = object
    [ "scsActive" .= mapToList (scsActive store)
    , "scsQuarantine" .= mapToList (scsQuarantine store)
    , "scsLineage" .= mapToList (scsLineage store)
    , "scsContradictions" .= scsContradictions store
    , "scsNextId" .= scsNextId store
    ]
    where mapToList = HashMap.toList

instance FromJSON SemanticCommitmentStore where
  parseJSON = withObject "SemanticCommitmentStore" $ \o ->
    SemanticCommitmentStore
      <$> (HashMap.fromList <$> o .: "scsActive")
      <*> (HashMap.fromList <$> o .:? "scsQuarantine" .!= [])
      <*> (HashMap.fromList <$> o .: "scsLineage")
      <*> o .: "scsContradictions"
      <*> o .: "scsNextId"

-- | Empty store with no commitments.
emptySemanticCommitmentStore :: SemanticCommitmentStore
emptySemanticCommitmentStore = SemanticCommitmentStore
  { scsActive     = HashMap.empty
  , scsQuarantine = HashMap.empty
  , scsLineage    = HashMap.empty
  , scsContradictions = []
  , scsNextId     = 1
  }

-- | Review-visibility accessor: claims currently in quarantine.
quarantinedClaims :: SemanticCommitmentStore -> [FactualClaimPayload]
quarantinedClaims = map fst . HashMap.elems . scsQuarantine


