{-# LANGUAGE OverloadedStrings #-}

module CLI where

import CLI.Health (handleHealthcheck)
import CLI.Health (handleRuntimeReady)
import CLI.Http (handleServeHttp)
import CLI.Protocol (RuntimeOutputMode(..))
import CLI.State (handleStateJson)
import CLI.Turn (runTurnJson)
import CLI.Worker (runWorkerStdio)
import CLI.AutonomousSmoke (runAutonomousFor, runAutonomousSmoke)
import QxFx0.Learning.Autonomous (auditHistoricalSelectorPreflight)
import QxFx0.Learning.CorroborationQueue (ensureCorroborationTaskSchema)
import QxFx0.Learning.Events (ensureLearningEventsSchema)
import QxFx0.Learning.JobQueue (ensureLearningJobSchema)
import QxFx0.Learning.Quarantine (ensureQuarantineSchema)

import QxFx0.Learning.Tuning (runCorpusTuning)

import Control.Monad (when, forM_)
import Data.Aeson (encode)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Render.Text (textShow)
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs, setEnv, lookupEnv)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory)
import System.IO (BufferMode(..), hPutStrLn, hSetBuffering, stderr, stdout)
import qualified Data.ByteString.Lazy.Char8 as BLC
import Control.Exception (finally)
import Text.Read (readMaybe)

import qualified QxFx0.Bridge.EmbeddedSQLSync as EmbeddedSQLSync
import qualified QxFx0.Runtime as Runtime
import qualified QxFx0.Resources as Resources
import qualified QxFx0.Bridge.StatePersistence as StatePersistence
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Semantic.SelfPlay as SelfPlay
import qualified QxFx0.Semantic.LLMDiscovery as LLMDiscovery
import qualified QxFx0.Semantic.Content.AtomStore as AtomStore
import qualified QxFx0.Semantic.Content.PathFinder as PathFinder
import QxFx0.Semantic.Content.PathFinder (defaultFieldProfile)
import Data.List (partition)
import QxFx0.CLI.Parser (extractSessionArgs)
import qualified QxFx0.CLI.Ingest as Ingest
import QxFx0.ExceptionPolicy (QxFx0Exception, tryIO, tryQxFx0)
import QxFx0.Types.State (ssMorphology, ssRuntimeGraph, ssTurnCount)
import QxFx0.Types.Persistence (StateVersion(..))
import QxFx0.Bridge.SQLite (QxFx0DB(..))
import qualified QxFx0.Bridge.SemanticNetwork.RuntimeProjection as RuntimeProjection
import QxFx0.Learning.Promotion
  ( PromotionEvaluation(..)
  , PromotionSnapshot(..)
  , activatePromotionOverlay
  , buildPromotionCandidates
  , createDraftOverlay
  , createPromotionSnapshot
  , ensurePromotionSchema
  , recordPromotionHumanRelease
  , rollbackPromotionOverlay
  , runPromotionEvaluation
  , runPromotionGates
  )
import QxFx0.Learning.PromotionRuntime
  ( RuntimePromotionEvaluation
  , runPromotionRuntimeEvaluation
  )
import QxFx0.Learning.PromotionReview
  ( renderPromotionReview
  , renderPromotionRevalidationReport
  )

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  let (debugFlag, restArgs1) = extractDebugFlag args
      (strictFlag, restArgs2) = extractStrictDecodeFlag restArgs1
  when debugFlag $ setEnv "QXFX0_DEBUG_ERRORS" "true"
  when strictFlag $ setEnv "QXFX0_STRICT_DECODE" "true"
  sessionId0 <- Runtime.resolveSessionId
  let (sessionId, finalArgs) = extractSessionArgs sessionId0 restArgs2
  case finalArgs of
    []                        -> interactiveMain sessionId
    ["--help"]                -> Runtime.printHelp >> printMachineHelp
    ["--healthcheck"]         -> handleHealthcheck sessionId
    ["--health"]              -> handleHealthcheck sessionId
    ["--runtime-ready"]       -> handleRuntimeReady
    ["--write-agda-witness"]  -> handleWriteAgdaWitness
    ["--state-json"]          -> handleStateJson sessionId
    ["--worker-stdio"]        -> handleWorkerStdio sessionId
    ("--serve-http":portArgs) -> handleServeHttp sessionId portArgs
    ("--turn-json":textParts) -> handleTurnJson sessionId (filter (/= "--json") textParts)
    ("--input":textParts)     -> handleTurnJson sessionId (filter (/= "--json") textParts)
    ["--json"]                -> handleStateJson sessionId
    ["--init-db-only"]        -> handleInitDb
    ["--init-learning-db-only"] -> handleInitLearningDb
    ["--check-embedded-sql"]  -> handleCheckEmbeddedSql
    ["--sync-embedded-sql"]   -> handleSyncEmbeddedSql
    ("--selfplay":rest)       -> handleSelfPlay sessionId rest
    ("--discover":rest)       -> handleDiscover sessionId rest
    ("--tune-corpus":rest)    -> handleTuneCorpus sessionId rest
    ["--promotion-snapshot"] -> handlePromotionSnapshot
    ["--promotion-candidates", snapshotId] -> handlePromotionCandidates (T.pack snapshotId)
    ["--promotion-gate", snapshotId] -> handlePromotionGates (T.pack snapshotId)
    ["--promotion-draft", snapshotId] -> handlePromotionDraft (T.pack snapshotId)
    ["--promotion-activate", overlayVersion] -> handlePromotionActivate (T.pack overlayVersion)
    ["--promotion-rollback"] -> handlePromotionRollback
    ["--promotion-eval", overlayVersion] -> handlePromotionEvaluation (T.pack overlayVersion)
    ["--promotion-runtime-eval", overlayVersion] -> handlePromotionRuntimeEvaluation (T.pack overlayVersion)
    ["--promotion-release", overlayVersion] -> handlePromotionRelease (T.pack overlayVersion)
    ["--promotion-review", snapshotId, overlayVersion] -> handlePromotionReview (T.pack snapshotId) (T.pack overlayVersion)
    ["--promotion-revalidation-review", snapshotId, priorOverlayVersion] -> handlePromotionRevalidationReview (T.pack snapshotId) (T.pack priorOverlayVersion)
    ["--autonomous-preflight-audit"] -> handleAutonomousPreflightAudit
    ("--autonomous-smoke":rest) -> case rest of
      (topic:_) -> runAutonomousSmoke (T.pack topic) sessionId
      _ -> do
        hPutStrLn stderr "Error: --autonomous-smoke requires a topic name"
        exitFailure
    ("--autonomous-run":rest) -> case rest of
      (secondsText:_) -> case readMaybe secondsText of
        Just seconds -> runAutonomousFor seconds sessionId
        Nothing -> do
          hPutStrLn stderr "Error: --autonomous-run requires an integer duration in seconds"
          exitFailure
      _ -> do
        hPutStrLn stderr "Error: --autonomous-run requires an integer duration in seconds"
        exitFailure
    ("ingest":rest)           -> handleIngest rest
    _                         -> do
      hPutStrLn stderr "Unsupported arguments. Use --help."
      exitFailure

printMachineHelp :: IO ()
printMachineHelp = do
  T.putStrLn ""
  T.putStrLn "Machine flags:"
  T.putStrLn "  --session-id <id>             select isolated runtime session"
  T.putStrLn "  --session <id>               alias for --session-id"
  T.putStrLn "  --healthcheck, --health      emit runtime health JSON"
  T.putStrLn "  --runtime-ready              emit side-effect free runtime readiness JSON"
  T.putStrLn "  --write-agda-witness         persist fresh Agda witness into runtime state dir"
  T.putStrLn "  --state-json                 emit runtime state JSON"
  T.putStrLn "  --json                       alias for --state-json"
  T.putStrLn "  --turn-json <text>           run one dialogue turn, emit JSON"
  T.putStrLn "  --turn-json --semantic <text> run one semantic turn, emit JSON"
  T.putStrLn "  --input <text>               alias for --turn-json"
  T.putStrLn "  --worker-stdio               run as JSON-over-stdio worker"
  T.putStrLn "  --serve-http [port]          start HTTP sidecar"
  T.putStrLn "  --check-embedded-sql         verify EmbeddedSQL.hs matches spec/sql"
  T.putStrLn "  --sync-embedded-sql          rewrite EmbeddedSQL.hs from spec/sql"
  T.putStrLn "  --debug-errors               show full error details (sets QXFX0_DEBUG_ERRORS=true)"
  T.putStrLn "  --strict-decode              fail on missing JSON fields (sets QXFX0_STRICT_DECODE=true)"
  T.putStrLn "  --selfplay [N]               run N self-play iterations (offline graph enrichment)"
  T.putStrLn "  --discover <concept>         discover relations for a concept via LLM (offline)"
  T.putStrLn "  --autonomous-smoke <topic>    run with LLM; requires QXFX0_AUTONOMOUS_SMOKE_DB=/tmp/..."
  T.putStrLn "  --autonomous-run <seconds>    run bounded unattended autonomous learning"
  T.putStrLn "  --autonomous-preflight-audit  annotate legacy selector-preflight rejections"
  T.putStrLn "  --check-schema-consistency   verify cumulative migrations match canonical schema.sql"
  T.putStrLn "  --init-learning-db-only     migrate core, learning, and promotion schemas without starting workers"
  T.putStrLn "  --check-schema-contract      verify runtime schema contract manifest against schema.sql and SchemaContract.hs"
  T.putStrLn "  --tune-corpus [session-id|all]  run corpus-driven calibration tuning"
  T.putStrLn "  --promotion-snapshot            materialize runtime LLM edges for promotion"
  T.putStrLn "  --promotion-candidates <id>     build normalized candidate predicates"
  T.putStrLn "  --promotion-gate <id>           run deterministic promotion gates"
  T.putStrLn "  --promotion-draft <id>          create a versioned draft overlay"
  T.putStrLn "  --promotion-activate <version>  activate an evaluated overlay"
  T.putStrLn "  --promotion-rollback            restore the parent active overlay"
  T.putStrLn "  --promotion-eval <version>      record deterministic overlay evaluation"
  T.putStrLn "  --promotion-runtime-eval <ver>  run isolated renderer A/B evaluation"
  T.putStrLn "  --promotion-release <version>   human-release the latest passing evaluation (does not activate)"
  T.putStrLn "  --promotion-review <snapshot> <overlay>  render a read-only A/B review report"
  T.putStrLn "  --promotion-revalidation-review <snapshot> <prior-overlay>  report a fail-closed revalidation"
  T.putStrLn "  ingest [--relations <path>] [--ontology <path>]"
  T.putStrLn "                              ingest external knowledge and emit a summary"

handleTurnJson :: Text -> [String] -> IO ()
handleTurnJson sessionId args =
  let (mode, inputText) = case args of
        ("--semantic":rest) -> (SemanticIntrospectionMode, T.unwords (map T.pack rest))
        rest                -> (DialogueMode, T.unwords (map T.pack rest))
  in if T.null inputText
     then do
       hPutStrLn stderr "Error: --turn-json requires input text"
       exitFailure
     else do
       response <- runTurnJson sessionId mode inputText
       BLC.putStrLn (encode response)

handleInitDb :: IO ()
handleInitDb = do
  dbPath <- Runtime.resolveDbPath
  createDirectoryIfMissing True (takeDirectory dbPath)
  mDb <- NSQL.open dbPath
  case mDb of
    Left err -> hPutStrLn stderr $ "Cannot open database: " <> T.unpack err
    Right db -> do
       Runtime.ensureSchemaMigrations db
       NSQL.close db
       hPutStrLn stderr $ "DB initialized at: " ++ dbPath

handleInitLearningDb :: IO ()
handleInitLearningDb = do
  dbPath <- Runtime.resolveDbPath
  createDirectoryIfMissing True (takeDirectory dbPath)
  opened <- NSQL.open dbPath
  case opened of
    Left err -> hPutStrLn stderr ("Cannot open database: " <> T.unpack err) >> exitFailure
    Right conn -> do
      let db = QxFx0DB dbPath conn
      migrated <- tryIO (tryQxFx0 $ do
          Runtime.ensureSchemaMigrations conn
          RuntimeProjection.ensureRuntimeProjectionSchema db
          ensureLearningJobSchema db
          ensureLearningEventsSchema db
          ensureCorroborationTaskSchema db
          ensureQuarantineSchema db
          ensurePromotionSchema db
        )
      NSQL.close conn
      case migrated of
        Left err -> do
          hPutStrLn stderr ("Learning schema migration failed: " <> show err)
          exitFailure
        Right (Left err) -> do
          hPutStrLn stderr ("Learning schema migration failed: " <> show err)
          exitFailure
        Right (Right ()) -> hPutStrLn stderr ("Learning schema initialized at: " <> dbPath)

withPromotionDb :: (QxFx0DB -> IO a) -> IO a
withPromotionDb action = do
  dbPath <- Runtime.resolveDbPath
  opened <- NSQL.open dbPath
  case opened of
    Left err -> hPutStrLn stderr ("Cannot open promotion DB: " <> T.unpack err) >> exitFailure
    Right conn -> action (QxFx0DB dbPath conn) `finally` NSQL.close conn

handleAutonomousPreflightAudit :: IO ()
handleAutonomousPreflightAudit = withPromotionDb $ \db -> do
  count <- auditHistoricalSelectorPreflight db
  T.putStrLn $ "audited_selector_preflight_rows=" <> T.pack (show count)

handlePromotionSnapshot :: IO ()
handlePromotionSnapshot = withPromotionDb $ \db -> do
  snapshot <- createPromotionSnapshot db
  T.putStrLn $ "snapshot_id=" <> psSnapshotId snapshot
    <> " edge_count=" <> T.pack (show (psEdgeCount snapshot))

handlePromotionCandidates :: Text -> IO ()
handlePromotionCandidates snapshotId = withPromotionDb $ \db -> do
  count <- buildPromotionCandidates db snapshotId
  T.putStrLn $ "candidates=" <> T.pack (show count)

handlePromotionGates :: Text -> IO ()
handlePromotionGates snapshotId = withPromotionDb $ \db -> do
  eligible <- runPromotionGates db snapshotId
  T.putStrLn $ "eligible_for_draft=" <> T.pack (show eligible)

handlePromotionDraft :: Text -> IO ()
handlePromotionDraft snapshotId = withPromotionDb $ \db -> do
  version <- createDraftOverlay db snapshotId
  T.putStrLn $ "overlay_version=" <> version

handlePromotionActivate :: Text -> IO ()
handlePromotionActivate version = withPromotionDb $ \db -> do
  activatePromotionOverlay db version
  T.putStrLn $ "active_overlay=" <> version

handlePromotionRollback :: IO ()
handlePromotionRollback = withPromotionDb $ \db -> do
  rollbackPromotionOverlay db
  T.putStrLn "overlay rollback complete"

handlePromotionEvaluation :: Text -> IO ()
handlePromotionEvaluation version = withPromotionDb $ \db -> do
  evaluation <- runPromotionEvaluation db version
  T.putStrLn $ "evaluation_id=" <> peEvaluationId evaluation
    <> " baseline_contentful=" <> T.pack (show (peBaselineContentful evaluation))
    <> " candidate_contentful=" <> T.pack (show (peCandidateContentful evaluation))
    <> " baseline_refusals=" <> T.pack (show (peBaselineRefusals evaluation))
    <> " candidate_refusals=" <> T.pack (show (peCandidateRefusals evaluation))
    <> " baseline_conflicts=" <> T.pack (show (peBaselineConflicts evaluation))
    <> " candidate_conflicts=" <> T.pack (show (peCandidateConflicts evaluation))

handlePromotionRuntimeEvaluation :: Text -> IO ()
handlePromotionRuntimeEvaluation version = withPromotionDb $ \db -> do
  evaluation <- runPromotionRuntimeEvaluation db version
  BLC.putStrLn (encode evaluation)

handlePromotionRelease :: Text -> IO ()
handlePromotionRelease version = withPromotionDb $ \db -> do
  evaluationId <- recordPromotionHumanRelease db version "explicit_cli_human_release"
  T.putStrLn $ "released_evaluation=" <> evaluationId <> " overlay_version=" <> version

handlePromotionReview :: Text -> Text -> IO ()
handlePromotionReview snapshotId version = withPromotionDb $ \db -> do
  evaluation <- runPromotionRuntimeEvaluation db version
  report <- renderPromotionReview db snapshotId version evaluation
  T.putStrLn report

handlePromotionRevalidationReview :: Text -> Text -> IO ()
handlePromotionRevalidationReview snapshotId priorOverlayVersion = withPromotionDb $ \db -> do
  report <- renderPromotionRevalidationReport db snapshotId priorOverlayVersion
  T.putStrLn report

handleCheckEmbeddedSql :: IO ()
handleCheckEmbeddedSql = do
  paths <- Resources.resolveResourcePaths
  result <- EmbeddedSQLSync.checkEmbeddedSqlSync paths "src/QxFx0/Bridge/EmbeddedSQL.hs"
  case result of
    Right () -> T.putStrLn "EmbeddedSQL.hs is in sync with spec/sql"
    Left err -> hPutStrLn stderr (T.unpack err) >> exitFailure

handleSyncEmbeddedSql :: IO ()
handleSyncEmbeddedSql = do
  paths <- Resources.resolveResourcePaths
  EmbeddedSQLSync.writeEmbeddedSqlModule paths "src/QxFx0/Bridge/EmbeddedSQL.hs"
  T.putStrLn "wrote src/QxFx0/Bridge/EmbeddedSQL.hs"

handleSelfPlay :: Text -> [String] -> IO ()
handleSelfPlay _sessionId args = do
  apiKey <- lookupEnv "QXFX0_LLM_API_KEY"
  case apiKey of
    Nothing -> do
      hPutStrLn stderr "Error: QXFX0_LLM_API_KEY not set. Self-play requires LLM access."
      exitFailure
    Just key -> do
      let n = case args of
                  (s:_) | Just n' <- readMaybe s -> n'
                  _ -> 10
          config = (SelfPlay.defaultSelfPlayConfig (T.pack key)) { SelfPlay.spIterations = n }
      T.putStrLn $ "Starting self-play: " <> T.pack (show n) <> " iterations"
      Runtime.withBootstrappedSession True _sessionId $ \session -> do
        let ss = Runtime.sessSystemState session
            morph = ssMorphology ss
            graph = ssRuntimeGraph ss
        (results, enrichedGraph) <- SelfPlay.runSelfPlayIterations config morph graph
        let totalAdmitted = length (concatMap SelfPlay.sprAdmittedRelations results)
            avgScore = sum (map SelfPlay.sprScore results) / fromIntegral (length results)
            enrichedState = ss { ssRuntimeGraph = enrichedGraph }
        T.putStrLn $ "Self-play complete: " <> T.pack (show totalAdmitted) <> " relations admitted"
        T.putStrLn $ "Average score: " <> T.pack (show avgScore)
        forM_ results $ \r -> do
          T.putStrLn $ "  Q: " <> SelfPlay.sprQuestion r
          T.putStrLn $ "    Score: " <> T.pack (show (SelfPlay.sprScore r))
          T.putStrLn $ "    Admitted: " <> T.pack (show (length (SelfPlay.sprAdmittedRelations r)))
        let observedVersion = StateVersion
              (Runtime.sessStateRevision session)
              (ssTurnCount (Runtime.sessSystemState session))
        saveResult <- StatePersistence.saveStateExpected
          (Runtime.withRuntimeDb (Runtime.sessRuntime session))
          enrichedState
          _sessionId
          observedVersion
        case saveResult of
          Right _ -> T.putStrLn "Enriched graph persisted to session."
          Left err -> hPutStrLn stderr $ "Failed to persist enriched graph: " <> show err

handleTuneCorpus :: Text -> [String] -> IO ()
handleTuneCorpus defaultSessionId args =
  let mTarget = case args of
        []             -> Just defaultSessionId
        ["all"]        -> Nothing
        (sid:_)        -> Just (T.pack sid)
  in Runtime.withBootstrappedSession True defaultSessionId $ \session -> do
       let dbRunner = Runtime.withRuntimeDb (Runtime.sessRuntime session)
           mSessionId = case args of
             ["all"] -> Nothing
             _       -> mTarget
       outcome <- runCorpusTuning dbRunner mSessionId
       BLC.putStrLn (encode outcome)

handleDiscover :: Text -> [String] -> IO ()
handleDiscover _sessionId args =
  case args of
    [] -> do
      hPutStrLn stderr "Error: --discover requires a concept name"
      exitFailure
    (concept:_) -> do
      apiKey <- lookupEnv "QXFX0_LLM_API_KEY"
      case apiKey of
        Nothing -> do
          hPutStrLn stderr "Error: QXFX0_LLM_API_KEY not set. Discovery requires LLM access."
          exitFailure
        Just key -> do
          let config = LLMDiscovery.defaultLLMConfig (T.pack key)
          T.putStrLn $ "Discovering relations for: " <> T.pack concept
          relations <- LLMDiscovery.discoverFromLLM config (T.pack concept)
          T.putStrLn $ "Found " <> T.pack (show (length relations)) <> " candidate relations:"
          forM_ relations $ \r -> do
            T.putStrLn $ "  " <> AtomStore.relRuOriginal r
              <> " [" <> T.pack (show (AtomStore.relType r)) <> "]"

handleIngest :: [String] -> IO ()
handleIngest args =
  case Ingest.parseIngestArgs args of
    Nothing -> do
      hPutStrLn stderr "Error: ingest expects [--relations <path>] [--ontology <path>] [--selfplay <path>]"
      exitFailure
    Just opts -> do
      outcome <- Ingest.runIngest opts
      case outcome of
        Left err -> do
          hPutStrLn stderr (T.unpack err)
          exitFailure
        Right summary -> T.putStrLn (Ingest.formatIngestSummary summary)

handleWorkerStdio :: Text -> IO ()
handleWorkerStdio sessionId = runWorkerStdio sessionId

handleWriteAgdaWitness :: IO ()
handleWriteAgdaWitness = do
  result <- tryQxFx0 Runtime.writeAgdaWitness
  case result of
    Right witnessPath -> T.putStrLn (T.pack witnessPath)
    Left err -> do
      hPutStrLn stderr $ "Error writing Agda witness: " ++ show (err :: QxFx0Exception)
      exitFailure

interactiveMain :: Text -> IO ()
interactiveMain sessionId =
  Runtime.withBootstrappedSession False sessionId $ \session -> do
    T.putStrLn ""
    T.putStrLn "QxFx0 - Flagship Philosophical Dialogue System"
    T.putStrLn "Semantic.Logic routing + threshold intuition + meaning graph + dream rewiring"
    T.putStrLn "Commands: :help, :state, :dialogue, :semantic, :quit"
    T.putStrLn $ "Session: " <> Runtime.sessSessionId session
    T.putStrLn $ "State: " <> textShow (Runtime.sessStateOrigin session)
    Runtime.loop session

-- | Extract --debug-errors flag from args. Sets QXFX0_DEBUG_ERRORS env var
-- which enables detailed error output in the logging layer.
extractDebugFlag :: [String] -> (Bool, [String])
extractDebugFlag args =
  let (flags, rest) = partition (== "--debug-errors") args
  in (not (null flags), rest)

-- | Extract --strict-decode flag from args. Sets QXFX0_STRICT_DECODE env var
-- which enforces strict JSON validation (no .:? .!= defaults) for persisted
-- state blobs. Missing required fields cause decode failure instead of
-- silent defaults.
extractStrictDecodeFlag :: [String] -> (Bool, [String])
extractStrictDecodeFlag args =
  let (flags, rest) = partition (== "--strict-decode") args
  in (not (null flags), rest)
