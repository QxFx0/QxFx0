{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.Ontology
  ( ontologyTests
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import Test.HUnit

import QxFx0.Semantic.Content (ConceptCategory(..))
import QxFx0.Semantic.Ontology

ontologyPath :: FilePath
ontologyPath = "resources/knowledge/ontology.jsonl"

ontologyTests :: [Test]
ontologyTests =
  [ TestLabel "Ontology loads real ontology file" testLoadOntology
  , TestLabel "Ontology has 5 expected roots" testRoots
  , TestLabel "Ontology known topic has expected parent and category" testKnownTopic
  , TestLabel "Ontology hierarchy helpers work" testHierarchyHelpers
  ]

testLoadOntology :: Test
testLoadOntology = TestCase $ do
  ot <- loadOntology ontologyPath
  assertEqual "ontology must contain 335 unique nodes" 335 (Map.size (otNodes ot))
  assertEqual "ontology must have 5 roots" 5 (Set.size (otRoots ot))

testRoots :: Test
testRoots = TestCase $ do
  ot <- loadOntology ontologyPath
  assertEqual "roots must match the 5 expected root concepts"
    (Set.fromList ["философия", "психология", "социум", "физическое", "общее"])
    (otRoots ot)

testKnownTopic :: Test
testKnownTopic = TestCase $ do
  ot <- loadOntology ontologyPath
  let node = lookupOntologyNode ot "свобода"
  assertEqual "known topic must have expected category"
    (Just CategoryPhilosophical) (fmap onCategory node)
  assertEqual "known topic must have expected parent"
    (Just "аксиология" :: Maybe Text) (node >>= onParent)
  assertEqual "known topic category lookup must match"
    (Just CategoryPhilosophical) (lookupCategory ot "свобода")
  assertEqual "known topic parent lookup must match"
    (Just "аксиология") (lookupParent ot "свобода")

testHierarchyHelpers :: Test
testHierarchyHelpers = TestCase $ do
  ot <- loadOntology ontologyPath
  assertEqual "siblings of свобода must be the other child of аксиология"
    ["произвол"] (lookupSiblings ot "свобода")
  assertEqual "root nodes have no siblings"
    [] (lookupSiblings ot "философия")
  assertEqual "children of философия must match"
    ["аксиология", "онтология", "эпистемология", "эстетика"]
    (lookupChildren ot "философия")
  assertEqual "unknown node has no children"
    [] (lookupChildren ot "неизвестно")
