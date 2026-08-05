{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Memory.Episodic
  ( EpisodicStore(..)
  , EpisodicEvent(..)
  , EpisodicId(..)
  , EpisodicKind(..)
  , EpisodicContent(..)
  , EpisodicIndex(..)
  , EpisodicQuery(..)
  , ForgettingReason(..)
  , ReuseAnnotation(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..), FromJSONKey(..), FromJSONKeyFunction(..)
  , ToJSON(..), ToJSONKey(..), ToJSONKeyFunction(..)
  , object, withObject, (.:), (.=)
  )
import Data.HashMap.Strict (HashMap)
import qualified Data.HashMap.Strict as HM
import Data.HashSet (HashSet)
import qualified Data.HashSet as HS
import Data.Hashable (Hashable)
import Data.List (foldl')
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Decision.Enums.Render (RenderStyle)
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily)
import QxFx0.Types.Self.Deliberation (NarrativeTone)
import QxFx0.Types.State.SemanticCommitment
  ( CommitmentId, ContradictionKind, RetractionReason, TurnSeq )

newtype EpisodicId = EpisodicId { unEpisodicId :: Int }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, Hashable)

data EpisodicKind
  = EpisodicUserInput
  | EpisodicSystemDecision
  | EpisodicCommitment
  | EpisodicContradiction
  | EpisodicRetraction
  | EpisodicUnresolved
  deriving stock (Eq, Show, Generic, Bounded, Enum)
  deriving anyclass (NFData, Hashable)

data EpisodicContent
  = EpisodicUserText !Text
  | EpisodicFamilyDecision !CanonicalMoveFamily
  | EpisodicStyleDecision !RenderStyle
  | EpisodicToneDecision !NarrativeTone
  | EpisodicCommitmentCreated !CommitmentId
  | EpisodicCommitmentRevised !(CommitmentId, TurnSeq)
  | EpisodicCommitmentRetracted !(CommitmentId, RetractionReason)
  | EpisodicContentContradiction !(CommitmentId, CommitmentId, ContradictionKind)
  | EpisodicContentUnresolved !Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data EpisodicEvent = EpisodicEvent
  { eeId      :: !EpisodicId
  , eeTurnSeq :: !TurnSeq
  , eeKind    :: !EpisodicKind
  , eeContent :: !EpisodicContent
  , eeLinked  :: ![CommitmentId]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data EpisodicIndex = EpisodicIndex
  { eiByKind       :: !(HashMap EpisodicKind (HashSet EpisodicId))
  , eiByTurn       :: !(HashMap TurnSeq (HashSet EpisodicId))
  , eiByCommitment :: !(HashMap CommitmentId (HashSet EpisodicId))
  , eiByTag        :: !(HashMap Text (HashSet EpisodicId))
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data EpisodicStore = EpisodicStore
  { esEvents    :: !(Seq EpisodicEvent)
  , esIndex     :: !EpisodicIndex
  , esForgotten :: !(HashSet EpisodicId)
  , esSessionId :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data EpisodicQuery
  = ByKind !EpisodicKind
  | ByCommitment !CommitmentId
  | ByTurnRange !(TurnSeq, TurnSeq)
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ForgettingReason = ForgetByCapacity | ForgetByAge | ForgetByUser | ForgetByPolicy
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

data ReuseAnnotation = ReuseAsContext | ReuseAsConstraint | ReuseAsTrigger | ReuseAsEvidence
  deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

instance ToJSONKey EpisodicId where
  toJSONKey = ToJSONKeyValue (toJSON . unEpisodicId) (toEncoding . unEpisodicId)

instance FromJSONKey EpisodicId where
  fromJSONKey = FromJSONKeyValue (fmap EpisodicId . parseJSON)

instance FromJSON EpisodicId where
  parseJSON value = EpisodicId <$> parseJSON value

instance ToJSON EpisodicId where
  toJSON = toJSON . unEpisodicId
  toEncoding = toEncoding . unEpisodicId

instance FromJSON EpisodicKind
instance ToJSON EpisodicKind

instance ToJSON EpisodicIndex where
  toJSON idx = object
    [ "eiByKind" .= HM.toList (fmap HS.toList (eiByKind idx))
    , "eiByTurn" .= HM.toList (fmap HS.toList (eiByTurn idx))
    , "eiByCommitment" .= HM.toList (fmap HS.toList (eiByCommitment idx))
    , "eiByTag" .= HM.toList (fmap HS.toList (eiByTag idx))
    ]

instance FromJSON EpisodicIndex where
  parseJSON = withObject "EpisodicIndex" $ \o -> do
    byKind <- o .: "eiByKind"
    byTurn <- o .: "eiByTurn"
    byCommitment <- o .: "eiByCommitment"
    byTag <- o .: "eiByTag"
    pure EpisodicIndex
      { eiByKind = HM.fromList [(k, HS.fromList v) | (k, v) <- byKind]
      , eiByTurn = HM.fromList [(k, HS.fromList v) | (k, v) <- byTurn]
      , eiByCommitment = HM.fromList [(k, HS.fromList v) | (k, v) <- byCommitment]
      , eiByTag = HM.fromList [(k, HS.fromList v) | (k, v) <- byTag]
      }

instance ToJSON EpisodicStore where
  toJSON store = object
    [ "esEvents" .= foldr (:) [] (esEvents store)
    , "esForgotten" .= HS.toList (esForgotten store)
    , "esSessionId" .= esSessionId store
    ]

instance FromJSON EpisodicStore where
  parseJSON = withObject "EpisodicStore" $ \o -> do
    events <- o .: "esEvents"
    forgotten <- o .: "esForgotten"
    sid <- o .: "esSessionId"
    let eventSeq = Seq.fromList events
    pure EpisodicStore
      { esEvents = eventSeq
      , esIndex = rebuildIndexForCodec eventSeq
      , esForgotten = HS.fromList forgotten
      , esSessionId = sid
      }

rebuildIndexForCodec :: Seq EpisodicEvent -> EpisodicIndex
rebuildIndexForCodec = foldl' indexEventForCodec emptyIndexForCodec

emptyIndexForCodec :: EpisodicIndex
emptyIndexForCodec = EpisodicIndex HM.empty HM.empty HM.empty HM.empty

indexEventForCodec :: EpisodicIndex -> EpisodicEvent -> EpisodicIndex
indexEventForCodec idx event = idx
  { eiByKind = HM.insertWith HS.union (eeKind event) singleton (eiByKind idx)
  , eiByTurn = HM.insertWith HS.union (eeTurnSeq event) singleton (eiByTurn idx)
  , eiByCommitment = foldl' (\acc cid -> HM.insertWith HS.union cid singleton acc)
      (eiByCommitment idx) (eeLinked event)
  , eiByTag = case eeContent event of
      EpisodicContentUnresolved tag -> HM.insertWith HS.union tag singleton (eiByTag idx)
      _ -> eiByTag idx
  }
  where
    singleton = HS.singleton (eeId event)
