{-# LANGUAGE OverloadedStrings #-}

module CLI.AutonomousSmoke
  ( runAutonomousSmoke
  , runAutonomousFor
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (bracket, bracket_, finally, onException)
import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Exit (exitFailure)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.IO (hPutStrLn, stderr, stdout, hFlush)
import Data.Time.Clock (UTCTime, getCurrentTime)

import qualified QxFx0.Runtime as Runtime
import qualified QxFx0.Runtime.AutonomousSmoke as SmokeIsolation
import qualified QxFx0.Semantic.Network as Network
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Bridge.SQLite as SQLite
import qualified Data.Map.Strict as M
import QxFx0.Semantic.Content.AtomStore (atomStore)
import QxFx0.Learning.Autonomous (autonomousApplyLLMResponse, buildAtomMorphology)
import QxFx0.Learning.SeedVerify (verifyDiscoveredEdges)
import QxFx0.Semantic.Ontology.Philosophy (philosophySeedNetwork)
import QxFx0.Types.State (SystemState(..), ssSemanticNetwork)
import QxFx0.Runtime.Session (sessRuntime, sessSystemState)
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , LearningEventSource(..)
  , ensureLearningEventsSchema
  , insertLearningEventsOnConnection
  )
import qualified QxFx0.Bridge.SemanticNetwork.RuntimeProjection as RuntimeProjection
import qualified QxFx0.Semantic.LLMDiscovery as LLMDiscovery (buildDiscoveryPrompt)
import qualified QxFx0.Bridge.ExternalLLM as ExternalLLM
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Tool (ExternalTool(..), ToolDomain(..))
import QxFx0.Semantic.Network.Types (SemanticEdge(..))
import QxFx0.Bridge.SemanticNetwork.RuntimeProjection (namespaceText)
import QxFx0.Learning.Quarantine (provenanceText)
import QxFx0.Runtime.Session.Bootstrap
  ( readAutonomousLearningAuditInterval
  , readAutonomousLearningEnabled
  )
import QxFx0.ExceptionPolicy
  ( mkRuntimeInitError
  , mkSQLiteError
  , throwQxFx0
  )

-- | Keep the unattended worker alive for a bounded wall-clock duration.
-- Bootstrap owns the audit, worker, and governed apply threads; its bracket
-- closes them and their SQLite storage in the correct order on return.
runAutonomousFor :: Int -> Text -> IO ()
runAutonomousFor seconds sessionId = do
  enabled <- readAutonomousLearningEnabled
  auditInterval <- readAutonomousLearningAuditInterval
  if seconds <= 0
    then do
      hPutStrLn stderr "Error: --autonomous-run duration must be a positive number of seconds"
      exitFailure
    else if not enabled || auditInterval <= 0
      then do
        hPutStrLn stderr "Error: autonomous run requires QXFX0_AUTONOMOUS_LEARNING=1 and QXFX0_LEARNING_AUDIT_INTERVAL_SEC>0"
        exitFailure
      else Runtime.withBootstrappedSession True sessionId $ \_ -> do
        T.putStrLn $ "[autonomous-run] running for " <> T.pack (show seconds)
          <> " second(s); audit interval=" <> T.pack (show auditInterval)
        waitSeconds seconds
        T.putStrLn "[autonomous-run] duration reached; stopping cleanly"
  where
    -- threadDelay takes Int microseconds, so wait in minute-sized chunks and
    -- safely support multi-hour runs on every supported architecture.
    waitSeconds 0 = pure ()
    waitSeconds remaining = do
      let chunk = min 60 remaining
      threadDelay (chunk * 1000 * 1000)
      waitSeconds (remaining - chunk)

runAutonomousSmoke :: Text -> Text -> IO ()
runAutonomousSmoke topic sessionId = do
  smokeDbResult <- SmokeIsolation.resolveAutonomousSmokeDbPath
  smokeDbPath <- case smokeDbResult of
    Left err -> do
      hPutStrLn stderr ("Error: " <> T.unpack err)
      exitFailure
    Right path -> pure path
  hPutStrLn stderr $ "[autonomous-smoke] isolated database: " <> smokeDbPath
  withEnvValue "QXFX0_DB" smokeDbPath $
    withEnvValue "QXFX0_AUTONOMOUS_LEARNING" "0" $
      Runtime.withBootstrappedSession True sessionId $ \session -> do
    let runtime = sessRuntime session
        systemState = sessSystemState session
        network = ssSemanticNetwork systemState

    -- Run initial turn to establish baseline
    hPutStrLn stderr "[autonomous-smoke] About to run initial turn..."
    (session1, response) <- Runtime.runTurnInSession session topic
    hPutStrLn stderr "[autonomous-smoke] runTurn OK"
    let updatedState0 = sessSystemState session1
    T.putStrLn $ "Initial turn for topic: " <> topic
    T.putStrLn $ "Response: " <> response

    -- Synchronous discovery keeps this CLI smoke deterministic.  The normal
    -- runtime exercises the equivalent candidate path through its background
    -- worker and between-turn governed apply.
    T.putStrLn "[autonomous-smoke] About to discoverAndApply..."
    hFlush stdout
    discoveredNetwork <- discoverAndApply topic network
    T.putStrLn "[autonomous-smoke] discoverAndApply OK"
    hFlush stdout
    T.putStrLn $ "[autonomous-smoke] discoveredNetwork edges: " <> T.pack (show (M.size (Network.snEdges discoveredNetwork)))
    hFlush stdout
    let newEdges = SmokeIsolation.newSemanticEdges network discoveredNetwork
        updatedState = updatedState0 { ssSemanticNetwork = discoveredNetwork }
        updatedNetwork = ssSemanticNetwork updatedState
    hPutStrLn stderr $ "[autonomous-smoke] newEdges count: " <> show (length newEdges)
    hFlush stderr

    when (null newEdges) $ do
      T.putStrLn "No new edges added in initial turn"
      hFlush stdout

    -- The smoke projection is append-only for edges absent from the baseline.
    hPutStrLn stderr $ "[autonomous-smoke] Discovered " <> show (length newEdges) <> " genuinely new edges"
    case newEdges of
      firstEdge : _ -> do
        hPutStrLn stderr $ "[autonomous-smoke] First edge: " <> T.unpack (seFrom firstEdge) <> " -> " <> T.unpack (seTo firstEdge)
        hPutStrLn stderr $ "[autonomous-smoke]   provenance: " <> T.unpack (provenanceText (seProvenance firstEdge))
        hPutStrLn stderr $ "[autonomous-smoke]   namespace: " <> maybe "Nothing" (T.unpack . namespaceText) (seNamespace firstEdge)
        hFlush stderr
      [] -> pure ()
    persistEdgesToRuntime smokeDbPath sessionId newEdges

    -- Run second turn using the enriched network
    (session2, feedbackResponse) <- Runtime.runTurnInSession
      (session1 { sessSystemState = updatedState })
      topic
    let finalState = sessSystemState session2
    T.putStrLn $ "Feedback turn response: " <> feedbackResponse
    hFlush stdout

    when (Network.snEdges updatedNetwork == Network.snEdges (ssSemanticNetwork finalState)) $ do
      T.putStrLn "No edge reinforcement applied"
      hFlush stdout

    T.putStrLn "Final state persisted by the feedback turn"

discoverAndApply :: Text -> Network.SemanticNetwork -> IO Network.SemanticNetwork
discoverAndApply topic network =
  bracket ExternalLLM.buildTransportFromEnv ExternalLLM.closeOwnedTransport $ \transport -> do
  let tool = ExternalTool
        { etName        = "llm-discovery"
        , etDomain      = DomainKeyword
        , etReliability = 0.7
        , etValidatable = False
        }
      need = NeedKeywordEnrichment
      prompt = LLMDiscovery.buildDiscoveryPrompt topic
      morph = buildAtomMorphology atomStore
  T.putStrLn $ "Discovering relations for: " <> topic
  hFlush stdout
  result <- ExternalLLM.queryExternalTool transport tool need prompt
  case result of
    Left err -> do
      hPutStrLn stderr $ "Discovery query failed: " <> show err
      hFlush stderr
      throwSmokeRuntime ("discovery provider failed: " <> T.pack (show err))
    Right resp -> do
      let rawNet = autonomousApplyLLMResponse atomStore morph need resp
          net = verifyDiscoveredEdges philosophySeedNetwork rawNet
          edges = M.elems (Network.snEdges net)
      T.putStrLn $ "Found " <> T.pack (show (length edges)) <> " candidate relation(s):"
      hFlush stdout
      mapM_ (\e -> T.putStrLn $ "  " <> seFrom e <> " -> " <> seTo e) edges
      hFlush stdout
      pure (Network.mergeSemanticNetworks network net)

persistEdgesToRuntime :: FilePath -> Text -> [SemanticEdge] -> IO ()
persistEdgesToRuntime _ _ [] = pure ()
persistEdgesToRuntime dbPath sessionId edges = do
  mDb <- NSQL.open dbPath
  case mDb of
    Left err -> throwSmokeSql ("cannot open database: " <> err)
    Right db -> flip finally (NSQL.close db) $ do
      let dbWrapper = SQLite.QxFx0DB dbPath db
      hPutStrLn stderr "[autonomous-smoke] Starting DB setup..."
      Runtime.ensureSchemaMigrations db
      hPutStrLn stderr "[autonomous-smoke] ensureSchemaMigrations OK"
      RuntimeProjection.ensureRuntimeProjectionSchema dbWrapper
      hPutStrLn stderr "[autonomous-smoke] ensureRuntimeProjectionSchema OK"
      ensureLearningEventsSchema dbWrapper
      hPutStrLn stderr "[autonomous-smoke] ensureLearningEventsSchema OK"
      now <- getCurrentTime
      let events = map (edgeToDiscoveryEvent now sessionId "autonomous-smoke") edges
      hPutStrLn stderr "[autonomous-smoke] Persisting learning events and edges..."
      begun <- NSQL.execSql db "BEGIN IMMEDIATE;"
      either throwSmokeSql pure begun
      let rollback = do
            _ <- NSQL.execSql db "ROLLBACK;"
            pure ()
      (do
          insertLearningEventsOnConnection db events
          RuntimeProjection.persistRuntimeEdgesOnConnection db sessionId edges
          committed <- NSQL.execSql db "COMMIT;"
          either throwSmokeSql pure committed
        ) `onException` rollback
      hPutStrLn stderr "[autonomous-smoke] Learning events and edges persisted OK"
      T.putStrLn $ "Persisted " <> T.pack (show (length edges)) <> " edge(s) to runtime projection."
      hFlush stdout

withEnvValue :: String -> String -> IO a -> IO a
withEnvValue key value action = do
  previous <- lookupEnv key
  let restore = maybe (unsetEnv key) (setEnv key) previous
  bracket_ (setEnv key value) restore action

throwSmokeRuntime :: Text -> IO a
throwSmokeRuntime detail =
  throwQxFx0 (mkRuntimeInitError
    "autonomous_smoke"
    "external_discovery"
    "AUTONOMOUS_SMOKE_PROVIDER_ERROR"
    (M.singleton "detail" detail))

throwSmokeSql :: Text -> IO a
throwSmokeSql detail =
  throwQxFx0 (mkSQLiteError
    "autonomous_smoke"
    "AUTONOMOUS_SMOKE_SQLITE_ERROR"
    (M.singleton "detail" detail))

edgeToDiscoveryEvent :: UTCTime -> Text -> Text -> SemanticEdge -> LearningEvent
edgeToDiscoveryEvent now sessionId topic edge = LearningEvent
  { leTimestamp    = now
  , leSessionId    = Just sessionId
  , leTurnSeq      = Nothing
  , leRequestId    = "autonomous-smoke-" <> seFrom edge <> "-" <> seTo edge
  , leTopic        = topic
  , leKind         = EdgeAdmitted
  , leSource       = LesAutonomousApply
  , leEdgeFrom     = Just (seFrom edge)
  , leEdgeTo       = Just (seTo edge)
  , leProvenance   = Just (seProvenance edge)
  , leConfidence   = Just (seConfidence edge)
  , leCoOccurrence = Just (seCoOccurrence edge)
  , leReason       = Just "autonomous LLM discovery"
  , lePromptHash   = Nothing
  , leResponseHash = Nothing
  , leModel = Nothing
  , leParserDecision = Nothing
  , leAdmissionDecision = Just "smoke_runtime_admitted"
  , leEvidenceSource = Just "autonomous_smoke"
  , leEdgeNamespace = seNamespace edge
  , leEdgeOwner = Just sessionId
  }
