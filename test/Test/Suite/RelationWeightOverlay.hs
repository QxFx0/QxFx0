{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.RelationWeightOverlay
  ( relationWeightOverlayTests
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Sequence as Seq
import qualified Data.Set as S
import Data.Text (Text)
import System.Directory (removeFile)
import System.IO (writeFile)
import Test.HUnit

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Seed (overlayConfidence)
import QxFx0.Semantic.Network.Seed.Select (loadRelationWeightOverlay)
import QxFx0.Semantic.Network.Types

mkEdge :: Text -> Text -> Double -> Double -> SemanticEdge
mkEdge f t w conf = SemanticEdge
  { seFrom         = f
  , seTo           = t
  , seWeight       = w
  , seCoOccurrence = 1
  , seSource       = ExplicitEdge
  , seRelationType = Just RelRequires
  , seVerb         = Nothing
  , seRationale    = Nothing
  , seCounter      = Nothing
  , seSynthesis    = Nothing
  , seConfidence   = conf
  , seProvenance   = ProvenanceCurated
  }

mkNetwork :: [(Text, Text, Double, Double)] -> SemanticNetwork
mkNetwork pairs = SemanticNetwork
  { snNodes = S.fromList (concat [ [f, t] | (f, t, _, _) <- pairs ])
  , snEdges = Map.fromList [ ((f, t), mkEdge f t w c) | (f, t, w, c) <- pairs ]
  , snActivation = Map.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = Seq.empty
  }

relationWeightOverlayTests :: [Test]
relationWeightOverlayTests =
  [ TestLabel "overlay blends fresh and restored (restored dominant)" testBlendDominatesRestored
  , TestLabel "overlay caps at 0.95" testCapAt0_95
  , TestLabel "fresh-only edges remain unchanged" testFreshOnlyEdgesUnchanged
  , TestLabel "loadRelationWeightOverlay reads JSONL weights" testLoadRelationWeightOverlay
  , TestLabel "loadRelationWeightOverlay skips malformed JSONL lines" testMalformedLineIsSkipped
  , TestLabel "loadRelationWeightOverlay missing file is no-op" testMissingFileNoOp
  ]

testBlendDominatesRestored :: Test
testBlendDominatesRestored = TestCase $ do
  let fresh    = mkNetwork [("a", "b", 0.5, 0.5)]
      restored = mkNetwork [("a", "b", 0.5, 0.8)]
      result   = overlayConfidence fresh restored
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "edge should remain"
    Just e  -> do
      assertEqual "blended confidence" 0.71 (round2 (seConfidence e))
      assertEqual "fresh edge weight preserved" 0.5 (seWeight e)
  where
    round2 x = fromIntegral (round (x * 100 :: Double)) / 100.0

testCapAt0_95 :: Test
testCapAt0_95 = TestCase $ do
  let fresh    = mkNetwork [("a", "b", 0.5, 0.9)]
      restored = mkNetwork [("a", "b", 0.5, 1.0)]
      result   = overlayConfidence fresh restored
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "edge should remain"
    Just e  -> assertEqual "confidence capped at 0.95" 0.95 (seConfidence e)

testFreshOnlyEdgesUnchanged :: Test
testFreshOnlyEdgesUnchanged = TestCase $ do
  let fresh    = mkNetwork [("a", "b", 0.5, 0.5), ("b", "c", 0.6, 0.3)]
      restored = mkNetwork [("a", "b", 0.5, 0.9)]
      result   = overlayConfidence fresh restored
  case Map.lookup ("b", "c") (snEdges result) of
    Nothing -> assertFailure "fresh-only edge should remain"
    Just e  -> assertEqual "fresh-only edge unchanged" 0.3 (seConfidence e)

testLoadRelationWeightOverlay :: Test
testLoadRelationWeightOverlay = TestCase $ do
  let fresh = mkNetwork [("a", "b", 0.5, 0.5)]
      line  = "{\"seFrom\":\"a\",\"seTo\":\"b\",\"seWeight\":0.5,\"seCoOccurrence\":1,\"seSource\":\"ExplicitEdge\",\"relation_type\":\"RelRequires\",\"confidence\":0.9,\"provenance\":\"ProvenanceCurated\"}"
      path  = "/tmp/qxfx0_relation_weight_overlay_test.jsonl"
  writeFile path (line <> "\n")
  result <- loadRelationWeightOverlay path fresh
  removeFile path
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "edge should remain"
    Just e  -> assertEqual "JSONL weight overlay applied" 0.78 (round2 (seConfidence e))
  where
    round2 x = fromIntegral (round (x * 100 :: Double)) / 100.0

testMalformedLineIsSkipped :: Test
testMalformedLineIsSkipped = TestCase $ do
  let fresh = mkNetwork [("a", "b", 0.5, 0.5)]
      validLine = "{\"seFrom\":\"a\",\"seTo\":\"b\",\"seWeight\":0.5,\"seCoOccurrence\":1,\"seSource\":\"ExplicitEdge\",\"relation_type\":\"RelRequires\",\"confidence\":0.9,\"provenance\":\"ProvenanceCurated\"}"
      path = "/tmp/qxfx0_relation_weight_overlay_malformed_test.jsonl"
  writeFile path ("not-json\n" <> validLine <> "\n")
  result <- loadRelationWeightOverlay path fresh
  removeFile path
  case Map.lookup ("a", "b") (snEdges result) of
    Nothing -> assertFailure "valid edge should still be applied"
    Just edge -> assertEqual "valid edge survives malformed predecessor" 0.78 (round2 (seConfidence edge))
  where
    round2 x = fromIntegral (round (x * 100 :: Double)) / 100.0

testMissingFileNoOp :: Test
testMissingFileNoOp = TestCase $ do
  let fresh = mkNetwork [("a", "b", 0.5, 0.5)]
  result <- loadRelationWeightOverlay "does-not-exist-overlay.jsonl" fresh
  assertEqual "network unchanged when overlay file missing" fresh result
