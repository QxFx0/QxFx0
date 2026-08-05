{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.FeedbackLoopEndToEnd
  ( feedbackLoopEndToEndTests
  ) where

import qualified Data.Foldable as F
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.Text (Text)
import Data.Maybe (mapMaybe)
import Test.HUnit

import QxFx0.Core.TurnPipeline.Protocol
  ( FinalizePrecommitBundle(..)
  , TurnArtifacts(..)
  )
import QxFx0.Runtime.StateDefaults (emptySystemState)
import QxFx0.Semantic.Content.Base (PredicateRole(..), mkPred)
import QxFx0.Semantic.ContentSelector
  ( SelectorDiagnostic(..)
  , buildContentSelector
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Feedback (UserFeedback(..))
import QxFx0.Semantic.Network.Feedback.Collect (applyDetectedFeedback, collectUsedEdges)
import QxFx0.Semantic.Network.Feedback.Detect (detectUserFeedback)
import QxFx0.Semantic.Network.Types
import QxFx0.Semantic.Space.Types (emptySemanticSpace)
import QxFx0.Types
  ( MorphologyData(..)
  , SystemState(..)
  , TurnProjection(..)
  , TurnReplayTrace(..)
  )
import Test.Support.TurnPipelineFixtures (buildFinalizeFixtureWithState)

sampleEdge :: SemanticEdge
sampleEdge = SemanticEdge
  { seFrom         = "a"
  , seTo           = "b"
  , seWeight       = 0.5
  , seCoOccurrence = 1
  , seSource       = ExplicitEdge
  , seRelationType = Just RelRequires
  , seVerb         = Nothing
  , seRationale    = Nothing
  , seCounter      = Nothing
  , seSynthesis    = Nothing
  , seConfidence   = 0.8
  , seProvenance   = ProvenanceCurated
  , seDomain       = Nothing
  , seTemporalScope = Nothing
  , seNamespace    = Nothing
  , seLineage      = Nothing
  }

sampleNetwork :: SemanticNetwork
sampleNetwork = SemanticNetwork
  { snNodes = S.fromList ["a", "b"]
  , snEdges = Map.singleton ("a", "b") sampleEdge
  , snActivation = Map.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = Seq.singleton (ActivationStep "b" ExplicitEdge "a" 1 0.5)
  }

sampleArtifact :: ActivationArtifact
sampleArtifact = ActivationArtifact
  { aaSeedTopics = ["a"]
  , aaActivation = Map.singleton "b" 0.5
  , aaSteps = snActivationLog sampleNetwork
  , aaUsedEdges = [sampleEdge]
  }

feedbackLoopEndToEndTests :: [Test]
feedbackLoopEndToEndTests =
  [ TestLabel "detect challenge marker" testDetectChallenge
  , TestLabel "detect accept marker" testDetectAccept
  , TestLabel "detect clarify marker" testDetectClarify
  , TestLabel "no feedback for neutral input" testDetectNothing
  , TestLabel "no false positives for embedded accept markers" testDetectNoFalsePositive
  , TestLabel "collect used edges from activation log" testCollectUsedEdges
  , TestLabel "feedback loop disabled leaves network unchanged" testFeedbackLoopDisabled
  , TestLabel "challenge via pipeline lowers confidence and adds counter" testChallengePipeline
  , TestLabel "accept via pipeline raises confidence" testAcceptPipeline
  , TestLabel "clarify via pipeline updates rationale" testClarifyPipeline
  , TestLabel "production selection, trace, substrate, and feedback share activation artifact" testProductionActivationArtifactChain
  ]

testDetectChallenge :: Test
testDetectChallenge = TestCase $ do
  assertEqual "challenge detected with remainder"
    (Just (Challenge "потому что неверно"))
    (detectUserFeedback "не согласен, потому что неверно")

testDetectAccept :: Test
testDetectAccept = TestCase $ do
  assertEqual "accept detected"
    (Just Accept)
    (detectUserFeedback "да, согласен")

testDetectClarify :: Test
testDetectClarify = TestCase $ do
  assertEqual "clarify detected with remainder"
    (Just (Clarify "именно это"))
    (detectUserFeedback "то есть именно это")

testDetectNothing :: Test
testDetectNothing = TestCase $ do
  assertEqual "neutral input returns Nothing"
    Nothing
    (detectUserFeedback "расскажи про свободу")

testDetectNoFalsePositive :: Test
testDetectNoFalsePositive = TestCase $ do
  assertEqual "да inside загадка is not a marker"
    Nothing
    (detectUserFeedback "загадка")
  assertEqual "да inside надо is not a marker"
    Nothing
    (detectUserFeedback "надо подумать")

testCollectUsedEdges :: Test
testCollectUsedEdges = TestCase $ do
  let used = collectUsedEdges sampleNetwork (F.toList (snActivationLog sampleNetwork))
  assertEqual "one used edge collected" [sampleEdge] used

testFeedbackLoopDisabled :: Test
testFeedbackLoopDisabled = TestCase $
  let result = applyDetectedFeedback False "не согласен, потому что неверно" (Just sampleArtifact) sampleNetwork
  in assertEqual "feedback loop disabled leaves network unchanged"
       sampleNetwork
       result

testChallengePipeline :: Test
testChallengePipeline = TestCase $ do
  let result = applyDetectedFeedback True "не согласен, потому что неверно" (Just sampleArtifact) sampleNetwork
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain"
    Just e  -> assertEqual "challenge lowers confidence" 0.65 (seConfidence e)
  case Map.lookup ("b", "a") (snEdges result) of
    Nothing -> assertFailure "counter-relation must be added"
    Just e  -> do
      assertEqual "counter relation type" (Just RelContrastsWith) (seRelationType e)
      assertEqual "counter confidence" 0.3 (seConfidence e)
      assertEqual "counter provenance" ProvenanceDialogueFeedback (seProvenance e)

testAcceptPipeline :: Test
testAcceptPipeline = TestCase $ do
  let challenged = applyDetectedFeedback True "не согласен, потому что неверно" (Just sampleArtifact) sampleNetwork
      result     = applyDetectedFeedback True "да, согласен" (Just sampleArtifact) challenged
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain"
    Just e  -> assertEqual "accept raises confidence after challenge" 0.75 (seConfidence e)

testClarifyPipeline :: Test
testClarifyPipeline = TestCase $ do
  let result = applyDetectedFeedback True "то есть именно это" (Just sampleArtifact) sampleNetwork
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain"
    Just e  -> assertEqual "clarify updates rationale" (Just "именно это") (seRationale e)

testProductionActivationArtifactChain :: Test
testProductionActivationArtifactChain = TestCase $ do
  let predicateSurface = "тема требует явной проверки"
      predicate = mkPred RoleProperty predicateSurface "the topic requires explicit verification"
      substrate = sampleEdge
        { seSource = SubstrateEdge
        , seProvenance = ProvenanceSubstrate
        }
      network = sampleNetwork
        { snEdges = Map.singleton ("a", "b") substrate
        , snActivation = Map.empty
        , snActivationLog = Seq.empty
        }
      selector = buildContentSelector
        emptySemanticSpace
        (Map.singleton "тема" (S.singleton "a"))
        (Map.singleton "тема" [predicate])
        Map.empty
        Nothing
      morphology = (ssMorphology emptySystemState)
        { mdNominative = Map.singleton "тема" "тема" }
      state = emptySystemState
        { ssSemanticNetwork = network
        , ssContentSelector = selector
        , ssMorphology = morphology
        }
  (_, _, _, _, artifacts, bundle) <-
    buildFinalizeFixtureWithState state "что такое тема?"
  artifact <- case taActivationArtifact artifacts of
    Nothing -> assertFailure "production renderer did not carry activation artifact" >> fail "unreachable"
    Just value -> pure value
  let trace = tqpReplayTrace (fpbProjection bundle)
      selectedSurfaces = mapMaybe selectedSurface (taSelectorDiagnostics artifacts)
      substrateSteps = filter ((== SubstrateEdge) . asSource) (F.toList (aaSteps artifact))
      nextState = fpbNextSs bundle
      feedbackResult = applyDetectedFeedback
        True
        "да, согласен"
        (ssLastActivationArtifact nextState)
        (ssSemanticNetwork nextState)
  assertBool "the selected predicate is emitted" (predicateSurface `elem` taEmittedPredicates artifacts)
  assertBool "selector diagnostics identify the emitted predicate" (predicateSurface `elem` selectedSurfaces)
  assertEqual "trace records the exact artifact steps" (aaSteps artifact) (trcActivationSteps trace)
  assertEqual "substrate edge count comes from the same steps" (length substrateSteps) (trcSubstrateEdgesUsed trace)
  assertEqual "substrate activated nodes come from the same steps"
    (S.fromList (map asNode substrateSteps))
    (S.fromList (trcSubstrateActivated trace))
  assertEqual "finalize preserves the exact artifact for next-turn feedback"
    (Just artifact)
    (ssLastActivationArtifact nextState)
  assertEqual "feedback source is the exact traversed edge"
    [substrate]
    (aaUsedEdges artifact)
  case Map.lookup ("a", "b") (snEdges feedbackResult) of
    Nothing -> assertFailure "feedback source edge disappeared"
    Just edge -> assertEqual "feedback updated the artifact edge" 0.9 (seConfidence edge)
  where
    selectedSurface diagnostic
      | sdSelected diagnostic = sdPredicateSurface diagnostic
      | otherwise = Nothing
