{-# LANGUAGE OverloadedStrings #-}

module CLI.AutonomousSmoke
  ( runAutonomousSmoke
  ) where

import Control.Exception (SomeException, catch, try)
import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr, stdout, hFlush)
import Data.Time.Clock (UTCTime, getCurrentTime)

import qualified QxFx0.Runtime as Runtime
import qualified QxFx0.Semantic.Network as Network
import qualified QxFx0.Bridge.StatePersistence as StatePersistence
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
  , recordLearningEventsOnConnection
  )
import qualified QxFx0.Semantic.Network.RuntimeProjection as RuntimeProjection
import qualified QxFx0.Semantic.LLMDiscovery as LLMDiscovery (buildDiscoveryPrompt)
import qualified QxFx0.Bridge.ExternalLLM as ExternalLLM
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Tool (ExternalTool(..), ToolDomain(..))
import QxFx0.Semantic.Network.Types (SemanticEdge(..))
import QxFx0.Semantic.Network.RuntimeProjection (namespaceText)
import QxFx0.Learning.Quarantine (provenanceText)

runAutonomousSmoke :: Text -> Text -> IO ()
runAutonomousSmoke topic sessionId = do
  Runtime.withBootstrappedSession True sessionId $ \session -> do
    let runtime = sessRuntime session
        systemState = sessSystemState session
        network = ssSemanticNetwork systemState

    -- Run initial turn to establish baseline
    hPutStrLn stderr "[autonomous-smoke] About to run initial turn..."
    output <- Runtime.runTurn runtime systemState topic sessionId
    hPutStrLn stderr "[autonomous-smoke] runTurn OK"
    let (updatedState0, response) = output
    T.putStrLn $ "Initial turn for topic: " <> topic
    T.putStrLn $ "Response: " <> response

    -- Synchronous autonomous discovery: ask the LLM for related relations
    -- and apply them immediately in the main thread.  This avoids the
    -- background-worker concurrency path that currently segfaults when it
    -- races with main-thread SQLite access.
    T.putStrLn "[autonomous-smoke] About to discoverAndApply..."
    hFlush stdout
    discoveredNetwork <- discoverAndApply topic network
    T.putStrLn "[autonomous-smoke] discoverAndApply OK"
    hFlush stdout
    T.putStrLn $ "[autonomous-smoke] discoveredNetwork edges: " <> T.pack (show (M.size (Network.snEdges discoveredNetwork)))
    hFlush stdout
    let allDiscoveredEdges = M.elems (Network.snEdges discoveredNetwork)
        newEdges = filter (\e -> not (M.member (seFrom e, seTo e) (Network.snEdges network)))
                              allDiscoveredEdges
        updatedState = updatedState0 { ssSemanticNetwork = discoveredNetwork }
        updatedNetwork = ssSemanticNetwork updatedState
    hPutStrLn stderr $ "[autonomous-smoke] allDiscoveredEdges count: " <> show (length allDiscoveredEdges)
    hPutStrLn stderr $ "[autonomous-smoke] newEdges count: " <> show (length newEdges)
    hFlush stderr

    when (null newEdges) $ do
      T.putStrLn "No new edges added in initial turn"
      hFlush stdout

    -- Persist ALL discovered edges to the runtime projection table
    -- (including those already in seed for reinforcement)
    hPutStrLn stderr $ "[autonomous-smoke] Discovered " <> show (length allDiscoveredEdges) <> " edges"
    when (not (null allDiscoveredEdges)) $ do
      let firstEdge = head allDiscoveredEdges
      hPutStrLn stderr $ "[autonomous-smoke] First edge: " <> T.unpack (seFrom firstEdge) <> " -> " <> T.unpack (seTo firstEdge)
      hPutStrLn stderr $ "[autonomous-smoke]   provenance: " <> T.unpack (provenanceText (seProvenance firstEdge))
      hPutStrLn stderr $ "[autonomous-smoke]   namespace: " <> maybe "Nothing" (T.unpack . namespaceText) (seNamespace firstEdge)
      hFlush stderr
    persistEdgesToRuntime Runtime.resolveDbPath allDiscoveredEdges

    -- Run second turn using the enriched network
    feedbackOutput <- Runtime.runTurn runtime updatedState topic sessionId
    let (finalState, feedbackResponse) = feedbackOutput
    T.putStrLn $ "Feedback turn response: " <> feedbackResponse
    hFlush stdout

    when (Network.snEdges updatedNetwork == Network.snEdges (ssSemanticNetwork finalState)) $ do
      T.putStrLn "No edge reinforcement applied"
      hFlush stdout

    -- Save final state
    hPutStrLn stderr "[autonomous-smoke] About to save state..."
    saveResultE <- try (StatePersistence.saveState (Runtime.withRuntimeDb runtime) finalState sessionId)
    case saveResultE of
      Left e -> do
        hPutStrLn stderr $ "[autonomous-smoke] saveState failed: " <> show (e :: SomeException)
        hFlush stderr
        exitFailure
      Right saveResult ->
        case saveResult of
          Right _ -> T.putStrLn "Final state persisted"
          Left err -> do
            hPutStrLn stderr $ "Failed to persist state: " <> show err
            hFlush stderr
            exitFailure

discoverAndApply :: Text -> Network.SemanticNetwork -> IO Network.SemanticNetwork
discoverAndApply topic network = do
  transport <- ExternalLLM.buildTransportFromEnv
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
      pure network
    Right resp -> do
      let rawNet = autonomousApplyLLMResponse atomStore morph need resp
          net = verifyDiscoveredEdges philosophySeedNetwork rawNet
          edges = M.elems (Network.snEdges net)
      T.putStrLn $ "Found " <> T.pack (show (length edges)) <> " candidate relation(s):"
      hFlush stdout
      mapM_ (\e -> T.putStrLn $ "  " <> seFrom e <> " -> " <> seTo e) edges
      hFlush stdout
      pure (Network.mergeSemanticNetworks network net)

persistEdgesToRuntime :: IO FilePath -> [SemanticEdge] -> IO ()
persistEdgesToRuntime resolveDbPath edges = do
  dbPath <- resolveDbPath
  mDb <- NSQL.open dbPath
  case mDb of
    Left err -> hPutStrLn stderr $ "Cannot open database: " <> T.unpack err
    Right db -> do
      let dbWrapper = SQLite.QxFx0DB dbPath db
      hPutStrLn stderr "[autonomous-smoke] Starting DB setup..."
      Runtime.ensureSchemaMigrations db `catch` \e ->
        hPutStrLn stderr $ "[autonomous-smoke] ensureSchemaMigrations failed: " <> show (e :: SomeException)
      hPutStrLn stderr "[autonomous-smoke] ensureSchemaMigrations OK"
      RuntimeProjection.ensureRuntimeProjectionSchema dbWrapper `catch` \e ->
        hPutStrLn stderr $ "[autonomous-smoke] ensureRuntimeProjectionSchema failed: " <> show (e :: SomeException)
      hPutStrLn stderr "[autonomous-smoke] ensureRuntimeProjectionSchema OK"
      ensureLearningEventsSchema dbWrapper `catch` \e ->
        hPutStrLn stderr $ "[autonomous-smoke] ensureLearningEventsSchema failed: " <> show (e :: SomeException)
      hPutStrLn stderr "[autonomous-smoke] ensureLearningEventsSchema OK"
      now <- getCurrentTime
      let events = map (edgeToDiscoveryEvent now "autonomous-smoke") edges
      hPutStrLn stderr "[autonomous-smoke] About to record learning events..."
      recordLearningEventsOnConnection db events
      hPutStrLn stderr "[autonomous-smoke] Learning events recorded OK"
      hPutStrLn stderr "[autonomous-smoke] About to persist edges..."
      RuntimeProjection.persistRuntimeEdges dbWrapper edges
      hPutStrLn stderr "[autonomous-smoke] Edges persisted OK"
      NSQL.close db
      T.putStrLn $ "Persisted " <> T.pack (show (length edges)) <> " edge(s) to runtime projection."
      hFlush stdout

edgeToDiscoveryEvent :: UTCTime -> Text -> SemanticEdge -> LearningEvent
edgeToDiscoveryEvent now topic edge = LearningEvent
  { leTimestamp    = now
  , leSessionId    = Just "autonomous_smoke_test"
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
  }
