{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.NetworkIngest
  ( networkIngestTests
  ) where

import Control.Exception (SomeException, try)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Directory (removeFile)
import System.IO (hClose, openTempFile)
import Test.HUnit

import QxFx0.Semantic.Content.AtomStore
  ( AtomGraph(..)
  , RelationSource(..)
  , RelationType(..)
  , agRelations
  , relCounter
  , relRationale
  , relSource
  , relSynthesis
  , relType
  )
import QxFx0.Semantic.Network.Ingest
import QxFx0.Semantic.Network.Types (SemanticNetwork(..), snEdges, snNodes)

relationsPath :: FilePath
relationsPath = "resources/knowledge/relations.jsonl"

ontologyPath :: FilePath
ontologyPath = "resources/knowledge/ontology.jsonl"

writeRelationFile :: String -> IO FilePath
writeRelationFile contents = do
  (path, h) <- openTempFile "." "network-ingest-*.jsonl"
  hClose h
  writeFile path contents
  pure path

networkIngestTests :: [Test]
networkIngestTests =
  [ TestLabel "loadRelations returns >600 entries" testLoadRelations
  , TestLabel "loadRelations parses expected first relation fields" testLoadRelationsFields
  , TestLabel "loadRelationGraph returns >600 edges" testLoadRelationGraph
  , TestLabel "loadRelationGraph preserves relation types" testLoadRelationGraphTypes
  , TestLabel "loadRelations skips blank lines" testLoadRelationsSkipsBlankLines
  , TestLabel "loadRelations rejects unknown relation type" testLoadRelationsRejectsUnknownType
  , TestLabel "ingestExternalKnowledge returns Just with expected atom count" testIngestExternalKnowledge
  , TestLabel "ingestExternalKnowledge produces explicit edges" testIngestExternalKnowledgeEdges
  , TestLabel "ingestExternalKnowledge returns Nothing on missing files" testIngestExternalKnowledgeMissingFiles
  , TestLabel "ingestExternalKnowledge returns Nothing on invalid ontology" testIngestExternalKnowledgeInvalidOntology
  , TestLabel "loadRelationGraph marks relations as Curated" testLoadRelationGraphSource
  , TestLabel "loadRelationGraph preserves optional fields" testLoadRelationGraphOptionalFields
  ]

testLoadRelations :: Test
testLoadRelations = TestCase $ do
  rels <- loadRelations relationsPath
  assertBool "relations must contain more than 600 entries" (length rels > 600)
  assertBool "relations must contain at most 700 entries" (length rels <= 700)

testLoadRelationsFields :: Test
testLoadRelationsFields = TestCase $ do
  rels <- loadRelations relationsPath
  let first = head rels
  assertEqual "first relation source atom" "свобода" (lrFrom first)
  assertEqual "first relation target atom" "выбор" (lrTo first)
  assertEqual "first relation type" RelPresupposes (lrType first)
  assertEqual "first relation verb" (Just "предполагает") (lrVerb first)
  assertEqual "first relation author" "curator" (lrAuthor first)
  assertEqual "first relation version" 1 (lrVersion first)
  assertBool "first relation confidence is positive" (lrConfidence first > 0)

testLoadRelationGraph :: Test
testLoadRelationGraph = TestCase $ do
  graph <- loadRelationGraph relationsPath
  assertBool "relation graph must contain more than 600 edges"
    (length (agRelations graph) > 600)
  assertBool "relation graph index must cover source atoms"
    (not (Map.null (agByFrom graph)))
  assertEqual "relation graph version must be ingest-v1"
    "ingest-v1" (agVersion graph)

testLoadRelationGraphTypes :: Test
testLoadRelationGraphTypes = TestCase $ do
  graph <- loadRelationGraph relationsPath
  let types = Set.fromList (map relType (agRelations graph))
  assertBool "graph must contain RelPresupposes edges"
    (RelPresupposes `Set.member` types)
  assertBool "graph must contain RelRequires edges"
    (RelRequires `Set.member` types)
  assertBool "graph must contain RelIsA edges"
    (RelIsA `Set.member` types)

testLoadRelationsSkipsBlankLines :: Test
testLoadRelationsSkipsBlankLines = TestCase $ do
  tmp <- writeRelationFile
    "\n{\"from\":\"a\",\"to\":\"b\",\"type\":\"RelIsA\",\"confidence\":1.0,\"author\":\"test\",\"version\":1}\n\n"
  rels <- loadRelations tmp
  removeFile tmp
  assertEqual "blank lines must be skipped" 1 (length rels)
  assertEqual "loaded relation source" "a" (lrFrom (head rels))
  assertEqual "loaded relation target" "b" (lrTo (head rels))

testLoadRelationsRejectsUnknownType :: Test
testLoadRelationsRejectsUnknownType = TestCase $ do
  tmp <- writeRelationFile
    "{\"from\":\"a\",\"to\":\"b\",\"type\":\"RelDoesNotExist\",\"confidence\":1.0,\"author\":\"test\",\"version\":1}\n"
  result <- try (loadRelations tmp) :: IO (Either SomeException [LoadedRelation])
  removeFile tmp
  case result of
    Left _  -> pure ()
    Right _ -> assertFailure "unknown relation type must cause a parse failure"

testIngestExternalKnowledge :: Test
testIngestExternalKnowledge = TestCase $ do
  mNetwork <- ingestExternalKnowledge ontologyPath relationsPath
  case mNetwork of
    Nothing -> assertFailure "ingestExternalKnowledge must return Just a network"
    Just sn -> do
      assertEqual "network must contain 335 atoms from ontology and relations"
        335 (Set.size (snNodes sn))
      assertBool "network must contain the atom свобода"
        (Set.member "свобода" (snNodes sn))
      assertBool "network must contain the atom бытие"
        (Set.member "бытие" (snNodes sn))
      assertBool "network must contain the ontology root философия"
        (Set.member "философия" (snNodes sn))

testIngestExternalKnowledgeEdges :: Test
testIngestExternalKnowledgeEdges = TestCase $ do
  mNetwork <- ingestExternalKnowledge ontologyPath relationsPath
  case mNetwork of
    Nothing -> assertFailure "network must load"
    Just sn -> do
      assertBool "network must have explicit edges"
        (not (Map.null (snEdges sn)))
      assertBool "network edge count must be >600"
        (Map.size (snEdges sn) > 600)
      assertBool "network must contain the свобода->выбор edge"
        (Map.member ("свобода", "выбор") (snEdges sn))

testIngestExternalKnowledgeMissingFiles :: Test
testIngestExternalKnowledgeMissingFiles = TestCase $ do
  result <- ingestExternalKnowledge "does-not-exist.jsonl" relationsPath
  assertEqual "missing ontology must yield Nothing" Nothing result
  result2 <- ingestExternalKnowledge ontologyPath "does-not-exist.jsonl"
  assertEqual "missing relations must yield Nothing" Nothing result2

testIngestExternalKnowledgeInvalidOntology :: Test
testIngestExternalKnowledgeInvalidOntology = TestCase $ do
  tmp <- writeRelationFile "{\"name\":\"x\",\"category\":\"Bad\",\"parent\":\"\",\"depth\":0}\n"
  result <- ingestExternalKnowledge tmp relationsPath
  removeFile tmp
  assertEqual "invalid ontology category must yield Nothing" Nothing result

testLoadRelationGraphSource :: Test
testLoadRelationGraphSource = TestCase $ do
  graph <- loadRelationGraph relationsPath
  let sources = map relSource (agRelations graph)
  assertBool "relation graph must contain at least one relation" (not (null sources))
  assertBool "all loaded relations must be marked Curated"
    (all (== Curated) sources)

testLoadRelationGraphOptionalFields :: Test
testLoadRelationGraphOptionalFields = TestCase $ do
  graph <- loadRelationGraph relationsPath
  let withRationale = filter (\r -> relRationale r /= Nothing) (agRelations graph)
      withCounter   = filter (\r -> relCounter r /= Nothing) (agRelations graph)
      withSynthesis = filter (\r -> relSynthesis r /= Nothing) (agRelations graph)
  assertBool "some relations must have a rationale" (not (null withRationale))
  assertBool "some relations must have a counter" (not (null withCounter))
  assertBool "some relations must have a synthesis" (not (null withSynthesis))
