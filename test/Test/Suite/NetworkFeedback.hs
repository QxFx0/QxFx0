{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.NetworkFeedback
  ( networkFeedbackTests
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.Text (Text)
import Test.HUnit

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Feedback
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
  , seConfidence   = 0.5
  , seProvenance   = ProvenanceCurated
  }

sampleNetwork :: SemanticNetwork
sampleNetwork = SemanticNetwork
  { snNodes = S.fromList ["a", "b"]
  , snEdges = Map.singleton ("a", "b") sampleEdge
  , snActivation = Map.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = Seq.empty
  }

networkFeedbackTests :: [Test]
networkFeedbackTests =
  [ TestLabel "Accept increases confidence" testAcceptIncreasesConfidence
  , TestLabel "Accept clamps confidence at 1.0" testAcceptClampsConfidence
  , TestLabel "Challenge decreases confidence" testChallengeDecreasesConfidence
  , TestLabel "Challenge adds counter-relation edge" testChallengeAddsCounterEdge
  , TestLabel "Challenge clamps confidence at 0.1" testChallengeClampsConfidence
  , TestLabel "Clarify updates empty rationale" testClarifyEmptyRationale
  , TestLabel "Clarify appends non-empty rationale" testClarifyAppendsRationale
  ]

testAcceptIncreasesConfidence :: Test
testAcceptIncreasesConfidence = TestCase $ do
  let result = applyFeedback sampleNetwork [sampleEdge] Accept
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain in network"
    Just e  -> assertEqual "confidence increased by 0.1" 0.6 (seConfidence e)

testAcceptClampsConfidence :: Test
testAcceptClampsConfidence = TestCase $ do
  let edge = sampleEdge { seConfidence = 0.98 }
      network = sampleNetwork { snEdges = Map.singleton ("a", "b") edge }
      result = applyFeedback network [edge] Accept
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain in network"
    Just e  -> assertEqual "confidence clamps at 1.0" 1.0 (seConfidence e)

testChallengeDecreasesConfidence :: Test
testChallengeDecreasesConfidence = TestCase $ do
  let result = applyFeedback sampleNetwork [sampleEdge] (Challenge "user disagrees")
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain in network"
    Just e  -> assertEqual "confidence decreased by 0.15" 0.35 (seConfidence e)

testChallengeAddsCounterEdge :: Test
testChallengeAddsCounterEdge = TestCase $ do
  let reason = "user disagrees"
      result = applyFeedback sampleNetwork [sampleEdge] (Challenge reason)
  case Map.lookup ("b", "a") (snEdges result) of
    Nothing -> assertFailure "counter-relation edge must be added"
    Just e  -> do
      assertEqual "counter edge source" "b" (seFrom e)
      assertEqual "counter edge target" "a" (seTo e)
      assertEqual "counter relation type" (Just RelContrastsWith) (seRelationType e)
      assertEqual "counter confidence" 0.3 (seConfidence e)
      assertEqual "counter provenance" ProvenanceDialogueFeedback (seProvenance e)
      assertEqual "counter field" (Just reason) (seCounter e)

testChallengeClampsConfidence :: Test
testChallengeClampsConfidence = TestCase $ do
  let edge = sampleEdge { seConfidence = 0.12 }
      network = sampleNetwork { snEdges = Map.singleton ("a", "b") edge }
      result = applyFeedback network [edge] (Challenge "too low")
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain in network"
    Just e  -> assertEqual "confidence clamps at 0.1" 0.1 (seConfidence e)

testClarifyEmptyRationale :: Test
testClarifyEmptyRationale = TestCase $ do
  let detail = "context from user"
      result = applyFeedback sampleNetwork [sampleEdge] (Clarify detail)
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain in network"
    Just e  -> assertEqual "rationale set to detail" (Just detail) (seRationale e)
  case Map.lookup ("a", "b") (snEdges sampleNetwork) of
    Nothing -> assertFailure "sample edge lookup failed"
    Just e  -> assertEqual "original confidence unchanged" (seConfidence e) (seConfidence $ sampleEdge)

testClarifyAppendsRationale :: Test
testClarifyAppendsRationale = TestCase $ do
  let edge = sampleEdge { seRationale = Just "prior rationale" }
      network = sampleNetwork { snEdges = Map.singleton ("a", "b") edge }
      detail = "additional context"
      result = applyFeedback network [edge] (Clarify detail)
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "original edge must remain in network"
    Just e  -> assertEqual "rationale appended"
             (Just "prior rationale; additional context") (seRationale e)
