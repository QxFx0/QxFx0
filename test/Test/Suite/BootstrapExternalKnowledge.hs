{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.BootstrapExternalKnowledge
Description : Tests for ADR-0052 Phase II external knowledge loading
              during bootstrap.
-}
module Test.Suite.BootstrapExternalKnowledge
  ( bootstrapExternalKnowledgeTests
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import System.Directory (doesFileExist)
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

-- | External-only node from the relations corpus ("свобода" -> "выбор").
externalNode :: T.Text
externalNode = "выбор"

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

-- | With external knowledge disabled, the external-only node is not
-- introduced into the semantic network.
testDisabledLeavesNetworkUnchanged :: Test
testDisabledLeavesNetworkUnchanged = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries False False
  assertBool "external-only node should not appear when disabled"
    (not (S.member externalNode (snNodes network)))

-- | With external knowledge enabled, the final network contains both
-- seed nodes and external-only nodes.
testEnabledMergesExternalNodes :: Test
testEnabledMergesExternalNodes = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries False True
  assertBool "seed node should be present"
    (S.member seedNode (snNodes network))
  assertBool "external-only node should be present"
    (S.member externalNode (snNodes network))

-- | The "свобода" -> "выбор" edge imported from the external corpus is
-- present and carries 'ProvenanceIngested'.
testExternalEdgeHasIngestedProvenance :: Test
testExternalEdgeHasIngestedProvenance = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries False True
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
