{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.RuntimeProjection
  ( runtimeProjectionTests
  ) where

import Control.Exception (bracket_)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime(..))
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import Test.HUnit

import QxFx0.Bridge.SQLite (QxFx0DB(..))
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )
import QxFx0.Bridge.SemanticNetwork.RuntimeProjection
  ( applyProjectionDelta
  , ensureRuntimeProjectionSchema
  , loadRuntimeEdgeProjection
  , persistRuntimeEdge
  , persistRuntimeEdges
  , rebuildLearningProjection
  )
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , LearningEventSource(..)
  )
import Test.Support (freshTestDbPath, removeIfExists)

mkEdge :: Text -> Text -> EdgeProvenance -> RelationType -> Double -> Int -> SemanticEdge
mkEdge from to prov rel conf cooc = SemanticEdge
  { seFrom = from
  , seTo = to
  , seWeight = conf
  , seCoOccurrence = cooc
  , seSource = ExplicitEdge
  , seRelationType = Just rel
  , seDomain = Nothing
  , seTemporalScope = Nothing
  , seVerb = Nothing
  , seRationale = Nothing
  , seCounter = Nothing
  , seSynthesis = Nothing
  , seConfidence = conf
  , seProvenance = prov
  , seNamespace = Just NamespaceSessionLocal
  , seLineage = Nothing
  }

mkNetwork :: [SemanticEdge] -> SemanticNetwork
mkNetwork edges = SemanticNetwork
  { snNodes = mempty
  , snEdges = M.fromList [((seFrom e, seTo e), e) | e <- edges]
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = mempty
  }

testRoundTrip :: Test
testRoundTrip = TestLabel "runtime projection round-trip" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_runtime_projection.db"
  let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  cleanup
  connResult <- NSQL.open dbPath
  conn <- case connResult of
    Left err -> assertFailure ("failed to open test db: " ++ T.unpack err) >> undefined
    Right c -> pure c
  let db = QxFx0DB dbPath conn
  ensureRuntimeProjectionSchema db
  let edge1 = mkEdge "свобода" "долг" ProvenanceRuntimeLLM RelRequires 0.6 1
      edge2 = mkEdge "свобода" "выбор" ProvenanceRuntimeLLM RelPresupposes 0.7 2
  persistRuntimeEdges db "session-a" [edge1, edge2]
  loaded <- loadRuntimeEdgeProjection db "session-a"
  NSQL.close conn
  cleanup
  assertEqual "two edges persisted" 2 (M.size loaded)
  assertEqual "first edge faithful" (Just edge1) (M.lookup ("свобода", "долг") loaded)
  assertEqual "second edge faithful" (Just edge2) (M.lookup ("свобода", "выбор") loaded)

testSeedWins :: Test
testSeedWins = TestLabel "seed edges win on overlap" $ TestCase $ do
  let seedEdge = mkEdge "свобода" "долг" ProvenanceCurated RelRequires 0.9 1
      runtimeEdge = mkEdge "свобода" "долг" ProvenanceRuntimeLLM RelNegates 0.6 2
      seedNet = mkNetwork [seedEdge]
      runtimeDelta = M.fromList [(("свобода", "долг"), runtimeEdge)]
      merged = applyProjectionDelta runtimeDelta seedNet
  assertEqual "seed edge preserved" (Just seedEdge) (M.lookup ("свобода", "долг") (snEdges merged))

testNovelEdgesAdded :: Test
testNovelEdgesAdded = TestLabel "novel runtime edges added" $ TestCase $ do
  let seedEdge = mkEdge "свобода" "долг" ProvenanceCurated RelRequires 0.9 1
      runtimeEdge = mkEdge "свобода" "выбор" ProvenanceRuntimeLLM RelPresupposes 0.6 2
      seedNet = mkNetwork [seedEdge]
      runtimeDelta = M.fromList [(("свобода", "выбор"), runtimeEdge)]
      merged = applyProjectionDelta runtimeDelta seedNet
  assertEqual "seed edge preserved" (Just seedEdge) (M.lookup ("свобода", "долг") (snEdges merged))
  assertEqual "runtime edge added" (Just runtimeEdge) (M.lookup ("свобода", "выбор") (snEdges merged))

mkLearningEvent :: LearningEventKind -> Text -> Text -> Double -> Int -> LearningEvent
mkLearningEvent kind from to conf cooc = LearningEvent
  { leTimestamp    = posixSecondsToUTCTime 0
  , leSessionId    = Nothing
  , leTurnSeq      = Nothing
  , leRequestId    = "req-1"
  , leTopic        = "test"
  , leKind         = kind
  , leSource       = LesAutonomousApply
  , leEdgeFrom     = Just from
  , leEdgeTo       = Just to
  , leProvenance   = Just ProvenanceRuntimeLLM
  , leConfidence   = Just conf
  , leCoOccurrence = Just cooc
  , leReason       = Nothing
  , lePromptHash   = Nothing
  , leResponseHash = Nothing
  , leModel = Nothing
  , leParserDecision = Nothing
  , leAdmissionDecision = Nothing
  , leEvidenceSource = Nothing
  , leEdgeNamespace = Just NamespaceSessionLocal
  , leEdgeOwner = Nothing
  }

testReplayEmpty :: Test
testReplayEmpty = TestLabel "replay empty events" $ TestCase $ do
  let delta = rebuildLearningProjection []
  assertEqual "empty delta" M.empty delta

testReplayAdmit :: Test
testReplayAdmit = TestLabel "replay admit inserts edge" $ TestCase $ do
  let events = [mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1]
      delta = rebuildLearningProjection events
  assertEqual "one edge" 1 (M.size delta)
  assertBool "edge exists" (M.member ("свобода", "долг") delta)

testReplayCorroboration :: Test
testReplayCorroboration = TestLabel "replay corroboration increments edge support" $ TestCase $ do
  let events =
        [ mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1
        , mkLearningEvent EdgeCorroborated "свобода" "долг" 0.6 2
        ]
      delta = rebuildLearningProjection events
  case M.lookup ("свобода", "долг") delta of
    Nothing -> assertFailure "edge missing"
    Just edge -> assertEqual "corroboration increments co-occurrence" 2 (seCoOccurrence edge)

testReplayTargetedConflictPreservesAdmittedEdge :: Test
testReplayTargetedConflictPreservesAdmittedEdge =
  TestLabel "replay targeted conflict keeps the admitted target" $ TestCase $ do
    let admitted = mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1
        conflict = (mkLearningEvent EdgeQuarantined "свобода" "долг" 0.6 1)
          { leEvidenceSource = Just "candidate_targeted_corroboration" }
        delta = rebuildLearningProjection [admitted, conflict]
    assertBool "incoming conflict does not erase admitted edge" (M.member ("свобода", "долг") delta)

testReplayReject :: Test
testReplayReject = TestLabel "replay reject removes edge" $ TestCase $ do
  let events =
        [ mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1
        , mkLearningEvent EdgeRejected "свобода" "долг" 0.6 1
        ]
      delta = rebuildLearningProjection events
  assertEqual "edge removed" M.empty delta

testReplayQuarantine :: Test
testReplayQuarantine = TestLabel "replay quarantine removes edge" $ TestCase $ do
  let events =
        [ mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1
        , mkLearningEvent EdgeQuarantined "свобода" "долг" 0.6 1
        ]
      delta = rebuildLearningProjection events
  assertEqual "edge removed" M.empty delta

testReplayPositiveFeedback :: Test
testReplayPositiveFeedback = TestLabel "replay positive feedback boosts confidence" $ TestCase $ do
  let events =
        [ mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1
        , mkLearningEvent RuntimeFeedbackPositive "свобода" "долг" 0.6 1
        ]
      delta = rebuildLearningProjection events
  case M.lookup ("свобода", "долг") delta of
    Nothing -> assertFailure "edge missing"
    Just edge -> assertBool "confidence boosted" (seConfidence edge > 0.6)

testReplayNegativeFeedback :: Test
testReplayNegativeFeedback = TestLabel "replay negative feedback lowers confidence" $ TestCase $ do
  let events =
        [ mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1
        , mkLearningEvent RuntimeFeedbackNegative "свобода" "долг" 0.6 1
        ]
      delta = rebuildLearningProjection events
  case M.lookup ("свобода", "долг") delta of
    Nothing -> assertFailure "edge missing"
    Just edge -> assertBool "confidence lowered" (seConfidence edge < 0.6)

testReplayRetire :: Test
testReplayRetire = TestLabel "replay retire removes edge" $ TestCase $ do
  let events =
        [ mkLearningEvent EdgeAdmitted "свобода" "долг" 0.6 1
        , mkLearningEvent EdgeRetired "свобода" "долг" 0.6 1
        ]
      delta = rebuildLearningProjection events
  assertEqual "edge retired" M.empty delta

testReplayHumanCorrection :: Test
testReplayHumanCorrection = TestLabel "replay human correction produces authoritative edge" $ TestCase $ do
  let event = (mkLearningEvent EdgeAdmitted "свобода" "ответственность" 1.0 1)
        { leSource = LesHumanCorrection
        , leProvenance = Just ProvenanceHumanCorrection
        , leReason = Just "explicit_human_correction"
        }
      delta = rebuildLearningProjection [event]
  case M.lookup ("свобода", "ответственность") delta of
    Nothing -> assertFailure "edge missing"
    Just edge -> do
      assertEqual "human correction provenance" ProvenanceHumanCorrection (seProvenance edge)
      assertEqual "human correction confidence" 1.0 (seConfidence edge)

testHumanCorrectionWinsOverRuntime :: Test
testHumanCorrectionWinsOverRuntime = TestLabel "human correction wins over runtime edge in applyProjectionDelta" $ TestCase $ do
  let runtimeEdge = mkEdge "свобода" "долг" ProvenanceRuntimeLLM RelRequires 0.6 1
      correctedEdge = mkEdge "свобода" "долг" ProvenanceHumanCorrection RelRequires 1.0 1
      seedNet = mkNetwork [runtimeEdge]
      delta = M.fromList [(("свобода", "долг"), correctedEdge)]
      merged = applyProjectionDelta delta seedNet
  assertEqual "human correction wins" (Just correctedEdge) (M.lookup ("свобода", "долг") (snEdges merged))

testNamespaceGlobalWins :: Test
testNamespaceGlobalWins = TestLabel "global namespace wins over user-local and session-local" $ TestCase $ do
  let sessionEdge = (mkEdge "a" "b" ProvenanceRuntimeLLM RelRequires 0.6 1) { seNamespace = Just NamespaceSessionLocal }
      userEdge    = (mkEdge "a" "b" ProvenanceRuntimeLLM RelRequires 0.6 1) { seNamespace = Just NamespaceUserLocal }
      globalEdge  = (mkEdge "a" "b" ProvenanceRuntimeLLM RelRequires 0.6 1) { seNamespace = Just NamespaceGlobal }
      net1 = applyProjectionDelta (M.singleton ("a", "b") userEdge) (mkNetwork [sessionEdge])
      net2 = applyProjectionDelta (M.singleton ("a", "b") globalEdge) net1
  assertEqual "user wins over session" (Just NamespaceUserLocal) (M.lookup ("a", "b") (snEdges net1) >>= seNamespace)
  assertEqual "global wins over user" (Just NamespaceGlobal) (M.lookup ("a", "b") (snEdges net2) >>= seNamespace)

testNamespaceRoundTrip :: Test
testNamespaceRoundTrip = TestLabel "namespace round-trips through runtime projection" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_runtime_namespace.db"
  let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  cleanup
  connResult <- NSQL.open dbPath
  conn <- case connResult of
    Left err -> assertFailure ("failed to open test db: " ++ T.unpack err) >> undefined
    Right c -> pure c
  let db = QxFx0DB dbPath conn
  ensureRuntimeProjectionSchema db
  let edge = (mkEdge "x" "y" ProvenanceHumanCorrection RelRequires 0.9 1) { seNamespace = Just NamespaceGlobal }
  persistRuntimeEdge db "session-a" edge
  loaded <- loadRuntimeEdgeProjection db "session-a"
  NSQL.close conn
  cleanup
  case M.lookup ("x", "y") loaded of
    Nothing -> assertFailure "edge missing"
    Just e -> assertEqual "namespace preserved" (Just NamespaceGlobal) (seNamespace e)

testSessionIsolationAndLegacyMigration :: Test
testSessionIsolationAndLegacyMigration = TestLabel "runtime projection isolates sessions and migrates legacy rows global" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_runtime_session_isolation.db"
  let cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  cleanup
  Right conn <- NSQL.open dbPath
  _ <- NSQL.execSql conn
    "CREATE TABLE semantic_edges_runtime (id INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, weight REAL NOT NULL, co_occurrence INTEGER NOT NULL, relation_type TEXT, domain TEXT, temporal_scope TEXT, verb TEXT, rationale TEXT, confidence REAL NOT NULL, provenance TEXT NOT NULL, namespace TEXT NOT NULL DEFAULT 'session_local')"
  _ <- NSQL.execSql conn
    "INSERT INTO semantic_edges_runtime(ts, edge_from, edge_to, weight, co_occurrence, relation_type, confidence, provenance, namespace) VALUES(1, 'legacy', 'shared', 0.5, 1, 'related_to', 0.5, 'runtime_llm', 'session_local')"
  let db = QxFx0DB dbPath conn
      sessionA = mkEdge "only-a" "target-a" ProvenanceRuntimeLLM RelRequires 0.6 1
      sessionB = mkEdge "only-b" "target-b" ProvenanceRuntimeLLM RelRequires 0.6 1
  ensureRuntimeProjectionSchema db
  persistRuntimeEdge db "session-a" sessionA
  persistRuntimeEdge db "session-b" sessionB
  loadedA <- loadRuntimeEdgeProjection db "session-a"
  loadedB <- loadRuntimeEdgeProjection db "session-b"
  NSQL.close conn
  cleanup
  assertBool "legacy row is explicitly global and visible to A" (M.member ("legacy", "shared") loadedA)
  assertBool "legacy row is explicitly global and visible to B" (M.member ("legacy", "shared") loadedB)
  assertBool "A sees its own local row" (M.member ("only-a", "target-a") loadedA)
  assertBool "A cannot see B local row" (not (M.member ("only-b", "target-b") loadedA))
  assertBool "B sees its own local row" (M.member ("only-b", "target-b") loadedB)
  assertBool "B cannot see A local row" (not (M.member ("only-a", "target-a") loadedB))

runtimeProjectionTests :: [Test]
runtimeProjectionTests =
  [ testRoundTrip
  , testSeedWins
  , testNovelEdgesAdded
  , testReplayEmpty
  , testReplayAdmit
  , testReplayCorroboration
  , testReplayTargetedConflictPreservesAdmittedEdge
  , testReplayReject
  , testReplayQuarantine
  , testReplayPositiveFeedback
  , testReplayNegativeFeedback
  , testReplayRetire
  , testReplayHumanCorrection
  , testHumanCorrectionWinsOverRuntime
  , testNamespaceGlobalWins
  , testNamespaceRoundTrip
  , testSessionIsolationAndLegacyMigration
  ]
