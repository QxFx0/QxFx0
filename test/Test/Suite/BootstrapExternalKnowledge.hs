{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.BootstrapExternalKnowledge
Description : Tests for ADR-0052 Phase II external knowledge loading
              during bootstrap.
-}
module Test.Suite.BootstrapExternalKnowledge
  ( bootstrapExternalKnowledgeTests
  ) where

import Control.Exception (bracket_)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import System.Directory (doesFileExist)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.HUnit (Test (..), (@?=), assertBool)

import QxFx0.Runtime.Session
  ( bootstrapSemanticNetwork
  , minimalMorphologyFallback
  , readExternalKnowledgeEnabled
  , resolveKnowledgePath
  , useExternalKnowledge
  )
import QxFx0.Semantic.Network.Substrate (loadBrainKB, resolveBrainKBPath)
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance (..)
  , SemanticEdge (..)
  , SemanticNetwork (..)
  )

-- | Seed topic that is also present in the external ontology.
seedNode :: T.Text
seedNode = "свобода"

-- | External-only node from the relations corpus ("свобода" -> "самоопределение").
-- This word is deliberately absent from the seeded definition corpus, the
-- self-play corpus and the atom-graph seed, so the disabled path cannot
-- introduce it.
externalNode :: T.Text
externalNode = "самоопределение"

-- | The default compile-time flag must keep the feature off.
testUseExternalKnowledgeDefaultOff :: Test
testUseExternalKnowledgeDefaultOff = TestCase $ do
  useExternalKnowledge @?= False

-- | The environment-based reader must default to 'False' when the
-- variable is unset.
testReadExternalKnowledgeEnabledDefaultsOff :: Test
testReadExternalKnowledgeEnabledDefaultsOff = TestCase $ do
  enabled <- readExternalKnowledgeEnabled
  enabled @?= False

-- | resolveKnowledgePath returns an existing path for bundled knowledge
-- files, falling back to the original path when nothing else works.
testResolveKnowledgePathFindsRelations :: Test
testResolveKnowledgePathFindsRelations = TestCase $ do
  let relPath = "resources/knowledge/relations.jsonl"
  resolved <- resolveKnowledgePath relPath
  exists <- doesFileExist resolved
  assertBool "resolved relations path should exist" exists

-- | Temporarily set @QXFX0_USE_ATOM_GRAPH_SEED@ to the supplied value
-- for the duration of an 'IO' action, restoring the previous value
-- afterwards.
withAtomGraphSeed :: String -> IO a -> IO a
withAtomGraphSeed value action = do
  old <- lookupEnv "QXFX0_USE_ATOM_GRAPH_SEED"
  bracket_ (setEnv "QXFX0_USE_ATOM_GRAPH_SEED" value)
           (restore old)
           action
  where
    restore Nothing  = unsetEnv "QXFX0_USE_ATOM_GRAPH_SEED"
    restore (Just v) = setEnv "QXFX0_USE_ATOM_GRAPH_SEED" v

-- | With external knowledge disabled, the external-only node is not
-- introduced into the semantic network.
--
-- We pin @QXFX0_USE_ATOM_GRAPH_SEED@ to @"false"@ for this test because
-- the default was changed to use the atom-graph seed, which happens to
-- contain the external-only node @"выбор"@. Without the pin the disabled
-- code path would still see that node and the assertion would fail.
--
-- We also disable self-play relations, because P2.1 turned them on by
-- default and the bundled self-play corpus also references @"выбор"@.
testDisabledLeavesNetworkUnchanged :: Test
testDisabledLeavesNetworkUnchanged = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- withAtomGraphSeed "false" . withoutSelfPlay $
    bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries False
  assertBool "external-only node should not appear when disabled"
    (not (S.member externalNode (snNodes network)))

-- | Temporarily disable the self-play relation feature for an 'IO' action.
withoutSelfPlay :: IO a -> IO a
withoutSelfPlay action = do
  old <- lookupEnv "QXFX0_USE_SELFPLAY"
  bracket_ (setEnv "QXFX0_USE_SELFPLAY" "0")
           (restore old)
           action
  where
    restore Nothing  = unsetEnv "QXFX0_USE_SELFPLAY"
    restore (Just v) = setEnv "QXFX0_USE_SELFPLAY" v

-- | With external knowledge enabled, the final network contains both
-- seed nodes and external-only nodes.
testEnabledMergesExternalNodes :: Test
testEnabledMergesExternalNodes = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries True
  assertBool "seed node should be present"
    (S.member seedNode (snNodes network))
  assertBool "external-only node should be present"
    (S.member externalNode (snNodes network))

-- | The "свобода" -> "самоопределение" edge imported from the external corpus
-- is present and carries 'ProvenanceIngested'.
testExternalEdgeHasIngestedProvenance :: Test
testExternalEdgeHasIngestedProvenance = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries True
  case M.lookup (seedNode, externalNode) (snEdges network) of
    Nothing ->
      assertBool "expected edge свобода -> выбор to be present" False
    Just edge ->
      seProvenance edge @?= ProvenanceIngested

bootstrapExternalKnowledgeTests :: [Test]
bootstrapExternalKnowledgeTests =
  [ TestLabel "useExternalKnowledge defaults to False" testUseExternalKnowledgeDefaultOff
  , TestLabel "readExternalKnowledgeEnabled defaults to False" testReadExternalKnowledgeEnabledDefaultsOff
  , TestLabel "resolveKnowledgePath finds bundled relations" testResolveKnowledgePathFindsRelations
  , TestLabel "disabled external knowledge leaves network unchanged" testDisabledLeavesNetworkUnchanged
  , TestLabel "enabled external knowledge merges nodes" testEnabledMergesExternalNodes
  , TestLabel "external edge has ProvenanceIngested" testExternalEdgeHasIngestedProvenance
  ]
