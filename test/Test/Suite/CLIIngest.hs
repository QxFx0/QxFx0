{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.CLIIngest
  ( cliIngestTests
  ) where

import Control.Exception (SomeException, try)
import qualified Data.Text as T
import Test.HUnit

import QxFx0.CLI.Ingest
  ( IngestOptions(..)
  , IngestSummary(..)
  , defaultIngestOptions
  , formatIngestSummary
  , parseIngestArgs
  , runIngest
  )

relationsPath :: FilePath
relationsPath = "resources/knowledge/relations.jsonl"

ontologyPath :: FilePath
ontologyPath = "resources/knowledge/ontology.jsonl"

cliIngestTests :: [Test]
cliIngestTests =
  [ TestLabel "parseIngestArgs accepts empty defaults" testParseDefaults
  , TestLabel "parseIngestArgs reads --relations and --ontology" testParseFlags
  , TestLabel "parseIngestArgs rejects unknown flags" testParseUnknown
  , TestLabel "parseIngestArgs requires a value for --relations" testParseMissingValue
  , TestLabel "runIngest on canonical files succeeds" testRunIngestCanonical
  , TestLabel "runIngest summary reports >600 edges" testRunIngestEdges
  , TestLabel "runIngest summary reports a sample edge" testRunIngestSampleEdge
  , TestLabel "runIngest returns Left for a missing relations file" testRunIngestMissing
  ]

testParseDefaults :: Test
testParseDefaults = TestCase $
  assertEqual "empty args should parse to defaults"
    (Just defaultIngestOptions)
    (parseIngestArgs [])

testParseFlags :: Test
testParseFlags = TestCase $ do
  let expected = Just defaultIngestOptions
        { ioRelations = "/tmp/relations.jsonl"
        , ioOntology  = "/tmp/ontology.jsonl"
        }
  assertEqual "flag args should parse"
    expected
    (parseIngestArgs ["--relations", "/tmp/relations.jsonl"
                     ,"--ontology", "/tmp/ontology.jsonl"])

testParseUnknown :: Test
testParseUnknown = TestCase $
  assertBool "unknown flag should make parsing fail"
    (parseIngestArgs ["--relations", relationsPath, "--extra"] == Nothing)

testParseMissingValue :: Test
testParseMissingValue = TestCase $
  assertBool "dangling --relations should make parsing fail"
    (parseIngestArgs ["--relations"] == Nothing)

testRunIngestCanonical :: Test
testRunIngestCanonical = TestCase $ do
  result <- runIngest defaultIngestOptions
  case result of
    Left err -> assertFailure ("canonical ingest must succeed: " ++ T.unpack err)
    Right _  -> pure ()

testRunIngestEdges :: Test
testRunIngestEdges = TestCase $ do
  Right summary <- runIngest defaultIngestOptions
  assertBool "relations count must be >600"
    (isRelationsCount summary > 600)
  assertBool "network edge count must be >600"
    (isNetworkEdgeCount summary > 600)
  assertBool "network node count must be >300"
    (isNetworkNodeCount summary > 300)

testRunIngestSampleEdge :: Test
testRunIngestSampleEdge = TestCase $ do
  Right summary <- runIngest defaultIngestOptions
  case isSampleEdge summary of
    Nothing -> assertFailure "sample edge must be present"
    Just (_fromN, _toN, rt, _prov) ->
      assertBool "sample edge relation type must be rendered"
        (not (T.null rt))

testRunIngestMissing :: Test
testRunIngestMissing = TestCase $ do
  result <- try (runIngest defaultIngestOptions { ioRelations = "does-not-exist-cli-ingest.jsonl" })
    :: IO (Either SomeException (Either T.Text IngestSummary))
  case result of
    Left _ -> assertFailure "runIngest must not throw"
    Right outcome ->
      assertBool "missing relations file must yield Left"
        (case outcome of Left _ -> True; Right _ -> False)
