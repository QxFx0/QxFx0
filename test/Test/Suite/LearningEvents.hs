{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.LearningEvents
  ( learningEventsTests
  ) where

import Control.Exception (bracket_)
import qualified Data.Map.Strict as M
import Data.Aeson (decode, encode)
import Data.Text (Text)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime(..))
import Foreign.Ptr (nullPtr)
import Test.HUnit

import QxFx0.Bridge.SQLite (QxFx0DB(..))
import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  , LearningEventSource(..)
  , diffRuntimeFeedbackEvents
  , ensureLearningEventsSchema
  , learningEventKindFromText
  , learningEventKindText
  , learningEventSourceFromText
  , learningEventSourceText
  , loadLearningEvents
  , loadLearningEventsFiltered
  , recordLearningEvent
  , recordLearningEvents
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )
import Test.Support (freshTestDbPath, removeIfExists)

sampleEvent :: LearningEvent
sampleEvent = LearningEvent
  { leTimestamp = UTCTime (fromGregorian 2026 7 11) 0
  , leSessionId = Just "session"
  , leTurnSeq = Just 7
  , leRequestId = "request"
  , leTopic = "свобода"
  , leKind = EdgeAdmitted
  , leSource = LesAutonomousApply
  , leEdgeFrom = Just "свобода"
  , leEdgeTo = Just "долг"
  , leProvenance = Just ProvenanceRuntimeLLM
  , leConfidence = Just 0.6
  , leCoOccurrence = Just 1
  , leReason = Nothing
  , lePromptHash = Just "prompt"
  , leResponseHash = Just "response"
  }

secondEvent :: LearningEvent
secondEvent = LearningEvent
  { leTimestamp = UTCTime (fromGregorian 2026 7 11) 5
  , leSessionId = Nothing
  , leTurnSeq = Nothing
  , leRequestId = "request-2"
  , leTopic = "свобода"
  , leKind = RuntimeFeedbackPositive
  , leSource = LesRuntimeFeedback
  , leEdgeFrom = Just "свобода"
  , leEdgeTo = Just "долг"
  , leProvenance = Just ProvenanceRuntimeLLM
  , leConfidence = Just 0.65
  , leCoOccurrence = Just 2
  , leReason = Nothing
  , lePromptHash = Nothing
  , leResponseHash = Nothing
  }

mkEdge :: Text -> Text -> EdgeProvenance -> Double -> Int -> SemanticEdge
mkEdge from to prov conf cooc = SemanticEdge
  { seFrom = from
  , seTo = to
  , seWeight = conf
  , seCoOccurrence = cooc
  , seSource = ExplicitEdge
  , seRelationType = Just RelRequires
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

feedbackTs :: UTCTime
feedbackTs = UTCTime (fromGregorian 2026 7 11) 0

testKindText :: Test
testKindText = TestLabel "LearningEventKind has stable text" $ TestCase $ do
  assertEqual "admitted" "edge_admitted" (learningEventKindText EdgeAdmitted)
  assertEqual "promoted" "edge_promoted" (learningEventKindText EdgePromoted)
  assertEqual "positive" "runtime_feedback_positive" (learningEventKindText RuntimeFeedbackPositive)

testSourceText :: Test
testSourceText = TestLabel "LearningEventSource has stable text" $ TestCase $ do
  assertEqual "apply" "autonomous_apply" (learningEventSourceText LesAutonomousApply)
  assertEqual "feedback" "runtime_feedback" (learningEventSourceText LesRuntimeFeedback)

testTextRoundTrips :: Test
testTextRoundTrips = TestLabel "kind/source text parsers round-trip" $ TestCase $ do
  mapM_
    (\k -> assertEqual "kind" (Just k) (learningEventKindFromText (learningEventKindText k)))
    [ LlmEdgeProposed, EdgeAdmitted, EdgeRejected, EdgeQuarantined
    , RuntimeFeedbackPositive, RuntimeFeedbackNegative, RuntimeFeedbackConflict
    , EdgePromoted, EdgeDecayed, EdgeRetired
    ]
  mapM_
    (\s -> assertEqual "source" (Just s) (learningEventSourceFromText (learningEventSourceText s)))
    [ LesAutonomousApply, LesWorker, LesRuntimeFeedback, LesHumanCorrection ]
  assertEqual "unknown kind" Nothing (learningEventKindFromText "nope")
  assertEqual "unknown source" Nothing (learningEventSourceFromText "nope")

testRoundTrip :: Test
testRoundTrip = TestLabel "LearningEvent JSON round-trips" $ TestCase $ do
  assertEqual "round-trip" (Just sampleEvent) (decode (encode sampleEvent))

testDbRoundTrip :: Test
testDbRoundTrip = TestLabel "learning events persist and reload from SQLite" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_learning_events.db"
  let db = QxFx0DB dbPath nullPtr
      cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  bracket_ cleanup cleanup $ do
    ensureLearningEventsSchema db
    recordLearningEvents db [sampleEvent, secondEvent]
    loaded <- loadLearningEvents db 10
    assertEqual "two events persisted" 2 (length loaded)
    -- loadLearningEvents returns oldest-first (insertion order).
    assertEqual "first event faithful" sampleEvent (head loaded)
    assertEqual "second event faithful" secondEvent (loaded !! 1)

testDbLimit :: Test
testDbLimit = TestLabel "learning events load honours limit (newest kept)" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_learning_events_limit.db"
  let db = QxFx0DB dbPath nullPtr
      cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  bracket_ cleanup cleanup $ do
    ensureLearningEventsSchema db
    recordLearningEvents db [sampleEvent, secondEvent]
    loaded <- loadLearningEvents db 1
    assertEqual "one event returned" 1 (length loaded)
    assertEqual "newest event kept" secondEvent (head loaded)

-- | An event on a different topic, to exercise topic filtering.
otherTopicEvent :: LearningEvent
otherTopicEvent = sampleEvent
  { leTopic = "долг"
  , leEdgeFrom = Just "долг"
  , leEdgeTo = Just "ответственность"
  }

testDbTopicFilter :: Test
testDbTopicFilter = TestLabel "loadLearningEventsFiltered filters by topic" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_learning_events_topic.db"
  let db = QxFx0DB dbPath nullPtr
      cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  bracket_ cleanup cleanup $ do
    ensureLearningEventsSchema db
    recordLearningEvents db [sampleEvent, otherTopicEvent]
    byTopic <- loadLearningEventsFiltered db 10 (Just "свобода")
    assertEqual "only свобода events" 1 (length byTopic)
    assertEqual "topic matches" "свобода" (leTopic (head byTopic))
    allEvents <- loadLearningEventsFiltered db 10 Nothing
    assertEqual "no filter returns both" 2 (length allEvents)

testDiffPositive :: Test
testDiffPositive = TestLabel "diff detects positive reinforcement" $ TestCase $ do
  let before = mkNetwork [mkEdge "свобода" "долг" ProvenanceRuntimeLLM 0.60 1]
      after  = mkNetwork [mkEdge "свобода" "долг" ProvenanceRuntimeLLM 0.65 2]
      events = diffRuntimeFeedbackEvents feedbackTs Nothing (Just 3) "req" "свобода" before after
  assertEqual "one event" 1 (length events)
  assertEqual "positive kind" RuntimeFeedbackPositive (leKind (head events))
  assertEqual "source is runtime feedback" LesRuntimeFeedback (leSource (head events))

testDiffNegative :: Test
testDiffNegative = TestLabel "diff detects negative decay" $ TestCase $ do
  let before = mkNetwork [mkEdge "свобода" "долг" ProvenanceRuntimeLLM 0.60 2]
      after  = mkNetwork [mkEdge "свобода" "долг" ProvenanceRuntimeLLM 0.50 2]
      events = diffRuntimeFeedbackEvents feedbackTs Nothing (Just 3) "req" "свобода" before after
  assertEqual "one event" 1 (length events)
  assertEqual "negative kind" RuntimeFeedbackNegative (leKind (head events))

testDiffConflict :: Test
testDiffConflict = TestLabel "diff detects conflict removal" $ TestCase $ do
  let before = mkNetwork [mkEdge "свобода" "долг" ProvenanceRuntimeLLM 0.60 2]
      after  = mkNetwork []
      events = diffRuntimeFeedbackEvents feedbackTs Nothing (Just 3) "req" "свобода" before after
  assertEqual "one event" 1 (length events)
  assertEqual "conflict kind" RuntimeFeedbackConflict (leKind (head events))

testDiffPromotion :: Test
testDiffPromotion = TestLabel "diff detects promotion to dialogue feedback" $ TestCase $ do
  let before = mkNetwork [mkEdge "свобода" "долг" ProvenanceRuntimeLLM 0.72 2]
      after  = mkNetwork [mkEdge "свобода" "долг" ProvenanceDialogueFeedback 0.77 3]
      events = diffRuntimeFeedbackEvents feedbackTs Nothing (Just 3) "req" "свобода" before after
      kinds  = map leKind events
  assertEqual "two events" 2 (length events)
  assertBool "positive present" (RuntimeFeedbackPositive `elem` kinds)
  assertBool "promoted present" (EdgePromoted `elem` kinds)

testDiffIgnoresAuthoritative :: Test
testDiffIgnoresAuthoritative = TestLabel "diff ignores non-runtime-LLM edges" $ TestCase $ do
  let before = mkNetwork [mkEdge "свобода" "долг" ProvenanceCurated 0.60 1]
      after  = mkNetwork [mkEdge "свобода" "долг" ProvenanceCurated 0.90 5]
      events = diffRuntimeFeedbackEvents feedbackTs Nothing (Just 3) "req" "свобода" before after
  assertEqual "no events" [] events

testDiffIgnoresMergeReplacement :: Test
testDiffIgnoresMergeReplacement = TestLabel "diff ignores merge-provenance replacement" $ TestCase $ do
  let before = mkNetwork [mkEdge "свобода" "долг" ProvenanceRuntimeLLM 0.60 1]
      after  = mkNetwork [mkEdge "свобода" "долг" ProvenanceCorpus 0.90 1]
      events = diffRuntimeFeedbackEvents feedbackTs Nothing (Just 3) "req" "свобода" before after
  assertEqual "no events" [] events

testBatchEmptyIsNoOp :: Test
testBatchEmptyIsNoOp = TestLabel "recordLearningEvents is safe on empty batch" $ TestCase $ do
  dbPath <- freshTestDbPath "qxfx0_test_learning_events_empty.db"
  let db = QxFx0DB dbPath nullPtr
      cleanup = mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
  bracket_ cleanup cleanup $ do
    ensureLearningEventsSchema db
    recordLearningEvents db []
    loaded <- loadLearningEvents db 10
    assertEqual "nothing persisted" 0 (length loaded)

learningEventsTests :: [Test]
learningEventsTests =
  [ testKindText
  , testSourceText
  , testTextRoundTrips
  , testRoundTrip
  , testDbRoundTrip
  , testDbLimit
  , testDbTopicFilter
  , testBatchEmptyIsNoOp
  , testDiffPositive
  , testDiffNegative
  , testDiffConflict
  , testDiffPromotion
  , testDiffIgnoresAuthoritative
  , testDiffIgnoresMergeReplacement
  ]
