{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}

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
  , newPersistentLearningQueue
  , newPersistentLearningQueueForSession
  , enqueueLearningTask
  , drainLearningQueue
  , spawnAutonomousWorker
  , spawnAutonomousWorkerWithTopicAtoms
  , spawnAutonomousWorkerWithTopicAtomsAndPredicates
  , spawnAutonomousWorkerWithTransport
  , AutonomousWorkerConfig(..)
  , AutonomousMode(..)
  , defaultAutonomousWorkerConfig
  , readAutonomousWorkerConfig
  , autonomousApplyLLMResponse
  , autonomousApplyLLMResponseForTopic
  , auditHistoricalSelectorPreflight
  , acquisitionPreflightPass
  , responseViolatesTopicLanguage
  , CompetitiveUtilityAudit(..)
  , evaluateCompetitiveUtility
  , corroborationPriority
  , ConfirmationOutcome(..)
  , confirmationOutcome
  , buildAtomMorphology
  , extendAtomStoreWithTopics
  , isTruthy
  , readIntWithDefault
  , enqueueIfStarving
  , enqueueIfStarvingWithTopicAtoms
  , enqueueStarvingTopics
  , enqueueStarvingTopicsWithTopicAtoms
  , maybeEnqueueStarvingTopic
  , spawnDensityAudit
  , spawnDensityAuditWithTopicAtoms
  , ManagedWorker
  , stopManagedWorker
  , CircuitBreakerState(..)
  , isCircuitOpen
  ) where

import Control.Applicative ((<|>))
import Control.Concurrent (threadDelay)
import Data.Char (isAlpha, isAscii, toLower, isSpace)
import Data.List (dropWhileEnd, maximumBy, sortBy)
import Control.Concurrent.STM (TQueue, atomically, newTQueue, readTQueue, tryReadTQueue, writeTQueue)
import Control.Exception (AsyncException, SomeException, catch, finally, fromException, mask, mask_, onException, throwIO, try)
import Control.Monad (forM_, forever, unless, void, when)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeStrict, encode)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8
import Data.Foldable (foldl')
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.Int (Int64)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Ord (comparing)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Data.Time.Clock (UTCTime, getCurrentTime, diffUTCTime, NominalDiffTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import GHC.Generics (Generic)
import qualified Network.HTTP.Client as HC
import qualified Network.HTTP.Client.TLS as HCT
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)
import System.Timeout (timeout)

import QxFx0.Bridge.ExternalLLM
  ( LLMTransport
  , buildTransportFromEnv
  , closeOwnedTransport
  , isRetryableError
  , llmMaxCompletionTokens
  , queryExternalTool
  , transportMaxAttempts
  , transportModel
  )
import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Learning.JobQueue
  ( LearningJob(..)
  , LearningJobClaim
  , LearningQuotaLimits(..)
  , LearningReadyPayload(..)
  , claimLearningJob
  , claimLearningReadyPayloads
  , claimLearningReadyPayloadsForSession
  , enqueueLearningJob
  , enqueueLearningJobForSession
  , ensureLearningJobSchema
  , loadRunnableLearningJobs
  , loadRunnableLearningJobsForSession
  , markLearningJobClaimFailed
  , markLearningJobClaimFailedOnConnection
  , recordLearningJobResponseReady
  , recordLearningResponseOnConnection
  , rejectLearningReadyPayload
  , releaseLearningReadyPayloads
  , releaseLearningJobClaim
  , reserveLearningQuota
  , recordLearningTopicCooldownOnConnection
  , advanceLearningTopicCursor
  )
import QxFx0.Learning.Need (LearningNeed(..), renderLearningNeed)
import QxFx0.Learning.Promotion
  ( InformativenessResult(..)
  , PromotionCandidate(..)
  , evaluateCandidateInformativeness
  )
import QxFx0.Learning.CorroborationQueue
  ( CorroborationTask(..)
  , CorroborationReadyResponse(..)
  , CorroborationTaskState(..)
  , claimCorroborationBatch
  , claimCorroborationBatchForSession
  , loadCorroborationResponseReady
  , loadCorroborationResponseReadyForSession
  , ensureCorroborationTaskSchema
  , markCorroborationTaskTerminal
  , markCorroborationTaskFailed
  , recordCorroborationResponseReady
  , releaseCorroborationBatch
  , releaseCorroborationReadyResponses
  )
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , LearningEventSource(..)
  , ensureLearningEventsSchema
  , insertLearningEventsOnConnection
  )
import QxFx0.Learning.Tool (ExternalTool(..), ToolDomain(..))
import QxFx0.Semantic.Content.AtomStore
  ( Atom(..)
  , AtomCategory(..)
  , AtomId(..)
  , Relation(..)
  , RelationType(..)
  , atomStore
  , atomDisplay
  , atomHead
  )
import QxFx0.Semantic.LLMDiscovery
  ( buildDiscoveryPromptWithCandidates
  , buildGapAwareDiscoveryPrompt
  , buildCorroborationPrompt
  , parseStructuredLLMRelations
  , responseViolatesTopicLanguage
  )
import QxFx0.Semantic.Network.Seed
  ( DensityConfig(..)
  , buildTopicAtomsMap
  , contentDensity
  , seedFromCorpus
  , starvingTopics
  )
import QxFx0.Semantic.Morphology (buildLemmaMap)
import QxFx0.Semantic.Morphology (toNominative)
import QxFx0.Semantic.Network (mergeSemanticNetworksWithProvenance, activateTopicWithField)
import QxFx0.Semantic.Space (buildSemanticSpace)
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , relationTypeWeight
  , semanticEdge
  )
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  , renderExternalQueryError
  )
import QxFx0.Semantic.Content
  ( CanonicalPredicateRelation(..)
  , DefinitionContent(..)
  , definitionCorpus
  , PredicateRole(..)
  , SemanticPredicate(..)
  , mkPred
  )
import QxFx0.Semantic.ContentSelector
  ( buildContentSelector
  , selectPredicatesWithDiagnostics
  )
import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..), SelectedPredicate(..), SelectorDiagnostic(..))
import QxFx0.Self.Field (Field(..), Resonance(..), emptyField)
import QxFx0.Learning.Quarantine (sha256Hex)
import QxFx0.Types.State.System (SystemState(..), ssSemanticNetwork)
import QxFx0.Runtime.ManagedWorker (ManagedWorker, spawnManagedWorker, stopManagedWorker)
import QxFx0.ExceptionPolicy (mkSQLiteError, throwQxFx0)

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
  , nueRequestId :: Text
  , nuePromptHash :: Maybe Text
  , nueResponseHash :: Maybe Text
  , nueModel :: Maybe Text
  , nueParserDecision :: Maybe Text
  , nueAdmissionDecision :: Maybe Text
  , nueEvidenceSource :: Maybe Text
  -- | Present only for first-admission candidates that passed competitive
  -- utility ranking. Governed apply turns this into a durable corroboration
  -- task; ordinary runtime admissions never read this field.
  , nueCompetitiveAudit :: Maybe Text
  , nueCorroborationPriority :: Maybe Double
  , nueCorroborationTaskId :: Maybe Int64
  -- | Durable broad apply lease. Present only after response_ready dispatch;
  -- governed persistence uses it to reject stale queued deliveries.
  , nueApplyToken :: Maybe Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

newtype BroadReadyEnvelope = BroadReadyEnvelope
  { breEvents :: [NetworkUpdateEvent]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Pure decision evidence for whether a structurally safe first hypothesis is
-- worth spending an independent corroboration request on. It never decides
-- knowledge admission and is evaluated only on transient selector state.
data CompetitiveUtilityAudit = CompetitiveUtilityAudit
  { cuaBasePrimary :: !(Maybe Text)
  , cuaTransientPrimary :: !(Maybe Text)
  , cuaCandidateRole :: !Text
  , cuaCandidateScore :: !(Maybe Double)
  , cuaCandidateMarginalGain :: !(Maybe Double)
  , cuaBasePrimaryPreserved :: !Bool
  , cuaContribution :: !Text
  , cuaContributionNew :: !Bool
  , cuaQualifiedForCorroboration :: !Bool
  , cuaPrototypeFields :: !Int
  } deriving stock (Eq, Show)

-- | Bounded execution queue backed by an optional durable job store.
data LearningQueue = LearningQueue
  { lqTasks       :: !(TQueue LearningTask)
  , lqSize        :: !(IORef Int)
  , lqCapacity    :: !Int
  , lqPersistence :: !(Maybe QxFx0DB)
  , lqSessionId   :: !(Maybe Text)
  }

-- | Worker configuration.  All quotas default to safe values; the
-- feature is fail-closed when the LLM transport is unavailable.
data AutonomousMode
  = CorroborationOnly
  | FullAutonomous
  deriving stock (Eq, Show)

data AutonomousWorkerConfig = AutonomousWorkerConfig
  { awcEnabled                  :: Bool
  , awcMode                     :: AutonomousMode
  , awcMaxRequestsPerMinute     :: Int
  , awcMaxRequestsPerHour       :: Int
  , awcMaxRequestsPerDay        :: Int
  , awcMaxTokensPerMinute       :: Int
  , awcMaxTokensPerHour         :: Int
  , awcMaxTokensPerDay          :: Int
  , awcReservedCompletionTokens :: Int
  , awcMaxEdgesPerBatch         :: Int
  , awcQueueCap                 :: Int
  , awcHourResetDelaySec        :: Int    -- ^ sleeps when any quota is reached
  , awcProviderTimeoutMs        :: Int    -- ^ total wall-clock bound per provider call
  }
  deriving stock (Eq, Show)

defaultAutonomousWorkerConfig :: AutonomousWorkerConfig
defaultAutonomousWorkerConfig = AutonomousWorkerConfig
  { awcEnabled                  = False
  , awcMode                     = CorroborationOnly
  , awcMaxRequestsPerMinute     = 100
  , awcMaxRequestsPerHour       = 6000
  , awcMaxRequestsPerDay        = 144000
  , awcMaxTokensPerMinute       = 100000
  , awcMaxTokensPerHour         = 6000000
  , awcMaxTokensPerDay          = 144000000
  , awcReservedCompletionTokens = 512
  , awcMaxEdgesPerBatch         = 5
  , awcQueueCap                 = 100
  , awcHourResetDelaySec        = 60
  , awcProviderTimeoutMs        = 120000
  }

-- | Circuit breaker state for autonomous learning.
-- Used by the breaker watcher to determine if the learning queue should
-- drain pending tasks or remain blocked.
data CircuitBreakerState
  = CircuitClosed
  | CircuitOpen
  | CircuitHalfOpen
  deriving stock (Eq, Show)

-- | Check if the circuit breaker is in an open state.
-- Returns 'True' when the breaker is open (blocking new requests).
isCircuitOpen :: CircuitBreakerState -> UTCTime -> Bool
isCircuitOpen CircuitOpen     _ = True
isCircuitOpen CircuitHalfOpen _ = True
isCircuitOpen CircuitClosed   _ = False

-- | Read configuration from environment variables.  Mirrors the
-- quota semantics described in ADR-0054 §M1.
readAutonomousWorkerConfig :: IO AutonomousWorkerConfig
readAutonomousWorkerConfig = do
  mEnabled <- lookupEnv "QXFX0_AUTONOMOUS_LEARNING"
  mMode <- lookupEnv "QXFX0_AUTONOMOUS_MODE"
  mMaxReqM <- lookupEnv "QXFX0_LEARNING_MAX_REQ_PER_MINUTE"
  mMaxReqH <- lookupEnv "QXFX0_LEARNING_MAX_REQ_PER_HOUR"
  mMaxReqD <- lookupEnv "QXFX0_LEARNING_MAX_REQ_PER_DAY"
  mMaxTokM <- lookupEnv "QXFX0_LEARNING_MAX_TOKENS_PER_MINUTE"
  mMaxTokH <- lookupEnv "QXFX0_LEARNING_MAX_TOKENS_PER_HOUR"
  mMaxTokD <- lookupEnv "QXFX0_LEARNING_MAX_TOKENS_PER_DAY"
  mReserve <- lookupEnv "QXFX0_LEARNING_RESERVED_COMPLETION_TOKENS"
  mMaxEdge <- lookupEnv "QXFX0_LEARNING_MAX_EDGES_PER_BATCH"
  mQCap    <- lookupEnv "QXFX0_LEARNING_QUEUE_CAP"
  mProviderTimeout <- lookupEnv "QXFX0_LEARNING_PROVIDER_TIMEOUT_MS"
  pure AutonomousWorkerConfig
    { awcEnabled                  = isTruthy mEnabled
    , awcMode                     = readAutonomousMode mMode
    , awcMaxRequestsPerMinute     = readIntWithDefault mMaxReqM 100
    , awcMaxRequestsPerHour       = readIntWithDefault mMaxReqH 6000
    , awcMaxRequestsPerDay        = readIntWithDefault mMaxReqD 144000
    , awcMaxTokensPerMinute       = readIntWithDefault mMaxTokM 100000
    , awcMaxTokensPerHour         = readIntWithDefault mMaxTokH 6000000
    , awcMaxTokensPerDay          = readIntWithDefault mMaxTokD 144000000
    , awcReservedCompletionTokens = readIntWithDefault mReserve 512
    , awcMaxEdgesPerBatch         = readIntWithDefault mMaxEdge 5
    , awcQueueCap                 = readIntWithDefault mQCap 100
    , awcHourResetDelaySec        = 60
    , awcProviderTimeoutMs        = max 1000 (min 300000 (readIntWithDefault mProviderTimeout 120000))
    }

readAutonomousMode :: Maybe String -> AutonomousMode
readAutonomousMode raw =
  case fmap (map toLower . dropWhileEnd isSpace . dropWhile isSpace) raw of
    Just "full" -> FullAutonomous
    _ -> CorroborationOnly

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

-- | Create a non-persistent bounded learning queue.  Production bootstrap
-- uses 'newPersistentLearningQueue'.
newLearningQueue :: IO LearningQueue
newLearningQueue = newLearningQueueWithPersistence Nothing Nothing 100

newPersistentLearningQueue :: QxFx0DB -> Int -> IO LearningQueue
newPersistentLearningQueue db = newPersistentLearningQueueForSession db Nothing

newPersistentLearningQueueForSession :: QxFx0DB -> Maybe Text -> Int -> IO LearningQueue
newPersistentLearningQueueForSession db sessionId capacity = do
  ensureLearningJobSchema db
  ensureLearningEventsSchema db
  ensureCorroborationTaskSchema db
  queue <- newLearningQueueWithPersistence (Just db) sessionId capacity
  jobs <- loadRunnableLearningJobsForSession db (maybe "autonomous-default" id sessionId) (max 0 capacity)
  mapM_ (pushLoadedTask queue) jobs
  pure queue

newLearningQueueWithPersistence :: Maybe QxFx0DB -> Maybe Text -> Int -> IO LearningQueue
newLearningQueueWithPersistence persistence sessionId capacity = do
  tasks <- atomically newTQueue
  size <- newIORef 0
  pure LearningQueue
    { lqTasks = tasks
    , lqSize = size
    , lqCapacity = max 1 capacity
    , lqPersistence = persistence
    , lqSessionId = sessionId
    }

pushLoadedTask :: LearningQueue -> LearningJob -> IO ()
pushLoadedTask queue job = do
  accepted <- reserveQueueSlot queue
  when accepted $ atomically (writeTQueue (lqTasks queue) (LearningTask (ljTopic job) (ljPriority job) (ljRequestId job)))

-- | Enqueue a task, applying capacity and durable deduplication when enabled.
enqueueLearningTask :: LearningQueue -> LearningTask -> IO Bool
enqueueLearningTask queue task = do
  reserved <- reserveQueueSlot queue
  if not reserved
    then pure False
    else (do
      persisted <- case lqPersistence queue of
        Nothing -> pure True
        Just db -> enqueueLearningJobForSession db (maybe "autonomous-default" id (lqSessionId queue))
          (ltRequestId task) (ltTopic task) (ltPriority task) 3
      if persisted
        then atomically (writeTQueue (lqTasks queue) task) >> pure True
        else releaseQueueSlot queue >> pure False)
      -- Reserving capacity precedes the durable insert.  If that insert (or
      -- the in-memory hand-off) throws, do not strand the reserved slot.
      `onException` releaseQueueSlot queue

-- | Requeue a task already represented by a durable job.  Re-running the
-- durable INSERT here would be rejected by active-key deduplication and lose
-- the in-memory hand-off.  Only the worker uses this after it has drained or
-- deferred one of its own tasks.
requeueExistingTask :: LearningQueue -> LearningTask -> IO ()
requeueExistingTask queue task = do
  reserved <- reserveQueueSlot queue
  when reserved $ atomically (writeTQueue (lqTasks queue) task)

reserveQueueSlot :: LearningQueue -> IO Bool
reserveQueueSlot queue = atomicModifyIORef' (lqSize queue) $ \n ->
  if n >= lqCapacity queue then (n, False) else (n + 1, True)

releaseQueueSlot :: LearningQueue -> IO ()
releaseQueueSlot queue = atomicModifyIORef' (lqSize queue) $ \n -> (max 0 (n - 1), ())

-- | Non-blocking drain — returns all tasks currently in the queue.
drainLearningQueue :: LearningQueue -> IO [LearningTask]
drainLearningQueue queue = do
  tasks <- atomically (loop [])
  atomicModifyIORef' (lqSize queue) $ \n -> (max 0 (n - length tasks), ())
  pure tasks
  where
    loop acc = do
      mt <- tryReadTQueue (lqTasks queue)
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
autonomousApplyLLMResponse store morph need =
  autonomousApplyLLMResponseForTopic store morph (renderLearningNeed need)

-- | Topic-aware variant used by the autonomous worker.  The topic becomes
-- response provenance for legacy parsing; endpoint admission remains solely
-- local through the supplied registry and morphology.
autonomousApplyLLMResponseForTopic
  :: Map AtomId Atom
  -> MorphologyData
  -> Text
  -> ExternalQueryResponse
  -> SemanticNetwork
autonomousApplyLLMResponseForTopic store morph concept resp =
  let
      body = if T.null (eqrStructured resp) then eqrRawBody resp else eqrStructured resp
      candidates = parseStructuredLLMRelations concept body
      admitted = mapMaybe (admitRelation morph) candidates
      nodes = foldl' (\acc (f, t, _, _, _) -> S.insert f (S.insert t acc)) S.empty admitted
      edges = foldl' insertEdge M.empty admitted
      insertEdge acc (f, t, rt, mverb, mrationale) =
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
              , seRationale    = mrationale
              , seCounter      = Nothing
              , seSynthesis    = Nothing
              , seConfidence   = 0.6
              , seProvenance   = ProvenanceIngested
              , seDomain       = Nothing
              , seTemporalScope = Nothing
              , seNamespace    = Nothing
              , seLineage      = Nothing
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
    admitRelation :: MorphologyData -> Relation -> Maybe (Text, Text, RelationType, Maybe Text, Maybe Text)
    admitRelation m r =
      let AtomId fromId = relFrom r
          AtomId toId   = relTo r
      in do
        fromAtom <- admitRelationEndpointWith store m fromId
        toAtom   <- admitRelationEndpointWith store m toId
        pure (atomDisplay fromAtom, atomDisplay toAtom, relType r, relVerbText r, relRationale r)

-- ---------------------------------------------------------------------------
-- Worker
-- ---------------------------------------------------------------------------

-- | Quota state: monotonic timestamp of last quota reset and count
-- since reset.
data QuotaState = QuotaState
  { qsMinuteResetAt :: UTCTime
  , qsRequestsMinute :: Int
  , qsTokensMinute :: Int
  , qsHourResetAt :: UTCTime
  , qsRequestsHour :: Int
  , qsTokensHour :: Int
  , qsDayResetAt :: UTCTime
  , qsRequestsDay :: Int
  , qsTokensDay :: Int
  }

-- | Extend the worker's admission registry with all topics loaded from the
-- curated runtime corpus.  The worker may propose edges only between entries
-- in this registry; arbitrary LLM text remains rejected.
extendAtomStoreWithTopics
  :: Map AtomId Atom
  -> Map Text DefinitionContent
  -> Map AtomId Atom
extendAtomStoreWithTopics store corpus =
  M.foldlWithKey' addTopic store corpus
  where
    addTopic acc topic _ =
      let normalized = T.toLower (T.strip topic)
          aid = AtomId normalized
          atom = Atom aid normalized normalized normalized CatTopic
      in M.insertWith (\_ existing -> existing) aid atom acc

newQuotaState :: UTCTime -> QuotaState
newQuotaState t = QuotaState
  { qsMinuteResetAt = t, qsRequestsMinute = 0, qsTokensMinute = 0
  , qsHourResetAt = t, qsRequestsHour = 0, qsTokensHour = 0
  , qsDayResetAt = t, qsRequestsDay = 0, qsTokensDay = 0
  }

quotaExceeded :: AutonomousWorkerConfig -> QuotaState -> Int -> Int -> Bool
quotaExceeded cfg qs requests tokens =
  qsRequestsMinute qs + requests > max 0 (awcMaxRequestsPerMinute cfg)
    || qsRequestsHour qs + requests > max 0 (awcMaxRequestsPerHour cfg)
    || qsRequestsDay qs + requests > max 0 (awcMaxRequestsPerDay cfg)
    || qsTokensMinute qs + tokens > max 0 (awcMaxTokensPerMinute cfg)
    || qsTokensHour qs + tokens > max 0 (awcMaxTokensPerHour cfg)
    || qsTokensDay qs + tokens > max 0 (awcMaxTokensPerDay cfg)

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
  -> IO ManagedWorker
spawnAutonomousWorker cfg store morph queue updateQ =
  spawnAutonomousWorkerWithTopicAtoms
    cfg store morph (buildTopicAtomsMap (buildLemmaMap morph)) queue updateQ

-- | Runtime variant supplied with predicate-overlap data from the complete
-- loaded corpus.  Its prompt contains only a compact, locally selected
-- endpoint shortlist, while final admission remains local and deterministic.
spawnAutonomousWorkerWithTopicAtoms
  :: AutonomousWorkerConfig
  -> Map AtomId Atom
  -> MorphologyData
  -> Map Text (S.Set Text)
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> IO ManagedWorker
spawnAutonomousWorkerWithTopicAtoms cfg store morph topicAtoms queue updateQ =
  spawnAutonomousWorkerWithTopicAtomsAndPredicates
    cfg store morph topicAtoms M.empty queue updateQ

spawnAutonomousWorkerWithTopicAtomsAndPredicates
  :: AutonomousWorkerConfig
  -> Map AtomId Atom
  -> MorphologyData
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> IO ManagedWorker
spawnAutonomousWorkerWithTopicAtomsAndPredicates cfg store morph topicAtoms basePredicates queue updateQ =
  spawnAutonomousWorkerWithTransportAndTopicAtomsAndPredicates
    cfg buildTransportFromEnv store morph topicAtoms basePredicates queue updateQ

-- | Variant of 'spawnAutonomousWorker' with an injected transport builder.
-- Runtime wiring supplies 'buildTransportFromEnv'; tests can use a
-- deterministic mock without touching process-wide environment state.
spawnAutonomousWorkerWithTransport
  :: AutonomousWorkerConfig
  -> IO LLMTransport
  -> Map AtomId Atom
  -> MorphologyData
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> IO ManagedWorker
spawnAutonomousWorkerWithTransport cfg buildTransport store morph queue updateQ =
  spawnAutonomousWorkerWithTransportAndTopicAtoms
    cfg buildTransport store morph (buildTopicAtomsMap (buildLemmaMap morph)) queue updateQ

spawnAutonomousWorkerWithTransportAndTopicAtoms
  :: AutonomousWorkerConfig
  -> IO LLMTransport
  -> Map AtomId Atom
  -> MorphologyData
  -> Map Text (S.Set Text)
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> IO ManagedWorker
spawnAutonomousWorkerWithTransportAndTopicAtoms cfg buildTransport store morph topicAtoms queue updateQ = do
  spawnAutonomousWorkerWithTransportAndTopicAtomsAndPredicates
    cfg buildTransport store morph topicAtoms M.empty queue updateQ

spawnAutonomousWorkerWithTransportAndTopicAtomsAndPredicates
  :: AutonomousWorkerConfig
  -> IO LLMTransport
  -> Map AtomId Atom
  -> MorphologyData
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> IO ManagedWorker
spawnAutonomousWorkerWithTransportAndTopicAtomsAndPredicates cfg buildTransport store morph topicAtoms basePredicates queue updateQ = do
  qsRef <- newIORef =<< newQuotaState <$> getCurrentTime
  spawnManagedWorker . forever $ do
    when (awcMode cfg == FullAutonomous) (refillPersistentQueue queue)
    broadReadyProcessed <-
      if awcEnabled cfg && awcMode cfg == FullAutonomous
        then dispatchReadyBroad queue updateQ
        else pure False
    corroborationProcessed <-
      if broadReadyProcessed
        then pure False
        else processCorroborationBatch cfg buildTransport qsRef store morph queue updateQ
    if broadReadyProcessed || corroborationProcessed
      then pure ()
      else if not (awcEnabled cfg)
      then threadDelay (60 * 1000 * 1000)  -- sleep 60s when disabled
      else if awcMode cfg /= FullAutonomous
      then threadDelay (5 * 1000 * 1000)
      else do
        drainResult <- try (drainLearningQueue queue)
        case drainResult of
          Left (e :: SomeException) -> do
            rethrowAsync e
            hPutStrLn stderr $ "[autonomous] drain error: " <> show e
            threadDelay (10 * 1000 * 1000)  -- back off on error
          Right [] -> threadDelay (5 * 1000 * 1000)  -- idle
          Right (task:pendingTasks) -> do
            -- Process one task per iteration to bound LLM spend, but preserve
            -- the rest of the atomically drained batch for later iterations.
            -- These jobs already exist in SQLite, so durable dedup must not
            -- reject their in-memory requeue as duplicates.
            mapM_ (requeueExistingTask queue) pendingTasks
            processResult <- try
              (processOneTask cfg buildTransport store morph topicAtoms basePredicates qsRef queue updateQ task)
              :: IO (Either SomeException ())
            case processResult of
              Right () -> pure ()
              Left err -> do
                rethrowAsync err
                -- A transient persistence failure must not terminate the
                -- autonomous worker.  The durable lease/retry state is
                -- repaired best-effort; the next loop keeps draining work.
                hPutStrLn stderr $ "[autonomous] task failure for '"
                  <> T.unpack (ltTopic task) <> "': " <> show err
                -- A fenced provider/apply path owns durable repair. If the
                -- exception happened before claim, the row remains runnable;
                -- if after claim, lease expiry permits a bounded retry.
                pure ()

-- | Recover broad responses without provider access. Payload decode is strict
-- and bounded by JobQueue; malformed envelopes are fenced to failed.
dispatchReadyBroad :: LearningQueue -> TQueue NetworkUpdateEvent -> IO Bool
dispatchReadyBroad queue updateQ = case lqPersistence queue of
  Nothing -> pure False
  Just db -> mask $ \restore -> do
    ready <- claimLearningReadyPayloadsForSession db
      (maybe "autonomous-default" id (lqSessionId queue)) (lqCapacity queue) 120
    restore (forM_ ready $ \item ->
        case eitherDecodeStrict (TE.encodeUtf8 (lrpPayload item)) of
          Left _ -> void (rejectLearningReadyPayload db item "ready_payload_decode_failed")
          Right (BroadReadyEnvelope events)
            | null events -> void (rejectLearningReadyPayload db item "ready_payload_empty")
            | length events > maxDurableBroadEvents ->
                void (rejectLearningReadyPayload db item "ready_payload_event_limit_exceeded")
            | any ((/= lrpRequestId item) . nueRequestId) events ->
                void (rejectLearningReadyPayload db item "ready_payload_request_mismatch")
            | otherwise -> atomically (mapM_ (writeTQueue updateQ . withApplyToken item) events))
      `catch` \(err :: SomeException) ->
        releaseLearningReadyPayloads db ready `finally` throwIO err
    pure (not (null ready))
  where
    withApplyToken item event = event { nueApplyToken = Just (lrpApplyToken item) }

-- | Dispatch independent confirmation only when a durable batch of three
-- qualified hypotheses exists. A confirmation response can carry exactly the
-- leased canonical shape (or its conflict); all other provider output is
-- terminally rejected before it reaches the graph queue.
processCorroborationBatch
  :: AutonomousWorkerConfig
  -> IO LLMTransport
  -> IORef QuotaState
  -> Map AtomId Atom
  -> MorphologyData
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> IO Bool
processCorroborationBatch cfg buildTransport qsRef _store _morph queue updateQ
  | not (awcEnabled cfg) = pure False
  | otherwise = case lqPersistence queue of
      Nothing -> pure False
      Just db -> do
        readyProcessed <- dispatchReadyCorroboration db queue updateQ
        if readyProcessed
          then pure True
          else mask $ \restore -> do
            tasks <- claimCorroborationBatchForSession db (lqSessionId queue) 3 3
            restore (processClaimedCorroborationTasks cfg buildTransport qsRef queue updateQ db tasks)
              `catch` repairCancelledCorroboration db tasks

dispatchReadyCorroboration :: QxFx0DB -> LearningQueue -> TQueue NetworkUpdateEvent -> IO Bool
dispatchReadyCorroboration db queue updateQ = mask $ \restore -> do
  ready <- loadCorroborationResponseReadyForSession db (lqSessionId queue) 3
  restore (mapM_ (enqueueReadyCorroboration db updateQ) ready)
    `catch` \(err :: SomeException) ->
      releaseCorroborationReadyResponses db ready `finally` throwIO err
  pure (not (null ready))

processClaimedCorroborationTasks
  :: AutonomousWorkerConfig
  -> IO LLMTransport
  -> IORef QuotaState
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> QxFx0DB
  -> [CorroborationTask]
  -> IO Bool
processClaimedCorroborationTasks cfg buildTransport qsRef queue updateQ db tasks
  | null tasks = pure False
  | otherwise = do
      now <- getCurrentTime
      let estimatedTokens = foldl saturatingAdd 0
            [ saturatingAdd
                (max 1 (BS8.length (TE.encodeUtf8 (buildCorroborationPrompt
                  (ctTopic task) (ctEdgeFrom task) (ctRelationType task) (ctEdgeTo task)))))
                (max llmMaxCompletionTokens (awcReservedCompletionTokens cfg))
            | task <- tasks
            ]
      transportResult <- try buildTransport
      case transportResult of
        Left (err :: SomeException) -> do
          rethrowAsync err
          hPutStrLn stderr $ "[autonomous] corroboration transport error: " <> show err
          releaseCorroborationBatch db tasks
          threadDelay (fromIntegral (max 1 (awcHourResetDelaySec cfg)) * 1000 * 1000)
          pure True
        Right transport -> flip finally (closeOwnedTransport transport) $ do
          let retryBudget = transportMaxAttempts transport
          reserved <- reserveQuota cfg qsRef queue now
            (saturatingProduct (length tasks) retryBudget)
            (saturatingProduct estimatedTokens retryBudget)
          if not reserved
            then do
              releaseCorroborationBatch db tasks
              -- Do not spend a smaller residual quota on broad discovery while
              -- a controlled confirmation gate waits.
              threadDelay (fromIntegral (max 1 (awcHourResetDelaySec cfg)) * 1000 * 1000)
              pure True
            else do
              forM_ tasks $ \task -> do
                processed <- try (processCorroborationTask cfg transport db task)
                  :: IO (Either SomeException ())
                case processed of
                  Right () -> pure ()
                  Left err -> do
                    rethrowAsync err
                    hPutStrLn stderr $ "[autonomous] corroboration task failure for "
                      <> show (ctId task) <> ": " <> show err
                    markCorroborationTaskFailed db task True 60 "worker_exception"
              newlyReady <- loadCorroborationResponseReadyForSession db (lqSessionId queue) 3
              mapM_ (enqueueReadyCorroboration db updateQ) newlyReady
              pure True

repairCancelledCorroboration :: QxFx0DB -> [CorroborationTask] -> SomeException -> IO a
repairCancelledCorroboration db tasks err =
  case fromException err :: Maybe AsyncException of
    Nothing -> throwIO err
    Just _ -> do
      forM_ tasks $ \task ->
        markCorroborationTaskFailed db task True 1 "worker_cancelled"
          `catch` \(_ :: SomeException) -> pure ()
      throwIO err

processCorroborationTask :: AutonomousWorkerConfig -> LLMTransport -> QxFx0DB -> CorroborationTask -> IO ()
processCorroborationTask cfg transport db task = do
  let prompt = buildCorroborationPrompt
        (ctTopic task) (ctEdgeFrom task) (ctRelationType task) (ctEdgeTo task)
      promptHash = sha256Hex (TE.encodeUtf8 prompt)
      requestId = maybe ("corroborate-" <> T.pack (show (ctId task))) id (ctConfirmationRequestId task)
      tool = ExternalTool
        { etName = "candidate_targeted_corroboration"
        , etDomain = DomainGeneral
        , etReliability = 0.5
        , etValidatable = False
        }
  result <- boundedProviderQuery (awcProviderTimeoutMs cfg) transport tool NeedKeywordEnrichment prompt
  case result of
    Left err -> markCorroborationTaskFailed db task (isRetryableError err) 60 (renderExternalQueryError err)
    Right response -> do
      let responseBody = if T.null (eqrStructured response) then eqrRawBody response else eqrStructured response
          responseHash = sha256Hex (TE.encodeUtf8 responseBody)
      mask_ $ recordCorroborationResponseReady db (ctId task) requestId promptHash responseHash (transportModel transport) responseBody

enqueueReadyCorroboration :: QxFx0DB -> TQueue NetworkUpdateEvent -> CorroborationReadyResponse -> IO ()
enqueueReadyCorroboration db updateQ ready = do
  let task = crrTask ready
      requestId = maybe ("corroborate-" <> T.pack (show (ctId task))) id (ctConfirmationRequestId task)
  if crrResponseHash ready == ctSourceResponseHash task
    then markCorroborationTaskTerminal db task (readyLeaseToken ready) CtsRejected "source_response_hash_reused"
    else do
      now <- getCurrentTime
      case confirmationOutcome task (crrResponseBody ready) of
        ConfirmationExact edge -> atomically (writeTQueue updateQ
          ((confirmationEvent now task requestId (crrPromptHash ready) (crrResponseHash ready) (crrModel ready) edge "corroboration_confirmation")
            { nueApplyToken = crrApplyToken ready }))
        ConfirmationConflict edge -> atomically (writeTQueue updateQ
          ((confirmationEvent now task requestId (crrPromptHash ready) (crrResponseHash ready) (crrModel ready) edge "corroboration_conflict")
            { nueApplyToken = crrApplyToken ready }))
        ConfirmationRejected reason -> markCorroborationTaskTerminal db task (readyLeaseToken ready) CtsRejected reason

confirmationLeaseToken :: CorroborationTask -> Text
confirmationLeaseToken task = maybe
  ("corroborate-" <> T.pack (show (ctId task))) id (ctConfirmationRequestId task)

readyLeaseToken :: CorroborationReadyResponse -> Text
readyLeaseToken ready = maybe (confirmationLeaseToken (crrTask ready)) id (crrApplyToken ready)

data ConfirmationOutcome
  = ConfirmationExact SemanticEdge
  | ConfirmationConflict SemanticEdge
  | ConfirmationRejected Text

confirmationOutcome :: CorroborationTask -> Text -> ConfirmationOutcome
confirmationOutcome task responseBody =
  case parseStructuredLLMRelations (ctTopic task) responseBody of
    [relation]
      | relationMatchesEndpoints relation ->
          let parsedType = relationTypeName (Just (relType relation))
              edge = confirmationEdge task (relType relation) (relVerbText relation)
          in if parsedType == ctRelationType task
               then ConfirmationExact edge
               else ConfirmationConflict edge
    [] -> ConfirmationRejected "confirmation_not_provided"
    _ -> ConfirmationRejected "confirmation_contains_free_or_multiple_triples"
  where
    relationMatchesEndpoints relation =
      let AtomId from = relFrom relation
          AtomId to = relTo relation
      in T.toLower from == T.toLower (ctEdgeFrom task)
        && T.toLower to == T.toLower (ctEdgeTo task)

confirmationEdge :: CorroborationTask -> RelationType -> Maybe Text -> SemanticEdge
confirmationEdge task relation verb = SemanticEdge
  { seFrom = ctEdgeFrom task
  , seTo = ctEdgeTo task
  , seWeight = 0.6
  , seCoOccurrence = 1
  , seSource = ExplicitEdge
  , seRelationType = Just relation
  , seVerb = verb
  , seRationale = Nothing
  , seCounter = Nothing
  , seSynthesis = Nothing
  , seConfidence = 0.6
  , seProvenance = ProvenanceRuntimeLLM
  , seDomain = Nothing
  , seTemporalScope = Nothing
  , seNamespace = case ctNamespace task of
      "global" -> Just NamespaceGlobal
      "user_local" -> Just NamespaceUserLocal
      _ -> Just NamespaceSessionLocal
  , seLineage = Nothing
  }

confirmationEvent :: UTCTime -> CorroborationTask -> Text -> Text -> Text -> Text -> SemanticEdge -> Text -> NetworkUpdateEvent
confirmationEvent now task requestId promptHash responseHash model edge decision = NetworkUpdateEvent
  { nueTopic = ctTopic task
  , nueEdges = [edge]
  , nueTimestamp = now
  , nueRequestId = requestId
  , nuePromptHash = Just promptHash
  , nueResponseHash = Just responseHash
  , nueModel = Just model
  , nueParserDecision = Just "structured_confirmation_parser:accepted"
  , nueAdmissionDecision = Just decision
  , nueEvidenceSource = Just "candidate_targeted_corroboration"
  , nueCompetitiveAudit = Nothing
  , nueCorroborationPriority = Nothing
  , nueCorroborationTaskId = Just (ctId task)
  , nueApplyToken = Nothing
  }

-- | Process a single learning task with quota enforcement.
processOneTask
  :: AutonomousWorkerConfig
  -> IO LLMTransport
  -> Map AtomId Atom
  -> MorphologyData
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> IORef QuotaState
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> LearningTask
  -> IO ()
processOneTask cfg buildTransport store morph topicAtoms basePredicates qsRef queue updateQ task = do
  now <- getCurrentTime
  let normalizedTopic = T.toLower (T.strip (ltTopic task))
      baseForTopic = M.findWithDefault [] normalizedTopic basePredicates
      baseWinner = basePrimaryForTopic normalizedTopic topicAtoms baseForTopic (buildLemmaMap morph)
      queryText = buildGapAwareDiscoveryPrompt
         (ltTopic task)
         (selectCandidateTopics topicAtoms (ltTopic task))
         (maybe [] pure baseWinner)
         acquisitionRelationSlots
      estimatedTokens = saturatingAdd
        (max 1 (BS8.length (TE.encodeUtf8 queryText)))
        (max llmMaxCompletionTokens (awcReservedCompletionTokens cfg))
  -- Claim while masked, then become interruptible only after the cancellation
  -- repair handler owns the lease. This closes the post-claim teardown gap.
  mask $ \restore -> do
    mClaim <- case lqPersistence queue of
      Nothing -> pure Nothing
      Just db -> claimLearningJob db (ltRequestId task) 120
    restore (processClaimedTask cfg buildTransport store morph topicAtoms basePredicates qsRef queue updateQ task now normalizedTopic queryText estimatedTokens mClaim)
      `catch` repairCancelledClaim queue mClaim

processClaimedTask
  :: AutonomousWorkerConfig
  -> IO LLMTransport
  -> Map AtomId Atom
  -> MorphologyData
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> IORef QuotaState
  -> LearningQueue
  -> TQueue NetworkUpdateEvent
  -> LearningTask
  -> UTCTime
  -> Text
  -> Text
  -> Int
  -> Maybe LearningJobClaim
  -> IO ()
processClaimedTask cfg buildTransport store morph topicAtoms basePredicates qsRef queue updateQ task now normalizedTopic queryText estimatedTokens mClaim = do
  let claimed = case lqPersistence queue of
        Nothing -> True
        Just _ -> maybe False (const True) mClaim
  when (claimed && not (trustedAutonomousTopic normalizedTopic)) $
    rejectClaimWithReason queue mClaim "topic_not_trusted_for_autonomous_acquisition"
  when (claimed && trustedAutonomousTopic normalizedTopic) $ do
    transportResult <- try buildTransport
    case transportResult of
      Left (e :: SomeException) -> do
        rethrowAsync e
        hPutStrLn stderr $ "[autonomous] transport error: " <> show e
        failClaim queue mClaim False EqeEmptyResponse
      Right transport -> flip finally (closeOwnedTransport transport) $ do
        let retryBudget = transportMaxAttempts transport
        reserved <- reserveQuota cfg qsRef queue now retryBudget
          (saturatingProduct estimatedTokens retryBudget)
        if not reserved
          then do
            case (lqPersistence queue, mClaim) of
              (Just db, Just claim) -> void (releaseLearningJobClaim db claim)
              _ -> pure ()
            requeueExistingTask queue task
            threadDelay (fromIntegral (max 1 (awcHourResetDelaySec cfg)) * 1000 * 1000)
          else do
            let tool = ExternalTool
                  { etName        = "autonomous_learning"
                  , etDomain      = DomainGeneral
                  , etReliability = 0.5
                  , etValidatable = False
                  }
                need = NeedKeywordEnrichment
            queried <- try (boundedProviderQuery (awcProviderTimeoutMs cfg) transport tool need queryText)
              :: IO (Either SomeException (Either ExternalQueryError ExternalQueryResponse))
            case queried of
              Left e -> do
                rethrowAsync e
                hPutStrLn stderr $ "[autonomous] query error: " <> show e
                failClaim queue mClaim True EqeEmptyResponse
              Right (Left err) -> do
                hPutStrLn stderr $ "[autonomous] LLM error for topic '" <> T.unpack (ltTopic task) <> "': " <> show err
                failClaim queue mClaim (isRetryableError err) err
              Right (Right resp) -> do
                let model = transportModel transport
                    responseBody = if T.null (eqrStructured resp) then eqrRawBody resp else eqrStructured resp
                    promptHash = sha256Hex (TE.encodeUtf8 queryText)
                    responseHash = sha256Hex (TE.encodeUtf8 responseBody)
                    languageRejected = responseViolatesTopicLanguage (ltTopic task) responseBody
                    net = autonomousApplyLLMResponseForTopic store morph (ltTopic task) resp
                    edges = M.elems (snEdges net)
                    truncated = take (min maxDurableBroadEvents (awcMaxEdgesPerBatch cfg)) edges
                    (preflightAccepted, preflightRejected) =
                      if M.null basePredicates
                        then (truncated, [])
                        else partitionAcquisitionPreflight
                          (ltTopic task) topicAtoms basePredicates (buildLemmaMap morph) truncated
                    competitiveAudits = M.fromList
                      [ ((seFrom edge, seTo edge), evaluateCompetitiveUtility
                          (ltTopic task) topicAtoms basePredicates (buildLemmaMap morph) edge)
                      | edge <- truncated
                      ]
                    preflightDetails = M.map competitiveUtilityDetail competitiveAudits
                if languageRejected
                  then persistLanguageRejected queue mClaim task now model promptHash responseHash responseBody
                  else if null preflightAccepted
                  then persistPreflightRejected queue mClaim task now model promptHash responseHash responseBody truncated preflightRejected preflightDetails
                   else persistPreflightAccepted queue mClaim task now model promptHash responseHash responseBody preflightAccepted preflightRejected preflightDetails competitiveAudits updateQ

repairCancelledClaim :: LearningQueue -> Maybe LearningJobClaim -> SomeException -> IO a
repairCancelledClaim queue mClaim err =
  case fromException err :: Maybe AsyncException of
    Nothing -> throwIO err
    Just _ -> do
      case (lqPersistence queue, mClaim) of
        (Just db, Just claim) ->
          void (markLearningJobClaimFailed db claim True 1 "worker_cancelled")
        _ -> pure ()
      throwIO err

boundedProviderQuery
  :: Int
  -> LLMTransport
  -> ExternalTool
  -> LearningNeed
  -> Text
  -> IO (Either ExternalQueryError ExternalQueryResponse)
boundedProviderQuery timeoutMs transport tool need query = do
  result <- timeout (max 1 timeoutMs * 1000)
    (queryExternalTool transport tool need query)
  pure (maybe (Left (EqeTimeout "provider_wall_clock_timeout")) id result)

failClaim :: LearningQueue -> Maybe LearningJobClaim -> Bool -> ExternalQueryError -> IO ()
failClaim queue mClaim retryable err =
  case (lqPersistence queue, mClaim) of
    (Just db, Just claim) -> void $ markLearningJobClaimFailed db claim retryable 60 (renderExternalQueryError err)
    _ -> pure ()

rejectClaimWithReason :: LearningQueue -> Maybe LearningJobClaim -> Text -> IO ()
rejectClaimWithReason queue mClaim reason =
  case (lqPersistence queue, mClaim) of
    (Just db, Just claim) -> void (markLearningJobClaimFailed db claim False 1 reason)
    _ -> pure ()

rethrowAsync :: SomeException -> IO ()
rethrowAsync err = case fromException err :: Maybe AsyncException of
  Just async -> throwIO async
  Nothing -> pure ()

persistPreflightRejected
  :: LearningQueue -> Maybe LearningJobClaim -> LearningTask -> UTCTime -> Text -> Text -> Text -> Text -> [SemanticEdge] -> [SemanticEdge] -> Map (Text, Text) Text -> IO ()
persistPreflightRejected queue mClaim task now model promptHash responseHash responseBody truncated rejected preflightDetails = do
  let rejectedEvent = NetworkUpdateEvent
        { nueTopic = ltTopic task
        , nueEdges = truncated
        , nueTimestamp = now
        , nueRequestId = ltRequestId task
        , nuePromptHash = Just promptHash
        , nueResponseHash = Just responseHash
        , nueModel = Just model
        , nueParserDecision = Just "structured_relation_parser:accepted"
        , nueAdmissionDecision = Just "selector_preflight_rejected"
        , nueEvidenceSource = Just "autonomous_external_llm"
        , nueCompetitiveAudit = Nothing
        , nueCorroborationPriority = Nothing
        , nueCorroborationTaskId = Nothing
        , nueApplyToken = Nothing
        }
  persistWorkerResult queue mClaim task promptHash responseHash responseBody
    (preflightRejectionEvents rejectedEvent rejected preflightDetails)
    Nothing
    (Just (False, 0, "selector_preflight_no_positive_candidates", Just (terminalRejectionCooldownSeconds, "selector_preflight_rejected")))

persistLanguageRejected
  :: LearningQueue -> Maybe LearningJobClaim -> LearningTask -> UTCTime -> Text -> Text -> Text -> Text -> IO ()
persistLanguageRejected queue mClaim task now model promptHash responseHash responseBody = do
  let event = LearningEvent
        { leTimestamp = now
        , leSessionId = lqSessionId queue
        , leTurnSeq = Nothing
        , leRequestId = ltRequestId task
        , leTopic = ltTopic task
        , leKind = EdgeRejected
        , leSource = LesWorker
        , leEdgeFrom = Nothing
        , leEdgeTo = Nothing
        , leProvenance = Nothing
        , leConfidence = Nothing
        , leCoOccurrence = Nothing
        , leReason = Just "provider_language_contract_rejected"
        , lePromptHash = Just promptHash
        , leResponseHash = Just responseHash
        , leModel = Just model
        , leParserDecision = Just "structured_relation_parser:language_rejected"
        , leAdmissionDecision = Just "language_rejected"
        , leEvidenceSource = Just "autonomous_external_llm"
        , leEdgeNamespace = Nothing
        , leEdgeOwner = lqSessionId queue
        }
  persistWorkerResult queue mClaim task promptHash responseHash responseBody [event] Nothing
    (Just (False, 0, "provider_language_contract_rejected", Just (terminalRejectionCooldownSeconds, "language_rejected")))

terminalRejectionCooldownSeconds :: Int
terminalRejectionCooldownSeconds = 3600

persistPreflightAccepted
  :: LearningQueue -> Maybe LearningJobClaim -> LearningTask -> UTCTime -> Text -> Text -> Text -> Text -> [SemanticEdge] -> [SemanticEdge] -> Map (Text, Text) Text -> Map (Text, Text) CompetitiveUtilityAudit -> TQueue NetworkUpdateEvent -> IO ()
persistPreflightAccepted queue mClaim task now model promptHash responseHash responseBody accepted rejected preflightDetails competitiveAudits updateQ = do
  let eventFor edge =
        let auditResult = M.lookup (seFrom edge, seTo edge) competitiveAudits
            audit = competitiveUtilityDetail <$> auditResult
            qualified = maybe False cuaQualifiedForCorroboration auditResult
        in NetworkUpdateEvent
          { nueTopic = ltTopic task
          , nueEdges = [edge]
          , nueTimestamp = now
          , nueRequestId = ltRequestId task
          , nuePromptHash = Just promptHash
          , nueResponseHash = Just responseHash
          , nueModel = Just model
          , nueParserDecision = Just "structured_relation_parser:accepted"
          , nueAdmissionDecision = Just (if qualified then "worker_candidate_qualified" else "worker_candidate_admitted")
          , nueEvidenceSource = Just "autonomous_external_llm"
          , nueCompetitiveAudit = if qualified then audit else Nothing
          , nueCorroborationPriority = if qualified then corroborationPriority <$> auditResult else Nothing
          , nueCorroborationTaskId = Nothing
          , nueApplyToken = Nothing
          }
      events = map eventFor accepted
  let rejectionEvents = maybe []
        (\event -> preflightRejectionEvents event rejected preflightDetails)
        (listToMaybe events)
  persistWorkerResult queue mClaim task promptHash responseHash responseBody
    (concatMap (proposalEventsWithDetails preflightDetails) events ++ rejectionEvents)
    (Just events)
    Nothing
  case lqPersistence queue of
    Nothing -> atomically (mapM_ (writeTQueue updateQ) events)
    Just _ -> void (dispatchReadyBroad queue updateQ)

partitionAcquisitionPreflight
  :: Text
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> Map Text Text
  -> [SemanticEdge]
  -> ([SemanticEdge], [SemanticEdge])
partitionAcquisitionPreflight topic topicAtoms basePredicates lemmaMap = foldr step ([], [])
  where
    normalizedTopic = T.toLower (T.strip topic)
    step edge (accepted, rejected)
      | acquisitionPreflightPass normalizedTopic topicAtoms basePredicates lemmaMap edge = (edge : accepted, rejected)
      | otherwise = (accepted, edge : rejected)

acquisitionPreflightPass
  :: Text
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> Map Text Text
  -> SemanticEdge
  -> Bool
acquisitionPreflightPass topic topicAtoms basePredicates lemmaMap edge =
  let relation = relationTypeName (seRelationType edge)
      candidate = PromotionCandidate
        { pcCandidateId = "preflight"
        , pcSnapshotId = "preflight"
        , pcTopic = topic
        , pcSubject = seFrom edge
        , pcRelationType = relation
        , pcObject = seTo edge
        , pcRenderedRu = seFrom edge <> " " <> relation <> " " <> seTo edge
        , pcConfidence = seConfidence edge
        , pcSupportCount = 1
        , pcStatus = "preflight"
        }
      info = evaluateCandidateInformativeness candidate
    in trustedAutonomousTopic topic
       && T.toLower (T.strip (seFrom edge)) == topic
       && sameAlphabeticScript (seFrom edge) (seTo edge)
       && relation `elem` acquisitionRelationSlots
       && irPassed info

sameAlphabeticScript :: Text -> Text -> Bool
sameAlphabeticScript left right =
  case (textScript left, textScript right) of
    (Just leftScript, Just rightScript) -> leftScript == rightScript
    _ -> False
  where
    textScript text =
      let hasLatin = T.any (\c -> isAscii c && isAlpha c) text
          hasCyrillic = T.any (\c -> c >= '\x0400' && c <= '\x04ff') text
      in case (hasLatin, hasCyrillic) of
           (True, False) -> Just (0 :: Int)
           (False, True) -> Just 1
           _ -> Nothing

-- | Evaluate candidate usefulness against the exact-topic base selector before
-- spending a future independent corroboration request. This is observational:
-- first-admission safety is decided by 'acquisitionPreflightPass' above.
evaluateCompetitiveUtility
  :: Text
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> Map Text Text
  -> SemanticEdge
  -> CompetitiveUtilityAudit
evaluateCompetitiveUtility topic topicAtoms basePredicates lemmaMap edge =
  let relation = relationTypeName (seRelationType edge)
      candidateSurface = seFrom edge <> " " <> relation <> " " <> seTo edge
      baseTopicPredicates = M.findWithDefault [] topic basePredicates
      candidatePredicate = SemanticPredicate RoleProperty candidateSurface "" (seFrom edge)
        (Just (CanonicalPredicateRelation (seFrom edge) relation (seTo edge))) Nothing Nothing Nothing
      baseNetwork = seedFromCorpus lemmaMap
      transientNetwork = withTransientCandidate baseNetwork edge relation
      baseSelector = buildContentSelector
        (buildSemanticSpace baseNetwork topicAtoms)
        topicAtoms (M.singleton topic baseTopicPredicates) lemmaMap Nothing
      transientAtoms = M.insertWith S.union topic
        (S.fromList [seFrom edge, relation, seTo edge]) topicAtoms
      transientSelector = buildContentSelector
        (buildSemanticSpace transientNetwork transientAtoms)
        transientAtoms (M.singleton topic (baseTopicPredicates ++ [candidatePredicate])) lemmaMap Nothing
      fields = preflightPrototypeFields
      fieldAudits =
        [ competitiveFieldAudit baseSelector transientSelector baseNetwork transientNetwork field topic candidateSurface
        | field <- fields
        ]
      basePrimary = listToMaybe [surface | (Just surface, _, _, _) <- fieldAudits]
      transientPrimary = listToMaybe [surface | (_, Just surface, _, _) <- fieldAudits]
      candidateRoles = [role | (_, _, role, _) <- fieldAudits, role /= "none"]
      candidateRole = case candidateRoles of
        [] -> "none"
        role : _ -> role
      candidateDiagnostics = [diagnostic | (_, _, _, Just diagnostic) <- fieldAudits]
      candidateScore = maxMaybe (mapMaybe sdScore candidateDiagnostics)
      candidateMarginal = maxMaybe (mapMaybe sdMarginalSemanticGain candidateDiagnostics)
      basePrimaryPreserved = all preservesPrimary fieldAudits
      (contribution, contributionNew) = contributionAudit baseTopicPredicates candidatePredicate
      candidateQualifies = any qualifiesField fieldAudits
      qualified = candidateQualifies && basePrimaryPreserved && contributionNew
  in CompetitiveUtilityAudit
       basePrimary transientPrimary candidateRole candidateScore candidateMarginal
       basePrimaryPreserved contribution contributionNew qualified (length fields)
  where
    preservesPrimary (Nothing, _, _, _) = True
    preservesPrimary (Just base, Just transient, _, _) = base == transient
    preservesPrimary (Just _, Nothing, _, _) = False
    expectedCandidateSurface = seFrom edge <> " " <> relationTypeName (seRelationType edge) <> " " <> seTo edge
    qualifiesField (Nothing, Just transient, "primary", _) = transient == expectedCandidateSurface
    qualifiesField (Just _, _, "secondary", Just diagnostic) =
      maybe False (>= competitiveMarginalGainThreshold) (sdMarginalSemanticGain diagnostic)
    qualifiesField _ = False

-- | Priority only. A scheduler that later gains targeted corroboration tasks
-- can consume this value without changing first-admission semantics.
corroborationPriority :: CompetitiveUtilityAudit -> Double
corroborationPriority audit
  | not (cuaQualifiedForCorroboration audit) = 0.0
  | otherwise = 1.0
      + maybe 0.0 id (cuaCandidateScore audit)
      + maybe 0.0 id (cuaCandidateMarginalGain audit)

competitiveUtilityDetail :: CompetitiveUtilityAudit -> Text
competitiveUtilityDetail audit =
  "competitive_utility_v1;base_primary=" <> maybe "none" id (cuaBasePrimary audit)
    <> ";transient_primary=" <> maybe "none" id (cuaTransientPrimary audit)
    <> ";candidate_role=" <> cuaCandidateRole audit
    <> ";candidate_score=" <> showMaybe (cuaCandidateScore audit)
    <> ";candidate_marginal=" <> showMaybe (cuaCandidateMarginalGain audit)
    <> ";base_primary_preserved=" <> boolText (cuaBasePrimaryPreserved audit)
    <> ";contribution=" <> cuaContribution audit
    <> ";contribution_new=" <> boolText (cuaContributionNew audit)
    <> ";qualified_for_corroboration=" <> boolText (cuaQualifiedForCorroboration audit)
    <> ";prototype_fields=" <> T.pack (show (cuaPrototypeFields audit))
  where
    showMaybe Nothing = "none"
    showMaybe (Just value) = T.pack (show value)
    boolText True = "true"
    boolText False = "false"

type CompetitiveFieldAudit = (Maybe Text, Maybe Text, Text, Maybe SelectorDiagnostic)

competitiveFieldAudit
  :: ContentSelector
  -> ContentSelector
  -> SemanticNetwork
  -> SemanticNetwork
  -> Field
  -> Text
  -> Text
  -> CompetitiveFieldAudit
competitiveFieldAudit baseSelector transientSelector baseNetwork transientNetwork field topic candidateSurface =
  let baseActivated = activateTopicWithField field
        (M.findWithDefault S.empty topic (csTopicAtoms baseSelector)) baseNetwork
      transientActivated = activateTopicWithField field
        (M.findWithDefault S.empty topic (csTopicAtoms transientSelector)) transientNetwork
      (baseSelected, _) = selectPredicatesWithDiagnostics baseSelector field topic (Just baseActivated)
      (transientSelected, transientDiagnostics) = selectPredicatesWithDiagnostics transientSelector field topic (Just transientActivated)
      basePrimary = selectedPrimarySurface baseSelected
      transientPrimary = selectedPrimarySurface transientSelected
      mCandidateDiagnostic = listToMaybe
        [ diagnostic
        | diagnostic <- transientDiagnostics
        , sdPredicateSurface diagnostic == Just candidateSurface
        ]
      role = case mCandidateDiagnostic of
        Just diagnostic
          | sdSelected diagnostic && transientPrimary == Just candidateSurface -> "primary"
          | sdSelected diagnostic -> "secondary"
        _ -> "none"
  in (basePrimary, transientPrimary, role, mCandidateDiagnostic)

selectedPrimarySurface :: [SelectedPredicate] -> Maybe Text
selectedPrimarySurface selections = do
  selection <- listToMaybe selections
  predicate <- listToMaybe (spPredicates selection)
  pure (spRu predicate)

preflightPrototypeFields :: [Field]
preflightPrototypeFields =
  [ emptyField { fieldResonance = Resonance 0.2 }
  , emptyField { fieldResonance = Resonance 0.5 }
  , emptyField { fieldResonance = Resonance 0.8 }
  ]

withTransientCandidate :: SemanticNetwork -> SemanticEdge -> Text -> SemanticNetwork
withTransientCandidate baseNetwork edge relation =
  let candidateNodes = S.fromList [seFrom edge, relation, seTo edge]
  in baseNetwork
      { snNodes = S.union (snNodes baseNetwork) candidateNodes
      , snEdges = M.insert (seFrom edge, seTo edge)
          (semanticEdge (seFrom edge) (seTo edge) (seWeight edge) (seCoOccurrence edge) (seSource edge))
          (snEdges baseNetwork)
      }

contributionAudit :: [SemanticPredicate] -> SemanticPredicate -> (Text, Bool)
contributionAudit basePredicates candidate =
  let candidateRelation = spCanonicalRelation candidate
      baseRelations = mapMaybe spCanonicalRelation basePredicates
      duplicate = maybe False (`elem` baseRelations) candidateRelation
      candidateObject = maybe "" cprObject candidateRelation
      objectMentioned = any (T.isInfixOf (T.toLower candidateObject) . T.toLower . spRu) basePredicates
      relation = maybe "" cprRelation candidateRelation
      constraining = relation `elem` acquisitionRelationSlots
  in if duplicate
       then ("duplicate", False)
       else if constraining && not objectMentioned
         then ("new_constraint", True)
         else if not objectMentioned
           then ("new_relation", True)
           else ("no_new_contribution", False)

maxMaybe :: [Double] -> Maybe Double
maxMaybe [] = Nothing
maxMaybe values = Just (maximum values)

competitiveMarginalGainThreshold :: Double
competitiveMarginalGainThreshold = 0.5

basePrimaryForTopic
  :: Text
  -> Map Text (S.Set Text)
  -> [SemanticPredicate]
  -> Map Text Text
  -> Maybe Text
basePrimaryForTopic topic topicAtoms predicates lemmaMap =
  selectedPrimarySurface (fst (selectPredicatesWithDiagnostics selector promptField topic (Just activated)))
  where
    baseNetwork = seedFromCorpus lemmaMap
    selector = buildContentSelector (buildSemanticSpace baseNetwork topicAtoms)
      topicAtoms (M.singleton topic predicates) lemmaMap Nothing
    promptField = emptyField { fieldResonance = Resonance 0.8 }
    activated = activateTopicWithField promptField
      (M.findWithDefault S.empty topic topicAtoms) baseNetwork

selectorPreflightDiagnostic
  :: Text
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> Map Text Text
  -> SemanticEdge
  -> Maybe SelectorDiagnostic
selectorPreflightDiagnostic topic topicAtoms basePredicates lemmaMap edge =
  let relation = relationTypeName (seRelationType edge)
      candidateSurface = seFrom edge <> " " <> relation <> " " <> seTo edge
      topicPredicates = M.findWithDefault [] topic basePredicates
      candidatePredicate = SemanticPredicate RoleProperty candidateSurface "" (seFrom edge)
        (Just (CanonicalPredicateRelation (seFrom edge) relation (seTo edge))) Nothing Nothing Nothing
      predicateMap = M.insertWith (++) topic [candidatePredicate] (M.singleton topic topicPredicates)
      atomMap = M.insertWith S.union topic (S.fromList [seFrom edge, relation, seTo edge]) topicAtoms
      baseNetwork = seedFromCorpus lemmaMap
      candidateNodes = S.fromList [seFrom edge, relation, seTo edge]
      -- Transient network: the candidate edge is added to a /copy/ of the
      -- seeded network so that activation can spread across it.  No
      -- mutation reaches the runtime @ssSemanticNetwork@ — the copy is
      -- local to this preflight evaluation.
      transientNetwork = baseNetwork
        { snNodes = S.union (snNodes baseNetwork) candidateNodes
        , snEdges = M.insert (seFrom edge, seTo edge)
            (semanticEdge (seFrom edge) (seTo edge) (seWeight edge) (seCoOccurrence edge) (seSource edge))
            (snEdges baseNetwork)
        }
      selector = buildContentSelector (buildSemanticSpace transientNetwork atomMap)
        atomMap predicateMap lemmaMap Nothing
      topicAtomsForActivation = M.findWithDefault S.empty topic atomMap
      prototypeFields =
        [ emptyField { fieldResonance = Resonance 0.2 }
        , emptyField { fieldResonance = Resonance 0.5 }
        , emptyField { fieldResonance = Resonance 0.8 }
        ]
      diagnostics = concat
        [ let activatedNetwork = activateTopicWithField field topicAtomsForActivation transientNetwork
          in snd (selectPredicatesWithDiagnostics selector field topic (Just activatedNetwork))
        | field <- prototypeFields
        ]
  in listToMaybe
      [ diagnostic
      | diagnostic <- diagnostics
      , sdPredicateSurface diagnostic == Just candidateSurface
      ]

selectorPreflightDetail
  :: Text
  -> Map Text (S.Set Text)
  -> Map Text [SemanticPredicate]
  -> Map Text Text
  -> SemanticEdge
  -> Text
selectorPreflightDetail topic topicAtoms basePredicates lemmaMap edge =
  case selectorPreflightDiagnostic topic topicAtoms basePredicates lemmaMap edge of
    Nothing -> "selector_preflight;score=0;topic=0;field=0;activation=0;ontology=0;oov=unknown;marginal=unknown;fields=3"
    Just diagnostic ->
      "selector_preflight;score=" <> showMaybe (sdScore diagnostic)
        <> ";topic=" <> showMaybe (sdTopicRelevance diagnostic)
        <> ";field=" <> showMaybe (sdFieldAffinity diagnostic)
        <> ";activation=" <> showMaybe (sdActivationBonus diagnostic)
        <> ";ontology=" <> showMaybe (sdOntologyContribution diagnostic)
        <> ";oov=" <> showMaybeList (sdOovAtoms diagnostic)
        <> ";marginal=" <> showMaybe (sdMarginalSemanticGain diagnostic)
        <> ";reason=" <> sdReason diagnostic <> ";fields=3"
  where
    showMaybe Nothing = "unknown"
    showMaybe (Just value) = T.pack (show value)
    showMaybeList Nothing = "unknown"
    showMaybeList (Just values) = T.intercalate "," values

-- | Recompute decomposition for legacy selector-preflight rejection rows using
-- only persisted response bodies and local deterministic selector state.
auditHistoricalSelectorPreflight :: QxFx0DB -> IO Int
auditHistoricalSelectorPreflight db = do
  let store = atomStore
      morph = buildAtomMorphology store
      lemmaMap = buildLemmaMap morph
      topicAtoms = buildTopicAtomsMap lemmaMap
      basePredicates = M.map dcPredicates definitionCorpus
  withImmediateTransaction (qdbConn db) $ do
    rows <- loadHistoricalRejections (qdbConn db)
    forM_ rows $ \(eventId, topic, edgeFrom, edgeTo, responseBody) -> do
      let detail = historicalPreflightDetail topic edgeFrom edgeTo responseBody topicAtoms basePredicates lemmaMap
      updateHistoricalReason (qdbConn db) eventId ("selector_preflight_audit_v1;" <> detail)
    pure (length rows)
  where
    loadHistoricalRejections conn = do
      prepared <- NSQL.prepare conn
        "SELECT e.id, e.topic, e.edge_from, e.edge_to, r.response_body FROM learning_events e JOIN learning_responses r ON r.request_id = e.request_id WHERE e.reason = 'selector_preflight_rejected' OR e.reason LIKE 'selector_preflight_audit_v1;%' ORDER BY e.id"
      case prepared of
        Left err -> throwAutonomousPersistenceError err
        Right stmt -> collect stmt []

    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          eventId <- NSQL.columnInt64 stmt 0
          topic <- NSQL.columnText stmt 1
          edgeFrom <- NSQL.columnText stmt 2
          edgeTo <- NSQL.columnText stmt 3
          responseBody <- NSQL.columnTextLenient stmt 4
          collect stmt ((eventId, topic, edgeFrom, edgeTo, responseBody) : acc)

    updateHistoricalReason conn eventId reason = do
      prepared <- NSQL.prepare conn
        "UPDATE learning_events SET reason = ? WHERE id = ? AND (reason = 'selector_preflight_rejected' OR reason LIKE 'selector_preflight_audit_v1;%')"
      case prepared of
        Left err -> throwAutonomousPersistenceError err
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 reason
          _ <- NSQL.bindInt64 stmt 2 eventId
          _ <- NSQL.step stmt
          NSQL.finalize stmt

historicalPreflightDetail
  :: Text -> Text -> Text -> Text
  -> Map Text (S.Set Text) -> Map Text [SemanticPredicate] -> Map Text Text -> Text
historicalPreflightDetail topic edgeFrom edgeTo responseBody topicAtoms basePredicates lemmaMap =
  case chooseHistoricalRelation (parseStructuredLLMRelations topic responseBody) of
    Nothing -> "relation=unknown;score=unknown;field=unknown;activation=unknown;ontology=unknown;oov=unknown;marginal=unknown;fields=3"
    Just relation ->
      let edge = SemanticEdge
            { seFrom = edgeFrom
            , seTo = edgeTo
            , seWeight = 0.6
            , seCoOccurrence = 1
            , seSource = ExplicitEdge
            , seRelationType = Just (relType relation)
            , seVerb = relVerbText relation
            , seRationale = Nothing
            , seCounter = Nothing
            , seSynthesis = Nothing
            , seConfidence = 0.6
            , seProvenance = ProvenanceRuntimeLLM
            , seDomain = Nothing
            , seTemporalScope = Nothing
            , seNamespace = Nothing
            , seLineage = Nothing
            }
      in "relation=" <> relationTypeName (seRelationType edge) <> ";"
        <> selectorPreflightDetail topic topicAtoms basePredicates lemmaMap edge
  where
    chooseHistoricalRelation relations =
      let candidates = filter matchesFrom relations
          scored = [(tokenOverlap edgeTo (renderAtomId (relTo relation)), relation) | relation <- candidates]
      in case scored of
           [] -> Nothing
           ranked -> let (overlap, relation) = maximumBy (comparing fst) ranked
                     in if overlap > 0 then Just relation else Nothing

    matchesFrom relation =
      let AtomId from = relFrom relation
      in T.toLower from == T.toLower edgeFrom

    renderAtomId (AtomId value) = value
    tokenOverlap left right =
      let leftTokens = S.fromList (T.words (T.toLower left))
          rightTokens = S.fromList (T.words (T.toLower right))
      in S.size (S.intersection leftTokens rightTokens)

relationTypeName :: Maybe RelationType -> Text
relationTypeName Nothing = ""
relationTypeName (Just relation) = case relation of
  RelCauses -> "causes"
  RelPresupposes -> "presupposes"
  RelRequires -> "requires"
  RelLimitedBy -> "limitedBy"
  RelPartOf -> "partOf"
  RelContrastsWith -> "contrastsWith"
  RelRelatedTo -> "relatedTo"
  RelSignals -> "signals"
  RelDependsOn -> "dependsOn"
  RelPrecedes -> "precedes"
  _ -> T.pack (show relation)

preflightRejectionEvents :: NetworkUpdateEvent -> [SemanticEdge] -> Map (Text, Text) Text -> [LearningEvent]
preflightRejectionEvents evt rejected details = map rejectOne rejected
  where
    rejectOne edge = (edgeLearningEventForPreflight evt edge)

    edgeLearningEventForPreflight event edge = LearningEvent
      { leTimestamp = nueTimestamp event
      , leSessionId = Nothing
      , leTurnSeq = Nothing
      , leRequestId = nueRequestId event
      , leTopic = nueTopic event
      , leKind = EdgeRejected
      , leSource = LesWorker
      , leEdgeFrom = Just (seFrom edge)
      , leEdgeTo = Just (seTo edge)
      , leProvenance = Just (seProvenance edge)
      , leConfidence = Just (seConfidence edge)
      , leCoOccurrence = Just (seCoOccurrence edge)
      , leReason = Just
          ("knowledge_admission_rejected;"
            <> M.findWithDefault "selector_preflight=unavailable" (seFrom edge, seTo edge) details)
      , lePromptHash = nuePromptHash event
      , leResponseHash = nueResponseHash event
      , leModel = nueModel event
      , leParserDecision = nueParserDecision event
      , leAdmissionDecision = Just "knowledge_admission_rejected"
      , leEvidenceSource = nueEvidenceSource event
      , leEdgeNamespace = seNamespace edge
      , leEdgeOwner = Nothing
      }

-- | Prefer concepts whose predicate vocabularies overlap the scheduled topic.
-- Sorting gives repeatable prompts; the fallback order still remains a local
-- registry, never an LLM-created endpoint list.
selectCandidateTopics :: Map Text (S.Set Text) -> Text -> [Text]
selectCandidateTopics topicAtoms topic =
  take 24 (map snd (sortBy rank candidates))
  where
    normalized = T.toLower (T.strip topic)
    sourceAtoms = M.findWithDefault S.empty normalized topicAtoms
    candidates =
      [ (S.size (S.intersection sourceAtoms atoms), candidate)
      | (candidate, atoms) <- M.toList topicAtoms
      , candidate /= normalized
      ]
    rank (scoreA, topicA) (scoreB, topicB) =
      case compare scoreB scoreA of
        EQ -> compare topicA topicB
        other -> other

acquisitionRelationSlots :: [Text]
acquisitionRelationSlots =
  [ "causes", "presupposes", "requires", "dependsOn", "limitedBy", "partOf", "contrastsWith" ]

proposalEvents :: NetworkUpdateEvent -> [LearningEvent]
proposalEvents = proposalEventsWithDetails M.empty

proposalEventsWithDetails :: Map (Text, Text) Text -> NetworkUpdateEvent -> [LearningEvent]
proposalEventsWithDetails details evt = map recordOne (nueEdges evt)
  where
    recordOne edge = LearningEvent
      { leTimestamp = nueTimestamp evt
      , leSessionId = Nothing
      , leTurnSeq = Nothing
      , leRequestId = nueRequestId evt
      , leTopic = nueTopic evt
      , leKind = LlmEdgeProposed
      , leSource = LesWorker
      , leEdgeFrom = Just (seFrom edge)
      , leEdgeTo = Just (seTo edge)
      , leProvenance = Just (seProvenance edge)
      , leConfidence = Just (seConfidence edge)
      , leCoOccurrence = Just (seCoOccurrence edge)
      , leReason = Just
          ("llm_candidate_admitted_to_runtime_queue;"
            <> M.findWithDefault "selector_preflight=deferred" (seFrom edge, seTo edge) details)
      , lePromptHash = nuePromptHash evt
      , leResponseHash = nueResponseHash evt
      , leModel = nueModel evt
      , leParserDecision = nueParserDecision evt
      , leAdmissionDecision = nueAdmissionDecision evt
      , leEvidenceSource = nueEvidenceSource evt
      , leEdgeNamespace = seNamespace edge
      , leEdgeOwner = Nothing
      }

-- | A successful provider response is durable before it enters the in-memory
-- queue.  Response body and all locally-admitted proposal events share a
-- single transaction; a no-candidate outcome also finalizes its job there.
persistWorkerResult
  :: LearningQueue
  -> Maybe LearningJobClaim
  -> LearningTask
  -> Text
  -> Text
  -> Text
  -> [LearningEvent]
  -> Maybe [NetworkUpdateEvent]
  -> Maybe (Bool, Int, Text, Maybe (Int, Text))
  -> IO ()
persistWorkerResult queue mClaim task promptHash responseHash responseBody events mReadyEvents mFailure =
  case lqPersistence queue of
    Nothing -> pure ()
    Just db -> case mClaim of
      Nothing -> throwAutonomousPersistenceError "persistent learning result has no worker lease"
      Just claim -> case mReadyEvents of
        Just readyEvents -> do
          let payload = TE.decodeUtf8 (LBS.toStrict (encode (BroadReadyEnvelope readyEvents)))
          mask_ $ recordLearningJobResponseReady db claim promptHash responseHash responseBody payload (map (stampWorkerEvent queue) events)
        Nothing -> do
          result <- mask_ $ withDB (qdbPath db) $ \conn ->
              withImmediateTransaction conn $ do
                recordLearningResponseOnConnection conn
                  (ltRequestId task) promptHash responseHash responseBody
                insertLearningEventsOnConnection conn (map (stampWorkerEvent queue) events)
                case mFailure of
                  Nothing -> throwAutonomousPersistenceError "learning result has neither ready payload nor terminal transition"
                  Just (retryable, backoffSeconds, message, mCooldown) -> do
                    changed <- markLearningJobClaimFailedOnConnection conn claim retryable backoffSeconds message
                    unless changed (throwAutonomousPersistenceError "learning failure rejected stale worker lease")
                    forM_ mCooldown $ \(seconds, reason) ->
                      recordLearningTopicCooldownOnConnection conn (ltTopic task) seconds reason True
          either throwAutonomousPersistenceError pure result

stampWorkerEvent :: LearningQueue -> LearningEvent -> LearningEvent
stampWorkerEvent queue event = event
  { leSessionId = lqSessionId queue
  , leEdgeNamespace = effectiveNamespace
  , leEdgeOwner = case effectiveNamespace of
      Just NamespaceGlobal -> Just "global"
      Just _ -> lqSessionId queue
      Nothing -> leEdgeOwner event <|> lqSessionId queue
  }
  where
    effectiveNamespace = leEdgeNamespace event <|>
      case (leEdgeFrom event, leEdgeTo event) of
        (Just _, Just _) -> Just NamespaceSessionLocal
        _ -> Nothing

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

throwAutonomousPersistenceError :: Text -> IO a
throwAutonomousPersistenceError detail =
  throwQxFx0 (mkSQLiteError
    "autonomous_learning"
    "AUTONOMOUS_LEARNING_SQLITE_ERROR"
    (M.singleton "detail" detail))

refillPersistentQueue :: LearningQueue -> IO ()
refillPersistentQueue queue = do
  current <- readIORef (lqSize queue)
  when (current == 0) $ case lqPersistence queue of
    Nothing -> pure ()
    Just db -> loadRunnableLearningJobsForSession db
      (maybe "autonomous-default" id (lqSessionId queue)) (lqCapacity queue) >>= mapM_ (pushLoadedTask queue)

-- | Atomically bump quota counter and reset window if elapsed.
reserveQuota :: AutonomousWorkerConfig -> IORef QuotaState -> LearningQueue -> UTCTime -> Int -> Int -> IO Bool
reserveQuota cfg qsRef queue now requests estimatedTokens =
  case lqPersistence queue of
    Just db -> reserveLearningQuota db now limits requests estimatedTokens
    Nothing -> atomicModifyIORef' qsRef $ \qs ->
      let current = resetQuotaWindows qs now
      in if quotaExceeded cfg current requests estimatedTokens
           then (current, False)
           else (bumpQuota current requests estimatedTokens, True)
  where
    limits = LearningQuotaLimits
      { lqlRequestsPerMinute = awcMaxRequestsPerMinute cfg
      , lqlRequestsPerHour = awcMaxRequestsPerHour cfg
      , lqlRequestsPerDay = awcMaxRequestsPerDay cfg
      , lqlTokensPerMinute = awcMaxTokensPerMinute cfg
      , lqlTokensPerHour = awcMaxTokensPerHour cfg
      , lqlTokensPerDay = awcMaxTokensPerDay cfg
      }

saturatingProduct :: Int -> Int -> Int
saturatingProduct left right
  | left <= 0 || right <= 0 = 0
  | left > maxBound `div` right = maxBound
  | otherwise = left * right

saturatingAdd :: Int -> Int -> Int
saturatingAdd left right
  | left <= 0 = max 0 right
  | right <= 0 = max 0 left
  | left > maxBound - right = maxBound
  | otherwise = left + right

resetQuotaWindows :: QuotaState -> UTCTime -> QuotaState
resetQuotaWindows qs now =
  let dailyReset = diffUTCTime now (qsDayResetAt qs) >= 86400
      hourlyReset = diffUTCTime now (qsHourResetAt qs) >= 3600
      minuteReset = diffUTCTime now (qsMinuteResetAt qs) >= 60
      base = if dailyReset
               then qs { qsDayResetAt = now, qsRequestsDay = 0, qsTokensDay = 0 }
               else qs
      base' = if hourlyReset
                then base { qsHourResetAt = now, qsRequestsHour = 0, qsTokensHour = 0 }
                else base
      base'' = if minuteReset
                 then base' { qsMinuteResetAt = now, qsRequestsMinute = 0, qsTokensMinute = 0 }
                 else base'
  in base''

bumpQuota :: QuotaState -> Int -> Int -> QuotaState
bumpQuota qs requests estimatedTokens = qs
  { qsRequestsMinute = qsRequestsMinute qs + requests
  , qsTokensMinute = qsTokensMinute qs + estimatedTokens
  , qsRequestsHour = qsRequestsHour qs + requests
  , qsTokensHour = qsTokensHour qs + estimatedTokens
  , qsRequestsDay = qsRequestsDay qs + requests
  , qsTokensDay = qsTokensDay qs + estimatedTokens
  }

-- ---------------------------------------------------------------------------
-- ADR-0054 M2: Density-gate triggers
-- ---------------------------------------------------------------------------

-- | Enqueue a 'LearningTask' for a single topic if its density is below
-- 'dcThreshold'.  Returns 'True' iff the task was enqueued.  Useful as a
-- per-turn trigger right after the topic has been chosen.
enqueueIfStarving
  :: LearningQueue
  -> Map Text Text          -- ^ lemma map (used to build topic→atoms)
  -> DensityConfig
  -> Text                  -- ^ topic
  -> SemanticNetwork
  -> IO Bool
enqueueIfStarving queue lemmaMap cfg topic network =
  enqueueIfStarvingWithTopicAtoms queue (buildTopicAtomsMap lemmaMap) cfg topic network

-- | Corpus-aware density-gate variant.  Production uses the map built from
-- 'ssDefinitionCorpus'; the seed-only wrapper remains for compatibility.
enqueueIfStarvingWithTopicAtoms
  :: LearningQueue
  -> Map Text (S.Set Text)
  -> DensityConfig
  -> Text
  -> SemanticNetwork
  -> IO Bool
enqueueIfStarvingWithTopicAtoms queue topicAtoms cfg topic network = do
  requestId <- freshLearningRequestId "per-turn" topic
  case M.lookup topic topicAtoms of
       Just atoms | contentDensity network atoms (dcKappa cfg) < dcThreshold cfg ->
         let task = LearningTask
               { ltTopic     = topic
               , ltPriority  = 1.0 / max 1.0 (contentDensity network atoms (dcKappa cfg) + 0.01)
               , ltRequestId = requestId
               }
         in enqueueLearningTask queue task
       _ -> pure False

-- | Enqueue 'LearningTask's for ALL starving topics discovered by
-- 'starvingTopics'.  Returns the number of tasks enqueued.  Intended
-- for the periodic audit loop.
enqueueStarvingTopics
  :: LearningQueue
  -> Map Text Text          -- ^ lemma map
  -> DensityConfig
  -> SemanticNetwork
  -> IO Int
enqueueStarvingTopics queue lemmaMap cfg network = do
  enqueueStarvingTopicsWithTopicAtoms queue (buildTopicAtomsMap lemmaMap) cfg network

-- | Corpus-aware periodic enqueue variant.  The result counts only accepted
-- tasks, rather than the number considered before bounded-capacity/dedup.
enqueueStarvingTopicsWithTopicAtoms
  :: LearningQueue
  -> Map Text (S.Set Text)
  -> DensityConfig
  -> SemanticNetwork
  -> IO Int
enqueueStarvingTopicsWithTopicAtoms queue topicAtoms cfg network = do
  enqueueStarvingTopicList queue (starvingTopics network topicAtoms cfg)

enqueueStarvingTopicList :: LearningQueue -> [Text] -> IO Int
enqueueStarvingTopicList queue topics = do
  tasks <- mapM
    (\t -> do
      requestId <- freshLearningRequestId "audit" t
      pure LearningTask
        { ltTopic = t
        , ltPriority = 1.0
        , ltRequestId = requestId
        })
    (filter trustedAutonomousTopic topics)
  accepted <- mapM (enqueueLearningTask queue) tasks
  pure (length (filter id accepted))

freshLearningRequestId :: Text -> Text -> IO Text
freshLearningRequestId source topic = do
  requestUuid <- UUIDv4.nextRandom
  pure (source <> ":" <> topic <> ":" <> UUID.toText requestUuid)

trustedAutonomousTopic :: Text -> Bool
trustedAutonomousTopic = (`M.member` definitionCorpus) . T.toLower . T.strip

-- Must not exceed the governed between-turn apply cap. Oversized persisted
-- payloads are rejected before dispatch so they cannot stall the queue.
maxDurableBroadEvents :: Int
maxDurableBroadEvents = 100

rotateTopics :: Int -> [a] -> [a]
rotateTopics _ [] = []
rotateTopics offset topics =
  let pivot = offset `mod` length topics
  in drop pivot topics ++ take pivot topics

-- | Convenience wrapper for the per-turn call site: same as
-- 'enqueueIfStarving' but returns unit so it can be called from IO
-- contexts without threading the boolean.
maybeEnqueueStarvingTopic
  :: LearningQueue
  -> Map Text Text
  -> DensityConfig
  -> Text
  -> SemanticNetwork
  -> IO ()
maybeEnqueueStarvingTopic q lm cfg t sn = void (enqueueIfStarving q lm cfg t sn)

-- | Spawn a background thread that periodically scans all seed topics and
-- enqueues 'LearningTask's for the starving ones.  Prefer
-- 'spawnDensityAuditWithTopicAtoms' in a live runtime, where the curated
-- corpus is larger than the static seed.
--
-- 'getNetwork' is an IO action that returns the current
-- 'SemanticNetwork' to scan (e.g. 'readIORef' of an MVar updated by the
-- turn pipeline, or a SQLite query).
spawnDensityAudit
  :: LearningQueue
  -> Map Text Text          -- ^ lemma map
  -> DensityConfig
  -> Int                      -- ^ audit interval in seconds
  -> IO SemanticNetwork       -- ^ get current network
  -> IO ManagedWorker
spawnDensityAudit queue lemmaMap cfg auditIntervalSec getNetwork =
  spawnDensityAuditWithTopicAtoms queue (buildTopicAtomsMap lemmaMap) cfg auditIntervalSec getNetwork

-- | Corpus-aware density audit.  It runs once immediately, then repeats at
-- the supplied interval.  Capacity, durable deduplication, and cooldowns
-- remain enforced by 'enqueueLearningTask'; an audit never bypasses them.
spawnDensityAuditWithTopicAtoms
  :: LearningQueue
  -> Map Text (S.Set Text)
  -> DensityConfig
  -> Int
  -> IO SemanticNetwork
  -> IO ManagedWorker
spawnDensityAuditWithTopicAtoms queue topicAtoms cfg auditIntervalSec getNetwork =
  do
    cursor <- newIORef 0
    spawnManagedWorker . forever $ do
      result <- try $ do
        network <- getNetwork
        start <- case lqPersistence queue of
          Just db -> advanceLearningTopicCursor db (max 1 (lqCapacity queue))
          Nothing -> do
            current <- readIORef cursor
            modifyIORef' cursor (+ max 1 (lqCapacity queue))
            pure current
        let topics = starvingTopics network topicAtoms cfg
        -- Move by a whole queue window even when every attempted item is
        -- currently deduplicated/cooling down.  Without this rotation a
        -- 4k-topic corpus would repeatedly inspect the alphabetically first
        -- queue-cap entries and never reach the rest.
        enqueueStarvingTopicList queue (rotateTopics start topics)
      case result of
        Left (e :: SomeException)
          | Just async <- (fromException e :: Maybe AsyncException) -> throwIO async
          | otherwise ->
              hPutStrLn stderr $ "[density-audit] scan failed: " <> show e
        Right n -> when (n > 0) $
          hPutStrLn stderr $ "[density-audit] enqueued " <> show n <> " starving topics"
      threadDelay (max 1 auditIntervalSec * 1000 * 1000)
