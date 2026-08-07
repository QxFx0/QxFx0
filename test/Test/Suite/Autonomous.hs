{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | ADR-0054 M1 regression tests for the autonomous learning worker.
module Test.Suite.Autonomous
  ( autonomousTests
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( AutonomousWorkerConfig(..)
  , AutonomousMode(..)
  , CompetitiveUtilityAudit(..)
  , LearningTask(..)
  , NetworkUpdateEvent(..)
  , autonomousApplyLLMResponse
  , autonomousApplyLLMResponseForTopic
  , buildAtomMorphology
  , corroborationPriority
  , defaultAutonomousWorkerConfig
  , drainLearningQueue
  , enqueueLearningTask
  , extendAtomStoreWithTopics
  , isTruthy
  , evaluateCompetitiveUtility
  , newLearningQueue
  , readIntWithDefault
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Semantic.LLMDiscovery (buildDiscoveryPrompt, buildGapAwareDiscoveryPrompt)
import QxFx0.Semantic.Content
  ( DefinitionContent(..)
  , PredicateRole(..)
  , SemanticPredicate(..)
  )
import QxFx0.Types.Semantic.Content (CanonicalPredicateRelation(..))
import QxFx0.Semantic.Content.AtomStore
  ( Atom(..)
  , AtomId(..)
  , Relation(..)
  , RelationType(..)
  , atomStore
  , atomDisplay
  )
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
import QxFx0.Types.ExternalQuery (ExternalQueryResponse(..))
import QxFx0.Semantic.Network.Types (EdgeProvenance(..), EdgeSource(..), SemanticNetwork(..), SemanticEdge(..))
import QxFx0.Types.State.System (SystemState(..), ssSemanticNetwork)
import QxFx0.Runtime.StateDefaults (emptySystemState)

-- ---------------------------------------------------------------------------
-- Config helpers
-- ---------------------------------------------------------------------------

testIsTruthy :: Test
testIsTruthy = TestLabel "isTruthy recognises 1/true/yes/on" $
  TestCase $ do
    assertBool "1 is truthy"      (isTruthy (Just "1"))
    assertBool "true is truthy"   (isTruthy (Just "true"))
    assertBool "yes is truthy"    (isTruthy (Just "yes"))
    assertBool "on is truthy"     (isTruthy (Just "on"))
    assertBool "TRUE uppercase"   (isTruthy (Just "TRUE"))
    assertBool "  1  trimmed"     (isTruthy (Just "  1  "))
    assertBool "0 is falsy"       (not (isTruthy (Just "0")))
    assertBool "no is falsy"      (not (isTruthy (Just "no")))
    assertBool "Nothing is falsy" (not (isTruthy Nothing))

testReadIntWithDefault :: Test
testReadIntWithDefault = TestLabel "readIntWithDefault parses ints and falls back" $
  TestCase $ do
    assertEqual "valid int"  42 (readIntWithDefault (Just "42") 0)
    assertEqual "with spaces" 7 (readIntWithDefault (Just "  7  ") 0)
    assertEqual "negative"    (-3) (readIntWithDefault (Just "-3") 0)
    assertEqual "garbage → default" 99 (readIntWithDefault (Just "abc") 99)
    assertEqual "trailing garbage → default" 11 (readIntWithDefault (Just "5xx") 11)
    assertEqual "Nothing → default" 50 (readIntWithDefault Nothing 50)

testDefaultConfig :: Test
testDefaultConfig = TestLabel "defaultAutonomousWorkerConfig is disabled" $
  TestCase $ do
    let cfg = defaultAutonomousWorkerConfig
    assertBool "disabled by default" (not (awcEnabled cfg))
    assertEqual "enabled runtime defaults to corroboration-only dispatch"
      CorroborationOnly (awcMode cfg)
    assertEqual "default max req/min" 100 (awcMaxRequestsPerMinute cfg)
    assertEqual "default max req/h"  6000 (awcMaxRequestsPerHour cfg)
    assertEqual "default max req/day" 144000 (awcMaxRequestsPerDay cfg)
    assertEqual "default max tokens/min" 100000 (awcMaxTokensPerMinute cfg)
    assertEqual "default max tokens/h" 6000000 (awcMaxTokensPerHour cfg)
    assertEqual "default max tokens/day" 144000000 (awcMaxTokensPerDay cfg)
    assertEqual "default max edges"   5 (awcMaxEdgesPerBatch cfg)
    assertEqual "default queue cap" 100 (awcQueueCap cfg)

-- ---------------------------------------------------------------------------
-- Queue
-- ---------------------------------------------------------------------------

testQueueEnqueueDrain :: Test
testQueueEnqueueDrain = TestLabel "LearningQueue enqueue + drain round-trip" $
  TestCase $ do
    q <- newLearningQueue
    let task1 = LearningTask { ltTopic = "свобода", ltPriority = 1.0, ltRequestId = "r1" }
        task2 = LearningTask { ltTopic = "истина",  ltPriority = 0.5, ltRequestId = "r2" }
    enqueueLearningTask q task1
    enqueueLearningTask q task2
    drained <- drainLearningQueue q
    assertEqual "two tasks enqueued" 2 (length drained)
    -- Second drain should be empty
    drained2 <- drainLearningQueue q
    assertEqual "queue empty after drain" 0 (length drained2)

-- ---------------------------------------------------------------------------
-- autonomousApplyLLMResponse (explicit store)
-- ---------------------------------------------------------------------------

testBuildMorphologyFromStore :: Test
testBuildMorphologyFromStore = TestLabel "explicit-store gate rejects unknown endpoint" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = ExternalQueryResponse
          { eqrRawBody    = "свобода | связана | несуществующий_атом_99999 | relatedto\n"
          , eqrStructured = ""
          , eqrToolName   = "test"
          , eqrLatencyMs  = 0
          }
        net = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
    assertEqual "no edges for unknown endpoint" 0 (M.size (snEdges net))

testBuildMorphologyAdmitsKnown :: Test
testBuildMorphologyAdmitsKnown = TestLabel "explicit-store gate admits known endpoints" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = ExternalQueryResponse
          { eqrRawBody    = "свобода | связана | выбор | relatedto\n"
          , eqrStructured = ""
          , eqrToolName   = "test"
          , eqrLatencyMs  = 0
          }
        net = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
    assertBool "one edge admitted" (M.size (snEdges net) >= 1)

testExtendedCorpusTopicsAreAdmitted :: Test
testExtendedCorpusTopicsAreAdmitted = TestLabel "autonomous admission accepts loaded curated topics" $
  TestCase $ do
    let corpus = M.fromList
          [ ("ремонт", DefinitionContent "ремонт" [])
          , ("инструмент", DefinitionContent "инструмент" [])
          ]
        store = extendAtomStoreWithTopics atomStore corpus
        resp = ExternalQueryResponse
          { eqrRawBody = ""
          , eqrStructured = "{\"schema_version\":1,\"relations\":[{\"from\":\"ремонт\",\"verb\":\"требует\",\"to\":\"инструмент\",\"type\":\"requires\"}]}"
          , eqrToolName = "test"
          , eqrLatencyMs = 0
          }
        net = autonomousApplyLLMResponseForTopic store (buildAtomMorphology store) "ремонт" resp
    assertBool "relation between curated topics is admitted" (M.member ("ремонт", "инструмент") (snEdges net))

testDiscoveryPromptIsDomainGeneral :: Test
testDiscoveryPromptIsDomainGeneral = TestLabel "autonomous prompt is not restricted to seed philosophy topics" $
  TestCase $ do
    let prompt = buildDiscoveryPrompt "ремонт"
    assertBool "prompt retains the scheduled topic" ("ремонт" `T.isInfixOf` prompt)
    assertBool "prompt must not constrain learning to the L1 list" (not ("Темы L1" `T.isInfixOf` prompt))

testGapAwareDiscoveryPromptRejectsParaphrase :: Test
testGapAwareDiscoveryPromptRejectsParaphrase = TestLabel "gap-aware prompt includes base exclusions and relation slots" $
  TestCase $ do
    let prompt = buildGapAwareDiscoveryPrompt
          "надежда"
          ["истина", "будущее"]
          ["надежда поддерживает действие"]
          ["causes", "requires", "partOf"]
    assertBool "prompt names base predicate" ("надежда поддерживает действие" `T.isInfixOf` prompt)
    assertBool "prompt forbids paraphrases" ("не перефразируй" `T.isInfixOf` prompt)
    assertBool "prompt requests missing slots" ("causes, requires, partOf" `T.isInfixOf` prompt)
    assertBool "prompt keeps local endpoint boundary" ("истина, будущее" `T.isInfixOf` prompt)

testCompetitiveUtilityPreservesBasePrimary :: Test
testCompetitiveUtilityPreservesBasePrimary =
  TestLabel "competitive utility keeps base primary and qualifies a novel secondary" $ TestCase $ do
    let topic = "тема"
        base = SemanticPredicate RoleProperty "тема связана с основанием" "" topic
          (Just (CanonicalPredicateRelation topic "related_to" "основание")) Nothing Nothing Nothing
        edge = testCompetitiveEdge "условие" RelRequires
        topicAtoms = M.singleton topic (S.fromList [topic, "related_to", "основание"])
        audit = evaluateCompetitiveUtility topic topicAtoms (M.singleton topic [base]) M.empty edge
    assertEqual "base primary remains the primary predicate"
      (Just "тема связана с основанием") (cuaBasePrimary audit)
    assertEqual "transient selector retains base primary"
      (Just "тема связана с основанием") (cuaTransientPrimary audit)
    assertBool "base primary is preserved" (cuaBasePrimaryPreserved audit)
    assertEqual "candidate is selected only as secondary" "secondary" (cuaCandidateRole audit)
    assertEqual "candidate contributes a new constraint" "new_constraint" (cuaContribution audit)
    assertBool "candidate can receive corroboration priority" (cuaQualifiedForCorroboration audit)
    assertBool "qualified candidate gets nonzero priority" (corroborationPriority audit > 0.0)

testCompetitiveUtilityRejectsDuplicateContribution :: Test
testCompetitiveUtilityRejectsDuplicateContribution =
  TestLabel "competitive utility does not prioritize duplicate contribution" $ TestCase $ do
    let topic = "тема"
        base = SemanticPredicate RoleProperty "тема требует основания" "" topic
          (Just (CanonicalPredicateRelation topic "requires" "основание")) Nothing Nothing Nothing
        edge = testCompetitiveEdge "основание" RelRequires
        topicAtoms = M.singleton topic (S.fromList [topic, "requires", "основание"])
        audit = evaluateCompetitiveUtility topic topicAtoms (M.singleton topic [base]) M.empty edge
    assertEqual "duplicate has no new contribution" "duplicate" (cuaContribution audit)
    assertBool "duplicate is not corroboration qualified" (not (cuaQualifiedForCorroboration audit))
    assertEqual "duplicate has zero corroboration priority" 0.0 (corroborationPriority audit)

testCompetitiveEdge :: Text -> RelationType -> SemanticEdge
testCompetitiveEdge object relation = SemanticEdge
  { seFrom = "тема"
  , seTo = object
  , seWeight = 0.6
  , seCoOccurrence = 1
  , seSource = ExplicitEdge
  , seRelationType = Just relation
  , seVerb = Nothing
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

-- ---------------------------------------------------------------------------
-- Test group
-- ---------------------------------------------------------------------------

autonomousTests :: [Test]
autonomousTests =
  [ testIsTruthy
  , testReadIntWithDefault
  , testDefaultConfig
  , testQueueEnqueueDrain
  , testBuildMorphologyFromStore
  , testBuildMorphologyAdmitsKnown
  , testExtendedCorpusTopicsAreAdmitted
  , testDiscoveryPromptIsDomainGeneral
  , testGapAwareDiscoveryPromptRejectsParaphrase
  , testCompetitiveUtilityPreservesBasePrimary
  , testCompetitiveUtilityRejectsDuplicateContribution
  ]
