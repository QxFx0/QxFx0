{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.RuntimeLLMFeedback
  ( runtimeLLMFeedbackTests
  ) where

import qualified Data.Map.Strict as M
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime(..))
import Test.HUnit

import QxFx0.Learning.RuntimeLLMFeedback
  ( RuntimeLLMFeedbackEvent(..)
  , RuntimeLLMOutcome(..)
  , applyRuntimeLLMFeedback
  , DecayConfig(..)
  , applyEdgeDecayAndRetire
  , defaultDecayConfig
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )

mkEdge :: EdgeProvenance -> Double -> Int -> SemanticEdge
mkEdge prov conf cooc = SemanticEdge
  { seFrom = "свобода"
  , seTo = "воля"
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
  , seNamespace = Just NamespaceSessionLocal
  , seLineage = Nothing
  }

mkNetwork :: SemanticEdge -> SemanticNetwork
mkNetwork edge = SemanticNetwork
  { snNodes = mempty
  , snEdges = M.singleton (seFrom edge, seTo edge) edge
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = mempty
  }

mkEvent :: RuntimeLLMOutcome -> RuntimeLLMFeedbackEvent
mkEvent outcome = RuntimeLLMFeedbackEvent
  { rlfeTopic = "свобода"
  , rlfeEdgeFrom = "свобода"
  , rlfeEdgeTo = "воля"
  , rlfeOutcome = outcome
  , rlfeTurnId = 1
  , rlfeTimestamp = UTCTime (fromGregorian 2026 7 11) 0
  }

lookupEdge :: SemanticNetwork -> Maybe SemanticEdge
lookupEdge = M.lookup ("свобода", "воля") . snEdges

testPositiveReinforces :: Test
testPositiveReinforces = TestLabel "positive feedback reinforces runtime edge" $ TestCase $ do
  let net = applyRuntimeLLMFeedback (mkEvent RloPositive) (mkNetwork (mkEdge ProvenanceRuntimeLLM 0.60 1))
  case lookupEdge net of
    Nothing -> assertFailure "edge missing"
    Just edge -> do
      assertEqual "confidence increased" 0.65 (seConfidence edge)
      assertEqual "co-occurrence increased" 2 (seCoOccurrence edge)
      assertEqual "still runtime provenance" ProvenanceRuntimeLLM (seProvenance edge)

testRepeatedPositivePromotes :: Test
testRepeatedPositivePromotes = TestLabel "repeated positive feedback promotes runtime edge" $ TestCase $ do
  let net = applyRuntimeLLMFeedback (mkEvent RloPositive) (mkNetwork (mkEdge ProvenanceRuntimeLLM 0.72 2))
  case lookupEdge net of
    Nothing -> assertFailure "edge missing"
    Just edge -> do
      assertEqual "confidence increased to threshold" 0.77 (seConfidence edge)
      assertEqual "co-occurrence reaches threshold" 3 (seCoOccurrence edge)
      assertEqual "promoted to dialogue feedback" ProvenanceDialogueFeedback (seProvenance edge)

testNegativeDecays :: Test
testNegativeDecays = TestLabel "negative feedback decays runtime edge" $ TestCase $ do
  let net = applyRuntimeLLMFeedback (mkEvent RloNegative) (mkNetwork (mkEdge ProvenanceRuntimeLLM 0.60 2))
  case lookupEdge net of
    Nothing -> assertFailure "edge missing"
    Just edge -> do
      assertEqual "confidence decayed" 0.50 (seConfidence edge)
      assertEqual "co-occurrence unchanged" 2 (seCoOccurrence edge)

testConflictQuarantinesByRemoval :: Test
testConflictQuarantinesByRemoval = TestLabel "conflict removes runtime edge for quarantine path" $ TestCase $ do
  let net = applyRuntimeLLMFeedback (mkEvent RloConflict) (mkNetwork (mkEdge ProvenanceRuntimeLLM 0.60 2))
  assertEqual "runtime edge removed" Nothing (lookupEdge net)

testAuthoritativeIsolation :: Test
testAuthoritativeIsolation = TestLabel "authoritative edge is not modified by runtime feedback" $ TestCase $ do
  let edge0 = mkEdge ProvenanceCurated 0.90 10
      net = applyRuntimeLLMFeedback (mkEvent RloPositive) (mkNetwork edge0)
  assertEqual "curated edge unchanged" (Just edge0) (lookupEdge net)

testDecaySkipsUsedTopic :: Test
testDecaySkipsUsedTopic = TestLabel "decay skips edges touching current topic" $ TestCase $ do
  let edge = (mkEdge ProvenanceRuntimeLLM 0.60 1) { seFrom = "свобода", seTo = "воля" }
      net = applyEdgeDecayAndRetire defaultDecayConfig "свобода" (mkNetwork edge)
  case lookupEdge net of
    Nothing -> assertFailure "edge missing"
    Just e -> assertEqual "confidence unchanged" 0.60 (seConfidence e)

testDecayReducesUnused :: Test
testDecayReducesUnused = TestLabel "decay reduces confidence of unused runtime edges" $ TestCase $ do
  let edge = (mkEdge ProvenanceRuntimeLLM 0.60 1) { seFrom = "свобода", seTo = "воля" }
      net = applyEdgeDecayAndRetire defaultDecayConfig "ответственность" (mkNetwork edge)
  case lookupEdge net of
    Nothing -> assertFailure "edge missing"
    Just e -> assertEqual "confidence decayed by 5%" 0.57 (seConfidence e)

testRetireBelowThreshold :: Test
testRetireBelowThreshold = TestLabel "retire removes runtime edge below threshold" $ TestCase $ do
  let edge = (mkEdge ProvenanceRuntimeLLM 0.31 1) { seFrom = "свобода", seTo = "воля" }
      net = applyEdgeDecayAndRetire defaultDecayConfig "ответственность" (mkNetwork edge)
  assertEqual "edge retired" Nothing (lookupEdge net)

testAuthoritativeNotDecayed :: Test
testAuthoritativeNotDecayed = TestLabel "authoritative edges are not decayed" $ TestCase $ do
  let edge = (mkEdge ProvenanceHumanCorrection 1.0 1) { seFrom = "свобода", seTo = "воля" }
      net = applyEdgeDecayAndRetire defaultDecayConfig "ответственность" (mkNetwork edge)
  case lookupEdge net of
    Nothing -> assertFailure "edge missing"
    Just e -> assertEqual "confidence unchanged" 1.0 (seConfidence e)

runtimeLLMFeedbackTests :: [Test]
runtimeLLMFeedbackTests =
  [ testPositiveReinforces
  , testRepeatedPositivePromotes
  , testNegativeDecays
  , testConflictQuarantinesByRemoval
  , testAuthoritativeIsolation
  , testDecaySkipsUsedTopic
  , testDecayReducesUnused
  , testRetireBelowThreshold
  , testAuthoritativeNotDecayed
  ]
