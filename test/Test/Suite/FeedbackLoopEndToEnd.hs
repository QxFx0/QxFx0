{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.FeedbackLoopEndToEnd
  ( feedbackLoopEndToEndTests
  ) where

import qualified Data.Foldable as F
import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.Text (Text)
import Test.HUnit

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Feedback (UserFeedback(..))
import QxFx0.Semantic.Network.Feedback.Collect (applyDetectedFeedback, collectUsedEdges)
import QxFx0.Semantic.Network.Feedback.Detect (detectUserFeedback)
import QxFx0.Semantic.Network.Types

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

feedbackLoopEndToEndTests :: [Test]
feedbackLoopEndToEndTests =
  [ TestLabel "detect challenge marker" testDetectChallenge
  , TestLabel "detect accept marker" testDetectAccept
  , TestLabel "detect clarify marker" testDetectClarify
  , TestLabel "no feedback for neutral input" testDetectNothing
  , TestLabel "collect used edges from activation log" testCollectUsedEdges
  , TestLabel "challenge via pipeline lowers confidence and adds counter" testChallengePipeline
  , TestLabel "accept via pipeline raises confidence" testAcceptPipeline
  , TestLabel "clarify via pipeline updates rationale" testClarifyPipeline
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

testCollectUsedEdges :: Test
testCollectUsedEdges = TestCase $ do
  let used = collectUsedEdges sampleNetwork (F.toList (snActivationLog sampleNetwork))
  assertEqual "one used edge collected" [sampleEdge] used

testChallengePipeline :: Test
testChallengePipeline = TestCase $ do
  let result = applyDetectedFeedback "не согласен, потому что неверно" sampleNetwork sampleNetwork
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
  let challenged = applyDetectedFeedback "не согласен, потому что неверно" sampleNetwork sampleNetwork
      result     = applyDetectedFeedback "да, согласен" challenged challenged
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain"
    Just e  -> assertEqual "accept raises confidence after challenge" 0.75 (seConfidence e)

testClarifyPipeline :: Test
testClarifyPipeline = TestCase $ do
  let result = applyDetectedFeedback "то есть именно это" sampleNetwork sampleNetwork
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain"
    Just e  -> assertEqual "clarify updates rationale" (Just "именно это") (seRationale e)
