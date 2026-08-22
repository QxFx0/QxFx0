{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{-| Session bootstrap, readiness gating, and runtime lifecycle wiring. -}
module QxFx0.Runtime.Session.Bootstrap
  ( bootstrapSession
  , withBootstrappedSession
  , closeSession
  , checkSessionReadiness
  , generateFallbackSessionId
  , minimalMorphologyFallback
  , mergeMorphology
  , recoverBootstrapBlanket
  , useExternalKnowledge
  , readExternalKnowledgeEnabled
  , resolveKnowledgePath
  , loadBootstrapDefinitionCorpus
  , bootstrapSemanticNetwork
  , buildNetworkFromAtomGraph
  , readSelfPlayEnabled
  , readSelfPlayRelationsPath
  , selfPlayRelationsPath
  , useSelfPlay
  , useAutonomousLearning
  , readAutonomousLearningEnabled
  , readAutonomousLearningAuditInterval
  , spawnAutonomousLearningHandles
  , spawnAutonomousLearningHandlesWithStore
  , spawnAutonomousLearningHandlesWithStoreAndTopicAtoms
  , stopAutonomousLearningHandles
  ) where

import Control.Concurrent.MVar (modifyMVar, newMVar)
import Control.Exception (bracket, finally, mask, onException, try, IOException, SomeException, catch, throwIO)
import Control.Monad (unless, when)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import qualified QxFx0.Observability.Logging as Log
import QxFx0.Bridge.SQLite
  ( ensureSchemaMigrations
  , loadClusters
  , loadScenes
  , queryIdentityClaimsByFocus
  , withDB
  )
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement (prepareTx, bindTextOrFail, stepOrFail)
import QxFx0.Types.Persistence (LoadStateResult(..), renderPersistenceDiagnostics)
import QxFx0.Bridge.StatePersistence (loadStateWithVersion)
import QxFx0.Types.Persistence (StateVersion(..))
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(..)
  , RuntimeInitErrorDetails(..)
  , SQLiteErrorDetails(..)
  , mkRuntimeInitError
  , renderQxFx0ExceptionForLog
  , throwQxFx0
  , tryIO
  , tryQxFx0
  )
import QxFx0.Governance.Replay (rebuildGovernedSystemState)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Invariants (checkInitialBlanket, renderBlanketViolations)
import QxFx0.Self.Types (BlanketViolation (..))
import QxFx0.Resources
  ( ReadinessMode(..)
  , assessResourceReadiness
  , computeReadinessMode
  , loadMorphologyData
  )
import QxFx0.Runtime.Wiring
  ( hydrateRuntimeTurnState
  , initRuntimeContext
  , rcCaches
  , releaseRuntimeContext
  , withRuntimeDb
  )
import QxFx0.Runtime.Wiring.Context (rtcPgf)
import QxFx0.Runtime.Gate
  ( evaluateBootstrapReadiness
  , evaluateStrictHealth
  , renderBootstrapGateFailure
  )
import QxFx0.Runtime.Health (checkHealth)
import QxFx0.Runtime.PGF (preloadDefaultPGFWithCache)
import QxFx0.Lexicon.GfMap (preloadGfMap, GfMapLoadStatus(..))
import QxFx0.Runtime.Mode (RuntimeMode(..), resolveRuntimeMode)
import QxFx0.Runtime.Paths (resolveDbPath)
import QxFx0.Runtime.Session.Types
import QxFx0.Runtime.Session.SelfConfig
  ( bootstrapSelfState
  , loadSelfBootstrapConfig
  )
import QxFx0.Semantic.SemanticScene (defaultScenes)
import QxFx0.Semantic.Lexicon.RuntimeParadigms (loadDefaultRuntimeParadigms, allParadigmLemmas, emptyRuntimeParadigms)
import QxFx0.Semantic.ContentSelector (buildContentSelector, predicateAtomsForSelector)
import QxFx0.Semantic.ContentSelector.Optimized (buildTopicPredicateIndex, buildAtomTopicIndex, ScoreCache, emptyScoreCache)
import QxFx0.Semantic.ContentSelector.Integration (ContentSelectorState, initSelectorWithOptimizations, emptyContentSelectorState)
import QxFx0.Semantic.Space (buildSemanticSpace)
import QxFx0.Semantic.Content (definitionCorpus, DefinitionContent(..), SemanticPredicate(..), coveredTopics)
import QxFx0.Semantic.Content.Curated
  ( curatedPredicatesPath
  , loadCuratedPredicates
  , mergeCuratedIntoDefinitionCorpus
  )
import QxFx0.Semantic.Ontology (loadOntology, emptyOntology)
import QxFx0.Semantic.Ontology.Dynamic (defaultLearningConfig, emptyDynamicOntologyState)
import QxFx0.Semantic.Network (contentDensityGate, mergeSemanticNetworks)
import QxFx0.Runtime.Session.Autonomous
  ( AutonomousHandles(..)
  , newSemanticNetworkOwner
  , readSemanticNetworkSnapshot
  , snsNetwork
  , spawnGovernedApplyLoop
  )
import QxFx0.Runtime.ManagedWorker (stopManagedWorker)
import QxFx0.Learning.Autonomous
  ( AutonomousWorkerConfig(..)
  , LearningQueue
  , LearningTask(..)
  , NetworkUpdateEvent(..)
  , buildAtomMorphology
  , extendAtomStoreWithTopics
  , defaultAutonomousWorkerConfig
  , enqueueLearningTask
  , newLearningQueue
  , newPersistentLearningQueueForSession
  , readAutonomousWorkerConfig
  , readIntWithDefault
  , spawnAutonomousWorkerWithTopicAtoms
  , spawnAutonomousWorkerWithTopicAtomsAndPredicates
  , spawnDensityAuditWithTopicAtoms
  )
import QxFx0.Learning.CircuitBreaker (PendingBreakerCloseQueue, newPendingBreakerCloseQueue)
import QxFx0.Bridge.SQLite (QxFx0DB(..))
import QxFx0.Learning.Events (ensureLearningEventsSchema)
import QxFx0.Learning.JobQueue (ensureLearningJobSchema)
import QxFx0.Learning.CorroborationQueue (ensureCorroborationTaskSchema)
import QxFx0.Learning.Quarantine (ensureQuarantineSchema)
import QxFx0.Learning.Promotion (ensurePromotionSchema, loadActivePromotionOverlay, renderPromotionOverlay)
import qualified QxFx0.Bridge.SemanticNetwork.RuntimeProjection as RuntimeProjection
import QxFx0.Learning.Metrics (LearningMetrics(..), emptyLearningMetrics, newLearningMetrics)
import QxFx0.Semantic.Content.AtomStore (atomStore)
import QxFx0.Semantic.Network.Types (SemanticNetwork(..))
import Control.Concurrent.STM (TQueue, atomically, newTQueue, writeTQueue)
import QxFx0.Semantic.Network.Seed.Select (loadRelationWeightOverlay, selectSeedNetwork, selectSeedNetworkIO, readUseAtomGraphSeed)
import QxFx0.Semantic.Network.Seed
  ( buildTopicAtomsMapFromCorpus
  , buildTopicAtomsMap
  , overlayConfidence
  , readDensityConfig
  )
import QxFx0.Semantic.Network.Ingest (buildNetworkFromAtomGraph, ingestExternalKnowledge, mergeSelfPlayRelations)
import QxFx0.Semantic.Content.AtomStore (seedGraph)
import Data.Maybe (fromMaybe)
import QxFx0.Semantic.Network.Substrate (BrainKBEntry(..), loadBrainKB, resolveBrainKBPath, buildSubstrateEdges, SubstrateEdgeInfo(..))
import QxFx0.Semantic.Content.SubstrateCandidate
  ( extractCandidates, admitCandidates, promoteAll, defaultAdmissionConfig )
import QxFx0.Semantic.Content.AtomStore (AtomId(..), allTopics, allAtomIds, relationStore, Relation(..), RelationSource(..), seedGraph, withPromoted, atomStore, Atom(..), AtomCategory(..))
import QxFx0.Semantic.Content.AtomDiscovery (discoverAtoms, DiscoveredAtom(..))
import qualified QxFx0.Semantic.Network.Types as NetTypes
import QxFx0.Semantic.Network.Types (SemanticEdge(..), EdgeSource(..), SemanticNetwork(..))
import qualified Data.Set as S
import qualified Data.Text as T
import QxFx0.Types.RuntimeRegime (defaultRuntimeRegime, rrRglMorphologyActive)
import QxFx0.Types.State
  ( SystemState(..)
  , dsActiveScene
  , idsIdentityClaims
  , semClusters
  , ssActiveScene
  , ssClusters
  , ssHistory
  , ssIdentityClaims
  , ssTurnCount
  )
import QxFx0.Runtime.StateDefaults (emptySystemState)
import QxFx0.Types.Domain.Atoms (LexemeCase(..), LexemeForm(..), LexemeNumber(..), MorphologyData(..), SourceTier(..))
import QxFx0.Semantic.Morphology (buildLemmaMap)
import QxFx0.Types.State.Governance (GovernanceRuntimeFault(..))
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory)
import System.IO (hPutStrLn, stderr)
import Paths_qxfx0 (getDataFileName)

-- | Compile-time feature flag for ADR-0052 Phase II external knowledge
-- ingestion. Defaults to 'False' so runtime behavior is unchanged.
useExternalKnowledge :: Bool
useExternalKnowledge = False

-- | Read whether external knowledge ingestion should be enabled.
-- The compile-time 'useExternalKnowledge' flag can force it on; otherwise
-- the @QXFX0_USE_EXTERNAL_KNOWLEDGE@ environment variable enables it
-- when set to @\"1\"@, @\"true\"@, or @\"yes\"@.
readExternalKnowledgeEnabled :: IO Bool
readExternalKnowledgeEnabled = do
  mEnv <- lookupEnv "QXFX0_USE_EXTERNAL_KNOWLEDGE"
  let envEnabled = maybe False (`elem` ["1", "true", "yes"]) mEnv
  pure (envEnabled || useExternalKnowledge)

-- | Compile-time feature flag for ADR-0052 Phase III self-play relation
-- ingestion. Defaults to 'True' as of P2.1 (selfplay admission gate +
-- default-on); set @QXFX0_USE_SELFPLAY@ to @"0"@, @"false"@, @"no"@, or
-- @"disable"@ to disable at runtime.
useSelfPlay :: Bool
useSelfPlay = True

-- | Read whether self-play relation ingestion should be enabled.
-- The compile-time 'useSelfPlay' flag defaults it on; the
-- @QXFX0_USE_SELFPLAY@ environment variable can disable it when set to
-- @\"0\"@, @\"false\"@, @\"no\"@, or @\"disable\"@, or explicitly enable it with
-- @\"1\"@, @\"true\"@, or @\"yes\"@.
readSelfPlayEnabled :: IO Bool
readSelfPlayEnabled = do
  mEnv <- lookupEnv "QXFX0_USE_SELFPLAY"
  let envDisabled = maybe False (`elem` ["0", "false", "no", "disable"]) mEnv
      envEnabled  = maybe False (`elem` ["1", "true", "yes"]) mEnv
  pure (not envDisabled && (useSelfPlay || envEnabled))

-- | Compile-time feature flag for ADR-0054 autonomous semantic network
-- expansion. Defaults to 'False' so runtime behaviour is unchanged unless
-- explicitly enabled via @QXFX0_AUTONOMOUS_LEARNING@ environment variable.
useAutonomousLearning :: Bool
useAutonomousLearning = False

-- | Read whether autonomous semantic network expansion should be enabled.
-- The compile-time 'useAutonomousLearning' flag defaults it off; the
-- @QXFX0_AUTONOMOUS_LEARNING@ environment variable enables it when set to
-- @"1"@, @"true"@, or @"yes"@.
readAutonomousLearningEnabled :: IO Bool
readAutonomousLearningEnabled = do
  mEnv <- lookupEnv "QXFX0_AUTONOMOUS_LEARNING"
  let envEnabled = maybe False (`elem` ["1", "true", "yes"]) mEnv
  pure (envEnabled || useAutonomousLearning)

-- | Interval for the unattended corpus audit.  A value of zero (the default)
-- keeps learning turn-driven; a positive value enables the bounded audit and
-- governed background application loop.
readAutonomousLearningAuditInterval :: IO Int
readAutonomousLearningAuditInterval = do
  mEnv <- lookupEnv "QXFX0_LEARNING_AUDIT_INTERVAL_SEC"
  pure (max 0 (readIntWithDefault mEnv 0))

-- | Resolve the path to the self-play relations file. The
-- @QXFX0_SELFPLAY_RELATIONS_PATH@ environment variable overrides the
-- default @resources/knowledge/selfplay_relations.jsonl@.
readSelfPlayRelationsPath :: IO FilePath
readSelfPlayRelationsPath = do
  mEnv <- lookupEnv "QXFX0_SELFPLAY_RELATIONS_PATH"
  pure (fromMaybe "resources/knowledge/selfplay_relations.jsonl" mEnv)

-- | Spawn the autonomous learning infrastructure (worker thread + queues)
-- when @QXFX0_AUTONOMOUS_LEARNING@ is enabled.  Returns 'Nothing' for
-- all handles when disabled.  The worker processes 'LearningTask's
-- pulled from the queue and emits 'NetworkUpdateEvent's on the update
-- channel for the turn pipeline to drain between turns.
--
-- Between-turn updates are committed by 'commitSemanticNetworkTurn' in
-- 'QxFx0.Runtime.Engine'; this function owns only worker startup and its
-- persistence boundary.
spawnAutonomousLearningHandles :: FilePath -> IO AutonomousHandles
spawnAutonomousLearningHandles dbPath =
  spawnAutonomousLearningHandlesWithStore dbPath atomStore

-- | Production bootstrap supplies a registry extended with all topics from
-- the loaded curated corpus.  The compatibility wrapper above keeps the
-- seed-only registry for narrow tests and legacy callers.
spawnAutonomousLearningHandlesWithStore
  :: FilePath
  -> M.Map AtomId Atom
  -> IO AutonomousHandles
spawnAutonomousLearningHandlesWithStore dbPath store = do
  let topicAtoms = buildTopicAtomsMap (buildLemmaMap (buildAtomMorphology store))
  spawnAutonomousLearningHandlesWithStoreAndTopicAtoms dbPath store topicAtoms

-- | Production variant with a density/candidate map generated from the
-- complete loaded corpus, not only the fixed atom-store seed.
spawnAutonomousLearningHandlesWithStoreAndTopicAtoms
  :: FilePath
  -> M.Map AtomId Atom
  -> M.Map Text (S.Set Text)
  -> IO AutonomousHandles
spawnAutonomousLearningHandlesWithStoreAndTopicAtoms dbPath store topicAtoms = do
  spawnAutonomousLearningHandlesWithStoreAndTopicAtomsAndPredicates dbPath store topicAtoms M.empty

spawnAutonomousLearningHandlesWithStoreAndTopicAtomsAndPredicates
  :: FilePath
  -> M.Map AtomId Atom
  -> M.Map Text (S.Set Text)
  -> M.Map Text [SemanticPredicate]
  -> IO AutonomousHandles
spawnAutonomousLearningHandlesWithStoreAndTopicAtomsAndPredicates dbPath store topicAtoms basePredicates = do
  spawnAutonomousLearningHandlesForSession (Just "autonomous-default") dbPath store topicAtoms basePredicates

spawnAutonomousLearningHandlesForSession
  :: Maybe Text
  -> FilePath
  -> M.Map AtomId Atom
  -> M.Map Text (S.Set Text)
  -> M.Map Text [SemanticPredicate]
  -> IO AutonomousHandles
spawnAutonomousLearningHandlesForSession sessionId dbPath store topicAtoms basePredicates = do
  enabled <- readAutonomousLearningEnabled
  if not enabled
    then pure disabledAutonomousHandles
    else do
      storageResult <- initializeAutonomousStorage dbPath
      case storageResult of
        Left err -> do
          Log.logError "Autonomous learning storage initialization failed; worker disabled"
            (Log.addContext "db_path" (T.pack dbPath) $
             Log.addContext "detail" err Log.emptyContext)
          pure disabledAutonomousHandles
        Right persistenceDb -> mask $ \restore -> do
          let closeStorage = NSQL.close (qdbConn persistenceDb)
          (cfg, queue, updates, breakerQueue, metricsRef) <- restore (do
              cfg <- readAutonomousWorkerConfig
              queue <- newPersistentLearningQueueForSession persistenceDb sessionId (awcQueueCap cfg)
              updates <- atomically newTQueue
              breakerQueue <- newPendingBreakerCloseQueue 100
              metricsRef <- newLearningMetrics
              pure (cfg, queue, updates, breakerQueue, metricsRef))
            `onException` closeStorage
          let morph = buildAtomMorphology store
          -- The parent stays masked from fork until ownership is returned.
          workerThread <- spawnAutonomousWorkerWithTopicAtomsAndPredicates
            cfg store morph topicAtoms basePredicates queue updates
            `onException` closeStorage
          pure AutonomousHandles
            { ahQueue               = Just queue
            , ahUpdateQueue         = Just updates
            , ahWorkerThread        = Just workerThread
            , ahPendingBreakerQueue = Just breakerQueue
            , ahQuarantineDB       = Just persistenceDb
            , ahMetricsRef         = Just metricsRef
            , ahNetworkOwner       = Nothing
            , ahAuditThread        = Nothing
            , ahApplyThread        = Nothing
            , ahSessionId          = sessionId
            , ahEnabled            = True
            }

disabledAutonomousHandles :: AutonomousHandles
disabledAutonomousHandles = AutonomousHandles
  { ahQueue               = Nothing
  , ahUpdateQueue         = Nothing
  , ahWorkerThread        = Nothing
  , ahPendingBreakerQueue = Nothing
  , ahQuarantineDB       = Nothing
  , ahMetricsRef         = Nothing
  , ahNetworkOwner       = Nothing
  , ahAuditThread        = Nothing
  , ahApplyThread        = Nothing
  , ahSessionId          = Nothing
  , ahEnabled            = False
  }

-- | Attach the opt-in unattended learning loop to an already-created worker.
-- The versioned owner is the only canonical network snapshot for background learning;
-- all emitted LLM candidates still pass 'applyAutonomousEventBatch'.
startAutonomousLearningAudit
  :: AutonomousHandles
  -> MorphologyData
  -> M.Map Text DefinitionContent
  -> SemanticNetwork
  -> IO AutonomousHandles
startAutonomousLearningAudit handles morphology corpus initialNetwork = do
  auditInterval <- readAutonomousLearningAuditInterval
  case ahQueue handles of
    Nothing -> pure handles
    Just queue
      | not (ahEnabled handles) || auditInterval <= 0 -> pure handles
      | otherwise -> mask $ \restore -> do
          networkOwner <- newSemanticNetworkOwner initialNetwork
          densityConfig <- restore readDensityConfig
          let topicAtoms = buildTopicAtomsMapFromCorpus (buildLemmaMap morphology) corpus
              attached = handles { ahNetworkOwner = Just networkOwner }
          auditThread <- spawnDensityAuditWithTopicAtoms
            queue topicAtoms densityConfig auditInterval
              (snsNetwork <$> readSemanticNetworkSnapshot networkOwner)
          -- Apply quickly after a worker result arrives, while keeping a
          -- modest bounded cadence even when the audit itself is infrequent.
          applyThread <- spawnGovernedApplyLoop attached (min 5 auditInterval)
            `onException` stopManagedWorker auditThread
          let started = attached
                { ahAuditThread = Just auditThread
                , ahApplyThread = Just applyThread
                }
              stopStarted = stopManagedWorker applyThread `finally` stopManagedWorker auditThread
          restore (Log.logInfo "Autonomous corpus audit enabled"
              (Log.addContext "interval_sec" (T.pack (show auditInterval)) $
               Log.addContext "topics" (T.pack (show (M.size corpus))) Log.emptyContext))
            `onException` stopStarted
          pure started

initializeAutonomousStorage :: FilePath -> IO (Either Text QxFx0DB)
initializeAutonomousStorage dbPath = do
  opened <- NSQL.open dbPath
  case opened of
    Left err -> pure (Left err)
    Right conn -> do
      let persistenceDb = QxFx0DB dbPath conn
      initialized <- try $ do
        RuntimeProjection.ensureRuntimeProjectionSchema persistenceDb
        ensureLearningJobSchema persistenceDb
        ensureLearningEventsSchema persistenceDb
        ensureCorroborationTaskSchema persistenceDb
        ensureQuarantineSchema persistenceDb
      case initialized of
        Left (err :: SomeException) -> do
          NSQL.close conn
          pure (Left (T.pack (show err)))
        Right () -> pure (Right persistenceDb)

-- | Alias for 'readSelfPlayRelationsPath'.
selfPlayRelationsPath :: IO FilePath
selfPlayRelationsPath = readSelfPlayRelationsPath

-- | Resolve a knowledge file path. First try the path as given; if it
-- does not exist, fall back to a @Paths_qxfx0@ data-file path; finally
-- return the original path so that a later stage can report a sensible
-- \"file not found\" error.
resolveKnowledgePath :: FilePath -> IO FilePath
resolveKnowledgePath path = do
  exists <- doesFileExist path
  if exists
    then pure path
    else do
      dataResult <- tryIO (getDataFileName path)
      case dataResult of
        Right dataPath -> pure dataPath
        Left _         -> pure path

-- | The display corpus shared by normal sessions and isolated evaluations.
-- Curated material remains local and deterministic; a missing or malformed
-- resource degrades to the checked-in seed corpus just as session bootstrap
-- does.
loadBootstrapDefinitionCorpus :: IO (M.Map Text DefinitionContent)
loadBootstrapDefinitionCorpus = do
  curatedPath <- resolveKnowledgePath curatedPredicatesPath
  curatedExists <- doesFileExist curatedPath
  if not curatedExists
    then do
      Log.logWarn "Curated predicates file not found; using seed corpus only"
        (Log.addContext "path" (T.pack curatedPath) Log.emptyContext)
      pure definitionCorpus
    else do
      curatedResult <- try @IOException (loadCuratedPredicates curatedPath)
      case curatedResult of
        Left err -> do
          Log.logWarn "Curated predicates load failed; using seed corpus only"
            (Log.addContext "error" (T.pack (show err)) Log.emptyContext)
          pure definitionCorpus
        Right curated -> do
          Log.logInfo "Curated predicates loaded"
            (Log.addContext "topics" (T.pack $ show $ M.size curated) Log.emptyContext)
          pure (mergeCuratedIntoDefinitionCorpus curated definitionCorpus)

-- | Build the bootstrapped semantic network from morphology and brain_kb
-- substrate, optionally merging external ontology/relations.
bootstrapSemanticNetwork :: MorphologyData -> [BrainKBEntry] -> Bool -> IO SemanticNetwork
bootstrapSemanticNetwork morphology brainKBEntries useExternal =
  let lemmaMap = buildLemmaMap morphology
      explicitTopicSet = S.fromList coveredTopics
      substrateEdges = buildSubstrateEdges brainKBEntries explicitTopicSet
      substrateEdgeMap = M.fromList
        [ ((seiFrom e, seiTo e), NetTypes.semanticEdge (seiFrom e) (seiTo e) (seiWeight e) (seiCooc e) NetTypes.SubstrateEdge)
        | e <- substrateEdges
        ]
  in do
      seedNetwork <- selectSeedNetworkIO lemmaMap
      let seedEdges = NetTypes.snEdges seedNetwork
          mergedEdges = M.union seedEdges substrateEdgeMap
          mergedNetwork = seedNetwork { NetTypes.snEdges = mergedEdges }
      withExternal <- if not useExternal
        then pure mergedNetwork
        else do
          ontologyPath <- resolveKnowledgePath "resources/knowledge/ontology.jsonl"
          relationsPath <- resolveKnowledgePath "resources/knowledge/relations.jsonl"
          mExternal <- ingestExternalKnowledge ontologyPath relationsPath
          pure $ maybe mergedNetwork (mergeSemanticNetworks mergedNetwork) mExternal
      selfPlayEnabled <- readSelfPlayEnabled
      if not selfPlayEnabled
        then pure withExternal
        else do
          selfPlayPath <- resolveKnowledgePath =<< readSelfPlayRelationsPath
          selfPlayExists <- doesFileExist selfPlayPath
          if not selfPlayExists
            then pure withExternal
            else mergeSelfPlayRelations selfPlayPath withExternal

bootstrapSession :: Bool -> Text -> IO Session
bootstrapSession quiet sessionId = mask $ \restore -> do
  cleanupRef <- newIORef (pure ())
  session <- restore (bootstrapSessionTracked cleanupRef quiet sessionId)
    `onException` (readIORef cleanupRef >>= id)
  writeIORef cleanupRef (pure ())
  pure session

-- The outer bootstrap owns resources until a complete Session is returned.
-- Register each long-lived acquisition while masked so asynchronous failure
-- cannot land between acquisition and rollback registration.
bootstrapSessionTracked :: IORef (IO ()) -> Bool -> Text -> IO Session
bootstrapSessionTracked cleanupRef quiet sessionId = do
  bootstrapStart <- getCurrentTime
  Log.logInfo "Starting session bootstrap"
    (Log.addContext "session_id" sessionId Log.emptyContext)
  selfBootstrapConfig <- loadSelfBootstrapConfig
  dbPath <- resolveDbPath
  runtimeMode <- resolveRuntimeMode
  createDirectoryIfMissing True (takeDirectory dbPath)
  readiness <- assessResourceReadiness dbPath
  let readinessMode = computeReadinessMode readiness
  Log.logDebug "Resource readiness assessed"
    (Log.addContext "readiness_mode" (T.pack $ show readinessMode) $
     Log.addContext "db_path" (T.pack dbPath) Log.emptyContext)
  case evaluateBootstrapReadiness runtimeMode readinessMode of
    Left failure -> do
      Log.logError "Bootstrap readiness gate failed"
        (Log.addContext "failure" (renderBootstrapGateFailure failure) Log.emptyContext)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "readiness_gate" "BOOTSTRAP_GATE_FAILURE"
        (M.fromList [("failure", renderBootstrapGateFailure failure)])
    Right _ ->
      case readinessMode of
        Degraded failed -> do
          Log.logWarn "Bootstrap in degraded mode"
            (Log.addContext "failed_components" (T.pack $ show failed) Log.emptyContext)
          unless quiet $ hPutStrLn stderr $ "[degraded] optional components unavailable: " ++ show failed
        _ ->
          pure ()
  gfMapPreloadStatus <- preloadGfMap
  case gfMapPreloadStatus of
    GfMapLoaded _ ->
      Log.logInfo "GF lexicon map preloaded" Log.emptyContext
    GfMapLoadFailed reason ->
      Log.logWarn "GF lexicon map preload failed; runtime will degrade gracefully on GF map paths"
        (Log.addContext "reason" reason Log.emptyContext)
  schemaInitResult <- try (withDB dbPath $ \db -> do
    ensureSchemaMigrations db
    ensurePromotionSchema (QxFx0DB dbPath db)
    ts <- prepareTx db "bootstrap_runtime_session" "INSERT OR IGNORE INTO runtime_sessions(id, agency, tension, status) VALUES(?, 0.5, 0.3, 'active')"
    bindTextOrFail ts 1 sessionId
    stepOrFail ts
    pure ()
    ) :: IO (Either QxFx0Exception (Either Text ()))
  case schemaInitResult of
    Left err -> do
      Log.logException err
        (Log.addContext "db_path" (T.pack dbPath) $
         Log.addContext "stage" "schema_init" Log.emptyContext)
      hPutStrLn stderr $ "[runtime_init_debug] schema_init_qxfx0_exception db=" <> dbPath <> " detail=" <> T.unpack (renderQxFx0ExceptionForLog err)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "schema_init" "SCHEMA_INIT_EXCEPTION"
        (M.fromList [("db_path", T.pack dbPath), ("detail", runtimeInitDetail err)])
    Right (Left err) -> do
      Log.logError "Schema initialization SQL error"
        (Log.addContext "db_path" (T.pack dbPath) $
         Log.addContext "detail" err Log.emptyContext)
      hPutStrLn stderr $ "[runtime_init_debug] schema_init_sql_error db=" <> dbPath <> " detail=" <> T.unpack err
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "schema_init" "SCHEMA_INIT_SQL_ERROR"
        (M.fromList [("db_path", T.pack dbPath), ("detail", err)])
    Right (Right _) -> do
      Log.logInfo "Schema initialization complete"
        (Log.addContext "db_path" (T.pack dbPath) Log.emptyContext)
      pure ()

  morphologyResult <- tryQxFx0 loadMorphologyData
  morphology <- case morphologyResult of
    Left err -> do
      Log.logException err
        (Log.addContext "stage" "morphology_load" Log.emptyContext)
      hPutStrLn stderr $ "[runtime_init_debug] morphology_load_failed detail=" <> T.unpack (renderQxFx0ExceptionForLog err)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "morphology_load" "MORPHOLOGY_LOAD_FAILED"
        (M.fromList [("detail", renderQxFx0ExceptionForLog err)])
    Right md -> do
      Log.logInfo "Morphology data loaded" Log.emptyContext
      pure md
  -- R1 + flag gate (RGL Russian): load runtime morphology paradigms only when
  -- 'rrRglMorphologyActive' is set. The flag is static (set in
  -- 'defaultRuntimeRegime', not changed mid-session), so gating the LOAD here
  -- makes it a real switch: flag off → empty paradigms → 'lookupNounForm' always
  -- misses → 'lookupLemmaForm' uses the JSON path everywhere → RGL is genuinely
  -- inert (the documented "rrRglMorphologyActive = False ⇒ JSON production"
  -- contract). Flag on → RGL-backed morphology for covered lemmas. Load failure
  -- is non-fatal: an empty set degrades gracefully to JSON.
  runtimeParadigms <-
    if rrRglMorphologyActive defaultRuntimeRegime
      then do
        ps <- loadDefaultRuntimeParadigms
        when (null (allParadigmLemmas ps)) $
          Log.logInfo "Runtime paradigms empty (JSON morphology fallback active)" Log.emptyContext
        pure ps
      else pure emptyRuntimeParadigms
  runtime <- mask $ \restore -> do
    acquired <- restore (initRuntimeContext dbPath)
    writeIORef cleanupRef (releaseRuntimeContext acquired)
    pure acquired
  pgfPreloadStart <- getCurrentTime
  pgfPreloadResult <- try (preloadDefaultPGFWithCache (rtcPgf (rcCaches runtime)))
  pgfPreloadEnd <- getCurrentTime
  case pgfPreloadResult of
    Left (err :: IOException) ->
      Log.logWarn "PGF grammar preload failed; runtime will degrade gracefully on PGF paths"
        (Log.addContext "error" (T.pack (show err)) Log.emptyContext)
    Right (Left err) ->
      Log.logWarn "PGF grammar preload failed; runtime will degrade gracefully on PGF paths"
        (Log.addContext "error" err Log.emptyContext)
    Right (Right ()) ->
      Log.logInfo "PGF grammar preloaded" Log.emptyContext
  Log.logInfo "PGF preload timing"
    (Log.addContext "duration_ms" (elapsedMillis pgfPreloadStart pgfPreloadEnd) $
     Log.addContext "status" (pgfPreloadStatus pgfPreloadResult) Log.emptyContext)
  health <- checkHealth runtime
  case evaluateStrictHealth runtimeMode health of
    Left failure -> do
      Log.logError "Health gate failed"
        (Log.addContext "failure" (renderBootstrapGateFailure failure) Log.emptyContext)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "health_gate" "HEALTH_GATE_FAILURE"
        (M.fromList [("failure", renderBootstrapGateFailure failure)])
    Right _ -> do
      Log.logInfo "Health check passed" Log.emptyContext
      pure ()

  idClaims <- withRuntimeDb runtime $ \db ->
    queryIdentityClaimsByFocus db ["identity", "agency", "meaning", "consciousness", "truth"]

  clusters <- withRuntimeDb runtime loadClusters
  scenes <- withRuntimeDb runtime loadScenes

  -- Load brain_kb for substrate network enrichment
  brainKBPath <- resolveBrainKBPath
  brainKBEntries <- loadBrainKB brainKBPath

  -- ADR-0052 Phase IV: load ontology once for category classification.
  -- Failure is non-fatal: the classifier falls back to lexical markers.
  ontologyPath <- resolveKnowledgePath "resources/knowledge/ontology.jsonl"
  ontologyResult <- try @IOException (loadOntology ontologyPath)
  ontology <- case ontologyResult of
    Left err -> do
      Log.logWarn "Ontology load failed; category classifier will fall back to lexical markers"
        (Log.addContext "error" (T.pack (show err)) Log.emptyContext)
      pure emptyOntology
    Right ot -> do
      Log.logInfo "Ontology loaded" Log.emptyContext
      pure ot

  externalEnabled <- readExternalKnowledgeEnabled
  seededNetwork <- bootstrapSemanticNetwork morphology brainKBEntries externalEnabled
  -- Autonomous governed applies persist each admitted runtime edge
  -- immediately.  Rehydrate that projection before the state restore overlay
  -- so unattended learning survives a clean shutdown without requiring a
  -- follow-up dialogue turn to save the whole SystemState.
  runtimeEdges <- withRuntimeDb runtime $ \db -> do
    let projectionDb = QxFx0DB dbPath db
    RuntimeProjection.ensureRuntimeProjectionSchema projectionDb
    RuntimeProjection.loadRuntimeEdgeProjection projectionDb sessionId
  let projectionNetwork = seededNetwork
        { snNodes = S.fromList
            (concatMap (\edge -> [seFrom edge, seTo edge]) (M.elems runtimeEdges))
        , snEdges = runtimeEdges
        , snActivation = M.empty
        , snActivationLog = mempty
        }
      finalNetwork = mergeSemanticNetworks seededNetwork projectionNetwork
  when (not (M.null runtimeEdges)) $
    Log.logInfo "Runtime semantic projection restored"
      (Log.addContext "edges" (T.pack (show (M.size runtimeEdges))) Log.emptyContext)

  -- P1.2: load curated predicates for gap concepts and merge them into the
  -- definition corpus.  Failure is non-fatal: the runtime falls back to the
  -- hardcoded seed corpus.
  extendedCorpus <- loadBootstrapDefinitionCorpus

  activePromotionOverlay <- withRuntimeDb runtime $ \db ->
    loadActivePromotionOverlay (QxFx0DB dbPath db)
  let (promotionOverlayRuntime, promotionCorpus) =
        case activePromotionOverlay of
          Nothing -> (Nothing, M.empty)
          Just (runtimeOverlay, rawCorpus) ->
            let (renderedRuntime, renderedCorpus) = renderPromotionOverlay morphology runtimeOverlay rawCorpus
            in (Just renderedRuntime, renderedCorpus)
  when (not (M.null promotionCorpus)) $
    Log.logInfo "Active promotion overlay loaded"
      (Log.addContext "topics" (T.pack (show (M.size promotionCorpus))) Log.emptyContext)
  let effectiveCorpus = M.unionWith mergeOverlayTopic extendedCorpus promotionCorpus
      mergeOverlayTopic base overlay =
        base { dcPredicates = dcPredicates base ++ dcPredicates overlay }

  let firstScene = case (scenes ++ defaultScenes) of
        s : _ -> s
        [] -> ssActiveScene emptySystemState

      lemmaMap = buildLemmaMap morphology
      topicAtoms = M.fromList
         [ (topic, S.unions [predicateAtomsForSelector lemmaMap p | p <- dcPredicates dc])
        | (topic, dc) <- M.toList effectiveCorpus
        ]
      topicPredicates = M.map dcPredicates effectiveCorpus
      topicList = allTopics
      discoveredAtoms = discoverAtoms brainKBEntries
      discoveredAtomIds = map (atomId . daAtom) discoveredAtoms
      knownAtomIds = allAtomIds ++ discoveredAtomIds
      candidates = extractCandidates brainKBEntries topicList
      (admitted, _rejected) = admitCandidates defaultAdmissionConfig knownAtomIds candidates
      promotedRelations = promoteAll admitted
      seedSpace = buildSemanticSpace finalNetwork topicAtoms
      seedSelector = buildContentSelector seedSpace topicAtoms topicPredicates lemmaMap (Just ontology)
      -- Initialize ContentSelectorState with optimizations
      selectorState = initSelectorWithOptimizations seedSpace topicAtoms topicPredicates lemmaMap (Just ontology)

      freshState = emptySystemState
        { ssDialogue = (ssDialogue emptySystemState) {dsActiveScene = firstScene}
        , ssMorphology = morphology
        , ssRuntimeParadigms = runtimeParadigms
        , ssIdentity = (ssIdentity emptySystemState) {idsIdentityClaims = idClaims}
        , ssSemantic = (ssSemantic emptySystemState) {semClusters = clusters}
        , ssSessionId = sessionId
        , ssContentSelector = seedSelector
        , ssContentSelectorState = Just selectorState
        , ssLemmaMap = buildLemmaMap morphology
        , ssSemanticNetwork = finalNetwork
        , ssOntology = ontology
        , ssRuntimeGraph = withPromoted promotedRelations seedGraph
        , ssDefinitionCorpus = effectiveCorpus
        , ssCuratedOverlay = promotionOverlayRuntime
        , ssSelfState = bootstrapSelfState selfBootstrapConfig Nothing
        }



  (loadedState, observedVersion) <-
    loadStateWithVersion (withRuntimeDb runtime) sessionId
  let observedRevision = stateRevision observedVersion
  (stateOrigin, restored) <- do
    case loadedState of
      LoadStateMissing ->
        pure (FreshOrigin, freshState)
      LoadStateCorrupt diagnostics -> do
        let rendered = renderPersistenceDiagnostics diagnostics
        unless quiet $
          hPutStrLn stderr $
            "[runtime_init_debug] persisted_state_corrupt session=" <> T.unpack sessionId <> " detail=" <> T.unpack rendered
        case runtimeMode of
          DegradedRuntime -> do
            let recovered = freshState
                  { ssSessionId = sessionId
                  , ssGovernanceRuntimeFault = Just (GrfRecoveredCorruptBootstrap rendered)
                  }
            unless quiet $
              hPutStrLn stderr $
                "[runtime_init_debug] persisted_state_corrupt_degraded_recovery session=" <> T.unpack sessionId
            pure (RecoveredCorruptOrigin, recovered)
          StrictRuntime ->
            throwQxFx0 $ mkRuntimeInitError "Bootstrap" "state_restore" "STATE_CORRUPT"
              (M.fromList [("session_id", sessionId), ("diagnostics", rendered)])
      LoadStateRestored ss ->
        -- A persisted zero-turn state still carries restoration provenance and
        -- may contain a non-authoritative truth cap that must survive restart.
        -- Bootstrap currently performs three lifecycle roles in one local block:
        -- (1) authoritative restore admission has already happened inside
        --     'loadState' / 'rebuildDerivedViewsAfterLoad';
        -- (2) substrate backfill/overlay applies scene, morphology, cluster,
        --     identity-claim, and live-session adjustments;
        -- (3) authoritative governance rebuild may rerun after those overlays.
        let restored0 = ss
                  { ssDialogue = (ssDialogue ss) {dsActiveScene = firstScene}
                  , ssMorphology = mergeMorphology morphology (ssMorphology ss)
                  , ssRuntimeParadigms = runtimeParadigms
                  , ssIdentity = (ssIdentity ss)
                    { idsIdentityClaims = if null (ssIdentityClaims ss) then idClaims else ssIdentityClaims ss
                    }
                  , ssSemantic = (ssSemantic ss)
                     { semClusters = if null (ssClusters ss) then clusters else ssClusters ss
                     }
                   , ssSessionId = sessionId
                   , ssSemanticNetwork = finalNetwork
                   , ssOntology = ontology
                   , ssSemanticSpace = seedSpace
                   , ssContentSelector = seedSelector
                   , ssContentSelectorState = Just selectorState
                   , ssLemmaMap = lemmaMap
                   , ssRuntimeGraph = withPromoted promotedRelations seedGraph
                   , ssDefinitionCorpus = effectiveCorpus
                   , ssCuratedOverlay = promotionOverlayRuntime
                   , ssSelfState = bootstrapSelfState selfBootstrapConfig (Just (ssSelfState ss))
                   }
        in if truthContractIsAuthoritative (ssTruthContractStatus restored0)
             then case rebuildGovernedSystemState restored0 of
                    Right restored1 -> pure (RestoredOrigin, restored1)
                    Left err -> throwQxFx0 $ mkRuntimeInitError "Bootstrap" "governance_rebuild" "GOVERNANCE_REBUILD_FAILED"
                      (M.fromList [("session_id", sessionId), ("error", err)])
             else pure (RestoredOrigin, restored0)
  -- P1.1: overlay persisted semantic-network confidence onto the freshly
  -- built seed network, then load any tuned relation-weight overlay.
  -- This closes the write-without-read feedback loop: graph structure
  -- always comes from the current seed/build, while learned weights are
  -- preserved across restarts and further tuned by the JSONL overlay file.
  let restoredNetwork = ssSemanticNetwork restored
      overlayedNetwork = case stateOrigin of
        FreshOrigin -> finalNetwork
        _           -> if not (S.null (snNodes restoredNetwork)) && contentDensityGate restoredNetwork
                         then overlayConfidence finalNetwork restoredNetwork
                         else finalNetwork
  networkWithOverlay <- loadRelationWeightOverlay "resources/config/tuned_relation_weights.jsonl" overlayedNetwork
  let restoredWithNetwork = restored { ssSemanticNetwork = networkWithOverlay }
  -- Phase 1: verify that the freshly bootstrapped state forms a
  -- structurally coherent self (see docs/THEORY.md §4.1 and
  -- docs/adr/0007-dual-mode-conatus.md). Some failures are recoverable
  -- (empty session identifier, empty morphology). Recovered fields are
  -- threaded back into 'restored' and 'sessionId' so the remainder of
  -- bootstrap uses the repaired values.
  (remainingVs, restored', sessionId') <-
    recoverBootstrapBlanket morphology restoredWithNetwork sessionId
  case remainingVs of
    [] -> do
      if sessionId' /= sessionId || restored' /= restored
        then Log.logWarn "Self-blanket verification recovered"
               (Log.addContext "state_origin" (T.pack $ show stateOrigin) $
                Log.addContext "recovered_session_id" sessionId' Log.emptyContext)
        else Log.logInfo "Self-blanket verification passed"
               (Log.addContext "state_origin" (T.pack $ show stateOrigin) Log.emptyContext)
      pure ()
    vs -> do
      let violations = renderBlanketViolations vs
      Log.logError "Self-blanket verification failed"
        (Log.addContext "violations" violations Log.emptyContext)
      throwQxFx0 (IdentityRupture ("bootstrap: " <> violations))
  hydrateRuntimeTurnState runtime restored'
  let learningStore = extendAtomStoreWithTopics atomStore effectiveCorpus
      learningTopicAtoms = buildTopicAtomsMapFromCorpus (buildLemmaMap (ssMorphology restored')) effectiveCorpus
  mask $ \restore -> do
    workerHandles <- spawnAutonomousLearningHandlesForSession
      (Just sessionId') dbPath learningStore learningTopicAtoms
      (M.map dcPredicates effectiveCorpus)
    autonomousHandles <- restore (startAutonomousLearningAudit
        workerHandles
        (ssMorphology restored')
        effectiveCorpus
        (ssSemanticNetwork restored'))
      `onException` stopAutonomousLearningHandles workerHandles
    closeState <- newMVar False
    let session = Session
          { sessSystemState = restored'
          , sessOutputMode = DialogueMode
          , sessSessionId = sessionId'
          , sessDbPath = dbPath
          , sessStateOrigin = stateOrigin
          , sessStateRevision = observedRevision
          , sessReadinessMode = readinessMode
          , sessRuntime = runtime
          , sessAutonomousHandles = autonomousHandles
          , sessCloseState = closeState
          }
    bootstrapEnd <- getCurrentTime
    restore (Log.logInfo "Session bootstrap complete"
        (Log.addContext "bootstrap_ms" (elapsedMillis bootstrapStart bootstrapEnd) $
         Log.addContext "pgf_preload_ms" (elapsedMillis pgfPreloadStart pgfPreloadEnd) $
         Log.addContext "session_id" sessionId' $
         Log.addContext "state_origin" (T.pack $ show stateOrigin) $
         Log.addContext "turn_count" (T.pack $ show $ ssTurnCount restored') Log.emptyContext))
      `onException` stopAutonomousLearningHandles autonomousHandles
    pure session

elapsedMillis :: UTCTime -> UTCTime -> Text
elapsedMillis start end =
  T.pack (show (round (realToFrac (diffUTCTime end start) * 1000 :: Double) :: Integer))

pgfPreloadStatus :: Either IOException (Either Text ()) -> Text
pgfPreloadStatus result =
  case result of
    Left _ -> "io_error"
    Right (Left _) -> "degraded"
    Right (Right ()) -> "ok"

-- | Merge persisted morphology with resource-loaded morphology.
-- Resource morphology takes precedence; persisted morphology may fill
-- only gaps and must not outrun the current provenance boundary.
mergeMorphology :: MorphologyData -> MorphologyData -> MorphologyData
mergeMorphology resource persisted = MorphologyData
  { mdPrepositional = M.union (mdPrepositional resource) (mdPrepositional persisted)
  , mdGenitive      = M.union (mdGenitive resource)      (mdGenitive persisted)
  , mdNominative    = M.union (mdNominative resource)    (mdNominative persisted)
    , mdFormsBySurface = M.union (mdFormsBySurface resource) (mdFormsBySurface persisted)
    }

runtimeInitDetail :: QxFx0Exception -> Text
runtimeInitDetail ex =
  case ex of
    SQLiteErrorStructured details -> sedOperation details <> ": " <> sedErrorCode details
    RuntimeInitError msg -> msg
    RuntimeInitErrorStructured details -> riedOperation details <> ": " <> riedErrorCode details
    _ -> renderQxFx0ExceptionForLog ex

withBootstrappedSession :: Bool -> Text -> (Session -> IO a) -> IO a
withBootstrappedSession quiet sessionId =
  bracket (bootstrapSession quiet sessionId) closeSession

closeSession :: Session -> IO ()
closeSession session = mask $ \restore ->
  -- Keep the state MVar owned until cleanup completes.  'modifyMVar' restores
  -- the old False value if cleanup throws or is interrupted, making close
  -- safely retryable and making concurrent close callers wait for completion.
  modifyMVar (sessCloseState session) $ \closed ->
    if closed
      then pure (True, ())
      else do
        restore (do
          Log.logInfo "Closing session"
            (Log.addContext "session_id" (sessSessionId session) Log.emptyContext)
          stopAutonomousWorker (sessAutonomousHandles session) `finally`
            ((releaseRuntimeContext (sessRuntime session) `catch` \e -> do
                hPutStrLn stderr $ "[closeSession] releaseRuntimeContext failed: " <> show (e :: SomeException)
                throwIO e)
              `finally` closeAutonomousStorage (sessAutonomousHandles session)))
        pure (True, ())

-- | Stop every autonomous producer/consumer, join it, then close the owned
-- persistence handle. Used by startup rollback before a Session exists.
stopAutonomousLearningHandles :: AutonomousHandles -> IO ()
stopAutonomousLearningHandles handles =
  stopAutonomousWorker handles `finally` closeAutonomousStorage handles

stopAutonomousWorker :: AutonomousHandles -> IO ()
stopAutonomousWorker handles =
  stop "audit" (ahAuditThread handles) `finally`
    (stop "worker" (ahWorkerThread handles) `finally`
      stop "governed apply" (ahApplyThread handles))
  where
    stop _ Nothing = pure ()
    stop label (Just worker) =
      stopManagedWorker worker `catch` \e -> do
        hPutStrLn stderr $ "[closeSession] stop autonomous " <> label <> " failed: " <> show (e :: SomeException)
        throwIO e

closeAutonomousStorage :: AutonomousHandles -> IO ()
closeAutonomousStorage handles =
  case ahQuarantineDB handles of
    Nothing -> pure ()
    Just persistenceDb ->
      NSQL.close (qdbConn persistenceDb) `catch` \e -> do
        hPutStrLn stderr $ "[closeSession] close autonomous storage failed: " <> show (e :: SomeException)
        throwIO e

checkSessionReadiness :: Session -> IO ReadinessMode
checkSessionReadiness session = do
  readiness <- assessResourceReadiness (sessDbPath session)
  pure (computeReadinessMode readiness)

-- | Tokenize predicate text into atoms for ContentSelector initialization.
-- Filters stop words and short words (≤3 chars).
tokenizePredicateForSeed :: T.Text -> S.Set T.Text
tokenizePredicateForSeed text =
  let words = T.words (T.toLower text)
      filtered = filter (\w -> T.length w > 3 && not (isStopWord w)) words
  in S.fromList filtered
  where
    isStopWord w = w `elem`
      [ "это", "есть", "является", "быть", "было", "будет"
      , "и", "или", "но", "а", "в", "на", "с", "по", "для"
      , "что", "как", "когда", "где", "кто", "который", "которая"
      , "не", "ни", "же", "ли", "бы", "то", "так", "только"
      , "может", "могут", "должен", "должна", "должно"
      , "через", "между", "перед", "после", "при", "во", "со"
      , "the", "and", "or", "but", "is", "are", "was", "were"
      , "of", "to", "in", "on", "at", "for", "with", "by"
      , "that", "which", "who", "when", "where", "how"
      ]

-- | Generate a stable, human-readable fallback session identifier.
-- Used when the bootstrap self-blanket reports 'BlanketEmptySession'.
-- Format: @bootstrap-recovery-<utc>-<uuid>@.
generateFallbackSessionId :: IO Text
generateFallbackSessionId = do
  now <- getCurrentTime
  uuid <- UUIDv4.nextRandom
  pure $ T.concat
    [ "bootstrap-recovery-"
    , T.pack (formatTime defaultTimeLocale "%Y%m%dT%H%M%S%Q" now)
    , "-"
    , UUID.toText uuid
    ]

-- | A minimal, valid morphology that guarantees
-- @sbMorphologyTotalSize > 0@. It contains a single surface form
-- mapped to itself so the system can always normalise at least one
-- token. This is the morphology used by 'recoverBootstrapBlanket' when
-- the loaded morphology is completely empty.
minimalMorphologyFallback :: MorphologyData
minimalMorphologyFallback = MorphologyData
  { mdPrepositional = M.empty
  , mdGenitive      = M.empty
  , mdNominative    = M.singleton "qxfx0" "qxfx0"
  , mdFormsBySurface = M.singleton "qxfx0"
      [ LexemeForm
          { lfSurface = "qxfx0"
          , lfLemma   = "qxfx0"
          , lfPOS     = "noun"
          , lfCase    = NominativeCase
          , lfNumber  = SingularNumber
          , lfTier    = CuratedTier
          , lfQuality = 1.0
          }
      ]
  }

-- | Recover a bootstrapped state that fails the initial self-blanket.
-- Currently handles two recoverable violations:
--
--   * 'BlanketEmptySession'      -> generate a fallback session id;
--   * 'BlanketEmptyMorphology'   -> install 'minimalMorphologyFallback'
--                                   and recompute the lemma map.
--
-- After repairs the blanket is recomputed. Remaining (non-recoverable)
-- violations, the repaired state, and the final session id are
-- returned to the caller.
recoverBootstrapBlanket
  :: MorphologyData
  -> SystemState
  -> Text
  -> IO ([BlanketViolation], SystemState, Text)
recoverBootstrapBlanket originalMorphology state sessionIdIn = do
  let initialVs = checkInitialBlanket (computeSelfBlanket state)
  if null initialVs
    then pure ([], state, sessionIdIn)
    else do
      let sessionIdOut
            | BlanketEmptySession `elem` initialVs = Nothing
            | otherwise                            = Just sessionIdIn
          stateWithMorph
            | BlanketEmptyMorphology `elem` initialVs =
                let fallback = minimalMorphologyFallback
                in state
                     { ssMorphology = fallback
                     , ssLemmaMap   = buildLemmaMap fallback
                     }
            | otherwise = state
      recoveredSessionId <- maybe generateFallbackSessionId pure sessionIdOut
      let stateOut = stateWithMorph { ssSessionId = recoveredSessionId }
          remainingVs = checkInitialBlanket (computeSelfBlanket stateOut)
      unless (null remainingVs) $ do
        Log.logWarn "Bootstrap blanket recovery attempted but violations remain"
          (Log.addContext "violations" (renderBlanketViolations remainingVs) Log.emptyContext)
      when (BlanketEmptySession `elem` initialVs) $ do
        Log.logWarn "Generated fallback session id during bootstrap blanket recovery"
          (Log.addContext "fallback_session_id" recoveredSessionId Log.emptyContext)
      when (BlanketEmptyMorphology `elem` initialVs) $ do
        Log.logWarn "Installed minimal morphology fallback during bootstrap blanket recovery"
          (Log.addContext "original_morphology_size"
             (T.pack $ show $ M.size (mdNominative originalMorphology)
                       + M.size (mdGenitive originalMorphology)
                       + M.size (mdPrepositional originalMorphology)
                       + M.size (mdFormsBySurface originalMorphology))
             Log.emptyContext)
      pure (remainingVs, stateOut, recoveredSessionId)
