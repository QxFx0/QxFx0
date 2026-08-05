{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  , SemanticNetworkOwner
  , SemanticNetworkSnapshot(..)
  , SemanticNetworkTurn
  , SemanticNetworkVersion(..)
  , newSemanticNetworkOwner
  , readSemanticNetworkSnapshot
  , beginSemanticNetworkTurn
  , commitSemanticNetworkTurn
  , commitSemanticNetworkTurnForTest
  , rebaseSemanticNetwork
  , applyAutonomousEventBatch
  , applyAutonomousEventBatchForTest
  , applyPendingUpdatesForSessionForTest
  , applyPendingUpdatesInBackground
  , applyPendingUpdatesInBackgroundForTest
  , spawnGovernedApplyLoop
  , enqueueAutonomousLearningForTopic
  , maxUpdatesPerTurn
  ) where

import Control.Exception (AsyncException, SomeException, finally, fromException, mask_, onException, throwIO, try)
import Control.Monad (forever, when)
import Control.Concurrent (MVar, modifyMVar, newMVar, readMVar, threadDelay)
import Control.Concurrent.STM (TQueue)
import qualified Control.Concurrent.STM as STM
import Data.IORef (IORef, atomicModifyIORef')
import Data.Int (Int64)
import Data.List (findIndex)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Word (Word64)
import System.IO (hPutStrLn, stderr)

import QxFx0.Learning.Metrics (LearningMetrics(..))
import QxFx0.Learning.EdgeScore (authorityRankDouble)
import QxFx0.Learning.Autonomous
  ( LearningQueue
  , NetworkUpdateEvent(..)
  , buildAtomMorphology
  , enqueueIfStarvingWithTopicAtoms
  )
import QxFx0.Semantic.Morphology (buildLemmaMap)
import QxFx0.Semantic.Network.Seed (buildTopicAtomsMapFromCorpus, readDensityConfig)
import QxFx0.Semantic.Content (definitionCorpus)
import QxFx0.Learning.CircuitBreaker (PendingBreakerCloseQueue)
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , LearningEventSource(..)
  , RuntimeEvidence(..)
  , insertLearningEventsOnConnection
  , loadRuntimeEvidenceOnConnection
  )
import QxFx0.Learning.Quarantine
  ( QuarantineEntry(..)
  , QuarantineReason(..)
  , provenanceText
  , recordQuarantinesOnConnection
  , relationTypeText
  )
import QxFx0.Learning.JobQueue
  ( LearningReadyPayload(..)
  , authorizeLearningJobsApplyOnConnection
  , markLearningJobsAppliedOnConnection
  , releaseLearningReadyPayloads
  )
import QxFx0.Learning.CorroborationQueue
  ( CorroborationTaskState(..)
  , CorroborationTaskSeed(..)
  , enqueueCorroborationTaskOnConnection
  , authorizeCorroborationApplyOnConnection
  , markCorroborationTaskTerminalOnConnection
  , releaseCorroborationApplyProofs
  )
import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Bridge.SemanticNetwork.RuntimeProjection as RuntimeProjection
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , edgeRefOf
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network (mergeSemanticEdge)
import QxFx0.Types.State.System (SystemState(..), ssSemanticNetwork)
import QxFx0.Runtime.ManagedWorker (ManagedWorker, spawnManagedWorker)
import QxFx0.ExceptionPolicy (QxFx0Exception(..), mkSQLiteError, throwQxFx0)

newtype SemanticNetworkVersion = SemanticNetworkVersion
  { unSemanticNetworkVersion :: Word64
  } deriving stock (Eq, Ord, Show)

data SemanticNetworkSnapshot = SemanticNetworkSnapshot
  { snsVersion :: !SemanticNetworkVersion
  , snsNetwork :: !SemanticNetwork
  } deriving stock (Eq, Show)

-- | The only mutable in-memory SemanticNetwork authority in unattended mode.
newtype SemanticNetworkOwner = SemanticNetworkOwner
  (MVar SemanticNetworkSnapshot)

-- | A turn's optimistic base. The constructor is intentionally private so a
-- commit can only use a snapshot obtained from 'beginSemanticNetworkTurn'.
newtype SemanticNetworkTurn = SemanticNetworkTurn
  (Maybe SemanticNetworkSnapshot)

newSemanticNetworkOwner :: SemanticNetwork -> IO SemanticNetworkOwner
newSemanticNetworkOwner network =
  SemanticNetworkOwner <$> newMVar (SemanticNetworkSnapshot (SemanticNetworkVersion 0) network)

readSemanticNetworkSnapshot :: SemanticNetworkOwner -> IO SemanticNetworkSnapshot
readSemanticNetworkSnapshot (SemanticNetworkOwner state) = readMVar state

data AutonomousHandles = AutonomousHandles
  { ahQueue       :: !(Maybe LearningQueue)
  , ahUpdateQueue :: !(Maybe (TQueue NetworkUpdateEvent))
  , ahWorkerThread :: !(Maybe ManagedWorker)
  , ahPendingBreakerQueue :: !(Maybe PendingBreakerCloseQueue)
  , ahQuarantineDB :: !(Maybe QxFx0DB)
  , ahMetricsRef :: !(Maybe (IORef LearningMetrics))
  -- | The single versioned network authority for opt-in unattended mode.
  -- Turns and background application serialize through this owner.
  , ahNetworkOwner :: !(Maybe SemanticNetworkOwner)
  , ahAuditThread :: !(Maybe ManagedWorker)
  , ahApplyThread :: !(Maybe ManagedWorker)
  -- | Owner of all session-local graph mutations and autonomous evidence.
  , ahSessionId   :: !(Maybe Text)
  , ahEnabled     :: !Bool
  }

-- | Everything determined during governed admission before any write reaches
-- SQLite.  Keeping the plan pure lets one transaction persist its complete
-- decision, so a crash cannot leave an edge without its event or job status.
data AutonomousApplyPlan = AutonomousApplyPlan
  { aapNetwork          :: !SemanticNetwork
  , aapAdmittedEdges    :: ![SemanticEdge]
  , aapCorroboratedEdges :: ![SemanticEdge]
  , aapLearningEvents   :: ![LearningEvent]
  , aapQuarantines      :: ![QuarantineEntry]
  , aapAcceptedCount    :: !Int
  , aapCorroboratedCount :: !Int
  , aapQuarantinedCount :: !Int
  , aapEvidence         :: !(S.Set RuntimeEvidenceKey)
  , aapCorroborationSeeds :: ![CorroborationTaskSeed]
  , aapCorroborationOutcomes :: ![(Int64, Text, Text, CorroborationTaskState, Text)]
  }

type RuntimeEvidenceKey = (Text, Text, Text, Text, Text, Text)

-- | Maximum number of update events to process per turn to prevent storm updates
maxUpdatesPerTurn :: Int
maxUpdatesPerTurn = 100

-- | Queue a learning task for the selected turn topic only when its existing
-- semantic neighbourhood is below the configured density threshold.
enqueueAutonomousLearningForTopic :: AutonomousHandles -> Text -> SystemState -> IO Bool
enqueueAutonomousLearningForTopic handles topic ss
  | not (ahEnabled handles) || T.null normalizedTopic = pure False
  | otherwise =
      case ahQueue handles of
        Nothing -> pure False
        Just queue -> do
          densityConfig <- readDensityConfig
          enqueueIfStarvingWithTopicAtoms
            queue
            (buildTopicAtomsMapFromCorpus
              (buildLemmaMap (ssMorphology ss))
              effectiveCorpus)
            densityConfig
            normalizedTopic
            (ssSemanticNetwork ss)
  where
    normalizedTopic = T.toLower (T.strip topic)
    effectiveCorpus
      | M.null (ssDefinitionCorpus ss) = definitionCorpus
      | otherwise = ssDefinitionCorpus ss

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

-- | Rebase session state onto the canonical owner immediately before a turn.
-- Background updates committed before this snapshot are therefore visible to
-- planning and finalization.
beginSemanticNetworkTurn
  :: AutonomousHandles
  -> SystemState
  -> IO (SemanticNetworkTurn, SystemState)
beginSemanticNetworkTurn handles ss =
  case ahNetworkOwner handles of
    Nothing -> pure (SemanticNetworkTurn Nothing, ss)
    Just owner -> do
      snapshot <- readSemanticNetworkSnapshot owner
      pure
        ( SemanticNetworkTurn (Just snapshot)
        , ss { ssSemanticNetwork = snsNetwork snapshot }
        )

-- | Atomically apply the pending governed batch and commit the finalized turn
-- network. Both operations serialize through the one unattended owner.
commitSemanticNetworkTurn
  :: AutonomousHandles
  -> SemanticNetworkTurn
  -> SystemState
  -> IO SystemState
commitSemanticNetworkTurn = commitSemanticNetworkTurnWith applyPendingUpdateBatch

-- | Nonpersistent owner protocol for integration tests only.
commitSemanticNetworkTurnForTest
  :: AutonomousHandles
  -> SemanticNetworkTurn
  -> SystemState
  -> IO SystemState
commitSemanticNetworkTurnForTest = commitSemanticNetworkTurnWith applyPendingUpdateBatchForTest

commitSemanticNetworkTurnWith
  :: (AutonomousHandles -> SemanticNetwork -> ([NetworkUpdateEvent], Int) -> IO SemanticNetwork)
  -> AutonomousHandles
  -> SemanticNetworkTurn
  -> SystemState
  -> IO SystemState
commitSemanticNetworkTurnWith applyBatch handles (SemanticNetworkTurn mBase) ss = do
  batch <- takePendingUpdateBatch handles
  case (ahNetworkOwner handles, mBase) of
    (Nothing, Nothing) -> do
      network <- applyBatch handles (ssSemanticNetwork ss) batch
      pure ss { ssSemanticNetwork = network }
    (Just (SemanticNetworkOwner ownerState), Just base) -> do
      committed <- modifyMVar ownerState $ \current -> do
        withPending <- applyBatch handles (snsNetwork current) batch
        let network = rebaseSemanticNetwork (snsNetwork base) withPending (ssSemanticNetwork ss)
            snapshot = SemanticNetworkSnapshot (nextVersion (snsVersion current)) network
        pure (snapshot, snapshot)
      pure ss { ssSemanticNetwork = snsNetwork committed }
    _ -> throwAutonomousInvariant "SemanticNetwork owner changed during a turn"

nextVersion :: SemanticNetworkVersion -> SemanticNetworkVersion
nextVersion (SemanticNetworkVersion version) = SemanticNetworkVersion (version + 1)

-- | Three-way turn merge. Turn-only changes replace their unchanged base;
-- owner-only changes survive; concurrent writes to one edge use
-- 'mergeSemanticEdge'. A turn deletion is accepted only when the owner still
-- contains the base value. Turn-local activation/configuration remains the
-- finalized value while canonical nodes and edges are rebased.
rebaseSemanticNetwork
  :: SemanticNetwork -- ^ turn base
  -> SemanticNetwork -- ^ current owner (possibly background-updated)
  -> SemanticNetwork -- ^ turn-finalized network
  -> SemanticNetwork
rebaseSemanticNetwork base current finalized = finalized
  { snNodes = S.union (snNodes current) (snNodes finalized)
  , snEdges = foldl rebaseKey (snEdges current) changedKeys
  }
  where
    baseEdges = snEdges base
    currentEdges = snEdges current
    finalizedEdges = snEdges finalized
    changedKeys = S.toList $ S.filter turnChanged $
      S.union (M.keysSet baseEdges) (M.keysSet finalizedEdges)
    turnChanged key = M.lookup key baseEdges /= M.lookup key finalizedEdges
    rebaseKey edges key =
      let baseValue = M.lookup key baseEdges
          ownerValue = M.lookup key currentEdges
          turnValue = M.lookup key finalizedEdges
      in if ownerValue == baseValue
           then setEdge key turnValue edges
           else case (ownerValue, turnValue) of
             (Just ownerEdge, Just turnEdge) ->
               M.insert key (mergeSemanticEdge ownerEdge turnEdge) edges
             (Nothing, Just turnEdge) -> M.insert key turnEdge edges
             _ -> edges
    setEdge key Nothing = M.delete key
    setEdge key (Just edge) = M.insert key edge

-- | Nonpersistent queue drain for unit tests only.
applyPendingUpdatesForSessionForTest :: AutonomousHandles -> SystemState -> IO SystemState
applyPendingUpdatesForSessionForTest handles ss = do
  batch <- takePendingUpdateBatch handles
  network <- applyPendingUpdateBatchForTest handles (ssSemanticNetwork ss) batch
  pure ss { ssSemanticNetwork = network }

-- | Drain and govern queued learning results without a dialogue turn.  This is
-- deliberately available only when bootstrap has installed a canonical
-- network owner for the opt-in unattended audit.
applyPendingUpdatesInBackground :: AutonomousHandles -> IO Int
applyPendingUpdatesInBackground handles =
  case ahNetworkOwner handles of
    -- Do not drain the channel when unattended mode was never attached.
    -- Normal turns remain its sole consumer in that configuration.
    Nothing -> pure 0
    Just owner -> do
      batch@(toApply, _) <- takePendingUpdateBatch handles
      if null toApply
        then pure 0
        else do
          modifySemanticNetworkOwner owner (\original -> applyPendingUpdateBatch handles original batch)
          pure (length toApply)

-- | Nonpersistent canonical-network drain for unit tests only.
applyPendingUpdatesInBackgroundForTest :: AutonomousHandles -> IO Int
applyPendingUpdatesInBackgroundForTest handles = case ahNetworkOwner handles of
  Nothing -> pure 0
  Just owner -> do
    batch@(toApply, _) <- takePendingUpdateBatch handles
    when (not (null toApply)) $
      modifySemanticNetworkOwner owner (\original -> applyPendingUpdateBatchForTest handles original batch)
    pure (length toApply)

modifySemanticNetworkOwner
  :: SemanticNetworkOwner
  -> (SemanticNetwork -> IO SemanticNetwork)
  -> IO ()
modifySemanticNetworkOwner (SemanticNetworkOwner ownerState) update =
  modifyMVar ownerState $ \snapshot -> do
    network <- update (snsNetwork snapshot)
    let next
          | network == snsNetwork snapshot = snapshot
          | otherwise = SemanticNetworkSnapshot (nextVersion (snsVersion snapshot)) network
    pure (next, ())

-- | Start the governed, candidate-only background apply loop.  It does not
-- perform inference itself: it merely drains worker events through the exact
-- same admission, provenance, quarantine, persistence, and job-finalization
-- path used between dialogue turns.
spawnGovernedApplyLoop :: AutonomousHandles -> Int -> IO ManagedWorker
spawnGovernedApplyLoop handles intervalSec =
  spawnManagedWorker . forever $ do
    threadDelay (max 1 intervalSec * 1000 * 1000)
    applied <- applyPendingUpdatesInBackground handles
    when (applied > 0) $
      hPutStrLn stderr $ "[autonomous-apply] governed " ++ show applied ++ " learning update(s)"

takePendingUpdateBatch :: AutonomousHandles -> IO ([NetworkUpdateEvent], Int)
takePendingUpdateBatch handles =
  case ahUpdateQueue handles of
    Nothing -> pure ([], 0)
    Just updateQ -> takeUpdateBatch updateQ maxUpdatesPerTurn

applyPendingUpdateBatch
  :: AutonomousHandles
  -> SemanticNetwork
  -> ([NetworkUpdateEvent], Int)
  -> IO SemanticNetwork
applyPendingUpdateBatch handles original (toApply, deferredCount) = do
  let appliedCount = length toApply
      pendingCount = appliedCount + deferredCount
  when (pendingCount > 0) $
    hPutStrLn stderr $ "applyPendingUpdatesForSession: applied " ++ show appliedCount ++ " updates, deferred " ++ show deferredCount ++ " (max_per_turn=" ++ show maxUpdatesPerTurn ++ ")"
  result <- try (applyAutonomousEventBatch handles original toApply) :: IO (Either SomeException SemanticNetwork)
  case result of
    Left err | Just _ <- (fromException err :: Maybe AsyncException) ->
      releaseCancelledApplyLeases handles toApply >> throwIO err
    Left _ -> do
      updateMetrics handles (\m -> m { lmEdgesRejected = lmEdgesRejected m + sum (map (length . nueEdges) toApply) })
      -- Durable response_ready rows retain their apply leases. If this process
      -- cannot persist the governed batch, lease expiry re-dispatches the
      -- stored payload without another provider request.
      pure original
    Right network -> do
      when (deferredCount > 0) $
        updateMetrics handles (\m -> m { lmUpdatesDeferred = lmUpdatesDeferred m + deferredCount })
      pure network

releaseCancelledApplyLeases :: AutonomousHandles -> [NetworkUpdateEvent] -> IO ()
releaseCancelledApplyLeases handles events =
  case ahQuarantineDB handles of
    Nothing -> pure ()
    Just db -> do
      let broad = M.elems $ M.fromList
            [ (nueRequestId event, LearningReadyPayload
                (nueRequestId event) (nueTopic event) "" token)
            | event <- events
            , nueAdmissionDecision event `notElem`
                [Just "corroboration_confirmation", Just "corroboration_conflict"]
            , Just token <- [nueApplyToken event]
            ]
          corroboration = M.elems $ M.fromList
            [ (taskId, (taskId, token))
            | event <- events
            , nueAdmissionDecision event `elem`
                [Just "corroboration_confirmation", Just "corroboration_conflict"]
            , Just taskId <- [nueCorroborationTaskId event]
            , Just token <- [nueApplyToken event]
            ]
      releaseLearningReadyPayloads db broad
        `finally` releaseCorroborationApplyProofs db corroboration

applyPendingUpdateBatchForTest
  :: AutonomousHandles
  -> SemanticNetwork
  -> ([NetworkUpdateEvent], Int)
  -> IO SemanticNetwork
applyPendingUpdateBatchForTest handles original (toApply, deferredCount) = do
  network <- applyAutonomousEventBatchForTest handles original toApply
  when (deferredCount > 0) $
    updateMetrics handles (\m -> m { lmUpdatesDeferred = lmUpdatesDeferred m + deferredCount })
  pure network

applyAutonomousEventBatch :: AutonomousHandles -> SemanticNetwork -> [NetworkUpdateEvent] -> IO SemanticNetwork
applyAutonomousEventBatch _ base [] = pure base
applyAutonomousEventBatch handles base events = do
  case ahQuarantineDB handles of
    Nothing -> throwAutonomousInvariant "persisted autonomous apply requires durable job authorization"
    Just _ -> pure ()
  priorEvidence <- loadPriorEvidence handles
  now <- getCurrentTime
  let plan = finalizeApplyPlan (foldl (planEvent (ahSessionId handles) now) (emptyApplyPlan base priorEvidence) events)
  persistAutonomousApplyPlan handles events plan
  updateMetrics handles $ \metrics -> metrics
    { lmEdgesAccepted = lmEdgesAccepted metrics + aapAcceptedCount plan
    , lmEdgesCorroborated = lmEdgesCorroborated metrics + aapCorroboratedCount plan
    , lmEdgesQuarantined = lmEdgesQuarantined metrics + aapQuarantinedCount plan
    }
  pure (aapNetwork plan)

-- | Pure admission planner for unit tests. Production callers must use
-- 'applyAutonomousEventBatch', which fails closed without durable persistence.
applyAutonomousEventBatchForTest :: AutonomousHandles -> SemanticNetwork -> [NetworkUpdateEvent] -> IO SemanticNetwork
applyAutonomousEventBatchForTest handles base events = do
  now <- getCurrentTime
  let plan = finalizeApplyPlan (foldl (planEvent (ahSessionId handles) now) (emptyApplyPlan base S.empty) events)
  updateMetrics handles $ \metrics -> metrics
    { lmEdgesAccepted = lmEdgesAccepted metrics + aapAcceptedCount plan
    , lmEdgesCorroborated = lmEdgesCorroborated metrics + aapCorroboratedCount plan
    , lmEdgesQuarantined = lmEdgesQuarantined metrics + aapQuarantinedCount plan
    }
  pure (aapNetwork plan)

loadPriorEvidence :: AutonomousHandles -> IO (S.Set RuntimeEvidenceKey)
loadPriorEvidence handles =
  case ahQuarantineDB handles of
    Nothing -> pure S.empty
    Just db -> do
      result <- withDB (qdbPath db) $ \conn -> do
        evidence <- loadRuntimeEvidenceOnConnection conn
        pure (S.fromList
          [ runtimeEvidenceKeyFromRecord item
          | item <- evidence
          , reNamespace item == "global"
              || (reNamespace item == "session_local" && reSessionId item == ahSessionId handles)
          ])
      either throwAutonomousPersistenceError pure result

emptyApplyPlan :: SemanticNetwork -> S.Set RuntimeEvidenceKey -> AutonomousApplyPlan
emptyApplyPlan network priorEvidence = AutonomousApplyPlan
  { aapNetwork = network
  , aapAdmittedEdges = []
  , aapCorroboratedEdges = []
  , aapLearningEvents = []
  , aapQuarantines = []
  , aapAcceptedCount = 0
  , aapCorroboratedCount = 0
  , aapQuarantinedCount = 0
  , aapEvidence = priorEvidence
  , aapCorroborationSeeds = []
  , aapCorroborationOutcomes = []
  }

finalizeApplyPlan :: AutonomousApplyPlan -> AutonomousApplyPlan
finalizeApplyPlan plan = plan
  { aapAdmittedEdges = reverse (aapAdmittedEdges plan)
  , aapCorroboratedEdges = reverse (aapCorroboratedEdges plan)
  , aapLearningEvents = reverse (aapLearningEvents plan)
  , aapQuarantines = reverse (aapQuarantines plan)
  , aapCorroborationSeeds = reverse (aapCorroborationSeeds plan)
  , aapCorroborationOutcomes = reverse (aapCorroborationOutcomes plan)
  }

planEvent :: Maybe Text -> UTCTime -> AutonomousApplyPlan -> NetworkUpdateEvent -> AutonomousApplyPlan
planEvent sessionId now plan evt = foldl (planEdge sessionId now evt) plan (nueEdges evt)

planEdge :: Maybe Text -> UTCTime -> NetworkUpdateEvent -> AutonomousApplyPlan -> SemanticEdge -> AutonomousApplyPlan
planEdge sessionId now evt plan incoming0 =
  let incoming = incoming0
        { seProvenance = ProvenanceRuntimeLLM
        , seLineage = Just (maybe [] id (seLineage incoming0) ++ [edgeRefOf incoming0])
        }
      key = (seFrom incoming, seTo incoming)
      existing = M.lookup key (snEdges (aapNetwork plan))
      sameRuntimeRelation old =
        seProvenance old == ProvenanceRuntimeLLM
          && seRelationType old == seRelationType incoming
      mEvidenceKey = runtimeEvidenceKey sessionId evt incoming
      duplicateEvidence = maybe False (hasDuplicateEvidence (aapEvidence plan)) mEvidenceKey
  in case nueAdmissionDecision evt of
    Just "corroboration_confirmation" ->
      case existing of
        Nothing ->
          rejectEdge sessionId evt incoming "confirmation_target_missing"
            (withCorroborationOutcome evt CtsRejected "confirmation_target_missing" plan)
        Just old
          | sameRuntimeRelation old, Just _ <- mEvidenceKey, duplicateEvidence ->
              rejectDuplicateEdge sessionId evt incoming
                (withCorroborationOutcome evt CtsRejected "duplicate_confirmation_evidence" plan)
          | sameRuntimeRelation old, Just evidenceKey <- mEvidenceKey ->
              corroborateEdge sessionId now evt old evidenceKey
                (withCorroborationOutcome evt CtsSucceeded "confirmed" plan)
          | seProvenance old == ProvenanceRuntimeLLM ->
              quarantineEdge sessionId now evt incoming (Just old) QRRelationConflict
                (withCorroborationOutcome evt CtsConflicted "confirmation_target_changed" plan)
          | otherwise ->
              quarantineEdge sessionId now evt incoming (Just old) QRLowerAuthorityConflict
                (withCorroborationOutcome evt CtsRejected "confirmation_target_not_runtime" plan)
    Just "corroboration_conflict" ->
      quarantineEdge sessionId now evt incoming existing QRRelationConflict
        (withCorroborationOutcome evt CtsConflicted
          (if maybe True (const False) existing then "conflict_target_missing" else "relation_conflict") plan)
    Just decision
      | decision `elem` ["worker_candidate_admitted", "worker_candidate_qualified"] ->
          case existing of
            Nothing ->
              admitEdge sessionId now evt incoming Nothing (withCorroborationSeed sessionId evt incoming plan)
            Just old
              | sameRuntimeRelation old, Just _ <- mEvidenceKey, duplicateEvidence ->
                  rejectDuplicateEdge sessionId evt incoming plan
              | sameRuntimeRelation old, Just evidenceKey <- mEvidenceKey ->
                  corroborateEdge sessionId now evt old evidenceKey plan
              | seProvenance old == ProvenanceRuntimeLLM
                  && seRelationType old /= seRelationType incoming ->
                  quarantineEdge sessionId now evt incoming (Just old) QRRelationConflict plan
              | edgeContradicts old incoming && authorityRank (seProvenance old) >= authorityRank (seProvenance incoming) ->
                  quarantineEdge sessionId now evt incoming (Just old) QRLowerAuthorityConflict plan
              | edgeContradicts old incoming ->
                  admitEdge sessionId now evt incoming (Just "replaced_lower_authority_contradiction") plan
              | authorityRank (seProvenance old) > authorityRank (seProvenance incoming) ->
                  quarantineEdge sessionId now evt incoming (Just old) QRLowerAuthorityConflict plan
              | authorityRank (seProvenance old) < authorityRank (seProvenance incoming) ->
                  admitEdge sessionId now evt incoming (Just "replaced_lower_authority") plan
              | incomingWinsByScore incoming old ->
                  admitEdge sessionId now evt incoming (Just "same_authority_score_win")
                    (quarantineEdge sessionId now evt old (Just incoming) QRSameAuthorityReplaced plan)
              | otherwise ->
                  quarantineEdge sessionId now evt incoming (Just old) QRSameAuthorityReplaced plan
    _ -> rejectEdge sessionId evt incoming "untrusted_admission_decision" plan

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

admitEdge :: Maybe Text -> UTCTime -> NetworkUpdateEvent -> SemanticEdge -> Maybe Text -> AutonomousApplyPlan -> AutonomousApplyPlan
admitEdge sessionId now evt edge reason plan = plan
  { aapNetwork = insertEdge edge (aapNetwork plan)
  , aapAdmittedEdges = edge : aapAdmittedEdges plan
  , aapLearningEvents = edgeLearningEvent sessionId now evt edge EdgeAdmitted reason : aapLearningEvents plan
  , aapAcceptedCount = aapAcceptedCount plan + 1
  , aapEvidence = maybe (aapEvidence plan) (\identity -> S.insert identity (aapEvidence plan)) (runtimeEvidenceKey sessionId evt edge)
  }

withCorroborationSeed :: Maybe Text -> NetworkUpdateEvent -> SemanticEdge -> AutonomousApplyPlan -> AutonomousApplyPlan
withCorroborationSeed sessionId evt edge plan =
  case qualifiedSeed sessionId evt edge of
    Nothing -> plan
    Just seed -> plan { aapCorroborationSeeds = seed : aapCorroborationSeeds plan }

qualifiedSeed :: Maybe Text -> NetworkUpdateEvent -> SemanticEdge -> Maybe CorroborationTaskSeed
qualifiedSeed sessionId evt edge = do
  decision <- nueAdmissionDecision evt
  if decision /= "worker_candidate_qualified"
    then Nothing
    else do
      audit <- nueCompetitiveAudit evt
      responseHash <- nueResponseHash evt
      relation <- seRelationType edge
      let namespace = maybe "session_local" RuntimeProjection.namespaceText (seNamespace edge)
      pure CorroborationTaskSeed
        { ctsTopic = nueTopic evt
        , ctsEdgeFrom = seFrom edge
        , ctsEdgeTo = seTo edge
        , ctsRelationType = relationTypeText relation
        , ctsNamespace = namespace
        , ctsSessionId = if namespace == "session_local" then sessionId else Nothing
        , ctsOwner = if namespace == "global" then "global" else maybe "" id sessionId
        , ctsSourceRequestId = nueRequestId evt
        , ctsSourceResponseHash = responseHash
        , ctsPriority = maybe 0.0 id (nueCorroborationPriority evt)
        , ctsAudit = audit
        }

withCorroborationOutcome :: NetworkUpdateEvent -> CorroborationTaskState -> Text -> AutonomousApplyPlan -> AutonomousApplyPlan
withCorroborationOutcome evt state resultKind plan =
  case nueAdmissionDecision evt of
    Just "corroboration_confirmation" ->
      case nueCorroborationTaskId evt of
        Just taskId -> plan
          { aapCorroborationOutcomes =
              (taskId, nueRequestId evt, maybe "" id (nueApplyToken evt), state, resultKind)
                : aapCorroborationOutcomes plan
          }
        Nothing -> plan
    Just "corroboration_conflict" ->
      case nueCorroborationTaskId evt of
        Just taskId -> plan
          { aapCorroborationOutcomes =
              (taskId, nueRequestId evt, maybe "" id (nueApplyToken evt), CtsConflicted, resultKind)
                : aapCorroborationOutcomes plan
          }
        Nothing -> plan
    _ -> plan

corroborateEdge
  :: Maybe Text
  -> UTCTime
  -> NetworkUpdateEvent
  -> SemanticEdge
  -> RuntimeEvidenceKey
  -> AutonomousApplyPlan
  -> AutonomousApplyPlan
corroborateEdge sessionId now evt old evidenceKey plan =
  let updated = old { seCoOccurrence = seCoOccurrence old + 1 }
  in plan
    { aapNetwork = insertEdge updated (aapNetwork plan)
    , aapCorroboratedEdges = updated : aapCorroboratedEdges plan
    , aapLearningEvents = edgeLearningEvent sessionId now evt updated EdgeCorroborated Nothing : aapLearningEvents plan
    , aapCorroboratedCount = aapCorroboratedCount plan + 1
    , aapEvidence = S.insert evidenceKey (aapEvidence plan)
    }

rejectDuplicateEdge :: Maybe Text -> NetworkUpdateEvent -> SemanticEdge -> AutonomousApplyPlan -> AutonomousApplyPlan
rejectDuplicateEdge sessionId evt edge plan = plan
  { aapLearningEvents = edgeLearningEvent sessionId (nueTimestamp evt) evt edge EdgeRejected (Just "duplicate_runtime_evidence") : aapLearningEvents plan
  }

rejectEdge :: Maybe Text -> NetworkUpdateEvent -> SemanticEdge -> Text -> AutonomousApplyPlan -> AutonomousApplyPlan
rejectEdge sessionId evt edge reason plan = plan
  { aapLearningEvents = edgeLearningEvent sessionId (nueTimestamp evt) evt edge EdgeRejected (Just reason) : aapLearningEvents plan
  }

quarantineEdge :: Maybe Text -> UTCTime -> NetworkUpdateEvent -> SemanticEdge -> Maybe SemanticEdge -> QuarantineReason -> AutonomousApplyPlan -> AutonomousApplyPlan
quarantineEdge sessionId now evt edge mConflict reason plan = plan
  { aapLearningEvents = edgeLearningEvent sessionId now evt edge EdgeQuarantined (Just (provenanceText (seProvenance edge))) : aapLearningEvents plan
  , aapQuarantines = QuarantineEntry
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
      } : aapQuarantines plan
  , aapQuarantinedCount = aapQuarantinedCount plan + 1
  }

edgeLearningEvent :: Maybe Text -> UTCTime -> NetworkUpdateEvent -> SemanticEdge -> LearningEventKind -> Maybe Text -> LearningEvent
edgeLearningEvent sessionId now evt edge kind reason = LearningEvent
  { leTimestamp = now
  , leSessionId = sessionId
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
  , leReason = admissionReason reason edge
  , lePromptHash = nuePromptHash evt
  , leResponseHash = nueResponseHash evt
  , leModel = nueModel evt
  , leParserDecision = nueParserDecision evt
  , leAdmissionDecision = Just (runtimeAdmissionDecision kind)
  , leEvidenceSource = nueEvidenceSource evt
  , leEdgeNamespace = Just (maybe NamespaceSessionLocal id (seNamespace edge))
  , leEdgeOwner = edgeEventOwner sessionId edge
  }

edgeEventOwner :: Maybe Text -> SemanticEdge -> Maybe Text
edgeEventOwner sessionId edge =
  case maybe NamespaceSessionLocal id (seNamespace edge) of
    NamespaceGlobal -> Just "global"
    _ -> sessionId

runtimeAdmissionDecision :: LearningEventKind -> Text
runtimeAdmissionDecision kind = case kind of
  EdgeAdmitted -> "runtime_admitted"
  EdgeCorroborated -> "runtime_corroborated"
  EdgeRejected -> "runtime_rejected"
  EdgeQuarantined -> "runtime_quarantined"
  _ -> "runtime_observed"

-- | Relation type is part of the admission event lineage. Promotion snapshots
-- use it to bind request/response evidence to the exact canonical triple,
-- rather than treating another relation on the same endpoints as support.
admissionReason :: Maybe Text -> SemanticEdge -> Maybe Text
admissionReason reason edge =
  Just $ T.intercalate ";" $
    maybe [] pure reason
      ++ maybe [] (pure . ("relation_type=" <>) . relationTypeText) (seRelationType edge)

runtimeEvidenceKey :: Maybe Text -> NetworkUpdateEvent -> SemanticEdge -> Maybe RuntimeEvidenceKey
runtimeEvidenceKey sessionId evt edge = do
  relation <- seRelationType edge
  requestId <- nonEmpty (nueRequestId evt)
  promptHash <- nuePromptHash evt >>= nonEmpty
  responseHash <- nueResponseHash evt >>= nonEmpty
  _ <- nueModel evt >>= nonEmpty
  _ <- nueParserDecision evt >>= nonEmpty
  _ <- nueAdmissionDecision evt >>= nonEmpty
  _ <- nueEvidenceSource evt >>= nonEmpty
  owner <- edgeEventOwner sessionId edge >>= nonEmpty
  pure (seFrom edge, seTo edge, relationTypeText relation, requestId, responseHash, owner)
  where
    nonEmpty value = if T.null (T.strip value) then Nothing else Just value

runtimeEvidenceKeyFromRecord :: RuntimeEvidence -> RuntimeEvidenceKey
runtimeEvidenceKeyFromRecord evidence =
  ( reEdgeFrom evidence
  , reEdgeTo evidence
  , reRelationType evidence
  , reRequestId evidence
  , reResponseHash evidence
  , reOwner evidence
  )

hasDuplicateEvidence :: S.Set RuntimeEvidenceKey -> RuntimeEvidenceKey -> Bool
hasDuplicateEvidence evidence (edgeFrom, edgeTo, relationType, requestId, responseHash, owner) =
  any matches (S.toList evidence)
  where
    matches (priorFrom, priorTo, priorRelation, priorRequest, priorResponse, priorOwner) =
      priorFrom == edgeFrom
        && priorTo == edgeTo
        && priorRelation == relationType
        && priorOwner == owner
        && (priorRequest == requestId || priorResponse == responseHash)

persistAutonomousApplyPlan :: AutonomousHandles -> [NetworkUpdateEvent] -> AutonomousApplyPlan -> IO ()
persistAutonomousApplyPlan _ [] _ = pure ()
persistAutonomousApplyPlan handles events plan =
  case ahQuarantineDB handles of
    Nothing -> throwAutonomousInvariant "persisted autonomous apply requires durable job authorization"
    Just db -> do
      sessionId <- case ahSessionId handles of
        Just value | not (T.null (T.strip value)) -> pure value
        _ -> throwAutonomousInvariant "persisted autonomous apply requires a session owner"
      broadJobs <- either throwAutonomousInvariant pure (learningApplyJobs events)
      corroborationProofs <- either throwAutonomousInvariant pure (corroborationApplyProofs events)
      result <- mask_ $ withDB (qdbPath db) $ \conn ->
        withImmediateTransaction conn $ do
          authorizeLearningJobsApplyOnConnection conn sessionId broadJobs
          authorizeCorroborationApplyOnConnection conn corroborationProofs
          RuntimeProjection.persistRuntimeEdgesOnConnection conn sessionId (aapAdmittedEdges plan)
          mapM_ (RuntimeProjection.corroborateRuntimeEdgeOnConnection conn sessionId)
            (aapCorroboratedEdges plan)
          insertLearningEventsOnConnection conn (aapLearningEvents plan)
          mapM_ (enqueueCorroborationTaskOnConnection conn) (aapCorroborationSeeds plan)
          mapM_ (\(taskId, requestId, leaseToken, state, resultKind) ->
            markCorroborationTaskTerminalOnConnection conn taskId requestId leaseToken state resultKind)
            (aapCorroborationOutcomes plan)
          recordQuarantinesOnConnection conn (aapQuarantines plan)
          markLearningJobsAppliedOnConnection conn sessionId broadJobs 300
      either throwAutonomousPersistenceError pure result

-- One provider response may yield several edge events. The durable job lease
-- is acknowledged once per request, while mismatched tokens fail the entire
-- transaction before any graph write commits.
learningApplyJobs :: [NetworkUpdateEvent] -> Either Text [(Text, Text, Text)]
learningApplyJobs = fmap M.elems . foldl addEvent (Right M.empty) . filter isBroad
  where
    isBroad evt = nueAdmissionDecision evt `notElem`
      [Just "corroboration_confirmation", Just "corroboration_conflict"]
    addEvent (Left err) _ = Left err
    addEvent (Right jobs) evt =
      let requestId = nueRequestId evt
      in case nueApplyToken evt >>= nonEmpty of
           Nothing -> Left ("durable broad apply is missing dispatch token for request " <> requestId)
           Just applyToken ->
             let job = (requestId, nueTopic evt, applyToken)
             in case M.lookup requestId jobs of
                  Nothing -> Right (M.insert requestId job jobs)
                  Just (_, priorTopic, priorToken)
                    | priorTopic == nueTopic evt && priorToken == applyToken -> Right jobs
                    | otherwise -> Left ("inconsistent durable apply envelope for request " <> requestId)
    nonEmpty value = if T.null (T.strip value) then Nothing else Just value

corroborationApplyProofs :: [NetworkUpdateEvent] -> Either Text [(Int64, Text, Text)]
corroborationApplyProofs = fmap M.elems . foldl addEvent (Right M.empty) . filter isCorroboration
  where
    isCorroboration evt = nueAdmissionDecision evt `elem`
      [Just "corroboration_confirmation", Just "corroboration_conflict"]
    addEvent (Left err) _ = Left err
    addEvent (Right proofs) evt = case (nueCorroborationTaskId evt, nueApplyToken evt >>= nonEmpty) of
      (Just taskId, Just applyToken) ->
        let proof = (taskId, nueRequestId evt, applyToken)
        in case M.lookup taskId proofs of
             Nothing -> Right (M.insert taskId proof proofs)
             Just prior
               | prior == proof -> Right proofs
               | otherwise -> Left ("inconsistent corroboration apply envelope for task " <> T.pack (show taskId))
      _ -> Left ("corroboration apply is missing exact task/token proof for request " <> nueRequestId evt)
    nonEmpty value = if T.null (T.strip value) then Nothing else Just value

withImmediateTransaction :: NSQL.Database -> IO a -> IO a
withImmediateTransaction conn action = mask_ $ do
  begun <- NSQL.execSql conn "BEGIN IMMEDIATE;"
  either throwAutonomousPersistenceError pure begun
  value <- action `onException` rollbackBestEffort conn
  committed <- NSQL.execSql conn "COMMIT;"
  case committed of
    Right () -> pure value
    Left err -> do
      rollbackBestEffort conn
      throwAutonomousPersistenceError err

rollbackBestEffort :: NSQL.Database -> IO ()
rollbackBestEffort conn = do
  _ <- NSQL.execSql conn "ROLLBACK;"
  pure ()

throwAutonomousInvariant :: Text -> IO a
throwAutonomousInvariant = throwQxFx0 . StateInvariantViolation

throwAutonomousPersistenceError :: Text -> IO a
throwAutonomousPersistenceError detail =
  throwQxFx0 (mkSQLiteError
    "runtime_session_autonomous"
    "AUTONOMOUS_APPLY_SQLITE_ERROR"
    (M.singleton "detail" detail))

updateMetrics :: AutonomousHandles -> (LearningMetrics -> LearningMetrics) -> IO ()
updateMetrics handles f =
  case ahMetricsRef handles of
    Nothing -> pure ()
    Just ref -> atomicModifyIORef' ref (\m -> (f m, ()))

-- | Atomically take the work permitted for this turn and put the remainder
-- back before any producer can observe the queue.  This preserves event order
-- and prevents capped updates from being silently discarded.
takeUpdateBatch :: TQueue NetworkUpdateEvent -> Int -> IO ([NetworkUpdateEvent], Int)
takeUpdateBatch q limit = STM.atomically $ do
  pending <- drain []
  let (initial, suffix) = splitAt limit pending
      crossingRequests = S.intersection
        (S.fromList [(nueRequestId evt, token) | evt <- initial, Just token <- [nueApplyToken evt]])
        (S.fromList [(nueRequestId evt, token) | evt <- suffix, Just token <- [nueApplyToken evt]])
      firstCrossing = findIndex
        (\evt -> maybe False (\token -> (nueRequestId evt, token) `S.member` crossingRequests) (nueApplyToken evt))
        initial
      (toApply, deferred) = case firstCrossing of
        Nothing -> (initial, suffix)
        Just boundary -> splitAt boundary pending
  mapM_ (STM.writeTQueue q) deferred
  pure (toApply, length deferred)
  where
    drain acc = do
      mt <- STM.tryReadTQueue q
      case mt of
        Just e -> drain (e : acc)
        Nothing -> pure (reverse acc)
