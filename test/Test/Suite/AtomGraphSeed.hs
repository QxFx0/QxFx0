{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.AtomGraphSeed
Description : Tests for the P0.1 atom-graph seed default.
-}
module Test.Suite.AtomGraphSeed
  ( atomGraphSeedTests
  ) where

import Control.Exception (bracket_)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.HUnit

import QxFx0.Semantic.Content.AtomStore (AtomGraph(..), seedGraph)
import QxFx0.Semantic.Network (contentDensityGate)
import QxFx0.Semantic.Network.Ingest (buildNetworkFromAtomGraph)
import QxFx0.Semantic.Network.Seed (seedFromCorpus)
import QxFx0.Semantic.Network.Seed.Select (selectSeedNetwork, selectSeedNetworkFor, readUseAtomGraphSeed)
import QxFx0.Semantic.Network.Types (SemanticNetwork(..))

-- | The atom-graph seed built from the curated seed graph must pass the
-- content-density gate and be large enough to drive semantic space
-- construction.
testAtomGraphSeedPassesDensityGate :: Test
testAtomGraphSeedPassesDensityGate = TestCase $ do
  let network = buildNetworkFromAtomGraph seedGraph
      nodeCount = S.size (snNodes network)
      edgeCount = M.size (snEdges network)
  assertBool ("atom-graph seed must pass contentDensityGate (nodes=" ++ show nodeCount ++ ", edges=" ++ show edgeCount ++ ")")
    (contentDensityGate network)
  assertBool ("atom-graph seed must have >= 311 nodes, got " ++ show nodeCount)
    (nodeCount >= 311)
  assertBool ("atom-graph seed must have >= 633 edges, got " ++ show edgeCount)
    (edgeCount >= 633)

-- | 'selectSeedNetwork' (the default production selector) returns the
-- curated atom-graph seed with at least 311 nodes and 633 edges and passes
-- the content-density gate.
testSelectSeedNetworkSize :: Test
testSelectSeedNetworkSize = TestCase $ do
  let network = selectSeedNetwork (M.empty :: M.Map T.Text T.Text)
      nodeCount = S.size (snNodes network)
      edgeCount = M.size (snEdges network)
  assertBool ("selectSeedNetwork must have >= 311 nodes, got " ++ show nodeCount)
    (nodeCount >= 311)
  assertBool ("selectSeedNetwork must have >= 633 edges, got " ++ show edgeCount)
    (edgeCount >= 633)
  assertBool "selectSeedNetwork must pass contentDensityGate"
    (contentDensityGate network)

-- | 'readUseAtomGraphSeed' returns 'False' when the environment variable is
-- set to @"0"@.
testReadUseAtomGraphSeedDisabled :: Test
testReadUseAtomGraphSeedDisabled = TestCase $ do
  old <- lookupEnv "QXFX0_USE_ATOM_GRAPH_SEED"
  bracket_ (setEnv "QXFX0_USE_ATOM_GRAPH_SEED" "0")
           (restore old)
           (do useAtom <- readUseAtomGraphSeed
               assertBool "readUseAtomGraphSeed should return False for \"0\""
                 (not useAtom))
  where
    restore Nothing  = unsetEnv "QXFX0_USE_ATOM_GRAPH_SEED"
    restore (Just v) = setEnv "QXFX0_USE_ATOM_GRAPH_SEED" v

-- | If the atom graph is too sparse to pass the content-density gate,
-- 'selectSeedNetworkFor' must fall back to the corpus-derived seed.
testFallbackToCorpusSeed :: Test
testFallbackToCorpusSeed = TestCase $ do
  let sparseGraph = AtomGraph [] M.empty "empty"
      network = selectSeedNetworkFor sparseGraph M.empty
      nodeCount = S.size (snNodes network)
      edgeCount = M.size (snEdges network)
      corpusNetwork = seedFromCorpus M.empty
  assertBool "sparse atom graph must fail contentDensityGate"
    (not (contentDensityGate (buildNetworkFromAtomGraph sparseGraph)))
  assertBool ("fallback corpus seed must have >= 15 nodes, got " ++ show nodeCount)
    (nodeCount >= 15)
  assertBool ("fallback corpus seed must have >= 50 edges, got " ++ show edgeCount)
    (edgeCount >= 50)
  assertEqual "fallback network should be the corpus seed"
    corpusNetwork network

atomGraphSeedTests :: [Test]
atomGraphSeedTests =
  [ TestLabel "atom-graph seed passes content density gate" testAtomGraphSeedPassesDensityGate
  , TestLabel "selectSeedNetwork has expected size" testSelectSeedNetworkSize
  , TestLabel "readUseAtomGraphSeed returns False for 0" testReadUseAtomGraphSeedDisabled
  , TestLabel "fallback to corpus seed when atom graph is sparse" testFallbackToCorpusSeed
  ]
