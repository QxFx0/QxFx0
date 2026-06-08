{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Memory.Episodic
  ( EpisodicStore (..)
  , EpisodicEvent (..)
  , EpisodicId (..)
  , EpisodicKind (..)
  , EpisodicContent(..)
  , EpisodicIndex (..)
  , EpisodicQuery (..)
  , ForgettingReason (..)
  , ReuseAnnotation (..)
  , emptyIndex
  , rebuildIndex
  , encode
  , retrieve
  , recallForTrace
  , episodicRecallActive
  , forget
  , enforceCapacity
  , enforceAgeWindow
  , episodicCapacity
  , episodicWindow
  ) where

import QxFx0.Types.State.SemanticCommitment
  ( CommitmentId (..)
  , TurnSeq (..)
  , RetractionReason (..)
  , ContradictionKind (..)
  )
import QxFx0.Types.Decision.Enums.Render (RenderStyle (..))
import QxFx0.Self.Deliberation (NarrativeTone (..))
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily (..))

import Data.Aeson (FromJSON(..), ToJSON(..), ToJSONKey(..), FromJSONKey(..), ToJSONKeyFunction(..), FromJSONKeyFunction(..), object, withObject, (.:), (.=))
import Data.HashSet (HashSet)
import Data.HashMap.Strict (HashMap)
import Control.DeepSeq (NFData)
import Data.Hashable (Hashable(..))
import Data.List (foldl')
import Data.Sequence (Seq (..), (|>))
import Data.Text (Text)
import GHC.Generics (Generic)
import qualified Data.HashSet as HS
import qualified Data.HashMap.Strict as HM
import qualified Data.Sequence as Seq

episodicCapacity :: Int
episodicCapacity = 1000

episodicWindow :: TurnSeq
episodicWindow = TurnSeq 50

-- | WP-B: default-on promotion flag gating live episodic recall on the turn
-- path. Promoted to default-on 2026-06-04 (P0 Stage 1, ADR-0034 §Promotion);
-- registered in the flag-off discipline (@scripts/check_architecture.sh@ rule [20]).
episodicRecallActive :: Bool
episodicRecallActive = True

-- | WP-B: a living consumer of 'retrieve'. Runs a deterministic recall query
-- over the episodic store and reports the query together with how many events
-- it returned, for the turn-projection trace @trcEpisodicRetrieval@. Pure and
-- deterministic; returns 'Nothing' when there is no store. This is the
-- anti-rot consumer guarded by @docs/anti_rot_registry.tsv@ (ADR-0042).
recallForTrace :: Maybe EpisodicStore -> Maybe (EpisodicQuery, Int)
recallForTrace Nothing      = Nothing
recallForTrace (Just store) =
  let q  = ByKind EpisodicUserInput
      rs = retrieve q store
  in Just (q, length rs)

newtype EpisodicId = EpisodicId { unEpisodicId :: Int }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data EpisodicKind
  = EpisodicUserInput
  | EpisodicSystemDecision
  | EpisodicCommitment
  | EpisodicContradiction
  | EpisodicRetraction
  | EpisodicUnresolved
  deriving stock (Eq, Show, Generic, Bounded, Enum)
  deriving anyclass (NFData)

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
  deriving anyclass (NFData)

data EpisodicEvent = EpisodicEvent
  { eeId        :: !EpisodicId
  , eeTurnSeq   :: !TurnSeq
  , eeKind      :: !EpisodicKind
  , eeContent   :: !EpisodicContent
  , eeLinked    :: ![CommitmentId]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data EpisodicIndex = EpisodicIndex
  { eiByKind       :: !(HashMap EpisodicKind (HashSet EpisodicId))
  , eiByTurn       :: !(HashMap TurnSeq (HashSet EpisodicId))
  , eiByCommitment :: !(HashMap CommitmentId (HashSet EpisodicId))
  , eiByTag        :: !(HashMap Text (HashSet EpisodicId))
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

emptyIndex :: EpisodicIndex
emptyIndex = EpisodicIndex
  { eiByKind       = HM.empty
  , eiByTurn       = HM.empty
  , eiByCommitment = HM.empty
  , eiByTag        = HM.empty
  }

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

data ForgettingReason
  = ForgetByCapacity
  | ForgetByAge
  | ForgetByUser
  | ForgetByPolicy
  deriving stock (Eq, Show, Generic)

data ReuseAnnotation
  = ReuseAsContext
  | ReuseAsConstraint
  | ReuseAsTrigger
  | ReuseAsEvidence
  deriving stock (Eq, Show, Generic)

nextEpisodicId :: EpisodicStore -> EpisodicId
nextEpisodicId store = EpisodicId (case Seq.viewr (esEvents store) of
  Seq.EmptyR    -> 1
  _ Seq.:> prev -> unEpisodicId (eeId prev) + 1)

indexEvent :: EpisodicIndex -> EpisodicEvent -> EpisodicIndex
indexEvent idx event = idx
  { eiByKind       = HM.insertWith HS.union (eeKind event) (HS.singleton (eeId event)) (eiByKind idx)
  , eiByTurn       = HM.insertWith HS.union (eeTurnSeq event) (HS.singleton (eeId event)) (eiByTurn idx)
  , eiByCommitment = foldl' (\acc cid ->
      HM.insertWith HS.union cid (HS.singleton (eeId event)) acc)
      (eiByCommitment idx) (eeLinked event)
  , eiByTag        = case eeContent event of
      EpisodicContentUnresolved tag -> HM.insertWith HS.union tag (HS.singleton (eeId event)) (eiByTag idx)
      _                      -> eiByTag idx
  }

encode :: TurnSeq -> EpisodicKind -> EpisodicContent -> [CommitmentId] -> EpisodicStore -> EpisodicStore
encode turn kind content linked store =
  let eid = nextEpisodicId store
      event = EpisodicEvent
        { eeId      = eid
        , eeTurnSeq = turn
        , eeKind    = kind
        , eeContent = content
        , eeLinked  = linked
        }
  in store { esEvents = esEvents store |> event
           , esIndex  = indexEvent (esIndex store) event
           }

retrieve :: EpisodicQuery -> EpisodicStore -> [EpisodicEvent]
retrieve q store =
  let ids = candidateIds q (esIndex store)
      forgotten = esForgotten store
      allEvents = esEvents store
  in filter (\e -> HS.member (eeId e) ids && not (HS.member (eeId e) forgotten))
            (foldr (:) [] (Seq.filter (\e -> HS.member (eeId e) ids) allEvents))

candidateIds :: EpisodicQuery -> EpisodicIndex -> HashSet EpisodicId
candidateIds q idx = case q of
  ByKind k           -> HM.lookupDefault HS.empty k (eiByKind idx)
  ByCommitment cid   -> HM.lookupDefault HS.empty cid (eiByCommitment idx)
  ByTurnRange (lo, hi) ->
    let inRange eidByTurn (_turn, eids) = eids
        allBys = HM.toList (eiByTurn idx)
    in HS.unions [ eids | (t, eids) <- allBys, unTurnSeq t >= unTurnSeq lo && unTurnSeq t <= unTurnSeq hi ]

forget :: EpisodicId -> ForgettingReason -> EpisodicStore -> EpisodicStore
forget eid _reason store =
  store { esForgotten = HS.insert eid (esForgotten store) }

enforceCapacity :: EpisodicStore -> EpisodicStore
enforceCapacity store
  | Seq.length (esEvents store) <= episodicCapacity = store
  | otherwise =
    let (removed, remaining) = Seq.splitAt 1 (esEvents store)
        mids = case Seq.viewl removed of
          Seq.EmptyL -> HS.empty
          ev Seq.:< _ -> HS.singleton (eeId ev)
    in store { esEvents    = remaining
             , esIndex     = rebuildIndex remaining
             , esForgotten = esForgotten store `HS.difference` mids
             }

rebuildIndex :: Seq EpisodicEvent -> EpisodicIndex
rebuildIndex events = foldl' indexEvent emptyIndex (foldr (:) [] events)

enforceAgeWindow :: TurnSeq -> EpisodicStore -> EpisodicStore
enforceAgeWindow currentTurn store =
  let cutoff = currentTurn
      before = TurnSeq (unTurnSeq cutoff - unTurnSeq episodicWindow)
      toForget = filter (\e -> unTurnSeq (eeTurnSeq e) < unTurnSeq before
                            && not (HS.member (eeId e) (esForgotten store))
                            && null (eeLinked e))
                        (foldr (:) [] (esEvents store))
  in foldl' (\s e -> forget (eeId e) ForgetByAge s) store toForget

instance Hashable EpisodicId
instance Hashable EpisodicKind

instance ToJSONKey EpisodicId where
  toJSONKey = ToJSONKeyValue (toJSON . unEpisodicId) (toEncoding . unEpisodicId)
instance FromJSONKey EpisodicId where
  fromJSONKey = FromJSONKeyValue (\v -> EpisodicId <$> parseJSON v)

instance FromJSON EpisodicId where
  parseJSON v = EpisodicId <$> parseJSON v
instance ToJSON EpisodicId where
  toJSON = toJSON . unEpisodicId
  toEncoding = toEncoding . unEpisodicId

instance FromJSON EpisodicKind
instance ToJSON EpisodicKind

instance FromJSON EpisodicContent
instance ToJSON EpisodicContent

instance FromJSON EpisodicEvent
instance ToJSON EpisodicEvent

instance ToJSON EpisodicIndex where
  toJSON idx = object
    [ "eiByKind"       .= HM.toList (fmap HS.toList (eiByKind idx))
    , "eiByTurn"       .= HM.toList (fmap HS.toList (eiByTurn idx))
    , "eiByCommitment" .= HM.toList (fmap HS.toList (eiByCommitment idx))
    , "eiByTag"        .= HM.toList (fmap HS.toList (eiByTag idx))
    ]

instance ToJSON EpisodicStore where
  toJSON store = object
    [ "esEvents"    .= toJSON (foldr (:) [] (esEvents store))
    , "esForgotten" .= HS.toList (esForgotten store)
    , "esSessionId" .= esSessionId store
    ]
instance FromJSON EpisodicStore where
  parseJSON = withObject "EpisodicStore" $ \o -> do
    events    <- o .: "esEvents"
    forgotten <- o .: "esForgotten"
    sid       <- o .: "esSessionId"
    let eventList = events :: [EpisodicEvent]
        eventSeq  = Seq.fromList eventList
    pure EpisodicStore
      { esEvents    = eventSeq
      , esIndex     = rebuildIndex eventSeq
      , esForgotten = HS.fromList forgotten
      , esSessionId = sid
      }

instance FromJSON EpisodicQuery
instance ToJSON EpisodicQuery

instance FromJSON ForgettingReason
instance ToJSON ForgettingReason

instance FromJSON ReuseAnnotation
instance ToJSON ReuseAnnotation
