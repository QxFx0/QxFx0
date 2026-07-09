{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.VariantC
Description : Tests for Variant C atom-graph seeding and relation-type
              weight calibration.
-}
module Test.Suite.VariantC
  ( variantCTests
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Runtime.Session
  ( bootstrapSemanticNetwork
  , buildNetworkFromAtomGraph
  , minimalMorphologyFallback
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..), seedGraph)
import QxFx0.Semantic.Network.Seed (seedFromCorpus)
import QxFx0.Semantic.Network.Substrate (loadBrainKB, resolveBrainKBPath)
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , calibrateRelationTypeWeight
  , sweepRelationTypeWeights
  )

-- | The definition-corpus seed must never carry the 'ProvenanceCurated'
-- provenance that belongs to the atom-graph seed.
testCorpusSeedHasNoCuratedEdges :: Test
testCorpusSeedHasNoCuratedEdges = TestCase $ do
  let network = seedFromCorpus M.empty
      curatedEdges = filter ((== ProvenanceCurated) . seProvenance)
                            (M.elems (snEdges network))
  assertBool "corpus seed should not contain ProvenanceCurated edges"
    (null curatedEdges)

-- | Bootstrapping (now defaulting to the atom-graph seed) must produce a
-- network that contains curated provenance edges from the atom graph.
testBootstrapAtomGraphSeedCuratedEdges :: Test
testBootstrapAtomGraphSeedCuratedEdges = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries False
  let curatedEdges = filter ((== ProvenanceCurated) . seProvenance)
                            (M.elems (snEdges network))
  assertBool "atom-graph seed must add ProvenanceCurated edges"
    (not (null curatedEdges))
  assertBool "atom-graph seed must add nodes"
    (not (S.null (snNodes network)))

-- | 'buildNetworkFromAtomGraph seedGraph' produces curated edges.
testBuildNetworkFromAtomGraphProducesCurated :: Test
testBuildNetworkFromAtomGraphProducesCurated = TestCase $ do
  let network = buildNetworkFromAtomGraph seedGraph
      curatedEdges = filter ((== ProvenanceCurated) . seProvenance)
                            (M.elems (snEdges network))
  assertBool "buildNetworkFromAtomGraph seedGraph must produce curated edges"
    (not (null curatedEdges))

-- | High-count relation types are calibrated to a higher weight than
-- low-count types.
testCalibrateBoostsHighCountReducesLowCount :: Test
testCalibrateBoostsHighCountReducesLowCount = TestCase $ do
  let stats = M.fromList
        [ (RelIsA, 100.0)
        , (RelRelatedTo, 1.0)
        ]
      highW = calibrateRelationTypeWeight stats RelIsA
      lowW  = calibrateRelationTypeWeight stats RelRelatedTo
  assertBool "high-count type must be >= 0.9" (highW >= 0.9)
  assertBool "low-count type must be <= 0.4" (lowW <= 0.4)
  assertBool "high-count weight must exceed low-count weight" (highW > lowW)

-- | Unknown relation types fall back to the default weight.
testCalibrateUnknownDefaults :: Test
testCalibrateUnknownDefaults = TestCase $ do
  let stats = M.singleton RelIsA 10.0
  calibrateRelationTypeWeight stats RelRequires @?= 0.5

-- | A uniform corpus yields the midpoint weight.
testCalibrateUniformCorpus :: Test
testCalibrateUniformCorpus = TestCase $ do
  let stats = M.fromList [(RelIsA, 5.0), (RelRequires, 5.0)]
  calibrateRelationTypeWeight stats RelIsA @?= 0.65
  calibrateRelationTypeWeight stats RelRequires @?= 0.65

-- | 'sweepRelationTypeWeights' maps counts into @[0.0, 1.0]@.
testSweepWeightsInRange :: Test
testSweepWeightsInRange = TestCase $ do
  let weights = sweepRelationTypeWeights
        [ (RelIsA, 100.0)
        , (RelRequires, 50.0)
        , (RelRelatedTo, 0.0)
        ]
  assertEqual "all types should be present" 3 (M.size weights)
  assertBool "all weights must be >= 0.0"
    (all (>= 0.0) (M.elems weights))
  assertBool "all weights must be <= 1.0"
    (all (<= 1.0) (M.elems weights))
  case (M.lookup RelIsA weights, M.lookup RelRelatedTo weights) of
    (Just high, Just low) -> do
      assertBool "highest count must map to 1.0" (high == 1.0)
      assertBool "lowest count must map to 0.0" (low == 0.0)
    _ -> assertFailure "expected RelIsA and RelRelatedTo in sweep output"

-- | 'sweepRelationTypeWeights' on uniform counts yields 0.5 for all
-- entries.
testSweepUniformCounts :: Test
testSweepUniformCounts = TestCase $ do
  let weights = sweepRelationTypeWeights
        [ (RelIsA, 7.0)
        , (RelRequires, 7.0)
        ]
  assertBool "uniform counts must map to 0.5"
    (all (== 0.5) (M.elems weights))

-- | 'sweepRelationTypeWeights' on an empty list yields an empty map.
testSweepEmpty :: Test
testSweepEmpty = TestCase $ do
  let weights = sweepRelationTypeWeights ([] :: [(RelationType, Double)])
  assertBool "empty input must yield empty map" (M.null weights)

variantCTests :: [Test]
variantCTests =
  [ TestLabel "corpus seed has no ProvenanceCurated edges" testCorpusSeedHasNoCuratedEdges
  , TestLabel "atom-graph seed produces ProvenanceCurated edges" testBootstrapAtomGraphSeedCuratedEdges
  , TestLabel "buildNetworkFromAtomGraph seedGraph produces curated edges" testBuildNetworkFromAtomGraphProducesCurated
  , TestLabel "calibrate boosts high count and reduces low count" testCalibrateBoostsHighCountReducesLowCount
  , TestLabel "calibrate unknown type defaults to 0.5" testCalibrateUnknownDefaults
  , TestLabel "calibrate uniform corpus yields midpoint" testCalibrateUniformCorpus
  , TestLabel "sweep weights are in [0.0, 1.0]" testSweepWeightsInRange
  , TestLabel "sweep uniform counts yield 0.5" testSweepUniformCounts
  , TestLabel "sweep empty input yields empty map" testSweepEmpty
  ]
