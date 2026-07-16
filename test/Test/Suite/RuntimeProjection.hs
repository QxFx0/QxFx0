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
import QxFx0.Semantic.Network.RuntimeProjection
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
  , seNamespace = NamespaceSessionLocal
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
  persistRuntimeEdges db [edge1, edge2]
  loaded <- loadRuntimeEdgeProjection db
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
  let sessionEdge = (mkEdge "a" "b" ProvenanceRuntimeLLM RelRequires 0.6 1) { seNamespace = NamespaceSessionLocal }
      userEdge    = (mkEdge "a" "b" ProvenanceRuntimeLLM RelRequires 0.6 1) { seNamespace = NamespaceUserLocal }
      globalEdge  = (mkEdge "a" "b" ProvenanceRuntimeLLM RelRequires 0.6 1) { seNamespace = NamespaceGlobal }
      net1 = applyProjectionDelta (M.singleton ("a", "b") userEdge) (mkNetwork [sessionEdge])
      net2 = applyProjectionDelta (M.singleton ("a", "b") globalEdge) net1
  assertEqual "user wins over session" (Just NamespaceUserLocal) (seNamespace <$> M.lookup ("a", "b") (snEdges net1))
  assertEqual "global wins over user" (Just NamespaceGlobal) (seNamespace <$> M.lookup ("a", "b") (snEdges net2))

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
  let edge = (mkEdge "x" "y" ProvenanceHumanCorrection RelRequires 0.9 1) { seNamespace = NamespaceUserLocal }
  persistRuntimeEdge db edge
  loaded <- loadRuntimeEdgeProjection db
  NSQL.close conn
  cleanup
  case M.lookup ("x", "y") loaded of
    Nothing -> assertFailure "edge missing"
    Just e -> assertEqual "namespace preserved" NamespaceUserLocal (seNamespace e)

runtimeProjectionTests :: [Test]
runtimeProjectionTests =
  [ testRoundTrip
  , testSeedWins
  , testNovelEdgesAdded
  , testReplayEmpty
  , testReplayAdmit
  , testReplayReject
  , testReplayQuarantine
  , testReplayPositiveFeedback
  , testReplayNegativeFeedback
  , testReplayRetire
  , testReplayHumanCorrection
  , testHumanCorrectionWinsOverRuntime
  , testNamespaceGlobalWins
  , testNamespaceRoundTrip
  ]