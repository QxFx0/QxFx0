{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Module      : QxFx0.Learning.Autonomous
Description : ADR-0054 M1 — Autonomous semantic network expansion worker.

This module provides the background worker that autonomously enriches
the semantic network via LLM calls.  It is **disabled by default** and
must be enabled via the @QXFX0_AUTONOMOUS_LEARNING@ environment
variable.

Key types:
* 'LearningTask' — a topic that needs enrichment (placed in the queue).
* 'NetworkUpdateEvent' — the result of a worker iteration, placed in
  the update channel that the turn pipeline drains between turns.

Key functions:
* 'newLearningQueue' — bounded queue for learning tasks.
* 'spawnAutonomousWorker' — forkIO that drains the queue and calls
  the LLM, emitting 'NetworkUpdateEvent's.
* 'autonomousApplyLLMResponse' — extract relations from a response with
  explicit 'AtomStore' / 'MorphologyData' (no global state).
-}

module QxFx0.Learning.Autonomous
  ( LearningTask(..)
  , NetworkUpdateEvent(..)
  , LearningQueue
  , newLearningQueue
  , enqueueLearningTask
  , drainLearningQueue
  , spawnAutonomousWorker
  , AutonomousWorkerConfig(..)
  , defaultAutonomousWorkerConfig
  , readAutonomousWorkerConfig
  , autonomousApplyLLMResponse
  , applyPendingNetworkUpdates
  , buildAtomMorphology
  , isTruthy
  , readIntWithDefault
  ) where

import Control.Applicative ((<|>))
import Control.Concurrent (forkIO, threadDelay)
import Data.Char (toLower, isSpace)
import Data.List (dropWhileEnd)
import Control.Concurrent.STM (TQueue, atomically, newTQueue, readTQueue, tryReadTQueue, writeTQueue)
import Control.Exception (SomeException, try)
import Control.Monad (forever, void, when)
import Data.Aeson (Object, Value(..), eitherDecodeStrict, object, toJSON, (.=))
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8
import Data.Foldable (foldl')
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (mapMaybe)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime, NominalDiffTime)
import qualified Network.HTTP.Client as HC
import qualified Network.HTTP.Client.TLS as HCT
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

import QxFx0.Bridge.ExternalLLM (buildTransportFromEnv, queryExternalTool)
import QxFx0.Learning.Need (LearningNeed(..), renderLearningNeed)
import QxFx0.Learning.Tool (ExternalTool(..), ToolDomain(..))
import QxFx0.Semantic.Content.AtomStore
  ( Atom(..)
  , AtomId(..)
  , Relation(..)
  , RelationType(..)
  , atomStore
  , atomDisplay
  , atomHead
  )
import QxFx0.Semantic.LLMDiscovery (parseLLMRelations, buildDiscoveryPrompt)
import QxFx0.Semantic.Morphology (toNominative)
import QxFx0.Semantic.Network (mergeSemanticNetworksWithProvenance)
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , relationTypeWeight
  )
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  )
import QxFx0.Types.State.System (SystemState(..), ssSemanticNetwork)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A topic that the worker should try to enrich via an LLM call.
data LearningTask = LearningTask
  { ltTopic     :: Text
  , ltPriority  :: Double   -- ^ higher = more important (1/density)
  , ltRequestId :: Text     -- ^ for tracing
  }
  deriving stock (Eq, Show)

-- | The result of a single worker iteration: a list of semantic edges
-- to merge into 'ssSemanticNetwork' on the next between-turn apply.
data NetworkUpdateEvent = NetworkUpdateEvent
  { nueTopic     :: Text
  , nueEdges     :: [SemanticEdge]
  , nueTimestamp :: UTCTime
  }
  deriving stock (Eq, Show)

-- | Bounded queue of 'LearningTask's.
newtype LearningQueue = LearningQueue (TQueue LearningTask)

-- | Worker configuration.  All quotas default to safe values; the
-- feature is fail-closed when the LLM transport is unavailable.
data AutonomousWorkerConfig = AutonomousWorkerConfig
  { awcEnabled            :: Bool
  , awcMaxRequestsPerHour :: Int
  , awcMaxEdgesPerBatch   :: Int
  , awcQueueCap           :: Int
  , awcHourResetDelaySec  :: Int    -- ^ sleeps when quota reached
  }
  deriving stock (Eq, Show)

defaultAutonomousWorkerConfig :: AutonomousWorkerConfig
defaultAutonomousWorkerConfig = AutonomousWorkerConfig
  { awcEnabled            = False
  , awcMaxRequestsPerHour = 10
  , awcMaxEdgesPerBatch   = 5
  , awcQueueCap           = 100
  , awcHourResetDelaySec  = 60
  }

-- | Read configuration from environment variables.  Mirrors the
-- quota semantics described in ADR-0054 §M1.
readAutonomousWorkerConfig :: IO AutonomousWorkerConfig
readAutonomousWorkerConfig = do
  mEnabled <- lookupEnv "QXFX0_AUTONOMOUS_LEARNING"
  mMaxReq  <- lookupEnv "QXFX0_LEARNING_MAX_REQ_PER_HOUR"
  mMaxEdge <- lookupEnv "QXFX0_LEARNING_MAX_EDGES_PER_BATCH"
  mQCap    <- lookupEnv "QXFX0_LEARNING_QUEUE_CAP"
  pure AutonomousWorkerConfig
    { awcEnabled            = isTruthy mEnabled
    , awcMaxRequestsPerHour = readIntWithDefault mMaxReq 10
    , awcMaxEdgesPerBatch   = readIntWithDefault mMaxEdge 5
    , awcQueueCap           = readIntWithDefault mQCap 100
    , awcHourResetDelaySec  = 60
    }

isTruthy :: Maybe String -> Bool
isTruthy (Just t) = map toLower (dropWhileEnd isSpace (dropWhile isSpace t)) `elem` ["1", "true", "yes", "on"]
isTruthy Nothing  = False

readIntWithDefault :: Maybe String -> Int -> Int
readIntWithDefault (Just t) d =
  let trimmed = dropWhileEnd isSpace (dropWhile isSpace t)
  in case reads trimmed :: [(Int, String)] of
       [(n, "")] -> n
       _         -> d
readIntWithDefault Nothing d = d

-- ---------------------------------------------------------------------------
-- Queue helpers
-- ---------------------------------------------------------------------------

-- | Create a new bounded learning queue.  Note: 'TQueue' itself is
-- unbounded, so callers should respect the 'awcQueueCap' policy when
-- enqueueing tasks (we do not block on cap).
newLearningQueue :: IO LearningQueue
newLearningQueue = LearningQueue <$> atomically newTQueue

enqueueLearningTask :: LearningQueue -> LearningTask -> IO ()
enqueueLearningTask (LearningQueue q) t = atomically (writeTQueue q t)

-- | Non-blocking drain — returns all tasks currently in the queue.
drainLearningQueue :: LearningQueue -> IO [LearningTask]
drainLearningQueue (LearningQueue q) = atomically (loop [])
  where
    loop acc = do
      mt <- tryReadTQueue q
      case mt of
        Just t  -> loop (t : acc)
        Nothing -> pure (reverse acc)

-- ---------------------------------------------------------------------------
-- LLM response → SemanticNetwork (explicit store)
-- ---------------------------------------------------------------------------

-- | Build the morphology data needed by 'autonomousApplyLLMResponse'
-- from the curated atom store.  Mirrors 'atomMorphologyData' in
-- 'QxFx0.Semantic.Network.Ingest' but operates on an explicit atom
-- store parameter.
buildAtomMorphology :: Map AtomId Atom -> MorphologyData
buildAtomMorphology store = MorphologyData
  { mdPrepositional = M.empty
  , mdGenitive      = M.empty
  , mdNominative    = M.fromList [ (atomDisplay a, atomHead a) | (_, a) <- M.toList store ]
  , mdFormsBySurface = M.empty
  }

-- | Normalize an endpoint text using the given morphology (in
-- nominative form) without relying on global state.
normalizeRelationTextWith
  :: MorphologyData
  -> Text
  -> Text
normalizeRelationTextWith morph text =
  let stripped = T.strip (stripEndPrepositions (T.strip text))
  in T.strip (toNominative morph stripped)

stripEndPrepositions :: Text -> Text
stripEndPrepositions text =
  let words' = T.words text
      dropPrep = dropWhile (`S.member` russianPrepositions)
      stripped = reverse . dropPrep . reverse . dropPrep $ words'
  in T.unwords stripped

russianPrepositions :: S.Set Text
russianPrepositions = S.fromList
  [ "в", "на", "с", "по", "для", "к", "о", "об", "обо", "от"
  , "до", "из", "за", "под", "над", "перед", "при", "про", "через"
  , "между"
  ]

-- | Admit an endpoint against an explicit atom store (no global state).
admitRelationEndpointWith
  :: Map AtomId Atom
  -> MorphologyData
  -> Text
  -> Maybe Atom
admitRelationEndpointWith store morph text =
  let normalized = normalizeRelationTextWith morph text
      displayMap = M.fromList [ (atomDisplay a, a) | (_, a) <- M.toList store ]
      headMap    = M.fromList [ (atomHead a, a)    | (_, a) <- M.toList store ]
  in  M.lookup (AtomId normalized) store
      <|> M.lookup normalized displayMap
      <|> M.lookup normalized headMap

-- | Like 'applyLLMResponseToSemanticNetwork' (Learning/Loop.hs) but
-- takes the atom store and morphology as explicit arguments.
-- Confidence is seeded low (0.6); runtime-LLM edges are subordinate
-- to curated/selfplay edges until reinforced by feedback.
autonomousApplyLLMResponse
  :: Map AtomId Atom          -- ^ curated atom store
  -> MorphologyData          -- ^ morphology data for nominative normalization
  -> LearningNeed
  -> ExternalQueryResponse
  -> SemanticNetwork
autonomousApplyLLMResponse store morph need resp =
  let concept = renderLearningNeed need
      body = if T.null (eqrStructured resp) then eqrRawBody resp else eqrStructured resp
      candidates = parseLLMRelations concept body
      admitted = mapMaybe (admitRelation morph) candidates
      nodes = foldl' (\acc (f, t, _, _) -> S.insert f (S.insert t acc)) S.empty admitted
      edges = foldl' insertEdge M.empty admitted
      insertEdge acc (f, t, rt, mverb) =
        let key = (f, t)
            w = relationTypeWeight rt
            edge = SemanticEdge
              { seFrom         = f
              , seTo           = t
              , seWeight       = w * 0.6
              , seCoOccurrence = 1
              , seSource       = ExplicitEdge
              , seRelationType = Just rt
              , seVerb         = mverb
              , seRationale    = Nothing
              , seCounter      = Nothing
              , seSynthesis    = Nothing
              , seConfidence   = 0.6
              , seProvenance   = ProvenanceIngested
              }
        in case M.lookup key acc of
             Nothing -> M.insert key edge acc
             Just old -> if seWeight edge > seWeight old then M.insert key edge acc else acc
  in SemanticNetwork
      { snNodes         = nodes
      , snEdges         = edges
      , snActivation    = M.empty
      , snDecayRate     = 0.5
      , snMaxHops       = 3
      , snActivationLog = mempty
      }
  where
    admitRelation :: MorphologyData -> Relation -> Maybe (Text, Text, RelationType, Maybe Text)
    admitRelation m r =
      let AtomId fromId = relFrom r
          AtomId toId   = relTo r
      in do
        fromAtom <- admitRelationEndpointWith store m fromId
        toAtom   <- admitRelationEndpointWith store m toId
        pure (atomDisplay fromAtom, atomDisplay toAtom, relType r, relVerbText r)

-- ---------------------------------------------------------------------------
-- Between-turn apply
-- ---------------------------------------------------------------------------

-- | Drain the update channel and merge all pending 'NetworkUpdateEvent's
-- into the runtime 'ssSemanticNetwork'.  Safe to call between turns.
applyPendingNetworkUpdates
  :: Map AtomId Atom
  -> MorphologyData
  -> TQueue NetworkUpdateEvent
  -> SystemState
  -> IO SystemState
applyPendingNetworkUpdates store morph updates ss = do
  pending <- drainUpdateQueue updates
  let merged = foldl' applyOne (ssSemanticNetwork ss) pending
  pure ss { ssSemanticNetwork = merged }
  where
    applyOne sn evt =
      mergeSemanticNetworksWithProvenance sn (nueEdgesToNetwork store morph evt)
    drainUpdateQueue q = atomically (loop [])
      where
        loop acc = do
          mt <- tryReadTQueue q
          case mt of
            Just e  -> loop (e : acc)
            Nothing -> pure (reverse acc)
    nueEdgesToNetwork _store _morph evt =
      SemanticNetwork
        { snNodes         = S.fromList (concat [[nueTopic evt], map seFrom (nueEdges evt), map seTo (nueEdges evt)])
        , snEdges         = M.fromList [ ((seFrom e, seTo e), e) | e <- nueEdges evt ]
        , snActivation    = M.empty
        , snDecayRate     = 0.5
        , snMaxHops       = 3
        , snActivationLog = mempty
        }

-- ---------------------------------------------------------------------------
-- Worker
-- ---------------------------------------------------------------------------

-- | Quota state: monotonic timestamp of last quota reset and count
-- since reset.
data QuotaState = QuotaState
  { qsResetAt  :: UTCTime
  , qsRequests :: Int
  }

newQuotaState :: UTCTime -> QuotaState
newQuotaState t = QuotaState { qsResetAt = t, qsRequests = 0 }

quotaExceeded :: AutonomousWorkerConfig -> QuotaState -> Bool
quotaExceeded cfg qs = qsRequests qs >= awcMaxRequestsPerHour cfg

-- | Spawn a worker thread that drains the queue and writes
-- 'NetworkUpdateEvent's to the update channel.  The thread loops
-- forever (the caller is responsible for its lifecycle).  Worker is
-- fail-closed: any exception is logged and the thread exits.
--
-- For testing, set @QXFX0_LLM_TRANSPORT=mock@ to use the in-process
-- mock transport (see 'QxFx0.Bridge.ExternalLLM.buildTransportFromEnv').
spawnAutonomousWorker
  :: AutonomousWorkerConfig
  -> Map AtomId Atom
  -> MorphologyData
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> IO ()
spawnAutonomousWorker cfg store morph (LearningQueue taskQ) updateQ = do
  qsRef <- newIORef =<< newQuotaState <$> getCurrentTime
  void . forkIO . forever $ do
    if not (awcEnabled cfg)
      then threadDelay (60 * 1000 * 1000)  -- sleep 60s when disabled
      else do
        drainResult <- try (drainLearningQueue (LearningQueue taskQ))
        case drainResult of
          Left (e :: SomeException) -> do
            hPutStrLn stderr $ "[autonomous] drain error: " <> show e
            threadDelay (10 * 1000 * 1000)  -- back off on error
          Right [] -> threadDelay (5 * 1000 * 1000)  -- idle
          Right tasks -> do
            -- Process at most one task per iteration to bound LLM spend.
            let task = head tasks
            processOneTask cfg store morph qsRef taskQ updateQ task

-- | Process a single learning task with quota enforcement.
processOneTask
  :: AutonomousWorkerConfig
  -> Map AtomId Atom
  -> MorphologyData
  -> IORef QuotaState
  -> TQueue LearningTask
  -> TQueue NetworkUpdateEvent
  -> LearningTask
  -> IO ()
processOneTask cfg store morph qsRef taskQ updateQ task = do
  -- Quota check
  now <- getCurrentTime
  qs <- atomicModifyIORef' qsRef (\q -> checkAndBump q (awcMaxRequestsPerHour cfg, now))
  if quotaExceeded cfg qs
    then do
      -- Re-enqueue and back off (caller will sleep on idle drain)
      enqueueLearningTask (LearningQueue taskQ) task
      threadDelay (fromIntegral (awcHourResetDelaySec cfg) * 1000 * 1000)
    else do
      tool <- pure ExternalTool
        { etName        = "autonomous_learning"
        , etDomain      = DomainGeneral
        , etReliability = 0.5
        , etValidatable = False
        }
      need <- pure NeedKeywordEnrichment
      queryText <- pure (buildDiscoveryPrompt (ltTopic task))
      result <- do
        transportResult <- try (buildTransportFromEnv)
        case transportResult of
          Left (e :: SomeException) -> do
            hPutStrLn stderr $ "[autonomous] transport error: " <> show e
            pure (Left EqeEmptyResponse)
          Right transport -> do
            r <- try (queryExternalTool transport tool need queryText)
            case r of
              Left (e :: SomeException) -> do
                hPutStrLn stderr $ "[autonomous] query error: " <> show e
                pure (Left EqeEmptyResponse)
              Right v -> pure v
      case result of
        Left err -> do
          hPutStrLn stderr $ "[autonomous] LLM error for topic '" <> T.unpack (ltTopic task) <> "': " <> show err
        Right resp -> do
          let net = autonomousApplyLLMResponse store morph need resp
              edges = M.elems (snEdges net)
              truncated = take (awcMaxEdgesPerBatch cfg) edges
              evt = NetworkUpdateEvent
                { nueTopic     = ltTopic task
                , nueEdges     = truncated
                , nueTimestamp = now
                }
          atomically (writeTQueue updateQ evt)

-- | Atomically bump quota counter and reset window if elapsed.
checkAndBump :: QuotaState -> (Int, UTCTime) -> (QuotaState, QuotaState)
checkAndBump qs (maxReq, now)
  | diffUTCTime now (qsResetAt qs) >= 3600 =
      ( QuotaState { qsResetAt = now, qsRequests = 1 }
      , QuotaState { qsResetAt = now, qsRequests = 1 }
      )
  | otherwise =
      let qs' = qs { qsRequests = qsRequests qs + 1 }
      in (qs', qs')
  where
    _ = maxReq  -- bound for clarity; not used here, enforced at call site
