{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  , applyAutonomousEventBatch
  , applyPendingUpdatesForSession
  , maxUpdatesPerTurn
  ) where

import Control.Exception (SomeException, try)
import Control.Monad (when)
import Control.Concurrent.STM (TQueue)
import qualified Control.Concurrent.STM as STM
import Data.Foldable (foldlM)
import Data.IORef (IORef, atomicModifyIORef')
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (getCurrentTime)
import System.IO (hPutStrLn, stderr)

import QxFx0.Learning.Metrics (LearningMetrics(..), emptyLearningMetrics)
import QxFx0.Learning.EdgeScore (authorityRankDouble)
import QxFx0.Learning.Autonomous
  ( LearningQueue
  , NetworkUpdateEvent(..)
  , buildAtomMorphology
  )
import QxFx0.Learning.CircuitBreaker (PendingBreakerCloseQueue)
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , LearningEventSource(..)
  , recordLearningEvent
  )
import QxFx0.Learning.Quarantine
  ( QuarantineEntry(..)
  , QuarantineReason(..)
  , provenanceText
  , recordQuarantine
  , relationTypeText
  )
import QxFx0.Bridge.SQLite (QxFx0DB)
import qualified QxFx0.Semantic.Network.RuntimeProjection as RuntimeProjection
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Learning.Quarantine (QuarantineReason(..))
import QxFx0.Types.State.System (SystemState(..), ssSemanticNetwork)

data AutonomousHandles = AutonomousHandles
  { ahQueue       :: !(Maybe LearningQueue)
  , ahUpdateQueue :: !(Maybe (TQueue NetworkUpdateEvent))
  , ahPendingBreakerQueue :: !(Maybe PendingBreakerCloseQueue)
  , ahQuarantineDB :: !(Maybe QxFx0DB)
  , ahMetricsRef :: !(Maybe (IORef LearningMetrics))
  , ahEnabled     :: !Bool
  }

-- | Maximum number of update events to process per turn to prevent storm updates
maxUpdatesPerTurn :: Int
maxUpdatesPerTurn = 100

-- | Authority rank for provenance comparison (higher = more authoritative).
authorityRank :: EdgeProvenance -> Double
authorityRank = authorityRankDouble

-- | Check if incoming edge wins by score (higher confidence).
incomingWinsByScore :: SemanticEdge -> SemanticEdge -> Bool
incomingWinsByScore incoming old = seConfidence incoming > seConfidence old

-- | Check if two relation types are contradictory.
isContradictory :: RelationType -> RelationType -> Bool
isContradictory a b = a /= b && isContradictoryPair (a, b)
  where
    -- Define explicit contradiction pairs
    isContradictoryPair (RelNegates, _) = True
    isContradictoryPair (_, RelNegates) = True
    isContradictoryPair (RelIsNot, _) = True
    isContradictoryPair (_, RelIsNot) = True
    isContradictoryPair (RelContrastsWith, _) = True
    isContradictoryPair (_, RelContrastsWith) = True
    isContradictoryPair _ = False

applyPendingUpdatesForSession :: AutonomousHandles -> SystemState -> IO SystemState
applyPendingUpdatesForSession handles ss =
  case ahUpdateQueue handles of
    Nothing -> pure ss
    Just updateQ -> do
      pending <- drainUpdateQueue updateQ
      let original = ssSemanticNetwork ss
          pendingCount = length pending
          -- Split into applied and deferred: take up to maxUpdatesPerTurn
          (toApply, deferred) = splitAt maxUpdatesPerTurn pending
          appliedCount = length toApply
          deferredCount = length deferred
      -- Log the update application for observability
      when (pendingCount > 0) $ do
        hPutStrLn stderr $ "applyPendingUpdatesForSession: applied " ++ show appliedCount ++ " updates, deferred " ++ show deferredCount ++ " (max_per_turn=" ++ show maxUpdatesPerTurn ++ ")"
      result <- try (applyAutonomousEventBatch handles original toApply) :: IO (Either SomeException SemanticNetwork)
      case result of
        Left _ -> do
          updateMetrics handles (\m -> m { lmEdgesRejected = lmEdgesRejected m + sum (map (length . nueEdges) toApply) })
          pure ss { ssSemanticNetwork = original }
        Right network -> do
          -- Log if we had to defer updates
          when (deferredCount > 0) $ do
            updateMetrics handles (\m -> m { lmUpdatesDeferred = lmUpdatesDeferred m + deferredCount })
          pure ss { ssSemanticNetwork = network }

applyAutonomousEventBatch :: AutonomousHandles -> SemanticNetwork -> [NetworkUpdateEvent] -> IO SemanticNetwork
applyAutonomousEventBatch handles base events =
  foldlM (applyEvent handles) base events

applyEvent :: AutonomousHandles -> SemanticNetwork -> NetworkUpdateEvent -> IO SemanticNetwork
applyEvent handles network evt =
  foldlM (applyEdge handles evt) network (nueEdges evt)

applyEdge :: AutonomousHandles -> NetworkUpdateEvent -> SemanticNetwork -> SemanticEdge -> IO SemanticNetwork
applyEdge handles evt network incoming0 = do
  let incoming = incoming0 { seProvenance = ProvenanceRuntimeLLM }
      key = (seFrom incoming, seTo incoming)
      existing = M.lookup key (snEdges network)
  case existing of
    Nothing -> do
      updateMetrics handles (\m -> m { lmEdgesAccepted = lmEdgesAccepted m + 1 })
      recordEdgeEvent handles evt incoming EdgeAdmitted Nothing
      persistRuntimeEdge handles incoming
      pure (insertEdge incoming network)
    Just old
      | edgeContradicts old incoming && authorityRank (seProvenance old) >= authorityRank (seProvenance incoming) -> do
          quarantine handles evt incoming (Just old) QRLowerAuthorityConflict
          updateMetrics handles (\m -> m { lmEdgesQuarantined = lmEdgesQuarantined m + 1 })
          pure network
      | edgeContradicts old incoming -> do
          updateMetrics handles (\m -> m { lmEdgesAccepted = lmEdgesAccepted m + 1 })
          recordEdgeEvent handles evt incoming EdgeAdmitted (Just "replaced_lower_authority_contradiction")
          persistRuntimeEdge handles incoming
          pure (insertEdge incoming network)
      | authorityRank (seProvenance old) > authorityRank (seProvenance incoming) -> do
          quarantine handles evt incoming (Just old) QRLowerAuthorityConflict
          updateMetrics handles (\m -> m { lmEdgesQuarantined = lmEdgesQuarantined m + 1 })
          pure network
      | authorityRank (seProvenance old) < authorityRank (seProvenance incoming) -> do
          updateMetrics handles (\m -> m { lmEdgesAccepted = lmEdgesAccepted m + 1 })
          recordEdgeEvent handles evt incoming EdgeAdmitted (Just "replaced_lower_authority")
          persistRuntimeEdge handles incoming
          pure (insertEdge incoming network)
      | incomingWinsByScore incoming old -> do
          quarantine handles evt old (Just incoming) QRSameAuthorityReplaced
          updateMetrics handles (\m -> m { lmEdgesAccepted = lmEdgesAccepted m + 1, lmEdgesQuarantined = lmEdgesQuarantined m + 1 })
          recordEdgeEvent handles evt incoming EdgeAdmitted (Just "same_authority_score_win")
          persistRuntimeEdge handles incoming
          pure (insertEdge incoming network)
      | otherwise -> do
          quarantine handles evt incoming (Just old) QRSameAuthorityReplaced
          updateMetrics handles (\m -> m { lmEdgesQuarantined = lmEdgesQuarantined m + 1 })
          pure network

persistRuntimeEdge :: AutonomousHandles -> SemanticEdge -> IO ()
persistRuntimeEdge handles edge =
  case ahQuarantineDB handles of
    Nothing -> pure ()
    Just db -> RuntimeProjection.persistRuntimeEdge db edge

edgeContradicts :: SemanticEdge -> SemanticEdge -> Bool
edgeContradicts old incoming =
  case (seRelationType old, seRelationType incoming) of
    (Just a, Just b) -> isContradictory a b
    _ -> False

insertEdge :: SemanticEdge -> SemanticNetwork -> SemanticNetwork
insertEdge edge network = network
  { snNodes = S.insert (seFrom edge) (S.insert (seTo edge) (snNodes network))
  , snEdges = M.insert (seFrom edge, seTo edge) edge (snEdges network)
  }

quarantine :: AutonomousHandles -> NetworkUpdateEvent -> SemanticEdge -> Maybe SemanticEdge -> QuarantineReason -> IO ()
quarantine handles evt edge mConflict reason =
  case ahQuarantineDB handles of
    Nothing -> pure ()
    Just db -> do
      now <- getCurrentTime
      recordQuarantine db QuarantineEntry
        { qeTimestamp = now
        , qeTurnSeq = Nothing
        , qeRequestId = nueRequestId evt
        , qeTopic = nueTopic evt
        , qeEdgeFrom = seFrom edge
        , qeEdgeTo = seTo edge
        , qeEdgeProvenance = seProvenance edge
        , qeEdgeRelationType = relationTypeText <$> seRelationType edge
        , qeEdgeConfidence = seConfidence edge
        , qeConflictingFrom = seFrom <$> mConflict
        , qeConflictingTo = seTo <$> mConflict
        , qeConflictingProv = provenanceText . seProvenance <$> mConflict
        , qeReason = reason
        , qeSource = "apply"
        , qePromptHash = nuePromptHash evt
        , qeResponseHash = nueResponseHash evt
        }
      recordEdgeEvent handles evt edge EdgeQuarantined (Just (provenanceText (seProvenance edge)))

recordEdgeEvent :: AutonomousHandles -> NetworkUpdateEvent -> SemanticEdge -> LearningEventKind -> Maybe Text -> IO ()
recordEdgeEvent handles evt edge kind reason =
  case ahQuarantineDB handles of
    Nothing -> pure ()
    Just db -> do
      now <- getCurrentTime
      recordLearningEvent db LearningEvent
        { leTimestamp = now
        , leSessionId = Nothing
        , leTurnSeq = Nothing
        , leRequestId = nueRequestId evt
        , leTopic = nueTopic evt
        , leKind = kind
        , leSource = LesAutonomousApply
        , leEdgeFrom = Just (seFrom edge)
        , leEdgeTo = Just (seTo edge)
        , leProvenance = Just (seProvenance edge)
        , leConfidence = Just (seConfidence edge)
        , leCoOccurrence = Just (seCoOccurrence edge)
        , leReason = reason
        , lePromptHash = nuePromptHash evt
        , leResponseHash = nueResponseHash evt
        }

updateMetrics :: AutonomousHandles -> (LearningMetrics -> LearningMetrics) -> IO ()
updateMetrics handles f =
  case ahMetricsRef handles of
    Nothing -> pure ()
    Just ref -> atomicModifyIORef' ref (\m -> (f m, ()))

drainUpdateQueue :: TQueue NetworkUpdateEvent -> IO [NetworkUpdateEvent]
drainUpdateQueue q = STM.atomically (loop [])
  where
    loop acc = do
      mt <- STM.tryReadTQueue q
      case mt of
        Just e -> loop (e : acc)
        Nothing -> pure (reverse acc)
